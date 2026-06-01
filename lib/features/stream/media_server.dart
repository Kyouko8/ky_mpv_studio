import 'dart:io' show Platform;

import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:dart_plex/dart_plex.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plex_transcode_session_manager.dart';

// Monotonic, process-unique transcode session id. A FIXED id made the
// server reuse one transcode session for every track (so every song played
// back as the first one) — each request needs its own.
int _sessionSeq = 0;
String _newSession() =>
    'mpv-${DateTime.now().microsecondsSinceEpoch}-${_sessionSeq++}';

// Human-readable device name shown in the servers' "Now Playing" (e.g.
// "Alex's MacBook Pro"). Resolved once at startup via [resolveDeviceName]
// and set with [setMediaDeviceName]; both servers read it when they build
// their credentials. Defaults to the app name until resolved.
String _deviceName = 'MPV Studio';

/// Override the reported device name (call before connecting). See
/// [resolveDeviceName].
void setMediaDeviceName(String name) {
  if (name.trim().isNotEmpty) _deviceName = name.trim();
}

/// Best-effort, header-safe device name for server reporting: the machine
/// name on desktop, the device name on mobile. Falls back to 'MPV Studio'.
Future<String> resolveDeviceName() async {
  try {
    final info = DeviceInfoPlugin();
    String name;
    if (Platform.isMacOS) {
      name = (await info.macOsInfo).computerName;
    } else if (Platform.isIOS) {
      name = (await info.iosInfo).name;
    } else if (Platform.isWindows) {
      name = (await info.windowsInfo).computerName;
    } else if (Platform.isAndroid) {
      final a = await info.androidInfo;
      name = '${a.manufacturer} ${a.model}';
    } else if (Platform.isLinux) {
      name = (await info.linuxInfo).name;
    } else {
      name = 'MPV Studio';
    }
    // Normalise smart quotes, drop double quotes, keep printable ASCII only
    // (X-Plex-* / Jellyfin auth headers must stay ASCII-clean).
    name = name.replaceAll('’', "'").replaceAll('‘', "'");
    name = name.replaceAll('"', '');
    final sanitized = name.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
    return sanitized.isEmpty ? 'MPV Studio' : sanitized;
  } catch (e) {
    debugPrint('resolveDeviceName failed: $e');
    return 'MPV Studio';
  }
}

/// How a track is requested from the server: untouched original bytes
/// (`direct`), or a server-side transcode. The transport protocol for
/// transcoding is server-specific — Jellyfin streams HLS, Plex DASH — so
/// it isn't a user choice; the codec and bitrate are (see [TranscodeCodec]).
enum PlaybackMode { direct, transcode }

/// The media-server backend kind. Embedded in each server [Media]'s extras
/// (`'server'`) so the app-level playback reporter can route a report to the
/// right connected server.
enum ServerKind { jellyfin, plex }

extension PlaybackModeLabel on PlaybackMode {
  String get label => switch (this) {
        PlaybackMode.direct => 'Direct',
        PlaybackMode.transcode => 'Transcode',
      };
}

/// Output audio codec for a server-side transcode. [value] is the wire
/// token both servers accept as their `audioCodec` parameter.
enum TranscodeCodec {
  aac('AAC', 'aac'),
  mp3('MP3', 'mp3'),
  opus('Opus', 'opus');

  final String label;
  final String value;
  const TranscodeCodec(this.label, this.value);
}

/// A server-agnostic audio track — only what the minimal list needs, plus
/// an optional [artUrl] (token-embedded) so the Playback view can show cover
/// art for transcoded streams that carry no embedded metadata.
class ServerTrack {
  final String id;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final String? artUrl;

  const ServerTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    this.artUrl,
  });
}

/// One page of tracks plus the server's total count (for pagination).
class TrackPage {
  final List<ServerTrack> tracks;
  final int total;
  const TrackPage(this.tracks, this.total);
}

/// A connected media library (Jellyfin or Plex), reduced to what the
/// Stream page needs: connect, page/search the song list, and build a
/// playable URL per track. The concrete impls wrap the author's
/// `dart_jellyfin` / `dart_plex` packages; the UI only sees this interface.
abstract class MediaServer {
  String get name;
  bool get isConnected;

