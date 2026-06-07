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

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'infrastructure/adapter/rust/generated/frb_generated.dart';
import 'infrastructure/repository/video_repository_impl.dart';
import 'infrastructure/repository/playlist_repository_impl.dart';
import 'application/app_event_bus.dart';
import 'application/command_handler.dart';
import 'application/usecase/open_file_usecase.dart';
import 'domain/repository/video_repository.dart';
import 'domain/repository/playlist_repository.dart';
import 'presentation/video_player_view_model.dart';
import 'presentation/video_player_view.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) {
    final String dylibPath = Platform.isMacOS
        ? '${Directory.current.path}/rust/target/debug/librust_lib_jvp.dylib'
        : Platform.isWindows
        ? '${Directory.current.path}/rust/target/debug/rust_lib_jvp.dll'
        : '${Directory.current.path}/rust/target/debug/librust_lib_jvp.so';
    await RustLib.init(externalLibrary: ExternalLibrary.open(dylibPath));
  } else {
    if (Platform.isMacOS) {
      final String dylibPath =
          '${File(Platform.resolvedExecutable).parent.parent.path}/Frameworks/librust_lib_jvp.dylib';
      if (await File(dylibPath).exists()) {
        await RustLib.init(externalLibrary: ExternalLibrary.open(dylibPath));
      } else {
        await RustLib.init();
      }
    } else {
      await RustLib.init();
    }
  }
  final eventBus = AppEventBus();
  final repository = VideoRepositoryImpl();
  final playlistRepository = PlaylistRepositoryImpl();

  final viewModel = VideoPlayerViewModel(
    repository,
    playlistRepository,
    eventBus,
  );
  runApp(
    MultiProvider(
      providers: [
        Provider<AppEventBus>.value(value: eventBus),
        Provider<VideoRepository>.value(value: repository),
        Provider<PlaylistRepository>.value(value: playlistRepository),
        Provider<CommandHandler>(
          create: (_) => CommandHandler(repository, eventBus)..init(),
          dispose: (_, handler) => handler.dispose(),
          lazy: false,
        ),
        ChangeNotifierProvider<VideoPlayerViewModel>.value(value: viewModel),
      ],
      child: const MyApp(),
    ),
  );
  if (args.isNotEmpty) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      eventBus.publish(OpenFileUseCase(args[0], volume: 0.0));
    });
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'jvp - video player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          surface: Color(0xFF141414),
        ),
      ),
      home: const VideoPlayerView(),
    );
  }
}
