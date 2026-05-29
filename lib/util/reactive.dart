import 'package:flutter/widgets.dart';

/// Pairs a `player.stream.X` with its `player.state.X` seed in one
/// widget so call sites never write `?? default` fallbacks. The single
/// reactive primitive used across MPV Studio.
class Live<T> extends StatelessWidget {
  final Stream<T> stream;
  final T initial;
  final Widget Function(BuildContext context, T value) builder;

  const Live({
    super.key,
    required this.stream,
    required this.initial,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<T>(
      stream: stream,
      initialData: initial,
      builder: (context, snap) => builder(context, snap.data ?? initial),
    );
  }
}
