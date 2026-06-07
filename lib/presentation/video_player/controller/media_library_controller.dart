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

import 'package:flutter/foundation.dart';
import '../../../domain/models/video_models.dart';
import '../../../domain/repository/video_repository.dart';

class MediaLibraryController extends ChangeNotifier {
  final VideoRepository _repository;

  bool _isLoading = false;
  String? _error;
  List<String> _searchRoots = [];
  List<MediaFileEntry> _files = [];

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<String> get searchRoots => List.unmodifiable(_searchRoots);
  List<MediaFileEntry> get files => List.unmodifiable(_files);

  MediaLibraryController(this._repository);

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _searchRoots = await _repository.getMediaSearchRoots();
      _files = await _repository.scanMediaFiles();
    } catch (e) {
      _error = e.toString();
      _files = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateSearchRoots(List<String> roots) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _repository.setMediaSearchRoots(roots);
      _searchRoots = await _repository.getMediaSearchRoots();
      _files = await _repository.scanMediaFiles();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    await load();
  }
}
