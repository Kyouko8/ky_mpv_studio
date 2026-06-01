import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../../state/player_scope.dart';
import '../../../ui/tokens.dart';
import '../../../util/duration_format.dart';
import '../../../util/reactive.dart';

/// A Reaper-style tape meter: a time ruler with values on top, the track
/// waveform below it, and a fixed-zoom view the user pans with a
/// horizontal scrollbar. The playhead advances with playback through the
/// view (it does NOT auto-follow — the view only moves when you scroll).
///
/// Fills its parent's height, so the surrounding layout can make it
/// resizable.
class WaveformMeter extends StatefulWidget {
  /// Seconds of audio visible across the full width.
  final double windowSeconds;

  const WaveformMeter({super.key, this.windowSeconds = 30});

  /// Height of the time-ruler strip at the top.
  static const double rulerHeight = 22;

  /// Height of the bottom scrollbar strip.
  static const double scrollbarHeight = 14;

  @override
  State<WaveformMeter> createState() => _WaveformMeterState();
}

class _WaveformMeterState extends State<WaveformMeter>
    with SingleTickerProviderStateMixin, StreamListenerState<WaveformMeter> {
  late final Player _player;
  late final Ticker _ticker;
  final _sw = Stopwatch();

  Duration _anchor = Duration.zero;
  Duration _dur = Duration.zero;
  double _rate = 1;

  /// Seconds visible across the full width — the horizontal zoom level.
  /// Seeded from the widget, then driven by the zoom controls.
  late double _windowSeconds = widget.windowSeconds;

  /// Bounds for the zoom range.
  static const double _minWindow = 5;
  bool _playWhenReady = false;
  bool _seekable = false;

  /// The track's min/max envelope from `stream.waveform`. The engine
  /// fills this transparently: a full envelope up-front for local files,
  /// or one that grows during playback for network sources (segmented /
  /// transcode / live). Either way the meter just renders what it gets.
  WaveformData? _wave;

  bool _dragging = false;
  Duration _dragPos = Duration.zero;

  /// Mouse hover X over the waveform (preview cursor); null when away.
  double? _hoverX;

  /// First visible second of the view. Driven only by the scrollbar.
  double _viewStart = 0;

  @override
  void onSubscribe() {
    _player = PlayerScope.of(context);
    final s = _player.state;
    _anchor = s.position;
    _dur = s.duration;
    _rate = s.rate;
    _playWhenReady = s.playWhenReady;
    _seekable = s.seekable;

    _ticker = createTicker((_) {
      if (mounted) setState(() {});
    });
    if (_playWhenReady) {
      _sw.start();
      _ticker.start();
    }

    listen(_player.stream.position, (p) {
      _anchor = p;
      _sw
        ..reset()
        ..start();
      if (mounted) setState(() {});
    });
    listen(_player.stream.duration, (d) {
      if (!mounted) return;
      setState(() {
        if (d != _dur) _viewStart = 0; // new track → reset view to start
        _dur = d;
      });
    });
    listen(_player.stream.rate, (r) {
      if (mounted) setState(() => _rate = r);
    });
    listen(_player.stream.seekable, (v) {
      if (mounted) setState(() => _seekable = v);
    });
    listen(_player.stream.waveform, (w) {
      if (mounted) setState(() => _wave = w);
    });
    listen(_player.stream.playWhenReady, (v) {
      _playWhenReady = v;
      if (v) {
        _sw
          ..reset()
          ..start();
        if (!_ticker.isActive) _ticker.start();
      } else {
        _anchor = _livePos();
        _sw.stop();
        if (_ticker.isActive) _ticker.stop();
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Smooth playhead position, interpolated between position emits.
  Duration _livePos() {
    if (!_playWhenReady || !_sw.isRunning) return _anchor;
    final micros =
        _anchor.inMicroseconds + (_sw.elapsedMicroseconds * _rate).round();
    var d = Duration(microseconds: micros);
    if (d < Duration.zero) d = Duration.zero;
    if (_dur > Duration.zero && d > _dur) d = _dur;
    return d;
  }

  double get _durSecs => _dur.inMicroseconds / 1e6;

  /// Timeline length for the ruler + scroll range. Falls back to a
  /// 5-minute placeholder when nothing is loaded, so the meter is always
  /// populated with a usable timeline.
  static const double _placeholderSecs = 300;
  double get _timelineSecs => _durSecs > 0 ? _durSecs : _placeholderSecs;
  double get _maxStart =>
      (_timelineSecs - _windowSeconds).clamp(0, _timelineSecs);
  bool get _hasScroll => _maxStart > 0;
  double get _visibleSecs => _hasScroll ? _windowSeconds : _timelineSecs;

  /// Multiplies the zoom level (factor < 1 zooms in), keeping the current
  /// view centre fixed and the view start within range.
  void _zoomBy(double factor) {
    final center = _viewStart + _visibleSecs / 2;
    setState(() {
      _windowSeconds =
          (_windowSeconds * factor).clamp(_minWindow, _timelineSecs);
      _viewStart = (center - _visibleSecs / 2).clamp(0, _maxStart);
    });
  }

  void _seekToX(double localX, double width) {
    final pxPerSec = width / _visibleSecs;
    final t = _viewStart + localX / pxPerSec;
    final micros = (t * 1e6).round().clamp(0, _dur.inMicroseconds);
    final target = Duration(microseconds: micros);
    setState(() {
      _dragPos = target;
      _anchor = target;
    });
    _player.seek(target);
  }

  void _setViewStart(double v) {
    setState(() => _viewStart = v.clamp(0, _maxStart));
  }

  @override
  Widget build(BuildContext context) {
    final pos = _dragging ? _dragPos : _livePos();
    final canSeek = _seekable && _dur > Duration.zero;
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final w = c.maxWidth;
                    return MouseRegion(
                      cursor: canSeek
                          ? SystemMouseCursors.precise
                          : MouseCursor.defer,
                      onHover: (e) {
                        if (mounted) {
                          setState(() => _hoverX = e.localPosition.dx);
                        }
                      },
                      onExit: (_) {
                        if (mounted) setState(() => _hoverX = null);
                      },
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: canSeek
                            ? (d) => _seekToX(d.localPosition.dx, w)
                            : null,
                        onHorizontalDragStart: canSeek
                            ? (d) {
                                setState(() => _dragging = true);
                                _seekToX(d.localPosition.dx, w);
                              }
                            : null,
                        onHorizontalDragUpdate: canSeek
                            ? (d) => _seekToX(d.localPosition.dx, w)
                            : null,
                        onHorizontalDragEnd: canSeek
                            ? (_) => setState(() => _dragging = false)
                            : null,
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _MeterPainter(
                            wave: _wave,
                            pos: pos,
                            dur: _dur,
                            timelineSecs: _timelineSecs,
                            viewStart: _viewStart,
                            visibleSecs: _visibleSecs,
                            rulerHeight: WaveformMeter.rulerHeight,
                            hoverX: (canSeek && !_dragging) ? _hoverX : null,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Horizontal zoom for the waveform / playhead timeline.
              Positioned(
                top: WaveformMeter.rulerHeight + 4,
                right: 6,
                child: _ZoomControls(
                  canZoomIn: _windowSeconds > _minWindow,
                  canZoomOut: _windowSeconds < _timelineSecs,
                  onZoomIn: () => _zoomBy(0.6),
                  onZoomOut: () => _zoomBy(1 / 0.6),
                ),
              ),
            ],
          ),
        ),
        _HScrollBar(
          enabled: _hasScroll,
          viewStart: _viewStart,
          windowSeconds: _windowSeconds,
          maxStart: _maxStart,
          durSecs: _timelineSecs,
          onChanged: _setViewStart,
        ),
      ],
    );
  }
}

/// A compact zoom pill (out · in) overlaid on the waveform meter.
class _ZoomControls extends StatelessWidget {
  final bool canZoomIn;
  final bool canZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  const _ZoomControls({
    required this.canZoomIn,
    required this.canZoomOut,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: ShapeDecoration(
        color: Tokens.surface2,
        shape: Tokens.squircle(Tokens.rMd),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomBtn(
            icon: Icons.remove_rounded,
            tooltip: 'Zoom out',
            enabled: canZoomOut,
            onTap: onZoomOut,
          ),
          _ZoomBtn(
            icon: Icons.add_rounded,
            tooltip: 'Zoom in',
            enabled: canZoomIn,
            onTap: onZoomIn,
          ),
        ],
      ),
    );
  }
}

