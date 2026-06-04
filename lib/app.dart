import 'dart:async';
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

  @override
  void dispose() {
    unawaited(widget.studio.shutdown());
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
        routerConfig: _router,
      ),
    );
  }
}
