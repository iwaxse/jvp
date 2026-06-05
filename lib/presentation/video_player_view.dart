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
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../application/app_event_bus.dart';
import 'video_player_view_model.dart';
import 'components/shader_settings_panel_widget.dart';
import 'components/video_control_bar_widget.dart';
import 'components/video_drop_target_widget.dart';

class VideoPlayerView extends StatefulWidget {
  const VideoPlayerView({super.key});

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> {
  bool _showTuner = false;
  bool _showControlBar = true;
  StreamSubscription<ToggleTunerAction>? _tunerSub;
  Timer? _leftHoldTimer;
  Timer? _leftTapTimer;
  Timer? _rightTapTimer;
  bool _isRightHolding = false;
  bool _isLeftHolding = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final eventBus = context.read<AppEventBus>();
      _tunerSub = eventBus.on<ToggleTunerAction>().listen((_) {
        setState(() {
          _showTuner = !_showTuner;
        });
      });
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _tunerSub?.cancel();
    _leftHoldTimer?.cancel();
    _leftTapTimer?.cancel();
    _rightTapTimer?.cancel();
    super.dispose();
  }

  bool _onKeyEvent(KeyEvent event) {
    final viewModel = context.read<VideoPlayerViewModel>();

    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.space) {
        viewModel.togglePlay();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyD) {
        setState(() {
          _showControlBar = !_showControlBar;
        });
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        if (_leftTapTimer != null || _isLeftHolding) return true;
        viewModel.stepFrame(-1);
        _leftTapTimer = Timer(const Duration(milliseconds: 200), () {
          _isLeftHolding = true;
          _leftHoldTimer = Timer.periodic(const Duration(milliseconds: 33), (
            timer,
          ) {
            viewModel.stepFrame(-1);
          });
        });
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        if (_rightTapTimer != null || _isRightHolding) return true;
        viewModel.stepFrame(1);
        _rightTapTimer = Timer(const Duration(milliseconds: 200), () {
          _isRightHolding = true;
          viewModel.play();
        });
        return true;
      }
    }

    if (event is KeyUpEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        if (_leftTapTimer != null) {
          _leftTapTimer!.cancel();
          _leftTapTimer = null;
        }
        if (_isLeftHolding) {
          _isLeftHolding = false;
          _leftHoldTimer?.cancel();
          _leftHoldTimer = null;
        }
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        if (_rightTapTimer != null) {
          _rightTapTimer!.cancel();
          _rightTapTimer = null;
        }
        if (_isRightHolding) {
          _isRightHolding = false;
          viewModel.pause();
        }
        return true;
      }
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.read<VideoPlayerViewModel>();
    final isLoaded = context.select<VideoPlayerViewModel, bool>(
      (vm) => vm.isLoaded,
    );
    final textureId = context.select<VideoPlayerViewModel, int?>(
      (vm) => vm.textureId,
    );
    final width = context.select<VideoPlayerViewModel, int>((vm) => vm.width);
    final height = context.select<VideoPlayerViewModel, int>((vm) => vm.height);

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
                setState(() {
                  _showTuner = !_showTuner;
                });
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
              right: _showTuner ? 364 : 24,
              bottom: _showControlBar ? 24 : -100,
              child: const VideoControlBarWidget(),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              top: 0,
              bottom: 0,
              right: _showTuner ? 0 : -340,
              width: 340,
              child: ShaderSettingsPanelWidget(
                onClose: () {
                  setState(() {
                    _showTuner = false;
                  });
                },
              ),
            ),
          ],
        ),
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
