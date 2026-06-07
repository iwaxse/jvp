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
import '../../../application/app_event_bus.dart';
import '../../../application/commands/toggle_play_command.dart';
import '../../../application/commands/step_frame_command.dart';
import '../video_player_view_model.dart';

class VideoPlayerUiController extends ChangeNotifier {
  final BuildContext context;
  final VideoPlayerViewModel viewModel;

  bool _showSideMenu = false;
  int _sideMenuTabIndex = 0;
  bool _showControlBar = true;
  bool _isDraggingFile = false;
  StreamSubscription<ToggleTunerAction>? _tunerSubscription;

  Timer? _leftHoldTimer;
  Timer? _leftTapTimer;
  Timer? _rightTapTimer;
  Timer? _rightHoldTimer;
  bool _isRightHolding = false;
  bool _isLeftHolding = false;
  double? _scrubTargetPos;
  bool _wasPlayingBeforeHold = false;

  bool get showSideMenu => _showSideMenu;
  int get sideMenuTabIndex => _sideMenuTabIndex;
  bool get showControlBar => _showControlBar;
  bool get isDraggingFile => _isDraggingFile;

  set showSideMenu(bool val) {
    _showSideMenu = val;
    notifyListeners();
  }

  set sideMenuTabIndex(int val) {
    _sideMenuTabIndex = val;
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

  VideoPlayerUiController(this.context, this.viewModel) {
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    _tunerSubscription = context
        .read<AppEventBus>()
        .on<ToggleTunerAction>()
        .listen((_) {
          _showSideMenu = true;
          _sideMenuTabIndex = 2;
          notifyListeners();
        });
  }

  bool _onKeyEvent(KeyEvent event) {
    final eventBus = context.read<AppEventBus>();
    final key = event.logicalKey;

    final handledKeys = {
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.shiftRight,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.keyF,
      LogicalKeyboardKey.keyD,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
    };

    if (!handledKeys.contains(key)) return false;

    if (event is KeyDownEvent) {
      if (key == LogicalKeyboardKey.space) {
        eventBus.publish(
          TogglePlayCommand(currentIsPlaying: viewModel.isPlaying),
        );
      } else if (key == LogicalKeyboardKey.keyF) {
        _showSideMenu = !_showSideMenu;
        notifyListeners();
      } else if (key == LogicalKeyboardKey.keyD) {
        _showControlBar = !_showControlBar;
        notifyListeners();
      } else if (key == LogicalKeyboardKey.arrowLeft) {
        if (_leftTapTimer == null && !_isLeftHolding) {
          _scrubTargetPos = viewModel.currentPosSecs;
          eventBus.publish(
            StepFrameCommand(
              frames: -1,
              currentIsPlaying: viewModel.isPlaying,
              currentPosSecs: _scrubTargetPos!,
              fps: viewModel.fps,
              durationSecs: viewModel.durationSecs,
            ),
          );
          _scrubTargetPos = (_scrubTargetPos! - (1.0 / viewModel.fps)).clamp(
            0.0,
            viewModel.durationSecs,
          );
          _leftTapTimer = Timer(const Duration(milliseconds: 200), () {
            _isLeftHolding = true;
            _leftHoldTimer = Timer.periodic(const Duration(milliseconds: 16), (
              t,
            ) {
              if (_scrubTargetPos == 0.0) return;
              final keys = HardwareKeyboard.instance.logicalKeysPressed;
              final shift =
                  keys.contains(LogicalKeyboardKey.shiftLeft) ||
                  keys.contains(LogicalKeyboardKey.shiftRight);
              if (!shift && t.tick % 2 != 0) return;
              eventBus.publish(
                StepFrameCommand(
                  frames: 0,
                  currentIsPlaying: viewModel.isPlaying,
                  currentPosSecs: _scrubTargetPos!,
                  fps: viewModel.fps,
                  durationSecs: viewModel.durationSecs,
                  accurate: !shift,
                ),
              );
              _scrubTargetPos = (_scrubTargetPos! - (1.0 / viewModel.fps))
                  .clamp(0.0, viewModel.durationSecs);
            });
          });
        }
      } else if (key == LogicalKeyboardKey.arrowRight) {
        if (_rightTapTimer == null && !_isRightHolding) {
          _wasPlayingBeforeHold = viewModel.isPlaying;
          _scrubTargetPos = viewModel.currentPosSecs;
          eventBus.publish(
            StepFrameCommand(
              frames: 1,
              currentIsPlaying: viewModel.isPlaying,
              currentPosSecs: _scrubTargetPos!,
              fps: viewModel.fps,
              durationSecs: viewModel.durationSecs,
            ),
          );
          _scrubTargetPos = (_scrubTargetPos! + (1.0 / viewModel.fps)).clamp(
            0.0,
            viewModel.durationSecs,
          );
          _rightTapTimer = Timer(const Duration(milliseconds: 200), () {
            _isRightHolding = true;
            final keys = HardwareKeyboard.instance.logicalKeysPressed;
            final shift =
                keys.contains(LogicalKeyboardKey.shiftLeft) ||
                keys.contains(LogicalKeyboardKey.shiftRight);
            if (shift) {
              _rightHoldTimer = Timer.periodic(
                const Duration(milliseconds: 16),
                (t) {
                  if (_scrubTargetPos == viewModel.durationSecs) return;
                  final k = HardwareKeyboard.instance.logicalKeysPressed;
                  final s =
                      k.contains(LogicalKeyboardKey.shiftLeft) ||
                      k.contains(LogicalKeyboardKey.shiftRight);
                  if (!s && t.tick % 2 != 0) return;
                  eventBus.publish(
                    StepFrameCommand(
                      frames: 0,
                      currentIsPlaying: viewModel.isPlaying,
                      currentPosSecs: _scrubTargetPos!,
                      fps: viewModel.fps,
                      durationSecs: viewModel.durationSecs,
                      accurate: !s,
                    ),
                  );
                  _scrubTargetPos = (_scrubTargetPos! + (1.0 / viewModel.fps))
                      .clamp(0.0, viewModel.durationSecs);
                },
              );
            } else if (!_wasPlayingBeforeHold) {
              eventBus.publish(TogglePlayCommand(currentIsPlaying: false));
            }
          });
        }
      }
    } else if (event is KeyUpEvent) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        _leftTapTimer?.cancel();
        _leftTapTimer = null;
        if (_isLeftHolding) {
          _isLeftHolding = false;
          _leftHoldTimer?.cancel();
          _leftHoldTimer = null;
          eventBus.publish(
            StepFrameCommand(
              frames: 0,
              currentIsPlaying: viewModel.isPlaying,
              currentPosSecs: viewModel.currentPosSecs,
              fps: viewModel.fps,
              durationSecs: viewModel.durationSecs,
              accurate: true,
            ),
          );
        }
        _scrubTargetPos = null;
      } else if (key == LogicalKeyboardKey.arrowRight) {
        _rightTapTimer?.cancel();
        _rightTapTimer = null;
        if (_isRightHolding) {
          _isRightHolding = false;
          if (_rightHoldTimer != null) {
            _rightHoldTimer!.cancel();
            _rightHoldTimer = null;
            eventBus.publish(
              StepFrameCommand(
                frames: 0,
                currentIsPlaying: viewModel.isPlaying,
                currentPosSecs: viewModel.currentPosSecs,
                fps: viewModel.fps,
                durationSecs: viewModel.durationSecs,
                accurate: true,
              ),
            );
          } else if (!_wasPlayingBeforeHold) {
            eventBus.publish(TogglePlayCommand(currentIsPlaying: true));
          }
        }
        _scrubTargetPos = null;
      }
    }

    return true;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _tunerSubscription?.cancel();
    _leftHoldTimer?.cancel();
    _leftTapTimer?.cancel();
    _rightTapTimer?.cancel();
    _rightHoldTimer?.cancel();
    super.dispose();
  }
}
