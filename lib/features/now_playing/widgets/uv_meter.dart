import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../../state/player_scope.dart';
import '../../../ui/tokens.dart';

/// A stereo peak meter fed by `player.stream.pcm`. Two bars (L / R) with
/// pro PPM ballistics — fast attack, slow release, a latched peak-hold
/// marker — and flat green/amber/red zones. Subscribing arms the PCM tap
/// (shared with the spectrum); it disarms on unmount.
///
/// [axis] picks horizontal bars (default) or vertical bars (for a slim
/// meter beside the transport).
class UvMeter extends StatefulWidget {
  final Axis axis;
  const UvMeter({super.key, this.axis = Axis.horizontal});

  @override
  State<UvMeter> createState() => _UvMeterState();
}

class _UvMeterState extends State<UvMeter> with SingleTickerProviderStateMixin {
  static const double _minDb = -60;
  static const double _maxDb = 0;
  static const double _tauAttack = 0.005;
  static const double _tauRelease = 1.7;
  static const int _holdMs = 1500;
  static const double _fallDbPerSec = 12;

  late final Player _player;
  StreamSubscription<PcmFrame>? _sub;
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  double _dbL = -120, _dbR = -120;
  double _holdL = -120, _holdR = -120;
  Duration _holdLAt = Duration.zero, _holdRAt = Duration.zero;
  double _pendingL = -120, _pendingR = -120;

  static double _ampToDb(double a) =>
      a <= 1e-9 ? -120 : 20 * (math.log(a) / math.ln10);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sub != null) return;
    _player = PlayerScope.of(context);
    _ticker = createTicker(_onTick)..start();
    _sub = _player.stream.pcm.listen(_onFrame);
  }

  void _onFrame(PcmFrame f) {
    final s = f.samples;
    final ch = f.channels;
    double pL = 0, pR = 0;
    if (ch <= 1) {
      for (final v in s) {
        final a = v.abs();
        if (a > pL) pL = a;
      }
      pR = pL;
    } else {
      for (var i = 0; i + 1 < s.length; i += ch) {
        final l = s[i].abs();
        if (l > pL) pL = l;
        final r = s[i + 1].abs();
        if (r > pR) pR = r;
      }
    }
    final dbL = _ampToDb(pL), dbR = _ampToDb(pR);
    if (dbL > _pendingL) _pendingL = dbL;
    if (dbR > _pendingR) _pendingR = dbR;
  }

  void _onTick(Duration elapsed) {
    final dtMs = (elapsed - _lastTick).inMicroseconds / 1000.0;
    _lastTick = elapsed;
    if (dtMs <= 0) return;
    final dtS = dtMs / 1000.0;

    final inL = _pendingL, inR = _pendingR;
    _pendingL = -120;
    _pendingR = -120;

    _dbL = _advance(_dbL, inL, dtS);
    _dbR = _advance(_dbR, inR, dtS);

    final r = _hold(_holdL, _holdLAt, _dbL, elapsed, dtS);
    _holdL = r.$1;
    _holdLAt = r.$2;
    final r2 = _hold(_holdR, _holdRAt, _dbR, elapsed, dtS);
    _holdR = r2.$1;
    _holdRAt = r2.$2;

    setState(() {});
  }

  double _advance(double current, double input, double dtS) {
    final tau = input > current ? _tauAttack : _tauRelease;
    final alpha = 1 - math.exp(-dtS / tau);
    return current + alpha * (input - current);
  }

  (double, Duration) _hold(
      double hold, Duration setAt, double db, Duration now, double dtS) {
    if (db > hold) return (db, now);
    if ((now - setAt).inMilliseconds > _holdMs) {
      final next = hold - _fallDbPerSec * dtS;
      return (next < db ? db : next, setAt);
    }
    return (hold, setAt);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final painter = _UvPainter(
      axis: widget.axis,
      dbL: _dbL.clamp(_minDb, _maxDb),
      dbR: _dbR.clamp(_minDb, _maxDb),
      holdL: _holdL.clamp(_minDb, _maxDb),
      holdR: _holdR.clamp(_minDb, _maxDb),
      minDb: _minDb,
      maxDb: _maxDb,
    );
    if (widget.axis == Axis.vertical) {
      return SizedBox(
        width: 40,
        child: CustomPaint(size: Size.infinite, painter: painter),
      );
    }
    return SizedBox(
      height: 30,
      child: CustomPaint(size: Size.infinite, painter: painter),
    );
  }
}

class _UvPainter extends CustomPainter {
  final Axis axis;
  final double dbL, dbR, holdL, holdR, minDb, maxDb;
  static const double _amberDb = -18;
  static const double _redDb = -6;

