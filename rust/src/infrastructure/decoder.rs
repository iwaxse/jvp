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

use anyhow::{anyhow, Result};
use ffmpeg::format::pixel::Pixel;
use ffmpeg::software::scaling::{context::Context as SwsContext, flag::Flags};
use ffmpeg::util::frame::Audio as AudioFrame;
use ffmpeg::util::frame::Video as VideoFrame;
use ffmpeg_next as ffmpeg;
use ffmpeg_next::ffi;
use std::collections::VecDeque;
use std::ffi::c_void;
use std::ptr;

use crate::infrastructure::renderer::RawPtr;

struct CachedFrame {
    pts: f64,
    data: Vec<u8>,
    stride: usize,
    cv_buffer: Option<RawPtr>,
}

impl Drop for CachedFrame {
    fn drop(&mut self) {
        #[cfg(target_os = "macos")]
        if let Some(buf) = self.cv_buffer.take() {
            extern "C" {
                fn CFRelease(obj: *mut c_void);
            }
            unsafe {
                CFRelease(buf.0);
            }
        }
    }
}

pub struct VideoDecoder {
    input_context: ffmpeg::format::context::Input,
    decoder: ffmpeg::decoder::Video,
    video_stream_index: usize,
    sws_context: SwsContext,
    pub width: u32,
    pub height: u32,
    pub duration_secs: f64,
    pub frame_rate: f64,
    time_base: ffmpeg::Rational,
    raw_frame: VideoFrame,
    rgba_frame: VideoFrame,
    pub hw_accel: bool,

    // オーディオ関連
    audio_decoder: Option<ffmpeg::decoder::Audio>,
    audio_stream_index: Option<usize>,
    audio_resampler: Option<ffmpeg::software::resampling::Context>,
    audio_raw_frame: AudioFrame,
    pub audio_buffer: VecDeque<f32>,

    // ビデオパケット先読みキュー(prefetch_audio用)
    video_packet_queue: VecDeque<ffmpeg::Packet>,

    // キャッシュ管理
    cache: VecDeque<CachedFrame>,
    max_cache_size: usize,
    pub current_pts: f64,
}

unsafe impl Send for VideoDecoder {}
unsafe impl Sync for VideoDecoder {}

