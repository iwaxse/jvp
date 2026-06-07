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

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/video_models.dart';
import '../../domain/repository/playlist_repository.dart';

class PlaylistRepositoryImpl implements PlaylistRepository {
  static const _playlistPrefsKey = 'playlist_entries';

  @override
  Future<List<MediaFileEntry>> loadPlaylist() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_playlistPrefsKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map(
            (item) => MediaFileEntry(
              path: item['path']?.toString() ?? '',
              displayName: item['displayName']?.toString() ?? '',
              directoryPath: item['directoryPath']?.toString() ?? '',
            ),
          )
          .where((item) => item.path.isNotEmpty)
          .toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<void> savePlaylist(List<MediaFileEntry> playlist) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(
      playlist
          .map(
            (item) => {
              'path': item.path,
              'displayName': item.displayName,
              'directoryPath': item.directoryPath,
            },
          )
          .toList(),
    );
    await prefs.setString(_playlistPrefsKey, payload);
  }
}
