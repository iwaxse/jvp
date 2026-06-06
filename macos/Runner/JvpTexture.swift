/*
 * jvp (Jamy-chan Video Player)
 * Copyright (C) 2026 iwaxse
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import Cocoa
import FlutterMacOS
import AVFoundation

class JvpTexture: NSObject, FlutterTexture {
    static var instances = [Int64: JvpTexture]()
    
    private var pixelBuffer: CVPixelBuffer?
    private var playerPixelBuffer: CVPixelBuffer?
    var id: Int64 = -1
    private let registry: FlutterTextureRegistry
    private var textureCache: CVMetalTextureCache?
    private let metalDevice: MTLDevice?
    private var sharedCvTexture: CVMetalTexture?
    private var sharedMtlTexture: MTLTexture?
    private var displayLink: CVDisplayLink?
    
    fileprivate var player: AVPlayer?
    fileprivate var playerItem: AVPlayerItem?
    fileprivate var videoOutput: AVPlayerItemVideoOutput?
    
    fileprivate var videoWidth: Int = 0
    fileprivate var videoHeight: Int = 0
    fileprivate var videoDuration: Double = 0.0
    fileprivate var videoFps: Double = 30.0
    fileprivate var isPlayingState: Bool = false
    private var pendingFrame: Bool = false
    private var isSeeking = false
    private var pendingSeekTime: Double?
    private var hasPostedCompleted = false
    
    init(registry: FlutterTextureRegistry) {
        self.registry = registry
        self.metalDevice = MTLCreateSystemDefaultDevice()
        super.init()
        if let device = metalDevice {
            CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        }
        var displayID = CGMainDisplayID()
        if let window = NSApplication.shared.windows.first(where: { $0.isVisible }) ?? NSApplication.shared.mainWindow {
            if let screen = window.screen,
               let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                displayID = CGDirectDisplayID(screenNumber.uint32Value)
            }
        }
        CVDisplayLinkCreateWithCGDisplay(displayID, &displayLink)
        if let link = displayLink {
            let callback: CVDisplayLinkOutputCallback = { (displayLink, inNow, inOutputTime, flagsIn, flagsOut, displayLinkContext) -> CVReturn in
                let mySelf = Unmanaged<JvpTexture>.fromOpaque(displayLinkContext!).takeUnretainedValue()
                guard mySelf.isPlayingState, !mySelf.pendingFrame else { return kCVReturnSuccess }
                mySelf.pendingFrame = true
                DispatchQueue.main.async {
                    mySelf.processNextFrame()
                    mySelf.onFrameAvailable()
                    mySelf.pendingFrame = false
                }
                return kCVReturnSuccess
            }
            CVDisplayLinkSetOutputCallback(link, callback, Unmanaged.passUnretained(self).toOpaque())
            CVDisplayLinkStart(link)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidChangeScreen),
            name: NSWindow.didChangeScreenNotification,
            object: nil
        )
    }
    
    @objc private func windowDidChangeScreen(notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window == NSApplication.shared.mainWindow || window.contentViewController is FlutterViewController {
            guard let link = displayLink else { return }
            if let screen = window.screen,
               let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                let displayID = CGDirectDisplayID(screenNumber.uint32Value)
                CVDisplayLinkSetCurrentCGDisplay(link, displayID)
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
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
        playerPixelBuffer = nil
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
    
    func absorbFallbackIfNeeded() {
        guard let fb = fallbackInstance, fb.player != nil else { return }
        self.player = fb.player
        self.playerItem = fb.playerItem
        self.videoOutput = fb.videoOutput
        self.videoWidth = fb.videoWidth
        self.videoHeight = fb.videoHeight
        self.videoDuration = fb.videoDuration
        self.videoFps = fb.videoFps
        fb.player = nil
        fb.playerItem = nil
        fb.videoOutput = nil
        fallbackInstance = nil
    }

    private func clearPixelBuffer() {
        guard let pb = pixelBuffer else { return }
        CVPixelBufferLockBaseAddress(pb, [])
        let height = CVPixelBufferGetHeight(pb)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
        if let baseAddress = CVPixelBufferGetBaseAddress(pb) {
            memset(baseAddress, 0, height * bytesPerRow)
        }
        CVPixelBufferUnlockBaseAddress(pb, [])
        playerPixelBuffer = nil
    }

    func openVideo(path: String) -> Bool {
        cleanupPlayer()
        clearPixelBuffer()
        renderCurrentFrame()
        onFrameAvailable()
        
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
            object: nil
        )
        
        return true
    }
    
    @objc private func playerItemDidPlayToEndTime(notification: Notification) {
        guard let item = notification.object as? AVPlayerItem, item == self.playerItem else { return }
        NotificationCenter.default.post(name: NSNotification.Name("JvpPlayerCompleted"), object: self)
    }
    
    func playVideo() {
        isPlayingState = true
        hasPostedCompleted = false
        if isCompleted() {
            player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        player?.play()
    }
    
    func pauseVideo() {
        isPlayingState = false
        player?.pause()
    }
    
    func seekVideo(toSeconds: Double, accurate: Bool) {
        hasPostedCompleted = false
        guard let p = player else { return }
        if isSeeking {
            pendingSeekTime = toSeconds
            return
        }
        isSeeking = true
        let time = CMTime(seconds: toSeconds, preferredTimescale: 600)
        p.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self = self else { return }
            self.processNextFrame()
            self.onFrameAvailable()
            self.isSeeking = false
            if let nextTime = self.pendingSeekTime {
                self.pendingSeekTime = nil
                self.seekVideo(toSeconds: nextTime, accurate: accurate)
            }
        }
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

    func renderCurrentFrame() {
        guard let playerPb = playerPixelBuffer, let destPb = pixelBuffer, let cache = textureCache else { return }
        updateInputCallback?(Unmanaged.passUnretained(playerPb).toOpaque())
        let width = CVPixelBufferGetWidth(destPb)
        let height = CVPixelBufferGetHeight(destPb)
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            destPb,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )
        if status == kCVReturnSuccess, let cvTex = cvTexture, let mtlTex = CVMetalTextureGetTexture(cvTex) {
            let ptr = Unmanaged.passUnretained(mtlTex).toOpaque()
            setOutputTextureCallback?(ptr, Int32(videoWidth), Int32(videoHeight))
            renderCallback?()
        }
        CVMetalTextureCacheFlush(cache, 0)
    }

    func processNextFrame() {
        updateFrameBuffer()
        renderCurrentFrame()
        let pts = getCurrentPts()
        NotificationCenter.default.post(
            name: NSNotification.Name("JvpPlayerPtsChanged"),
            object: self,
            userInfo: ["pts": pts]
        )
        if isCompleted() && !hasPostedCompleted {
            hasPostedCompleted = true
            NotificationCenter.default.post(
                name: NSNotification.Name("JvpPlayerCompleted"),
                object: self
            )
        }
    }

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        if let pb = pixelBuffer {
            return Unmanaged.passRetained(pb)
        }
        return nil
    }
    
    private func updateFrameBuffer() {
        guard let output = videoOutput, let item = playerItem else { return }
        let time = item.currentTime()
        var presentationItemTime = CMTime.zero
        if let pb = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: &presentationItemTime) {
            self.playerPixelBuffer = pb
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
        let current = CMTimeGetSeconds(item.currentTime())
        let duration = CMTimeGetSeconds(item.duration)
        if duration.isNaN || duration <= 0.0 { return false }
        return current >= (duration - 0.1)
    }
    func generateThumbnail(atSeconds: Double) -> (data: Data, width: Int, height: Int)? {
        var activePlayer = player
        var activeItem = playerItem
        if activePlayer == nil {
            activePlayer = fallbackInstance?.player
            activeItem = fallbackInstance?.playerItem
        }
        guard let _ = activePlayer, let item = activeItem else { return nil }
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
public func jvp_player_seek(id: Int64, time_sec: Double, accurate: Int32) {
    getInstance(id)?.seekVideo(toSeconds: time_sec, accurate: accurate != 0)
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

private var renderCallback: (@convention(c) () -> Void)?
private var updateInputCallback: (@convention(c) (UnsafeMutableRawPointer) -> Void)?
private var setOutputTextureCallback: (@convention(c) (UnsafeMutableRawPointer, Int32, Int32) -> Void)?

@_cdecl("jvp_player_register_render_callback")
public func jvp_player_register_render_callback(callback: @escaping @convention(c) () -> Void) {
    renderCallback = callback
}

@_cdecl("jvp_player_register_update_input_callback")
public func jvp_player_register_update_input_callback(callback: @escaping @convention(c) (UnsafeMutableRawPointer) -> Void) {
    updateInputCallback = callback
}

@_cdecl("jvp_player_register_set_output_callback")
public func jvp_player_register_set_output_callback(callback: @escaping @convention(c) (UnsafeMutableRawPointer, Int32, Int32) -> Void) {
    setOutputTextureCallback = callback
}

