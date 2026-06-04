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

use std::collections::HashMap;
use std::ffi::c_void;
use wgpu::hal::api::Metal as MetalApi;
use wgpu::util::DeviceExt;

#[repr(C)]
#[derive(Debug, Copy, Clone, bytemuck::Pod, bytemuck::Zeroable)]
struct ShaderUniforms {
    intensity_smooth: f32,
    intensity_blur: f32,
    intensity_sharpen: f32,
    intensity_unsharp: f32,
    intensity_hdr: f32,
    intensity_vintage: f32,
    intensity_cyberpunk: f32,
    intensity_cleancinema: f32,
    intensity_vignette: f32,
    intensity_super_res: f32,
    intensity_deband: f32,
    intensity_bloom: f32,
    width: f32,
    height: f32,
    sharpen_type: f32,
    use_yuv: f32,
}

pub(crate) struct RawPtr(pub(crate) *mut c_void);
unsafe impl Send for RawPtr {}
unsafe impl Sync for RawPtr {}

pub struct RenderState {
    pub device: wgpu::Device,
    pub queue: wgpu::Queue,
    pub input_texture: Option<wgpu::Texture>,
    pub input_texture_uv: Option<wgpu::Texture>,
    pub input_width: u32,
    pub input_height: u32,
    pub surface_texture: Option<wgpu::Texture>,
    pub pipelines: HashMap<String, wgpu::RenderPipeline>,
    pub bind_group_layout: wgpu::BindGroupLayout,
    pub sampler: wgpu::Sampler,
    pub bind_group: Option<wgpu::BindGroup>,
    pub uniform_buffer: wgpu::Buffer,
    pub shader_intensity: f32,
    cv_texture_cache: Option<RawPtr>,
    current_cv_tex_y: Option<RawPtr>,
    current_cv_tex_uv: Option<RawPtr>,
    uniforms: std::sync::Mutex<ShaderUniforms>,
}

