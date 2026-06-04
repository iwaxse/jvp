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
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../application/app_event_bus.dart';
import '../view_models/video_player_view_model.dart';

class VideoControlBar extends StatefulWidget {
  const VideoControlBar({super.key});

  @override
  State<VideoControlBar> createState() => _VideoControlBarState();
}

class _VideoControlBarState extends State<VideoControlBar> {
  double? _localScrubValue;
  StreamSubscription<dynamic>? _positionSub;
  StreamSubscription<dynamic>? _loadedSub;
  double _currentPosSecs = 0.0;

  final GlobalKey _sliderKey = GlobalKey();
  OverlayEntry? _thumbnailOverlay;
  ui.Image? _currentThumbnail;
  double _thumbnailX = 0.0;
  double _thumbnailY = 0.0;
  double _thumbnailValue = 0.0;
  bool _isHovering = false;
  bool _isFetchingThumbnail = false;
  double? _pendingThumbnailValue;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_positionSub == null) {
      _currentPosSecs = context.read<VideoPlayerViewModel>().currentPosSecs;
      final eventBus = context.read<AppEventBus>();
      _positionSub = eventBus.on<PlaybackPositionEvent>().listen((event) {
        if (_localScrubValue == null && mounted) {
          setState(() {
            _currentPosSecs = event.position;
          });
        }
      });
      _loadedSub = eventBus.on<VideoLoadedEvent>().listen((event) {
        if (mounted) {
          setState(() {
            _currentPosSecs = 0.0;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _loadedSub?.cancel();
    _removeThumbnail();
    super.dispose();
  }

  void _removeThumbnail() {
    _isHovering = false;
    _thumbnailOverlay?.remove();
    _thumbnailOverlay = null;
    _pendingThumbnailValue = null;
    _currentThumbnail?.dispose();
    _currentThumbnail = null;
  }

  void _showThumbnail(double value, double max, Offset globalPosition) {
    final RenderBox? sliderBox =
        _sliderKey.currentContext?.findRenderObject() as RenderBox?;
    if (sliderBox == null) return;

    final double fraction = max > 0 ? (value / max).clamp(0.0, 1.0) : 0.0;
    final Offset sliderTopLeft = sliderBox.localToGlobal(Offset.zero);

    _thumbnailX = sliderTopLeft.dx + (sliderBox.size.width * fraction);
    _thumbnailY = sliderTopLeft.dy - 100;
    _thumbnailValue = value;

    if (_thumbnailOverlay != null) {
      _thumbnailOverlay!.markNeedsBuild();
    }

    _pendingThumbnailValue = value;
    _fetchNextThumbnail();
  }

  Future<void> _fetchNextThumbnail() async {
    if (_isFetchingThumbnail ||
        _pendingThumbnailValue == null ||
        !_isHovering) {
      return;
    }

    _isFetchingThumbnail = true;
    final targetValue = _pendingThumbnailValue!;
    _pendingThumbnailValue = null;

    final img = await context.read<VideoPlayerViewModel>().getThumbnailImage(
      targetValue,
    );

    if (mounted && _isHovering) {
      final oldImg = _currentThumbnail;
      _currentThumbnail = img;

      if (_thumbnailOverlay == null && _currentThumbnail != null) {
        _thumbnailOverlay = OverlayEntry(
          builder: (context) {
            return Positioned(
              left: _thumbnailX - 80,
              top: _thumbnailY,
              child: Material(
                color: Colors.transparent,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 160,
                      height: 90,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        border: Border.all(color: Colors.white24, width: 1),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: _currentThumbnail != null
                          ? RawImage(
                              image: _currentThumbnail,
                              fit: BoxFit.cover,
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDuration(_thumbnailValue),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
        Overlay.of(context).insert(_thumbnailOverlay!);
      } else if (_thumbnailOverlay != null) {
        _thumbnailOverlay!.markNeedsBuild();
      }

      oldImg?.dispose();
    } else {
      img?.dispose();
    }

    _isFetchingThumbnail = false;
    if (_pendingThumbnailValue != null) {
      Future.microtask(_fetchNextThumbnail);
    }
  }

  void _handleHover(PointerEvent event, double max) {
    if (_localScrubValue != null) {
      _removeThumbnail();
      return;
    }
    _isHovering = true;
    final RenderBox? box =
        _sliderKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null) {
      final localX = box.globalToLocal(event.position).dx;
      final usableWidth = box.size.width;
      final val = (localX / usableWidth) * max;
      final hoverValue = val.clamp(0.0, max);
      _showThumbnail(hoverValue, max, event.position);
    }
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

    final max = durationSecs > 0 ? durationSecs : 1.0;
    final displayValue = (_localScrubValue ?? _currentPosSecs).clamp(0.0, max);
    return ClipRRect(
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
                    onHover: (event) => _handleHover(event, max),
                    onExit: (_) => _removeThumbnail(),
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
                        key: _sliderKey,
                        value: displayValue,
                        max: max,
                        onChangeStart: (val) {
                          _removeThumbnail();
                          setState(() {
                            _localScrubValue = val;
                          });
                          eventBus.publish(StartScrubbingAction());
                        },
                        onChanged: (val) {
                          setState(() {
                            _localScrubValue = val;
                          });
                          eventBus.publish(UpdateScrubValueAction(val));
                        },
                        onChangeEnd: (val) {
                          eventBus.publish(EndScrubbingAction(val));
                          setState(() {
                            _localScrubValue = null;
                          });
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
                        color: isMuted ? const Color(0xFF555555) : Colors.white,
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
    );
  }

  String _formatDuration(double seconds) {
    if (seconds.isNaN || seconds.isInfinite) return '00:00';
    final int minutes = (seconds / 60).floor();
    final int remainingSeconds = (seconds % 60).floor();
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
