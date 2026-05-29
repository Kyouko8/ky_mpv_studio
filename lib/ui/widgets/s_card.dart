import 'package:flutter/material.dart';
import '../tokens.dart';

/// Flat surface container. No shadow, no elevation — just a filled
/// rounded rect with an optional hairline border. The base building
/// block for panels, rack items, settings rows.
class SCard extends StatelessWidget {
  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final bool border;
  final bool accentBorder;
  final VoidCallback? onTap;

  const SCard({
    super.key,
    required this.child,
    this.color,
    this.padding,
    this.radius = Tokens.rMd,
    this.border = false,
    this.accentBorder = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Tokens.surface,
        borderRadius: shape,
        border: accentBorder
            ? Border.all(color: Tokens.accentDim, width: 1)
            : border
                ? Border.all(color: Tokens.line, width: 1)
                : null,
      ),
      child: child,
    );
    if (onTap != null) {
      content = Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: shape,
          child: content,
        ),
      );
    }
    return content;
  }
}
