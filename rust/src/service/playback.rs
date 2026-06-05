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

use crate::domain::video::{Thumbnail, VideoInfo};
use crate::frb_generated::StreamSink;
use crate::infrastructure::decoder::VideoDecoder;
use crate::infrastructure::state::{
    ACTIVE_SHADER, AUDIO_PLAYER, DECODER, EFFECTS, IS_PLAYING, RENDER_STATE, SHADER_INTENSITIES,
    THUMBNAIL_DECODER,
};
use once_cell::sync::Lazy;
use ringbuf::traits::Producer;
use std::ffi::c_void;
use std::sync::{atomic::Ordering, Mutex};

static EVENT_SINK: Lazy<Mutex<Option<StreamSink<String>>>> = Lazy::new(|| Mutex::new(None));

pub fn emit_event(event_type: &str, data_json: &str) {
    if let Ok(lock) = EVENT_SINK.lock() {
        if let Some(sink) = &*lock {
            let msg = format!("{{\"type\": \"{}\", \"data\": {}}}", event_type, data_json);
            let _ = sink.add(msg);
        }
    }
}

fn update_textures_from_decoder(
    state: &mut crate::infrastructure::renderer::RenderState,
    decoder: &VideoDecoder,
) {
    let cv_buf_opt = decoder.get_cv_pixel_buffer();
    let w = decoder.width;
    let h = decoder.height;
    #[cfg(target_os = "macos")]
    {
        if let Some(cv_buf) = cv_buf_opt {
            if state.update_input_from_cv_buffer(cv_buf) {
                return;
            }
        }
    }

    if decoder.hw_accel {
        return;
    }

    state.resize_input_texture(w, h);
    if let Some(input_tex) = &state.input_texture {
        decoder.write_to_texture(&state.queue, input_tex);
    }
}

pub struct PlaybackService;

impl PlaybackService {
    pub fn init_app() {
        let _ = Lazy::force(&RENDER_STATE);
        let _ = Lazy::force(&ACTIVE_SHADER);
        let _ = Lazy::force(&EFFECTS);
    }

    pub fn start_player_event_stream(sink: StreamSink<String>) {
        if let Ok(mut lock) = EVENT_SINK.lock() {
            *lock = Some(sink);
        }
    }

    pub fn open_video(path: String) -> Result<VideoInfo, String> {
        ffmpeg_next::init().map_err(|e| e.to_string())?;

        let decoder = VideoDecoder::new(&path, true).map_err(|e| e.to_string())?;
        let thumb_decoder = VideoDecoder::new(&path, false).ok();

        let info = VideoInfo {
            width: decoder.width,
            height: decoder.height,
            duration_secs: decoder.duration_secs,
            frame_rate: decoder.frame_rate,
        };

        IS_PLAYING.store(false, Ordering::SeqCst);

        if let Ok(mut dec) = DECODER.lock() {
            *dec = Some(decoder);
        }
        if let Ok(mut dec) = THUMBNAIL_DECODER.lock() {
            *dec = thumb_decoder;
        }

        let info_json = serde_json::to_string(&info).unwrap_or_default();
        emit_event("metadata", &info_json);
        Ok(info)
    }

    pub fn get_thumbnail(time_sec: f64) -> Result<Thumbnail, String> {
        let mut dec = THUMBNAIL_DECODER.lock().map_err(|e| e.to_string())?;
        let decoder = match dec.as_mut() {
            Some(d) => d,
            None => return Err("Thumbnail decoder not ready".to_string()),
        };

        decoder.seek(time_sec, false).map_err(|e| e.to_string())?;

        let frame_duration = 1.0 / decoder.frame_rate;
        let mut frames_decoded = 0;

        while frames_decoded < 300 {
            match decoder.next_frame() {
                Ok(Some(pts_sec)) => {
                    frames_decoded += 1;
                    if pts_sec >= time_sec - frame_duration * 0.5 {
                        break;
                    }
                }
                Ok(None) => break,
                Err(e) => return Err(e.to_string()),
            }
        }

        let target_width = 160;
        let target_height =
            (decoder.height as f32 * (target_width as f32 / decoder.width as f32)) as u32;
        let (data, width, height) = decoder
            .get_scaled_rgba(target_width, target_height)
            .map_err(|e| e.to_string())?;

        Ok(Thumbnail {
            data,
            width,
            height,
        })
    }