impl VideoDecoder {
    pub fn new(path: &str, enable_hw: bool) -> Result<Self> {
        let input_context = ffmpeg::format::input(&path)?;

        let video_stream = input_context
            .streams()
            .best(ffmpeg::media::Type::Video)
            .ok_or_else(|| anyhow!("No video stream found"))?;
        let video_stream_index = video_stream.index();
        let mut video_context =
            ffmpeg::codec::context::Context::from_parameters(video_stream.parameters())?;

        let hw_accel = if enable_hw {
            unsafe {
                let mut hw_device_ctx: *mut ffi::AVBufferRef = ptr::null_mut();
                let ret = ffi::av_hwdevice_ctx_create(
                    &mut hw_device_ctx,
                    ffi::AVHWDeviceType::AV_HWDEVICE_TYPE_VIDEOTOOLBOX,
                    ptr::null(),
                    ptr::null_mut(),
                    0,
                );
                if ret >= 0 {
                    (*video_context.as_mut_ptr()).hw_device_ctx = ffi::av_buffer_ref(hw_device_ctx);
                    ffi::av_buffer_unref(&mut hw_device_ctx);
                    true
                } else {
                    video_context.set_threading(ffmpeg_next::threading::Config {
                        kind: ffmpeg_next::threading::Type::Frame,
                        count: 4,
                    });
                    false
                }
            }
        } else {
            video_context.set_threading(ffmpeg_next::threading::Config {
                kind: ffmpeg_next::threading::Type::Frame,
                count: 4,
            });
            false
        };

        let decoder = video_context.decoder().video()?;
        let width = decoder.width();
        let height = decoder.height();
        let sws_context = SwsContext::get(
            Pixel::YUV420P,
            width,
            height,
            Pixel::RGBA,
            width,
            height,
            Flags::FAST_BILINEAR,
        )?;
        let fr = video_stream.avg_frame_rate();
        let frame_rate = if fr.1 > 0 && fr.0 > 0 {
            let rate = fr.0 as f64 / fr.1 as f64;
            if rate > 0.0 {
                rate
            } else {
                30.0
            }
        } else {
            30.0
        };
        let time_base = video_stream.time_base();
        let duration_secs = if input_context.duration() > 0 {
            input_context.duration() as f64 / 1_000_000.0
        } else {
            0.0
        };

        let target_rate = crate::infrastructure::state::AUDIO_SAMPLE_RATE
            .load(std::sync::atomic::Ordering::SeqCst);
        let (audio_decoder, audio_stream_index, audio_resampler) =
            if let Some(audio_stream) = input_context.streams().best(ffmpeg::media::Type::Audio) {
                let audio_context =
                    ffmpeg::codec::context::Context::from_parameters(audio_stream.parameters())?;
                let audio_dec = audio_context.decoder().audio()?;
                let layout = if audio_dec.channel_layout().is_empty() {
                    match audio_dec.channels() {
                        1 => ffmpeg::util::channel_layout::ChannelLayout::MONO,
                        2 => ffmpeg::util::channel_layout::ChannelLayout::STEREO,
                        _ => ffmpeg::util::channel_layout::ChannelLayout::STEREO,
                    }
                } else {
                    audio_dec.channel_layout()
                };
                let resampler = ffmpeg::software::resampling::Context::get(
                    audio_dec.format(),
                    layout,
                    audio_dec.rate(),
                    ffmpeg::format::Sample::F32(ffmpeg::format::sample::Type::Packed),
                    ffmpeg::util::channel_layout::ChannelLayout::STEREO,
                    target_rate,
                )?;
                (Some(audio_dec), Some(audio_stream.index()), Some(resampler))
            } else {
                (None, None, None)
            };

        let max_cache_size = if hw_accel {
            256 // HW加速時はハンドルのみなので多めに
        } else {
            // SWデコード時はRGBA実データを保持するため、解像度に応じて制限(約1GB目安)
            let frame_size = width * height * 4;
            if frame_size > 0 {
                ((1024 * 1024 * 1024 / frame_size) as usize).clamp(16, 128)
            } else {
                64
            }
        };

        Ok(Self {
            input_context,
            decoder,
            video_stream_index,
            sws_context,
            width,
            height,
            duration_secs,
            frame_rate,
            time_base,
            raw_frame: VideoFrame::empty(),
            rgba_frame: VideoFrame::new(Pixel::RGBA, width, height),
            hw_accel,
            audio_decoder,
            audio_stream_index,
            audio_resampler,
            audio_raw_frame: AudioFrame::empty(),
            audio_buffer: VecDeque::with_capacity(target_rate as usize * 2),
            video_packet_queue: VecDeque::new(),
            cache: VecDeque::with_capacity(max_cache_size),
            max_cache_size,
            current_pts: 0.0,
        })
    }

    pub fn seek(&mut self, time_sec: f64, any_frame: bool) -> Result<()> {
        self.audio_buffer.clear();
        self.video_packet_queue.clear();
        let time_base = self.time_base;
        let stream_ts = (time_sec / f64::from(time_base)) as i64;
        let flags = if any_frame {
            ffi::AVSEEK_FLAG_BACKWARD | ffi::AVSEEK_FLAG_ANY
        } else {
            ffi::AVSEEK_FLAG_BACKWARD
        };
        unsafe {
            let ret = ffi::avformat_seek_file(
                self.input_context.as_mut_ptr(),
                self.video_stream_index as i32,
                i64::MIN,
                stream_ts,
                stream_ts,
                flags,
            );
            if ret < 0 {
                let timestamp = (time_sec * 1_000_000.0) as i64;
                self.input_context.seek(timestamp, ..timestamp)?;
            }
        }
        self.decoder.flush();
        if let Some(audio_dec) = &mut self.audio_decoder {
            audio_dec.flush();
        }
        Ok(())
    }