  /// Authenticate against [host] (IP or URL) with [username] / [password].
  Future<void> connect({
    required String host,
    required String username,
    required String password,
  });

  /// A page of the user's songs. [query] empty = browse all (sorted by
  /// title); non-empty = search.
  Future<TrackPage> fetchTracks({
    required int startIndex,
    required int pageSize,
    String query = '',
  });

  /// A URL mpv can open directly (auth token embedded in the query) for
  /// [track] in the given [mode]. For [PlaybackMode.transcode] the server
  /// re-encodes to [codec] capped at [bitrateKbps]; both are ignored for
  /// direct play.
  String streamUrl(
    ServerTrack track,
    PlaybackMode mode, {
    String codec,
    int bitrateKbps,
  });

  /// The real segment container for a transcode [mode] — which mpv can't
  /// report (its `file-format` only shows the `hls`/`dash` protocol). Null
  /// for direct play, where mpv reports the true container itself. Depends
  /// on [codec] because the chosen codec dictates the segment wrapper.
  String? segmentContainer(PlaybackMode mode, {String codec});

  /// Re-establish a previously saved session (token) without a password.
  /// Returns true when a stored session was restored. Does not verify the
  /// token is still valid — a stale token surfaces as a load error.
  Future<bool> tryRestore();

  /// Drop the session and forget the stored credentials.
  Future<void> logout();

  // ─── Playback reporting ──────────────────────────────────────────────
  // Tell the server what's playing so it shows in "Now Playing", advances
  // on-deck / play progress, and scrobbles. All are best-effort: failures
  // are swallowed (logged) so a reporting hiccup never disrupts playback.

  /// Which backend this is — lets the reporter route to the right server.
  ServerKind get kind;

  /// Playback of [itemId] has started.
  Future<void> reportStart(String itemId);

  /// Periodic progress for [itemId]: current [position] and whether [paused].
  Future<void> reportProgress(
    String itemId, {
    required Duration position,
    required bool paused,
  });

  /// Playback of [itemId] stopped at [position].
  Future<void> reportStopped(String itemId, {required Duration position});
}

/// Adds a scheme (http) and the platform default port when the user typed a
/// bare IP, and trims a trailing slash. Leaves explicit scheme/port alone.
String _normalizeBase(String host, int defaultPort) {
  var h = host.trim();
  if (h.isEmpty) return h;
  if (!h.contains('://')) h = 'http://$h';
  var uri = Uri.parse(h);
  if (!uri.hasPort) uri = uri.replace(port: defaultPort);
  return uri.toString().replaceAll(RegExp(r'/+$'), '');
}

// ── Jellyfin ──────────────────────────────────────────────────────────

class JellyfinServer implements MediaServer {
  JellyfinClient? _client;

  // Built per access so it picks up the resolved [_deviceName]. `client`
  // is the app (shown as the Jellyfin "Client"); `device` is the machine
  // name (shown as the "Device").
  JellyfinCredentials get _credentials => JellyfinCredentials(
        client: 'MPV Studio',
        device: _deviceName,
        deviceId: 'mpv-studio',
        version: '0.1.0',
      );

  static const _kBase = 'jellyfin.base';
  static const _kToken = 'jellyfin.token';
  static const _kUserId = 'jellyfin.userId';

  @override
  String get name => 'Jellyfin';

  @override
  bool get isConnected => _client?.token != null;

