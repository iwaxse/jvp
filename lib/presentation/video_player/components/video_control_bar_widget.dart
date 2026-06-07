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
import '../../../application/app_event_bus.dart';
import '../../../application/commands/toggle_play_command.dart';
import '../../../application/commands/toggle_looping_command.dart';
import '../../../application/commands/toggle_mute_command.dart';
import '../../../application/commands/set_volume_command.dart';
import '../../../application/commands/start_scrubbing_command.dart';
import '../../../application/commands/update_scrub_value_command.dart';
import '../../../application/commands/end_scrubbing_command.dart';
import '../video_player_view_model.dart';
import '../controller/video_control_bar_controller.dart';

class VideoControlBarWidget extends StatelessWidget {
  const VideoControlBarWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.read<VideoPlayerViewModel>();
    return ChangeNotifierProvider<VideoControlBarController>(
      create: (context) => VideoControlBarController(context, viewModel),
      child: Consumer<VideoControlBarController>(
        builder: (context, controller, _) {
          final eventBus = context.read<AppEventBus>();
          final durationSecs = context.select<VideoPlayerViewModel, double>(
            (vm) => vm.durationSecs,
          );
          final isPlaying = context.select<VideoPlayerViewModel, bool>(
            (vm) => vm.isPlaying,
          );
          final isLooping = context.select<VideoPlayerViewModel, bool>(
            (vm) => vm.isLooping,
          );
          final isMuted = context.select<VideoPlayerViewModel, bool>(
            (vm) => vm.isMuted,
          );
          final volume = context.select<VideoPlayerViewModel, double>(
            (vm) => vm.volume,
          );
          final isLoaded = context.select<VideoPlayerViewModel, bool>(
            (vm) => vm.isLoaded,
          );
          final realTimeFps = context.select<VideoPlayerViewModel, double>(
            (vm) => vm.realTimeFps,
          );

          return ExcludeFocus(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                color: const Color(0xFF141414).withValues(alpha: 0.85),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _TimeSlider(
                      controller: controller,
                      durationSecs: durationSecs,
                      isPlaying: isPlaying,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                isPlaying
                                    ? Icons.pause_circle_outline
                                    : Icons.play_circle_outline,
                                color: Colors.white,
                                size: 32,
                              ),
                              onPressed: () {
                                eventBus.publish(
                                  TogglePlayCommand(
                                    currentIsPlaying: isPlaying,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: Icon(
                                isLooping ? Icons.loop : Icons.loop_outlined,
                                color: isLooping
                                    ? Colors.white
                                    : const Color(0xFF555555),
                                size: 24,
                              ),
                              onPressed: () {
                                eventBus.publish(
                                  ToggleLoopingCommand(
                                    currentIsLooping: isLooping,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: Icon(
                                isMuted
                                    ? Icons.volume_off_outlined
                                    : Icons.volume_up_outlined,
                                color: isMuted
                                    ? const Color(0xFF555555)
                                    : Colors.white,
                                size: 24,
                              ),
                              onPressed: () {
                                eventBus.publish(
                                  ToggleMuteCommand(
                                    currentIsMuted: isMuted,
                                    currentVolume: volume,
                                  ),
                                );
                              },
                            ),
                            SizedBox(
                              width: 80,
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 2,
                                  activeTrackColor: Colors.white,
                                  inactiveTrackColor: const Color(0xFF333333),
                                  thumbColor: Colors.white,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 4,
                                  ),
                                ),
                                child: Slider(
                                  focusNode: controller.volumeFocusNode,
                                  value: volume,
                                  onChanged: (val) {
                                    eventBus.publish(SetVolumeCommand(val));
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (isLoaded)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${realTimeFps.toStringAsFixed(1)} FPS',
                                style: const TextStyle(
                                  color: Color(0xFF888888),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 12),
                              IconButton(
                                icon: const Icon(
                                  Icons.tune,
                                  color: Color(0xFFD4AF37),
                                  size: 20,
                                ),
                                onPressed: () {
                                  eventBus.publish(ToggleTunerAction());
                                },
                                tooltip: 'Engine Tuner',
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TimeSlider extends StatelessWidget {
  final VideoControlBarController controller;
  final double durationSecs;
  final bool isPlaying;

  const _TimeSlider({
    required this.controller,
    required this.durationSecs,
    required this.isPlaying,
  });

  @override
  Widget build(BuildContext context) {
    final eventBus = context.read<AppEventBus>();
    final currentPosSecs = context.select<VideoPlayerViewModel, double>(
      (vm) => vm.currentPosSecs,
    );

    return Consumer<VideoControlBarController>(
      builder: (context, ctrl, _) {
        final max = durationSecs > 0 ? durationSecs : 1.0;
        final displayValue = (ctrl.localScrubValue ?? currentPosSecs).clamp(
          0.0,
          max,
        );

        return Row(
          children: [
            Text(
              _formatDuration(displayValue),
              style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
            ),
            Expanded(
              child: MouseRegion(
                onHover: (event) => ctrl.handleHover(event, max),
                onExit: (_) => ctrl.removeThumbnail(),
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    activeTrackColor: const Color(0xFFE5E5E5),
                    inactiveTrackColor: const Color(0xFF333333),
                    thumbColor: Colors.white,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                  ),
                  child: Slider(
                    key: ctrl.sliderKey,
                    focusNode: ctrl.sliderFocusNode,
                    value: displayValue,
                    max: max,
                    onChangeStart: (val) {
                      ctrl.removeThumbnail();
                      ctrl.localScrubValue = val;
                      eventBus.publish(
                        StartScrubbingCommand(currentIsPlaying: isPlaying),
                      );
                    },
                    onChanged: (val) {
                      ctrl.localScrubValue = val;
                      eventBus.publish(
                        UpdateScrubValueCommand(
                          val,
                          durationSecs: durationSecs,
                          isScrubbing: true,
                        ),
                      );
                    },
                    onChangeEnd: (val) {
                      eventBus.publish(
                        EndScrubbingCommand(
                          seconds: val,
                          durationSecs: durationSecs,
                          wasPlayingBeforeScrub: context
                              .read<VideoPlayerViewModel>()
                              .wasPlayingBeforeScrub,
                        ),
                      );
                      ctrl.localScrubValue = null;
                    },
                  ),
                ),
              ),
            ),
            Text(
              _formatDuration(durationSecs),
              style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
            ),
          ],
        );
      },
    );
  }

  String _formatDuration(double seconds) {
    if (seconds.isNaN || seconds.isInfinite) return '00:00';
    final int minutes = (seconds / 60).floor();
    final int remainingSeconds = (seconds % 60).floor();
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
