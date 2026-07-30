import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../studio/library_manager.dart';
import '../../studio/player_scope.dart';
import '../../studio/queue_manager.dart';
import '../../ui/tokens.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  int _activeTab = 1; // Default to Songs tab
  bool _hasPermission = true;
  String _folderViewMode = 'List'; // List, Tree
  String _treeCurrentPath = 'Root';

  // Search controllers for each tab
  final Map<int, TextEditingController> _searchControllers = {
    0: TextEditingController(), // Folders
    1: TextEditingController(), // Songs
    2: TextEditingController(), // Artists
    3: TextEditingController(), // Album
    4: TextEditingController(), // Genre
    5: TextEditingController(), // Year
  };

  final Map<int, String> _searchQueries = {
    0: '', 1: '', 2: '', 3: '', 4: '', 5: '',
  };

  // Sub-group selectors for grouping
  String _artistGroupMode = 'Songs'; // Songs, Albums, Years, Genres
  String _albumGroupMode = 'Songs';  // Songs, Artists, Years, Genres
  String _genreGroupMode = 'Songs';  // Songs, Artists, Albums
  String _yearGroupMode = 'Songs';   // Songs, Albums

  // Drill-down selection states
  String? _selectedFolder;
  String? _selectedArtist;
  String? _selectedArtistSubItem; // e.g., selected album under selected artist
  String? _selectedAlbum;
  String? _selectedAlbumSubItem;
  String? _selectedGenre;
  String? _selectedGenreSubItem;
  String? _selectedYear;
  String? _selectedYearSubItem;

  @override
  void initState() {
    super.initState();
    _checkAndRequestPermission();
  }

  @override
  void dispose() {
    for (final controller in _searchControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _checkAndRequestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final manager = PlayerScope.libraryManagerOf(context);
      final ok = await manager.checkPermission();
      if (mounted) {
        setState(() {
          _hasPermission = ok;
        });
        if (ok) {
          manager.scan();
        }
      }
    } else {
      final manager = PlayerScope.libraryManagerOf(context);
      if (manager.tracks.isEmpty && !manager.isScanning) {
        manager.scan();
      }
    }
  }

  Future<void> _addMediasToQueue(
    QueueManager qm,
    String queueId,
    List<Media> medias, {
    required bool skipDuplicates,
  }) async {
    final origId = qm.viewedQueueId;
    qm.selectViewedQueue(queueId);
    final queue = qm.queues.firstWhere((q) => q.id == queueId);
    final existingUris = queue.items.map((item) => item.uri).toSet();
    for (final media in medias) {
      if (skipDuplicates && existingUris.contains(media.uri)) {
        continue;
      }
      await qm.add(media);
    }
    qm.selectViewedQueue(origId);
  }

  void _showQueueSelectionDialog(
    BuildContext context,
    QueueManager qm,
    List<Media> medias,
    String title, {
    required bool skipDuplicates,
  }) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Tokens.surface,
          title: const Text('Select a Queue', style: Tokens.heading),
          content: SizedBox(
            width: 300,
            height: 250,
            child: ListView.builder(
              itemCount: qm.queues.length,
              itemBuilder: (context, i) {
                final q = qm.queues[i];
                return ListTile(
                  title: Text(q.name, style: Tokens.body),
                  subtitle: Text('${q.items.length} tracks', style: Tokens.caption),
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final nav = Navigator.of(context);
                    await _addMediasToQueue(qm, q.id, medias, skipDuplicates: skipDuplicates);
                    nav.pop();
                    messenger.showSnackBar(
                      SnackBar(content: Text('Added ${medias.length} track(s) to ${q.name}')),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: Tokens.accent)),
            ),
          ],
        );
      },
    );
  }

  List<LibraryTrack> _getCurrentVisibleTracks() {
    final filtered = _filterTracks(PlayerScope.libraryManagerOf(context).tracks);
    if (_activeTab == 0) {
      if (_folderViewMode == 'List') {
        if (_selectedFolder != null) {
          return filtered.where((t) => _getParentFolder(t.uri) == _selectedFolder).toList();
        }
      } else {
        if (_treeCurrentPath != 'Root') {
          return filtered.where((t) => _getParentFolder(t.uri) == _treeCurrentPath).toList();
        }
      }
    } else if (_activeTab == 1) {
      return filtered;
    } else if (_activeTab == 2) {
      if (_selectedArtist != null) {
        final artistTracks = filtered.where((t) => t.artist == _selectedArtist).toList();
        if (_selectedArtistSubItem != null) {
          if (_artistGroupMode == 'Albums') {
            return artistTracks.where((t) => t.album == _selectedArtistSubItem).toList();
          } else if (_artistGroupMode == 'Years') {
            return artistTracks.where((t) => t.year == _selectedArtistSubItem).toList();
          } else if (_artistGroupMode == 'Genres') {
            return artistTracks.where((t) => t.genre == _selectedArtistSubItem).toList();
          }
        }
        return artistTracks;
      }
    } else if (_activeTab == 3) {
      if (_selectedAlbum != null) {
        final albumTracks = filtered.where((t) => t.album == _selectedAlbum).toList();
        if (_selectedAlbumSubItem != null) {
          if (_albumGroupMode == 'Artists') {
            return albumTracks.where((t) => t.artist == _selectedAlbumSubItem).toList();
          } else if (_albumGroupMode == 'Years') {
            return albumTracks.where((t) => t.year == _selectedAlbumSubItem).toList();
          } else if (_albumGroupMode == 'Genres') {
            return albumTracks.where((t) => t.genre == _selectedAlbumSubItem).toList();
          }
        }
        return albumTracks;
      }
    } else if (_activeTab == 4) {
      if (_selectedGenre != null) {
        final genreTracks = filtered.where((t) => t.genre == _selectedGenre).toList();
        if (_selectedGenreSubItem != null) {
          if (_genreGroupMode == 'Artists') {
            return genreTracks.where((t) => t.artist == _selectedGenreSubItem).toList();
          } else if (_genreGroupMode == 'Albums') {
            return genreTracks.where((t) => t.album == _selectedGenreSubItem).toList();
          }
        }
        return genreTracks;
      }
    } else if (_activeTab == 5) {
      if (_selectedYear != null) {
        final yearTracks = filtered.where((t) => t.year == _selectedYear).toList();
        if (_selectedYearSubItem != null) {
          return yearTracks.where((t) => t.album == _selectedYearSubItem).toList();
        }
        return yearTracks;
      }
    }
    return filtered;
  }

  void _showLibraryMenu(BuildContext context, String title, List<LibraryTrack> tracks) {
    if (tracks.isEmpty) return;
    final qm = PlayerScope.queueManagerOf(context);

    bool addAll = false;
    bool skipDuplicates = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Tokens.rMd)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final allInView = _getCurrentVisibleTracks();
            final targetTracks = addAll ? allInView : tracks;
            final medias = targetTracks.map((t) => Media(t.uri, extras: {'title': t.title, 'artist': t.artist, 'album': t.album})).toList();

            return SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Tokens.s12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SwitchListTile(
                        title: const Text('Agregar todas', style: Tokens.body),
                        subtitle: const Text('Añade todas las canciones de la vista actual', style: Tokens.caption),
                        value: addAll,
                        activeThumbColor: Tokens.accent,
                        onChanged: (val) => setSheetState(() => addAll = val),
                      ),
                      SwitchListTile(
                        title: const Text('Omitir si ya se encuentra en la lista', style: Tokens.body),
                        subtitle: const Text('Evita duplicados en la lista de reproducción', style: Tokens.caption),
                        value: skipDuplicates,
                        activeThumbColor: Tokens.accent,
                        onChanged: (val) => setSheetState(() => skipDuplicates = val),
                      ),
                      const Divider(color: Tokens.line),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Tokens.s16, vertical: Tokens.s8),
                        child: Text(
                          title,
                          style: Tokens.heading.copyWith(fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Divider(color: Tokens.line),
                      ListTile(
                        leading: const Icon(Icons.playlist_play_rounded, color: Tokens.accent),
                        title: const Text('Play now as new list', style: Tokens.body),
                        onTap: () async {
                          final nav = Navigator.of(context);
                          qm.createQueue(title);
                          await qm.openAll(medias, play: true);
                          nav.pop();
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.bookmark_added_rounded, color: Tokens.accent),
                        title: const Text('Add to Listen Later', style: Tokens.body),
                        onTap: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final nav = Navigator.of(context);
                          QueueModel? target;
                          for (final q in qm.queues) {
                            if (q.name == 'Listen Later') {
                              target = q;
                              break;
                            }
                          }
                          target ??= qm.createQueue('Listen Later');
                          await _addMediasToQueue(qm, target.id, medias, skipDuplicates: skipDuplicates);
                          nav.pop();
                          messenger.showSnackBar(
                            SnackBar(content: Text('Added ${medias.length} track(s) to Listen Later')),
                          );
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.playlist_add_rounded, color: Tokens.accent),
                        title: Text('Add to current list (${qm.viewedQueue.name})', style: Tokens.body),
                        onTap: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final nav = Navigator.of(context);
                          await _addMediasToQueue(qm, qm.viewedQueueId, medias, skipDuplicates: skipDuplicates);
                          nav.pop();
                          messenger.showSnackBar(
                            SnackBar(content: Text('Added ${medias.length} track(s) to current list')),
                          );
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.queue_music_rounded, color: Tokens.accent),
                        title: const Text('Add to a list...', style: Tokens.body),
                        onTap: () {
                          Navigator.of(context).pop();
                          _showQueueSelectionDialog(context, qm, medias, title, skipDuplicates: skipDuplicates);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Folder helper functions
  String _getParentFolder(String path) {
    final sep = path.contains('\\') ? '\\' : '/';
    final idx = path.lastIndexOf(sep);
    return idx > 0 ? path.substring(0, idx) : 'Root';
  }

  String _getFolderName(String path) {
    return path.split(RegExp(r'[/\\]')).last;
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPermission) {
      return _buildPermissionDeniedView();
    }

    final manager = PlayerScope.libraryManagerOf(context);

    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final tracks = manager.tracks;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ChromeTabBar(
              selected: _activeTab,
              tabs: const ['Folders', 'Songs', 'Artists', 'Album', 'Genre', 'Year'],
              onSelect: (i) {
                setState(() {
                  _activeTab = i;
                });
              },
            ),
            _buildSearchBar(),
            Expanded(
              child: manager.isScanning
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(color: Tokens.accent),
                          const SizedBox(height: Tokens.s16),
                          Text(
                            manager.totalToScan > 0
                                ? 'Scanning library tracks... (${manager.scannedCount} / ${manager.totalToScan})'
                                : 'Scanning library tracks...',
                            style: Tokens.caption,
                          ),
                        ],
                      ),
                    )
                  : tracks.isEmpty
                      ? _buildEmptyLibraryView(manager)
                      : IndexedStack(
                          index: _activeTab,
                          sizing: StackFit.expand,
                          children: [
                            _buildFoldersTab(tracks),
                            _buildSongsTab(tracks),
                            _buildArtistsTab(tracks),
                            _buildAlbumsTab(tracks),
                            _buildGenresTab(tracks),
                            _buildYearsTab(tracks),
                          ],
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPermissionDeniedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Tokens.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.security_rounded, size: 48, color: Tokens.fgFaint),
            const SizedBox(height: Tokens.s16),
            const Text('Storage Permission Required', style: Tokens.heading),
            const SizedBox(height: Tokens.s8),
            const Text(
              'To browse and play local files, MPV Studio needs permission to access audio files on your device.',
              style: Tokens.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Tokens.s24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Tokens.accent,
                foregroundColor: Tokens.onAccent,
                shape: Tokens.squircle(Tokens.rSm) as OutlinedBorder,
                padding: const EdgeInsets.symmetric(horizontal: Tokens.s24, vertical: Tokens.s12),
              ),
              onPressed: _checkAndRequestPermission,
              child: const Text('Grant Permission'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyLibraryView(LibraryManager manager) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Tokens.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.library_music_rounded, size: 48, color: Tokens.fgFaint),
            const SizedBox(height: Tokens.s16),
            const Text('Your library is empty', style: Tokens.heading),
            const SizedBox(height: Tokens.s8),
            Text(
              defaultTargetPlatform == TargetPlatform.android
                  ? 'Click rescan to search for media files on your device.'
                  : 'Add folders under Settings (More) -> Library to scan for tracks.',
              style: Tokens.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Tokens.s24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Tokens.accent,
                foregroundColor: Tokens.onAccent,
                shape: Tokens.squircle(Tokens.rSm) as OutlinedBorder,
                padding: const EdgeInsets.symmetric(horizontal: Tokens.s24, vertical: Tokens.s12),
              ),
              onPressed: () => manager.scan(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Scan Library'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    final controller = _searchControllers[_activeTab]!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s16, Tokens.s8, Tokens.s16, Tokens.s8),
      child: Container(
        height: Tokens.controlH,
        decoration: ShapeDecoration(
          color: Tokens.surface,
          shape: Tokens.squircle(Tokens.rSm),
        ),
        padding: const EdgeInsets.symmetric(horizontal: Tokens.s12),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, size: 16, color: Tokens.fgFaint),
            const SizedBox(width: Tokens.s8),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: (val) {
                  setState(() {
                    _searchQueries[_activeTab] = val;
                  });
                },
                style: const TextStyle(fontSize: 13.5, color: Tokens.fg),
                cursorColor: Tokens.accent,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Search in ${_getTabName(_activeTab)}...',
                  hintStyle: Tokens.caption,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.close_rounded, size: 16, color: Tokens.fgFaint),
                onPressed: () {
                  setState(() {
                    controller.clear();
                    _searchQueries[_activeTab] = '';
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  String _getTabName(int idx) {
    return switch (idx) {
      0 => 'Folders',
      1 => 'Songs',
      2 => 'Artists',
      3 => 'Albums',
      4 => 'Genres',
      5 => 'Years',
      _ => 'Library'
    };
  }

  List<LibraryTrack> _filterTracks(List<LibraryTrack> tracks) {
    final Q = _searchQueries[_activeTab]!.toLowerCase();
    if (Q.isEmpty) return tracks;
    return tracks.where((t) {
      return t.title.toLowerCase().contains(Q) ||
          t.artist.toLowerCase().contains(Q) ||
          t.album.toLowerCase().contains(Q) ||
          t.genre.toLowerCase().contains(Q) ||
          t.year.toLowerCase().contains(Q) ||
          t.uri.toLowerCase().contains(Q);
    }).toList();
  }

  // List Item Widgets
  Widget _buildTrackTile(LibraryTrack track) {
    final sub = [track.artist, track.album].where((s) => s.isNotEmpty).join('  ·  ');
    return Container(
      margin: const EdgeInsets.only(bottom: Tokens.s6),
      decoration: ShapeDecoration(
        color: Tokens.surface,
        shape: Tokens.squircle(Tokens.rSm),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => _showLibraryMenu(context, track.title, [track]),
          customBorder: Tokens.squircle(Tokens.rSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.s12, vertical: Tokens.s8),
            child: Row(
              children: [
                const Icon(Icons.music_note_rounded, size: 20, color: Tokens.accent),
                const SizedBox(width: Tokens.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Tokens.body.copyWith(fontWeight: FontWeight.w500),
                      ),
                      if (sub.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Tokens.caption,
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert_rounded, size: 18, color: Tokens.fgDim),
                  onPressed: () => _showLibraryMenu(context, track.title, [track]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    required VoidCallback onPlay,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: Tokens.s6),
      decoration: ShapeDecoration(
        color: Tokens.surface,
        shape: Tokens.squircle(Tokens.rSm),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          customBorder: Tokens.squircle(Tokens.rSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.s12, vertical: Tokens.s8),
            child: Row(
              children: [
                Icon(icon, size: 20, color: Tokens.accent),
                const SizedBox(width: Tokens.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Tokens.body.copyWith(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 2),
                      Text(subtitle, style: Tokens.caption),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert_rounded, size: 18, color: Tokens.fgDim),
                  onPressed: onPlay,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubGroupHeader(String title, VoidCallback onBack) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s16, 0, Tokens.s16, Tokens.s8),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            behavior: HitTestBehavior.opaque,
            child: const Row(
              children: [
                Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: Tokens.accent),
                SizedBox(width: Tokens.s6),
                Text('Back', style: TextStyle(color: Tokens.accent, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(width: Tokens.s16),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Tokens.heading.copyWith(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorRow(String value, List<String> options, ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s16, 0, Tokens.s16, Tokens.s8),
      child: Row(
        children: [
          const Text('Group by: ', style: Tokens.caption),
          const SizedBox(width: Tokens.s8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final opt in options)
                    Padding(
                      padding: const EdgeInsets.only(right: Tokens.s6),
                      child: ChoiceChip(
                        label: Text(opt, style: TextStyle(fontSize: 11, color: value == opt ? Tokens.onAccent : Tokens.fg)),
                        selected: value == opt,
                        selectedColor: Tokens.accent,
                        backgroundColor: Tokens.surface,
                        showCheckmark: false,
                        padding: const EdgeInsets.symmetric(horizontal: Tokens.s8, vertical: 0),
                        shape: Tokens.squircle(Tokens.rSm) as OutlinedBorder,
                        onSelected: (selected) {
                          if (selected) onChanged(opt);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- TABS ---

  // 1. FOLDERS TAB
  Widget _buildFoldersTab(List<LibraryTrack> tracks) {
    final filtered = _filterTracks(tracks);

    return Column(
      children: [
        _buildSelectorRow(_folderViewMode, const ['List', 'Tree'], (mode) {
          setState(() {
            _folderViewMode = mode;
            _treeCurrentPath = 'Root';
          });
        }),
        Expanded(
          child: _buildFoldersContent(filtered),
        ),
      ],
    );
  }

  Widget _buildFoldersContent(List<LibraryTrack> filtered) {
    if (_folderViewMode == 'List') {
      if (_selectedFolder != null) {
        final folderTracks = filtered.where((t) => _getParentFolder(t.uri) == _selectedFolder).toList();
        return Column(
          children: [
            _buildSubGroupHeader(_getFolderName(_selectedFolder!), () {
              setState(() {
                _selectedFolder = null;
              });
            }),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: Tokens.s16),
                itemCount: folderTracks.length,
                itemBuilder: (context, i) => _buildTrackTile(folderTracks[i]),
              ),
            ),
          ],
        );
      }

      // Grouping list of folders
      final foldersMap = <String, List<LibraryTrack>>{};
      for (final track in filtered) {
        final pf = _getParentFolder(track.uri);
        foldersMap.putIfAbsent(pf, () => []).add(track);
      }

      final folderList = foldersMap.keys.toList()..sort();

      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: Tokens.s16),
        itemCount: folderList.length,
        itemBuilder: (context, i) {
          final path = folderList[i];
          final name = _getFolderName(path);
          final count = foldersMap[path]!.length;
          return _buildGroupTile(
            title: name,
            subtitle: '$count tracks · $path',
            icon: Icons.folder_rounded,
            onTap: () {
              setState(() {
                _selectedFolder = path;
              });
            },
            onPlay: () => _showLibraryMenu(context, 'Folder: $name', foldersMap[path]!),
          );
        },
      );
    } else {
      // Hierarchical Tree Navigation
      final allFolders = <String>{};
      for (final track in filtered) {
        allFolders.add(_getParentFolder(track.uri));
      }

      final rootFolders = <String>{};
      for (final f in allFolders) {
        bool hasParentInSet = false;
        for (final other in allFolders) {
          if (other != f && f.startsWith(other + (other.contains('\\') ? '\\' : '/'))) {
            hasParentInSet = true;
            break;
          }
        }
        if (!hasParentInSet) {
          rootFolders.add(f);
        }
      }

      if (_treeCurrentPath == 'Root') {
        final sortedRoots = rootFolders.toList()..sort();
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.s16),
          itemCount: sortedRoots.length,
          itemBuilder: (context, i) {
            final path = sortedRoots[i];
            final name = _getFolderName(path);
            final totalTracks = filtered.where((t) => _getParentFolder(t.uri).startsWith(path)).toList();
            return _buildGroupTile(
              title: name,
              subtitle: '${totalTracks.length} tracks · $path',
              icon: Icons.folder_copy_rounded,
              onTap: () {
                setState(() {
                  _treeCurrentPath = path;
                });
              },
              onPlay: () => _showLibraryMenu(context, 'Folder: $name', totalTracks),
            );
          },
        );
      } else {
        // Direct child folders
        final childFolders = allFolders.where((f) {
          final sep = _treeCurrentPath.contains('\\') ? '\\' : '/';
          if (!f.startsWith(_treeCurrentPath + sep)) return false;
          final remaining = f.substring(_treeCurrentPath.length + 1);
          return !remaining.contains('/') && !remaining.contains('\\');
        }).toList()..sort();

        // Direct tracks
        final directTracks = filtered.where((t) => _getParentFolder(t.uri) == _treeCurrentPath).toList()
          ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

        final totalItems = childFolders.length + directTracks.length;

        return Column(
          children: [
            _buildSubGroupHeader(_getFolderName(_treeCurrentPath), () {
              setState(() {
                if (rootFolders.contains(_treeCurrentPath)) {
                  _treeCurrentPath = 'Root';
                } else {
                  _treeCurrentPath = _getParentFolder(_treeCurrentPath);
                }
              });
            }),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: Tokens.s16),
                itemCount: totalItems,
                itemBuilder: (context, i) {
                  if (i < childFolders.length) {
                    final path = childFolders[i];
                    final name = _getFolderName(path);
                    final recTracks = filtered.where((t) => _getParentFolder(t.uri).startsWith(path)).toList();
                    return _buildGroupTile(
                      title: name,
                      subtitle: '${recTracks.length} tracks',
                      icon: Icons.folder_rounded,
                      onTap: () {
                        setState(() {
                          _treeCurrentPath = path;
                        });
                      },
                      onPlay: () => _showLibraryMenu(context, 'Folder: $name', recTracks),
                    );
                  } else {
                    final track = directTracks[i - childFolders.length];
                    return _buildTrackTile(track);
                  }
                },
              ),
            ),
          ],
        );
      }
    }
  }

  // 2. SONGS TAB
  Widget _buildSongsTab(List<LibraryTrack> tracks) {
    final filtered = _filterTracks(tracks)..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: Tokens.s16),
      itemCount: filtered.length,
      itemBuilder: (context, i) => _buildTrackTile(filtered[i]),
    );
  }

  // 3. ARTISTS TAB
  Widget _buildArtistsTab(List<LibraryTrack> tracks) {
    final filtered = _filterTracks(tracks);

    if (_selectedArtist != null) {
      final artistTracks = filtered.where((t) => t.artist == _selectedArtist).toList();

      if (_selectedArtistSubItem != null) {
        List<LibraryTrack> subTracks = [];
        if (_artistGroupMode == 'Albums') {
          subTracks = artistTracks.where((t) => t.album == _selectedArtistSubItem).toList();
        } else if (_artistGroupMode == 'Years') {
          subTracks = artistTracks.where((t) => t.year == _selectedArtistSubItem).toList();
        } else if (_artistGroupMode == 'Genres') {
          subTracks = artistTracks.where((t) => t.genre == _selectedArtistSubItem).toList();
        }

        return Column(
          children: [
            _buildSubGroupHeader('$_selectedArtist → $_selectedArtistSubItem', () {
              setState(() {
                _selectedArtistSubItem = null;
              });
            }),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: Tokens.s16),
                itemCount: subTracks.length,
                itemBuilder: (context, i) => _buildTrackTile(subTracks[i]),
              ),
            ),
          ],
        );
      }

      // If viewing group items (Albums, Years, Genres) for selected artist
      if (_artistGroupMode != 'Songs') {
        final Map<String, List<LibraryTrack>> grouping = {};
        for (final t in artistTracks) {
          final String key = switch (_artistGroupMode) {
            'Albums' => t.album,
            'Years' => t.year,
            'Genres' => t.genre,
            _ => ''
          };
          if (key.isNotEmpty) {
            grouping.putIfAbsent(key, () => []).add(t);
          }
        }

        final keys = grouping.keys.toList()..sort();

        return Column(
          children: [
            _buildSubGroupHeader(_selectedArtist!, () {
              setState(() {
                _selectedArtist = null;
              });
            }),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: Tokens.s16),
                itemCount: keys.length,
                itemBuilder: (context, i) {
                  final key = keys[i];
                  return _buildGroupTile(
                    title: key,
                    subtitle: '${grouping[key]!.length} tracks',
                    icon: _artistGroupMode == 'Albums' ? Icons.album_rounded : (_artistGroupMode == 'Years' ? Icons.calendar_today_rounded : Icons.label_rounded),
                    onTap: () {
                      setState(() {
                        _selectedArtistSubItem = key;
                      });
                    },
                    onPlay: () => _showLibraryMenu(context, '$_selectedArtist - $key', grouping[key]!),
                  );
                },
              ),
            ),
          ],
        );
      }

      // Flat list of songs under Selected Artist
      return Column(
        children: [
          _buildSubGroupHeader(_selectedArtist!, () {
            setState(() {
              _selectedArtist = null;
            });
          }),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: Tokens.s16),
              itemCount: artistTracks.length,
              itemBuilder: (context, i) => _buildTrackTile(artistTracks[i]),
            ),
          ),
        ],
      );
    }

    // Artists Overview
    final artistsMap = <String, List<LibraryTrack>>{};
    for (final track in filtered) {
      artistsMap.putIfAbsent(track.artist, () => []).add(track);
    }

    final artistsList = artistsMap.keys.toList()..sort();

    return Column(
      children: [
        _buildSelectorRow(_artistGroupMode, const ['Songs', 'Albums', 'Years', 'Genres'], (mode) {
          setState(() {
            _artistGroupMode = mode;
          });
        }),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.s16),
            itemCount: artistsList.length,
            itemBuilder: (context, i) {
              final artist = artistsList[i];
              final count = artistsMap[artist]!.length;
              return _buildGroupTile(
                title: artist,
                subtitle: '$count tracks',
                icon: Icons.person_rounded,
                onTap: () {
                  setState(() {
                    _selectedArtist = artist;
                    _selectedArtistSubItem = null;
                  });
                },
                onPlay: () => _showLibraryMenu(context, 'Artist: $artist', artistsMap[artist]!),
              );
            },
          ),
        ),
      ],
    );
  }

  // 4. ALBUMS TAB
  Widget _buildAlbumsTab(List<LibraryTrack> tracks) {
    final filtered = _filterTracks(tracks);

    if (_selectedAlbum != null) {
      final albumTracks = filtered.where((t) => t.album == _selectedAlbum).toList();

      if (_selectedAlbumSubItem != null) {
        List<LibraryTrack> subTracks = [];
        if (_albumGroupMode == 'Artists') {
          subTracks = albumTracks.where((t) => t.artist == _selectedAlbumSubItem).toList();
        } else if (_albumGroupMode == 'Years') {
          subTracks = albumTracks.where((t) => t.year == _selectedAlbumSubItem).toList();
        } else if (_albumGroupMode == 'Genres') {
          subTracks = albumTracks.where((t) => t.genre == _selectedAlbumSubItem).toList();
        }

        return Column(
          children: [
            _buildSubGroupHeader('$_selectedAlbum → $_selectedAlbumSubItem', () {
              setState(() {
                _selectedAlbumSubItem = null;
              });
            }),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: Tokens.s16),
                itemCount: subTracks.length,
                itemBuilder: (context, i) => _buildTrackTile(subTracks[i]),
              ),
            ),
          ],
        );
      }

      if (_albumGroupMode != 'Songs') {
        final Map<String, List<LibraryTrack>> grouping = {};
        for (final t in albumTracks) {
          final String key = switch (_albumGroupMode) {
            'Artists' => t.artist,
            'Years' => t.year,
            'Genres' => t.genre,
            _ => ''
          };
          if (key.isNotEmpty) {
            grouping.putIfAbsent(key, () => []).add(t);
          }
        }

        final keys = grouping.keys.toList()..sort();

        return Column(
          children: [
            _buildSubGroupHeader(_selectedAlbum!, () {
              setState(() {
                _selectedAlbum = null;
              });
            }),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: Tokens.s16),
                itemCount: keys.length,
                itemBuilder: (context, i) {
                  final key = keys[i];
                  return _buildGroupTile(
                    title: key,
                    subtitle: '${grouping[key]!.length} tracks',
                    icon: _albumGroupMode == 'Artists' ? Icons.person_rounded : (_albumGroupMode == 'Years' ? Icons.calendar_today_rounded : Icons.label_rounded),
                    onTap: () {
                      setState(() {
                        _selectedAlbumSubItem = key;
                      });
                    },
                    onPlay: () => _showLibraryMenu(context, '$_selectedAlbum - $key', grouping[key]!),
                  );
                },
              ),
            ),
          ],
        );
      }

      return Column(
        children: [
          _buildSubGroupHeader(_selectedAlbum!, () {
            setState(() {
              _selectedAlbum = null;
            });
          }),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: Tokens.s16),
              itemCount: albumTracks.length,
              itemBuilder: (context, i) => _buildTrackTile(albumTracks[i]),
            ),
          ),
        ],
      );
    }

    final albumsMap = <String, List<LibraryTrack>>{};
    for (final track in filtered) {
      albumsMap.putIfAbsent(track.album, () => []).add(track);
    }

    final albumsList = albumsMap.keys.toList()..sort();

    return Column(
      children: [
        _buildSelectorRow(_albumGroupMode, const ['Songs', 'Artists', 'Years', 'Genres'], (mode) {
          setState(() {
            _albumGroupMode = mode;
          });
        }),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.s16),
            itemCount: albumsList.length,
            itemBuilder: (context, i) {
              final album = albumsList[i];
              final count = albumsMap[album]!.length;
              return _buildGroupTile(
                title: album,
                subtitle: '$count tracks',
                icon: Icons.album_rounded,
                onTap: () {
                  setState(() {
                    _selectedAlbum = album;
                    _selectedAlbumSubItem = null;
                  });
                },
                onPlay: () => _showLibraryMenu(context, 'Album: $album', albumsMap[album]!),
              );
            },
          ),
        ),
      ],
    );
  }

  // 5. GENRES TAB
  Widget _buildGenresTab(List<LibraryTrack> tracks) {
    final filtered = _filterTracks(tracks);

    if (_selectedGenre != null) {
      final genreTracks = filtered.where((t) => t.genre == _selectedGenre).toList();

      if (_selectedGenreSubItem != null) {
        List<LibraryTrack> subTracks = [];
        if (_genreGroupMode == 'Artists') {
          subTracks = genreTracks.where((t) => t.artist == _selectedGenreSubItem).toList();
        } else if (_genreGroupMode == 'Albums') {
          subTracks = genreTracks.where((t) => t.album == _selectedGenreSubItem).toList();
        }

        return Column(
          children: [
            _buildSubGroupHeader('$_selectedGenre → $_selectedGenreSubItem', () {
              setState(() {
                _selectedGenreSubItem = null;
              });
            }),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: Tokens.s16),
                itemCount: subTracks.length,
                itemBuilder: (context, i) => _buildTrackTile(subTracks[i]),
              ),
            ),
          ],
        );
      }

      if (_genreGroupMode != 'Songs') {
        final Map<String, List<LibraryTrack>> grouping = {};
        for (final t in genreTracks) {
          final String key = switch (_genreGroupMode) {
            'Artists' => t.artist,
            'Albums' => t.album,
            _ => ''
          };
          if (key.isNotEmpty) {
            grouping.putIfAbsent(key, () => []).add(t);
          }
        }

        final keys = grouping.keys.toList()..sort();

        return Column(
          children: [
            _buildSubGroupHeader(_selectedGenre!, () {
              setState(() {
                _selectedGenre = null;
              });
            }),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: Tokens.s16),
                itemCount: keys.length,
                itemBuilder: (context, i) {
                  final key = keys[i];
                  return _buildGroupTile(
                    title: key,
                    subtitle: '${grouping[key]!.length} tracks',
                    icon: _genreGroupMode == 'Artists' ? Icons.person_rounded : Icons.album_rounded,
                    onTap: () {
                      setState(() {
                        _selectedGenreSubItem = key;
                      });
                    },
                    onPlay: () => _showLibraryMenu(context, '$_selectedGenre - $key', grouping[key]!),
                  );
                },
              ),
            ),
          ],
        );
      }

      return Column(
        children: [
          _buildSubGroupHeader(_selectedGenre!, () {
            setState(() {
              _selectedGenre = null;
            });
          }),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: Tokens.s16),
              itemCount: genreTracks.length,
              itemBuilder: (context, i) => _buildTrackTile(genreTracks[i]),
            ),
          ),
        ],
      );
    }

    final genresMap = <String, List<LibraryTrack>>{};
    for (final track in filtered) {
      genresMap.putIfAbsent(track.genre, () => []).add(track);
    }

    final genresList = genresMap.keys.toList()..sort();

    return Column(
      children: [
        _buildSelectorRow(_genreGroupMode, const ['Songs', 'Artists', 'Albums'], (mode) {
          setState(() {
            _genreGroupMode = mode;
          });
        }),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.s16),
            itemCount: genresList.length,
            itemBuilder: (context, i) {
              final genre = genresList[i];
              final count = genresMap[genre]!.length;
              return _buildGroupTile(
                title: genre,
                subtitle: '$count tracks',
                icon: Icons.label_rounded,
                onTap: () {
                  setState(() {
                    _selectedGenre = genre;
                    _selectedGenreSubItem = null;
                  });
                },
                onPlay: () => _showLibraryMenu(context, 'Genre: $genre', genresMap[genre]!),
              );
            },
          ),
        ),
      ],
    );
  }

  // 6. YEARS TAB
  Widget _buildYearsTab(List<LibraryTrack> tracks) {
    final filtered = _filterTracks(tracks);

    if (_selectedYear != null) {
      final yearTracks = filtered.where((t) => t.year == _selectedYear).toList();

      if (_selectedYearSubItem != null) {
        final subTracks = yearTracks.where((t) => t.album == _selectedYearSubItem).toList();
        return Column(
          children: [
            _buildSubGroupHeader('$_selectedYear → $_selectedYearSubItem', () {
              setState(() {
                _selectedYearSubItem = null;
              });
            }),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: Tokens.s16),
                itemCount: subTracks.length,
                itemBuilder: (context, i) => _buildTrackTile(subTracks[i]),
              ),
            ),
          ],
        );
      }

      if (_yearGroupMode != 'Songs') {
        final Map<String, List<LibraryTrack>> grouping = {};
        for (final t in yearTracks) {
          if (t.album.isNotEmpty) {
            grouping.putIfAbsent(t.album, () => []).add(t);
          }
        }

        final keys = grouping.keys.toList()..sort();

        return Column(
          children: [
            _buildSubGroupHeader(_selectedYear!, () {
              setState(() {
                _selectedYear = null;
              });
            }),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: Tokens.s16),
                itemCount: keys.length,
                itemBuilder: (context, i) {
                  final key = keys[i];
                  return _buildGroupTile(
                    title: key,
                    subtitle: '${grouping[key]!.length} tracks',
                    icon: Icons.album_rounded,
                    onTap: () {
                      setState(() {
                        _selectedYearSubItem = key;
                      });
                    },
                    onPlay: () => _showLibraryMenu(context, '$_selectedYear - $key', grouping[key]!),
                  );
                },
              ),
            ),
          ],
        );
      }

      return Column(
        children: [
          _buildSubGroupHeader(_selectedYear!, () {
            setState(() {
              _selectedYear = null;
            });
          }),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: Tokens.s16),
              itemCount: yearTracks.length,
              itemBuilder: (context, i) => _buildTrackTile(yearTracks[i]),
            ),
          ),
        ],
      );
    }

    final yearsMap = <String, List<LibraryTrack>>{};
    for (final track in filtered) {
      yearsMap.putIfAbsent(track.year, () => []).add(track);
    }

    final yearsList = yearsMap.keys.toList()..sort();

    return Column(
      children: [
        _buildSelectorRow(_yearGroupMode, const ['Songs', 'Albums'], (mode) {
          setState(() {
            _yearGroupMode = mode;
          });
        }),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.s16),
            itemCount: yearsList.length,
            itemBuilder: (context, i) {
              final year = yearsList[i];
              final count = yearsMap[year]!.length;
              return _buildGroupTile(
                title: year,
                subtitle: '$count tracks',
                icon: Icons.calendar_today_rounded,
                onTap: () {
                  setState(() {
                    _selectedYear = year;
                    _selectedYearSubItem = null;
                  });
                },
                onPlay: () => _showLibraryMenu(context, 'Year: $year', yearsMap[year]!),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ChromeTabBar extends StatelessWidget {
  final int selected;
  final List<String> tabs;
  final ValueChanged<int> onSelect;

  const _ChromeTabBar({
    required this.selected,
    required this.tabs,
    required this.onSelect,
  });

  static const _radius = BorderRadius.vertical(top: Radius.circular(12));
  static const _shape = ContinuousRectangleBorder(borderRadius: _radius);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Tokens.surface,
      padding: const EdgeInsets.only(top: Tokens.s6, left: Tokens.s8, right: Tokens.s8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < tabs.length; i++) _tab(i),
          ],
        ),
      ),
    );
  }

  Widget _tab(int i) {
    final active = i == selected;
    return Padding(
      padding: const EdgeInsets.only(right: Tokens.s4),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => onSelect(i),
          customBorder: _shape,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: ShapeDecoration(
              color: active ? Tokens.bg : Colors.transparent,
              shape: _shape,
            ),
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 2,
                    color: active ? Tokens.accent : Colors.transparent,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Tokens.s12, Tokens.s6, Tokens.s12, Tokens.s12),
                    child: Text(
                      tabs[i],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                        color: active ? Tokens.fg : Tokens.fgDim,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
