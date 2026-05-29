import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../../state/player_scope.dart';
import '../../../ui/tokens.dart';

/// Square album art. Renders embedded cover bytes from
/// `player.stream.coverArt`, falling back to a flat placeholder when a
/// track carries none.
class CoverArtView extends StatelessWidget {
  final double size;
  const CoverArtView({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: StreamBuilder<CoverArt?>(
        stream: player.stream.coverArt,
        initialData: player.state.coverArt,
        builder: (context, snap) {
          final art = snap.data;
          return ClipRRect(
            borderRadius: BorderRadius.circular(Tokens.rLg),
            child: art != null
                ? Image.memory(
                    art.bytes,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => const _Placeholder(),
                  )
                : const _Placeholder(),
          );
        },
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Tokens.surface2,
      child: Center(
        child: Icon(Icons.music_note_rounded, size: 44, color: Tokens.fgFaint),
      ),
    );
  }
}
