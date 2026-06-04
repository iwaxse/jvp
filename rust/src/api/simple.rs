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

pub use crate::domain::video::{Thumbnail, VideoInfo};
pub use crate::service::playback::emit_event;

use crate::frb_generated::StreamSink;
use crate::infrastructure::state::{ACTIVE_SHADER, RENDER_STATE};
use crate::service::playback::PlaybackService;
use once_cell::sync::Lazy;
use std::sync::Mutex;

static RENDER_FPS_COUNTER: Lazy<Mutex<(u32, std::time::Instant)>> =
    Lazy::new(|| Mutex::new((0, std::time::Instant::now())));

#[no_mangle]
pub extern "C" fn jvp_render_frame() {
    let Ok(active_shader) = ACTIVE_SHADER.read() else {
        return;
    };
    let shader = active_shader.clone();

    if let Ok(state_lock) = RENDER_STATE.read() {
        if let Some(state) = &*state_lock {
            state.render(&shader);
            if let Ok(mut counter) = RENDER_FPS_COUNTER.lock() {
                counter.0 += 1;
                let elapsed = counter.1.elapsed();
                if elapsed >= std::time::Duration::from_secs(1) {
                    let fps = counter.0 as f64 / elapsed.as_secs_f64();
                    emit_event("renderFps", &format!("{{\"fps\": {:.2}}}", fps));
                    counter.0 = 0;
                    counter.1 = std::time::Instant::now();
                }
            }
        }
    }
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    PlaybackService::init_app();
}

pub fn start_player_event_stream(sink: StreamSink<String>) {
    PlaybackService::start_player_event_stream(sink);
}

pub fn open_video(path: String) -> Result<VideoInfo, String> {
    PlaybackService::open_video(path)
}

pub fn get_thumbnail(time_sec: f64) -> Result<Thumbnail, String> {
    PlaybackService::get_thumbnail(time_sec)
}

pub fn init_texture_mode(ptr: usize, width: u32, height: u32) {
    PlaybackService::init_texture_mode(ptr, width, height);
}

pub fn update_frame() -> Result<bool, String> {
    PlaybackService::update_frame()
}

pub fn seek(time_sec: f64, accurate: bool) -> Result<(), String> {
    PlaybackService::seek(time_sec, accurate)
}

pub fn set_playing(playing: bool) {
    PlaybackService::set_playing(playing);
}

pub fn set_shader(shader: String) {
    PlaybackService::set_shader(shader);
}

pub fn set_shader_intensity(shader: String, intensity: f32) {
    PlaybackService::set_shader_intensity(shader, intensity);
}

pub fn get_active_shader() -> String {
    PlaybackService::get_active_shader()
}

pub fn set_effect_intensity(effect: String, intensity: f32) {
    PlaybackService::set_effect_intensity(effect, intensity);
}

pub fn set_volume(volume: f32) {
    PlaybackService::set_volume(volume);
}
