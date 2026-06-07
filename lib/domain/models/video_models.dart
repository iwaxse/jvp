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

import 'dart:typed_data';

class VideoInfo {
  final int width;
  final int height;
  final double durationSecs;
  final double frameRate;

  const VideoInfo({
    required this.width,
    required this.height,
    required this.durationSecs,
    required this.frameRate,
  });

  double get frameDuration => frameRate > 0 ? (1.0 / frameRate) : (1.0 / 30.0);

  double calculateTargetPosition(double currentPosSecs, int frames) {
    return (currentPosSecs + frames * frameDuration)
        .clamp(0.0, durationSecs)
        .toDouble();
  }
}

class Thumbnail {
  final Uint8List data;
  final int width;
  final int height;

  const Thumbnail({
    required this.data,
    required this.width,
    required this.height,
  });
}

class MediaFileEntry {
  final String path;
  final String displayName;
  final String directoryPath;

  const MediaFileEntry({
    required this.path,
    required this.displayName,
    required this.directoryPath,
  });
}
