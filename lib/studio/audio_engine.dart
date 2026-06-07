import 'package:flutter/foundation.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../features/console/console_log.dart';
import 'app_settings.dart';

/// Builds the single [Player] and brings it to a ready state: publishes the
/// OS media session, restores the user's persisted engine configuration and
/// DSP rack, and starts snapshotting future changes back to disk. Also
/// returns an always-on [ConsoleLog] that captures the engine log from boot
/// so the Console shows the full backlog whenever it's first opened.
///
/// The [Player] stays the single runtime source of truth; [settings] only
/// seeds it on launch ([AppSettings.applyTo]) and records changes
/// ([AppSettings.attach]).
Future<({Player player, ConsoleLog consoleLog})> startAudioEngine(
  AppSettings settings,
) async {
  // Build-time configuration is assembled from the persisted knobs (resume,
  // watch-later dir, force-seekable, HLS bitrate, downmix normalization,
  // demuxer cache dir). It is read once here — the Settings UI records changes
  // that take effect on the next launch.
  final player = Player(configuration: settings.playerConfiguration);

  // Start log capture immediately — before any other setup emits log lines —
  // so nothing is lost before the Console is first opened.
  final consoleLog = ConsoleLog()..attach(player);

  // Native OS media session (Control Center / SMTC / MPRIS / lockscreen).
  // The advertised controls are user-customisable on the Session settings
  // page; `null` when the user disabled the session entirely.
  await player.setMediaSession(settings.mediaSession);

  // The library auto-applies inbound OS commands to the player; this
  // subscription is the interception/analytics hook — observe every
  // lockscreen / headset / Bluetooth / Siri command as it lands.
  player.stream.mediaSessionCommands.listen(
    (command) => debugPrint('MediaSession command from OS: $command'),
  );

  // Re-apply the user's last engine configuration and DSP rack, then
  // start snapshotting future changes back to disk.
  await settings.applyTo(player);
  await player.setAudioEffects(settings.effects);
  settings.attach(player);

  return (player: player, consoleLog: consoleLog);
}
