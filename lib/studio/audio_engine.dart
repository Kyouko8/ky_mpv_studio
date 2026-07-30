import 'package:flutter/foundation.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../features/console/console_log.dart';
import '../features/stream/media_server.dart';
import 'app_settings.dart';
import 'server_manager.dart';

/// Builds the single [Player] and brings it to a ready state: publishes the
/// OS media session, restores the user's persisted engine configuration and
/// DSP rack, and starts snapshotting future changes back to disk. Also
/// returns an always-on [ConsoleLog] that captures the engine log from boot
/// so the Console shows the full backlog whenever it's first opened.
///
/// The [Player] stays the single runtime source of truth; [settings] only
/// seeds it on launch ([AppSettings.applyTo]) and records changes
/// ([AppSettings.attach]).
Future<({Player player, ConsoleLog consoleLog})> startAudioEngine(
  AppSettings settings,
) async {
  // Build-time configuration is assembled from the persisted knobs (resume,
  // watch-later dir, force-seekable, HLS bitrate, downmix normalization,
  // demuxer cache dir). It is read once here — the Settings UI records changes
  // that take effect on the next launch.
  final player = Player(configuration: settings.playerConfiguration);

  // Start log capture immediately — before any other setup emits log lines —
  // so nothing is lost before the Console is first opened.
  final consoleLog = ConsoleLog()..attach(player);

  // Native OS media session (Control Center / SMTC / MPRIS / lockscreen).
  // The advertised controls are user-customisable on the Session settings
  // page; `null` when the user disabled the session entirely.
  await player.setMediaSession(settings.mediaSession);

  // The library auto-applies inbound OS commands to the player; this
  // subscription is the interception/analytics hook — observe every
  // lockscreen / headset / Bluetooth / Siri command as it lands.
  player.stream.mediaSessionCommands.listen(
    (command) => debugPrint('MediaSession command from OS: $command'),
  );

  // Re-apply the user's last engine configuration and DSP rack, then
  // start snapshotting future changes back to disk.
  await settings.applyTo(player);
  await player.setAudioEffects(settings.effects);
  settings.attach(player);

  return (player: player, consoleLog: consoleLog);
}

