import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';
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
  final bool requireAdvancedScan;

  LibraryTrack({
    required this.uri,
    this.title = '',
    this.artist = '',
    this.album = '',
    this.genre = '',
    this.year = '',
    required this.mtime,
    this.requireAdvancedScan = false,
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
      requireAdvancedScan: json['requireAdvancedScan'] as bool? ?? false,
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
      'requireAdvancedScan': requireAdvancedScan,
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
    bool? requireAdvancedScan,
  }) {
    return LibraryTrack(
      uri: uri ?? this.uri,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      genre: genre ?? this.genre,
      year: year ?? this.year,
      mtime: mtime ?? this.mtime,
      requireAdvancedScan: requireAdvancedScan ?? this.requireAdvancedScan,
    );
  }
}

class IsolateScanParams {
  final SendPort sendPort;
  final List<String> paths;
  final List<LibraryTrack> cachedTracks;
  final Map<String, Map<String, String>> fallbacks;

  IsolateScanParams({
    required this.sendPort,
    required this.paths,
    required this.cachedTracks,
    required this.fallbacks,
  });
}

// Background scan isolate function
Future<void> _isolateScan(IsolateScanParams params) async {
  final tagger = MetaTagger();
  final cacheMap = {for (final t in params.cachedTracks) t.uri: t};

  for (final path in params.paths) {
    try {
      final file = File(path);
      if (!file.existsSync()) {
        params.sendPort.send(null);
        continue;
      }

      final stat = file.statSync();
      final mtime = stat.modified.millisecondsSinceEpoch;

      final cached = cacheMap[path];
      if (cached != null && cached.mtime == mtime) {
        params.sendPort.send(cached);
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

      final track = LibraryTrack(
        uri: path,
        title: title.trim(),
        artist: artist.trim(),
        album: album.trim(),
        genre: genre.trim(),
        year: year.trim(),
        mtime: mtime,
        requireAdvancedScan: false,
      );
      params.sendPort.send(track);
    } catch (e) {
      debugPrint('Error scanning file $path in isolate: $e');
      params.sendPort.send(null);
    }
  }
}

class LibraryManager extends ChangeNotifier {
  final _onAudioQuery = OnAudioQuery();
  List<String> _folders = [];
  List<LibraryTrack> _tracks = [];
  bool _isScanning = false;
  bool _loaded = false;
  int _scannedCount = 0;
  int _totalToScan = 0;

  LibraryManager() {
    _init();
  }

  List<String> get folders => _folders;
  List<LibraryTrack> get tracks => _tracks;
  bool get isScanning => _isScanning;
  bool get loaded => _loaded;
  int get scannedCount => _scannedCount;
  int get totalToScan => _totalToScan;

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
    _scannedCount = 0;
    _totalToScan = 0;
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
        _totalToScan = songs.length;
        _scannedCount = 0;
        notifyListeners();

        final List<LibraryTrack> androidTracks = [];
        for (final song in songs) {
          final path = song.data;
          if (isAudioPath(path)) {
            // Use MediaStore info directly
            String artist = song.artist ?? 'Unknown Artist';
            if (artist == '<unknown>' || artist.isEmpty) artist = 'Unknown Artist';
            String album = song.album ?? 'Unknown Album';
            if (album == '<unknown>' || album.isEmpty) album = 'Unknown Album';
            String genre = song.genre ?? 'Unknown Genre';
            if (genre == '<unknown>' || genre.isEmpty) genre = 'Unknown Genre';

            androidTracks.add(LibraryTrack(
              uri: path,
              title: song.title.trim(),
              artist: artist.trim(),
              album: album.trim(),
              genre: genre.trim(),
              year: 'Unknown Year',
              mtime: (song.dateModified ?? 0) * 1000,
              requireAdvancedScan: true,
            ));
          }
          _scannedCount++;
          if (_scannedCount % 50 == 0 || _scannedCount == _totalToScan) {
            notifyListeners();
          }
        }
        _tracks = androidTracks;
        await saveCache();
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

        if (pathsToScan.isNotEmpty) {
          _totalToScan = pathsToScan.length;
          _scannedCount = 0;
          notifyListeners();

          final receivePort = ReceivePort();
          final isolate = await Isolate.spawn(
            _isolateScan,
            IsolateScanParams(
              sendPort: receivePort.sendPort,
              paths: pathsToScan,
              cachedTracks: _tracks,
              fallbacks: fallbacks,
            ),
          );

          final List<LibraryTrack> updatedTracks = [];
          await for (final msg in receivePort) {
            if (msg is LibraryTrack) {
              updatedTracks.add(msg);
            }
            _scannedCount++;
            notifyListeners();
            if (_scannedCount >= _totalToScan) {
              receivePort.close();
              isolate.kill();
              break;
            }
          }

          _tracks = updatedTracks;
          await saveCache();
        } else {
          _tracks = [];
          await saveCache();
        }
      }
    } catch (e) {
      debugPrint('Error scanning library: $e');
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  Future<LibraryTrack?> enrichTrackWithMetaTagger(String uri) async {
    final idx = _tracks.indexWhere((t) => t.uri == uri);
    if (idx == -1) return null;
    final track = _tracks[idx];
    if (!track.requireAdvancedScan) return track;

    try {
      final file = File(uri);
      if (!await file.exists()) {
        final updated = track.copyWith(requireAdvancedScan: false);
        _tracks[idx] = updated;
        await saveCache();
        notifyListeners();
        return updated;
      }

      final tagger = MetaTagger();
      if (tagger.isSupported(uri)) {
        final tags = await tagger.readCommonTags(uri);
        final title = tags[CommonTags.title]?.toString() ?? '';
        final artist = tags[CommonTags.artist]?.toString() ?? '';
        final album = tags[CommonTags.album]?.toString() ?? '';
        final genre = tags[CommonTags.genre]?.toString() ?? '';
        final year = tags[CommonTags.year]?.toString() ?? '';

        final updated = track.copyWith(
          title: title.isNotEmpty ? title.trim() : track.title,
          artist: artist.isNotEmpty ? artist.trim() : track.artist,
          album: album.isNotEmpty ? album.trim() : track.album,
          genre: genre.isNotEmpty ? genre.trim() : track.genre,
          year: year.isNotEmpty ? year.trim() : track.year,
          requireAdvancedScan: false,
        );

        _tracks[idx] = updated;
        await saveCache();
        notifyListeners();
        return updated;
      }
    } catch (e) {
      debugPrint('Error enriching track with metatagger: $e');
    }
    return track;
  }
}
