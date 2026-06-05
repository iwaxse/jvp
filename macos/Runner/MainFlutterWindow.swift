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

class MainFlutterWindow: NSWindow {
    var jvpTexture: JvpTexture?
    var channel: FlutterMethodChannel?

    override func awakeFromNib() {
        let flutterViewController = FlutterViewController()
        let windowFrame = self.frame
        self.contentViewController = flutterViewController
        self.setFrame(windowFrame, display: true)

        RegisterGeneratedPlugins(registry: flutterViewController)

        let channel = FlutterMethodChannel(name: "com.iwaxse.jvp/texture", binaryMessenger: flutterViewController.engine.binaryMessenger)
        self.channel = channel
        channel.setMethodCallHandler { [weak self] (call, result) in
            guard let self = self else { return }
            if call.method == "initTexture" {
                if let args = call.arguments as? [String: Any],
                   let width = args["width"] as? Int,
                   let height = args["height"] as? Int {
                    if self.jvpTexture == nil {
                        let registrar = flutterViewController.engine.registrar(forPlugin: "JvpTexturePlugin")
                        self.jvpTexture = JvpTexture(registry: registrar.textures)
                    }
                    guard let texture = self.jvpTexture else {
                        result(FlutterError(code: "INIT_FAIL", message: "Failed to init texture", details: nil))
                        return
                    }
                    let id = texture.create(width: width, height: height)
                    texture.absorbFallbackIfNeeded()
                    if let ptr = texture.getMTLTexturePointer() {
                        let address = UInt(bitPattern: ptr)
                        let bytesPerRow = texture.getPixelBufferBytesPerRow()
                        result(["textureId": id, "ptr": address, "bytesPerRow": bytesPerRow])
                        return
                    }
                    result(FlutterError(code: "PTR_FAIL", message: "Failed to get Metal pointer", details: nil))
                }
            } else if call.method == "updateTexture" {
                self.jvpTexture?.renderCurrentFrame()
                self.jvpTexture?.onFrameAvailable()
                result(nil)
            } else {
                result(FlutterMethodNotImplemented)
            }
        }

        super.awakeFromNib()
    }
}
