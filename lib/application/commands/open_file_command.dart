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

import '../app_event_bus.dart';
import '../../../domain/repository/video_repository.dart';

class OpenFileCommand extends AppCommand {
  final String filePath;
  final double volume;
  final bool autoplay;

  OpenFileCommand(this.filePath, {required this.volume, this.autoplay = false});

  @override
  Future<void> execute(VideoRepository repository, AppEventBus eventBus) async {
    final info = await repository.openVideo(filePath);
    await repository.setVolume(volume);

    final result = await repository.initTexture(info.width, info.height);
    if (result != null) {
      final textureId = result['textureId'] as int;
      final ptrVal = result['ptr'] as int;
      final ptr = BigInt.from(ptrVal);
      await repository.initTextureMode(ptr, info.width, info.height);

      eventBus.publish(
        VideoLoadedEvent(
          textureId: textureId,
          width: info.width,
          height: info.height,
          durationSecs: info.durationSecs,
          sourcePath: filePath,
        ),
      );
      await repository.setPlaying(false);
      eventBus.publish(PlaybackStateEvent(false));
      await repository.seek(0.0, accurate: true);
      await repository.updateTexture();
      if (autoplay) {
        await repository.setPlaying(true);
        eventBus.publish(PlaybackStateEvent(true));
      }
    }
  }
}
