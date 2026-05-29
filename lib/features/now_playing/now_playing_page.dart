import 'package:flutter/material.dart';

import '../../ui/tokens.dart';
import '../../ui/widgets/resize_handle.dart';
import 'widgets/cover_art.dart';
import 'widgets/spectrum_curve.dart';
import 'widgets/track_info.dart';
import 'widgets/transport_controls.dart';
import 'widgets/uv_meter.dart';
import 'widgets/volume_control.dart';
import 'widgets/waveform_meter.dart';

/// The home surface, laid out like a DAW: a full-bleed waveform meter
/// (Reaper-style ruler + playhead) on top — resizable — then a control
/// block (centred title over the transport, artwork left, vertical VU
/// meters right, volume) and finally the curved spectrum filling all the
/// remaining space, anchored to the bottom edge.
class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key});

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  double _meterHeight = 200;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final maxMeter = (c.maxHeight - 320).clamp(120.0, 600.0);
        final meterH = _meterHeight.clamp(120.0, maxMeter);
        // Meter and the controls area touch flush; the resize line is
        // overlaid on the seam, so there are no gap pixels between them.
        return Stack(
          children: [
            Column(
              children: [
                SizedBox(
                  height: meterH,
                  child: const ColoredBox(
                    color: Tokens.surface,
                    child: WaveformMeter(),
                  ),
                ),
                const Expanded(child: _BottomArea()),
              ],
            ),
            Positioned(
              top: meterH - 3.5,
              left: 0,
              right: 0,
              height: 7,
              child: ResizeHandle(
                axis: Axis.horizontal,
                onDelta: (dy) => setState(
                  () => _meterHeight = (meterH + dy).clamp(120.0, maxMeter),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BottomArea extends StatelessWidget {
  const _BottomArea();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Control block — full width, no lateral cap.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Tokens.s20,
            Tokens.s16,
            Tokens.s20,
            Tokens.s12,
          ),
          child: LayoutBuilder(
            builder: (context, c) {
              final coverSize =
                  (c.maxWidth * 0.14).clamp(120.0, 168.0).toDouble();
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Artwork with the track info beneath it.
                      SizedBox(
                        width: coverSize + 48,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CoverArtView(size: coverSize),
                            const SizedBox(height: Tokens.s12),
                            const TrackInfo(),
                          ],
                        ),
                      ),
                      const SizedBox(width: Tokens.s32),
                      const Expanded(child: TransportControls()),
                      const SizedBox(width: Tokens.s32),
                      SizedBox(
                        width: 40,
                        height: coverSize,
                        child: const VolumeControl(axis: Axis.vertical),
                      ),
                      const SizedBox(width: Tokens.s16),
                      SizedBox(
                        width: 44,
                        height: coverSize,
                        child: const UvMeter(axis: Axis.vertical),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
        // Visualizer fills the rest, full-bleed, anchored to the bottom.
        const Expanded(child: SpectrumCurve()),
      ],
    );
  }
}
