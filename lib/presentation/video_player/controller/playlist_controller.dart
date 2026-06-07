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
import 'package:flutter/foundation.dart';
import '../../../application/app_event_bus.dart';
import '../../../application/commands/open_file_command.dart';
import '../../../application/usecase/add_playlist_entry_usecase.dart';
import '../../../application/usecase/remove_playlist_entry_usecase.dart';
import '../../../application/usecase/clear_playlist_usecase.dart';
import '../../../application/usecase/play_next_track_usecase.dart';
import '../../../domain/models/video_models.dart';
import '../../../domain/repository/playlist_repository.dart';
import '../video_player_view_model.dart';

class PlaylistController extends ChangeNotifier {
  final PlaylistRepository _playlistRepository;
  final AppEventBus _eventBus;

  final AddPlaylistEntryUseCase _addUseCase;
  final RemovePlaylistEntryUseCase _removeUseCase;
  final ClearPlaylistUseCase _clearUseCase;
  final PlayNextTrackUseCase _playNextUseCase;

  List<MediaFileEntry> _playlist = [];
  StreamSubscription<AppEvent>? _subscription;

  List<MediaFileEntry> get playlist => List.unmodifiable(_playlist);

  PlaylistController(this._playlistRepository, this._eventBus)
    : _addUseCase = AddPlaylistEntryUseCase(_playlistRepository),
      _removeUseCase = RemovePlaylistEntryUseCase(_playlistRepository),
      _clearUseCase = ClearPlaylistUseCase(_playlistRepository),
      _playNextUseCase = PlayNextTrackUseCase();

  void init(VideoPlayerViewModel viewModel) {
    _subscription = _eventBus.stream.listen((event) async {
      if (event is PlaybackCompletedEvent) {
        await playNext(viewModel.currentMediaPath, viewModel.volume);
      }
    });
  }

  Future<void> load() async {
    _playlist = await _playlistRepository.loadPlaylist();
    notifyListeners();
  }

  Future<void> add(MediaFileEntry entry) async {
    _playlist = await _addUseCase.execute(_playlist, entry);
    notifyListeners();
  }

  Future<void> remove(String path) async {
    _playlist = await _removeUseCase.execute(_playlist, path);
    notifyListeners();
  }

  Future<void> clear() async {
    await _clearUseCase.execute();
    _playlist = [];
    notifyListeners();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _playlist.removeAt(oldIndex);
    _playlist.insert(newIndex, item);
    notifyListeners();
    await _playlistRepository.savePlaylist(_playlist);
  }

  Future<bool> playNext(String? currentPath, double volume) async {
    return await _playNextUseCase.execute(
      playlist: _playlist,
      currentPath: currentPath,
      volume: volume,
      eventBus: _eventBus,
    );
  }

  void playIndex(int index, double volume) {
    if (index < 0 || index >= _playlist.length) return;
    _eventBus.publish(
      OpenFileCommand(_playlist[index].path, volume: volume, autoplay: true),
    );
  }

  void playEntry(MediaFileEntry entry, double volume) async {
    if (!_playlist.any((item) => item.path == entry.path)) {
      await add(entry);
    }
    _eventBus.publish(
      OpenFileCommand(entry.path, volume: volume, autoplay: true),
    );
  }

  int? indexOf(String? path) {
    if (path == null) return null;
    final index = _playlist.indexWhere((item) => item.path == path);
    return index >= 0 ? index : null;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
