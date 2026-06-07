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
import '../video_player_view_model.dart';
import '../controller/thumbnail_controller.dart';

class VideoControlBarWidgetController extends ChangeNotifier {
  final BuildContext context;
  final VideoPlayerViewModel viewModel;

  double? _localScrubValue;
  final FocusNode sliderFocusNode = FocusNode(
    canRequestFocus: false,
    skipTraversal: true,
  );
  final FocusNode volumeFocusNode = FocusNode(
    canRequestFocus: false,
    skipTraversal: true,
  );

  final GlobalKey sliderKey = GlobalKey();
  OverlayEntry? _thumbnailOverlay;
  ui.Image? _currentThumbnail;
  double _thumbnailX = 0.0;
  double _thumbnailY = 0.0;
  double _thumbnailValue = 0.0;
  bool _isHovering = false;
  bool _isFetchingThumbnail = false;
  double? _pendingThumbnailValue;

  VideoControlBarWidgetController(this.context, this.viewModel);

  double? get localScrubValue => _localScrubValue;
  ui.Image? get currentThumbnail => _currentThumbnail;
  double get thumbnailX => _thumbnailX;
  double get thumbnailY => _thumbnailY;
  double get thumbnailValue => _thumbnailValue;
  bool get isHovering => _isHovering;

  set localScrubValue(double? val) {
    _localScrubValue = val;
    notifyListeners();
  }

  void removeThumbnail() {
    _isHovering = false;
    _thumbnailOverlay?.remove();
    _thumbnailOverlay = null;
    _pendingThumbnailValue = null;
    _currentThumbnail?.dispose();
    _currentThumbnail = null;
    notifyListeners();
  }

  void showThumbnail(double value, double max, Offset globalPosition) {
    final RenderBox? sliderBox =
        sliderKey.currentContext?.findRenderObject() as RenderBox?;
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
    notifyListeners();
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

    final thumbnailController = context.read<ThumbnailController>();
    final img = await thumbnailController.getThumbnailImage(targetValue);

    if (_isHovering) {
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
        if (context.mounted) {
          Overlay.of(context).insert(_thumbnailOverlay!);
        }
      } else if (_thumbnailOverlay != null) {
        _thumbnailOverlay!.markNeedsBuild();
      }

      oldImg?.dispose();
    } else {
      img?.dispose();
    }

    _isFetchingThumbnail = false;
    notifyListeners();
    if (_pendingThumbnailValue != null) {
      Future.microtask(_fetchNextThumbnail);
    }
  }

  void handleHover(PointerEvent event, double max) {
    if (_localScrubValue != null) {
      removeThumbnail();
      return;
    }
    _isHovering = true;
    final RenderBox? box =
        sliderKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null) {
      final localX = box.globalToLocal(event.position).dx;
      final usableWidth = box.size.width;
      final val = (localX / usableWidth) * max;
      final hoverValue = val.clamp(0.0, max);
      showThumbnail(hoverValue, max, event.position);
    }
  }

  String _formatDuration(double seconds) {
    if (seconds.isNaN || seconds.isInfinite) return '00:00';
    final int minutes = (seconds / 60).floor();
    final int remainingSeconds = (seconds % 60).floor();
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    removeThumbnail();
    sliderFocusNode.dispose();
    volumeFocusNode.dispose();
    super.dispose();
  }
}
