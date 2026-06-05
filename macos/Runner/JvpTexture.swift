import Cocoa
import FlutterMacOS
import AVFoundation

class JvpTexture: NSObject, FlutterTexture {
    static var instances = [Int64: JvpTexture]()
    
    private var pixelBuffer: CVPixelBuffer?
    var id: Int64 = -1
    private let registry: FlutterTextureRegistry
    private var textureCache: CVMetalTextureCache?
    private let metalDevice: MTLDevice?
    private var sharedCvTexture: CVMetalTexture?
    private var sharedMtlTexture: MTLTexture?
    private var displayLink: CVDisplayLink?
    
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var videoOutput: AVPlayerItemVideoOutput?
    
    private var videoWidth: Int = 0
    private var videoHeight: Int = 0
    private var videoDuration: Double = 0.0
    private var videoFps: Double = 30.0
    private var isPlayingState: Bool = false
    
    init(registry: FlutterTextureRegistry) {
        self.registry = registry
        self.metalDevice = MTLCreateSystemDefaultDevice()
        super.init()
        if let device = metalDevice {
            CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        }
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        if let link = displayLink {
            let callback: CVDisplayLinkOutputCallback = { (displayLink, inNow, inOutputTime, flagsIn, flagsOut, displayLinkContext) -> CVReturn in
                let mySelf = Unmanaged<JvpTexture>.fromOpaque(displayLinkContext!).takeUnretainedValue()
                RunLoop.main.perform(inModes: [.common]) {
                    mySelf.onFrameAvailable()
                }
                return kCVReturnSuccess
            }
            CVDisplayLinkSetOutputCallback(link, callback, Unmanaged.passUnretained(self).toOpaque())
            CVDisplayLinkStart(link)
        }
    }
    
    deinit {
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
        if id >= 0 {
            registry.unregisterTexture(id)
            JvpTexture.instances.removeValue(forKey: id)
        }
        cleanupPlayer()
        pixelBuffer = nil
        textureCache = nil
        sharedCvTexture = nil
        sharedMtlTexture = nil
    }
    
    private func cleanupPlayer() {
        player?.pause()
        if let output = videoOutput, let item = playerItem {
            item.remove(output)
        }
        videoOutput = nil
        playerItem = nil
        player = nil
    }
    
    func create(width: Int, height: Int) -> Int64 {
        let attrs = [
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ] as [String : Any] as CFDictionary
        
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs, &pb)
        
