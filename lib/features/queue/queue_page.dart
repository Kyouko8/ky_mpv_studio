import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../studio/player_scope.dart';
import '../../studio/queue_manager.dart';
import '../../ui/tokens.dart';
import '../../util/media_import.dart';
import '../../util/reactive.dart';

class QueuePage extends StatefulWidget {
  const QueuePage({super.key});

  @override
  State<QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends State<QueuePage> {
  late Player _player;
  late QueueManager _queueManager;
  bool _dragging = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _player = PlayerScope.of(context);
    _queueManager = PlayerScope.queueManagerOf(context);
  }

  Future<void> _enqueue(List<String> paths) async {
    final medias = [
      for (final p in paths) Media(p, extras: {'title': baseNameNoExt(p)}),
    ];
    if (medias.isEmpty) return;
    for (final m in medias) {
      await _queueManager.add(m);
    }
  }

  Future<void> _addFiles() async => _enqueue(await pickAudioFiles());
  Future<void> _addFolder() async => _enqueue(await pickAudioFolder());

  Future<void> _loadPlaylist() async {
    const group = XTypeGroup(
      label: 'playlist',
      extensions: ['m3u', 'm3u8', 'pls', 'cue'],
      uniformTypeIdentifiers: ['public.m3u-playlist', 'public.text'],
    );
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null) return;
    await _player.openPlaylistFile(Media(file.path), play: true);
  }

  Future<void> _replace(int index) async {
    final paths = await pickAudioFiles();
    if (paths.isEmpty) return;
    final p = paths.first;
    await _queueManager.replace(index, Media(p, extras: {'title': baseNameNoExt(p)}));
  }

  void _showAdminDialog() {
    showDialog(
      context: context,
      builder: (context) => QueueAdminDialog(queueManager: _queueManager),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _queueManager,
      builder: (context, _) {
        final queue = _queueManager.viewedQueue;
        final items = queue.items;

        return DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: (detail) {
            setState(() => _dragging = false);
            _enqueue(resolveDroppedPaths(detail.files.map((f) => f.path)));
          },
          child: Container(
            color: _dragging ? Tokens.accentWash : null,
            child: Column(
              children: [
                _Toolbar(
                  onAddFiles: _addFiles,
                  onAddFolder: _addFolder,
                  onLoadPlaylist: _loadPlaylist,
                  onClear: _queueManager.clearPlaylist,
                ),
                // Queue selector / administration banner
                Padding(
                  padding: const EdgeInsets.fromLTRB(Tokens.s16, 0, Tokens.s16, Tokens.s8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Tokens.s12,
                      vertical: Tokens.s6,
                    ),
                    decoration: ShapeDecoration(
                      color: Tokens.surface,
                      shape: Tokens.squircle(Tokens.rSm),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.playlist_play_rounded, size: 18, color: Tokens.accent),
                        const SizedBox(width: Tokens.s8),
                        Expanded(
                          child: GestureDetector(
                            onTap: _showAdminDialog,
                            behavior: HitTestBehavior.opaque,
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    'Lista: ${queue.name}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Tokens.body.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: Tokens.s4),
                                const Icon(Icons.arrow_drop_down_rounded, size: 18, color: Tokens.fgDim),
                              ],
                            ),
                          ),
                        ),
                        if (_queueManager.playingQueueId == queue.id) ...[
                          const Icon(Icons.volume_up_rounded, size: 14, color: Tokens.accent),
                          const SizedBox(width: Tokens.s8),
                        ],
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: _showAdminDialog,
                          icon: const Icon(Icons.settings_rounded, size: 18, color: Tokens.fgDim),
                          tooltip: 'Administrar listas',
                        ),
                      ],
                    ),
                  ),
                ),
                // Source-playlist banner (from playlist files)
                Live<String>(
                  stream: _player.stream.playlistPath,
                  initial: _player.state.playlistPath,
                  builder: (context, path) {
                    if (path.isEmpty) return const SizedBox.shrink();
                    return _PlaylistBanner(
                      path: path,
                      onPrevPlaylist: _player.previousPlaylist,
                      onNextPlaylist: _player.nextPlaylist,
                    );
                  },
                ),
                Expanded(
                  child: Live<Playlist>(
                    stream: _player.stream.playlist,
                    initial: _player.state.playlist,
                    builder: (context, mpvPlaylist) {
                      if (items.isEmpty) {
                        return _EmptyQueue(
                          onAddFiles: _addFiles,
                          onAddFolder: _addFolder,
                        );
                      }

                      // Check which track is playing
                      // We can match playing URI with items in our viewed list
                      final playingUri = (mpvPlaylist.index >= 0 && mpvPlaylist.index < mpvPlaylist.items.length)
                          ? mpvPlaylist.items[mpvPlaylist.index].uri
                          : null;

                      return ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                          Tokens.s16,
                          Tokens.s12,
                          Tokens.s16,
                          Tokens.s12,
                        ),
                        buildDefaultDragHandles: false,
                        itemCount: items.length,
                        onReorder: (oldIndex, newIndex) {
                          if (newIndex > oldIndex) {
                            newIndex -= 1;
                          }
                          if (newIndex != oldIndex) {
                            _queueManager.move(oldIndex, newIndex);
                          }
                        },
                        itemBuilder: (context, i) {
                          final item = items[i];
                          // Is this item the currently playing track?
                          final isPlaying = _queueManager.playingQueueId == queue.id &&
                              playingUri != null &&
                              item.uri == playingUri &&
                              item.active;

                          return _QueueTile(
                            key: ValueKey('${item.uri}#$i'),
                            index: i,
                            item: item,
                            current: isPlaying,
                            onTap: () => _queueManager.playTrack(i),
                            onActiveChanged: (active) => _queueManager.setTrackActive(i, active),
                            onReplace: () => _replace(i),
                            onRemove: () => _queueManager.remove(i),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  final VoidCallback onAddFiles;
  final VoidCallback onAddFolder;
  final VoidCallback onLoadPlaylist;
  final VoidCallback onClear;
  const _Toolbar({
    required this.onAddFiles,
    required this.onAddFolder,
    required this.onLoadPlaylist,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final folderEnabled = !kIsWeb && defaultTargetPlatform != TargetPlatform.iOS;
    const folderDisabledTip = 'Folder import isn’t available on iOS';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Tokens.s16,
        Tokens.s8,
        Tokens.s16,
        Tokens.s8,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < Tokens.desktopBreakpoint) {
            return Row(
              children: [
                ToolButton(
                  icon: Icons.add_rounded,
                  label: 'Add files',
                  onTap: onAddFiles,
                  primary: true,
                  iconOnly: true,
                ),
                const SizedBox(width: Tokens.s8),
                ToolButton(
                  icon: Icons.folder_open_rounded,
                  label: 'Add folder',
                  onTap: onAddFolder,
                  iconOnly: true,
                  enabled: folderEnabled,
                  disabledTooltip: folderDisabledTip,
                ),
                const SizedBox(width: Tokens.s8),
                ToolButton(
                  icon: Icons.playlist_play_rounded,
                  label: 'Load playlist',
                  onTap: onLoadPlaylist,
                  iconOnly: true,
                ),
                const Spacer(),
                ToolButton(
                  icon: Icons.clear_all_rounded,
                  label: 'Clear',
                  onTap: onClear,
                  iconOnly: true,
                ),
              ],
            );
          }
          return Row(
            children: [
              ToolButton(
                icon: Icons.add_rounded,
                label: 'Add files',
                onTap: onAddFiles,
                primary: true,
              ),
              const SizedBox(width: Tokens.s8),
              ToolButton(
                icon: Icons.folder_open_rounded,
                label: 'Add folder',
                onTap: onAddFolder,
                enabled: folderEnabled,
                disabledTooltip: folderDisabledTip,
              ),
              const SizedBox(width: Tokens.s8),
              ToolButton(
                icon: Icons.playlist_play_rounded,
                label: 'Load playlist',
                onTap: onLoadPlaylist,
              ),
              const Spacer(),
              ToolButton(
                icon: Icons.clear_all_rounded,
                label: 'Clear',
                onTap: onClear,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PlaylistBanner extends StatelessWidget {
  final String path;
  final VoidCallback onPrevPlaylist;
  final VoidCallback onNextPlaylist;
  const _PlaylistBanner({
    required this.path,
    required this.onPrevPlaylist,
    required this.onNextPlaylist,
  });

  String get _name {
    final sep = path.contains('\\') ? '\\' : '/';
    final cut = path.lastIndexOf(sep);
    return cut < 0 ? path : path.substring(cut + 1);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s16, 0, Tokens.s16, Tokens.s8),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.s12,
          vertical: Tokens.s8,
        ),
        decoration: ShapeDecoration(
          color: Tokens.surface2,
          shape: Tokens.squircle(Tokens.rSm),
        ),
        child: Row(
          children: [
            const Icon(Icons.queue_music_rounded, size: 16, color: Tokens.accent),
            const SizedBox(width: Tokens.s8),
            Expanded(
              child: Text(
                _name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Tokens.caption,
              ),
            ),
            _IconTap(
              icon: Icons.skip_previous_rounded,
              tooltip: 'Previous playlist',
              onTap: onPrevPlaylist,
            ),
            _IconTap(
              icon: Icons.skip_next_rounded,
              tooltip: 'Next playlist',
              onTap: onNextPlaylist,
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  final int index;
  final PlaylistItem item;
  final bool current;
  final VoidCallback onTap;
  final ValueChanged<bool> onActiveChanged;
  final VoidCallback onReplace;
  final VoidCallback onRemove;

  const _QueueTile({
    super.key,
    required this.index,
    required this.item,
    required this.current,
    required this.onTap,
    required this.onActiveChanged,
    required this.onReplace,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final hasMeta = item.artist.isNotEmpty || item.album.isNotEmpty;
    final sub = [item.artist, item.album].where((e) => e.isNotEmpty).join('  ·  ');

    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.s6),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          customBorder: Tokens.squircle(Tokens.rSm),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(
              Tokens.s6,
              Tokens.s8,
              Tokens.s6,
              Tokens.s8,
            ),
            decoration: ShapeDecoration(
              color: current ? Tokens.accentWash : Tokens.surface,
              shape: Tokens.squircle(Tokens.rSm),
            ),
            child: Row(
              children: [
                // Active checkbox
                Checkbox(
                  value: item.active,
                  onChanged: (val) => onActiveChanged(val ?? true),
                  activeColor: Tokens.accent,
                  checkColor: Tokens.onAccent,
                  visualDensity: VisualDensity.compact,
                ),
                SizedBox(
                  width: 24,
                  child: current
                      ? const Icon(Icons.volume_up_rounded, size: 16, color: Tokens.accent)
                      : Text(
                          '${index + 1}',
                          style: Tokens.numeric.copyWith(
                            color: item.active ? Tokens.fgDim : Tokens.fgFaint,
                          ),
                          textAlign: TextAlign.center,
                        ),
                ),
                const SizedBox(width: Tokens.s8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title.isNotEmpty ? item.title : baseNameNoExt(item.uri),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Tokens.body.copyWith(
                          color: current
                              ? Tokens.accent
                              : (item.active ? Tokens.fg : Tokens.fgFaint),
                          fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                          decoration: item.active ? null : TextDecoration.lineThrough,
                        ),
                      ),
                      if (hasMeta) ...[
                        const SizedBox(height: 2),
                        Text(
                          sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Tokens.caption.copyWith(
                            color: item.active ? Tokens.fgDim : Tokens.fgFaint,
                          ),
                        ),
                      ],
                      const SizedBox(height: 2),
                      Text(
                        item.uri,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Tokens.caption.copyWith(
                          fontSize: 11,
                          color: Tokens.fgFaint,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Tokens.s8),
                ReorderableDragStartListener(
                  index: index,
                  child: const MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Padding(
                      padding: EdgeInsets.all(Tokens.s6),
                      child: Icon(Icons.drag_indicator_rounded, size: 18, color: Tokens.fgFaint),
                    ),
                  ),
                ),
                _IconTap(
                  icon: Icons.swap_horiz_rounded,
                  tooltip: 'Replace',
                  onTap: onReplace,
                ),
                _IconTap(
                  icon: Icons.close_rounded,
                  tooltip: 'Remove',
                  onTap: onRemove,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconTap extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _IconTap({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          customBorder: Tokens.squircle(Tokens.rSm),
          child: Padding(
            padding: const EdgeInsets.all(Tokens.s6),
            child: Icon(icon, size: 16, color: Tokens.fgFaint),
          ),
        ),
      ),
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  final VoidCallback onAddFiles;
  final VoidCallback onAddFolder;
  const _EmptyQueue({required this.onAddFiles, required this.onAddFolder});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.queue_music_rounded, size: 40, color: Tokens.fgFaint),
          const SizedBox(height: Tokens.s12),
          const Text('Queue is empty', style: Tokens.label),
          const SizedBox(height: Tokens.s4),
          const Text(
            'Add files, a folder, or drop them here.',
            style: Tokens.caption,
          ),
          const SizedBox(height: Tokens.s20),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ToolButton(
                icon: Icons.add_rounded,
                label: 'Add files',
                onTap: onAddFiles,
                primary: true,
              ),
              const SizedBox(width: Tokens.s8),
              ToolButton(
                icon: Icons.folder_open_rounded,
                label: 'Add folder',
                onTap: onAddFolder,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool iconOnly;
  final bool enabled;
  final String? disabledTooltip;

  const ToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.iconOnly = false,
    this.enabled = true,
    this.disabledTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final fg = !enabled ? Tokens.fgFaint : (primary ? Tokens.onAccent : Tokens.fg);
    final bg = !enabled || !primary ? Tokens.surface2 : Tokens.accent;

    final content = iconOnly
        ? Icon(icon, size: 18, color: fg)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: Tokens.s6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          );

    final pill = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: Tokens.squircle(Tokens.rSm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Tokens.s12,
            vertical: Tokens.s8,
          ),
          decoration: ShapeDecoration(
            color: bg,
            shape: Tokens.squircle(Tokens.rSm),
          ),
          child: content,
        ),
      ),
    );

    final tip = !enabled ? (disabledTooltip ?? label) : (iconOnly ? label : null);
    return tip == null ? pill : Tooltip(message: tip, child: pill);
  }
}

class QueueAdminDialog extends StatefulWidget {
  final QueueManager queueManager;
  const QueueAdminDialog({super.key, required this.queueManager});

  @override
  State<QueueAdminDialog> createState() => _QueueAdminDialogState();
}

class _QueueAdminDialogState extends State<QueueAdminDialog> {
  @override
  Widget build(BuildContext context) {
    final qm = widget.queueManager;
    return ListenableBuilder(
      listenable: qm,
      builder: (context, _) {
        final queues = qm.queues;
        return AlertDialog(
          backgroundColor: Tokens.surface,
          title: Row(
            children: [
              const Icon(Icons.queue_music_rounded, color: Tokens.accent),
              const SizedBox(width: Tokens.s8),
              const Text('Administrar Listas', style: Tokens.heading),
            ],
          ),
          content: SizedBox(
            width: 400,
            height: 350,
            child: Column(
              children: [
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: queues.length,
                    onReorder: (oldIdx, newIdx) {
                      qm.reorderQueues(oldIdx, newIdx);
                    },
                    itemBuilder: (context, i) {
                      final q = queues[i];
                      final isViewed = q.id == qm.viewedQueueId;
                      final isPlaying = q.id == qm.playingQueueId;
                      return _DialogQueueTile(
                        key: ValueKey(q.id),
                        index: i,
                        queue: q,
                        isViewed: isViewed,
                        isPlaying: isPlaying,
                        onTap: () {
                          qm.selectViewedQueue(q.id);
                        },
                        onRename: () => _showRenameDialog(context, qm, q),
                        onDelete: queues.length > 1
                            ? () {
                                try {
                                  qm.deleteQueue(q.id);
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.toString())),
                                  );
                                }
                              }
                            : null,
                      );
                    },
                  ),
                ),
                const SizedBox(height: Tokens.s12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Tokens.accent,
                    foregroundColor: Tokens.onAccent,
                    shape: Tokens.squircle(Tokens.rSm) as OutlinedBorder,
                  ),
                  onPressed: () {
                    try {
                      qm.createQueue();
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.toString())),
                      );
                    }
                  },
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Nueva Lista'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar', style: TextStyle(color: Tokens.accent)),
            ),
          ],
        );
      },
    );
  }

  void _showRenameDialog(BuildContext context, QueueManager qm, QueueModel q) {
    final controller = TextEditingController(text: q.name);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Tokens.surface2,
          title: const Text('Renombrar Lista', style: Tokens.label),
          content: TextField(
            controller: controller,
            style: const TextStyle(color: Tokens.fg),
            cursorColor: Tokens.accent,
            decoration: const InputDecoration(
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Tokens.accent),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar', style: TextStyle(color: Tokens.fgDim)),
            ),
            TextButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isNotEmpty) {
                  qm.renameQueue(q.id, text);
                }
                Navigator.of(context).pop();
              },
              child: const Text('Guardar', style: TextStyle(color: Tokens.accent)),
            ),
          ],
        );
      },
    );
  }
}

