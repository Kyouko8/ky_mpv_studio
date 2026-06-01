import 'package:flutter/widgets.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../features/stream/media_server.dart';
import 'app_settings.dart';

/// Exposes the single [Player] and the running app's services (the
/// persisted [AppSettings] and the connected media [servers]) to the whole
/// widget tree. MPV Studio is a single-player app, so one of each lives at
/// the root and everything reads them from here.
///
/// The media servers live here (not inside the Stream page) so their
/// connections — and the playback reporting that depends on them — survive
/// navigating away from that page.
class PlayerScope extends InheritedWidget {
  final Player player;
  final AppSettings settings;

  /// The connected media servers, keyed by kind. The Stream page reads its
  /// Jellyfin / Plex instances from here instead of creating its own.
  final Map<ServerKind, MediaServer> servers;

  const PlayerScope({
    super.key,
    required this.player,
    required this.settings,
    required this.servers,
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

  /// The connected server of the given [kind].
  static MediaServer serverOf(BuildContext context, ServerKind kind) =>
      _scope(context).servers[kind]!;

  @override
  bool updateShouldNotify(PlayerScope oldWidget) =>
      oldWidget.player != player ||
      oldWidget.settings != settings ||
      oldWidget.servers != servers;
}
