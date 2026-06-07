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
import '../../../application/app_event_bus.dart';

class EffectController extends ChangeNotifier {
  final AppEventBus _eventBus;
  StreamSubscription<AppEvent>? _subscription;

  final Map<String, double> _effects = {
    'smooth': 0.0,
    'blur': 0.0,
    'sharpen': 0.0,
    'unsharp': 0.0,
    'hdr': 0.0,
    'vintage': 0.0,
    'cyberpunk': 0.0,
    'cleancinema': 0.0,
    'vignette': 0.0,
    'super_res': 0.0,
    'deband': 0.0,
    'bloom': 0.0,
    'sharpen_type': 0.0,
  };

  EffectController(this._eventBus);

  void init() {
    _subscription = _eventBus.stream.listen((event) {
      if (event is EffectStateEvent) {
        _effects[event.effect] = event.intensity;
        notifyListeners();
      }
    });
  }

  double getEffect(String key) => _effects[key] ?? 0.0;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
