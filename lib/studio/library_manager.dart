import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:metatagger/metatagger.dart';

import '../util/media_import.dart';

class LibraryTrack {
  final String uri;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final String year;
  final int mtime; // File modification timestamp (ms since epoch)

  LibraryTrack({
    required this.uri,
    this.title = '',
    this.artist = '',
    this.album = '',
    this.genre = '',
    this.year = '',
    required this.mtime,
  });

  factory LibraryTrack.fromJson(Map<String, dynamic> json) {
    return LibraryTrack(
      uri: json['uri'] as String,
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      album: json['album'] as String? ?? '',
      genre: json['genre'] as String? ?? '',
      year: json['year'] as String? ?? '',
      mtime: json['mtime'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uri': uri,
      'title': title,
      'artist': artist,
      'album': album,
      'genre': genre,
      'year': year,
      'mtime': mtime,
    };
  }

  LibraryTrack copyWith({
    String? uri,
    String? title,
    String? artist,
    String? album,
    String? genre,
    String? year,
    int? mtime,
  }) {
    return LibraryTrack(
      uri: uri ?? this.uri,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      genre: genre ?? this.genre,
      year: year ?? this.year,
      mtime: mtime ?? this.mtime,
    );
  }
}

class IsolateScanParams {
  final List<String> paths;
  final List<LibraryTrack> cachedTracks;
  final Map<String, Map<String, String>> fallbacks;

  IsolateScanParams({
    required this.paths,
    required this.cachedTracks,
    required this.fallbacks,
  });
}

// Background scan isolate function
Future<List<LibraryTrack>> _isolateScan(IsolateScanParams params) async {
  final tagger = MetaTagger();
  final List<LibraryTrack> results = [];
  final cacheMap = {for (final t in params.cachedTracks) t.uri: t};

  for (final path in params.paths) {
    try {
      final file = File(path);
      if (!file.existsSync()) continue;

      final stat = file.statSync();
      final mtime = stat.modified.millisecondsSinceEpoch;

      final cached = cacheMap[path];
      if (cached != null && cached.mtime == mtime) {
        results.add(cached);
        continue;
      }

      // Try reading with metatagger
      String title = '';
      String artist = '';
      String album = '';
      String genre = '';
      String year = '';

      final fallback = params.fallbacks[path];
      bool parsed = false;

      if (tagger.isSupported(path)) {
        try {
          final tags = await tagger.readCommonTags(path);
          title = tags[CommonTags.title]?.toString() ?? '';
          artist = tags[CommonTags.artist]?.toString() ?? '';
          album = tags[CommonTags.album]?.toString() ?? '';
          genre = tags[CommonTags.genre]?.toString() ?? '';
          year = tags[CommonTags.year]?.toString() ?? '';
          parsed = true;
        } catch (_) {
          // If metatagger fails, parsed is false, fallback will handle it
        }
      }

      if (!parsed || (title.isEmpty && artist.isEmpty && album.isEmpty)) {
        if (fallback != null) {
          title = title.isNotEmpty ? title : (fallback['title'] ?? '');
          artist = artist.isNotEmpty ? artist : (fallback['artist'] ?? '');
          album = album.isNotEmpty ? album : (fallback['album'] ?? '');
          genre = genre.isNotEmpty ? genre : (fallback['genre'] ?? '');
          year = year.isNotEmpty ? year : (fallback['year'] ?? '');
        } else {
          // Fallback to base name from path
          final name = path.split(RegExp(r'[/\\]')).last;
          final dot = name.lastIndexOf('.');
          title = title.isNotEmpty ? title : (dot > 0 ? name.substring(0, dot) : name);
        }
      }

      // Fallback clean-ups for standard strings
      if (artist == '<unknown>' || artist.isEmpty) artist = 'Unknown Artist';
      if (album == '<unknown>' || album.isEmpty) album = 'Unknown Album';
      if (genre == '<unknown>' || genre.isEmpty) genre = 'Unknown Genre';
      if (year.isEmpty) year = 'Unknown Year';

      results.add(LibraryTrack(
        uri: path,
        title: title.trim(),
        artist: artist.trim(),
        album: album.trim(),
        genre: genre.trim(),
        year: year.trim(),
        mtime: mtime,
      ));
    } catch (e) {
      debugPrint('Error scanning file $path in isolate: $e');
    }
  }

  return results;
}

class LibraryManager extends ChangeNotifier {
  final _onAudioQuery = OnAudioQuery();
  List<String> _folders = [];
  List<LibraryTrack> _tracks = [];
  bool _isScanning = false;
  bool _loaded = false;

