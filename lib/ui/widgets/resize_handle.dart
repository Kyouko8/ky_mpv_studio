import 'package:flutter/material.dart';

import '../tokens.dart';

/// A thin draggable separator line for resizing adjacent panes. There's
/// no grip glyph — the separation line *itself* is the affordance: it
/// brightens on hover and is draggable at any point along its length.
///
/// [axis] is the orientation of the line: [Axis.horizontal] separates a
/// top/bottom split (drag vertically), [Axis.vertical] separates a
/// left/right split (drag horizontally). [onDelta] reports the drag
/// delta along the resize direction each update.
class ResizeHandle extends StatefulWidget {
  final Axis axis;
  final ValueChanged<double> onDelta;

  /// Width (vertical) / height (horizontal) of the invisible grab area
  /// around the line, so it's easy to catch with the pointer.
  final double hitThickness;

  const ResizeHandle({
    super.key,
    required this.axis,
    required this.onDelta,
    this.hitThickness = 7,
  });

  @override
  State<ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<ResizeHandle> {
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.axis == Axis.horizontal;
    final color = _active ? Tokens.accent : Tokens.line2;
    final lineW = _active ? 1.5 : 1.0;

    final line = Center(
      child: Container(
        width: horizontal ? double.infinity : lineW,
        height: horizontal ? lineW : double.infinity,
        color: color,
      ),
    );

    return MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeRow
          : SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _active = true),
      onExit: (_) => setState(() => _active = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate:
            horizontal ? (d) => widget.onDelta(d.delta.dy) : null,
        onHorizontalDragUpdate:
            horizontal ? null : (d) => widget.onDelta(d.delta.dx),
        child: SizedBox(
          width: horizontal ? double.infinity : widget.hitThickness,
          height: horizontal ? widget.hitThickness : double.infinity,
          child: line,
        ),
      ),
    );
  }
}
