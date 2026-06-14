import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'app_settings.dart';

/// EBU R128 volume normalization, driven by the engine's offline loudness
/// scan (`player.stream.loudness`): every loaded track is measured moments
/// after load — before the audio starts — and the measured integrated
/// loudness steers `volume-gain` toward the user's target, streaming-service
/// style. Works on any local or direct-play file, ReplayGain tags or not.
///
/// The gain rides mpv's `volume-gain` (a dB stage separate from the user
/// volume slider), so enabling/disabling normalization never touches the
/// user's volume setting. Tracks the scan cannot measure up-front (adaptive
/// or live streams report `unavailable`) play at unity gain.
///
/// Owned by [MpvStudio]; the Settings toggle and the Now Playing badge both
/// observe this notifier.
class LoudnessNormalizer extends ChangeNotifier {
  LoudnessNormalizer(this._player, this._settings);

  final Player _player;
  final AppSettings _settings;

  StreamSubscription<LoudnessScan?>? _sub;
  LoudnessScan? _lastScan;
  double _appliedGainDb = 0;
  bool _enabled = false;

  /// Whether normalization is active.
  bool get enabled => _enabled;

  /// The most recent scan result for the loaded track (`null` until the
  /// first result lands, and again across a track change).
  LoudnessScan? get lastScan => _lastScan;

  /// The gain currently applied by the normalizer, in dB (0 when off,
  /// when no scan is available yet, or for unmeasurable sources).
  double get appliedGainDb => _appliedGainDb;

  /// Target integrated loudness, LUFS. -18 is the ReplayGain 2.0
  /// reference; streaming services typically sit between -14 and -16.
  double get targetLufs => _settings.loudnessTargetLufs;

  /// Restores the persisted state on launch.
  void restore() {
    if (_settings.loudnessNormalization) setEnabled(true);
  }

  /// Turns normalization on/off and records the choice.
  void setEnabled(bool on) {
    if (on == _enabled) return;
    _enabled = on;
    _settings.recordLoudnessNormalization(on);
    if (on) {
      // The subscription itself arms the engine's scan (listener-gated).
      _sub = _player.stream.loudness.listen(_onScan);
    } else {
      _sub?.cancel();
      _sub = null;
      _lastScan = null;
      _apply(0);
    }
    notifyListeners();
  }

  /// Changes the target and re-applies it to the current track.
  void setTargetLufs(double lufs) {
    _settings.recordLoudnessTargetLufs(lufs);
    if (_lastScan?.state == LoudnessScanState.ready) _onScan(_lastScan);
    notifyListeners();
  }

  void _onScan(LoudnessScan? scan) {
    _lastScan = scan;
    if (scan?.state == LoudnessScanState.ready) {
      // Clamp generously: a hot-mastered track needs at most a cut of a
      // dozen dB; a very quiet one should not be boosted into clipping.
      _apply((targetLufs - scan!.integrated!).clamp(-24.0, 24.0));
    } else {
      // Track change (`null`) or unmeasurable source: unity gain.
      _apply(0);
    }
    notifyListeners();
  }

  void _apply(double gainDb) {
    _appliedGainDb = gainDb;
    unawaited(_player.setVolumeGain(gainDb));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
