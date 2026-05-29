import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'shell/app_shell.dart';
import 'state/app_settings.dart';
import 'state/player_scope.dart';
import 'ui/theme.dart';

/// Root widget. Holds the single [Player] and the app services, exposes
/// them via [PlayerScope], and tears the player down on process exit.
class MpvStudioApp extends StatefulWidget {
  final Player player;
  final AppSettings settings;
  const MpvStudioApp({
    super.key,
    required this.player,
    required this.settings,
  });

  @override
  State<MpvStudioApp> createState() => _MpvStudioAppState();
}

class _MpvStudioAppState extends State<MpvStudioApp> {
  @override
  void dispose() {
    unawaited(widget.settings.dispose());
    unawaited(widget.player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // PlayerScope sits ABOVE MaterialApp so pushed routes (which live
    // under MaterialApp's Navigator) can still read the player/services.
    return PlayerScope(
      player: widget.player,
      settings: widget.settings,
      child: MaterialApp(
        title: 'MPV Studio',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: const AppShell(),
      ),
    );
  }
}