        if status == kCVReturnSuccess, let buffer = pb {
            self.pixelBuffer = buffer
            if let device = self.metalDevice {
                CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &self.textureCache)
            }
            if self.id < 0 {
                self.id = self.registry.register(self)
                JvpTexture.instances[self.id] = self
            }
            return self.id
        } else {
            NSLog("DEBUG Swift: CVPixelBufferCreate failed status=\(status) w=\(width) h=\(height)")
        }
        return -1
    }
    
    func openVideo(path: String) -> Bool {
        cleanupPlayer()
        
        let url: URL
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            guard let u = URL(string: path) else { return false }
            url = u
        } else {
            url = URL(fileURLWithPath: path)
        }
        
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let keys = ["duration", "tracks"]
        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        
        asset.loadValuesAsynchronously(forKeys: keys) {
            var error: NSError? = nil
            let statusDuration = asset.statusOfValue(forKey: "duration", error: &error)
            let statusTracks = asset.statusOfValue(forKey: "tracks", error: &error)
            success = (statusDuration == .loaded && statusTracks == .loaded)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5.0)
        if !success { return false }
        
        guard let videoTrack = asset.tracks(withMediaType: .video).first else { return false }
        
        let naturalSize = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
        self.videoWidth = Int(abs(naturalSize.width))
        self.videoHeight = Int(abs(naturalSize.height))
        self.videoDuration = CMTimeGetSeconds(asset.duration)
        self.videoFps = Double(videoTrack.nominalFrameRate)
        if self.videoFps <= 0.0 { self.videoFps = 30.0 }
        
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        
        self.videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: outputSettings)
        self.playerItem = AVPlayerItem(asset: asset)
        if let item = self.playerItem, let output = self.videoOutput {
            item.add(output)
        }
        
        self.player = AVPlayer(playerItem: self.playerItem)
        self.player?.actionAtItemEnd = .pause
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidPlayToEndTime),
            name: .AVPlayerItemDidPlayToEndTime,
            object: self.playerItem
        )
        
        return true
    }
    
    @objc private func playerItemDidPlayToEndTime(notification: Notification) {
        NotificationCenter.default.post(name: NSNotification.Name("JvpPlayerCompleted"), object: self)
    }
    
    func playVideo() {
        isPlayingState = true
        player?.play()
    }
    
    func pauseVideo() {
        isPlayingState = false
        player?.pause()
    }
    
    func seekVideo(toSeconds: Double) {
        guard let p = player else { return }
        let time = CMTime(seconds: toSeconds, preferredTimescale: 600)
        p.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    func setVideoVolume(vol: Float) {
        player?.volume = vol
    }
    
    func getMTLTexturePointer() -> UnsafeMutableRawPointer? {
        guard let pb = pixelBuffer, let cache = textureCache else { return nil }
        let width = CVPixelBufferGetWidth(pb)
        let height = CVPixelBufferGetHeight(pb)
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pb,
            nil,
            .bgra8Unorm, 
            width,
            height,
            0,
            &cvTexture
        )
        if status == kCVReturnSuccess, let cvTex = cvTexture, let mtlTex = CVMetalTextureGetTexture(cvTex) {
            self.sharedCvTexture = cvTex
            self.sharedMtlTexture = mtlTex
            return Unmanaged.passUnretained(mtlTex).toOpaque()
        }
        return nil
    }

    func getPixelBufferAddress() -> UInt? {
        guard let pb = pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        let addr = CVPixelBufferGetBaseAddress(pb)
        CVPixelBufferUnlockBaseAddress(pb, [])
        if let baseAddr = addr {
            return UInt(bitPattern: baseAddr)
        }
        return nil
    }
    
    func getPixelBufferBytesPerRow() -> Int {
        guard let pb = pixelBuffer else { return 0 }
        return CVPixelBufferGetBytesPerRow(pb)
    }

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        updateFrameBuffer()
        if let pb = pixelBuffer {
            return Unmanaged.passRetained(pb)
        }
        return nil
    }
    
    private func updateFrameBuffer() {
        guard let output = videoOutput, let item = playerItem else { return }
        let time = item.currentTime()
        if output.hasNewPixelBuffer(forItemTime: time) {
            var presentationItemTime = CMTime.zero
            if let pb = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: &presentationItemTime) {
                self.pixelBuffer = pb
            }
        }
    }
    
    func onFrameAvailable() {
        if id >= 0 {
            self.registry.textureFrameAvailable(id)
        }
    }
    
    func getMetadata() -> (width: Int, height: Int, duration: Double, fps: Double) {
        return (videoWidth, videoHeight, videoDuration, videoFps)
    }
    
    func getCurrentPts() -> Double {
        guard let item = playerItem else { return 0.0 }
        return CMTimeGetSeconds(item.currentTime())
    }
    
    func isCompleted() -> Bool {
        guard let item = playerItem else { return false }
        return CMTimeCompare(item.currentTime(), item.duration) >= 0
    }
    func generateThumbnail(atSeconds: Double) -> (data: Data, width: Int, height: Int)? {
        guard player != nil, let item = playerItem else { return nil }
        let asset = item.asset
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        let time = CMTime(seconds: atSeconds, preferredTimescale: 600)
        do {
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            let width = 160
            let height = Int(Double(cgImage.height) * (Double(width) / Double(cgImage.width)))
            
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            var rawData = Data(count: width * height * 4)
            rawData.withUnsafeMutableBytes { bytes in
                if let context = CGContext(
                    data: bytes.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) {
                    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                }
            }
            return (rawData, width, height)
        } catch {
            return nil
        }
    }
}

private var fallbackInstance: JvpTexture?

