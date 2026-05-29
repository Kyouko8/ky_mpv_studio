import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../../ui/widgets/controls.dart';
import '../../../ui/widgets/section_body.dart';
import '../../../util/reactive.dart';

/// Streaming behaviour: keep the output alive between tracks and prefetch
/// the next playlist entry while the current one is still playing.
class StreamingGroup extends StatelessWidget {
  final Player player;
  const StreamingGroup(this.player, {super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      label: 'Streaming',
      children: [
        Live<bool>(
          stream: player.stream.audioStreamSilence,
          initial: player.state.audioStreamSilence,
          builder: (context, v) => SwitchRow(
            label: 'Stream silence',
            subtitle: 'Keep the device open by feeding silence between tracks',
            value: v,
            onChanged: (x) => unawaited(player.setAudioStreamSilence(x)),
          ),
        ),
        Live<bool>(
          stream: player.stream.prefetchPlaylist,
          initial: player.state.prefetchPlaylist,
          builder: (context, v) => SwitchRow(
            label: 'Prefetch next track',
            subtitle: 'Open the next playlist entry ahead of time',
            value: v,
            onChanged: player.setPrefetchPlaylist,
          ),
        ),
        StreamBuilder<MpvPrefetchState>(
          stream: player.stream.prefetchState,
          initialData: MpvPrefetchState.idle,
          builder: (context, snap) => InfoRow(
            label: 'Prefetch state',
            value: (snap.data ?? MpvPrefetchState.idle).name,
          ),
        ),
      ],
    );
  }
}
