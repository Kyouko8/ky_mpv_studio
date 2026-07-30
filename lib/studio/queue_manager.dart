import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'app_settings.dart';
import 'library_manager.dart';

class PlaylistItem {
  final String uri;
  final String title;
  final String artist;
  final String album;
  final bool active;
  final Map<String, String>? demuxerLavfOptions;
  final int? httpChunkSize;
  final Map<String, String>? httpHeaders;
  final Map<String, dynamic>? extras;

  PlaylistItem({
    required this.uri,
    this.title = '',
    this.artist = '',
    this.album = '',
    this.active = true,
    this.demuxerLavfOptions,
    this.httpChunkSize,
    this.httpHeaders,
    this.extras,
  });

  factory PlaylistItem.fromMedia(Media media, {bool active = true}) {
    final extras = media.extras ?? const <String, dynamic>{};
    return PlaylistItem(
      uri: media.uri,
      title: extras['title'] as String? ?? '',
      artist: extras['artist'] as String? ?? '',
      album: extras['album'] as String? ?? '',
      active: active,
      demuxerLavfOptions: media.demuxerLavfOptions,
      httpChunkSize: media.httpChunkSize,
      httpHeaders: media.httpHeaders,
      extras: media.extras,
    );
  }

  Media toMedia() {
    final ex = Map<String, dynamic>.from(extras ?? {});
    if (title.isNotEmpty) ex['title'] = title;
    if (artist.isNotEmpty) ex['artist'] = artist;
    if (album.isNotEmpty) ex['album'] = album;
    return Media(
      uri,
      demuxerLavfOptions: demuxerLavfOptions,
      httpChunkSize: httpChunkSize,
      httpHeaders: httpHeaders,
      extras: ex,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uri': uri,
      'title': title,
      'artist': artist,
      'album': album,
      'active': active,
      'demuxerLavfOptions': demuxerLavfOptions,
      'httpChunkSize': httpChunkSize,
      'httpHeaders': httpHeaders,
      'extras': extras,
    };
  }

  factory PlaylistItem.fromJson(Map<String, dynamic> json) {
    return PlaylistItem(
      uri: json['uri'] as String,
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      album: json['album'] as String? ?? '',
      active: json['active'] as bool? ?? true,
      demuxerLavfOptions: (json['demuxerLavfOptions'] as Map?)?.cast<String, String>(),
      httpChunkSize: json['httpChunkSize'] as int?,
      httpHeaders: (json['httpHeaders'] as Map?)?.cast<String, String>(),
      extras: (json['extras'] as Map?)?.cast<String, dynamic>(),
    );
  }

  PlaylistItem copyWith({
    String? uri,
    String? title,
    String? artist,
    String? album,
    bool? active,
    Map<String, String>? demuxerLavfOptions,
    int? httpChunkSize,
    Map<String, String>? httpHeaders,
    Map<String, dynamic>? extras,
  }) {
    return PlaylistItem(
      uri: uri ?? this.uri,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      active: active ?? this.active,
      demuxerLavfOptions: demuxerLavfOptions ?? this.demuxerLavfOptions,
      httpChunkSize: httpChunkSize ?? this.httpChunkSize,
      httpHeaders: httpHeaders ?? this.httpHeaders,
      extras: extras ?? this.extras,
    );
  }
}

class QueueModel {
  final String id;
  final String name;
  final List<PlaylistItem> items;

  QueueModel({
    required this.id,
    required this.name,
    required this.items,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }

  factory QueueModel.fromJson(Map<String, dynamic> json) {
    final list = json['items'] as List? ?? [];
    return QueueModel(
      id: json['id'] as String,
      name: json['name'] as String,
      items: list.map((item) => PlaylistItem.fromJson(item as Map<String, dynamic>)).toList(),
    );
  }

  QueueModel copyWith({
    String? id,
    String? name,
    List<PlaylistItem>? items,
  }) {
    return QueueModel(
      id: id ?? this.id,
      name: name ?? this.name,
      items: items ?? this.items,
    );
  }
}

class QueueManager extends ChangeNotifier {
  final Player _player;
  final AppSettings _settings;
  final _uuid = const Uuid();

  List<QueueModel> _queues = [];
  String _viewedQueueId = '';
  String? _playingQueueId;
  int _lastPlayingIndex = 0;
  bool _loaded = false;

  StreamSubscription? _playlistSub;
  LibraryManager? libraryManager;

  QueueManager(this._player, this._settings) {
    _initPlayerListener();
  }

