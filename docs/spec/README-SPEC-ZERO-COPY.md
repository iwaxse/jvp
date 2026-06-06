# JVP Zero-Copy Texture Pipeline Spec

Yo! Let's dive deep into the real hardware metal. 🛠️🔥 This document specifies how JVP manages **Zero-Copy Texture Rendering** between macOS Native (`CVPixelBuffer`), the GPU rendering logic (`Rust` / `wgpu`), and Flutter's rendering tree (`FlutterTexture`).

No heavy memory copies, no CPU overhead—just pure hardware-accelerated pipeline goodness. Let's break down how the bytes flow!


## 🎬 The Core Pipeline Overview

The key to zero-copy rendering is **passing GPU memory pointers (addresses)** rather than copying actual pixel arrays. Here is the low-level data flow on the GPU:

```
[AVPlayer (Swift)]
       │
       ▼ (1) Extracts raw video frame
[CVPixelBuffer (NV12/Biplanar)]
       │
       ▼ (2) Shared C-FFI Pointer (Zero-Copy)
[Rust State (RENDER_STATE)]
       │
       ▼ (3) wgpu Bindings (Reads NV12, converts to RGBA, applies Custom Shaders)
[MTLTexture (Metal Texture)]
       │
       ▼ (4) Registered pointer mapping
[FlutterTextureRegistry]
       │
       ▼ (5) Direct GPU presentation
[Flutter Engine (macOS Window)]
```


## 1. Native Frame Capture (Swift Land)

Swift utilizes `AVPlayerItemVideoOutput` to extract frames from the hardware decoder as `CVPixelBuffer`.

* **Pixel Format**: We request `kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange` (NV12 format). This format is natively supported by iOS/macOS hardware decoders and consumes less GPU bandwidth.
* **Metal Compatibility**: We mark `kCVPixelBufferMetalCompatibilityKey` as `true` during allocation. This allows the GPU to directly map the pixel buffer as a Metal texture resource without any copying!


## 2. Pointers & Registration (Swift ➔ Rust)

When Flutter requests texture initialization, the following handshake happens:

1. **Flutter requests Texture ID**: Dart calls `initTexture` via MethodChannel.
2. **Swift Allocates Buffer**: `JvpTexture.swift` allocates a `CVPixelBuffer` compatible with Metal and registers it with `FlutterTextureRegistry`.
3. **Ffi Handshake**:
   - Swift passes the texture ID and the raw memory address of the Metal texture (`MTLTexture`) to Rust using `initTextureMode`.
   - On the Rust side, the rendering engine wraps this raw address using Rust's `RENDER_STATE` so it knows exactly where to write the processed output.


## 3. Shader Processing & wgpu (Rust Land)

When a new frame is available, Swift triggers the Rust render callback:

```
[Swift] processNextFrame() ➔ [Rust] jvp_render_frame()
```

1. **CVBuffer Update**: Swift registers the current frame `CVPixelBuffer` with Rust. Rust accesses the buffer planes (Y and UV) directly in GPU memory using the memory addresses.
2. **GPU Processing**:
   - `wgpu` binds the Y and UV planes as input textures.
   - A custom vertex/fragment shader compiles. The fragment shader converts YUV to RGB color space.
   - Rust applies any active shaders (Vintage, Deband, Vignette, HDR, Vintage, etc.) based on the intensity states configured via Dart.
3. **Writing Output**: Rust writes the final processed RGBA pixels directly into the registered destination `MTLTexture`.


## 4. Flutter Presentation (Flutter Land)

Once Rust finishes writing to the `MTLTexture`, the final frame is presented to the screen:

1. **Frame Signal**: Swift calls `textureFrameAvailable(id)` on the Flutter registry.
2. **Direct Compositing**: The Flutter Engine reads the same GPU memory space (`MTLTexture`) where Rust just wrote the frame. It composites the video frame directly inside the Flutter Widget hierarchy using Metal.
3. **Hardware Sync**: All rendering is synced with the monitor refresh rate via `CVDisplayLink` to ensure buttery-smooth playback at 60+ FPS without screen tearing.


This native zero-copy structure allows JVP to run heavy shader pipelines at 4K resolution with almost 0% CPU consumption! Power efficiency at its finest. ⚡😎