    pub fn next_frame(&mut self) -> Result<Option<f64>> {
        let mut retry = 0;
        while retry < 1000 {
            if self.decoder.receive_frame(&mut self.raw_frame).is_ok() {
                let pts = self.raw_frame.pts().unwrap_or(0);
                let pts_sec = pts as f64 * f64::from(self.time_base);

                if self.hw_accel && self.raw_frame.format() == Pixel::VIDEOTOOLBOX {
                    self.current_pts = pts_sec;
                    if self.raw_frame.width() != self.width
                        || self.raw_frame.height() != self.height
                    {
                        self.width = self.raw_frame.width();
                        self.height = self.raw_frame.height();
                    }
                    self.add_cv_to_cache(pts_sec);
                    let _ = self.receive_audio();
                    return Ok(Some(pts_sec));
                }

                let src_frame = &self.raw_frame;
                let src_pixel = src_frame.format();
                if self.sws_context.input().format != src_pixel
                    || self.sws_context.input().width != src_frame.width()
                    || self.sws_context.input().height != src_frame.height()
                {
                    self.sws_context = SwsContext::get(
                        src_pixel,
                        src_frame.width(),
                        src_frame.height(),
                        Pixel::RGBA,
                        src_frame.width(),
                        src_frame.height(),
                        Flags::FAST_BILINEAR,
                    )
                    .map_err(|e| anyhow!("sws reinit failed: {}", e))?;
                    self.rgba_frame =
                        VideoFrame::new(Pixel::RGBA, src_frame.width(), src_frame.height());
                    self.width = src_frame.width();
                    self.height = src_frame.height();
                }

                if let Err(e) = self.sws_context.run(src_frame, &mut self.rgba_frame) {
                    eprintln!("ERROR: sws_scale failed! error: {:?}", e);
                    return Err(anyhow!("sws_scale failed: {}", e));
                }

                self.add_to_cache(pts_sec);
                self.current_pts = pts_sec;
                let _ = self.receive_audio();
                return Ok(Some(pts_sec));
            }

            // video_packet_queueにあれば先に消費(prefetch_audioで溜めたもの)
            let eof = if let Some(pkt) = self.video_packet_queue.pop_front() {
                self.decoder.send_packet(&pkt)?;
                false
            } else if let Some((stream, packet)) = self.input_context.packets().next() {
                if stream.index() == self.video_stream_index {
                    self.decoder.send_packet(&packet)?;
                } else if Some(stream.index()) == self.audio_stream_index {
                    if let Some(audio_dec) = &mut self.audio_decoder {
                        let _ = audio_dec.send_packet(&packet);
                        let _ = self.receive_audio();
                    }
                }
                false
            } else {
                true
            };
            if eof {
                return Ok(None);
            }
            retry += 1;
        }
        Ok(None)
    }

    /// オーディオを先読みしてaudio_bufferを補充する。
    /// ビデオパケットはvideo_packet_queueに積み、current_ptsは変化しない。
    pub fn prefetch_audio(&mut self, target_samples: usize, max_packets: usize) -> bool {
        let _ = self.receive_audio();
        let mut count = 0;
        while self.audio_buffer.len() < target_samples && count < max_packets {
            match self.input_context.packets().next() {
                Some((stream, packet)) => {
                    if stream.index() == self.video_stream_index {
                        self.video_packet_queue.push_back(packet);
                    } else if Some(stream.index()) == self.audio_stream_index {
                        if let Some(audio_dec) = &mut self.audio_decoder {
                            let _ = audio_dec.send_packet(&packet);
                            let _ = self.receive_audio();
                        }
                    }
                }
                None => return true,
            }
            count += 1;
        }
        false
    }

