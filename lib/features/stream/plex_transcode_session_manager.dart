import 'package:dart_plex/dart_plex.dart';
import 'package:flutter/foundation.dart';

/// Owns the lifecycle of Plex audio transcode sessions.
///
/// Unlike Jellyfin (whose `/Audio/.../universal` URL is self-contained and
/// can be handed straight to mpv), Plex's transcode pipeline needs three
/// steps the client must drive itself:
///
///   1. **register** a logical session up-front and hand mpv a
///      `plex-transcode://{session}` *marker* URL (synchronous — happens in
///      [PlexServer.streamUrl]);
///   2. call `/transcode/universal/decision` **lazily**, when mpv actually
///      opens the track via its `on_load` hook ([resolve]) — this is what
///      tells Plex to spin up the transcoder and pick the right
///      codec/container, and turns the marker into a real `start.mpd` URL;
///   3. **ping** the session every ~20 s ([ping]) so Plex doesn't reap it
///      while the player is paused or buffering — a reaped session makes
///      every later segment fetch 404.
///
/// The on_load hook is global (one [Player]) but a marker can belong to any
/// server instance, so the manager keeps a static [_registry] keyed by
/// session id. The hook resolves through [resolveMarker] / [pingActive],
/// which route to whichever instance created the marker.
class PlexTranscodeSessionManager {
  PlexTranscodeSessionManager(this._client);

  final PlexClient _client;

  /// `'dash'` → `start.mpd` + fMP4 segments (sample-accurate timestamps;
  /// the path Plex documents for audio). `'hls'` → `start.m3u8` + MPEG-TS.
  String preferredProtocol = 'dash';

  static const _markerPrefix = 'plex-transcode://';

  /// session id → pending entry, for this instance.
  final Map<String, _PendingTranscode> _pending = {};

  /// Process-wide session id → owning manager, so the single global
  /// on_load hook can route any marker back to the right instance.
  static final Map<String, PlexTranscodeSessionManager> _registry = {};

  /// The session mpv most recently opened — the one the ping heartbeat
  /// must keep warm. Updated on every successful [resolve].
  static String? _activeSession;

  int _seq = 0;

  // ─── Registration (sync, from streamUrl) ─────────────────────────────

  /// Register a transcode session for [ratingKey] and return the
  /// `plex-transcode://{session}` marker URL to hand to mpv. The real
  /// `/decision` call is deferred to [resolve]. [fallbackUrl] is used if
  /// the decision fails (direct play).
  String register({
    required String ratingKey,
    required String codec,
    required String fallbackUrl,
    int? bitrateKbps,
    bool transcode = true,
  }) {
    final session = 'mpv-${DateTime.now().microsecondsSinceEpoch}-${_seq++}';
    final clientId = _client.credentials.clientIdentifier;
    _pending[session] = _PendingTranscode(
      transcode: transcode,
      params: <String, dynamic>{
        'path': '/library/metadata/$ratingKey',
        'mediaIndex': 0,
        'partIndex': 0,
        'protocol': preferredProtocol,
        'directPlay': 0,
        'directStream': 0,
        'audioCodec': codec,
        if (bitrateKbps != null) ...{
          'maxAudioBitrate': bitrateKbps,
          'musicBitrate': bitrateKbps,
        },
        'session': session,
        'X-Plex-Client-Identifier': clientId,
        'X-Plex-Session-Identifier': session,
      },
      fallbackUrl: fallbackUrl,
    );
    _registry[session] = this;
    if (_pending.length > 200) {
      final oldest = _pending.keys.first;
      _pending.remove(oldest);
      _registry.remove(oldest);
    }
    return '$_markerPrefix$session';
  }

  // ─── Lazy resolution (mpv on_load hook) ──────────────────────────────