  void _initPlayerListener() {
    _playlistSub = _player.stream.playlist.listen((pl) async {
      if (_loaded && _playingQueueId != null) {
        final qIdx = _queues.indexWhere((q) => q.id == _playingQueueId);
        if (qIdx != -1) {
          final queue = _queues[qIdx];
          final activeItems = queue.items.where((item) => item.active).toList();
          if (pl.index >= 0 && pl.index < pl.items.length && pl.index < activeItems.length) {
            final playingUri = pl.items[pl.index].uri;
            final fullIndex = queue.items.indexWhere((item) => item.uri == playingUri);
            if (fullIndex != -1 && fullIndex != _lastPlayingIndex) {
              _lastPlayingIndex = fullIndex;
              save();
            }

            // Enrich metadata dynamically if available!
            final lib = libraryManager;
            if (lib != null) {
              final enriched = await lib.enrichTrackWithMetaTagger(playingUri);
              if (enriched != null) {
                updatePlaylistItemMetadata(
                  enriched.uri,
                  enriched.title,
                  enriched.artist,
                  enriched.album,
                );
              }
            }
          }
        }
      }
    });
  }

  void updatePlaylistItemMetadata(String uri, String title, String artist, String album) {
    bool changed = false;
    for (int qIdx = 0; qIdx < _queues.length; qIdx++) {
      final queue = _queues[qIdx];
      final items = List<PlaylistItem>.from(queue.items);
      bool queueChanged = false;
      for (int i = 0; i < items.length; i++) {
        if (items[i].uri == uri) {
          final old = items[i];
          final updated = old.copyWith(
            title: title.isNotEmpty ? title : old.title,
            artist: artist.isNotEmpty ? artist : old.artist,
            album: album.isNotEmpty ? album : old.album,
          );
          if (old.title != updated.title || old.artist != updated.artist || old.album != updated.album) {
            items[i] = updated;
            queueChanged = true;
          }
        }
      }
      if (queueChanged) {
        _queues[qIdx] = queue.copyWith(items: items);
        changed = true;
      }
    }
    if (changed) {
      save();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _playlistSub?.cancel();
    super.dispose();
  }

  List<QueueModel> get queues => _queues;
  String get viewedQueueId => _viewedQueueId;
  String? get playingQueueId => _playingQueueId;
  bool get loaded => _loaded;

  QueueModel get viewedQueue {
    return _queues.firstWhere(
      (q) => q.id == _viewedQueueId,
      orElse: () => _queues.isNotEmpty ? _queues.first : QueueModel(id: '', name: '', items: []),
    );
  }

  QueueModel? get playingQueue {
    if (_playingQueueId == null) return null;
    final idx = _queues.indexWhere((q) => q.id == _playingQueueId);
    return idx != -1 ? _queues[idx] : null;
  }

  Future<File> get _localFile async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/queues_data.json');
  }

