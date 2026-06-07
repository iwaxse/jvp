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

import '../app_event_bus.dart';
import '../commands/open_file_command.dart';
import '../../../domain/models/video_models.dart';

class PlayNextTrackUseCase {
  Future<bool> execute({
    required List<MediaFileEntry> playlist,
    required String? currentPath,
    required double volume,
    required AppEventBus eventBus,
  }) async {
    if (currentPath == null || playlist.isEmpty) return false;

    final currentIndex = playlist.indexWhere(
      (item) => item.path == currentPath,
    );
    if (currentIndex < 0 || currentIndex + 1 >= playlist.length) return false;

    final nextEntry = playlist[currentIndex + 1];
    eventBus.publish(
      OpenFileCommand(nextEntry.path, volume: volume, autoplay: true),
    );
    return true;
  }
}
