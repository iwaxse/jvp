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
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import '../../../application/app_event_bus.dart';
import '../../../application/usecase/get_thumbnail_usecase.dart';
import '../../../domain/repository/video_repository.dart';
import '../../../domain/models/video_models.dart';

class ThumbnailController extends ChangeNotifier {
  final AppEventBus _eventBus;
  final GetThumbnailUseCase _getThumbnailUseCase;
  StreamSubscription<AppEvent>? _subscription;

  final Map<int, ui.Image> _thumbnailCache = {};
  final List<int> _thumbnailCacheKeys = [];
  static const int _maxCacheSize = 30;

  ThumbnailController(VideoRepository repository, this._eventBus)
    : _getThumbnailUseCase = GetThumbnailUseCase(repository);

  void init() {
    _subscription = _eventBus.stream.listen((event) {
      if (event is VideoLoadedEvent || event is VideoUnloadedEvent) {
        clearCache();
      }
    });
  }

  void clearCache() {
    for (final img in _thumbnailCache.values) {
      img.dispose();
    }
    _thumbnailCache.clear();
    _thumbnailCacheKeys.clear();
    notifyListeners();
  }

  Future<Thumbnail?> _fetchThumbnail(double seconds) async {
    try {
      return await _getThumbnailUseCase.getThumbnail(seconds);
    } catch (e) {
      debugPrint('ThumbnailController: Failed to get thumbnail: $e');
      return null;
    }
  }

  Future<ui.Image?> getThumbnailImage(double seconds) async {
    final key = (seconds * 1000).round();
    if (_thumbnailCache.containsKey(key)) {
      return _thumbnailCache[key]!.clone();
    }

    final thumb = await _fetchThumbnail(seconds);
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

  @override
  void dispose() {
    _subscription?.cancel();
    clearCache();
    super.dispose();
  }
}
