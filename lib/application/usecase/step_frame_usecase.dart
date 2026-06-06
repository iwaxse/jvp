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
import '../../../domain/models/video_models.dart';
import '../../../domain/repository/video_repository.dart';

class StepFrameUseCase extends AppCommand {
  final int frames;
  final bool currentIsPlaying;
  final double currentPosSecs;
  final double fps;
  final double durationSecs;

  StepFrameUseCase({
    required this.frames,
    required this.currentIsPlaying,
    required this.currentPosSecs,
    required this.fps,
    required this.durationSecs,
  });

  @override
  Future<void> execute(VideoRepository repository, AppEventBus eventBus) async {
    if (currentIsPlaying) {
      await repository.setPlaying(false);
      eventBus.publish(PlaybackStateEvent(false));
    }
    final info = VideoInfo(
      width: 0,
      height: 0,
      durationSecs: durationSecs,
      frameRate: fps,
    );
    final target = info.calculateTargetPosition(currentPosSecs, frames);
    eventBus.publish(PlaybackPositionEvent(target));
    await repository.seek(target, accurate: true);
    await repository.updateTexture();
  }
}
