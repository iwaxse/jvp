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

use crate::infrastructure::audio::AudioPlayer;
use crate::infrastructure::decoder::VideoDecoder;
use crate::infrastructure::renderer::RenderState;
use once_cell::sync::Lazy;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU32};
use std::sync::{Mutex, RwLock};

pub static DECODER: Lazy<Mutex<Option<VideoDecoder>>> = Lazy::new(|| Mutex::new(None));
pub static THUMBNAIL_DECODER: Lazy<Mutex<Option<VideoDecoder>>> = Lazy::new(|| Mutex::new(None));
pub static IS_PLAYING: Lazy<AtomicBool> = Lazy::new(|| AtomicBool::new(false));
pub static VOLUME: Lazy<AtomicU32> = Lazy::new(|| AtomicU32::new(0.0f32.to_bits()));

// レンダリング状態（wgpuリソース）を独立
pub static RENDER_STATE: Lazy<RwLock<Option<RenderState>>> = Lazy::new(|| {
    let state = pollster::block_on(async { RenderState::new().await });
    RwLock::new(state)
});

// エフェクト設定などを独立
pub static ACTIVE_SHADER: Lazy<RwLock<String>> = Lazy::new(|| RwLock::new("none".to_string()));
pub static EFFECTS: Lazy<RwLock<HashMap<String, f32>>> = Lazy::new(|| {
    let mut effects = HashMap::new();
    effects.insert("smooth".to_string(), 0.0);
    effects.insert("blur".to_string(), 0.0);
    effects.insert("sharpen".to_string(), 0.0);
    effects.insert("unsharp".to_string(), 0.0);
    effects.insert("hdr".to_string(), 0.0);
    effects.insert("vintage".to_string(), 0.0);
    effects.insert("cyberpunk".to_string(), 0.0);
    effects.insert("cleancinema".to_string(), 0.0);
    effects.insert("vignette".to_string(), 0.0);
    effects.insert("super_res".to_string(), 0.0);
    effects.insert("deband".to_string(), 0.0);
    effects.insert("bloom".to_string(), 0.0);
    effects.insert("sharpen_type".to_string(), 0.0);
    effects.insert("width".to_string(), 1280.0);
    effects.insert("height".to_string(), 720.0);
    RwLock::new(effects)
});

pub static SHADER_INTENSITIES: Lazy<RwLock<HashMap<String, f32>>> = Lazy::new(|| {
    let mut intensities = HashMap::new();
    intensities.insert("none".to_string(), 1.0);
    RwLock::new(intensities)
});

pub static AUDIO_SAMPLE_RATE: Lazy<std::sync::atomic::AtomicU32> =
    Lazy::new(|| std::sync::atomic::AtomicU32::new(48000));

pub static AUDIO_PLAYER: Lazy<Mutex<Option<AudioPlayer>>> =
    Lazy::new(|| Mutex::new(AudioPlayer::new().ok()));