  Future<void> load() async {
    try {
      final file = await _localFile;
      if (await file.exists()) {
        final raw = await file.readAsString();
        if (raw.isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            final qList = decoded['queues'] as List? ?? [];
            _queues = qList.map((q) => QueueModel.fromJson(q as Map<String, dynamic>)).toList();
            _viewedQueueId = decoded['viewedQueueId'] as String? ?? '';
            _playingQueueId = decoded['playingQueueId'] as String?;
            _lastPlayingIndex = decoded['lastPlayingIndex'] as int? ?? 0;
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading queues: $e');
    }

    // Ensure we have at least one queue
    if (_queues.isEmpty) {
      final defaultQueue = QueueModel(
        id: _uuid.v4(),
        name: _settings.queueBaseName,
        items: [],
      );
      _queues.add(defaultQueue);
      _viewedQueueId = defaultQueue.id;
    } else if (_viewedQueueId.isEmpty || !_queues.any((q) => q.id == _viewedQueueId)) {
      _viewedQueueId = _queues.first.id;
    }

    // Restore player state
    try {
      final targetQueueId = _playingQueueId ?? _viewedQueueId;
      final idx = _queues.indexWhere((q) => q.id == targetQueueId);
      if (idx != -1) {
        final queue = _queues[idx];
        final activeItems = queue.items.where((item) => item.active).toList();
        if (activeItems.isNotEmpty) {
          final mediaList = activeItems.map((item) => item.toMedia()).toList();

          int targetMpvIndex = 0;
          if (_lastPlayingIndex >= 0 && _lastPlayingIndex < queue.items.length) {
            final targetUri = queue.items[_lastPlayingIndex].uri;
            final foundIdx = activeItems.indexWhere((item) => item.uri == targetUri);
            if (foundIdx != -1) {
              targetMpvIndex = foundIdx;
            }
          }

          // Open but do not play
          await _player.openAll(mediaList, play: false, index: targetMpvIndex);
        }
      }
    } catch (e) {
      debugPrint('Error restoring last queue state: $e');
    }

    _loaded = true;
    notifyListeners();
  }

  Future<void> save() async {
    try {
      final file = await _localFile;
      final data = {
        'queues': _queues.map((q) => q.toJson()).toList(),
        'viewedQueueId': _viewedQueueId,
        'playingQueueId': _playingQueueId,
        'lastPlayingIndex': _lastPlayingIndex,
      };
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('Error saving queues: $e');
    }
  }

  void selectViewedQueue(String id) {
    if (_queues.any((q) => q.id == id)) {
      _viewedQueueId = id;
      save();
      notifyListeners();
    }
  }

  QueueModel createQueue([String? name]) {
    final maxAllowed = _settings.queueMaxLists;
    if (_queues.length >= maxAllowed) {
      throw Exception('You have reached the maximum limit of lists ($maxAllowed).');
    }

    final newQueue = QueueModel(
      id: _uuid.v4(),
      name: name ?? _settings.queueBaseName,
      items: [],
    );
    _queues.add(newQueue);
    _viewedQueueId = newQueue.id;
    save();
    notifyListeners();
    return newQueue;
  }

  void renameQueue(String id, String newName) {
    final index = _queues.indexWhere((q) => q.id == id);
    if (index != -1) {
      _queues[index] = _queues[index].copyWith(name: newName);
      save();
      notifyListeners();
    }
  }

  void reorderQueues(int oldIndex, int newIndex) {
    if (newIndex < 0 || newIndex > _queues.length) return;
    if (oldIndex < 0 || oldIndex >= _queues.length) return;

    final q = _queues.removeAt(oldIndex);
    if (newIndex > oldIndex) {
      _queues.insert(newIndex - 1, q);
    } else {
      _queues.insert(newIndex, q);
    }
    save();
    notifyListeners();
  }

  void deleteQueue(String id) {
    if (_queues.length <= 1) {
      throw Exception('At least one list is required.');
    }
    final index = _queues.indexWhere((q) => q.id == id);
    if (index != -1) {
      _queues.removeAt(index);
      if (_viewedQueueId == id) {
        _viewedQueueId = _queues.first.id;
      }
      if (_playingQueueId == id) {
        _playingQueueId = null;
        _player.clearPlaylist();
      }
      save();
      notifyListeners();
    }
  }

  int? _mpvIndexFor(int fullIndex, List<PlaylistItem> items) {
    if (fullIndex < 0 || fullIndex >= items.length) return null;
    if (!items[fullIndex].active) return null;

    int activeCount = 0;
    for (int i = 0; i < fullIndex; i++) {
      if (items[i].active) {
        activeCount++;
      }
    }
    return activeCount;
  }

  Future<void> playTrack(int fullIndex) async {
    final initialQueue = viewedQueue;
    if (fullIndex < 0 || fullIndex >= initialQueue.items.length) return;

    // Ensure the track is active (if they click it, make sure it is active)
    if (!initialQueue.items[fullIndex].active) {
      await setTrackActive(fullIndex, true);
    }

    final queue = viewedQueue;
    final items = queue.items;

    _playingQueueId = queue.id;
    _lastPlayingIndex = fullIndex;
    save();

    final activeItems = items.where((item) => item.active).toList();
    final mediaList = activeItems.map((item) => item.toMedia()).toList();
    final targetMpvIndex = activeItems.indexWhere((item) => item.uri == items[fullIndex].uri);

    if (targetMpvIndex != -1) {
      await _player.openAll(mediaList, play: true, index: targetMpvIndex);
    }
    notifyListeners();
  }

  Future<void> setTrackActive(int fullIndex, bool active) async {
    final queueIndex = _queues.indexWhere((q) => q.id == _viewedQueueId);
    if (queueIndex == -1) return;

    final queue = _queues[queueIndex];
    final items = List<PlaylistItem>.from(queue.items);
    if (fullIndex < 0 || fullIndex >= items.length) return;

    final oldItem = items[fullIndex];
    if (oldItem.active == active) return;

    final newItem = oldItem.copyWith(active: active);
    items[fullIndex] = newItem;
    _queues[queueIndex] = queue.copyWith(items: items);

    save();

    // If this is the playing queue, synchronize to the player
    if (_playingQueueId == _viewedQueueId) {
      if (!active) {
        final mpvIdx = _mpvIndexFor(fullIndex, queue.items);
        if (mpvIdx != null && mpvIdx < _player.state.playlist.items.length) {
          await _player.remove(mpvIdx);
        }
      } else {
        // Find insert target index in the player's active playlist
        final targetIndex = _mpvIndexFor(fullIndex, items);
        if (targetIndex != null) {
          await _player.add(newItem.toMedia());
          final currentMpvLength = _player.state.playlist.items.length;
          if (currentMpvLength > 0 && targetIndex < currentMpvLength) {
            await _player.move(currentMpvLength - 1, targetIndex);
          }
        }
      }
    }

    notifyListeners();
  }

  Future<void> add(Media media) async {
    final queueIndex = _queues.indexWhere((q) => q.id == _viewedQueueId);
    if (queueIndex == -1) return;

    final queue = _queues[queueIndex];
    final items = List<PlaylistItem>.from(queue.items);
    final newItem = PlaylistItem.fromMedia(media);
    items.add(newItem);
    _queues[queueIndex] = queue.copyWith(items: items);

    save();

    if (_playingQueueId == _viewedQueueId) {
      await _player.add(media);
    }

    notifyListeners();
  }

  Future<void> open(Media media, {bool play = true}) async {
    final queueIndex = _queues.indexWhere((q) => q.id == _viewedQueueId);
    if (queueIndex == -1) return;

    final queue = _queues[queueIndex];
    final newItem = PlaylistItem.fromMedia(media);
    _queues[queueIndex] = queue.copyWith(items: [newItem]);
    _playingQueueId = _viewedQueueId;

    save();

    await _player.open(media, play: play);
    notifyListeners();
  }

  Future<void> openAll(List<Media> medias, {bool play = true, int index = 0}) async {
    final queueIndex = _queues.indexWhere((q) => q.id == _viewedQueueId);
    if (queueIndex == -1) return;

    final queue = _queues[queueIndex];
    final newItems = medias.map((m) => PlaylistItem.fromMedia(m)).toList();
    _queues[queueIndex] = queue.copyWith(items: newItems);
    _playingQueueId = _viewedQueueId;

    save();

    await _player.openAll(medias, play: play, index: index);
    notifyListeners();
  }

  Future<void> remove(int fullIndex) async {
    final queueIndex = _queues.indexWhere((q) => q.id == _viewedQueueId);
    if (queueIndex == -1) return;

    final queue = _queues[queueIndex];
    final items = List<PlaylistItem>.from(queue.items);
    if (fullIndex < 0 || fullIndex >= items.length) return;

    final oldItem = items[fullIndex];
    items.removeAt(fullIndex);
    _queues[queueIndex] = queue.copyWith(items: items);

    save();

    if (_playingQueueId == _viewedQueueId && oldItem.active) {
      final mpvIdx = _mpvIndexFor(fullIndex, queue.items);
      if (mpvIdx != null && mpvIdx < _player.state.playlist.items.length) {
        await _player.remove(mpvIdx);
      }
    }

    notifyListeners();
  }

  Future<void> move(int oldFullIndex, int newFullIndex) async {
    final queueIndex = _queues.indexWhere((q) => q.id == _viewedQueueId);
    if (queueIndex == -1) return;

    final queue = _queues[queueIndex];
    final items = List<PlaylistItem>.from(queue.items);
    if (oldFullIndex < 0 || oldFullIndex >= items.length) return;
    if (newFullIndex < 0 || newFullIndex >= items.length) return;

    final item = items.removeAt(oldFullIndex);
    items.insert(newFullIndex, item);
    _queues[queueIndex] = queue.copyWith(items: items);

    save();

    if (_playingQueueId == _viewedQueueId && item.active) {
      final oldMpvIdx = _mpvIndexFor(oldFullIndex, queue.items);
      final newMpvIdx = _mpvIndexFor(newFullIndex, items);
      if (oldMpvIdx != null && newMpvIdx != null && oldMpvIdx != newMpvIdx) {
        await _player.move(oldMpvIdx, newMpvIdx);
      }
    }

    notifyListeners();
  }

  Future<void> replace(int fullIndex, Media media) async {
    final queueIndex = _queues.indexWhere((q) => q.id == _viewedQueueId);
    if (queueIndex == -1) return;

    final queue = _queues[queueIndex];
    final items = List<PlaylistItem>.from(queue.items);
    if (fullIndex < 0 || fullIndex >= items.length) return;

    final oldItem = items[fullIndex];
    final newItem = PlaylistItem.fromMedia(media, active: oldItem.active);
    items[fullIndex] = newItem;
    _queues[queueIndex] = queue.copyWith(items: items);

    save();

    if (_playingQueueId == _viewedQueueId && oldItem.active) {
      final mpvIdx = _mpvIndexFor(fullIndex, queue.items);
      if (mpvIdx != null && mpvIdx < _player.state.playlist.items.length) {
        await _player.replace(mpvIdx, media);
      }
    }

    notifyListeners();
  }

  Future<void> clearPlaylist() async {
    final queueIndex = _queues.indexWhere((q) => q.id == _viewedQueueId);
    if (queueIndex == -1) return;

    final queue = _queues[queueIndex];
    _queues[queueIndex] = queue.copyWith(items: []);

    save();

    if (_playingQueueId == _viewedQueueId) {
      await _player.clearPlaylist();
    }

    notifyListeners();
  }
}