impl RenderState {
    pub async fn new() -> Option<Self> {
        let instance = wgpu::Instance::default();
        let adapter = instance
            .request_adapter(&wgpu::RequestAdapterOptions {
                power_preference: wgpu::PowerPreference::HighPerformance,
                force_fallback_adapter: false,
                compatible_surface: None,
            })
            .await?;
        let (device, queue) = adapter
            .request_device(
                &wgpu::DeviceDescriptor {
                    label: Some("Jvp Wgpu Device"),
                    required_features: wgpu::Features::empty(),
                    required_limits: wgpu::Limits::default(),
                    memory_hints: wgpu::MemoryHints::default(),
                },
                None,
            )
            .await
            .ok()?;
        let sampler = device.create_sampler(&wgpu::SamplerDescriptor {
            address_mode_u: wgpu::AddressMode::ClampToEdge,
            address_mode_v: wgpu::AddressMode::ClampToEdge,
            mag_filter: wgpu::FilterMode::Linear,
            min_filter: wgpu::FilterMode::Linear,
            ..Default::default()
        });
        let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("Jvp Bind Group Layout"),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Texture {
                        sample_type: wgpu::TextureSampleType::Float { filterable: true },
                        view_dimension: wgpu::TextureViewDimension::D2,
                        multisampled: false,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 2,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 3,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Texture {
                        sample_type: wgpu::TextureSampleType::Float { filterable: true },
                        view_dimension: wgpu::TextureViewDimension::D2,
                        multisampled: false,
                    },
                    count: None,
                },
            ],
        });

        let uniform_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Jvp Uniform Buffer"),
            contents: bytemuck::cast_slice(&[ShaderUniforms {
                intensity_smooth: 0.0,
                intensity_blur: 0.0,
                intensity_sharpen: 0.0,
                intensity_unsharp: 0.0,
                intensity_hdr: 0.0,
                intensity_vintage: 0.0,
                intensity_cyberpunk: 0.0,
                intensity_cleancinema: 0.0,
                intensity_vignette: 0.0,
                intensity_super_res: 0.0,
                intensity_deband: 0.0,
                intensity_bloom: 0.0,
                width: 1280.0,
                height: 720.0,
                sharpen_type: 0.0,
                use_yuv: 0.0,
            }]),
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        });

        let mut cv_texture_cache: Option<RawPtr> = None;
        #[cfg(target_os = "macos")]
        {
            extern "C" {
                fn CVMetalTextureCacheCreate(
                    allocator: *mut c_void,
                    cacheAttributes: *mut c_void,
                    metalDevice: *mut c_void,
                    textureAttributes: *mut c_void,
                    cacheOut: *mut *mut c_void,
                ) -> i32;
            }
            let mut cache: *mut c_void = std::ptr::null_mut();
            unsafe {
                device.as_hal::<MetalApi, _, _>(|hal_device| {
                    if let Some(hal_dev) = hal_device {
                        use metal::foreign_types::ForeignType as _;
                        let raw_metal_device = hal_dev.raw_device().lock().as_ptr() as *mut c_void;
                        let status = CVMetalTextureCacheCreate(
                            std::ptr::null_mut(),
                            std::ptr::null_mut(),
                            raw_metal_device,
                            std::ptr::null_mut(),
                            &mut cache,
                        );
                        if status == 0 {
                            cv_texture_cache = Some(RawPtr(cache));
                        }
                    }
                });
            }
        }

        let initial_uniforms = ShaderUniforms {
            intensity_smooth: 0.0,
            intensity_blur: 0.0,
            intensity_sharpen: 0.0,
            intensity_unsharp: 0.0,
            intensity_hdr: 0.0,
            intensity_vintage: 0.0,
            intensity_cyberpunk: 0.0,
            intensity_cleancinema: 0.0,
            intensity_vignette: 0.0,
            intensity_super_res: 0.0,
            intensity_deband: 0.0,
            intensity_bloom: 0.0,
            width: 1280.0,
            height: 720.0,
            sharpen_type: 0.0,
            use_yuv: 0.0,
        };

        let mut state = Self {
            device,
            queue,
            input_texture: None,
            input_texture_uv: None,
            input_width: 0,
            input_height: 0,
            surface_texture: None,
            pipelines: HashMap::new(),
            bind_group_layout,
            sampler,
            bind_group: None,
            uniform_buffer,
            shader_intensity: 1.0,
            cv_texture_cache,
            current_cv_tex_y: None,
            current_cv_tex_uv: None,
            uniforms: std::sync::Mutex::new(initial_uniforms),
        };
        state.compile_pipelines();
        Some(state)
    }

    fn compile_pipelines(&mut self) {
        let shader_mod = self
            .device
            .create_shader_module(wgpu::ShaderModuleDescriptor {
                label: Some("Effects Shader"),
                source: wgpu::ShaderSource::Wgsl(include_str!("effects.wgsl").into()),
            });

        let pipeline_layout = self
            .device
            .create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
                label: Some("Jvp Pipeline Layout"),
                bind_group_layouts: &[&self.bind_group_layout],
                push_constant_ranges: &[],
            });

        let pipeline = self
            .device
            .create_render_pipeline(&wgpu::RenderPipelineDescriptor {
                label: Some("effects"),
                layout: Some(&pipeline_layout),
                vertex: wgpu::VertexState {
                    module: &shader_mod,
                    entry_point: "vs_main",
                    buffers: &[],
                    compilation_options: Default::default(),
                },
                fragment: Some(wgpu::FragmentState {
                    module: &shader_mod,
                    entry_point: "fs_main",
                    targets: &[Some(wgpu::ColorTargetState {
                        format: wgpu::TextureFormat::Bgra8Unorm,
                        blend: None,
                        write_mask: wgpu::ColorWrites::ALL,
                    })],
                    compilation_options: Default::default(),
                }),
                primitive: wgpu::PrimitiveState::default(),
                depth_stencil: None,
                multisample: wgpu::MultisampleState::default(),
                multiview: None,
                cache: None,
            });
        self.pipelines.insert("effects".to_string(), pipeline);
    }

    pub fn update_intensity(&self, _intensity: f32) {}

    pub fn update_effects(&self, effects: &HashMap<String, f32>) {
        if let Ok(mut uniforms_lock) = self.uniforms.lock() {
            uniforms_lock.intensity_smooth = *effects.get("smooth").unwrap_or(&0.0);
            uniforms_lock.intensity_blur = *effects.get("blur").unwrap_or(&0.0);
            uniforms_lock.intensity_sharpen = *effects.get("sharpen").unwrap_or(&0.0);
            uniforms_lock.intensity_unsharp = *effects.get("unsharp").unwrap_or(&0.0);
            uniforms_lock.intensity_hdr = *effects.get("hdr").unwrap_or(&0.0);
            uniforms_lock.intensity_vintage = *effects.get("vintage").unwrap_or(&0.0);
            uniforms_lock.intensity_cyberpunk = *effects.get("cyberpunk").unwrap_or(&0.0);
            uniforms_lock.intensity_cleancinema = *effects.get("cleancinema").unwrap_or(&0.0);
            uniforms_lock.intensity_vignette = *effects.get("vignette").unwrap_or(&0.0);
            uniforms_lock.intensity_super_res = *effects.get("super_res").unwrap_or(&0.0);
            uniforms_lock.intensity_deband = *effects.get("deband").unwrap_or(&0.0);
            uniforms_lock.intensity_bloom = *effects.get("bloom").unwrap_or(&0.0);
            uniforms_lock.width = *effects.get("width").unwrap_or(&1280.0);
            uniforms_lock.height = *effects.get("height").unwrap_or(&720.0);
            uniforms_lock.sharpen_type = *effects.get("sharpen_type").unwrap_or(&0.0);
            self.queue.write_buffer(
                &self.uniform_buffer,
                0,
                bytemuck::cast_slice(&[*uniforms_lock]),
            );
        }
    }

    pub fn resize_input_texture(&mut self, width: u32, height: u32) {
        if self.input_width == width && self.input_height == height && self.input_texture.is_some()
        {
            return;
        }
        self.input_width = width;
        self.input_height = height;
        let texture = self.device.create_texture(&wgpu::TextureDescriptor {
            label: Some("Jvp Input Texture"),
            size: wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::Rgba8Unorm,
            usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
            view_formats: &[],
        });
        self.input_texture = Some(texture);
        self.input_texture_uv = None;
        self.update_bind_group();
        if let Ok(mut uniforms_lock) = self.uniforms.lock() {
            uniforms_lock.use_yuv = 0.0;
            uniforms_lock.width = width as f32;
            uniforms_lock.height = height as f32;
            self.queue.write_buffer(
                &self.uniform_buffer,
                0,
                bytemuck::cast_slice(&[*uniforms_lock]),
            );
        }
    }

    #[cfg(target_os = "macos")]
    pub fn update_input_from_cv_buffer(&mut self, pixel_buffer: *mut c_void) -> bool {
        let cache_ptr = match &self.cv_texture_cache {
            Some(c) => c.0,
            None => return false,
        };

        extern "C" {
            fn CVMetalTextureCacheCreateTextureFromImage(
                allocator: *mut c_void,
                textureCache: *mut c_void,
                sourceImage: *mut c_void,
                textureAttributes: *mut c_void,
                pixelFormat: usize,
                width: usize,
                height: usize,
                planeIndex: usize,
                textureOut: *mut *mut c_void,
            ) -> i32;
            fn CVMetalTextureGetTexture(texture: *mut c_void) -> *mut c_void;
            fn CFRelease(obj: *mut c_void);
            fn CVPixelBufferGetPixelFormatType(pb: *mut c_void) -> u32;
            fn CVPixelBufferGetWidthOfPlane(pb: *mut c_void, planeIndex: usize) -> usize;
            fn CVPixelBufferGetHeightOfPlane(pb: *mut c_void, planeIndex: usize) -> usize;
        }

        let fmt = unsafe { CVPixelBufferGetPixelFormatType(pixel_buffer) };
        let is_10bit = fmt == 0x78343230 || fmt == 0x78663230;
        if fmt != 0x34323076 && fmt != 0x34323066 && !is_10bit {
            return false;
        }

        let w_y = unsafe { CVPixelBufferGetWidthOfPlane(pixel_buffer, 0) } as u32;
        let h_y = unsafe { CVPixelBufferGetHeightOfPlane(pixel_buffer, 0) } as u32;
        let w_uv = unsafe { CVPixelBufferGetWidthOfPlane(pixel_buffer, 1) } as u32;
        let h_uv = unsafe { CVPixelBufferGetHeightOfPlane(pixel_buffer, 1) } as u32;

        let metal_pixel_format_y = if is_10bit { 115 } else { 10 };
        let metal_pixel_format_uv = if is_10bit { 125 } else { 30 };
        let wgpu_format_y = if is_10bit {
            wgpu::TextureFormat::R16Unorm
        } else {
            wgpu::TextureFormat::R8Unorm
        };
        let wgpu_format_uv = if is_10bit {
            wgpu::TextureFormat::Rg16Unorm
        } else {
            wgpu::TextureFormat::Rg8Unorm
        };

        let mut cv_tex_y: *mut c_void = std::ptr::null_mut();
        let status_y = unsafe {
            CVMetalTextureCacheCreateTextureFromImage(
                std::ptr::null_mut(),
                cache_ptr,
                pixel_buffer,
                std::ptr::null_mut(),
                metal_pixel_format_y,
                w_y as usize,
                h_y as usize,
                0,
                &mut cv_tex_y,
            )
        };

        let mut cv_tex_uv: *mut c_void = std::ptr::null_mut();
        let status_uv = unsafe {
            CVMetalTextureCacheCreateTextureFromImage(
                std::ptr::null_mut(),
                cache_ptr,
                pixel_buffer,
                std::ptr::null_mut(),
                metal_pixel_format_uv,
                w_uv as usize,
                h_uv as usize,
                1,
                &mut cv_tex_uv,
            )
        };

        if status_y == 0 && status_uv == 0 {
            unsafe {
                let mtl_y = CVMetalTextureGetTexture(cv_tex_y);
                let mtl_uv = CVMetalTextureGetTexture(cv_tex_uv);

                if !mtl_y.is_null() && !mtl_uv.is_null() {
                    let mut tex_y_opt: Option<wgpu::Texture> = None;
                    let mut tex_uv_opt: Option<wgpu::Texture> = None;

                    self.device.as_hal::<MetalApi, _, _>(|_hal_device| {
                        use metal::foreign_types::ForeignTypeRef as _;
                        let mtl_tex_y =
                            metal::TextureRef::from_ptr(mtl_y as *mut metal::MTLTexture).to_owned();
                        let mtl_tex_uv =
                            metal::TextureRef::from_ptr(mtl_uv as *mut metal::MTLTexture)
                                .to_owned();

                        let hal_tex_y = wgpu::hal::metal::Device::texture_from_raw(
                            mtl_tex_y,
                            wgpu_format_y,
                            metal::MTLTextureType::D2,
                            1,
                            1,
                            wgpu::hal::CopyExtent {
                                width: w_y,
                                height: h_y,
                                depth: 1,
                            },
                        );
                        let hal_tex_uv = wgpu::hal::metal::Device::texture_from_raw(
                            mtl_tex_uv,
                            wgpu_format_uv,
                            metal::MTLTextureType::D2,
                            1,
                            1,
                            wgpu::hal::CopyExtent {
                                width: w_uv,
                                height: h_uv,
                                depth: 1,
                            },
                        );

                        tex_y_opt = Some(self.device.create_texture_from_hal::<MetalApi>(
                            hal_tex_y,
                            &wgpu::TextureDescriptor {
                                label: Some("ZeroCopy Y"),
                                size: wgpu::Extent3d {
                                    width: w_y,
                                    height: h_y,
                                    depth_or_array_layers: 1,
                                },
                                mip_level_count: 1,
                                sample_count: 1,
                                dimension: wgpu::TextureDimension::D2,
                                format: wgpu_format_y,
                                usage: wgpu::TextureUsages::TEXTURE_BINDING,
                                view_formats: &[],
                            },
                        ));
                        tex_uv_opt = Some(self.device.create_texture_from_hal::<MetalApi>(
                            hal_tex_uv,
                            &wgpu::TextureDescriptor {
                                label: Some("ZeroCopy UV"),
                                size: wgpu::Extent3d {
                                    width: w_uv,
                                    height: h_uv,
                                    depth_or_array_layers: 1,
                                },
                                mip_level_count: 1,
                                sample_count: 1,
                                dimension: wgpu::TextureDimension::D2,
                                format: wgpu_format_uv,
                                usage: wgpu::TextureUsages::TEXTURE_BINDING,
                                view_formats: &[],
                            },
                        ));
                    });

                    if let (Some(ty), Some(tuv)) = (tex_y_opt, tex_uv_opt) {
                        self.input_texture = Some(ty);
                        self.input_texture_uv = Some(tuv);
                        self.input_width = w_y;
                        self.input_height = h_y;
                        self.update_bind_group();
                        if let Ok(mut uniforms_lock) = self.uniforms.lock() {
                            uniforms_lock.use_yuv = 1.0;
                            uniforms_lock.width = w_y as f32;
                            uniforms_lock.height = h_y as f32;
                            self.queue.write_buffer(
                                &self.uniform_buffer,
                                0,
                                bytemuck::cast_slice(&[*uniforms_lock]),
                            );
                        }
                        if let Some(old_y) = self.current_cv_tex_y.take() {
                            CFRelease(old_y.0);
                        }
                        if let Some(old_uv) = self.current_cv_tex_uv.take() {
                            CFRelease(old_uv.0);
                        }
                        self.current_cv_tex_y = Some(RawPtr(cv_tex_y));
                        self.current_cv_tex_uv = Some(RawPtr(cv_tex_uv));
                        return true;
                    }
                }
                CFRelease(cv_tex_y);
                CFRelease(cv_tex_uv);
            }
        }
        false
    }

    fn update_bind_group(&mut self) {
        let Some(tex_y) = &self.input_texture else {
            return;
        };
        let view_y = tex_y.create_view(&wgpu::TextureViewDescriptor::default());

        let view_uv = if let Some(tex_uv) = &self.input_texture_uv {
            tex_uv.create_view(&wgpu::TextureViewDescriptor::default())
        } else {
            tex_y.create_view(&wgpu::TextureViewDescriptor::default())
        };

        self.bind_group = Some(self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Jvp Bind Group"),
            layout: &self.bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::TextureView(&view_y),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::Sampler(&self.sampler),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: self.uniform_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 3,
                    resource: wgpu::BindingResource::TextureView(&view_uv),
                },
            ],
        }));
    }

    pub fn init_output_texture(&mut self, ptr: *mut c_void, width: u32, height: u32) {
        if ptr.is_null() {
            return;
        }
        #[cfg(target_os = "macos")]
        {
            unsafe {
                let mut texture_opt: Option<wgpu::Texture> = None;
                self.device.as_hal::<MetalApi, _, _>(|_hal_device| {
                    use metal::foreign_types::ForeignTypeRef as _;
                    let mtl_ptr = ptr as *mut metal::MTLTexture;
                    let mtl_texture = metal::TextureRef::from_ptr(mtl_ptr).to_owned();
                    let hal_texture = wgpu::hal::metal::Device::texture_from_raw(
                        mtl_texture,
                        wgpu::TextureFormat::Bgra8Unorm,
                        metal::MTLTextureType::D2,
                        1,
                        1,
                        wgpu::hal::CopyExtent {
                            width,
                            height,
                            depth: 1,
                        },
                    );
                    texture_opt = Some(self.device.create_texture_from_hal::<MetalApi>(
                        hal_texture,
                        &wgpu::TextureDescriptor {
                            label: Some("External MTLTexture"),
                            size: wgpu::Extent3d {
                                width,
                                height,
                                depth_or_array_layers: 1,
                            },
                            mip_level_count: 1,
                            sample_count: 1,
                            dimension: wgpu::TextureDimension::D2,
                            format: wgpu::TextureFormat::Bgra8Unorm,
                            usage: wgpu::TextureUsages::RENDER_ATTACHMENT
                                | wgpu::TextureUsages::TEXTURE_BINDING,
                            view_formats: &[],
                        },
                    ));
                });
                if let Some(tex) = texture_opt {
                    self.surface_texture = Some(tex);
                }
            }
        }
    }

    pub fn render(&self, _shader_name: &str) {
        let Some(surface_tex) = &self.surface_texture else {
            return;
        };
        let Some(bind_group) = &self.bind_group else {
            return;
        };
        let Some(pipeline) = self.pipelines.get("effects") else {
            return;
        };

        let view = surface_tex.create_view(&wgpu::TextureViewDescriptor::default());
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("Jvp Render Encoder"),
            });
        {
            let mut rp = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("Jvp Render Pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &view,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color::BLACK),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
            });
            rp.set_pipeline(pipeline);
            rp.set_bind_group(0, bind_group, &[]);
            rp.draw(0..3, 0..1);
        }
        self.queue.submit(std::iter::once(encoder.finish()));
        if !crate::infrastructure::state::IS_PLAYING.load(std::sync::atomic::Ordering::SeqCst) {
            self.device.poll(wgpu::Maintain::Wait);
        }
    }
}

impl Drop for RenderState {
    fn drop(&mut self) {
        #[cfg(target_os = "macos")]
        {
            extern "C" {
                fn CFRelease(obj: *mut c_void);
            }
            if let Some(cache) = self.cv_texture_cache.take() {
                unsafe {
                    CFRelease(cache.0);
                }
            }
            if let Some(y) = self.current_cv_tex_y.take() {
                unsafe {
                    CFRelease(y.0);
                }
            }
            if let Some(uv) = self.current_cv_tex_uv.take() {
                unsafe {
                    CFRelease(uv.0);
                }
            }
        }
    }
}