    /// macOS VideoToolbox からデコードされた生の CVPixelBufferRef を取得する
    pub fn get_cv_pixel_buffer(&self) -> Option<*mut c_void> {
        if self.hw_accel && self.raw_frame.format() == Pixel::VIDEOTOOLBOX {
            unsafe {
                let frame_ptr = self.raw_frame.as_ptr();
                // FFmpegのVideoToolbox実装では、data[3]にCVPixelBufferRefが格納されている
                let pixel_buffer = (*frame_ptr).data[3] as *mut c_void;
                if !pixel_buffer.is_null() {
                    return Some(pixel_buffer);
                }
            }
        }
        None
    }

    fn receive_audio(&mut self) -> Result<()> {
        if self.audio_decoder.is_none() || self.audio_resampler.is_none() {
            return Ok(());
        }
        let audio_dec = self.audio_decoder.as_mut().unwrap();
        let target_rate = crate::infrastructure::state::AUDIO_SAMPLE_RATE
            .load(std::sync::atomic::Ordering::SeqCst);

        while audio_dec.receive_frame(&mut self.audio_raw_frame).is_ok() {
            let layout = if self.audio_raw_frame.channel_layout().is_empty() {
                let default_layout = match self.audio_raw_frame.channels() {
                    1 => ffmpeg::util::channel_layout::ChannelLayout::MONO,
                    2 => ffmpeg::util::channel_layout::ChannelLayout::STEREO,
                    _ => ffmpeg::util::channel_layout::ChannelLayout::STEREO,
                };
                self.audio_raw_frame.set_channel_layout(default_layout);
                default_layout
            } else {
                self.audio_raw_frame.channel_layout()
            };

            let resampler = self.audio_resampler.as_mut().unwrap();
            if resampler.input().format != self.audio_raw_frame.format()
                || resampler.input().channel_layout != layout
                || resampler.input().rate != self.audio_raw_frame.rate()
            {
                if let Ok(new_resampler) = ffmpeg::software::resampling::Context::get(
                    self.audio_raw_frame.format(),
                    layout,
                    self.audio_raw_frame.rate(),
                    ffmpeg::format::Sample::F32(ffmpeg::format::sample::Type::Packed),
                    ffmpeg::util::channel_layout::ChannelLayout::STEREO,
                    target_rate,
                ) {
                    self.audio_resampler = Some(new_resampler);
                }
            }

            let mut resampled = AudioFrame::empty();
            resampled.set_format(ffmpeg::format::Sample::F32(
                ffmpeg::format::sample::Type::Packed,
            ));
            resampled.set_channel_layout(ffmpeg::util::channel_layout::ChannelLayout::STEREO);
            resampled.set_rate(target_rate);

            let resampler = self.audio_resampler.as_mut().unwrap();
            if resampler
                .run(&self.audio_raw_frame, &mut resampled)
                .is_err()
            {
                if let Ok(new_resampler) = ffmpeg::software::resampling::Context::get(
                    self.audio_raw_frame.format(),
                    layout,
                    self.audio_raw_frame.rate(),
                    ffmpeg::format::Sample::F32(ffmpeg::format::sample::Type::Packed),
                    ffmpeg::util::channel_layout::ChannelLayout::STEREO,
                    target_rate,
                ) {
                    self.audio_resampler = Some(new_resampler);
                    let resampler = self.audio_resampler.as_mut().unwrap();
                    let _ = resampler.run(&self.audio_raw_frame, &mut resampled);
                }
            }

            let data = resampled.data(0);
            if !data.is_empty() {
                let count = resampled.samples() * resampled.channels() as usize;
                let samples: &[f32] =
                    unsafe { std::slice::from_raw_parts(data.as_ptr() as *const f32, count) };
                self.audio_buffer.extend(samples);
            }
        }
        Ok(())
    }

    fn add_to_cache(&mut self, pts: f64) {
        if self.cache.len() >= self.max_cache_size {
            self.cache.pop_front();
        }
        let data = self.rgba_frame.data(0).to_vec();
        let stride = self.rgba_frame.stride(0);
        self.cache.push_back(CachedFrame {
            pts,
            data,
            stride,
            cv_buffer: None,
        });
    }