  _UvPainter({
    required this.axis,
    required this.dbL,
    required this.dbR,
    required this.holdL,
    required this.holdR,
    required this.minDb,
    required this.maxDb,
  });

  double _t(double db) => ((db - minDb) / (maxDb - minDb)).clamp(0.0, 1.0);

  Color _holdColor(double db) => db >= _redDb
      ? Tokens.red
      : db >= _amberDb
          ? Tokens.amber
          : Tokens.green;

  void _label(Canvas canvas, String s, Offset topLeft) {
    final tp = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: s,
        style: const TextStyle(
          fontFamily: Tokens.mono,
          fontSize: 10,
          color: Tokens.fgFaint,
        ),
      ),
    )..layout();
    tp.paint(canvas, topLeft);
  }

  void _barH(Canvas canvas, Rect r, double db, double hold) {
    final rrect = RRect.fromRectAndRadius(r, const Radius.circular(3));
    canvas.drawRRect(rrect, Paint()..color = Tokens.surface2);
    canvas.save();
    canvas.clipRRect(rrect);
    final litW = _t(db) * r.width;
    final amberX = _t(_amberDb) * r.width;
    final redX = _t(_redDb) * r.width;
    void seg(double x0, double x1, Color c) {
      final a = x0.clamp(0.0, litW);
      final b = x1.clamp(0.0, litW);
      if (b > a) {
        canvas.drawRect(Rect.fromLTRB(r.left + a, r.top, r.left + b, r.bottom),
            Paint()..color = c);
      }
    }

    seg(0, amberX, Tokens.green);
    seg(amberX, redX, Tokens.amber);
    seg(redX, r.width, Tokens.red);
    canvas.restore();
    if (hold > minDb) {
      final hx = r.left + _t(hold) * r.width;
      canvas.drawLine(
          Offset(hx, r.top),
          Offset(hx, r.bottom),
          Paint()
            ..color = _holdColor(hold)
            ..strokeWidth = 1.5);
    }
  }

  void _barV(Canvas canvas, Rect r, double db, double hold) {
    final rrect = RRect.fromRectAndRadius(r, const Radius.circular(3));
    canvas.drawRRect(rrect, Paint()..color = Tokens.surface2);
    canvas.save();
    canvas.clipRRect(rrect);
    final litTopY = r.bottom - _t(db) * r.height;
    final amberY = r.bottom - _t(_amberDb) * r.height;
    final redY = r.bottom - _t(_redDb) * r.height;
    void seg(double yTop, double yBottom, Color c) {
      final a = math.max(yTop, litTopY);
      final b = yBottom;
      if (b > a) {
        canvas.drawRect(
            Rect.fromLTRB(r.left, a, r.right, b), Paint()..color = c);
      }
    }

    seg(amberY, r.bottom, Tokens.green);
    seg(redY, amberY, Tokens.amber);
    seg(r.top, redY, Tokens.red);
    canvas.restore();
    if (hold > minDb) {
      final hy = r.bottom - _t(hold) * r.height;
      canvas.drawLine(
          Offset(r.left, hy),
          Offset(r.right, hy),
          Paint()
            ..color = _holdColor(hold)
            ..strokeWidth = 1.5);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0) return;
    if (axis == Axis.horizontal) {
      const labelW = 14.0, barH = 10.0, gap = 4.0;
      final barLeft = labelW + 6;
      final barW = w - barLeft;
      if (barW <= 0) return;
      final topY = (h - (barH * 2 + gap)) / 2;
      final lRect = Rect.fromLTWH(barLeft, topY, barW, barH);
      final rRect = Rect.fromLTWH(barLeft, topY + barH + gap, barW, barH);
      _label(canvas, 'L', Offset(0, lRect.center.dy - 6));
      _label(canvas, 'R', Offset(0, rRect.center.dy - 6));
      _barH(canvas, lRect, dbL, holdL);
      _barH(canvas, rRect, dbR, holdR);
    } else {
      const labelH = 13.0, barW = 11.0, gap = 6.0;
      final barsH = h - labelH;
      final totalW = barW * 2 + gap;
      final left = (w - totalW) / 2;
      final lRect = Rect.fromLTWH(left, 0, barW, barsH);
      final rRect = Rect.fromLTWH(left + barW + gap, 0, barW, barsH);
      _barV(canvas, lRect, dbL, holdL);
      _barV(canvas, rRect, dbR, holdR);
      _label(canvas, 'L', Offset(lRect.center.dx - 3, barsH + 1));
      _label(canvas, 'R', Offset(rRect.center.dx - 3, barsH + 1));
    }
  }

  @override
  bool shouldRepaint(_UvPainter old) =>
      old.axis != axis ||
      old.dbL != dbL ||
      old.dbR != dbR ||
      old.holdL != holdL ||
      old.holdR != holdR;
}
