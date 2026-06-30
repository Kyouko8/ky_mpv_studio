import 'dart:async';

import 'package:dart_plex/dart_plex.dart';
import 'package:flutter/foundation.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

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

  /// Whether any Plex transcode marker is currently registered. The global
  /// on_load hook gates on this: a `plex-transcode://` marker can only exist
  /// after [PlexServer.streamUrl] → [register] has run, and that runs
  /// synchronously while the playlist is built, before `openAll` triggers the
  /// load. So when this is false the load being opened is NOT Plex (Jellyfin /
  /// YouTube / local file) and the hook can skip its work entirely — no Plex
  /// track is ever missed. Stays false for a whole session that never plays
  /// Plex; cleared back to empty on [clear] (logout).
  static bool get hasRegisteredSessions => _registry.isNotEmpty;

  /// The session mpv most recently opened — the one the ping heartbeat
  /// must keep warm. Updated on every successful [resolve].
  static String? _activeSession;

  int _seq = 0;

  // ─── Registration (sync, from streamUrl) ─────────────────────────────

  /// Register a transcode session for [ratingKey] and return the
  /// `plex-transcode://{session}` marker URL to hand to mpv. The real
  /// `/decision` call is deferred to [resolve]. [fallbackUrl] is used if
  /// the decision fails (direct play). [protocol] (`dash` → start.mpd,
  /// `hls` → start.m3u8) defaults to [preferredProtocol]; [container]
  /// (`mp4` → fMP4, `mpegts`) defaults to the protocol's natural one
  /// (DASH→mp4, HLS→mpegts). Both are captured per-session so different
  /// tracks can use different transports.
  String register({
    required String ratingKey,
    required String codec,
    required String fallbackUrl,
    int? bitrateKbps,
    bool transcode = true,
    String? protocol,
    String? container,
  }) {
    final session = 'mpv-${DateTime.now().microsecondsSinceEpoch}-${_seq++}';
    final clientId = _client.credentials.clientIdentifier;
    final sessionProtocol = protocol ?? preferredProtocol;
    final sessionContainer =
        container ?? (sessionProtocol == 'hls' ? 'mpegts' : 'mp4');
    _pending[session] = _PendingTranscode(
      transcode: transcode,
      protocol: sessionProtocol,
      container: sessionContainer,
      params: <String, dynamic>{
        'path': '/library/metadata/$ratingKey',
        'mediaIndex': 0,
        'partIndex': 0,
        'protocol': sessionProtocol,
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
    final isHls = pending.protocol == 'hls';
    final container = pending.container;
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
        '&protocol=${pending.protocol}&container=$container&audioCodec=$codec)'
        '$bitrateLimit';

    try {
      final decision = await _client.streaming.decisionUniversal(
        params: params,
        extraHeaders: {'X-Plex-Client-Profile-Extra': profileValue},
      );
      // Accept any playable decision. With directPlay=0 and directStream=0
      // Plex can't direct-play, so a successful decision comes back as a
      // 1xxx code (e.g. 1001 "Direct play not available; Conversion OK"),
      // which spins up a transcode session and a valid start.mpd. As of
      // dart_plex 0.1.0 isPlayable is true for any 1xxx decision; only a
      // genuinely non-playable decision (an error code) falls through to
      // the direct part URL.
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
    required this.protocol,
    required this.container,
  });
  final Map<String, dynamic> params;
  final String fallbackUrl;

  /// Plex transcode protocol for this session: `dash` (start.mpd) or `hls`
  /// (start.m3u8).
  final String protocol;

  /// Segment container Plex packages each chunk in: `mp4` (fMP4) or `mpegts`.
  /// Independent of [protocol] except that DASH only carries fMP4.
  final String container;

  /// Whether this session should transcode (`/decision` → `start.mpd`) or
  /// just direct-play the original media Part. Direct play skips `/decision`
  /// — the universal-transcoder `start.*` URL is not openable by mpv, so we
  /// always resolve to the Part URL instead.
  final bool transcode;

  ({String url, Map<String, String> headers})? resolved;
}

/// Wire Plex's transcode flow into the [player]. Plex hands mpv a
/// `plex-transcode://{session}` marker URL (it can't be a plain URL — Plex
/// needs a `/decision` round-trip first). The on_load hook intercepts each
/// file open, resolves the marker to the real `start.mpd` URL via the
/// session manager, and rewrites `stream-open-filename` before mpv opens it.
/// A heartbeat then pings the live session so Plex doesn't reap it while
/// paused/buffering. Non-marker URLs (Jellyfin, files, direct play) pass
/// straight through.
Future<void> wirePlexTranscodeHook(Player player) async {
  await player.registerHook(Hook.load, timeout: const Duration(seconds: 10));
  player.stream.hook.listen((event) async {
    if (event.hook != Hook.load) {
      await player.continueHook(event.id);
      return;
    }
    try {
      // Gate to Plex-only: with no marker registered, the load being opened
      // cannot be a Plex transcode (register() runs synchronously in
      // streamUrl, before openAll fires this load), so skip the
      // stream-open-filename read and marker work entirely. This keeps the
      // hook a true no-op on every Jellyfin / YouTube / local-file load
      // instead of doing an async property read on each one.
      if (!PlexTranscodeSessionManager.hasRegisteredSessions) return;
      final url = await player.getRawProperty('stream-open-filename') ?? '';
      debugPrint('PlexTranscode hook: on_load url="$url"');
      if (PlexTranscodeSessionManager.extractMarker(url) == null) return;
      final resolved = await PlexTranscodeSessionManager.resolveMarker(url);
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
      // Any throw here would otherwise be swallowed and the marker would
      // leak through to mpv silently. Surface it.
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