  @override
  Future<void> connect({
    required String host,
    required String username,
    required String password,
  }) async {
    final base = _normalizeBase(host, 8096);
    final client = JellyfinClient(baseUrl: base, credentials: _credentials);
    final auth = await client.user
        .authenticateByName(username: username, password: password);
    client.setSession(token: auth.accessToken, userId: auth.user.id);
    _client = client;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kBase, base);
    await p.setString(_kToken, auth.accessToken);
    await p.setString(_kUserId, auth.user.id);
  }

  @override
  Future<bool> tryRestore() async {
    final p = await SharedPreferences.getInstance();
    final base = p.getString(_kBase);
    final token = p.getString(_kToken);
    final userId = p.getString(_kUserId);
    if (base == null || token == null || userId == null) return false;
    final client = JellyfinClient(baseUrl: base, credentials: _credentials);
    client.setSession(token: token, userId: userId);
    _client = client;
    return true;
  }

  @override
  Future<void> logout() async {
    _client = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kBase);
    await p.remove(_kToken);
    await p.remove(_kUserId);
  }

  @override
  Future<TrackPage> fetchTracks({
    required int startIndex,
    required int pageSize,
    String query = '',
  }) async {
    final res = await _client!.items.list(
      includeItemTypes: const [JellyfinItemKind.audio],
      recursive: true,
      sortBy: const ['SortName'],
      startIndex: startIndex,
      limit: pageSize,
      searchTerm: query.isEmpty ? null : query,
    );
    final token = _client!.token!;
    final tracks = [
      for (final it in res.items)
        ServerTrack(
          id: it.id,
          title: it.name,
          artist: it.artists.isNotEmpty
              ? it.artists.join(', ')
              : (it.albumArtist ?? ''),
          album: it.album ?? '',
          // runTimeTicks are 100-ns units → microseconds = ticks / 10.
          duration: Duration(microseconds: (it.runTimeTicks ?? 0) ~/ 10),
          artUrl: _imageUrl(it.id, token),
        ),
    ];
    return TrackPage(tracks, res.totalRecordCount);
  }

  // Primary (album) image. The images API omits the token, so append it —
  // private servers reject image requests otherwise. A 404 (no art) just
  // falls through to the placeholder in the UI.
  String _imageUrl(String itemId, String token) {
    final u = _client!.images
        .url(itemId: itemId, fillWidth: 400, fillHeight: 400);
    return u.contains('?') ? '$u&api_key=$token' : '$u?api_key=$token';
  }

  @override
  String streamUrl(
    ServerTrack track,
    PlaybackMode mode, {
    String codec = 'aac',
    int bitrateKbps = 256,
  }) {
    final audio = _client!.audio;
    // Jellyfin transcodes over HLS. The playlist stays .m3u8; only the
    // per-segment container changes with the codec. AAC/Opus go in fMP4
    // ('mp4'): MPEG-TS cannot carry edit lists, so the AAC encoder priming
    // (~2112 samples) is never skipped at each segment boundary → recurring
    // PTS discontinuities ("Invalid audio PTS"); fMP4 carries the edit list
    // (demuxed by ffmpeg's mov/mp4 path) so priming is skipped and segment
    // boundaries stay sample-accurate. Opus is valid in fMP4 too. MP3 has
    // no edit-list priming problem and is awkward in fMP4, so it rides
    // MPEG-TS ('ts') — its long-standing native container.
    return switch (mode) {
      PlaybackMode.direct => audio.directStreamUrl(itemId: track.id).$1,
      PlaybackMode.transcode => audio.universalStreamUrl(
          itemId: track.id,
          audioCodec: codec,
          containers: const ['aac', 'mp3', 'flac', 'ogg', 'opus'],
          transcodingProtocol: 'hls',
          transcodingContainer: codec == 'mp3' ? 'ts' : 'mp4',
          maxStreamingBitrate: bitrateKbps * 1000,
          audioBitRate: bitrateKbps * 1000,
          playSessionId: _newSession(),
        ),
    };
  }

  @override
  String? segmentContainer(PlaybackMode mode, {String codec = 'aac'}) =>
      mode == PlaybackMode.transcode
          ? (codec == 'mp3' ? 'MPEG-TS' : 'fMP4')
          : null;

  @override
  ServerKind get kind => ServerKind.jellyfin;

  @override
  Future<void> reportStart(String itemId) async {
    final c = _client;
    if (c == null) return;
    try {
      await c.playback.start(itemId: itemId);
    } catch (e) {
      debugPrint('JellyfinServer: reportStart failed: $e');
    }
  }

  @override
  Future<void> reportProgress(
    String itemId, {
    required Duration position,
    required bool paused,
  }) async {
    final c = _client;
    if (c == null) return;
    try {
      await c.playback
          .progress(itemId: itemId, position: position, isPaused: paused);
    } catch (e) {
      debugPrint('JellyfinServer: reportProgress failed: $e');
    }
  }

  @override
  Future<void> reportStopped(String itemId, {required Duration position}) async {
    final c = _client;
    if (c == null) return;
    try {
      await c.playback.stopped(itemId: itemId, position: position);
    } catch (e) {
      debugPrint('JellyfinServer: reportStopped failed: $e');
    }
  }
}