class _ZoomBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  const _ZoomBtn({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: enabled ? onTap : null,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(
              icon,
              size: 16,
              color: enabled ? Tokens.fgDim : Tokens.fgFaint,
            ),
          ),
        ),
      ),
    );
  }
}

class _HScrollBar extends StatelessWidget {
  final bool enabled;
  final double viewStart;
  final double windowSeconds;
  final double maxStart;
  final double durSecs;
  final ValueChanged<double> onChanged;

  const _HScrollBar({
    required this.enabled,
    required this.viewStart,
    required this.windowSeconds,
    required this.maxStart,
    required this.durSecs,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: WaveformMeter.scrollbarHeight,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final frac =
              (durSecs <= 0 ? 1.0 : (windowSeconds / durSecs)).clamp(0.06, 1.0);
          final thumbW = (w * frac).clamp(28.0, w);
          final avail = w - thumbW;
          final thumbX = maxStart > 0 ? (viewStart / maxStart) * avail : 0.0;

          void setFromX(double x) {
            if (!enabled || avail <= 0) return;
            final tx = (x - thumbW / 2).clamp(0.0, avail);
            onChanged((tx / avail) * maxStart);
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => setFromX(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => setFromX(d.localPosition.dx),
            // Flush, square strip — a recessed track colour so it reads as a
            // control, not blank space below the waveform, with a hairline
            // above it separating it from the waveform.
            child: Container(
              decoration: const BoxDecoration(
                color: Tokens.surface2,
                border: Border(top: BorderSide(color: Tokens.line, width: 1)),
              ),
              child: Stack(
                children: [
                  // Thumb — a square pane spanning the full strip height.
                  Positioned(
                    left: thumbX,
                    top: 0,
                    bottom: 0,
                    width: thumbW,
                    child: Container(
                      decoration: BoxDecoration(
                        color: enabled ? Tokens.surface3 : Tokens.surface2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MeterPainter extends CustomPainter {
  final WaveformData? wave;
  final Duration pos;
  final Duration dur;
  final double timelineSecs;
  final double viewStart;
  final double visibleSecs;
  final double rulerHeight;
  final double? hoverX;

  _MeterPainter({
    required this.wave,
    required this.pos,
    required this.dur,
    required this.timelineSecs,
    required this.viewStart,
    required this.visibleSecs,
    required this.rulerHeight,
    required this.hoverX,
  });

  static double _niceStep(double visibleSecs) {
    const steps = <double>[1, 2, 5, 10, 15, 20, 30, 60, 120, 300, 600];
    final target = visibleSecs / 5;
    for (final s in steps) {
      if (s >= target) return s;
    }
    return steps.last;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final durSecs = dur.inMicroseconds / 1e6;
    final posSecs = pos.inMicroseconds / 1e6;
    final pxPerSec = w / visibleSecs;
    final tLeft = viewStart;
    final tRight = viewStart + visibleSecs;
    final playheadX = (posSecs - tLeft) * pxPerSec;

    final waveTop = rulerHeight;
    final waveH = h - rulerHeight;
    final centreY = waveTop + waveH / 2;

    // ── Ruler ────────────────────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, rulerHeight),
      Paint()..color = Tokens.surface2,
    );
    canvas.drawLine(
      Offset(0, rulerHeight - 0.5),
      Offset(w, rulerHeight - 0.5),
      Paint()
        ..color = Tokens.line
        ..strokeWidth = 1,
    );
    if (timelineSecs > 0) {
      final tickPaint = Paint()
        ..color = Tokens.fgFaint
        ..strokeWidth = 1;
      final step = _niceStep(visibleSecs);
      final tp = TextPainter(textDirection: TextDirection.ltr);
      var t = (tLeft / step).floorToDouble() * step;
      for (; t <= tRight; t += step) {
        if (t < 0 || t > timelineSecs) continue;
        final x = (t - tLeft) * pxPerSec;
        canvas.drawLine(
          Offset(x, rulerHeight - 5),
          Offset(x, rulerHeight),
          tickPaint,
        );
        tp.text = TextSpan(
          text: formatDuration(Duration(microseconds: (t * 1e6).round())),
          style: const TextStyle(
            fontFamily: Tokens.mono,
            fontSize: 9.5,
            color: Tokens.fgDim,
          ),
        );
        tp.layout();
        var dx = x - tp.width / 2;
        if (dx < 1) dx = 1;
        if (dx + tp.width > w - 1) dx = w - 1 - tp.width;
        tp.paint(canvas, Offset(dx, 2));
      }
    }

    // ── Waveform ─────────────────────────────────────────────────────
    canvas.drawLine(
      Offset(0, centreY),
      Offset(w, centreY),
      Paint()
        ..color = Tokens.line
        ..strokeWidth = 1,
    );
    final played = Paint()..color = Tokens.accent;
    final upcoming = Paint()..color = Tokens.line2;
    // Bins not yet covered (progressive envelope ahead of the playhead, or
    // a region skipped by a seek) — drawn as a faint baseline, not as a
    // real flat-zero spike, using the per-bin `filled` flags.
    final unloaded = Paint()..color = Tokens.line;
    final wv = wave;
    if (wv != null && wv.bins > 0 && durSecs > 0) {
      final bins = wv.bins;
      final filled = wv.filled;
      final binSecs = wv.duration.inMicroseconds / 1e6 / bins;
      var i = (tLeft / binSecs).floor();
      if (i < 0) i = 0;
      final maxHalf = waveH / 2 - 3;
      final barW = (pxPerSec * binSecs * 0.7).clamp(0.6, 6.0);
      for (; i < bins; i++) {
        final t = (i + 0.5) * binSecs;
        if (t > tRight) break;
        final x = (t - tLeft) * pxPerSec;
        if (x < -barW || x > w + barW) continue;
        final covered = i >= filled.length || filled[i] != 0;
        final lo = wv.min[i].clamp(-1.0, 1.0);
        final hi = wv.max[i].clamp(-1.0, 1.0);
        final top = centreY - hi * maxHalf;
        final bottomRaw = centreY - lo * maxHalf;
        final bottom = bottomRaw < top + 1 ? top + 1 : bottomRaw;
        canvas.drawRect(
          Rect.fromLTRB(x, top, x + barW, bottom),
          !covered ? unloaded : (t <= posSecs ? played : upcoming),
        );
      }
    }

    // ── Hover preview cursor ─────────────────────────────────────────
    final hx = hoverX;
    if (hx != null && hx >= 0 && hx <= w) {
      canvas.drawRect(
        Rect.fromLTWH(hx - 0.5, rulerHeight, 1, h - rulerHeight),
        Paint()..color = Tokens.fg.withValues(alpha: 0.28),
      );
      final t = (tLeft + hx / pxPerSec).clamp(0.0, timelineSecs);
      final tp = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          text: formatDuration(Duration(microseconds: (t * 1e6).round())),
          style: const TextStyle(
            fontFamily: Tokens.mono,
            fontSize: 9.5,
            color: Tokens.fg,
          ),
        ),
      )..layout();
      var bx = hx + 4;
      if (bx + tp.width + 6 > w) bx = hx - 4 - tp.width - 6;
      final bubble =
          Rect.fromLTWH(bx, rulerHeight + 3, tp.width + 6, tp.height + 3);
      canvas.drawRRect(
        RRect.fromRectAndRadius(bubble, const Radius.circular(3)),
        Paint()..color = Tokens.surface3,
      );
      tp.paint(canvas, Offset(bx + 3, rulerHeight + 4));
    }

    // ── Reaper playhead: one continuous line through the ruler, capped
    //    by a downward triangle pip (no gap). ──────────────────────────
    if (playheadX >= 0 && playheadX <= w) {
      final ph = Paint()..color = Tokens.accent;
      canvas.drawRect(Rect.fromLTWH(playheadX - 0.75, 0, 1.5, h), ph);
      final pip = Path()
        ..moveTo(playheadX - 5, 0)
        ..lineTo(playheadX + 5, 0)
        ..lineTo(playheadX, 9)
        ..close();
      canvas.drawPath(pip, ph);
    }
  }

  @override
  bool shouldRepaint(_MeterPainter old) =>
      old.wave != wave ||
      old.pos != pos ||
      old.dur != dur ||
      old.timelineSecs != timelineSecs ||
      old.viewStart != viewStart ||
      old.visibleSecs != visibleSecs ||
      old.rulerHeight != rulerHeight ||
      old.hoverX != hoverX;
}

