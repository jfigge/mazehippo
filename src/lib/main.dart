import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/store.dart';
import 'app/title_screen.dart';
import 'audio/ambience.dart';
import 'audio/audio_settings.dart';
import 'render/board_painter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Not waited for: these are requests to the platform about how the window
  // behaves, not work the first frame depends on.
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
  // Portrait, because the board is square and the shorter side is what fits it
  // — so landscape would spend the extra width on nothing while making every
  // dot smaller.
  unawaited(
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]),
  );
  // These two *are* waited for, and before the first frame rather than after
  // it. The title screen's main button is "Continue — level 37", and one that
  // said "Play" for a frame and then corrected itself would be wrong exactly
  // once: on the launch the player was looking at it.
  await progress.load();
  await audioSettings.load();
  // Note what is *not* here. The audio engine is not started and nothing is
  // decoded — that happens on the way into the first puzzle, which is the first
  // thing that needs a sound. Launch is as fast as it was before there was any.
  runApp(const MazeHippoApp());
}

class MazeHippoApp extends StatefulWidget {
  const MazeHippoApp({super.key});

  @override
  State<MazeHippoApp> createState() => _MazeHippoAppState();
}

class _MazeHippoAppState extends State<MazeHippoApp> {
  /// The bed follows the app in and out of the foreground.
  ///
  /// Fade and pause, **never** deinit: tearing the engine down and building it
  /// again costs a visible stutter on Android, and the player switching away for
  /// ten seconds is a player who is coming back.
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onPause: ambience.sleep,
    onInactive: ambience.sleep,
    onResume: ambience.wake,
  );

  @override
  void initState() {
    super.initState();
    _lifecycle; // ignore: unnecessary_statements
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    // At the app's level and nowhere else. A screen that disposed the engine on
    // its way out would take the bed with it every time the player opened the
    // level list.
    unawaited(ambience.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Maze Hippo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(
        useMaterial3: true,
      ).copyWith(scaffoldBackgroundColor: BoardPainter.background),
      home: const TitleScreen(),
    );
  }
}