// ── Plex ──────────────────────────────────────────────────────────────

class PlexServer implements MediaServer {
  PlexClient? _client;
  String? _musicSectionId;
  PlexTranscodeSessionManager? _transcodes;

  // Built per access so it picks up the resolved [_deviceName]. `device` /
  // `deviceName` are the machine name (shown in Now Playing); `platform` is
  // a SEPARATE field — the transcode-profile selector (see [_platform]).
  PlexCredentials get _credentials => PlexCredentials(
        clientIdentifier: 'mpv-studio',
        product: 'MPV Studio',
        version: '0.1.0',
        device: _deviceName,
        deviceName: _deviceName,
        // Plex selects a base transcode profile by X-Plex-Platform; an
        // unrecognised value 400s the /decision with "Unable to find
        // client profile for device". So map the real OS to a
        // Plex-recognised platform name (see [_platform]).
        platform: _platform,
        // Seed a base musicProfile transcode target. The per-track
        // add-transcode-target in PlexTranscodeSessionManager.resolve only
        // *extends* an existing music profile — without this seed there is
        // no musicProfile context to extend, so Plex ignores our audioCodec
        // and the transcode never starts.
        clientProfileExtra:
            'add-transcode-target(type=musicProfile&context=streaming'
            '&protocol=hls&container=mpegts&audioCodec=aac,mp3)',
      );

