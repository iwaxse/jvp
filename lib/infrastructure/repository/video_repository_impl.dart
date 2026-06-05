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

import 'package:flutter/services.dart';
import '../../domain/models/video_models.dart';
import '../../domain/repository/video_repository.dart';
import '../../infrastructure/adapter/rust/generated/api/simple.dart' as rust;

class VideoRepositoryImpl implements VideoRepository {
  static const _channel = MethodChannel('com.iwaxse.jvp/texture');

  @override
  Stream<String> get playerEventStream => rust.startPlayerEventStream();

  @override
  Future<VideoInfo> openVideo(String path) async {
    final info = await rust.openVideo(path: path);
    return VideoInfo(
      width: info.width,
      height: info.height,
      durationSecs: info.durationSecs,
      frameRate: info.frameRate,
    );
  }

  @override
  Future<Map<String, dynamic>?> initTexture(int width, int height) async {
    final result = await _channel.invokeMethod('initTexture', {
      'width': width,
      'height': height,
    });
    if (result == null) return null;
    return Map<String, dynamic>.from(result);
  }

  @override
  Future<void> initTextureMode(BigInt ptr, int width, int height) async {
    await rust.initTextureMode(ptr: ptr, width: width, height: height);
  }

  @override
  Future<void> updateTexture() async {
    await _channel.invokeMethod('updateTexture');
  }

  @override
  Future<void> setPlaying(bool playing) async {
    await rust.setPlaying(playing: playing);
  }

  @override
  Future<void> seek(double timeSec, {bool accurate = true}) async {
    await rust.seek(timeSec: timeSec, accurate: accurate);
  }

  @override
  Future<Thumbnail?> getThumbnail(double timeSec) async {
    final thumb = await rust.getThumbnail(timeSec: timeSec);
    return Thumbnail(
      data: thumb.data,
      width: thumb.width,
      height: thumb.height,
    );
  }

  @override
  Future<void> setEffectIntensity(String effect, double intensity) async {
    await rust.setEffectIntensity(effect: effect, intensity: intensity);
  }

  @override
  Future<void> setVolume(double volume) async {
    await rust.setVolume(volume: volume);
  }
}
