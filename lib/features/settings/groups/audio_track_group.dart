import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../../ui/widgets/controls.dart';
import '../../../ui/widgets/section_body.dart';

/// Audio track (`aid`) selector. Lists the file's audio tracks plus the
/// two synthetic picks mpv understands — `auto` and `no`.
class AudioTrackGroup extends StatelessWidget {
  final Player player;
  const AudioTrackGroup(this.player, {super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MpvTrack>>(
      stream: player.stream.tracks,
      initialData: player.state.tracks,
      builder: (context, tracksSnap) {
        final audioTracks = (tracksSnap.data ?? const <MpvTrack>[])
            .where((t) => t.type == 'audio' && !t.image && !t.albumArt)
            .toList();
        return StreamBuilder<MpvTrack?>(
          stream: player.stream.currentAudioTrack,
          initialData: player.state.currentAudioTrack,
          builder: (context, currentSnap) {
            final current = currentSnap.data;
            final currentId = current?.id;

            final items = <DropdownMenuItem<int>>[
              const DropdownMenuItem(value: -1, child: Text('Auto')),
              const DropdownMenuItem(value: -2, child: Text('No audio')),
              for (final t in audioTracks)
                DropdownMenuItem(
                  value: t.id,
                  child: Text(
                    _trackLabel(t),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ];
            final selected =
                items.any((i) => i.value == currentId) ? currentId : -1;

            return SettingsGroup(
              label: 'Audio track',
              children: [
                DropdownRow<int>(
                  label: 'Track',
                  value: selected,
                  items: items,
                  onChanged: (v) {
                    if (v == null) return;
                    final mode = switch (v) {
                      -1 => Track.auto,
                      -2 => Track.off,
                      _ => Track.id(v),
                    };
                    player.setAudioTrack(mode);
                  },
                ),
                InfoRow(
                  label: 'Active',
                  value: current == null
                      ? 'no audio'
                      : 'aid=${current.id}'
                          '${current.lang != null ? ' (${current.lang})' : ''}',
                ),
              ],
            );
          },
        );
      },
    );
  }

  static String _trackLabel(MpvTrack t) {
    final lang = t.lang != null ? ' [${t.lang}]' : '';
    return t.title?.isNotEmpty == true
        ? '${t.id}: ${t.title}$lang'
        : '${t.id}$lang';
  }
}
