import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../../ui/tokens.dart';
import '../../../ui/widgets/controls.dart';
import '../../../ui/widgets/section_body.dart';
import '../../../util/duration_format.dart';

enum _CountChoice { off, finite, infinite }

/// mpv's A-B loop: when playback crosses point B it seeks back to A and
/// replays the segment. Points are stamped from the live position.
class AbLoopGroup extends StatelessWidget {
  final Player player;
  const AbLoopGroup(this.player, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          label: 'Loop boundaries',
          children: [
            StreamBuilder<Duration?>(
              stream: player.stream.abLoopA,
              initialData: player.state.abLoopA,
              builder: (context, snap) => _PointRow(
                label: 'Point A',
                value: snap.data,
                onSetHere: () => player.setAbLoopA(player.state.position),
                onClear:
                    snap.data == null ? null : () => player.setAbLoopA(null),
              ),
            ),
            StreamBuilder<Duration?>(
              stream: player.stream.abLoopB,
              initialData: player.state.abLoopB,
              builder: (context, snap) => _PointRow(
                label: 'Point B',
                value: snap.data,
                onSetHere: () => player.setAbLoopB(player.state.position),
                onClear:
                    snap.data == null ? null : () => player.setAbLoopB(null),
              ),
            ),
          ],
        ),
        SettingsGroup(
          label: 'Repetition',
          children: [
            StreamBuilder<int?>(
              stream: player.stream.abLoopCount,
              initialData: player.state.abLoopCount,
              builder: (context, snap) {
                final count = snap.data;
                final choice = switch (count) {
                  null => _CountChoice.infinite,
                  0 => _CountChoice.off,
                  _ => _CountChoice.finite,
                };
                return SettingTile(
                  title: 'Loop count',
                  below: SegmentedControl<_CountChoice>(
                    selected: choice,
                    onSelect: (c) => player.setAbLoopCount(switch (c) {
                      _CountChoice.off => 0,
                      _CountChoice.finite => 5,
                      _CountChoice.infinite => null,
                    }),
                    options: const [
                      SegmentOption(_CountChoice.off, 'Off'),
                      SegmentOption(_CountChoice.finite, '5×'),
                      SegmentOption(_CountChoice.infinite, 'Loop'),
                    ],
                  ),
                );
              },
            ),
            StreamBuilder<int?>(
              stream: player.stream.remainingAbLoops,
              initialData: player.state.remainingAbLoops,
              builder: (context, snap) => InfoRow(
                label: 'Remaining loops',
                value: snap.data == null ? '∞' : '${snap.data}',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PointRow extends StatelessWidget {
  final String label;
  final Duration? value;
  final VoidCallback onSetHere;
  final VoidCallback? onClear;
  const _PointRow({
    required this.label,
    required this.value,
    required this.onSetHere,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Tokens.s4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: Tokens.body)),
          Text(
            value == null ? 'off' : formatDuration(value!),
            style: Tokens.numeric.copyWith(
              color: value == null ? Tokens.fgFaint : Tokens.accent,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_location_alt_rounded),
            color: Tokens.fgDim,
            onPressed: onSetHere,
            tooltip: 'Set to current position',
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            color: Tokens.fgDim,
            onPressed: onClear,
            tooltip: 'Clear',
          ),
        ],
      ),
    );
  }
}