    pub fn init_texture_mode(ptr: usize, width: u32, height: u32) {
        if let Ok(mut effects) = EFFECTS.write() {
            effects.insert("width".to_string(), width as f32);
            effects.insert("height".to_string(), height as f32);
            let current_effects = effects.clone();

            let dec_dims = DECODER
                .lock()
                .ok()
                .and_then(|d| d.as_ref().map(|d| (d.width, d.height)));

            if let Ok(mut state_lock) = RENDER_STATE.write() {
                if let Some(state) = &mut *state_lock {
                    state.init_output_texture(ptr as *mut c_void, width, height);
                    state.update_effects(&current_effects);
                    if let Some((w, h)) = dec_dims {
                        state.resize_input_texture(w, h);
                    }
                }
            }
        }
    }

    pub fn update_frame() -> Result<bool, String> {
        if !IS_PLAYING.load(Ordering::SeqCst) {
            return Ok(false);
        }

        let mut dec = DECODER.lock().map_err(|e| e.to_string())?;
        let decoder = match dec.as_mut() {
            Some(d) => d,
            None => return Ok(false),
        };

        match decoder.next_frame() {
            Ok(Some(pts_sec)) => {
                if let Ok(mut state_lock) = RENDER_STATE.write() {
                    if let Some(state) = &mut *state_lock {
                        update_textures_from_decoder(state, decoder);
                    }
                }

                // オーディオの書き込み
                if let Ok(mut audio_lock) = AUDIO_PLAYER.lock() {
                    if let Some(audio) = &mut *audio_lock {
                        while let Some(sample) = decoder.audio_buffer.pop_front() {
                            if audio.producer.try_push(sample).is_err() {
                                decoder.audio_buffer.push_front(sample);
                                break;
                            }
                        }
                    }
                }

                emit_event("frame", &format!("{{\"pts_sec\": {}}}", pts_sec));
                Ok(true)
            }
            Ok(None) => {
                IS_PLAYING.store(false, Ordering::SeqCst);
                emit_event("completed", "{}");
                Ok(false)
            }
            Err(e) => {
                emit_event("error", &format!("{{\"message\": \"{}\"}}", e));
                Err(e.to_string())
            }
        }
    }

