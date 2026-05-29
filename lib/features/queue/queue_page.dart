import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../state/player_scope.dart';
import '../../ui/tokens.dart';
import '../../util/media_import.dart';
import '../../util/reactive.dart';

/// The live playback queue — a view onto `player.stream.playlist`. Add
/// tracks via the picker or by dropping files/folders; tap to jump,
/// drag to reorder, swipe the trailing handle to remove.
class QueuePage extends StatefulWidget {
  const QueuePage({super.key});

  @override
  State<QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends State<QueuePage> {
  late final Player _player;
  bool _dragging = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _player = PlayerScope.of(context);
  }

  Future<void> _enqueue(List<String> paths) async {
    final medias = [
      for (final p in paths)
        Media(p, extras: {'title': baseNameNoExt(p)}),
    ];
    if (medias.isEmpty) return;
    if (_player.state.playlist.items.isEmpty) {
      await _player.openAll(medias, play: true);
    } else {
      for (final m in medias) {
        await _player.add(m);
      }
    }
  }

  Future<void> _addFiles() async => _enqueue(await pickAudioFiles());
  Future<void> _addFolder() async => _enqueue(await pickAudioFolder());

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) {
        setState(() => _dragging = false);
        _enqueue(resolveDroppedPaths(detail.files.map((f) => f.path)));
      },
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: _dragging ? Tokens.accent : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            _Toolbar(
              onAddFiles: _addFiles,
              onAddFolder: _addFolder,
              onClear: _player.clearPlaylist,
            ),
            const Divider(height: 1, thickness: 1, color: Tokens.line),
            Expanded(
              child: Live<Playlist>(
                stream: _player.stream.playlist,
                initial: _player.state.playlist,
                builder: (context, playlist) {
                  if (playlist.items.isEmpty) {
                    return _EmptyQueue(
                      onAddFiles: _addFiles,
                      onAddFolder: _addFolder,
                    );
                  }
                  return ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: Tokens.s8),
                    itemCount: playlist.items.length,
                    // onReorderItem already adjusts newIndex for the
                    // item removed at oldIndex.
                    onReorderItem: (oldIndex, newIndex) {
                      if (newIndex != oldIndex) {
                        _player.move(oldIndex, newIndex);
                      }
                    },
                    itemBuilder: (context, i) {
                      final item = playlist.items[i];
                      return _QueueTile(
                        key: ValueKey('${item.uri}#$i'),
                        index: i,
                        title: _titleOf(item),
                        current: i == playlist.index,
                        onTap: () => _player.jump(i),
                        onRemove: () => _player.remove(i),
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
  }

  static String _titleOf(Media item) {
    final t = item.extras?['title'];
    if (t is String && t.isNotEmpty) return t;
    return baseNameNoExt(item.uri);
  }
}

class _Toolbar extends StatelessWidget {
  final VoidCallback onAddFiles;
  final VoidCallback onAddFolder;
  final VoidCallback onClear;
  const _Toolbar({
    required this.onAddFiles,
    required this.onAddFolder,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Tokens.s16,
        Tokens.s8,
        Tokens.s16,
        Tokens.s8,
      ),
      child: Row(
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
          const Spacer(),
          ToolButton(
            icon: Icons.clear_all_rounded,
            label: 'Clear',
            onTap: onClear,
          ),
        ],
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  final int index;
  final String title;
  final bool current;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _QueueTile({
    super.key,
    required this.index,
    required this.title,
    required this.current,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Tokens.s16,
            vertical: Tokens.s12,
          ),
          color: current ? Tokens.accentWash : Colors.transparent,
          child: Row(
            children: [
              SizedBox(
                width: 26,
                child: current
                    ? const Icon(Icons.volume_up_rounded,
                        size: 16, color: Tokens.accent)
                    : Text('${index + 1}',
                        style: Tokens.numeric, textAlign: TextAlign.center),
              ),
              const SizedBox(width: Tokens.s12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Tokens.body.copyWith(
                    color: current ? Tokens.accent : Tokens.fg,
                    fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded, size: 16),
                color: Tokens.fgFaint,
                splashRadius: 16,
                tooltip: 'Remove',
              ),
            ],
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

/// Small flat pill button used in section toolbars.
class ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  const ToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Tokens.onAccent : Tokens.fg;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.rSm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Tokens.s12,
            vertical: Tokens.s8,
          ),
          decoration: BoxDecoration(
            color: primary ? Tokens.accent : Tokens.surface2,
            borderRadius: BorderRadius.circular(Tokens.rSm),
          ),
          child: Row(
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
          ),
        ),
      ),
    );
  }
}
