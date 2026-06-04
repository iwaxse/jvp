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

class OpenFileAction extends AppEvent {
  final String filePath;
  OpenFileAction(this.filePath);
}

class TogglePlayAction extends AppEvent {}

class ToggleLoopingAction extends AppEvent {}

class ToggleMuteAction extends AppEvent {}

class SetVolumeAction extends AppEvent {
  final double volume;
  SetVolumeAction(this.volume);
}

class ChangeShaderAction extends AppEvent {
  final String shader;
  ChangeShaderAction(this.shader);
}

class SetShaderIntensityAction extends AppEvent {
  final String shader;
  final double value;
  SetShaderIntensityAction(this.shader, this.value);
}

class StartScrubbingAction extends AppEvent {}

class UpdateScrubValueAction extends AppEvent {
  final double seconds;
  UpdateScrubValueAction(this.seconds);
}

class EndScrubbingAction extends AppEvent {
  final double seconds;
  EndScrubbingAction(this.seconds);
}

class VideoLoadedEvent extends AppEvent {
  final int textureId;
  final int width;
  final int height;
  final double durationSecs;
  VideoLoadedEvent({
    required this.textureId,
    required this.width,
    required this.height,
    required this.durationSecs,
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

class MuteStateEvent extends AppEvent {
  final bool isMuted;
  final double volume;
  MuteStateEvent({required this.isMuted, required this.volume});
}

class ShaderStateEvent extends AppEvent {
  final String activeShader;
  final Map<String, double> intensities;
  ShaderStateEvent({required this.activeShader, required this.intensities});
}

class ToggleTunerAction extends AppEvent {}
