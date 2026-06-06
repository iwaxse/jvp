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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/models/video_models.dart';
import '../video_player_view_model.dart';

class PlaylistTabWidget extends StatelessWidget {
  const PlaylistTabWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.read<VideoPlayerViewModel>();
    final playlist = context.select<VideoPlayerViewModel, List<MediaFileEntry>>(
      (vm) => vm.playlist,
    );
    final currentIndex = context.select<VideoPlayerViewModel, int?>(
      (vm) => vm.currentPlaylistIndex,
    );

    return Container(
      color: const Color(0xFF141414),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Playlist',
                    style: TextStyle(
                      color: Color(0xFFD4AF37),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.3,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: playlist.isEmpty ? null : viewModel.clearPlaylist,
                  icon: const Icon(
                    Icons.delete_sweep_outlined,
                    color: Color(0xFFB9B9B9),
                    size: 20,
                  ),
                  tooltip: 'Clear playlist',
                ),
              ],
            ),
          ),
          if (playlist.isEmpty)
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Add videos from the Files tab to build a playlist.',
                    style: TextStyle(color: Color(0xFF888888), fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount: playlist.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: Color(0xFF232323)),
                itemBuilder: (context, index) {
                  final entry = playlist[index];
                  final isCurrent = currentIndex == index;
                  return Container(
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? const Color(0xFF1B1B1B)
                          : const Color(0xFF141414),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isCurrent
                            ? const Color(0xFFD4AF37)
                            : const Color(0xFF222222),
                      ),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: IconButton(
                        onPressed: () => viewModel.playPlaylistIndex(index),
                        icon: const Icon(
                          Icons.play_circle_outline,
                          color: Color(0xFFD4AF37),
                        ),
                        tooltip: 'Play',
                      ),
                      title: Text(
                        entry.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFEFEFEF),
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        entry.directoryPath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 11,
                        ),
                      ),
                      trailing: IconButton(
                        onPressed: () =>
                            viewModel.removeFromPlaylist(entry.path),
                        icon: const Icon(
                          Icons.remove_circle_outline,
                          color: Color(0xFFB56B6B),
                        ),
                        tooltip: 'Remove',
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
