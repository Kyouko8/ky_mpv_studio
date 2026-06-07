import 'dart:async';
import 'dart:ui' show AppExitResponse;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import 'shell/router.dart';
import 'studio/mpv_studio.dart';
import 'studio/player_scope.dart';
import 'ui/theme.dart';

/// Root widget. Renders the running [MpvStudio]: exposes it to the tree via
/// [PlayerScope] and shuts it down on process exit.
class MpvStudioApp extends StatefulWidget {
  final MpvStudio studio;
  const MpvStudioApp({super.key, required this.studio});

  @override
  State<MpvStudioApp> createState() => _MpvStudioAppState();
}

class _MpvStudioAppState extends State<MpvStudioApp> {
  late final _router = createAppRouter();

  // Dock-Quit / ⌘Q call NSApplication terminate: without unwinding the widget
  // tree, so State.dispose never runs before the engine tears down.
  // onExitRequested is the hook that does fire there: shut the player down
  // (bounded so it can't itself stall quit), then allow the exit.
  late final AppLifecycleListener _exitGate;
  Future<void>? _inFlight;

  @override
  void initState() {
    super.initState();
    _exitGate = AppLifecycleListener(
      onExitRequested: _onExitRequested,
      onDetach: () => unawaited(_teardown()),
    );
  }

  // Single cached teardown future so repeat lifecycle signals all await the
  // same shutdown; bounded so a wedged shutdown can never itself block quit.
  Future<void> _teardown() => _inFlight ??= widget.studio
      .shutdown()
      .timeout(const Duration(seconds: 3), onTimeout: () {});

  Future<AppExitResponse> _onExitRequested() async {
    await _teardown();
    return AppExitResponse.exit;
  }

  @override
  void dispose() {
    _exitGate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // PlayerScope sits ABOVE MaterialApp so the routed pages (which live
    // under MaterialApp's Navigator) can still read the studio's services.
    return PlayerScope(
      studio: widget.studio,
      child: MaterialApp.router(
        title: 'MPV Studio',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        // Let the mouse click-and-drag to scroll on desktop, like touch does —
        // Flutter leaves the mouse out of the default drag devices.
        scrollBehavior: const _DragScrollBehavior(),
        routerConfig: _router,
      ),
    );
  }
}

/// Adds the mouse (and the rest) to the scroll drag devices so lists scroll on
/// click-drag on desktop, not just with the wheel/trackpad.
class _DragScrollBehavior extends MaterialScrollBehavior {
  const _DragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.unknown,
      };
}
