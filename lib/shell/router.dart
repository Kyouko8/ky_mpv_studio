import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/console/console_page.dart';
import '../features/effects/effects_page.dart';
import '../features/now_playing/now_playing_page.dart';
import '../features/queue/queue_page.dart';
import '../features/settings/settings_page.dart';
import '../features/stream/stream_page.dart';
import 'app_shell.dart';
import 'sections.dart';

/// Builds the app router. One [StatefulShellBranch] per [Section]; every
/// branch stays mounted inside a keep-alive [IndexedStack], so player
/// subscriptions and the Now Playing visualizers survive section switches.
/// The custom [StatefulShellRoute.navigatorContainerBuilder] keeps that
/// instant, flash-free switch instead of a page transition.
GoRouter createAppRouter() {
  return GoRouter(
    initialLocation: Section.nowPlaying.path,
    routes: [
      StatefulShellRoute(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        navigatorContainerBuilder: (context, navigationShell, children) =>
            IndexedStack(
          index: navigationShell.currentIndex,
          sizing: StackFit.expand,
          children: children,
        ),
        branches: [
          for (final section in Section.values)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: section.path,
                  builder: (context, state) => _pageFor(section),
                ),
              ],
            ),
        ],
      ),
    ],
  );
}

Widget _pageFor(Section section) {
  switch (section) {
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
