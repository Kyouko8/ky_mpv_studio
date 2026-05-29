import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'state/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1100, 760),
      minimumSize: Size(380, 600),
      center: true,
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  MpvAudioKit.ensureInitialized();

  // Persisted settings, restored before the first frame.
  final settings = await AppSettings.load();

  final player = Player(
    configuration: PlayerConfiguration(
      initialVolume: settings.volume,
      autoPlay: true,
      logLevel: LogLevel.info,
    ),
  );

  // Native OS media session (Control Center / SMTC / MPRIS / lockscreen).
  // Metadata is derived from mpv's own properties automatically.
  await player.setMediaSession(const MediaSession());

  // Re-apply the user's last engine configuration and DSP rack, then
  // start snapshotting future changes back to disk.
  await settings.applyTo(player);
  await player.setAudioEffects(settings.effects);
  settings.attach(player);

  runApp(MpvStudioApp(player: player, settings: settings));
}