  LibraryManager() {
    _init();
  }

  List<String> get folders => _folders;
  List<LibraryTrack> get tracks => _tracks;
  bool get isScanning => _isScanning;
  bool get loaded => _loaded;

  Future<void> _init() async {
    await loadSettingsAndCache();
    // Do not trigger scan automatically at boot, scan is requested explicitly or upon directory change/pull-to-refresh
  }

  Future<File> get _cacheFile async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/library_cache.json');
  }

  Future<void> loadSettingsAndCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _folders = prefs.getStringList('library_folders') ?? [];

      final file = await _cacheFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final decoded = jsonDecode(content) as List;
          _tracks = decoded.map((e) => LibraryTrack.fromJson(e as Map<String, dynamic>)).toList();
        }
      }
    } catch (e) {
      debugPrint('Error loading library cache: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> saveCache() async {
    try {
      final file = await _cacheFile;
      final encoded = jsonEncode(_tracks.map((e) => e.toJson()).toList());
      await file.writeAsString(encoded);
    } catch (e) {
      debugPrint('Error saving library cache: $e');
    }
  }

  Future<void> addFolder(String path) async {
    if (!_folders.contains(path) && path.isNotEmpty) {
      _folders.add(path);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('library_folders', _folders);
      notifyListeners();
      await scan();
    }
  }

  Future<void> removeFolder(String path) async {
    if (_folders.remove(path)) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('library_folders', _folders);
      // Remove tracks that were in this folder
      _tracks.removeWhere((track) => track.uri.startsWith(path));
      await saveCache();
      notifyListeners();
    }
  }

  Future<bool> checkPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      bool status = await _onAudioQuery.permissionsStatus();
      if (!status) {
        status = await _onAudioQuery.permissionsRequest();
      }
      return status;
    }
    return true;
  }

  Future<void> scan() async {
    if (_isScanning) return;
    _isScanning = true;
    notifyListeners();

    try {
      final List<String> pathsToScan = [];
      final Map<String, Map<String, String>> fallbacks = {};

      if (defaultTargetPlatform == TargetPlatform.android) {
        final hasPermission = await checkPermission();
        if (!hasPermission) {
          _isScanning = false;
          notifyListeners();
          return;
        }

        final songs = await _onAudioQuery.querySongs();
        for (final song in songs) {
          final path = song.data;
          if (isAudioPath(path)) {
            pathsToScan.add(path);
            fallbacks[path] = {
              'title': song.title,
              'artist': song.artist ?? '',
              'album': song.album ?? '',
              'genre': song.genre ?? '',
              'year': '',
            };
          }
        }
      } else {
        // Windows / desktop
        for (final folder in _folders) {
          final dir = Directory(folder);
          if (await dir.exists()) {
            try {
              await for (final entity in dir.list(recursive: true, followLinks: false)) {
                if (entity is File && isAudioPath(entity.path)) {
                  pathsToScan.add(entity.path);
                }
              }
            } catch (e) {
              debugPrint('Error listing directory $folder: $e');
            }
          }
        }
      }

      if (pathsToScan.isNotEmpty) {
        // Run Isolate-based scan using compute
        final updatedTracks = await compute(
            _isolateScan,
            IsolateScanParams(
              paths: pathsToScan,
              cachedTracks: _tracks,
              fallbacks: fallbacks,
            ));

        _tracks = updatedTracks;
        await saveCache();
      } else {
        _tracks = [];
        await saveCache();
      }
    } catch (e) {
      debugPrint('Error scanning library: $e');
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }
}