  /// Resolve a `plex-transcode://{session}` marker — called from the global
  /// on_load hook via [resolveMarker]. Runs `/decision`, then builds the
  /// real manifest URL. Memoised so a re-open (prefetch + play, retries)
  /// doesn't re-hit `/decision`. Returns null only for an unknown session.
  Future<({String url, Map<String, String> headers})?> resolve(
    String markerUrl,
  ) async {
    final session = markerUrl.replaceFirst(_markerPrefix, '');
    final pending = _pending[session];
    if (pending == null) {
      debugPrint('PlexTranscode: no pending session for $session');
      return null;
    }
    _activeSession = session;

    final cached = pending.resolved;
    if (cached != null) return cached;

    // Direct-play session: skip /decision entirely and stream the original
    // media Part (the universal-transcoder start.* URL isn't openable by mpv).
    if (!pending.transcode) {
      final direct = await _directPlayUrl(
        pending.params['path'] as String,
        pending.fallbackUrl,
      );
      debugPrint('PlexTranscode: direct play $session → $direct');
      return pending.resolved =
          (url: direct, headers: const <String, String>{});
    }

    final params = pending.params;
    final codec = params['audioCodec'] as String? ?? 'aac';
    final token = _client.token ?? '';
    final isHls = preferredProtocol == 'hls';
    final container = isHls ? 'mpegts' : 'mp4';
    final manifestExt = isHls ? 'm3u8' : 'mpd';

    // Bitrate, when requested, must be enforced via add-limitation — the
    // maxAudioBitrate query param alone is ignored by Plex for music.
    final bitrate = params['maxAudioBitrate'] as int?;
    final bitrateLimit = bitrate != null
        ? '+add-limitation(scope=musicCodec&scopeName=$codec'
            '&type=upperBound&name=audio.bitrate&value=$bitrate'
            '&isRequired=false&reason=)'
        : '';
    // Override the global client profile so Plex emits the codec/container
    // we want instead of the profile's first target.
    final profileValue =
        'add-transcode-target(type=musicProfile&context=streaming'
        '&protocol=$preferredProtocol&container=$container&audioCodec=$codec)'
        '$bitrateLimit';

    try {
      final decision = await _client.streaming.decisionUniversal(
        params: params,
        extraHeaders: {'X-Plex-Client-Profile-Extra': profileValue},
      );
      // Accept any *playable* decision, not just isTranscode (2xxx).
      // With directPlay=0/directStream=0 Plex cannot direct-play, so a
      // successful decision comes back as 1001 "Direct play not available;
      // Conversion OK" — that IS a transcode (it spins up a session and a
      // valid start.mpd). isTranscode only matches 2xxx and so wrongly
      // rejected 1001, falling back to direct play. isPlayable (isDirect ||
      // isTranscode) is the correct gate. Only a genuinely non-playable
      // decision (no/error code) falls through to the direct part URL.
      if (!decision.isPlayable) {
        debugPrint('PlexTranscode: decision=${decision.code} not playable '
            '→ direct play');
        final direct = await _directPlayUrl(
          params['path'] as String,
          pending.fallbackUrl,
        );
        return pending.resolved =
            (url: direct, headers: const <String, String>{});
      }
      debugPrint('PlexTranscode: decision=${decision.code} → transcode');

      // ffmpeg/lavf opens the manifest directly and does NOT inherit the
      // Dio request's X-Plex-* base headers, so we embed the full client
      // identity + profile in the query string — otherwise Plex returns
      // 400 "Unable to find client profile for device".
      final queryString = params.entries
          .map((e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value.toString())}')
          .join('&');
      final creds = _client.credentials;
      final manifestUrl =
          '${_client.baseUrl}/music/:/transcode/universal/start.$manifestExt?$queryString'
          '&X-Plex-Token=${Uri.encodeQueryComponent(token)}'
          '&X-Plex-Client-Profile-Extra=${Uri.encodeQueryComponent(profileValue)}'
          '&X-Plex-Platform=${Uri.encodeQueryComponent(creds.platform)}'
          '&X-Plex-Device=${Uri.encodeQueryComponent(creds.deviceName)}'
          '&X-Plex-Device-Name=${Uri.encodeQueryComponent(creds.deviceName)}'
          '&X-Plex-Product=${Uri.encodeQueryComponent(creds.product)}'
          '&X-Plex-Version=${Uri.encodeQueryComponent(creds.version)}';
      debugPrint('PlexTranscode: resolved $session (decision=${decision.code})');
      return pending.resolved =
          (url: manifestUrl, headers: const <String, String>{});
    } catch (e) {
      // Network/auth failure: degrade to direct play and memoise so we
      // don't hammer /decision on every re-open.
      debugPrint('PlexTranscode: resolve error for $session: $e → direct play');
      final direct = await _directPlayUrl(
        params['path'] as String,
        pending.fallbackUrl,
      );
      return pending.resolved =
          (url: direct, headers: const <String, String>{});
    }
  }

