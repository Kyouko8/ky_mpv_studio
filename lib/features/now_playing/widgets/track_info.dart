import 'package:flutter/material.dart';

import '../../../state/player_scope.dart';
import '../../../ui/tokens.dart';
import '../../../util/reactive.dart';

/// Title + artist line. Title prefers the `title` tag, falling back to
/// `mediaTitle` (which itself falls back to the filename). Artist/album
/// come from the metadata map (case-insensitive lookup).
class TrackInfo extends StatelessWidget {
  /// Centre the text (stacked layout) or left-align it (side strip).
  final bool centered;
  const TrackInfo({super.key, this.centered = true});

  static String? _lookup(Map<String, String> m, String key) {
    for (final e in m.entries) {
      if (e.key.toLowerCase() == key) return e.value;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    return Live<Map<String, String>>(
      stream: player.stream.metadata,
      initial: player.state.metadata,
      builder: (context, meta) => Live<String>(
        stream: player.stream.mediaTitle,
        initial: player.state.mediaTitle,
        builder: (context, mediaTitle) {
          final title = _lookup(meta, 'title') ??
              (mediaTitle.isNotEmpty ? mediaTitle : 'Nothing playing');
          final artist = _lookup(meta, 'artist');
          final album = _lookup(meta, 'album');
          final sub = [artist, album].whereType<String>().join(' · ');
          final align = centered ? TextAlign.center : TextAlign.start;
          return Column(
            crossAxisAlignment: centered
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Tokens.title,
                textAlign: align,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (sub.isNotEmpty) ...[
                const SizedBox(height: Tokens.s4),
                Text(
                  sub,
                  style: Tokens.label,
                  textAlign: align,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
