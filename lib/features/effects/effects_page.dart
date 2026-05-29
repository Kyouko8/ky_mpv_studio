import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../state/player_scope.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/module_card.dart';
import '../../ui/widgets/section_body.dart';
import '../../generated/catalog.dart';
import 'widgets/equalizer.dart';

/// The DSP rack. A curated set of typed `AudioEffects` stages, each in a
/// [ModuleCard] with an enable switch and sliders. The whole bundle is
/// the single writer of mpv's `af` chain — changes are pushed atomically
/// via `setAudioEffects` and mirrored into [AppSettings] for persistence.
///
/// Slider drags mutate a local draft for smooth motion and commit to the
/// engine on release; toggles and resets commit immediately.
class EffectsPage extends StatefulWidget {
  const EffectsPage({super.key});

  @override
  State<EffectsPage> createState() => _EffectsPageState();
}

class _EffectsPageState extends State<EffectsPage> {
  late final Player _player;
  late AudioEffects _fx;
  bool _editing = false;
  StreamSubscription<AudioEffects>? _sub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sub != null) return;
    _player = PlayerScope.of(context);
    _fx = _player.state.audioEffects;
    _sub = _player.stream.audioEffects.listen((v) {
      // Resync from the engine only when the user isn't mid-drag, so an
      // optimistic local draft is never clobbered.
      if (!_editing && mounted && v != _fx) setState(() => _fx = v);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Updates the local draft only (no engine write) — used during drags.
  void _setLocal(AudioEffects next) {
    setState(() {
      _fx = next;
      _editing = true;
    });
  }

  /// Pushes the current draft to the engine. Persistence happens
  /// automatically via the [AppSettings] observer on `stream.audioEffects`.
  void _commit() {
    _editing = false;
    _player.setAudioEffects(_fx);
  }

  /// Sets a new bundle and commits immediately — toggles, resets.
  void _commitNow(AudioEffects next) {
    setState(() {
      _fx = next;
      _editing = false;
    });
    _player.setAudioEffects(next);
  }

  SliderRowSpec _spec(
    String label,
    double value,
    double min,
    double max,
    AudioEffects Function(double v) apply, {
    String Function(double v)? format,
  }) =>
      SliderRowSpec(
        label: label,
        value: value,
        min: min,
        max: max,
        format: format,
        onChanged: (v) => _setLocal(apply(v)),
        onChangeEnd: _commit,
      );

  @override
  Widget build(BuildContext context) {
    final eq = _fx.superequalizer;
    final comp = _fx.acompressor;
    final bass = _fx.bass;
    final treble = _fx.treble;
    final cf = _fx.crossfeed;
    final cr = _fx.crystalizer;
    final st = _fx.extrastereo;
    final sb = _fx.asubboost;
    final ln = _fx.loudnorm;

    final bandsDb = <String, double>{
      for (final b in kEqBands) b.key: eqLinearToDb(eq.params[b.key] ?? 1.0),
    };

    return SectionBody(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(Tokens.s4, 0, Tokens.s4, Tokens.s8),
          child: Text('FEATURED', style: Tokens.caption),
        ),
        // ---- 18-band graphic EQ -------------------------------------
        ModuleCard(
          title: 'Equalizer',
          subtitle: '18-band graphic',
          icon: Icons.equalizer_rounded,
          enabled: eq.enabled,
          initiallyExpanded: true,
          onEnabledChanged: (v) =>
              _commitNow(_fx.copyWith(superequalizer: eq.copyWith(enabled: v))),
          onReset: () => _commitNow(_fx.copyWith(
            superequalizer: SuperequalizerSettings(
              enabled: eq.enabled,
              params: const {},
            ),
          )),
          child: Padding(
            padding: const EdgeInsets.only(top: Tokens.s4),
            child: Equalizer(
              bandsDb: bandsDb,
              enabled: eq.enabled,
              onChanged: (key, db) {
                final params = Map<String, double>.from(eq.params);
                if (db.abs() < 0.05) {
                  params.remove(key);
                } else {
                  params[key] = eqDbToLinear(db);
                }
                _setLocal(_fx.copyWith(
                  superequalizer: eq.copyWith(params: params),
                ));
              },
              onChangeEnd: _commit,
            ),
          ),
        ),

        // ---- Compressor ---------------------------------------------
        _module(
          title: 'Compressor',
          subtitle: 'Dynamic range control',
          icon: Icons.compress_rounded,
          enabled: comp.enabled,
          onEnabled: (v) =>
              _commitNow(_fx.copyWith(acompressor: comp.copyWith(enabled: v))),
          onReset: () => _commitNow(_fx.copyWith(
              acompressor: AcompressorSettings(enabled: comp.enabled))),
          specs: [
            _spec(
                'Threshold',
                eqLinearToDb(comp.threshold),
                -60,
                0,
                (v) => _fx.copyWith(
                    acompressor: comp.copyWith(
                        threshold: eqDbToLinear(v).clamp(0.000977, 1.0))),
                format: (v) => '${v.round()} dB'),
            _spec('Ratio', comp.ratio, 1, 20,
                (v) => _fx.copyWith(acompressor: comp.copyWith(ratio: v)),
                format: (v) => '${v.toStringAsFixed(1)}:1'),
            _spec('Attack', comp.attack, 1, 200,
                (v) => _fx.copyWith(acompressor: comp.copyWith(attack: v)),
                format: (v) => '${v.round()} ms'),
            _spec('Release', comp.release, 20, 2000,
                (v) => _fx.copyWith(acompressor: comp.copyWith(release: v)),
                format: (v) => '${v.round()} ms'),
            _spec(
                'Make-up gain',
                eqLinearToDb(comp.makeup),
                0,
                24,
                (v) => _fx.copyWith(
                    acompressor: comp.copyWith(
                        makeup: eqDbToLinear(v).clamp(1.0, 64.0))),
                format: (v) => '+${v.round()} dB'),
          ],
        ),

        // ---- Bass / Treble shelves ----------------------------------
        _module(
          title: 'Bass',
          subtitle: 'Low shelf',
          icon: Icons.graphic_eq_rounded,
          enabled: bass.enabled,
          onEnabled: (v) =>
              _commitNow(_fx.copyWith(bass: bass.copyWith(enabled: v))),
          onReset: () => _commitNow(
              _fx.copyWith(bass: BassSettings(enabled: bass.enabled))),
          specs: [
            _spec('Gain', bass.gain, -24, 24,
                (v) => _fx.copyWith(bass: bass.copyWith(gain: v)),
                format: (v) => '${v.toStringAsFixed(1)} dB'),
            _spec('Frequency', bass.frequency, 20, 500,
                (v) => _fx.copyWith(bass: bass.copyWith(frequency: v)),
                format: (v) => '${v.round()} Hz'),
          ],
        ),
        _module(
          title: 'Treble',
          subtitle: 'High shelf',
          icon: Icons.graphic_eq_rounded,
          enabled: treble.enabled,
          onEnabled: (v) =>
              _commitNow(_fx.copyWith(treble: treble.copyWith(enabled: v))),
          onReset: () => _commitNow(
              _fx.copyWith(treble: TrebleSettings(enabled: treble.enabled))),
          specs: [
            _spec('Gain', treble.gain, -24, 24,
                (v) => _fx.copyWith(treble: treble.copyWith(gain: v)),
                format: (v) => '${v.toStringAsFixed(1)} dB'),
            _spec('Frequency', treble.frequency, 1000, 16000,
                (v) => _fx.copyWith(treble: treble.copyWith(frequency: v)),
                format: (v) => '${(v / 1000).toStringAsFixed(1)}k Hz'),
          ],
        ),

        // ---- Sub boost ----------------------------------------------
        _module(
          title: 'Sub boost',
          subtitle: 'Synthesised low end',
          icon: Icons.surround_sound_rounded,
          enabled: sb.enabled,
          onEnabled: (v) =>
              _commitNow(_fx.copyWith(asubboost: sb.copyWith(enabled: v))),
          onReset: () => _commitNow(
              _fx.copyWith(asubboost: AsubboostSettings(enabled: sb.enabled))),
          specs: [
            _spec('Boost', sb.boost, 1, 12,
                (v) => _fx.copyWith(asubboost: sb.copyWith(boost: v)),
                format: (v) => v.toStringAsFixed(1)),
            _spec('Cutoff', sb.cutoff, 50, 900,
                (v) => _fx.copyWith(asubboost: sb.copyWith(cutoff: v)),
                format: (v) => '${v.round()} Hz'),
            _spec('Wet', sb.wet, 0, 1,
                (v) => _fx.copyWith(asubboost: sb.copyWith(wet: v)),
                format: _pct),
            _spec('Dry', sb.dry, 0, 1,
                (v) => _fx.copyWith(asubboost: sb.copyWith(dry: v)),
                format: _pct),
          ],
        ),

        // ---- Stereo width -------------------------------------------
        _module(
          title: 'Stereo width',
          subtitle: 'Widen the stereo image',
          icon: Icons.panorama_horizontal_rounded,
          enabled: st.enabled,
          onEnabled: (v) =>
              _commitNow(_fx.copyWith(extrastereo: st.copyWith(enabled: v))),
          onReset: () => _commitNow(_fx.copyWith(
              extrastereo: ExtrastereoSettings(enabled: st.enabled))),
          specs: [
            _spec('Amount', st.m, 0, 8,
                (v) => _fx.copyWith(extrastereo: st.copyWith(m: v)),
                format: (v) => v.toStringAsFixed(1)),
          ],
        ),

        // ---- Crossfeed ----------------------------------------------
        _module(
          title: 'Crossfeed',
          subtitle: 'Headphone channel blend',
          icon: Icons.headphones_rounded,
          enabled: cf.enabled,
          onEnabled: (v) =>
              _commitNow(_fx.copyWith(crossfeed: cf.copyWith(enabled: v))),
          onReset: () => _commitNow(
              _fx.copyWith(crossfeed: CrossfeedSettings(enabled: cf.enabled))),
          specs: [
            _spec('Strength', cf.strength, 0, 1,
                (v) => _fx.copyWith(crossfeed: cf.copyWith(strength: v)),
                format: _pct),
            _spec('Range', cf.range, 0, 1,
                (v) => _fx.copyWith(crossfeed: cf.copyWith(range: v)),
                format: _pct),
          ],
        ),

        // ---- Crystalizer --------------------------------------------
        _module(
          title: 'Clarity',
          subtitle: 'Crystalizer expander',
          icon: Icons.auto_awesome_rounded,
          enabled: cr.enabled,
          onEnabled: (v) =>
              _commitNow(_fx.copyWith(crystalizer: cr.copyWith(enabled: v))),
          onReset: () => _commitNow(_fx.copyWith(
              crystalizer: CrystalizerSettings(enabled: cr.enabled))),
          specs: [
            _spec('Intensity', cr.i, -10, 10,
                (v) => _fx.copyWith(crystalizer: cr.copyWith(i: v)),
                format: (v) => v.toStringAsFixed(1)),
          ],
        ),

        // ---- Loudness normalization ---------------------------------
        _module(
          title: 'Loudness',
          subtitle: 'EBU R128 normalization',
          icon: Icons.volume_up_rounded,
          enabled: ln.enabled,
          onEnabled: (v) =>
              _commitNow(_fx.copyWith(loudnorm: ln.copyWith(enabled: v))),
          onReset: () => _commitNow(
              _fx.copyWith(loudnorm: LoudnormSettings(enabled: ln.enabled))),
          specs: [
            _spec('Target', ln.i, -70, -5,
                (v) => _fx.copyWith(loudnorm: ln.copyWith(i: v)),
                format: (v) => '${v.round()} LUFS'),
            _spec('Range', ln.lra, 1, 50,
                (v) => _fx.copyWith(loudnorm: ln.copyWith(lra: v)),
                format: (v) => '${v.round()} LU'),
            _spec('True peak', ln.tp, -9, 0,
                (v) => _fx.copyWith(loudnorm: ln.copyWith(tp: v)),
                format: (v) => '${v.toStringAsFixed(1)} dB'),
          ],
        ),

        // ---- Full catalog (generated) -------------------------------
        const SizedBox(height: Tokens.s8),
        const Padding(
          padding: EdgeInsets.fromLTRB(Tokens.s4, 0, Tokens.s4, Tokens.s8),
          child: Text('ALL EFFECTS', style: Tokens.caption),
        ),
        for (final cat in kCatalogCategories) _CatalogTile(category: cat),
      ],
    );
  }

  static String _pct(double v) => '${(v * 100).round()}%';

  Widget _module({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool enabled,
    required ValueChanged<bool> onEnabled,
    required VoidCallback onReset,
    required List<SliderRowSpec> specs,
  }) {
    return ModuleCard(
      title: title,
      subtitle: subtitle,
      icon: icon,
      enabled: enabled,
      onEnabledChanged: onEnabled,
      onReset: onReset,
      child: Column(
        children: [
          for (var i = 0; i < specs.length; i++) ...[
            if (i > 0) const SizedBox(height: Tokens.s4),
            specs[i].build(enabled),
          ],
        ],
      ),
    );
  }
}

