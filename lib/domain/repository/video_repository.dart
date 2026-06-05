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

import '../models/video_models.dart';

abstract class VideoRepository {
  Stream<String> get playerEventStream;
  Future<VideoInfo> openVideo(String path);
  Future<Map<String, dynamic>?> initTexture(int width, int height);
  Future<void> initTextureMode(BigInt ptr, int width, int height);
  Future<void> updateTexture();
  Future<void> setPlaying(bool playing);
  Future<void> seek(double timeSec, {bool accurate});
  Future<Thumbnail?> getThumbnail(double timeSec);
  Future<void> setEffectIntensity(String effect, double intensity);
  Future<void> setVolume(double volume);
  Future<void> setShader(String shader);
  Future<void> setShaderIntensity(String shader, double intensity);
}