    pub fn seek(time_sec: f64, accurate: bool) -> Result<(), String> {
        let was_playing = IS_PLAYING.swap(false, Ordering::SeqCst);

        let mut dec = DECODER.lock().map_err(|e| e.to_string())?;
        let decoder = match dec.as_mut() {
            Some(d) => d,
            None => {
                if was_playing {
                    IS_PLAYING.store(true, Ordering::SeqCst);
                }
                return Ok(());
            }
        };

        // シーク前のテクスチャ準備
        if let Ok(mut state_lock) = RENDER_STATE.write() {
            if let Some(state) = &mut *state_lock {
                state.resize_input_texture(decoder.width, decoder.height);
            }
        }

        let current_pts = decoder.current_pts;
        let frame_duration = 1.0 / decoder.frame_rate;

        if !accurate {
            let mut found_in_cache = false;
            let is_hw = decoder.hw_accel;
            if is_hw {
                if let Some(cv_buf) = decoder.get_cached_cv_buffer(time_sec) {
                    if let Ok(mut state_lock) = RENDER_STATE.write() {
                        if let Some(state) = &mut *state_lock {
                            state.update_input_from_cv_buffer(cv_buf);
                            decoder.current_pts = time_sec;
                            decoder.audio_buffer.clear();
                            found_in_cache = true;
                        }
                    }
                }
            } else {
                if let Ok(state_lock) = RENDER_STATE.read() {
                    if let Some(state) = &*state_lock {
                        if let Some(input_tex) = &state.input_texture {
                            if decoder.write_cache_to_texture(time_sec, &state.queue, input_tex) {
                                decoder.current_pts = time_sec;
                                decoder.audio_buffer.clear();
                                found_in_cache = true;
                            }
                        }
                    }
                }
            }
            if found_in_cache {
                emit_event("frame", &format!("{{\"pts_sec\": {}}}", time_sec));
                drop(dec);
                if was_playing {
                    Self::set_playing(true);
                }
                return Ok(());
            }
        }

        if !accurate && time_sec >= current_pts && time_sec < current_pts + 1.0 {
            let mut last_pts = current_pts;
            while last_pts < time_sec - frame_duration * 0.1 {
                match decoder.next_frame() {
                    Ok(Some(pts)) => {
                        last_pts = pts;
                        if pts >= time_sec - frame_duration * 0.5 {
                            break;
                        }
                    }
                    _ => break,
                }
            }
            if let Ok(mut state_lock) = RENDER_STATE.write() {
                if let Some(state) = &mut *state_lock {
                    update_textures_from_decoder(state, decoder);
                }
            }
            emit_event("frame", &format!("{{\"pts_sec\": {}}}", last_pts));
            drop(dec);
            if was_playing {
                Self::set_playing(true);
            }
            return Ok(());
        }

        decoder.seek(time_sec, false).map_err(|e| e.to_string())?;

        let mut last_pts = time_sec;
        let max_forward_frames = if accurate {
            if decoder.hw_accel {
                1000
            } else {
                500
            }
        } else {
            if decoder.hw_accel {
                60
            } else {
                30
            }
        };
        let mut frames_decoded = 0;

        while frames_decoded < max_forward_frames {
            match decoder.next_frame() {
                Ok(Some(pts_sec)) => {
                    last_pts = pts_sec;
                    frames_decoded += 1;
                    if pts_sec >= time_sec - frame_duration * 0.5 {
                        break;
                    }
                }
                Ok(None) => break,
                Err(e) => {
                    if was_playing {
                        Self::set_playing(true);
                    }
                    return Err(e.to_string());
                }
            }
        }

        decoder.audio_buffer.clear();
        let target_samples =
            (crate::infrastructure::state::AUDIO_SAMPLE_RATE.load(Ordering::SeqCst) as usize) * 2
                / 5;
        let mut pre_decoded = 0;
        while decoder.audio_buffer.len() < target_samples && pre_decoded < 10 {
            if let Ok(Some(pts)) = decoder.next_frame() {
                last_pts = pts;
                pre_decoded += 1;
            } else {
                break;
            }
        }

        if let Ok(mut state_lock) = RENDER_STATE.write() {
            if let Some(state) = &mut *state_lock {
                update_textures_from_decoder(state, decoder);
            }
        }

        emit_event("frame", &format!("{{\"pts_sec\": {}}}", last_pts));
        drop(dec);

        if was_playing {
            Self::set_playing(true);
        }
        Ok(())
    }