/// Bundles a [SliderRow]'s parameters so the page can declare a module's
/// controls as a flat list and let [ModuleCard] render them.
class SliderRowSpec {
  final String label;
  final double value;
  final double min;
  final double max;
  final String Function(double v)? format;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;

  const SliderRowSpec({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onChangeEnd,
    this.format,
  });

  Widget build(bool enabled) => SliderRow(
        label: label,
        value: value,
        min: min,
        max: max,
        format: format,
        enabled: enabled,
        onChanged: onChanged,
        onChangeEnd: (_) => onChangeEnd(),
      );
}

/// A tile in the "All effects" index. Opens a full page listing every
/// filter in [category] as a typed card.
class _CatalogTile extends StatelessWidget {
  final CatalogCategory category;
  const _CatalogTile({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: Tokens.s8),
      decoration: ShapeDecoration(
        color: Tokens.surface,
        shape: Tokens.squircle(
          Tokens.rMd,
          side: const BorderSide(color: Tokens.line, width: 1),
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: Tokens.squircle(Tokens.rMd),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _CatalogCategoryScreen(category: category),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Tokens.s16,
              vertical: Tokens.s12,
            ),
            child: Row(
              children: [
                Icon(category.icon, size: 18, color: Tokens.fgDim),
                const SizedBox(width: Tokens.s12),
                Expanded(child: Text(category.title, style: Tokens.body)),
                Text('${category.count}', style: Tokens.numeric),
                const SizedBox(width: Tokens.s8),
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: Tokens.fgFaint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-page list of one catalog category's filter cards, pushed over the
/// shell with a back affordance.
class _CatalogCategoryScreen extends StatelessWidget {
  final CatalogCategory category;
  const _CatalogCategoryScreen({required this.category});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.bg,
      appBar: AppBar(
        backgroundColor: Tokens.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: Tokens.fg,
        iconTheme: const IconThemeData(color: Tokens.fgDim),
        title: Text(category.title, style: Tokens.heading),
      ),
      body: SectionBody(children: [category.builder(context)]),
    );
  }
}
