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

import '../app_event_bus.dart';
import '../../../domain/repository/video_repository.dart';

class ToggleAbLoopingCommand extends AppCommand {
  final bool currentIsAbLooping;
  final bool currentIsLooping;

  ToggleAbLoopingCommand({
    required this.currentIsAbLooping,
    required this.currentIsLooping,
  });

  @override
  Future<void> execute(VideoRepository repository, AppEventBus eventBus) async {
    final nextEnabled = !currentIsAbLooping;
    eventBus.publish(
      ABLoopStateEvent(
        isEnabled: nextEnabled,
        restoreLooping: nextEnabled ? currentIsLooping : null,
      ),
    );
    if (nextEnabled) {
      eventBus.publish(LoopingStateEvent(false));
    }
  }
}
