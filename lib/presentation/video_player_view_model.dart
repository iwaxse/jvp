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
import '../../application/usecase/open_file_usecase.dart';
import '../../application/usecase/get_thumbnail_usecase.dart';
import '../../application/usecase/play_next_track_usecase.dart';
import '../../application/usecase/add_playlist_entry_usecase.dart';
import '../../application/usecase/remove_playlist_entry_usecase.dart';
import '../../application/usecase/clear_playlist_usecase.dart';
import '../../domain/models/video_models.dart';
import '../../domain/repository/video_repository.dart';
import '../../domain/repository/playlist_repository.dart';

class VideoPlayerViewModel extends ChangeNotifier {
  final VideoRepository _repository;
  final PlaylistRepository _playlistRepository;
  final AppEventBus _eventBus;
  final GetThumbnailUseCase _getThumbnailUseCase;
  final PlayNextTrackUseCase _playNextTrackUseCase;
  final AddPlaylistEntryUseCase _addPlaylistEntryUseCase;
  final RemovePlaylistEntryUseCase _removePlaylistEntryUseCase;
  final ClearPlaylistUseCase _clearPlaylistUseCase;

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
  bool _isMediaLibraryLoading = false;
  String? _mediaLibraryError;
  List<String> _mediaSearchRoots = [];
  List<MediaFileEntry> _mediaFiles = [];
  List<MediaFileEntry> _playlist = [];
  String? _currentMediaPath;
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
  bool get isMediaLibraryLoading => _isMediaLibraryLoading;
  String? get mediaLibraryError => _mediaLibraryError;
  List<String> get mediaSearchRoots => List.unmodifiable(_mediaSearchRoots);
  List<MediaFileEntry> get mediaFiles => List.unmodifiable(_mediaFiles);
  List<MediaFileEntry> get playlist => List.unmodifiable(_playlist);
  String? get currentMediaPath => _currentMediaPath;
  int? get currentPlaylistIndex {
    final path = _currentMediaPath;
    if (path == null) return null;
    final index = _playlist.indexWhere((item) => item.path == path);
    return index >= 0 ? index : null;
  }

  final Map<int, ui.Image> _thumbnailCache = {};
  final List<int> _thumbnailCacheKeys = [];
  static const int _maxCacheSize = 30;

  void _clearThumbnailCache() {
    for (final img in _thumbnailCache.values) {
      img.dispose();
    }
    _thumbnailCache.clear();
    _thumbnailCacheKeys.clear();
  }

  VideoPlayerViewModel(
    this._repository,
    this._playlistRepository,
    this._eventBus,
  ) : _getThumbnailUseCase = GetThumbnailUseCase(_repository),
      _playNextTrackUseCase = PlayNextTrackUseCase(),
      _addPlaylistEntryUseCase = AddPlaylistEntryUseCase(_playlistRepository),
      _removePlaylistEntryUseCase = RemovePlaylistEntryUseCase(
        _playlistRepository,
      ),
      _clearPlaylistUseCase = ClearPlaylistUseCase(_playlistRepository) {
    _initListeners();
    Future.microtask(_bootstrap);
  }

  Future<void> _bootstrap() async {
    _playlist = await _playlistRepository.loadPlaylist();
    notifyListeners();
    await _loadMediaLibrary();
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
        _currentMediaPath = event.sourcePath;
        _isLoaded = true;
        _currentPosSecs = 0.0;
        _clearThumbnailCache();
        notifyListeners();
      } else if (event is VideoUnloadedEvent) {
        _isLoaded = false;
        _isPlaying = false;
        _textureId = null;
        _clearThumbnailCache();
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
      notifyListeners();
      return;
    }

    await _playNextTrackUseCase.execute(
      playlist: _playlist,
      currentPath: _currentMediaPath,
      volume: volume,
      eventBus: _eventBus,
    );

    if (_currentMediaPath == null) {
      _isPlaying = false;
      await _repository.setPlaying(false);
      await _repository.seek(0.0, accurate: true);
      await _repository.updateTexture();
      _eventBus.publish(PlaybackPositionEvent(0.0));
      _eventBus.publish(PlaybackStateEvent(false));
      notifyListeners();
    }
  }

  Future<void> _playMediaEntry(
    MediaFileEntry entry, {
    required bool autoplay,
  }) async {
    _eventBus.publish(
      OpenFileUseCase(entry.path, volume: volume, autoplay: autoplay),
    );
  }

  Future<void> addToPlaylist(MediaFileEntry entry) async {
    _playlist = await _addPlaylistEntryUseCase.execute(_playlist, entry);
    notifyListeners();
  }

  Future<void> removeFromPlaylist(String path) async {
    _playlist = await _removePlaylistEntryUseCase.execute(_playlist, path);
    if (_currentMediaPath == path) {
      _currentMediaPath = null;
    }
    notifyListeners();
  }

  Future<void> clearPlaylist() async {
    await _clearPlaylistUseCase.execute();
    _playlist = [];
    notifyListeners();
  }

  Future<void> playPlaylistEntry(MediaFileEntry entry) async {
    _playlist = await _addPlaylistEntryUseCase.execute(_playlist, entry);
    notifyListeners();
    await _playMediaEntry(entry, autoplay: true);
  }

  Future<void> playPlaylistIndex(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    await _playMediaEntry(_playlist[index], autoplay: true);
  }

  Future<void> openMediaFile(String path) async {
    _eventBus.publish(OpenFileUseCase(path, volume: volume));
  }

  Future<void> _loadMediaLibrary() async {
    _isMediaLibraryLoading = true;
    _mediaLibraryError = null;
    notifyListeners();
    try {
      _mediaSearchRoots = await _repository.getMediaSearchRoots();
      _mediaFiles = await _repository.scanMediaFiles();
    } catch (e) {
      _mediaLibraryError = e.toString();
      _mediaFiles = [];
    } finally {
      _isMediaLibraryLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshMediaLibrary() async {
    await _loadMediaLibrary();
  }

  Future<void> updateMediaSearchRoots(List<String> roots) async {
    _isMediaLibraryLoading = true;
    _mediaLibraryError = null;
    notifyListeners();
    try {
      await _repository.setMediaSearchRoots(roots);
      _mediaSearchRoots = await _repository.getMediaSearchRoots();
      _mediaFiles = await _repository.scanMediaFiles();
    } catch (e) {
      _mediaLibraryError = e.toString();
    } finally {
      _isMediaLibraryLoading = false;
      notifyListeners();
    }
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
    final key = (seconds * 1000).round();
    if (_thumbnailCache.containsKey(key)) {
      return _thumbnailCache[key]!.clone();
    }
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
    final img = await completer.future;
    if (_thumbnailCache.containsKey(key)) {
      img.dispose();
      return _thumbnailCache[key]!.clone();
    }
    if (_thumbnailCacheKeys.length >= _maxCacheSize) {
      final oldestKey = _thumbnailCacheKeys.removeAt(0);
      _thumbnailCache.remove(oldestKey)?.dispose();
    }
    _thumbnailCache[key] = img;
    _thumbnailCacheKeys.add(key);
    return img.clone();
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
    _eventSubscription?.cancel();
    _eventBusSubscription?.cancel();
    _clearThumbnailCache();
    super.dispose();
  }
}
