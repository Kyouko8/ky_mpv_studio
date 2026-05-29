import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../../ui/widgets/controls.dart';
import '../../../ui/widgets/section_body.dart';
import '../../../util/reactive.dart';

/// Demuxer cache tuning and live status. Sizes are exposed in MiB; the
/// engine stores raw bytes.
class DemuxerGroup extends StatelessWidget {
  final Player player;
  const DemuxerGroup(this.player, {super.key});

  static const _mib = 1024 * 1024;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          label: 'Demuxer performance',
          children: [
            Live<int>(
              stream: player.stream.demuxerMaxBytes,
              initial: player.state.demuxerMaxBytes,
              builder: (context, v) => SliderRow(
                label: 'Max cache size',
                value: v / _mib,
                min: 1,
                max: 2048,
                resetTo: 150,
                format: (x) => '${x.round()} MiB',
                onChanged: (x) => player.setDemuxerMaxBytes((x * _mib).round()),
              ),
            ),
            Live<int>(
              stream: player.stream.demuxerReadaheadSecs,
              initial: player.state.demuxerReadaheadSecs,
              builder: (context, v) => SliderRow(
                label: 'Readahead',
                value: v.toDouble(),
                min: 0,
                max: 600,
                resetTo: 1,
                format: (x) => '${x.round()} s',
                onChanged: (x) => player.setDemuxerReadaheadSecs(x.round()),
              ),
            ),
            Live<int>(
              stream: player.stream.demuxerMaxBackBytes,
              initial: player.state.demuxerMaxBackBytes,
              builder: (context, v) => SliderRow(
                label: 'Seekback pool',
                value: v / _mib,
                min: 0,
                max: 1024,
                resetTo: 50,
                format: (x) => '${x.round()} MiB',
                onChanged: (x) =>
                    player.setDemuxerMaxBackBytes((x * _mib).round()),
              ),
            ),
          ],
        ),
        SettingsGroup(
          label: 'Demuxer status',
          children: [
            Live<String>(
              stream: player.stream.currentDemuxer,
              initial: player.state.currentDemuxer,
              builder: (context, v) =>
                  InfoRow(label: 'Current demuxer', value: v.isEmpty ? '—' : v),
            ),
            Live<Duration>(
              stream: player.stream.bufferDuration,
              initial: player.state.bufferDuration,
              builder: (context, v) => InfoRow(
                label: 'Cache ahead',
                value: '${(v.inMicroseconds / 1e6).toStringAsFixed(2)} s',
              ),
            ),
            StreamBuilder<bool>(
              stream: player.stream.demuxerIdle,
              initialData: true,
              builder: (context, snap) => InfoRow(
                label: 'Idle',
                value: (snap.data ?? true) ? 'yes' : 'no',
              ),
            ),
            Live<bool>(
              stream: player.stream.demuxerViaNetwork,
              initial: player.state.demuxerViaNetwork,
              builder: (context, v) =>
                  InfoRow(label: 'Via network', value: v ? 'yes' : 'no'),
            ),
            Live<Duration>(
              stream: player.stream.demuxerStartTime,
              initial: player.state.demuxerStartTime,
              builder: (context, v) => InfoRow(
                label: 'Start time',
                value: '${(v.inMicroseconds / 1e6).toStringAsFixed(3)} s',
              ),
            ),
          ],
        ),
      ],
    );
  }
}