    pub fn set_playing(playing: bool) {
        let was_playing = IS_PLAYING.swap(playing, Ordering::SeqCst);
        let playing_str = if playing { "true" } else { "false" };
        emit_event("playingState", playing_str);

        if playing && !was_playing {
            if let Ok(mut dec) = DECODER.lock() {
                if let Some(decoder) = dec.as_mut() {
                    let target_samples = (crate::infrastructure::state::AUDIO_SAMPLE_RATE
                        .load(Ordering::SeqCst) as usize)
                        * 2
                        / 5;
                    let mut pre_decoded = 0;
                    while decoder.audio_buffer.len() < target_samples && pre_decoded < 10 {
                        if let Ok(Some(_)) = decoder.next_frame() {
                            pre_decoded += 1;
                        } else {
                            break;
                        }
                    }
                }
            }

            std::thread::spawn(move || {
                let start_time = std::time::Instant::now();
                let mut start_pts = 0.0;

                if let Ok(dec) = DECODER.lock() {
                    if let Some(d) = dec.as_ref() {
                        start_pts = d.current_pts;
                    }
                }

                loop {
                    if !IS_PLAYING.load(Ordering::SeqCst) {
                        break;
                    }

                    let elapsed = start_time.elapsed().as_secs_f64();
                    let target_pts = start_pts + elapsed;

                    let mut current_pts = 0.0;
                    let mut audio_samples: Vec<f32> = Vec::new();

                    // DECODERをロックしてデコード
                    {
                        if let Ok(mut dec) = DECODER.lock() {
                            if let Some(decoder) = dec.as_mut() {
                                // 1イテレーションで最大 10 フレーム程度に制限するか、
                                // あるいはこまめに IS_PLAYING をチェックする
                                while decoder.current_pts < target_pts - 0.005 {
                                    if !IS_PLAYING.load(Ordering::SeqCst) {
                                        break;
                                    }

                                    match decoder.next_frame() {
                                        Ok(Some(pts)) => {
                                            if pts >= target_pts - 0.033 {
                                                if let Ok(mut state_lock) = RENDER_STATE.try_write()
                                                {
                                                    if let Some(state) = &mut *state_lock {
                                                        update_textures_from_decoder(
                                                            state, decoder,
                                                        );
                                                    }
                                                }
                                            }
                                        }
                                        Ok(None) => {
                                            IS_PLAYING.store(false, Ordering::SeqCst);
                                            emit_event("completed", "{}");
                                            return;
                                        }
                                        Err(e) => {
                                            eprintln!("ERROR: decoder.next_frame failed: {:?}", e);
                                            IS_PLAYING.store(false, Ordering::SeqCst);
                                            return;
                                        }
                                    }

                                    // あまりに遅れすぎている場合はスキップ
                                    if target_pts - decoder.current_pts > 0.5 {
                                        break;
                                    }
                                }
                                current_pts = decoder.current_pts;

                                audio_samples.extend(decoder.audio_buffer.drain(..));
                                if audio_samples.len() < 4800 {
                                    decoder.prefetch_audio(9600, 3);
                                    audio_samples.extend(decoder.audio_buffer.drain(..));
                                }
                            }
                        }
                    }

                    // DECODERロックを解放してからAUDIO_PLAYERに書き込む
                    if !audio_samples.is_empty() {
                        if let Ok(mut audio_lock) = AUDIO_PLAYER.lock() {
                            if let Some(audio) = &mut *audio_lock {
                                let mut leftover_start = audio_samples.len();
                                for (i, sample) in audio_samples.iter().enumerate() {
                                    if audio.producer.try_push(*sample).is_err() {
                                        leftover_start = i;
                                        break;
                                    }
                                }
                                if leftover_start < audio_samples.len() {
                                    // 書き込めなかった分をバッファに戻す
                                    if let Ok(mut dec) = DECODER.try_lock() {
                                        if let Some(decoder) = dec.as_mut() {
                                            for sample in
                                                audio_samples[leftover_start..].iter().rev()
                                            {
                                                decoder.audio_buffer.push_front(*sample);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if current_pts > 0.0 {
                        emit_event("frame", &format!("{{\"pts_sec\": {}}}", current_pts));
                    }

                    // 次のイテレーションまで少し待つ (CPU負荷軽減)
                    std::thread::sleep(std::time::Duration::from_millis(2));
                }
            });
        }
    }

    pub fn set_shader(shader: String) {
        if let Ok(mut active_lock) = ACTIVE_SHADER.write() {
            *active_lock = shader.clone();
            emit_event("shaderChanged", &format!("\"{}\"", shader));

            let intensity = SHADER_INTENSITIES
                .read()
                .ok()
                .and_then(|i| i.get(&shader).copied())
                .unwrap_or(1.0);

            if let Ok(state_lock) = RENDER_STATE.read() {
                if let Some(state) = &*state_lock {
                    state.update_intensity(intensity);
                }
            }
        }
    }

    pub fn set_shader_intensity(shader: String, intensity: f32) {
        if let Ok(mut intensities) = SHADER_INTENSITIES.write() {
            intensities.insert(shader.clone(), intensity);

            let active = ACTIVE_SHADER
                .read()
                .ok()
                .map(|s| s.clone())
                .unwrap_or_default();
            if active == shader {
                if let Ok(state_lock) = RENDER_STATE.read() {
                    if let Some(state) = &*state_lock {
                        state.update_intensity(intensity);
                    }
                }
            }
        }
    }

    pub fn get_active_shader() -> String {
        ACTIVE_SHADER
            .read()
            .ok()
            .map(|s| s.clone())
            .unwrap_or("none".to_string())
    }

    pub fn set_effect_intensity(effect: String, intensity: f32) {
        if let Ok(mut effects) = EFFECTS.write() {
            effects.insert(effect, intensity);
            let current_effects = effects.clone();
            if let Ok(state_lock) = RENDER_STATE.read() {
                if let Some(state) = &*state_lock {
                    state.update_effects(&current_effects);
                }
            }
        }
    }

    pub fn set_volume(volume: f32) {
        crate::infrastructure::state::VOLUME.store(volume.to_bits(), Ordering::SeqCst);
    }
}
