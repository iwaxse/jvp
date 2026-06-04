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

use crate::infrastructure::state::VOLUME;
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use ringbuf::{storage::Heap, traits::*, SharedRb};
use std::sync::atomic::Ordering;
use std::sync::Arc;

// cpal::Stream は !Send なので、macOSでの安全性を考慮しつつラップする
#[allow(dead_code)]
pub struct SendStream(cpal::Stream);
unsafe impl Send for SendStream {}
unsafe impl Sync for SendStream {}

pub struct AudioPlayer {
    _stream: SendStream,
    // トレイトの関連型を使って、具体的な内部型を引っ張ってくるよ
    pub producer: <Arc<SharedRb<Heap<f32>>> as Split>::Prod,
}

impl AudioPlayer {
    pub fn new() -> Result<Self, String> {
        let host = cpal::default_host();
        let device = host
            .default_output_device()
            .ok_or("No output device found")?;
        let config = device.default_output_config().map_err(|e| e.to_string())?;
        let sample_rate = config.sample_rate().0;
        crate::infrastructure::state::AUDIO_SAMPLE_RATE.store(sample_rate, Ordering::SeqCst);

        let rb = Arc::new(SharedRb::<Heap<f32>>::new((sample_rate * 4) as usize));
        let (prod, mut cons) = rb.split();

        let stream = device
            .build_output_stream(
                &config.into(),
                move |data: &mut [f32], _: &cpal::OutputCallbackInfo| {
                    // 再生直前に最新の音量を取得して適用
                    let volume = f32::from_bits(VOLUME.load(Ordering::Relaxed));
                    for sample in data.iter_mut() {
                        *sample = cons.try_pop().unwrap_or(0.0) * volume;
                    }
                },
                |err| eprintln!("Audio stream error: {}", err),
                None,
            )
            .map_err(|e| e.to_string())?;

        stream.play().map_err(|e| e.to_string())?;

        Ok(Self {
            _stream: SendStream(stream),
            producer: prod,
        })
    }
}