  /// Resolve a track to a *direct-play* URL mpv can actually open.
  ///
  /// On a direct-play / direct-stream decision (or any /decision failure)
  /// the universal-transcoder `start.*` URL is not openable by mpv — Plex
  /// serves the original file from its media Part instead. So we fetch the
  /// item metadata, take the first media Part's key and build
  /// `{baseUrl}{partKey}?download=0&X-Plex-Token=…` (the form a working Plex
  /// client uses). [metadataPath] is `/library/metadata/{ratingKey}`;
  /// [lastResort] is returned only if no part can be resolved.
  Future<String> _directPlayUrl(String metadataPath, String lastResort) async {
    final ratingKey = metadataPath.split('/').last;
    try {
      final meta = await _client.library.item(ratingKey);
      final media =
          (meta?.media.isNotEmpty ?? false) ? meta!.media.first : null;
      final part =
          (media?.parts.isNotEmpty ?? false) ? media!.parts.first : null;
      final partKey = part?.key;
      if (partKey == null) return lastResort;
      final token = _client.token ?? '';
      return '${_client.baseUrl}$partKey?download=0'
          '&X-Plex-Token=${Uri.encodeQueryComponent(token)}';
    } catch (e) {
      debugPrint('PlexTranscode: directPlayUrl fetch failed for $ratingKey: $e');
      return lastResort;
    }
  }

  /// Keep the live session alive (Plex reaps stagnant ones in ~2 min).
  Future<void> ping(String session) async {
    if (_client.baseUrl == null || session.isEmpty) return;
    final plexSessionId =
        _pending[session]?.params['session'] as String? ?? session;
    try {
      await _client.streaming.pingUniversal(plexSessionId);
    } catch (_) {
      // Silent — the next tick retries; logging would spam on hiccups.
    }
  }

  /// Forget every session owned by this instance (e.g. on logout).
  void clear() {
    for (final s in _pending.keys) {
      _registry.remove(s);
    }
    if (_activeSession != null && !_registry.containsKey(_activeSession)) {
      _activeSession = null;
    }
    _pending.clear();
  }

  // ─── Static entry points for the global on_load hook ─────────────────

  /// Parse the session id out of a `plex-transcode://…` URL, or null if
  /// [url] isn't a marker (so the hook can ignore plain http/file URLs).
  static String? extractMarker(String url) {
    if (!url.startsWith(_markerPrefix)) return null;
    final sid = url.substring(_markerPrefix.length);
    return sid.isEmpty ? null : sid;
  }

  /// Route a marker URL to its owning manager and resolve it. Returns null
  /// if [url] is not a marker or its session is unknown.
  static Future<({String url, Map<String, String> headers})?> resolveMarker(
    String url,
  ) {
    final sid = extractMarker(url);
    if (sid == null) return Future.value(null);
    final mgr = _registry[sid];
    if (mgr == null) return Future.value(null);
    return mgr.resolve(url);
  }

  /// Ping the session mpv is currently playing, if it's a transcode.
  static Future<void> pingActive() async {
    final sid = _activeSession;
    if (sid == null) return;
    await _registry[sid]?.ping(sid);
  }
}

class _PendingTranscode {
  _PendingTranscode({
    required this.params,
    required this.fallbackUrl,
    required this.transcode,
  });
  final Map<String, dynamic> params;
  final String fallbackUrl;

  /// Whether this session should transcode (`/decision` → `start.mpd`) or
  /// just direct-play the original media Part. Direct play skips `/decision`
  /// — the universal-transcoder `start.*` URL is not openable by mpv, so we
  /// always resolve to the Part URL instead.
  final bool transcode;

  ({String url, Map<String, String> headers})? resolved;
}
