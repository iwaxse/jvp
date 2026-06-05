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
import 'video_player_view_controller.dart';
import 'video_player_view_model.dart';
import 'components/shader_settings_panel_widget.dart';
import 'components/video_control_bar_widget.dart';
import 'components/video_drop_target_widget.dart';

class VideoPlayerView extends StatelessWidget {
  const VideoPlayerView({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.read<VideoPlayerViewModel>();
    return ChangeNotifierProvider<VideoPlayerViewController>(
      create: (context) => VideoPlayerViewController(context, viewModel),
      child: Consumer<VideoPlayerViewController>(
        builder: (context, controller, _) {
          final isLoaded = context.select<VideoPlayerViewModel, bool>(
            (vm) => vm.isLoaded,
          );
          final textureId = context.select<VideoPlayerViewModel, int?>(
            (vm) => vm.textureId,
          );
          final width = context.select<VideoPlayerViewModel, int>(
            (vm) => vm.width,
          );
          final height = context.select<VideoPlayerViewModel, int>(
            (vm) => vm.height,
          );
          final showTuner = context.select<VideoPlayerViewController, bool>(
            (c) => c.showTuner,
          );
          final showControlBar = context
              .select<VideoPlayerViewController, bool>((c) => c.showControlBar);

          return Scaffold(
            backgroundColor: const Color(0xFF0A0A0A),
            body: VideoDropTargetWidget(
              child: Stack(
                children: [
                  GestureDetector(
                    onTap: () {
                      viewModel.togglePlay();
                    },
                    onLongPress: () {
                      controller.showTuner = !controller.showTuner;
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Center(
                      child: isLoaded && textureId != null
                          ? AspectRatio(
                              aspectRatio: width / height,
                              child: Texture(textureId: textureId),
                            )
                          : const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.movie_creation_outlined,
                                  color: Color(0xFF555555),
                                  size: 64,
                                ),
                                uiKeyLabel,
                              ],
                            ),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    left: 24,
                    right: showTuner ? 364 : 24,
                    bottom: showControlBar ? 24 : -100,
                    child: const VideoControlBarWidget(),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    top: 0,
                    bottom: 0,
                    right: showTuner ? 0 : -340,
                    width: 340,
                    child: ShaderSettingsPanelWidget(
                      onClose: () {
                        controller.showTuner = false;
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static const Widget uiKeyLabel = Column(
    children: [
      SizedBox(height: 16),
      Text(
        'Drag & Drop video file here to play',
        style: TextStyle(
          color: Color(0xFF888888),
          fontSize: 16,
          fontWeight: FontWeight.w300,
          letterSpacing: 1.2,
        ),
      ),
      SizedBox(height: 8),
      Text(
        '[Space] Play/Pause  •  [←/→] Frame Step  •  [D] Toggle Controls',
        style: TextStyle(
          color: Color(0xFF444444),
          fontSize: 12,
          fontWeight: FontWeight.w300,
        ),
      ),
    ],
  );
}