private func getInstance(_ id: Int64) -> JvpTexture? {
    if let inst = JvpTexture.instances[id] {
        return inst
    }
    if let first = JvpTexture.instances.values.first {
        return first
    }
    if fallbackInstance == nil {
        // Create a headless/registry-less fallback instance just for metadata decoding
        let dummyRegistry = DummyTextureRegistry()
        fallbackInstance = JvpTexture(registry: dummyRegistry)
    }
    return fallbackInstance
}

class DummyTextureRegistry: NSObject, FlutterTextureRegistry {
    func register(_ texture: FlutterTexture) -> Int64 { return 0 }
    func textureFrameAvailable(_ textureId: Int64) {}
    func unregisterTexture(_ textureId: Int64) {}
}

@_cdecl("jvp_player_get_thumbnail")
public func jvp_player_get_thumbnail(id: Int64, time_sec: Double, out_width: UnsafeMutablePointer<Int32>, out_height: UnsafeMutablePointer<Int32>, out_size: UnsafeMutablePointer<Int32>) -> UnsafeMutablePointer<UInt8>? {
    guard let instance = getInstance(id) else { return nil }
    guard let res = instance.generateThumbnail(atSeconds: time_sec) else { return nil }
    
    out_width.pointee = Int32(res.width)
    out_height.pointee = Int32(res.height)
    out_size.pointee = Int32(res.data.count)
    
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: res.data.count)
    res.data.withUnsafeBytes { rawBuffer in
        if let baseAddress = rawBuffer.baseAddress {
            buffer.initialize(from: baseAddress.assumingMemoryBound(to: UInt8.self), count: res.data.count)
        }
    }
    return buffer
}

@_cdecl("jvp_player_free_thumbnail_buffer")
public func jvp_player_free_thumbnail_buffer(buffer: UnsafeMutablePointer<UInt8>, size: Int32) {
    buffer.deallocate()
}

@_cdecl("jvp_player_open")
public func jvp_player_open(id: Int64, path: UnsafePointer<CChar>) -> Int32 {
    guard let instance = getInstance(id) else { return 0 }
    let str = String(cString: path)
    return instance.openVideo(path: str) ? 1 : 0
}

@_cdecl("jvp_player_get_metadata")
public func jvp_player_get_metadata(id: Int64, width: UnsafeMutablePointer<Int32>, height: UnsafeMutablePointer<Int32>, duration: UnsafeMutablePointer<Double>, fps: UnsafeMutablePointer<Double>) {
    guard let instance = getInstance(id) else { return }
    let meta = instance.getMetadata()
    width.pointee = Int32(meta.width)
    height.pointee = Int32(meta.height)
    duration.pointee = meta.duration
    fps.pointee = meta.fps
}

@_cdecl("jvp_player_play")
public func jvp_player_play(id: Int64) {
    getInstance(id)?.playVideo()
}

@_cdecl("jvp_player_pause")
public func jvp_player_pause(id: Int64) {
    getInstance(id)?.pauseVideo()
}

@_cdecl("jvp_player_seek")
public func jvp_player_seek(id: Int64, time_sec: Double) {
    getInstance(id)?.seekVideo(toSeconds: time_sec)
}

@_cdecl("jvp_player_set_volume")
public func jvp_player_set_volume(id: Int64, vol: Float) {
    getInstance(id)?.setVideoVolume(vol: vol)
}

@_cdecl("jvp_player_get_pts")
public func jvp_player_get_pts(id: Int64) -> Double {
    return getInstance(id)?.getCurrentPts() ?? 0.0
}

@_cdecl("jvp_player_copy_pixel_buffer")
public func jvp_player_copy_pixel_buffer(id: Int64) -> UnsafeMutableRawPointer? {
    guard let instance = getInstance(id) else { return nil }
    guard let buffer = instance.copyPixelBuffer() else { return nil }
    return buffer.toOpaque()
}

@_cdecl("jvp_player_is_completed")
public func jvp_player_is_completed(id: Int64) -> Int32 {
    return (getInstance(id)?.isCompleted() ?? false) ? 1 : 0
}
