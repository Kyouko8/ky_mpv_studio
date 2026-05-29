import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../../state/player_scope.dart';
import '../../../ui/tokens.dart';

/// Flat real-time spectrum drawn as a smooth curve (not bars). Subscribes
/// to `player.stream.fft` and renders one continuous accent line through
/// the perceptual bands, over a faint fill. Subscribing arms the
/// analyzer; it disarms on unmount.
class SpectrumCurve extends StatelessWidget {
  /// Fixed height, or null to fill the parent (e.g. inside an [Expanded]).
  final double? height;
  const SpectrumCurve({super.key, this.height});

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    final paint = StreamBuilder<FftFrame>(
      stream: player.stream.fft,
      builder: (context, snap) => CustomPaint(
        size: Size.infinite,
        painter: _CurvePainter(snap.data?.bands),
      ),
    );
    if (height == null) return SizedBox.expand(child: paint);
    return SizedBox(height: height, width: double.infinity, child: paint);
  }
}

class _CurvePainter extends CustomPainter {
  final Float32List? bands;
  _CurvePainter(this.bands);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final b = bands;
    final n = b?.length ?? 0;

    // Baseline always drawn so the visualizer reads even when silent.
    final baseline = Paint()
      ..color = Tokens.line
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, h - 1), Offset(w, h - 1), baseline);

    if (b == null || n < 2) return;

    double yOf(int i) => h - b[i].clamp(0.0, 1.0) * (h - 2);
    double xOf(int i) => n == 1 ? w / 2 : (i / (n - 1)) * w;

    final top = Path()..moveTo(xOf(0), yOf(0));
    for (var i = 1; i < n; i++) {
      final x0 = xOf(i - 1), y0 = yOf(i - 1);
      final x1 = xOf(i), y1 = yOf(i);
      // Quadratic through the midpoint — smooths the band envelope.
      top.quadraticBezierTo(x0, y0, (x0 + x1) / 2, (y0 + y1) / 2);
    }
    top.lineTo(xOf(n - 1), yOf(n - 1));

    final fill = Path.from(top)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(fill, Paint()..color = Tokens.accentWash);

    canvas.drawPath(
      top,
      Paint()
        ..color = Tokens.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_CurvePainter old) => true;
}