  // X-Plex-Platform value Plex uses to pick the transcode client profile.
  // An unrecognised value makes /transcode/universal/decision return 400
  // ("Unable to find client profile for device"), so transcode never
  // starts. Verified against a live PMS: iOS / Android / Windows resolve to
  // a built-in profile; macOS, Linux (and anything else) do NOT — for those
  // we send 'Generic', Plex's own profile for custom/unrecognised clients,
  // which transcodes fine. This is the platform reported for profile
  // matching only; the app's real identity stays in product/deviceName.
  static String get _platform {
    if (Platform.isIOS) return 'iOS';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isWindows) return 'Windows';
    // macOS, Linux, etc.: no built-in Plex profile → fall back to Generic.
    return 'Generic';
  }

  static const _kBase = 'plex.base';
  static const _kToken = 'plex.token';
  static const _kSection = 'plex.section';

  @override
  String get name => 'Plex';

  @override
  bool get isConnected => _client?.isAuthenticated ?? false;

  @override
  Future<void> connect({
    required String host,
    required String username,
    required String password,
  }) async {
    final base = _normalizeBase(host, 32400);
    final client = PlexClient(credentials: _credentials);
    // Account auth goes to plex.tv; the token then authorises the local PMS.
    final user = await client.account
        .signInWithPassword(username: username, password: password);
    client.setToken(user.authToken);
    client.connect(base, accessToken: user.authToken);
    final sections = await client.library.sections();
    final music = sections.firstWhere(
      (s) => s.type == PlexLibraryType.music,
      orElse: () => sections.first,
    );
    _musicSectionId = music.id;
    _client = client;
    _transcodes = PlexTranscodeSessionManager(client);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kBase, base);
    await p.setString(_kToken, user.authToken);
    await p.setString(_kSection, music.id);
  }

  @override
  Future<bool> tryRestore() async {
    final p = await SharedPreferences.getInstance();
    final base = p.getString(_kBase);
    final token = p.getString(_kToken);
    final section = p.getString(_kSection);
    if (base == null || token == null || section == null) return false;
    final client = PlexClient(credentials: _credentials);
    client.setToken(token);
    client.connect(base, accessToken: token);
    _musicSectionId = section;
    _client = client;
    _transcodes = PlexTranscodeSessionManager(client);
    return true;
  }

  @override
  Future<void> logout() async {
    _transcodes?.clear();
    _transcodes = null;
    _client = null;
    _musicSectionId = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kBase);
    await p.remove(_kToken);
    await p.remove(_kSection);
  }

  @override
  Future<TrackPage> fetchTracks({
    required int startIndex,
    required int pageSize,
    String query = '',
  }) async {
    final res = await _client!.library.allByType(
      sectionId: _musicSectionId!,
      type: PlexMetadataType.track,
      start: startIndex,
      size: pageSize,
      sort: 'titleSort',
      title: query.isEmpty ? null : query,
    );
    final tracks = [
      for (final m in res.items)
        ServerTrack(
          id: m.ratingKey,
          title: m.title,
          artist: m.grandparentTitle ?? '',
          album: m.parentTitle ?? '',
          duration: Duration(milliseconds: m.durationMs ?? 0),
          artUrl: _imageUrl(m.parentThumb ?? m.grandparentThumb),
        ),
    ];
    return TrackPage(tracks, res.totalSize);
  }

  // Album/artist thumbnail through Plex's photo transcoder (token embedded).
  String? _imageUrl(String? sourcePath) {
    if (sourcePath == null || sourcePath.isEmpty) return null;
    return _client!.images
        .transcodeUrl(sourcePath: sourcePath, width: 400, height: 400);
  }

  @override
  String streamUrl(
    ServerTrack track,
    PlaybackMode mode, {
    String codec = 'aac',
    int bitrateKbps = 256,
  }) {
    final streaming = _client!.streaming;
    final directUrl = streaming.universalAudioUrl(
      ratingKey: track.id,
      protocol: 'http',
      directPlay: true,
      directStream: true,
    );
    // BOTH modes hand mpv a `plex-transcode://{session}` marker that the
    // global on_load hook resolves just before playback. Plex's universal
    // `start.*` URL isn't openable by mpv, so:
    //   • direct   → the hook resolves to the original media Part URL;
    //   • transcode→ /decision spins up a session → real start.mpd (and on a
    //     non-playable decision, falls back to the same Part URL).
    // [directUrl] is only the last-resort fallback if the Part can't be found.
    return _transcodes!.register(
      ratingKey: track.id,
      codec: codec,
      fallbackUrl: directUrl,
      bitrateKbps: bitrateKbps,
      transcode: mode == PlaybackMode.transcode,
    );
  }

  @override
  String? segmentContainer(PlaybackMode mode, {String codec = 'aac'}) =>
      mode == PlaybackMode.transcode ? 'fMP4' : null;

  @override
  ServerKind get kind => ServerKind.plex;

  @override
  Future<void> reportStart(String itemId) =>
      _timeline(itemId, PlexPlaybackApi.statePlaying, Duration.zero);

  @override
  Future<void> reportProgress(
    String itemId, {
    required Duration position,
    required bool paused,
  }) =>
      _timeline(
        itemId,
        paused ? PlexPlaybackApi.statePaused : PlexPlaybackApi.statePlaying,
        position,
      );

  @override
  Future<void> reportStopped(String itemId, {required Duration position}) =>
      // `continuing: true` mirrors Plex Web's track-transition report so the
      // server doesn't reap the (still-warm) transcode session when the next
      // track starts.
      _timeline(itemId, PlexPlaybackApi.stateStopped, position,
          continuing: true);

  Future<void> _timeline(
    String ratingKey,
    String state,
    Duration position, {
    bool continuing = false,
  }) async {
    final c = _client;
    if (c == null) return;
    try {
      await c.playback.timeline(
        ratingKey: ratingKey,
        state: state,
        timeMs: position.inMilliseconds,
        durationMs: 0,
        continuing: continuing,
      );
    } catch (e) {
      debugPrint('PlexServer: timeline($state) failed: $e');
    }
  }
}
