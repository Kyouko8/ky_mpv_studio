import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../../ui/tokens.dart';
import '../../../ui/widgets/section_body.dart';
import '../../../util/duration_format.dart';

/// Chapter navigation, list and per-chapter metadata for the current file.
/// mpv clamps `chapter` writes to the valid range, so navigation is a
/// no-op when the file carries no chapters.
class ChaptersGroup extends StatelessWidget {
  final Player player;
  const ChaptersGroup(this.player, {super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Chapter>>(
      stream: player.stream.chapters,
      initialData: player.state.chapters,
      builder: (context, chaptersSnap) {
        final chapters = chaptersSnap.data ?? const <Chapter>[];
        return StreamBuilder<int?>(
          stream: player.stream.currentChapter,
          initialData: player.state.currentChapter,
          builder: (context, currentSnap) {
            final current = currentSnap.data;
            final hasChapters = chapters.isNotEmpty;
            final atFirst = current == null || current <= 0;
            final atLast = current == null || current >= chapters.length - 1;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsGroup(
                  label: 'Chapters',
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Tokens.s6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              hasChapters
                                  ? 'Chapter ${(current ?? 0) + 1} of ${chapters.length}'
                                  : 'No chapters',
                              style: Tokens.body,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_previous_rounded),
                            color: Tokens.fgDim,
                            onPressed: hasChapters && !atFirst
                                ? () => player.setChapter(current - 1)
                                : null,
                            tooltip: 'Previous chapter',
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_next_rounded),
                            color: Tokens.fgDim,
                            onPressed: hasChapters && !atLast
                                ? () => player.setChapter(current + 1)
                                : null,
                            tooltip: 'Next chapter',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (hasChapters)
                  _ChapterList(
                    chapters: chapters,
                    current: current,
                    onTap: player.setChapter,
                  ),
                _Metadata(player: player),
              ],
            );
          },
        );
      },
    );
  }
}

class _ChapterList extends StatelessWidget {
  final List<Chapter> chapters;
  final int? current;
  final ValueChanged<int> onTap;
  const _ChapterList({
    required this.chapters,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < chapters.length; i++)
            _ChapterTile(
              index: i,
              chapter: chapters[i],
              active: i == current,
              onTap: () => onTap(i),
            ),
        ],
      ),
    );
  }
}

class _ChapterTile extends StatelessWidget {
  final int index;
  final Chapter chapter;
  final bool active;
  final VoidCallback onTap;
  const _ChapterTile({
    required this.index,
    required this.chapter,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = chapter.title?.trim().isNotEmpty == true
        ? chapter.title!
        : 'Chapter ${index + 1}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          customBorder: Tokens.squircle(Tokens.rSm),
          child: Container(
            decoration: ShapeDecoration(
              color: active ? Tokens.accentWash : Tokens.surface,
              shape: Tokens.squircle(Tokens.rSm),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: Tokens.s12,
              vertical: Tokens.s8,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    '${index + 1}',
                    style: Tokens.numeric.copyWith(
                      color: active ? Tokens.accent : Tokens.fgFaint,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tokens.body.copyWith(
                      color: active ? Tokens.accent : Tokens.fg,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(width: Tokens.s8),
                Text(formatDuration(chapter.time), style: Tokens.numeric),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Metadata extends StatelessWidget {
  final Player player;
  const _Metadata({required this.player});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, String>>(
      stream: player.stream.chapterMetadata,
      initialData: player.state.chapterMetadata,
      builder: (context, snap) {
        final meta = snap.data ?? const <String, String>{};
        if (meta.isEmpty) return const SizedBox.shrink();
        return SettingsGroup(
          label: 'Active chapter metadata',
          children: [
            for (final e in meta.entries) InfoRow(label: e.key, value: e.value),
          ],
        );
      },
    );
  }
}
