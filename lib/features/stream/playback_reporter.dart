import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'media_server.dart';

/// App-level service that reports playback of media-server tracks back to
/// their server (Jellyfin / Plex): start, periodic progress, and stop. This
/// drives the server's "Now Playing", play-progress / on-deck, and scrobble.
///
/// It listens to the single app [Player] and routes each report to the right
/// connected [MediaServer] using the `'server'` / `'serverId'` keys embedded
/// in the playing [Media]'s extras (see `ServerLibraryTab`). Tracks without
/// those extras (the Lab tab, local files) are ignored. All reporting is
/// best-effort — the server impls swallow their own errors.
class PlaybackReporter {
  PlaybackReporter(this._player, this._servers);

  final Player _player;
  final Map<ServerKind, MediaServer> _servers;

  /// How often a still-playing track re-reports its position.
  static const _progressInterval = Duration(seconds: 15);

  ServerKind? _kind;
  String? _itemId;
  bool _started = false;

  Timer? _progressTimer;
  final List<StreamSubscription<dynamic>> _subs = [];

  /// Begin listening. Safe to call once at app start.
  void start() {
    _subs.add(_player.stream.playlist.listen((_) => _onPlaylist()));
    _subs.add(_player.stream.playing.listen(_onPlaying));
    _subs.add(_player.stream.completed.listen((done) {
      if (done) _reportStop();
    }));
  }

  Future<void> dispose() async {
    _progressTimer?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
  }

  // ─── Stream handlers ──────────────────────────────────────────────────

  void _onPlaylist() {
    final (kind, id) = _currentTrack();
    if (id == _itemId && kind == _kind) return; // same track — nothing new
    _reportStop(); // stop the previous track (no-op if none / not started)
    _kind = kind;
    _itemId = id;
    _started = false;
    _maybeStart();
  }

  void _onPlaying(bool playing) {
    if (_itemId == null) return;
    if (!_started) {
      _maybeStart();
      return;
    }
    // Already started: reflect the pause/resume immediately so the server's
    // Now Playing shows the right state, and keep the progress timer in sync.
    _reportProgress(paused: !playing);
    if (playing) {
      _restartTimer();
    } else {
      _progressTimer?.cancel();
    }
  }

  // ─── Reporting ────────────────────────────────────────────────────────

  void _maybeStart() {
    if (_started || _itemId == null) return;
    if (!_player.state.playing) return; // wait for actual playback
    final server = _servers[_kind];
    if (server == null) return;
    _started = true;
    debugPrint('PlaybackReporter: start ${_kind!.name} $_itemId');
    server.reportStart(_itemId!);
    _restartTimer();
  }

  void _reportProgress({required bool paused}) {
    if (!_started || _itemId == null) return;
    _servers[_kind]?.reportProgress(
      _itemId!,
      position: _player.state.position,
      paused: paused,
    );
  }

  void _reportStop() {
    if (!_started || _itemId == null) return;
    debugPrint('PlaybackReporter: stop ${_kind!.name} $_itemId '
        '@ ${_player.state.position}');
    _servers[_kind]?.reportStopped(_itemId!, position: _player.state.position);
    _started = false;
    _progressTimer?.cancel();
  }

  void _restartTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(_progressInterval, (_) {
      if (_started && _player.state.playing) _reportProgress(paused: false);
    });
  }

  // ─── Current track resolution ─────────────────────────────────────────

  /// The currently-playing track's (server kind, server item id), or
  /// (null, null) when there is no current item or it isn't a server track.
  (ServerKind?, String?) _currentTrack() {
    final playlist = _player.state.playlist;
    final items = playlist.items;
    final i = playlist.index;
    if (i < 0 || i >= items.length) return (null, null);
    final extras = items[i].extras;
    if (extras == null) return (null, null);
    final id = extras['serverId'];
    final serverName = extras['server'];
    if (id is! String || serverName is! String) return (null, null);
    final kind = ServerKind.values
        .where((k) => k.name == serverName)
        .firstOrNull;
    if (kind == null) {
      debugPrint('PlaybackReporter: unknown server "$serverName"');
      return (null, null);
    }
    return (kind, id);
  }
}
