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
import 'package:flutter/foundation.dart';
import 'app_event_bus.dart';
import '../domain/repository/video_repository.dart';

class CommandHandler {
  final VideoRepository _repository;
  final AppEventBus _eventBus;
  StreamSubscription<AppEvent>? _subscription;

  CommandHandler(this._repository, this._eventBus);

  void init() {
    _subscription = _eventBus.stream.listen((event) async {
      if (event is AppCommand) {
        try {
          await event.execute(_repository, _eventBus);
        } catch (e) {
          debugPrint(
            "CommandHandler: Error executing command ${event.runtimeType}: $e",
          );
        }
      }
    });
  }

  void dispose() {
    _subscription?.cancel();
  }
}
