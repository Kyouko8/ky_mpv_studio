import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../state/player_scope.dart';
import '../ui/tokens.dart';
import 'desktop_shell.dart';
import 'mobile_shell.dart';
import 'sections.dart';

/// Root chrome. Wraps the routed section bodies (carried by
/// [navigationShell]) in the desktop or mobile shell depending on width, and
/// surfaces engine errors as SnackBars. The bodies themselves live in a
/// single keep-alive IndexedStack built by the router, so player
/// subscriptions (and the Now Playing visualizers) survive section switches.
class AppShell extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({super.key, required this.navigationShell});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  StreamSubscription<MpvPlayerError>? _errorSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_errorSub != null) return;
    // Surface engine errors (failed loads, decode errors) so they're not
    // silent — the full log stays in the Console panel.
    _errorSub = PlayerScope.of(context).stream.error.listen((e) {
      if (!mounted) return;
      // Also echo to the debug console so failures show in `flutter run`.
      debugPrint('mpv error: ${e.message}');
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(e.message, style: const TextStyle(color: Tokens.fg)),
          backgroundColor: Tokens.surface3,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    });
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    super.dispose();
  }

  void _select(Section section) {
    widget.navigationShell.goBranch(
      section.index,
      // Re-tapping the active section pops it back to its initial route.
      initialLocation: section.index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final navigationShell = widget.navigationShell;
    final section = Section.values[navigationShell.currentIndex];

    // A root Scaffold gives ScaffoldMessenger a surface to host SnackBars on
    // (the shells themselves are custom, not Scaffolds).
    return Scaffold(
      backgroundColor: Tokens.bg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= Tokens.desktopBreakpoint;
          if (desktop) {
            return DesktopShell(
              section: section,
              onSelect: _select,
              body: navigationShell,
            );
          }
          return MobileShell(
            section: section,
            onSelect: _select,
            body: navigationShell,
          );
        },
      ),
    );
  }
}
