import 'package:flutter/material.dart';

import '../../../ui/tokens.dart';

/// A loudness target map for the EBU R128 normaliser — a LUFS scale with
/// the integrated-loudness target pinned by an accent marker, the allowed
/// loudness range (LRA) drawn as a band around it, and the true-peak
/// ceiling marked near 0 dBFS. It visualises where loudnorm is aiming
/// rather than a live reading, so it stays readable and honest when the
/// engine isn't measuring.
class LoudnessGauge extends StatelessWidget {
  final double target; // integrated loudness target, LUFS (e.g. -24)
  final double range; // loudness range, LU
  final double truePeak; // dBTP ceiling (e.g. -2)
  final bool enabled;

  const LoudnessGauge({
    super.key,
    required this.target,
    required this.range,
    required this.truePeak,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      width: double.infinity,
      child: CustomPaint(
        size: Size.infinite,
        painter: _GaugePainter(
          target: target,
          range: range,
          truePeak: truePeak,
          enabled: enabled,
        ),
      ),
    );
  }
}

const double _luMin = -40;
const double _luMax = 0;

class _GaugePainter extends CustomPainter {
  final double target;
  final double range;
  final double truePeak;
  final bool enabled;

  _GaugePainter({
    required this.target,
    required this.range,
    required this.truePeak,
    required this.enabled,
  });

  static const _ticks = [-40, -32, -24, -16, -8, 0];

  @override
  void paint(Canvas canvas, Size size) {
    final accent = enabled ? Tokens.accent : Tokens.fgFaint;
    const padX = 6.0;
    final barTop = 30.0;
    final barH = 22.0;
    final left = padX;
    final right = size.width - padX;
    final w = right - left;
    if (w <= 0) return;

    double x(double lu) =>
        left + ((lu.clamp(_luMin, _luMax) - _luMin) / (_luMax - _luMin)) * w;

    // Scale rail.
    final rail = Rect.fromLTWH(left, barTop, w, barH);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rail, const Radius.circular(4)),
      Paint()..color = Tokens.surface2,
    );

    // LRA band centred on the target.
    final loLu = target - range / 2;
    final hiLu = target + range / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(x(loLu), barTop, x(hiLu), barTop + barH),
        const Radius.circular(4),
      ),
      Paint()..color = accent.withValues(alpha: 0.22),
    );

    // Target marker.
    final tx = x(target);
    canvas.drawRect(
      Rect.fromLTWH(tx - 1, barTop - 4, 2, barH + 8),
      Paint()..color = accent,
    );
    _label(canvas, '${target.round()} LUFS', Offset(tx, barTop - 18),
        accent, center: true);

    // True-peak ceiling.
    final px = x(truePeak);
    canvas.drawRect(
      Rect.fromLTWH(px - 1, barTop - 2, 2, barH + 4),
      Paint()..color = enabled ? Tokens.red : Tokens.fgFaint,
    );
    _label(canvas, 'TP', Offset(px, barTop + barH + 3),
        enabled ? Tokens.red : Tokens.fgFaint,
        center: true);

    // Scale ticks + labels.
    for (final lu in _ticks) {
      final xx = x(lu.toDouble());
      canvas.drawLine(Offset(xx, barTop + barH), Offset(xx, barTop + barH + 3),
          Paint()..color = Tokens.fgFaint);
      _label(canvas, '$lu', Offset(xx, barTop + barH + 14), Tokens.fgFaint,
          center: true);
    }
  }

  void _label(Canvas canvas, String text, Offset at, Color color,
      {bool center = false}) {
    final tp = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: text,
        style: TextStyle(fontFamily: Tokens.mono, fontSize: 9, color: color),
      ),
    )..layout();
    tp.paint(canvas, Offset(center ? at.dx - tp.width / 2 : at.dx, at.dy));
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.target != target ||
      old.range != range ||
      old.truePeak != truePeak ||
      old.enabled != enabled;
}
