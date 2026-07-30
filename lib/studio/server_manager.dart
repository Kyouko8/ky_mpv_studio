import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../features/stream/media_server.dart';

class ServerInstance {
  final String id;
  final String name;
  final ServerKind kind;
  final String host;
  final String share; // Samba only
  final String username;
  final String password;
  final String domain; // Samba only

  // Session cache
  String? token;
  String? userId; // Jellyfin
  String? sectionId; // Plex

  ServerInstance({
    required this.id,
    required this.name,
    required this.kind,
    required this.host,
    this.share = '',
    this.username = '',
    this.password = '',
    this.domain = '',
    this.token,
    this.userId,
    this.sectionId,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'kind': kind.name,
      'host': host,
      'share': share,
      'username': username,
      'password': password,
      'domain': domain,
      'token': token,
      'userId': userId,
      'sectionId': sectionId,
    };
  }

  factory ServerInstance.fromJson(Map<String, dynamic> json) {
    return ServerInstance(
      id: json['id'] as String,
      name: json['name'] as String,
      kind: ServerKind.values.byName(json['kind'] as String),
      host: json['host'] as String,
      share: json['share'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      domain: json['domain'] as String? ?? '',
      token: json['token'] as String?,
      userId: json['userId'] as String?,
      sectionId: json['sectionId'] as String?,
    );
  }

  ServerInstance copyWith({
    String? id,
    String? name,
    ServerKind? kind,
    String? host,
    String? share,
    String? username,
    String? password,
    String? domain,
    String? token,
    String? userId,
    String? sectionId,
  }) {
    return ServerInstance(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      host: host ?? this.host,
      share: share ?? this.share,
      username: username ?? this.username,
      password: password ?? this.password,
      domain: domain ?? this.domain,
      token: token ?? this.token,
      userId: userId ?? this.userId,
      sectionId: sectionId ?? this.sectionId,
    );
  }
}

class ServerManager extends ChangeNotifier {
  final _uuid = const Uuid();
  List<ServerInstance> _instances = [];
  bool _loaded = false;

  // Active connected MediaServer instances mapped by instance ID
  final Map<String, MediaServer> _servers = {};

  List<ServerInstance> get instances => _instances;
  bool get loaded => _loaded;

  Future<File> get _localFile async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/servers_data.json');
  }

  /// Get or create the MediaServer wrapper for a specific instance.
  MediaServer getOrCreateServer(ServerInstance instance) {
    if (_servers.containsKey(instance.id)) {
      return _servers[instance.id]!;
    }

    final MediaServer server;
    if (instance.kind == ServerKind.jellyfin) {
      server = JellyfinServer(instance: instance, onSessionChanged: (token, userId) {
        _updateSession(instance.id, token: token, userId: userId);
      });
    } else if (instance.kind == ServerKind.plex) {
      server = PlexServer(instance: instance, onSessionChanged: (token, sectionId) {
        _updateSession(instance.id, token: token, sectionId: sectionId);
      });
    } else {
      server = SambaServer(instance: instance);
    }

    _servers[instance.id] = server;
    return server;
  }

  void _updateSession(String instanceId, {String? token, String? userId, String? sectionId}) {
    final idx = _instances.indexWhere((i) => i.id == instanceId);
    if (idx != -1) {
      _instances[idx] = _instances[idx].copyWith(
        token: token,
        userId: userId,
        sectionId: sectionId,
      );
      save();
    }
  }

  Future<void> load() async {
    try {
      final file = await _localFile;
      if (await file.exists()) {
        final raw = await file.readAsString();
        if (raw.isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            final list = decoded['servers'] as List? ?? [];
            _instances = list.map((item) => ServerInstance.fromJson(item as Map<String, dynamic>)).toList();
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading servers_data.json: $e');
    }

    // Attempt automatic migration of legacy configurations from SharedPreferences
    await _migrateLegacyConfig();

    _loaded = true;
    notifyListeners();
  }

  Future<void> _migrateLegacyConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      bool migrated = false;

      // Migrate legacy Jellyfin
      final jBase = prefs.getString('jellyfin.base');
      final jToken = prefs.getString('jellyfin.token');
      final jUserId = prefs.getString('jellyfin.userId');
      if (jBase != null && !_instances.any((i) => i.kind == ServerKind.jellyfin)) {
        final instance = ServerInstance(
          id: 'jellyfin-legacy-id',
          name: 'Jellyfin Legacy',
          kind: ServerKind.jellyfin,
          host: jBase,
          token: jToken,
          userId: jUserId,
        );
        _instances.add(instance);
        migrated = true;
      }

      // Migrate legacy Plex
      final pBase = prefs.getString('plex.base');
      final pToken = prefs.getString('plex.token');
      final pSection = prefs.getString('plex.section');
      if (pBase != null && !_instances.any((i) => i.kind == ServerKind.plex)) {
        final instance = ServerInstance(
          id: 'plex-legacy-id',
          name: 'Plex Legacy',
          kind: ServerKind.plex,
          host: pBase,
          token: pToken,
          sectionId: pSection,
        );
        _instances.add(instance);
        migrated = true;
      }

      // Migrate legacy Samba
      final sHost = prefs.getString('samba.host');
      final sShare = prefs.getString('samba.share');
      final sUser = prefs.getString('samba.user') ?? '';
      final sPass = prefs.getString('samba.pass') ?? '';
      final sDomain = prefs.getString('samba.domain') ?? '';
      if (sHost != null && sShare != null && !_instances.any((i) => i.kind == ServerKind.samba)) {
        final instance = ServerInstance(
          id: 'samba-legacy-id',
          name: 'Samba Legacy',
          kind: ServerKind.samba,
          host: sHost,
          share: sShare,
          username: sUser,
          password: sPass,
          domain: sDomain,
        );
        _instances.add(instance);
        migrated = true;
      }

      if (migrated) {
        await save();
      }
    } catch (e) {
      debugPrint('Error migrating legacy configs: $e');
    }
  }

  Future<void> save() async {
    try {
      final file = await _localFile;
      final data = {
        'servers': _instances.map((s) => s.toJson()).toList(),
      };
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('Error saving servers_data.json: $e');
    }
  }

  Future<ServerInstance> addInstance({
    required String name,
    required ServerKind kind,
    required String host,
    String share = '',
    String username = '',
    String password = '',
    String domain = '',
  }) async {
    final newInstance = ServerInstance(
      id: _uuid.v4(),
      name: name,
      kind: kind,
      host: host,
      share: share,
      username: username,
      password: password,
      domain: domain,
    );
    _instances.add(newInstance);
    await save();
    notifyListeners();
    return newInstance;
  }

  Future<void> updateInstance(ServerInstance updated) async {
    final idx = _instances.indexWhere((i) => i.id == updated.id);
    if (idx != -1) {
      _instances[idx] = updated;
      _servers.remove(updated.id); // clear active cached connection to force recreate
      await save();
      notifyListeners();
    }
  }

  Future<void> removeInstance(String id) async {
    _instances.removeWhere((i) => i.id == id);
    _servers.remove(id);
    await save();
    notifyListeners();
  }
}
