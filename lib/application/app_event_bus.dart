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

import 'dart:async';
import '../domain/repository/video_repository.dart';

abstract class AppEvent {
  final DateTime timestamp = DateTime.now();
}

class AppEventBus {
  final _controller = StreamController<AppEvent>.broadcast();

  Stream<AppEvent> get stream => _controller.stream;

  Stream<T> on<T extends AppEvent>() =>
      _controller.stream.where((event) => event is T).cast<T>();

  void publish(AppEvent event) {
    _controller.add(event);
  }

  void dispose() {
    _controller.close();
  }
}

abstract class AppCommand extends AppEvent {
  Future<void> execute(VideoRepository repository, AppEventBus eventBus);
}

class VideoLoadedEvent extends AppEvent {
  final int textureId;
  final int width;
  final int height;
  final double durationSecs;
  final String sourcePath;
  VideoLoadedEvent({
    required this.textureId,
    required this.width,
    required this.height,
    required this.durationSecs,
    required this.sourcePath,
  });
}

class VideoUnloadedEvent extends AppEvent {}

class PlaybackPositionEvent extends AppEvent {
  final double position;
  PlaybackPositionEvent(this.position);
}

class PlaybackStateEvent extends AppEvent {
  final bool isPlaying;
  PlaybackStateEvent(this.isPlaying);
}

class LoopingStateEvent extends AppEvent {
  final bool isLooping;
  LoopingStateEvent(this.isLooping);
}

class ABLoopStateEvent extends AppEvent {
  final bool isEnabled;
  final bool? restoreLooping;

  ABLoopStateEvent({required this.isEnabled, this.restoreLooping});
}

class ABLoopRangeEvent extends AppEvent {
  final double? startSecs;
  final double? endSecs;

  ABLoopRangeEvent({required this.startSecs, required this.endSecs});
}

class MuteStateEvent extends AppEvent {
  final bool isMuted;
  final double volume;
  MuteStateEvent({required this.isMuted, required this.volume});
}

class ToggleTunerAction extends AppEvent {}

class ScrubbingStateEvent extends AppEvent {
  final bool isScrubbing;
  final bool wasPlayingBeforeScrub;
  ScrubbingStateEvent({
    required this.isScrubbing,
    required this.wasPlayingBeforeScrub,
  });
}

class EffectStateEvent extends AppEvent {
  final String effect;
  final double intensity;
  EffectStateEvent({required this.effect, required this.intensity});
}
