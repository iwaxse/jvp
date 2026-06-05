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
import '../application/usecase/toggle_play_usecase.dart';
import '../application/usecase/step_frame_usecase.dart';
import 'video_player_view_model.dart';

class VideoPlayerViewController extends ChangeNotifier {
  final BuildContext context;
  final VideoPlayerViewModel viewModel;

  bool _showTuner = false;
  bool _showControlBar = true;
  bool _isDraggingFile = false;
  StreamSubscription<ToggleTunerAction>? _tunerSubscription;

  Timer? _leftHoldTimer;
  Timer? _leftTapTimer;
  Timer? _rightTapTimer;
  bool _isRightHolding = false;
  bool _isLeftHolding = false;

  bool get showTuner => _showTuner;
  bool get showControlBar => _showControlBar;
  bool get isDraggingFile => _isDraggingFile;

  set showTuner(bool val) {
    _showTuner = val;
    notifyListeners();
  }

  set showControlBar(bool val) {
    _showControlBar = val;
    notifyListeners();
  }

  set isDraggingFile(bool val) {
    _isDraggingFile = val;
    notifyListeners();
  }

  VideoPlayerViewController(this.context, this.viewModel) {
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    _tunerSubscription = context
        .read<AppEventBus>()
        .on<ToggleTunerAction>()
        .listen((_) {
          _showTuner = !_showTuner;
          notifyListeners();
        });
  }

  bool _onKeyEvent(KeyEvent event) {
    final eventBus = context.read<AppEventBus>();
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.space) {
        eventBus.publish(
          TogglePlayUseCase(currentIsPlaying: viewModel.isPlaying),
        );
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyD) {
        _showControlBar = !_showControlBar;
        notifyListeners();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        if (_leftTapTimer != null || _isLeftHolding) return true;
        eventBus.publish(
          StepFrameUseCase(
            frames: -1,
            currentIsPlaying: viewModel.isPlaying,
            currentPosSecs: viewModel.currentPosSecs,
            fps: viewModel.fps,
            durationSecs: viewModel.durationSecs,
          ),
        );
        _leftTapTimer = Timer(const Duration(milliseconds: 200), () {
          _isLeftHolding = true;
          _leftHoldTimer = Timer.periodic(const Duration(milliseconds: 33), (
            timer,
          ) {
            eventBus.publish(
              StepFrameUseCase(
                frames: -1,
                currentIsPlaying: viewModel.isPlaying,
                currentPosSecs: viewModel.currentPosSecs,
                fps: viewModel.fps,
                durationSecs: viewModel.durationSecs,
              ),
            );
          });
        });
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        if (_rightTapTimer != null || _isRightHolding) return true;
        eventBus.publish(
          StepFrameUseCase(
            frames: 1,
            currentIsPlaying: viewModel.isPlaying,
            currentPosSecs: viewModel.currentPosSecs,
            fps: viewModel.fps,
            durationSecs: viewModel.durationSecs,
          ),
        );
        _rightTapTimer = Timer(const Duration(milliseconds: 200), () {
          _isRightHolding = true;
          eventBus.publish(TogglePlayUseCase(currentIsPlaying: false));
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
          eventBus.publish(TogglePlayUseCase(currentIsPlaying: true));
        }
        return true;
      }
    }

    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _tunerSubscription?.cancel();
    _leftHoldTimer?.cancel();
    _leftTapTimer?.cancel();
    _rightTapTimer?.cancel();
    super.dispose();
  }
}
