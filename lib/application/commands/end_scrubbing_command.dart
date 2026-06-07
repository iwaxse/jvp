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

class EndScrubbingCommand extends AppCommand {
  final double seconds;
  final double durationSecs;
  final bool wasPlayingBeforeScrub;
  final bool isAbLooping;
  final double? currentAbLoopStartSecs;
  final double? currentAbLoopEndSecs;

  EndScrubbingCommand({
    required this.seconds,
    required this.durationSecs,
    required this.wasPlayingBeforeScrub,
    required this.isAbLooping,
    required this.currentAbLoopStartSecs,
    required this.currentAbLoopEndSecs,
  });

  @override
  Future<void> execute(VideoRepository repository, AppEventBus eventBus) async {
    final clampedSeconds = seconds.clamp(0.0, durationSecs - 0.01).toDouble();
    eventBus.publish(PlaybackPositionEvent(clampedSeconds));
    eventBus.publish(
      ScrubbingStateEvent(isScrubbing: false, wasPlayingBeforeScrub: false),
    );
    await repository.seek(clampedSeconds, accurate: true);
    await repository.updateTexture();

    if (isAbLooping) {
      if (currentAbLoopStartSecs == null) {
        eventBus.publish(
          ABLoopRangeEvent(startSecs: clampedSeconds, endSecs: null),
        );
      } else if (currentAbLoopEndSecs == null) {
        final startSecs = currentAbLoopStartSecs!;
        var start = clampedSeconds < startSecs ? clampedSeconds : startSecs;
        var end = clampedSeconds < startSecs ? startSecs : clampedSeconds;
        const minGapSecs = 0.05;
        if ((end - start) < minGapSecs) {
          end = (start + minGapSecs).clamp(0.0, durationSecs - 0.01).toDouble();
          start = (end - minGapSecs).clamp(0.0, end).toDouble();
        }
        eventBus.publish(ABLoopRangeEvent(startSecs: start, endSecs: end));
      }
    }

    if (wasPlayingBeforeScrub) {
      await repository.setPlaying(true);
      eventBus.publish(PlaybackStateEvent(true));
    }
  }
}
