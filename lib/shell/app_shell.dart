import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../features/console/console_page.dart';
import '../features/effects/effects_page.dart';
import '../features/now_playing/now_playing_page.dart';
import '../features/queue/queue_page.dart';
import '../features/settings/settings_page.dart';
import '../features/stream/stream_page.dart';
import '../state/player_scope.dart';
import '../ui/tokens.dart';
import '../ui/widgets/fade_indexed_stack.dart';
import 'desktop_shell.dart';
import 'mobile_shell.dart';
import 'sections.dart';

/// Root chrome. Owns the current [Section] and console visibility, then
/// hands off to the desktop or mobile shell depending on width. Section
/// bodies live in a single [IndexedStack] so player subscriptions (and
/// the Now Playing visualizers) survive section switches.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  Section _section = Section.nowPlaying;
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

  Widget _bodyFor(Section s) {
    switch (s) {
      case Section.nowPlaying:
        return const NowPlayingPage();
      case Section.queue:
        return const QueuePage();
      case Section.effects:
        return const EffectsPage();
      case Section.stream:
        return const StreamPage();
      case Section.settings:
        return const SettingsPage();
      case Section.console:
        return const ConsolePage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = FadeIndexedStack(
      index: _section.index,
      children: [for (final s in Section.values) _bodyFor(s)],
    );

    // A root Scaffold gives ScaffoldMessenger a surface to host
    // SnackBars on (the shells themselves are custom, not Scaffolds).
    return Scaffold(
      backgroundColor: Tokens.bg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= Tokens.desktopBreakpoint;
          if (desktop) {
            return DesktopShell(
              section: _section,
              onSelect: (s) => setState(() => _section = s),
              body: body,
            );
          }
          return MobileShell(
            section: _section,
            onSelect: (s) => setState(() => _section = s),
            body: body,
          );
        },
      ),
    );
  }
}
