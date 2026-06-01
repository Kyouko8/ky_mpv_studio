import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'app.dart';
import 'features/stream/media_server.dart';
import 'features/stream/playback_reporter.dart';
import 'features/stream/plex_transcode_session_manager.dart';
import 'state/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  // App-level media servers (Jellyfin / Plex). They live here — not inside
  // the Stream page — so their sessions and the playback reporting survive
  // navigating away from that page. Restore any saved session up front.
  // Resolve the real device name first so it shows in Now Playing.
  setMediaDeviceName(await resolveDeviceName());
  final jellyfin = JellyfinServer();
  final plex = PlexServer();
  final servers = <ServerKind, MediaServer>{
    ServerKind.jellyfin: jellyfin,
    ServerKind.plex: plex,
  };
  await Future.wait([jellyfin.tryRestore(), plex.tryRestore()]);

  // Report playback (start / progress / stop) of server tracks back to
  // their server, for Now Playing + scrobble. Lives for the whole session.
  PlaybackReporter(player, servers).start();

  runApp(MpvStudioApp(player: player, settings: settings, servers: servers));
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
      debugPrint('PlexTranscode hook: on_load url="$url"');
      if (PlexTranscodeSessionManager.extractMarker(url) == null) return;
      final resolved =
          await PlexTranscodeSessionManager.resolveMarker(url);
      if (resolved == null) {
        // stale/unknown session — mpv will now open the raw marker and
        // emit "no protocol handler found". Log loudly so we can see it.
        debugPrint(
          'PlexTranscode hook: resolveMarker returned null for "$url" '
          '— mpv will fail to open this URL',
        );
        return;
      }
      debugPrint('PlexTranscode hook: rewriting → ${resolved.url}');
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
    } catch (e, st) {
      // mpv_studio previously had no catch here, so any throw was swallowed
      // and the marker leaked through to mpv silently. Surface it.
      debugPrint('PlexTranscode hook: error — $e\n$st');
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
