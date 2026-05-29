import 'package:flutter/material.dart';

/// An [IndexedStack] that fades the newly-selected child in when [index]
/// changes. Unlike an [AnimatedSwitcher], every child stays mounted, so
/// page state (the Console log buffer, scroll positions, live player
/// subscriptions) survives navigation — only the visible layer animates.
class FadeIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Duration duration;

  const FadeIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 200),
  });

  @override
  State<FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<FadeIndexedStack> {
  double _opacity = 1;

  @override
  void didUpdateWidget(FadeIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      // Drop to transparent, then fade the new layer back in next frame.
      _opacity = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _opacity = 1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _opacity,
      duration: widget.duration,
      curve: Curves.easeOut,
      child: IndexedStack(
        index: widget.index,
        sizing: StackFit.expand,
        children: widget.children,
      ),
    );
  }
}
