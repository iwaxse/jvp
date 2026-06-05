import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../application/app_event_bus.dart';
import '../video_player_view_model.dart';
import 'video_control_bar_widget_controller.dart';

class VideoControlBarWidget extends StatefulWidget {
  const VideoControlBarWidget({super.key});

  @override
  State<VideoControlBarWidget> createState() => _VideoControlBarWidgetState();
}

class _VideoControlBarWidgetState extends State<VideoControlBarWidget> {
  late VideoControlBarWidgetController _controller;

  @override
  void initState() {
    super.initState();
    final viewModel = context.read<VideoPlayerViewModel>();
    _controller = VideoControlBarWidgetController(context, viewModel);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
    final currentPosSecs = context.select<VideoPlayerViewModel, double>(
      (vm) => vm.currentPosSecs,
    );

    final max = durationSecs > 0 ? durationSecs : 1.0;
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final displayValue = (_controller.localScrubValue ?? currentPosSecs)
            .clamp(0.0, max);
        return ExcludeFocus(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: const Color(0xFF141414).withValues(alpha: 0.85),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        _formatDuration(displayValue),
                        style: const TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 12,
                        ),
                      ),
                      Expanded(
                        child: MouseRegion(
                          onHover: (event) =>
                              _controller.handleHover(event, max),
                          onExit: (_) => _controller.removeThumbnail(),
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
                              key: _controller.sliderKey,
                              focusNode: _controller.sliderFocusNode,
                              value: displayValue,
                              max: max,
                              onChangeStart: (val) {
                                _controller.removeThumbnail();
                                _controller.localScrubValue = val;
                                eventBus.publish(StartScrubbingAction());
                              },
                              onChanged: (val) {
                                _controller.localScrubValue = val;
                                eventBus.publish(UpdateScrubValueAction(val));
                              },
                              onChangeEnd: (val) {
                                eventBus.publish(EndScrubbingAction(val));
                                _controller.localScrubValue = null;
                              },
                            ),
                          ),
                        ),
                      ),
                      Text(
                        _formatDuration(durationSecs),
                        style: const TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 12,
                        ),
                      ),
                    ],
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
                              eventBus.publish(TogglePlayAction());
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
                              eventBus.publish(ToggleLoopingAction());
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
                              eventBus.publish(ToggleMuteAction());
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
                                focusNode: _controller.volumeFocusNode,
                                value: volume,
                                onChanged: (val) {
                                  eventBus.publish(SetVolumeAction(val));
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
    );
  }

  String _formatDuration(double seconds) {
    if (seconds.isNaN || seconds.isInfinite) return '00:00';
    final int minutes = (seconds / 60).floor();
    final int remainingSeconds = (seconds % 60).floor();
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
