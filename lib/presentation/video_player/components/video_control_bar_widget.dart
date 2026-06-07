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

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../application/app_event_bus.dart';
import '../../../application/commands/toggle_ab_looping_command.dart';
import '../../../application/commands/toggle_play_command.dart';
import '../../../application/commands/toggle_looping_command.dart';
import '../../../application/commands/toggle_mute_command.dart';
import '../../../application/commands/set_volume_command.dart';
import '../../../application/commands/start_scrubbing_command.dart';
import '../../../application/commands/update_scrub_value_command.dart';
import '../../../application/commands/end_scrubbing_command.dart';
import '../../../application/commands/update_ab_loop_range_command.dart';
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
          final isAbLooping = context.select<VideoPlayerViewModel, bool>(
            (vm) => vm.isAbLooping,
          );
          final abLoopStartSecs = context.select<VideoPlayerViewModel, double?>(
            (vm) => vm.abLoopStartSecs,
          );
          final abLoopEndSecs = context.select<VideoPlayerViewModel, double?>(
            (vm) => vm.abLoopEndSecs,
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
                      isAbLooping: isAbLooping,
                      abLoopStartSecs: abLoopStartSecs,
                      abLoopEndSecs: abLoopEndSecs,
                      isLoaded: isLoaded,
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
                                color: isLoaded ? Colors.white : Colors.white24,
                                size: 32,
                              ),
                              onPressed: isLoaded
                                  ? () {
                                      eventBus.publish(
                                        TogglePlayCommand(
                                          currentIsPlaying: isPlaying,
                                        ),
                                      );
                                    }
                                  : null,
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: Icon(
                                isLooping ? Icons.loop : Icons.loop_outlined,
                                color: isAbLooping
                                    ? const Color(0xFFE5C46A)
                                    : isLooping
                                    ? (isLoaded ? Colors.white : Colors.white24)
                                    : const Color(0xFF555555),
                                size: 24,
                              ),
                              onPressed: isLoaded && !isAbLooping
                                  ? () {
                                      eventBus.publish(
                                        ToggleLoopingCommand(
                                          currentIsLooping: isLooping,
                                        ),
                                      );
                                    }
                                  : null,
                              onLongPress: isLoaded
                                  ? () {
                                      eventBus.publish(
                                        ToggleAbLoopingCommand(
                                          currentIsAbLooping: isAbLooping,
                                          currentIsLooping: isLooping,
                                        ),
                                      );
                                    }
                                  : null,
                              tooltip: isAbLooping
                                  ? 'Exit A-B loop'
                                  : 'Long press for A-B loop',
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
  final bool isAbLooping;
  final double? abLoopStartSecs;
  final double? abLoopEndSecs;
  final bool isLoaded;

  const _TimeSlider({
    required this.controller,
    required this.durationSecs,
    required this.isPlaying,
    required this.isAbLooping,
    required this.abLoopStartSecs,
    required this.abLoopEndSecs,
    required this.isLoaded,
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
        final displayValue = (ctrl.localScrubValue ?? currentPosSecs)
            .clamp(0.0, max)
            .toDouble();

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Text(
                    _formatDuration(displayValue),
                    style: const TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 12,
                      fontFeatures: [ui.FontFeature.tabularFigures()],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: MouseRegion(
                    onHover: isLoaded
                        ? (event) => ctrl.handleHover(event, max)
                        : null,
                    onExit: (_) => ctrl.removeThumbnail(),
                    child: SizedBox(
                      height: 34,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4,
                              activeTrackColor: isLoaded
                                  ? const Color(0xFFE5E5E5)
                                  : Colors.white10,
                              inactiveTrackColor: const Color(0xFF333333),
                              thumbColor: isLoaded
                                  ? Colors.white
                                  : Colors.transparent,
                              thumbShape: isLoaded
                                  ? const RoundSliderThumbShape(
                                      enabledThumbRadius: 6,
                                    )
                                  : SliderComponentShape.noThumb,
                            ),
                            child: Slider(
                              key: ctrl.sliderKey,
                              focusNode: ctrl.sliderFocusNode,
                              value: displayValue,
                              max: max,
                              onChangeStart: isLoaded
                                  ? (val) {
                                      ctrl.removeThumbnail();
                                      ctrl.localScrubValue = val;
                                      eventBus.publish(
                                        StartScrubbingCommand(
                                          currentIsPlaying: isPlaying,
                                        ),
                                      );
                                    }
                                  : null,
                              onChanged: isLoaded
                                  ? (val) {
                                      ctrl.localScrubValue = val;
                                      eventBus.publish(
                                        UpdateScrubValueCommand(
                                          val,
                                          durationSecs: durationSecs,
                                          isScrubbing: true,
                                        ),
                                      );
                                    }
                                  : null,
                              onChangeEnd: isLoaded
                                  ? (val) {
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
                                    }
                                  : null,
                            ),
                          ),
                          if (isAbLooping)
                            Positioned.fill(
                              child: _AbLoopRangeLayer(
                                max: max,
                                startSecs: abLoopStartSecs,
                                endSecs: abLoopEndSecs,
                                isPlaying: isPlaying,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    _formatDuration(durationSecs),
                    style: const TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 12,
                      fontFeatures: [ui.FontFeature.tabularFigures()],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            if (isAbLooping) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF20190A),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFE5C46A)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: Text(
                      _abLoopStatusText(),
                      style: const TextStyle(
                        color: Color(0xFFE5C46A),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  String _abLoopStatusText() {
    final start = abLoopStartSecs ?? 0.0;
    final end = abLoopEndSecs ?? durationSecs;
    return 'A-B loop: ${_formatDuration(start)} - ${_formatDuration(end)}';
  }

  String _formatDuration(double seconds) {
    if (seconds.isNaN || seconds.isInfinite) return '00:00';
    final int minutes = (seconds / 60).floor();
    final int remainingSeconds = (seconds % 60).floor();
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}

class _AbLoopRangeLayer extends StatelessWidget {
  final double max;
  final double? startSecs;
  final double? endSecs;
  final bool isPlaying;

  const _AbLoopRangeLayer({
    required this.max,
    required this.startSecs,
    required this.endSecs,
    required this.isPlaying,
  });

  @override
  Widget build(BuildContext context) {
    if (startSecs == null && endSecs == null) {
      return const SizedBox.shrink();
    }

    final eventBus = context.read<AppEventBus>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Adjust for Slider padding (approx 12px each side)
        const horizontalPadding = 12.0;
        final trackWidth = width - (horizontalPadding * 2);
        final safeMax = max > 0 ? max : 1.0;

        final start = (startSecs ?? 0.0).clamp(0.0, safeMax);
        final end = (endSecs ?? safeMax).clamp(0.0, safeMax);

        final leftPos = horizontalPadding + (trackWidth * (start / safeMax));
        final rightPos = horizontalPadding + (trackWidth * (end / safeMax));

        final rangeWidth = math.max(2.0, rightPos - leftPos);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: horizontalPadding,
              right: horizontalPadding,
              top: 14,
              child: IgnorePointer(
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2B2414).withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
            Positioned(
              left: leftPos,
              top: 13,
              width: rangeWidth,
              child: IgnorePointer(
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5C46A).withValues(alpha: 0.34),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0xFFE5C46A).withValues(alpha: 0.85),
                      width: 1,
                    ),
                  ),
                ),
              ),
            ),
            // Draggable Pin A
            Positioned(
              left: leftPos - 12,
              top: 0,
              bottom: 0,
              width: 24,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) {
                  eventBus.publish(
                    StartScrubbingCommand(currentIsPlaying: isPlaying),
                  );
                },
                onHorizontalDragUpdate: (details) {
                  final renderBox = context.findRenderObject() as RenderBox;
                  final localX = renderBox
                      .globalToLocal(details.globalPosition)
                      .dx;
                  final newVal =
                      ((localX - horizontalPadding) / trackWidth * safeMax)
                          .clamp(0.0, end - 0.01);
                  eventBus.publish(
                    UpdateAbLoopRangeCommand(
                      startSecs: newVal,
                      endSecs: end,
                      seekToPoint: true,
                      isStartPoint: true,
                      accurate: false,
                    ),
                  );
                },
                onHorizontalDragEnd: (_) {
                  final viewModel = context.read<VideoPlayerViewModel>();
                  eventBus.publish(
                    UpdateAbLoopRangeCommand(
                      startSecs: start,
                      endSecs: end,
                      seekToPoint: true,
                      isStartPoint: true,
                      accurate: true,
                    ),
                  );
                  eventBus.publish(
                    EndScrubbingCommand(
                      seconds: start,
                      durationSecs: max,
                      wasPlayingBeforeScrub: viewModel.wasPlayingBeforeScrub,
                    ),
                  );
                },
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 11),
                    child: _AbLoopPin(label: 'A', active: startSecs != null),
                  ),
                ),
              ),
            ),
            // Draggable Pin B
            Positioned(
              left: rightPos - 12,
              top: 0,
              bottom: 0,
              width: 24,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) {
                  eventBus.publish(
                    StartScrubbingCommand(currentIsPlaying: isPlaying),
                  );
                },
                onHorizontalDragUpdate: (details) {
                  final renderBox = context.findRenderObject() as RenderBox;
                  final localX = renderBox
                      .globalToLocal(details.globalPosition)
                      .dx;
                  final newVal =
                      ((localX - horizontalPadding) / trackWidth * safeMax)
                          .clamp(start + 0.01, safeMax);
                  eventBus.publish(
                    UpdateAbLoopRangeCommand(
                      startSecs: start,
                      endSecs: newVal,
                      seekToPoint: true,
                      isStartPoint: false,
                      accurate: false,
                    ),
                  );
                },
                onHorizontalDragEnd: (_) {
                  final viewModel = context.read<VideoPlayerViewModel>();
                  eventBus.publish(
                    UpdateAbLoopRangeCommand(
                      startSecs: start,
                      endSecs: end,
                      seekToPoint: true,
                      isStartPoint: false,
                      accurate: true,
                    ),
                  );
                  eventBus.publish(
                    EndScrubbingCommand(
                      seconds: end,
                      durationSecs: max,
                      wasPlayingBeforeScrub: viewModel.wasPlayingBeforeScrub,
                    ),
                  );
                },
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 11),
                    child: const _AbLoopPin(label: 'B', active: true),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AbLoopPin extends StatelessWidget {
  final String label;
  final bool active;

  const _AbLoopPin({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFFE5C46A) : const Color(0xFF7A6A3A);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 14,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF151109),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color, width: 1),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 1),
        Container(
          width: 2,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ],
    );
  }
}
