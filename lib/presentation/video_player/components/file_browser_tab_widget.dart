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
import '../../../domain/models/video_models.dart';
import '../video_player_view_model.dart';
import '../controller/media_library_controller.dart';
import '../controller/playlist_controller.dart';

class FileBrowserTabWidget extends StatelessWidget {
  final VoidCallback onSettingsPressed;

  const FileBrowserTabWidget({super.key, required this.onSettingsPressed});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.read<VideoPlayerViewModel>();
    final libraryController = context.read<MediaLibraryController>();
    final playlistController = context.read<PlaylistController>();

    final roots = context.select<MediaLibraryController, List<String>>(
      (c) => c.searchRoots,
    );
    final isLoading = context.select<MediaLibraryController, bool>(
      (c) => c.isLoading,
    );
    final error = context.select<MediaLibraryController, String?>(
      (c) => c.error,
    );
    final files = context.select<MediaLibraryController, List<MediaFileEntry>>(
      (c) => c.files,
    );
    final currentMediaPath = context.select<VideoPlayerViewModel, String?>(
      (vm) => vm.currentMediaPath,
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
                    'Files',
                    style: TextStyle(
                      color: Color(0xFFD4AF37),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.3,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => libraryController.refresh(),
                  icon: const Icon(
                    Icons.refresh,
                    color: Color(0xFFB9B9B9),
                    size: 20,
                  ),
                  tooltip: 'Rescan',
                ),
                IconButton(
                  onPressed: onSettingsPressed,
                  icon: const Icon(
                    Icons.settings_outlined,
                    color: Color(0xFFB9B9B9),
                    size: 20,
                  ),
                  tooltip: 'Search roots',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: roots
                  .map(
                    (root) => Chip(
                      label: Text(
                        root,
                        style: const TextStyle(
                          color: Color(0xFFE7E7E7),
                          fontSize: 11,
                        ),
                      ),
                      backgroundColor: const Color(0xFF1E1E1E),
                      side: const BorderSide(color: Color(0xFF2E2E2E)),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
          if (isLoading)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFD4AF37),
                ),
              ),
            )
          else if (error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    error,
                    style: const TextStyle(
                      color: Color(0xFFB56B6B),
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          else if (files.isEmpty)
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'No playable files found in the configured folders.',
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
                itemCount: files.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: Color(0xFF232323)),
                itemBuilder: (context, index) {
                  final file = files[index];
                  final isCurrent = file.path == currentMediaPath;
                  return InkWell(
                    onTap: () {
                      viewModel.openMediaFile(file.path);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
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
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isCurrent
                                  ? Icons.play_circle
                                  : Icons.play_circle_outline,
                              color: isCurrent
                                  ? const Color(0xFFD4AF37)
                                  : const Color(0xFFB9B9B9),
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          file.displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: isCurrent
                                                ? const Color(0xFFFFF2CC)
                                                : const Color(0xFFEFEFEF),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      if (isCurrent)
                                        const Padding(
                                          padding: EdgeInsets.only(left: 8),
                                          child: Text(
                                            'Now Playing',
                                            style: TextStyle(
                                              color: Color(0xFFD4AF37),
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    file.directoryPath,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF8A8A8A),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => playlistController.add(file),
                              icon: const Icon(
                                Icons.playlist_add_outlined,
                                color: Color(0xFFB9B9B9),
                                size: 22,
                              ),
                              tooltip: 'Add to playlist',
                            ),
                          ],
                        ),
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
