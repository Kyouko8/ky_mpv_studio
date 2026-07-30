import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../features/console/console_log.dart';
import '../features/stream/favorites_controller.dart';
import '../features/stream/media_server.dart';
import '../features/stream/playback_reporter.dart';
import '../features/stream/plex_transcode_session_manager.dart';
import 'app_settings.dart';
import 'audio_engine.dart';
import 'library_manager.dart';
import 'loudness_normalizer.dart';
import 'queue_manager.dart';
import 'server_manager.dart';

/// The running MPV Studio: every long-lived service the player app needs,
/// owned in one place. [launch] turns the app on (settings → audio engine →
/// media servers) and [shutdown] turns it off; the widget tree only ever sees
/// a ready [MpvStudio] handed down through [PlayerScope].
///
/// This is the single home for the app's runtime. Adding a service means
/// adding a field here and a line to [launch] — nothing else in the boot
/// chain changes.
class MpvStudio {
  /// The single audio engine. Stays the one runtime source of truth — every
  /// surface reads its live streams and writes through its setters.
  final Player player;

  /// Persisted engine configuration + DSP rack. Seeds the player on launch
  /// and records changes back to disk.
  final AppSettings settings;

  /// Multi-instance quick-access server manager.
  final ServerManager serverManager;

  /// Connected media servers (Jellyfin / Plex), keyed by kind.
  Map<ServerKind, MediaServer> get servers {
    final map = <ServerKind, MediaServer>{};
    for (final instance in serverManager.instances) {
      if (!map.containsKey(instance.kind)) {
        map[instance.kind] = serverManager.getOrCreateServer(instance);
      }
    }
    // Fallback/placeholder servers for legacy code compatibility
    if (!map.containsKey(ServerKind.jellyfin)) {
      map[ServerKind.jellyfin] = serverManager.getOrCreateServer(ServerInstance(
        id: 'jellyfin-fallback-id',
        name: 'Jellyfin',
        kind: ServerKind.jellyfin,
        host: '',
      ));
    }
    if (!map.containsKey(ServerKind.plex)) {
      map[ServerKind.plex] = serverManager.getOrCreateServer(ServerInstance(
        id: 'plex-fallback-id',
        name: 'Plex',
        kind: ServerKind.plex,
        host: '',
      ));
    }
    return map;
  }

  /// Shared favourite (like) state for server tracks — the song-list star and
  /// the OS lock-screen like both read/write this.
  final FavoritesController favorites;

  /// Always-on engine-log buffer, capturing from boot so the Console is never
  /// empty on first open.
  final ConsoleLog consoleLog;

  /// EBU R128 volume normalization, fed by the engine's offline loudness
  /// scan. The Settings toggle and the Now Playing badge observe this.
  final LoudnessNormalizer normalizer;

  /// Manages multiple playlists (queues) and active/inactive tracks.
  final QueueManager queueManager;

  /// Manages the local device audio library.
  final LibraryManager libraryManager;

  const MpvStudio._({
    required this.player,
    required this.settings,
    required this.serverManager,
    required this.favorites,
    required this.consoleLog,
    required this.normalizer,
    required this.queueManager,
    required this.libraryManager,
  });

  /// Powers the app on. Restores persisted settings, starts the audio engine
  /// (with the OS media session and DSP rack), wires Plex's transcode hook,
  /// and connects the media servers + playback reporting. Everything is ready
  /// by the time this returns, so the first frame renders live state.
  static Future<MpvStudio> launch() async {
    // Persisted settings, restored before the first frame.
    final settings = await AppSettings.load();

    final engine = await startAudioEngine(settings);

    // Resolve device name and device ID before initializing servers
    await Future.wait([
      resolveDeviceName().then(setMediaDeviceName),
      resolveDeviceId(),
    ]);

    final serverManager = ServerManager();
    await serverManager.load();

    // Wire up unified loading hook!
    await wireMediaServersHook(engine.player, serverManager);

    // Plex hands mpv marker URLs that must be resolved in an on_load hook.
    await wirePlexTranscodeHook(engine.player);

    final favorites = FavoritesController(serverManager);

    // Report playback (start / progress / stop) of server tracks back to their
    // server, and bridge the OS lock-screen "like" to favourites. Lives for the
    // whole session.
    final reporter = PlaybackReporter(engine.player, serverManager, favorites);
    reporter.start();

    // Volume normalization rides the engine's offline loudness scan; the
    // subscription itself arms the scan, so an off toggle costs nothing.
    final normalizer = LoudnessNormalizer(engine.player, settings)..restore();

    final queueManager = QueueManager(engine.player, settings);
    await queueManager.load();

    final libraryManager = LibraryManager();
    queueManager.libraryManager = libraryManager;

    return MpvStudio._(
      player: engine.player,
      settings: settings,
      serverManager: serverManager,
      favorites: favorites,
      consoleLog: engine.consoleLog,
      normalizer: normalizer,
      queueManager: queueManager,
      libraryManager: libraryManager,
    );
  }

  /// Powers the app off — released on process exit. Stops persistence and the
  /// log buffer, then tears down the audio engine last.
  Future<void> shutdown() async {
    normalizer.dispose();
    await settings.dispose();
    await consoleLog.dispose();
    await queueManager.save();
    libraryManager.dispose();
    await player.dispose();
  }
}
