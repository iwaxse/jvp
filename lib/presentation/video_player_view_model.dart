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
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import '../../application/app_event_bus.dart';
import '../../application/usecase/get_thumbnail_usecase.dart';
import '../../domain/models/video_models.dart';
import '../../domain/repository/video_repository.dart';

class VideoPlayerViewModel extends ChangeNotifier {
  final VideoRepository _repository;
  final AppEventBus _eventBus;
  final GetThumbnailUseCase _getThumbnailUseCase;
  StreamSubscription<AppEvent>? _eventBusSubscription;

  bool _isLoaded = false;
  bool _isPlaying = false;
  bool _isLooping = false;
  double _durationSecs = 0.0;
  double _currentPosSecs = 0.0;
  int? _textureId;
  int _width = 0;
  int _height = 0;
  double _fps = 0.0;
  double _volume = 0.0;
  bool _isMuted = true;

  bool _wasPlayingBeforeScrub = false;
  StreamSubscription<String>? _eventSubscription;
  double _realTimeFps = 0.0;
  bool get isLoaded => _isLoaded;
  bool get isPlaying => _isPlaying;
  bool get isLooping => _isLooping;
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

  VideoPlayerViewModel(this._repository, this._eventBus)
    : _getThumbnailUseCase = GetThumbnailUseCase(_repository) {
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
            _eventBus.publish(
              VideoLoadedEvent(
                textureId: _textureId ?? 0,
                width: _width,
                height: _height,
                durationSecs: _durationSecs,
              ),
            );
            notifyListeners();
            break;
          case 'frame':
            final frameData = data as Map<String, dynamic>;
            final pts = (frameData['pts_sec'] as num).toDouble();
            if (pts >= 0.0) {
              _eventBus.publish(PlaybackPositionEvent(pts));
            }
            notifyListeners();
            break;
          case 'renderFps':
            final fpsData = data as Map<String, dynamic>;
            _realTimeFps = (fpsData['fps'] as num).toDouble();
            notifyListeners();
            break;
          case 'playingState':
            _isPlaying = data as bool;
            _eventBus.publish(PlaybackStateEvent(_isPlaying));
            _isPlaying ? _startPlaybackTimer() : _playbackTimer?.cancel();
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
      if (event is AppCommand) {
        try {
          await event.execute(_repository, _eventBus);
        } catch (e) {
          debugPrint("Error executing command: $e");
        }
      } else if (event is VideoLoadedEvent) {
        _textureId = event.textureId;
        _width = event.width;
        _height = event.height;
        _durationSecs = event.durationSecs;
        _isLoaded = true;
        _currentPosSecs = 0.0;
        notifyListeners();
      } else if (event is VideoUnloadedEvent) {
        _isLoaded = false;
        _isPlaying = false;
        _textureId = null;
        notifyListeners();
      } else if (event is PlaybackPositionEvent) {
        _currentPosSecs = event.position;
        notifyListeners();
      } else if (event is PlaybackStateEvent) {
        _isPlaying = event.isPlaying;
        _isPlaying ? _startPlaybackTimer() : _playbackTimer?.cancel();
        notifyListeners();
      } else if (event is LoopingStateEvent) {
        _isLooping = event.isLooping;
        notifyListeners();
      } else if (event is MuteStateEvent) {
        _isMuted = event.isMuted;
        _volume = event.volume;
        notifyListeners();
      } else if (event is ScrubbingStateEvent) {
        _wasPlayingBeforeScrub = event.wasPlayingBeforeScrub;
        notifyListeners();
      } else if (event is EffectStateEvent) {
        _effects[event.effect] = event.intensity;
        notifyListeners();
      }
    });
  }

  Future<void> _handleCompleted() async {
    if (_isLooping) {
      await _repository.seek(0.0, accurate: true);
      await _repository.updateTexture();
      await _repository.setPlaying(true);
      _eventBus.publish(PlaybackPositionEvent(0.0));
      _eventBus.publish(PlaybackStateEvent(true));
    } else {
      _isPlaying = false;
      await _repository.seek(0.0, accurate: true);
      await _repository.updateTexture();
      _eventBus.publish(PlaybackPositionEvent(0.0));
      _eventBus.publish(PlaybackStateEvent(false));
    }
    notifyListeners();
  }

  Timer? _playbackTimer;

  void _startPlaybackTimer() {
    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 33), (
      timer,
    ) async {
      if (!_isPlaying || !_isLoaded) {
        timer.cancel();
        return;
      }
      try {
        final ok = await _repository.updateFrame();
        if (!ok) {
          timer.cancel();
          await _repository.setPlaying(false);
          _eventBus.publish(PlaybackStateEvent(false));
        }
      } catch (e) {
        debugPrint("Error updating frame: $e");
      }
    });
  }

  Future<Thumbnail?> getThumbnail(double seconds) async {
    if (!_isLoaded) return null;
    try {
      return await _getThumbnailUseCase.getThumbnail(seconds);
    } catch (e) {
      debugPrint('Failed to get thumbnail: $e');
      return null;
    }
  }

  Future<ui.Image?> getThumbnailImage(double seconds) async {
    final thumb = await getThumbnail(seconds);
    if (thumb == null) return null;
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      thumb.data,
      thumb.width,
      thumb.height,
      ui.PixelFormat.rgba8888,
      (ui.Image img) {
        completer.complete(img);
      },
    );
    return completer.future;
  }

  final Map<String, double> _effects = {
    'smooth': 0.0,
    'blur': 0.0,
    'sharpen': 0.0,
    'unsharp': 0.0,
    'hdr': 0.0,
    'vintage': 0.0,
    'cyberpunk': 0.0,
    'cleancinema': 0.0,
    'vignette': 0.0,
    'super_res': 0.0,
    'deband': 0.0,
    'bloom': 0.0,
    'sharpen_type': 0.0,
  };

  double getEffect(String key) => _effects[key] ?? 0.0;

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _eventSubscription?.cancel();
    _eventBusSubscription?.cancel();
    super.dispose();
  }
}
