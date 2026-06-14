import 'package:mpv_audio_kit/mpv_audio_kit.dart';

/// Serialises the *curated* subset of [AudioEffects] that MPV Studio
/// exposes in its rack to/from a plain JSON-able map, for persistence
/// via `AppSettings.effects`.
///
/// Only the modules the UI surfaces are encoded; every other effect in
/// the bundle stays at its disabled default. Decoding an empty / partial
/// map yields defaults for the missing modules, so the format is
/// forward- and backward-compatible.
class EffectsCodec {
  EffectsCodec._();

  static double _d(Object? v, double fallback) =>
      (v as num?)?.toDouble() ?? fallback;
  static bool _b(Object? v, bool fallback) => v as bool? ?? fallback;
  static Map<String, Object?> _m(Object? v) =>
      v is Map ? v.cast<String, Object?>() : const {};

  static Map<String, Object?> encode(AudioEffects e) {
    // 0.4.0: nullable slots — encode the defaults for never-configured ones
    // so presets stay shape-stable.
    final superequalizer = e.superequalizer ?? const SuperequalizerSettings();
    final acompressor = e.acompressor ?? const AcompressorSettings();
    final bass = e.bass ?? const BassSettings();
    final treble = e.treble ?? const TrebleSettings();
    final crossfeed = e.crossfeed ?? const CrossfeedSettings();
    final crystalizer = e.crystalizer ?? const CrystalizerSettings();
    final extrastereo = e.extrastereo ?? const ExtrastereoSettings();
    final asubboost = e.asubboost ?? const AsubboostSettings();
    final loudnorm = e.loudnorm ?? const LoudnormSettings();
    return {
      'eq': {
        'enabled': superequalizer.enabled,
        'params': superequalizer.params,
      },
      'comp': {
        'enabled': acompressor.enabled,
        'threshold': acompressor.threshold,
        'ratio': acompressor.ratio,
        'attack': acompressor.attack,
        'release': acompressor.release,
        'makeup': acompressor.makeup,
        'knee': acompressor.knee,
      },
      'bass': {
        'enabled': bass.enabled,
        'gain': bass.gain,
        'frequency': bass.frequency,
      },
      'treble': {
        'enabled': treble.enabled,
        'gain': treble.gain,
        'frequency': treble.frequency,
      },
      'crossfeed': {
        'enabled': crossfeed.enabled,
        'strength': crossfeed.strength,
        'range': crossfeed.range,
      },
      'crystalizer': {
        'enabled': crystalizer.enabled,
        'i': crystalizer.i,
      },
      'stereo': {
        'enabled': extrastereo.enabled,
        'm': extrastereo.m,
      },
      'subboost': {
        'enabled': asubboost.enabled,
        'boost': asubboost.boost,
        'cutoff': asubboost.cutoff,
        'dry': asubboost.dry,
        'wet': asubboost.wet,
        'feedback': asubboost.feedback,
      },
      'loudnorm': {
        'enabled': loudnorm.enabled,
        'i': loudnorm.i,
        'lra': loudnorm.lra,
        'tp': loudnorm.tp,
        'linear': loudnorm.linear,
      },
    };
  }

  static AudioEffects decode(Map<String, Object?> json) {
    final eq = _m(json['eq']);
    final comp = _m(json['comp']);
    final bass = _m(json['bass']);
    final treble = _m(json['treble']);
    final crossfeed = _m(json['crossfeed']);
    final crystalizer = _m(json['crystalizer']);
    final stereo = _m(json['stereo']);
    final subboost = _m(json['subboost']);
    final loudnorm = _m(json['loudnorm']);

    final eqParams = <String, double>{};
    _m(eq['params']).forEach((k, v) {
      if (v is num) eqParams[k] = v.toDouble();
    });

    return AudioEffects(
      superequalizer: SuperequalizerSettings(
        enabled: _b(eq['enabled'], false),
        params: eqParams,
      ),
      acompressor: AcompressorSettings(
        enabled: _b(comp['enabled'], false),
        threshold: _d(comp['threshold'], 0.125),
        ratio: _d(comp['ratio'], 2),
        attack: _d(comp['attack'], 20),
        release: _d(comp['release'], 250),
        makeup: _d(comp['makeup'], 1),
        knee: _d(comp['knee'], 2.82843),
      ),
      bass: BassSettings(
        enabled: _b(bass['enabled'], false),
        gain: _d(bass['gain'], 0),
        frequency: _d(bass['frequency'], 100),
      ),
      treble: TrebleSettings(
        enabled: _b(treble['enabled'], false),
        gain: _d(treble['gain'], 0),
        frequency: _d(treble['frequency'], 3000),
      ),
      crossfeed: CrossfeedSettings(
        enabled: _b(crossfeed['enabled'], false),
        strength: _d(crossfeed['strength'], 0.2),
        range: _d(crossfeed['range'], 0.5),
      ),
      crystalizer: CrystalizerSettings(
        enabled: _b(crystalizer['enabled'], false),
        i: _d(crystalizer['i'], 2),
      ),
      extrastereo: ExtrastereoSettings(
        enabled: _b(stereo['enabled'], false),
        m: _d(stereo['m'], 2.5),
      ),
      asubboost: AsubboostSettings(
        enabled: _b(subboost['enabled'], false),
        boost: _d(subboost['boost'], 2),
        cutoff: _d(subboost['cutoff'], 100),
        dry: _d(subboost['dry'], 1),
        wet: _d(subboost['wet'], 1),
        feedback: _d(subboost['feedback'], 0.9),
      ),
      loudnorm: LoudnormSettings(
        enabled: _b(loudnorm['enabled'], false),
        i: _d(loudnorm['i'], -24),
        lra: _d(loudnorm['lra'], 7),
        tp: _d(loudnorm['tp'], -2),
        linear: _b(loudnorm['linear'], true),
      ),
    );
  }
}
