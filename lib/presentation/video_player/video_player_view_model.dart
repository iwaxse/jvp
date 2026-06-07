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
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../application/app_event_bus.dart';
import '../../../application/commands/open_file_command.dart';
import '../../../domain/repository/video_repository.dart';

class VideoPlayerViewModel extends ChangeNotifier {
  final VideoRepository _repository;
  final AppEventBus _eventBus;

  StreamSubscription<AppEvent>? _eventBusSubscription;

  bool _isLoaded = false;
  bool _isPlaying = false;
  bool _isLooping = false;
  bool _isAbLooping = false;
  double _durationSecs = 0.0;
  double _currentPosSecs = 0.0;
  int? _textureId;
  int _width = 0;
  int _height = 0;
  double _fps = 0.0;
  double _volume = 0.0;
  bool _isMuted = true;
  bool _isScrubbing = false;
  bool _wasPlayingBeforeScrub = false;
  double? _abLoopStartSecs;
  double? _abLoopEndSecs;
  bool _restoreLoopingAfterAbLoop = false;
  bool _isRestartingAbLoop = false;
  StreamSubscription<String>? _eventSubscription;
  double _realTimeFps = 0.0;
  String? _currentMediaPath;

  bool get isLoaded => _isLoaded;
  bool get isPlaying => _isPlaying;
  bool get isLooping => _isLooping;
  bool get isAbLooping => _isAbLooping;
  bool get isScrubbing => _isScrubbing;
  double get durationSecs => _durationSecs;
  double get currentPosSecs => _currentPosSecs;
  int? get textureId => _textureId;
  int get width => _width;
  int get height => _height;
  double get fps => _fps;
  double get realTimeFps => _realTimeFps;
  double get volume => _volume;
  bool get isMuted => _isMuted;
  bool get wasPlayingBeforeScrub => _wasPlayingBeforeScrub;
  double? get abLoopStartSecs => _abLoopStartSecs;
  double? get abLoopEndSecs => _abLoopEndSecs;
  bool get hasAbLoopRange => _abLoopStartSecs != null && _abLoopEndSecs != null;
  String? get currentMediaPath => _currentMediaPath;

  VideoPlayerViewModel(this._repository, this._eventBus) {
    _initListeners();
  }

  void _initListeners() {
    _eventSubscription = _repository.playerEventStream.listen((eventStr) {
      try {
        final parsed = jsonDecode(eventStr) as Map<String, dynamic>;
        final type = parsed['type'] as String;
        final data = parsed['data'];

        switch (type) {
          case 'metadata':
            final meta = data as Map<String, dynamic>;
            _width = meta['width'] as int;
            _height = meta['height'] as int;
            _durationSecs = (meta['duration_secs'] as num).toDouble();
            _fps = (meta['frame_rate'] as num).toDouble();
            notifyListeners();
            break;
          case 'frame':
            final frameData = data as Map<String, dynamic>;
            final pts = (frameData['pts_sec'] as num).toDouble();
            if (pts >= 0.0) {
              _eventBus.publish(PlaybackPositionEvent(pts));
              _handleAbLoopFrame(pts);
            }
            break;
          case 'renderFps':
            final fpsData = data as Map<String, dynamic>;
            _realTimeFps = (fpsData['fps'] as num).toDouble();
            notifyListeners();
            break;
          case 'playingState':
            _isPlaying = data as bool;
            _eventBus.publish(PlaybackStateEvent(_isPlaying));
            notifyListeners();
            break;
          case 'completed':
            _handleCompleted();
            break;
        }
      } catch (e) {
        debugPrint('Error parsing player event: $e');
      }
    });

    _eventBusSubscription = _eventBus.stream.listen((event) async {
      if (event is VideoLoadedEvent) {
        _textureId = event.textureId;
        _width = event.width;
        _height = event.height;
        _durationSecs = event.durationSecs;
        _currentMediaPath = event.sourcePath;
        _isLoaded = true;
        _currentPosSecs = 0.0;
        _isAbLooping = false;
        _abLoopStartSecs = null;
        _abLoopEndSecs = null;
        _restoreLoopingAfterAbLoop = false;
        notifyListeners();
      } else if (event is VideoUnloadedEvent) {
        _isLoaded = false;
        _isPlaying = false;
        _textureId = null;
        _isAbLooping = false;
        _abLoopStartSecs = null;
        _abLoopEndSecs = null;
        _restoreLoopingAfterAbLoop = false;
        notifyListeners();
      } else if (event is PlaybackPositionEvent) {
        _currentPosSecs = event.position;
        notifyListeners();
      } else if (event is PlaybackStateEvent) {
        _isPlaying = event.isPlaying;
        notifyListeners();
      } else if (event is LoopingStateEvent) {
        _isLooping = event.isLooping;
        notifyListeners();
      } else if (event is ABLoopStateEvent) {
        _isAbLooping = event.isEnabled;
        if (_isAbLooping) {
          _restoreLoopingAfterAbLoop = event.restoreLooping ?? _isLooping;
          _isLooping = false;
          // Initialize A-B loop range to [0, duration]
          _abLoopStartSecs = 0.0;
          _abLoopEndSecs = _durationSecs;
        } else {
          _isLooping = _restoreLoopingAfterAbLoop;
          _abLoopStartSecs = null;
          _abLoopEndSecs = null;
        }
        notifyListeners();
      } else if (event is ABLoopRangeEvent) {
        _abLoopStartSecs = event.startSecs;
        _abLoopEndSecs = event.endSecs;
        notifyListeners();
      } else if (event is MuteStateEvent) {
        _isMuted = event.isMuted;
        _volume = event.volume;
        notifyListeners();
      } else if (event is ScrubbingStateEvent) {
        _isScrubbing = event.isScrubbing;
        _wasPlayingBeforeScrub = event.wasPlayingBeforeScrub;
        notifyListeners();
      }
    });
  }

  Future<void> _handleCompleted() async {
    if (_isScrubbing) return;
    if (_isAbLooping && hasAbLoopRange) {
      await _restartAbLoop();
      return;
    }
    if (_isLooping) {
      await _repository.seek(0.0, accurate: true);
      await _repository.updateTexture();
      await _repository.setPlaying(true);
      _eventBus.publish(PlaybackStateEvent(true));
      notifyListeners();
      return;
    }
    _eventBus.publish(PlaybackCompletedEvent());
  }

  void _handleAbLoopFrame(double position) {
    if (!_isAbLooping ||
        !hasAbLoopRange ||
        _isScrubbing ||
        _isRestartingAbLoop) {
      return;
    }
    final endSecs = _abLoopEndSecs!;
    if (position < (endSecs - 0.01)) {
      return;
    }
    unawaited(_restartAbLoop());
  }

  Future<void> _restartAbLoop() async {
    if (_isRestartingAbLoop || _abLoopStartSecs == null) return;
    _isRestartingAbLoop = true;
    try {
      final startSecs = _abLoopStartSecs!;
      await _repository.seek(startSecs, accurate: true);
      await _repository.updateTexture();
      await _repository.setPlaying(true);
      _eventBus.publish(PlaybackPositionEvent(startSecs));
      _eventBus.publish(PlaybackStateEvent(true));
    } finally {
      _isRestartingAbLoop = false;
    }
  }

  Future<void> openMediaFile(String path) async {
    _eventBus.publish(OpenFileCommand(path, volume: volume, autoplay: true));
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _eventBusSubscription?.cancel();
    super.dispose();
  }
}

class PlaybackCompletedEvent extends AppEvent {}
