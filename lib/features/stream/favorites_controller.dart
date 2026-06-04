import 'package:flutter/foundation.dart';

import 'media_server.dart';

/// App-level store of favourite (like) state for media-server tracks, shared
/// by the song list (the star button) and the [PlaybackReporter] (the OS
/// lock-screen like command). Holds optimistic overrides keyed by
/// `"<kind>:<trackId>"` so a toggle from either surface reflects in the other
/// without a refetch, and writes through to the server.
class FavoritesController extends ChangeNotifier {
  FavoritesController(this._servers);

  final Map<ServerKind, MediaServer> _servers;
  final Map<String, bool> _overrides = {};

  static String _key(ServerKind kind, String id) => '${kind.name}:$id';

  /// The favourite state for a track if it's been toggled this session,
  /// otherwise [fallback] (the value the server returned for the list).
  bool resolved(ServerKind kind, String id, bool fallback) =>
      _overrides[_key(kind, id)] ?? fallback;

  /// Set the favourite state for [id] on [kind]: record the override
  /// (optimistic), notify listeners, then write through to the server.
  Future<void> setFavorite(ServerKind kind, String id, bool value) async {
    _overrides[_key(kind, id)] = value;
    notifyListeners();
    await _servers[kind]?.setFavorite(id, value);
  }
}
