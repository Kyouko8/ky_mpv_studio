import 'package:flutter/widgets.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'app_settings.dart';

/// Exposes the single [Player] and the running app's services (the
/// persisted [AppSettings]) to the whole widget tree. MPV Studio is a
/// single-player app, so one of each lives at the root and everything
/// reads them from here.
class PlayerScope extends InheritedWidget {
  final Player player;
  final AppSettings settings;

  const PlayerScope({
    super.key,
    required this.player,
    required this.settings,
    required super.child,
  });

  static PlayerScope _scope(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PlayerScope>();
    assert(scope != null, 'PlayerScope.of() called with no PlayerScope above');
    return scope!;
  }

  static Player of(BuildContext context) => _scope(context).player;

  static AppSettings settingsOf(BuildContext context) =>
      _scope(context).settings;

  @override
  bool updateShouldNotify(PlayerScope oldWidget) =>
      oldWidget.player != player || oldWidget.settings != settings;
}
