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
    return {
      'eq': {
        'enabled': e.superequalizer.enabled,
        'params': e.superequalizer.params,
      },
      'comp': {
        'enabled': e.acompressor.enabled,
        'threshold': e.acompressor.threshold,
        'ratio': e.acompressor.ratio,
        'attack': e.acompressor.attack,
        'release': e.acompressor.release,
        'makeup': e.acompressor.makeup,
        'knee': e.acompressor.knee,
      },
      'bass': {
        'enabled': e.bass.enabled,
        'gain': e.bass.gain,
        'frequency': e.bass.frequency,
      },
      'treble': {
        'enabled': e.treble.enabled,
        'gain': e.treble.gain,
        'frequency': e.treble.frequency,
      },
      'crossfeed': {
        'enabled': e.crossfeed.enabled,
        'strength': e.crossfeed.strength,
        'range': e.crossfeed.range,
      },
      'crystalizer': {
        'enabled': e.crystalizer.enabled,
        'i': e.crystalizer.i,
      },
      'stereo': {
        'enabled': e.extrastereo.enabled,
        'm': e.extrastereo.m,
      },
      'subboost': {
        'enabled': e.asubboost.enabled,
        'boost': e.asubboost.boost,
        'cutoff': e.asubboost.cutoff,
        'dry': e.asubboost.dry,
        'wet': e.asubboost.wet,
        'feedback': e.asubboost.feedback,
      },
      'loudnorm': {
        'enabled': e.loudnorm.enabled,
        'i': e.loudnorm.i,
        'lra': e.loudnorm.lra,
        'tp': e.loudnorm.tp,
        'linear': e.loudnorm.linear,
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
