import 'package:flutter/material.dart';

import '../../../state/player_scope.dart';
import '../../../ui/tokens.dart';
import '../../../util/reactive.dart';

/// Mute toggle + volume slider, bound to `player.stream.volume` and
/// `player.stream.mute`. Range tracks `volumeMax`. [axis] picks a
/// horizontal slider (default) or a vertical one (slim, fills its
/// parent's height — for a column beside the meters).
class VolumeControl extends StatelessWidget {
  final Axis axis;
  const VolumeControl({super.key, this.axis = Axis.horizontal});

  IconData _icon(bool muted, double vol, double max) => muted
      ? Icons.volume_off_rounded
      : vol <= 0
          ? Icons.volume_mute_rounded
          : vol < max * 0.5
              ? Icons.volume_down_rounded
              : Icons.volume_up_rounded;

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    return Live<bool>(
      stream: player.stream.mute,
      initial: player.state.mute,
      builder: (context, muted) => Live<double>(
        stream: player.stream.volumeMax,
        initial: player.state.volumeMax,
        builder: (context, vmax) => Live<double>(
          stream: player.stream.volume,
          initial: player.state.volume,
          builder: (context, vol) {
            final max = vmax < 100 ? 100.0 : vmax;
            final value = vol.clamp(0.0, max);
            final muteButton = IconButton(
              onPressed: () => player.setMute(!muted),
              icon: Icon(_icon(muted, vol, max), size: 20),
              color: muted ? Tokens.fgFaint : Tokens.fgDim,
              splashRadius: 18,
            );
            if (axis == Axis.vertical) {
              return Column(
                children: [
                  Text(vol.round().toString(), style: Tokens.numeric),
                  Expanded(
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: Slider(
                        value: value,
                        max: max,
                        onChanged: (v) => player.setVolume(v),
                      ),
                    ),
                  ),
                  muteButton,
                ],
              );
            }
            return Row(
              children: [
                muteButton,
                Expanded(
                  child: Slider(
                    value: value,
                    max: max,
                    onChanged: (v) => player.setVolume(v),
                  ),
                ),
                SizedBox(
                  width: 38,
                  child: Text(
                    vol.round().toString(),
                    style: Tokens.numeric,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
