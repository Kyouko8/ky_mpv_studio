import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:dart_plex/dart_plex.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plex_transcode_session_manager.dart';

// Monotonic, process-unique transcode session id. A FIXED id made the
// server reuse one transcode session for every track (so every song played
// back as the first one) — each request needs its own.
int _sessionSeq = 0;
String _newSession() =>
    'mpv-${DateTime.now().microsecondsSinceEpoch}-${_sessionSeq++}';

/// How a track is requested from the server: untouched original bytes
/// (`direct`), or a server-side transcode to Opus. The transport protocol
/// for transcoding is server-specific — Jellyfin streams HLS, Plex DASH —
/// so it isn't a user choice, only Direct vs Transcode is.
enum PlaybackMode { direct, transcode }

extension PlaybackModeLabel on PlaybackMode {
  String get label => switch (this) {
        PlaybackMode.direct => 'Direct',
        PlaybackMode.transcode => 'Transcode',
      };
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
  /// [track] in the given [mode]. Transcode modes request the Opus codec.
  String streamUrl(ServerTrack track, PlaybackMode mode);

  /// The real segment container for a transcode [mode] — which mpv can't
  /// report (its `file-format` only shows the `hls`/`dash` protocol). Null
  /// for direct play, where mpv reports the true container itself.
  String? segmentContainer(PlaybackMode mode);

  /// Re-establish a previously saved session (token) without a password.
  /// Returns true when a stored session was restored. Does not verify the
  /// token is still valid — a stale token surfaces as a load error.
  Future<bool> tryRestore();

  /// Drop the session and forget the stored credentials.
  Future<void> logout();
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

  static const _credentials = JellyfinCredentials(
    client: 'MPV Studio',
    device: 'MPV Studio',
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
  String streamUrl(ServerTrack track, PlaybackMode mode) {
    final audio = _client!.audio;
    // Jellyfin transcodes over HLS. The playlist stays .m3u8; only the
    // per-segment container changes. We request fMP4 ('mp4') segments, not
    // MPEG-TS: MPEG-TS cannot carry edit lists, so the AAC encoder priming
    // (~2112 samples) is never skipped at each segment boundary → recurring
    // PTS discontinuities ("Invalid audio PTS"). fMP4 segments carry the
    // edit list and are demuxed by ffmpeg's mov/mp4 path, so priming is
    // skipped and segment boundaries are sample-accurate. AAC stays the
    // codec — it's valid in fMP4 too. (Opus would also be safe here, but
    // AAC keeps server CPU/compat overhead lowest.)
    return switch (mode) {
      PlaybackMode.direct => audio.directStreamUrl(itemId: track.id).$1,
      PlaybackMode.transcode => audio.universalStreamUrl(
          itemId: track.id,
          audioCodec: 'aac',
          containers: const ['aac', 'mp3', 'flac', 'ogg', 'opus'],
          transcodingProtocol: 'hls',
          transcodingContainer: 'mp4',
          playSessionId: _newSession(),
        ),
    };
  }

  @override
  String? segmentContainer(PlaybackMode mode) =>
      mode == PlaybackMode.transcode ? 'fMP4' : null;
}

// ── Plex ──────────────────────────────────────────────────────────────

class PlexServer implements MediaServer {
  PlexClient? _client;
  String? _musicSectionId;
  PlexTranscodeSessionManager? _transcodes;

  static const _credentials = PlexCredentials(
    clientIdentifier: 'mpv-studio',
    product: 'MPV Studio',
    version: '0.1.0',
    device: 'Flutter',
    deviceName: 'MPV Studio',
    platform: 'Flutter',
  );

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
  String streamUrl(ServerTrack track, PlaybackMode mode) {
    final streaming = _client!.streaming;
    final directUrl = streaming.universalAudioUrl(
      ratingKey: track.id,
      protocol: 'http',
      directPlay: true,
      directStream: true,
    );
    // Plex transcodes over DASH (fMP4 segments). Unlike Jellyfin, the
    // transcode can't be a plain URL: Plex needs a /decision call to spin
    // up the session and pick the codec/container. So we hand mpv a
    // `plex-transcode://{session}` marker; the global on_load hook resolves
    // it via the session manager (decision → real start.mpd) right before
    // playback, and a heartbeat pings the session to keep it alive. The
    // direct URL is the fallback if /decision refuses.
    return switch (mode) {
      PlaybackMode.direct => directUrl,
      PlaybackMode.transcode => _transcodes!.register(
          ratingKey: track.id,
          codec: 'opus',
          fallbackUrl: directUrl,
        ),
    };
  }

  @override
  String? segmentContainer(PlaybackMode mode) =>
      mode == PlaybackMode.transcode ? 'fMP4' : null;
}