/// A unified on_load hook that handles background server connection, credential-rebuilding,
/// and streaming URL refreshing on track load. If connection fails, the track is skipped gracefully.
Future<void> wireMediaServersHook(Player player, ServerManager serverManager) async {
  await player.registerHook(Hook.load, timeout: const Duration(seconds: 12));
  player.stream.hook.listen((event) async {
    if (event.hook != Hook.load) {
      await player.continueHook(event.id);
      return;
    }

    try {
      final url = await player.getRawProperty('stream-open-filename') ?? '';
      debugPrint('MediaServers hook: on_load url="$url"');

      // Find the loading Media item from the player's active playlist
      final playlist = player.state.playlist;
      Media? currentMedia;
      if (playlist.index >= 0 && playlist.index < playlist.items.length) {
        currentMedia = playlist.items[playlist.index];
      }
      if (currentMedia == null || (currentMedia.uri != url && !url.startsWith('plex-transcode://'))) {
        for (final item in playlist.items) {
          if (item.uri == url) {
            currentMedia = item;
            break;
          }
        }
      }

      if (currentMedia == null) {
        return;
      }

      final extras = currentMedia.extras;
      if (extras == null) {
        return;
      }

      final serverInstanceId = extras['serverInstanceId'] as String?;
      if (serverInstanceId == null) {
        return;
      }

      // Find the server instance
      final instanceIdx = serverManager.instances.indexWhere((i) => i.id == serverInstanceId);
      if (instanceIdx == -1) {
        debugPrint('Server instance $serverInstanceId not found. Skipping track.');
        await player.setRawProperty('stream-open-filename', 'null://');
        return;
      }

      final instance = serverManager.instances[instanceIdx];
      final server = serverManager.getOrCreateServer(instance);

      // Ensure connected
      if (!server.isConnected) {
        try {
          debugPrint('Server ${instance.name} is not connected. Attempting auto-connect...');
          await server.tryRestore().timeout(const Duration(seconds: 4));
          if (!server.isConnected) {
            await server.connect(
              host: instance.host,
              username: instance.username,
              password: instance.password,
            ).timeout(const Duration(seconds: 5));
          }
        } catch (e) {
          debugPrint('Failed to connect to ${instance.name}: $e');
        }
      }

      if (!server.isConnected) {
        debugPrint('Server ${instance.name} connection failed. Skipping/omitting track.');
        await player.setRawProperty('stream-open-filename', 'null://');
        return;
      }

      // Refresh URL
      if (instance.kind == ServerKind.jellyfin) {
        final serverId = extras['serverId'] as String?;
        if (serverId != null) {
          final mode = PlaybackMode.values.byName(extras['playbackMode'] as String? ?? 'transcode');
          final codec = extras['codec'] as String? ?? 'aac';
          final bitrateKbps = extras['bitrateKbps'] as int? ?? 256;
          final transport = StreamTransport.values.byName(extras['transport'] as String? ?? 'fmp4');
          final protocol = StreamProtocol.values.byName(extras['protocol'] as String? ?? 'hls');
          final durationMs = extras['durationMs'] as int? ?? 0;

          final track = ServerTrack(
            id: serverId,
            title: extras['title'] as String? ?? '',
            artist: extras['artist'] as String? ?? '',
            album: extras['album'] as String? ?? '',
            duration: Duration(milliseconds: durationMs),
          );

          final freshUrl = server.streamUrl(
            track,
            mode,
            codec: codec,
            bitrateKbps: bitrateKbps,
            transport: transport,
            protocol: protocol,
          );

          debugPrint('MediaServers hook: Jellyfin URL refreshed successfully.');
          await player.setRawProperty('stream-open-filename', freshUrl);

          final lavfOptions = server.demuxerLavfOptions(mode, codec: codec, transport: transport, protocol: protocol);
          if (lavfOptions != null && lavfOptions.isNotEmpty) {
            final headerString = lavfOptions.entries.map((e) => '${e.key}: ${e.value}').join(',');
            await player.setRawProperty('file-local-options/http-header-fields', headerString);
          }
        }
      } else if (instance.kind == ServerKind.plex) {
        final serverId = extras['serverId'] as String?;
        if (serverId != null) {
          final mode = PlaybackMode.values.byName(extras['playbackMode'] as String? ?? 'transcode');
          final codec = extras['codec'] as String? ?? 'aac';
          final bitrateKbps = extras['bitrateKbps'] as int? ?? 256;
          final transport = StreamTransport.values.byName(extras['transport'] as String? ?? 'fmp4');
          final protocol = StreamProtocol.values.byName(extras['protocol'] as String? ?? 'dash');
          final durationMs = extras['durationMs'] as int? ?? 0;

          final track = ServerTrack(
            id: serverId,
            title: extras['title'] as String? ?? '',
            artist: extras['artist'] as String? ?? '',
            album: extras['album'] as String? ?? '',
            duration: Duration(milliseconds: durationMs),
          );

          final markerUrl = server.streamUrl(
            track,
            mode,
            codec: codec,
            bitrateKbps: bitrateKbps,
            transport: transport,
            protocol: protocol,
          );

          final plexServer = server as PlexServer;
          final resolved = await plexServer.transcodes?.resolve(markerUrl);
          if (resolved != null) {
            debugPrint('MediaServers hook: Plex URL resolved successfully.');
            await player.setRawProperty('stream-open-filename', resolved.url);
            if (resolved.headers.isNotEmpty) {
              final headerString = resolved.headers.entries.map((e) => '${e.key}: ${e.value}').join(',');
              await player.setRawProperty('file-local-options/http-header-fields', headerString);
            }
          } else {
            await player.setRawProperty('stream-open-filename', 'null://');
          }
        }
      } else if (instance.kind == ServerKind.samba) {
        final filePath = extras['path'] as String?;
        if (filePath != null) {
          String enc(String s) => Uri.encodeComponent(s);
          String encPath(String p) => p.split('/').where((s) => s.isNotEmpty).map(enc).join('/');
          final dom = instance.domain.isEmpty ? '' : '${enc(instance.domain)};';
          final auth = instance.username.isEmpty
              ? ''
              : (instance.password.isEmpty
                  ? '$dom${enc(instance.username)}@'
                  : '$dom${enc(instance.username)}:${enc(instance.password)}@');
          final freshUrl = 'smb2://$auth${instance.host}/${encPath(instance.share)}/${encPath(filePath)}';

          debugPrint('MediaServers hook: Samba URL rebuilt successfully.');
          await player.setRawProperty('stream-open-filename', freshUrl);
        }
      }
    } catch (e, st) {
      debugPrint('Error in MediaServers hook: $e\n$st');
    } finally {
      await player.continueHook(event.id);
    }
  });
}
