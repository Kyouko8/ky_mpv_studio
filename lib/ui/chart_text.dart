import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Paints a short monospace label onto a [Canvas] — the single text helper
/// shared by every chart and meter painter (response curve, knee plot,
/// goniometer, gauges, VU meter, …), replacing the per-painter copies.
///
/// [at] is the anchor: the top-left by default, the top-centre when
/// [center] is set (x only), and the dead-centre when [middle] is also set
/// (x and y) — the schematic diagrams use the latter to place node labels.
void paintChartLabel(
  Canvas canvas,
  String text,
  Offset at,
  Color color, {
  double fontSize = 9,
  bool center = false,
  bool middle = false,
}) {
  final tp = TextPainter(
    textDirection: TextDirection.ltr,
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: Tokens.mono,
        fontSize: fontSize,
        color: color,
        height: 1.0,
      ),
    ),
  )..layout();
  tp.paint(
    canvas,
    Offset(
      center ? at.dx - tp.width / 2 : at.dx,
      middle ? at.dy - tp.height / 2 : at.dy,
    ),
  );
}
