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
import 'package:desktop_drop/desktop_drop.dart';
import '../../application/app_event_bus.dart';
import '../video_player_view_model.dart';

class VideoDropTargetWidget extends StatelessWidget {
  final Widget child;

  const VideoDropTargetWidget({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final eventBus = context.read<AppEventBus>();
    final viewModel = context.read<VideoPlayerViewModel>();
    final isDragging = context.select<VideoPlayerViewModel, bool>(
      (vm) => vm.isDraggingFile,
    );

    return DropTarget(
      onDragEntered: (details) => viewModel.isDraggingFile = true,
      onDragExited: (details) => viewModel.isDraggingFile = false,
      onDragDone: (details) async {
        viewModel.isDraggingFile = false;
        if (details.files.isNotEmpty) {
          eventBus.publish(OpenFileAction(details.files.first.path));
        }
      },
      child: Stack(
        children: [
          child,
          if (isDragging)
            Container(
              color: Colors.black.withValues(alpha: 0.85),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 24,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF333333)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    'Drop to Import',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
