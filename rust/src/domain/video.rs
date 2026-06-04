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

use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
pub struct VideoInfo {
    pub width: u32,
    pub height: u32,
    pub duration_secs: f64,
    pub frame_rate: f64,
}

#[derive(Debug, Clone)]
pub struct Thumbnail {
    pub data: Vec<u8>,
    pub width: u32,
    pub height: u32,
}