    fn add_cv_to_cache(&mut self, pts: f64) {
        if self.cache.len() >= self.max_cache_size {
            self.cache.pop_front();
        }
        if let Some(cv_buf) = self.get_cv_pixel_buffer() {
            extern "C" {
                fn CFRetain(obj: *mut c_void) -> *mut c_void;
            }
            let retained = unsafe { CFRetain(cv_buf) };
            self.cache.push_back(CachedFrame {
                pts,
                data: Vec::new(),
                stride: 0,
                cv_buffer: Some(RawPtr(retained)),
            });
        }
    }

    pub fn get_cached_cv_buffer(&self, pts: f64) -> Option<*mut c_void> {
        let mut best_buf = None;
        let mut min_diff = 1.0 / self.frame_rate;
        for frame in &self.cache {
            let diff = (frame.pts - pts).abs();
            if diff < min_diff {
                if let Some(buf) = &frame.cv_buffer {
                    min_diff = diff;
                    best_buf = Some(buf.0);
                }
            }
        }
        best_buf
    }

    pub fn write_cache_to_texture(
        &self,
        pts: f64,
        queue: &wgpu::Queue,
        texture: &wgpu::Texture,
    ) -> bool {
        let mut best_idx = None;
        let mut min_diff = 1.0 / self.frame_rate;
        for (i, frame) in self.cache.iter().enumerate() {
            let diff = (frame.pts - pts).abs();
            if diff < min_diff {
                min_diff = diff;
                best_idx = Some(i);
            }
        }
        if let Some(idx) = best_idx {
            let frame = &self.cache[idx];
            queue.write_texture(
                wgpu::ImageCopyTexture {
                    texture,
                    mip_level: 0,
                    origin: wgpu::Origin3d::ZERO,
                    aspect: wgpu::TextureAspect::All,
                },
                &frame.data,
                wgpu::ImageDataLayout {
                    offset: 0,
                    bytes_per_row: Some(frame.stride as u32),
                    rows_per_image: Some(self.height),
                },
                wgpu::Extent3d {
                    width: self.width,
                    height: self.height,
                    depth_or_array_layers: 1,
                },
            );
            true
        } else {
            false
        }
    }

    pub fn get_scaled_rgba(
        &self,
        target_width: u32,
        target_height: u32,
    ) -> Result<(Vec<u8>, u32, u32)> {
        let mut sws_context = SwsContext::get(
            self.rgba_frame.format(),
            self.rgba_frame.width(),
            self.rgba_frame.height(),
            Pixel::RGBA,
            target_width,
            target_height,
            Flags::BILINEAR,
        )
        .map_err(|e| anyhow!("sws init failed for thumbnail: {}", e))?;

        let mut scaled_frame = VideoFrame::new(Pixel::RGBA, target_width, target_height);
        sws_context
            .run(&self.rgba_frame, &mut scaled_frame)
            .map_err(|e| anyhow!("sws_scale failed for thumbnail: {}", e))?;

        let data = scaled_frame.data(0).to_vec();
        Ok((data, target_width, target_height))
    }

    pub fn write_to_texture(&self, queue: &wgpu::Queue, texture: &wgpu::Texture) {
        let stride = self.rgba_frame.stride(0);
        let data = self.rgba_frame.data(0);
        queue.write_texture(
            wgpu::ImageCopyTexture {
                texture,
                mip_level: 0,
                origin: wgpu::Origin3d::ZERO,
                aspect: wgpu::TextureAspect::All,
            },
            data,
            wgpu::ImageDataLayout {
                offset: 0,
                bytes_per_row: Some(stride as u32),
                rows_per_image: Some(self.height),
            },
            wgpu::Extent3d {
                width: self.width,
                height: self.height,
                depth_or_array_layers: 1,
            },
        );
    }
}