class _DialogQueueTile extends StatelessWidget {
  final QueueModel queue;
  final int index;
  final bool isViewed;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback? onDelete;

  const _DialogQueueTile({
    super.key,
    required this.queue,
    required this.index,
    required this.isViewed,
    required this.isPlaying,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.s6),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          customBorder: Tokens.squircle(Tokens.rSm),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.s12, vertical: Tokens.s8),
            decoration: ShapeDecoration(
              color: isViewed ? Tokens.accentWash : Tokens.surface2,
              shape: Tokens.squircle(Tokens.rSm),
            ),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: const MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Icon(Icons.drag_indicator_rounded, size: 18, color: Tokens.fgFaint),
                  ),
                ),
                const SizedBox(width: Tokens.s8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              queue.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Tokens.body.copyWith(
                                color: isViewed ? Tokens.accent : Tokens.fg,
                                fontWeight: isViewed ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (isPlaying) ...[
                            const SizedBox(width: Tokens.s4),
                            const Icon(Icons.volume_up_rounded, size: 14, color: Tokens.accent),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${queue.items.length} canciones',
                        style: Tokens.caption,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onRename,
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  color: Tokens.fgDim,
                  splashRadius: 16,
                  tooltip: 'Renombrar',
                ),
                if (onDelete != null)
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    color: Tokens.red,
                    splashRadius: 16,
                    tooltip: 'Eliminar',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
