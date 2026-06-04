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

typealias RenderFrameFunc = @convention(c) () -> Void

private let jvp_render_frame: RenderFrameFunc? = {
    let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
    if let sym = dlsym(RTLD_DEFAULT, "jvp_render_frame") {
        return unsafeBitCast(sym, to: RenderFrameFunc.self)
    }
    return nil
}()

class JvpTexture: NSObject, FlutterTexture {
    private var pixelBuffer: CVPixelBuffer?
    var id: Int64 = -1
    private let registry: FlutterTextureRegistry
    private var textureCache: CVMetalTextureCache?
    private var metalDevice: MTLDevice?
    private var sharedCvTexture: CVMetalTexture?
    private var sharedMtlTexture: MTLTexture?
    private var displayLink: CVDisplayLink?
    
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
            }
            return self.id
        } else {
            NSLog("DEBUG Swift: CVPixelBufferCreate failed status=\(status) w=\(width) h=\(height)")
        }
        return -1
    }
    
    func getMTLTexturePointer() -> UnsafeMutableRawPointer? {
        guard let pb = pixelBuffer, let cache = textureCache else {
            NSLog("DEBUG Swift: getMTLTexturePointer - missing pb or cache")
            return nil
        }
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
        } else {
            NSLog("DEBUG Swift: CVMetalTextureCacheCreateTextureFromImage failed status=\(status)")
        }
        return nil
    }

    func getPixelBufferAddress() -> UInt? {
        guard let pb = pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        if let addr = CVPixelBufferGetBaseAddress(pb) {
            return UInt(bitPattern: addr)
        }
        return nil
    }
    
    func getPixelBufferBytesPerRow() -> Int {
        guard let pb = pixelBuffer else { return 0 }
        return CVPixelBufferGetBytesPerRow(pb)
    }

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        jvp_render_frame?()
        if let pb = pixelBuffer {
            return Unmanaged.passRetained(pb)
        }
        return nil
    }
    
    func onFrameAvailable() {
        if id >= 0 {
            self.registry.textureFrameAvailable(id)
        }
    }
}
