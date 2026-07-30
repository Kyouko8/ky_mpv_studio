import 'package:flutter/foundation.dart';

import '../../studio/server_manager.dart';
import 'media_server.dart';

/// App-level store of favourite (like) state for media-server tracks, shared
/// by the song list (the star button) and the [PlaybackReporter] (the OS
/// lock-screen like command). Holds optimistic overrides keyed by
/// `"<instanceId>:<trackId>"` so a toggle from either surface reflects in the other
/// without a refetch, and writes through to the server.
class FavoritesController extends ChangeNotifier {
  FavoritesController(this._serverManager);

  final ServerManager _serverManager;
  final Map<String, bool> _overrides = {};

  static String _key(String instanceId, String id) => '$instanceId:$id';

  /// The favourite state for a track if it's been toggled this session,
  /// otherwise [fallback] (the value the server returned for the list).
  bool resolvedByInstance(String instanceId, String id, bool fallback) =>
      _overrides[_key(instanceId, id)] ?? fallback;

  /// Legacy fallback: gets the favourite state using legacy ServerKind.
  bool resolved(ServerKind kind, String id, bool fallback) {
    final instance = _serverManager.instances.where((i) => i.kind == kind).firstOrNull;
    if (instance == null) return fallback;
    return resolvedByInstance(instance.id, id, fallback);
  }

  /// Set the favourite state for [id] on server [instanceId]: record the override
  /// (optimistic), notify listeners, then write through to the server.
  Future<void> setFavoriteByInstance(String instanceId, String id, bool value) async {
    _overrides[_key(instanceId, id)] = value;
    notifyListeners();
    final idx = _serverManager.instances.indexWhere((i) => i.id == instanceId);
    if (idx != -1) {
      final server = _serverManager.getOrCreateServer(_serverManager.instances[idx]);
      await server.setFavorite(id, value);
    }
  }

  /// Legacy fallback: sets favorite using ServerKind on the first matching instance.
  Future<void> setFavorite(ServerKind kind, String id, bool value) async {
    final instance = _serverManager.instances.where((i) => i.kind == kind).firstOrNull;
    if (instance != null) {
      await setFavoriteByInstance(instance.id, id, value);
    }
  }
}
