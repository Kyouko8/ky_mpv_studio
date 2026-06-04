import 'package:flutter/material.dart';

import '../tokens.dart';

/// A draggable separator for resizing adjacent panes. The seam is a constant
/// faint hairline; the affordance is a short **squircle grip** centred on it
/// that brightens on hover and lights up [Tokens.accent] while grabbed. The
/// whole length stays grabbable (a generous invisible hit area), but only the
/// centred grip is the visible, illuminating control.
///
/// [axis] is the orientation of the seam: [Axis.horizontal] separates a
/// top/bottom split (drag vertically), [Axis.vertical] separates a left/right
/// split (drag horizontally). [onDelta] reports the drag delta along the
/// resize direction each update.
class ResizeHandle extends StatefulWidget {
  final Axis axis;
  final ValueChanged<double> onDelta;

  /// Width (vertical) / height (horizontal) of the invisible grab area around
  /// the seam, so it's easy to catch with the pointer.
  final double hitThickness;

  const ResizeHandle({
    super.key,
    required this.axis,
    required this.onDelta,
    this.hitThickness = 9,
  });

  @override
  State<ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<ResizeHandle> {
  bool _hovering = false;
  bool _dragging = false;

  static const double _gripLong = 36; // length along the seam
  static const double _gripShort = 5; // thickness across the seam

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.axis == Axis.horizontal;
    final gripColor = _dragging
        ? Tokens.accent
        : (_hovering ? Tokens.fgDim : Tokens.fgFaint);

    final grip = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      width: horizontal ? _gripLong : _gripShort,
      height: horizontal ? _gripShort : _gripLong,
      decoration: ShapeDecoration(
        color: gripColor,
        shape: Tokens.squircle(Tokens.rSm),
      ),
    );

    // Constant seam behind the grip — marks the division, never illuminates.
    final seam = Container(
      width: horizontal ? double.infinity : 1,
      height: horizontal ? 1 : double.infinity,
      color: Tokens.line,
    );

    void setDragging(bool v) => setState(() => _dragging = v);

    return MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeRow
          : SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: horizontal ? (_) => setDragging(true) : null,
        onVerticalDragEnd: horizontal ? (_) => setDragging(false) : null,
        onVerticalDragCancel: horizontal ? () => setDragging(false) : null,
        onVerticalDragUpdate:
            horizontal ? (d) => widget.onDelta(d.delta.dy) : null,
        onHorizontalDragStart: horizontal ? null : (_) => setDragging(true),
        onHorizontalDragEnd: horizontal ? null : (_) => setDragging(false),
        onHorizontalDragCancel: horizontal ? null : () => setDragging(false),
        onHorizontalDragUpdate:
            horizontal ? null : (d) => widget.onDelta(d.delta.dx),
        child: SizedBox(
          width: horizontal ? double.infinity : widget.hitThickness,
          height: horizontal ? widget.hitThickness : double.infinity,
          child: Stack(
            alignment: Alignment.center,
            children: [seam, grip],
          ),
        ),
      ),
    );
  }
}
