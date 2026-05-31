import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'features/stream/plex_transcode_session_manager.dart';
import 'state/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    // `--dart-define=mobilePreview=true` shrinks the window to a phone
    // viewport so the mobile shell + layouts can be exercised on desktop.
    const mobilePreview = bool.fromEnvironment('mobilePreview');
    final options = WindowOptions(
      size: mobilePreview ? const Size(393, 852) : const Size(1100, 760),
      minimumSize: const Size(380, 600),
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

  await _wirePlexTranscode(player);

  runApp(MpvStudioApp(player: player, settings: settings));
}

/// Wire Plex's transcode flow into the player. Plex hands mpv a
/// `plex-transcode://{session}` marker URL (it can't be a plain URL — Plex
/// needs a `/decision` round-trip first). The on_load hook intercepts each
/// file open, resolves the marker to the real `start.mpd` URL via the
/// session manager, and rewrites `stream-open-filename` before mpv opens it.
/// A heartbeat then pings the live session so Plex doesn't reap it while
/// paused/buffering. Non-marker URLs (Jellyfin, files, direct play) pass
/// straight through.
Future<void> _wirePlexTranscode(Player player) async {
  await player.registerHook(Hook.load, timeout: const Duration(seconds: 10));
  player.stream.hook.listen((event) async {
    if (event.hook != Hook.load) {
      await player.continueHook(event.id);
      return;
    }
    try {
      final url = await player.getRawProperty('stream-open-filename') ?? '';
      if (PlexTranscodeSessionManager.extractMarker(url) == null) return;
      final resolved =
          await PlexTranscodeSessionManager.resolveMarker(url);
      if (resolved == null) return; // stale/unknown session — mpv will fail
      await player.setRawProperty('stream-open-filename', resolved.url);
      if (resolved.headers.isNotEmpty) {
        final headerString = resolved.headers.entries
            .map((e) => '${e.key}: ${e.value}')
            .join(',');
        await player.setRawProperty(
          'file-local-options/http-header-fields',
          headerString,
        );
      }
    } finally {
      // Must always fire — even on error — or mpv stalls on the hook.
      await player.continueHook(event.id);
    }
  });

  // Keep the active Plex transcode session warm (~2 min reap window).
  Timer.periodic(
    const Duration(seconds: 20),
    (_) => PlexTranscodeSessionManager.pingActive(),
  );
}
