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
import '../../domain/models/video_models.dart';
import '../../domain/repository/video_repository.dart';
import '../../infrastructure/adapter/rust/generated/api/simple.dart' as rust;

class VideoPlayerViewModel extends ChangeNotifier {
  final VideoRepository _repository;
  final AppEventBus _eventBus;

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

  bool _isScrubbing = false;
  bool _wasPlayingBeforeScrub = false;
  bool _isSeeking = false;
  double? _pendingSeekSecs;
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

  VideoPlayerViewModel(this._repository, this._eventBus) {
    _initEventStream();
    _initActionListeners();
  }

  void _initActionListeners() {
    _eventBus.on<OpenFileAction>().listen((e) => openFile(e.filePath));
    _eventBus.on<TogglePlayAction>().listen((e) => togglePlay());
    _eventBus.on<ToggleLoopingAction>().listen((e) => toggleLooping());
    _eventBus.on<ToggleMuteAction>().listen((e) => toggleMute());
    _eventBus.on<SetVolumeAction>().listen((e) => setVolume(e.volume));
    _eventBus.on<StartScrubbingAction>().listen((e) => startScrubbing());
    _eventBus.on<UpdateScrubValueAction>().listen(
      (e) => updateScrubValue(e.seconds),
    );
    _eventBus.on<EndScrubbingAction>().listen((e) => endScrubbing(e.seconds));
  }

  void _initEventStream() {
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
            _isLoaded = true;
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
              _currentPosSecs = pts;
              _eventBus.publish(PlaybackPositionEvent(_currentPosSecs));
            }
            _repository.updateTexture();
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
            notifyListeners();
            break;
          case 'completed':
            if (_isLooping) {
              seekTo(0.0);
              play();
            } else {
              _isPlaying = false;
              seekTo(0.0);
              _eventBus.publish(PlaybackStateEvent(false));
            }
            notifyListeners();
            break;
        }
      } catch (e) {
        debugPrint('Error parsing player event: $e');
      }
    });
  }

  Future<void> openFile(String filePath) async {
    try {
      _stopPlayback();
      final info = await _repository.openVideo(filePath);
      await _repository.setVolume(_isMuted ? 0.0 : _volume);

      final result = await _repository.initTexture(info.width, info.height);
      if (result != null) {
        _textureId = result['textureId'] as int;
        final ptrVal = result['ptr'] as int;
        final ptr = BigInt.from(ptrVal);
        await _repository.initTextureMode(ptr, info.width, info.height);
      }
      _isLoaded = true;
      _currentPosSecs = 0.0;
      _eventBus.publish(
        VideoLoadedEvent(
          textureId: _textureId ?? 0,
          width: info.width,
          height: info.height,
          durationSecs: info.durationSecs,
        ),
      );
      notifyListeners();
      await play();
    } catch (e, stack) {
      debugPrint("ERROR Dart: Exception in openFile: $e\n$stack");
    }
  }

  Timer? _playbackTimer;

  Future<void> play() async {
    if (!_isLoaded) return;
    await _repository.setPlaying(true);
    _isPlaying = true;
    _eventBus.publish(PlaybackStateEvent(true));
    _startPlaybackTimer();
    notifyListeners();
  }

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
        final ok = await rust.updateFrame();
        if (!ok) {
          timer.cancel();
          await pause();
        }
      } catch (e) {
        debugPrint("Error updating frame: $e");
      }
    });
  }

  Future<void> pause() async {
    if (!_isLoaded) return;
    _playbackTimer?.cancel();
    await _repository.setPlaying(false);
    _isPlaying = false;
    _eventBus.publish(PlaybackStateEvent(false));
    notifyListeners();
  }

  Future<void> togglePlay() async {
    if (_isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  void toggleLooping() {
    _isLooping = !_isLooping;
    _eventBus.publish(LoopingStateEvent(_isLooping));
    notifyListeners();
  }

  void startScrubbing() {
    if (!_isLoaded) return;
    _isScrubbing = true;
    _wasPlayingBeforeScrub = _isPlaying;
    if (_isPlaying) {
      pause();
      _isPlaying = true;
    }
  }

  void updateScrubValue(double seconds) {
    if (!_isLoaded) return;
    _currentPosSecs = seconds;
    _pendingSeekSecs = seconds;
    _eventBus.publish(PlaybackPositionEvent(_currentPosSecs));
    notifyListeners();
    _triggerSeek();
  }

  Future<void> _triggerSeek() async {
    if (_isSeeking || _pendingSeekSecs == null) return;
    _isSeeking = true;
    while (_pendingSeekSecs != null) {
      final target = _pendingSeekSecs!;
      _pendingSeekSecs = null;
      await _repository.seek(target, accurate: !_isScrubbing);
      await _repository.updateTexture();
      notifyListeners();
    }
    _isSeeking = false;
  }

  Future<void> endScrubbing(double seconds) async {
    if (!_isLoaded) return;
    _pendingSeekSecs = null;
    _isScrubbing = false;
    await seekTo(seconds);
    if (_wasPlayingBeforeScrub) {
      await play();
    }
  }

  Future<void> seekTo(double seconds) async {
    if (!_isLoaded) return;
    _currentPosSecs = seconds;
    _eventBus.publish(PlaybackPositionEvent(_currentPosSecs));
    await _repository.seek(seconds, accurate: true);
    await _repository.updateTexture();
    notifyListeners();
  }

  Future<Thumbnail?> getThumbnail(double seconds) async {
    if (!_isLoaded) return null;
    try {
      return await _repository.getThumbnail(seconds);
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

  Future<void> setEffect(String key, double value) async {
    _effects[key] = value;
    notifyListeners();
    await _repository.setEffectIntensity(key, value);
    await _repository.updateTexture();
  }

  void setVolume(double val) {
    _volume = val;
    _isMuted = _volume <= 0.0;
    _repository.setVolume(_isMuted ? 0.0 : _volume);
    _eventBus.publish(MuteStateEvent(isMuted: _isMuted, volume: _volume));
    notifyListeners();
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    _volume = _isMuted ? 0.0 : 0.5;
    _repository.setVolume(_isMuted ? 0.0 : _volume);
    _eventBus.publish(MuteStateEvent(isMuted: _isMuted, volume: _volume));
    notifyListeners();
  }

  void _stopPlayback() {
    _playbackTimer?.cancel();
    _isLoaded = false;
    _isPlaying = false;
    _textureId = null;
    _eventBus.publish(VideoUnloadedEvent());
    notifyListeners();
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _eventSubscription?.cancel();
    super.dispose();
  }
}
