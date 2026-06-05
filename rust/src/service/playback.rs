use crate::domain::video::{Thumbnail, VideoInfo};
use crate::frb_generated::StreamSink;
use crate::infrastructure::decoder::VideoDecoder;
use crate::infrastructure::state::{
    ACTIVE_SHADER, DECODER, EFFECTS, IS_PLAYING, RENDER_STATE, SHADER_INTENSITIES,
    THUMBNAIL_DECODER,
};
use once_cell::sync::Lazy;
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
    #[cfg(target_os = "macos")]
    {
        if let Some(cv_buf) = cv_buf_opt {
            let _ = state.update_input_from_cv_buffer(cv_buf);
        }
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
        let _ = decoder.next_frame();

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

            if let Ok(mut dec_lock) = DECODER.lock() {
                if let Some(decoder) = dec_lock.as_mut() {
                    decoder.set_texture_id(ptr as i64);
                }
            }

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

    pub fn seek(time_sec: f64, _accurate: bool) -> Result<(), String> {
        let mut dec = DECODER.lock().map_err(|e| e.to_string())?;
        let decoder = match dec.as_mut() {
            Some(d) => d,
            None => return Ok(()),
        };

        if let Ok(mut state_lock) = RENDER_STATE.write() {
            if let Some(state) = &mut *state_lock {
                state.resize_input_texture(decoder.width, decoder.height);
            }
        }

        decoder.seek(time_sec, false).map_err(|e| e.to_string())?;
        let _ = decoder.next_frame();

        if let Ok(mut state_lock) = RENDER_STATE.write() {
            if let Some(state) = &mut *state_lock {
                update_textures_from_decoder(state, decoder);
            }
        }

        emit_event("frame", &format!("{{\"pts_sec\": {}}}", time_sec));
        Ok(())
    }

    pub fn set_playing(playing: bool) {
        IS_PLAYING.store(playing, Ordering::SeqCst);
        let playing_str = if playing { "true" } else { "false" };
        emit_event("playingState", playing_str);

        if let Ok(mut dec) = DECODER.lock() {
            if let Some(decoder) = dec.as_mut() {
                if playing {
                    decoder.play();
                } else {
                    decoder.pause();
                }
            }
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
        if let Ok(mut dec) = DECODER.lock() {
            if let Some(decoder) = dec.as_mut() {
                decoder.set_volume(volume);
            }
        }
    }
}
