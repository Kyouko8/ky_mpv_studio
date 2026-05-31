import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../audio/biquad.dart';
import '../../audio/pcm_analysis.dart';
import '../../state/player_scope.dart';
import '../../ui/tokens.dart';
import '../../util/reactive.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/section_body.dart';
import '../../ui/widgets/section_switcher.dart';
import '../../generated/catalog.dart';
import 'widgets/equalizer.dart';
import 'widgets/compressor_curve.dart';
import 'widgets/response_curve.dart';
import 'widgets/stereo_scope.dart';
import 'widgets/crossfeed_diagram.dart';
import 'widgets/crystalizer_waveform.dart';
import 'widgets/loudness_gauge.dart';

/// The DSP rack. The curated effects that earn a bespoke visualiser are
/// surfaced as a **grid** of squircle tiles (mirroring the Settings
/// landing); tapping one opens its dedicated editor — the hero graphic
/// over its controls, with a back affordance. The remaining ffmpeg
/// catalog stays a plain **list** below, so the two tiers read as clearly
/// different things.
///
/// The bundle is the single writer of mpv's `af` chain — changes push
/// atomically via `setAudioEffects` and mirror into [AppSettings].
/// Slider drags mutate a local draft for smooth motion and commit on
/// release; toggles and resets commit immediately.
class EffectsPage extends StatefulWidget {
  const EffectsPage({super.key});

  @override
  State<EffectsPage> createState() => _EffectsPageState();
}

class _EffectsPageState extends State<EffectsPage>
    with StreamListenerState<EffectsPage> {
  late final Player _player;
  late AudioEffects _fx;
  bool _editing = false;

  /// Index of the open featured editor; null = the grid landing.
  int? _pushed;

  @override
  void onSubscribe() {
    _player = PlayerScope.of(context);
    _fx = _player.state.audioEffects;
    listen(_player.stream.audioEffects, (v) {
      // Resync from the engine only when the user isn't mid-drag, so an
      // optimistic local draft is never clobbered.
      if (!_editing && mounted && v != _fx) setState(() => _fx = v);
    });
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

  static String _pct(double v) => '${(v * 100).round()}%';

  // ── Featured effect descriptors ───────────────────────────────────
  //
  // Each carries everything both the grid tile (icon, title, on-state)
  // and the detail editor (graphic, controls, toggle, reset) need.

  List<_Featured> _featured() {
    final eq = _fx.superequalizer;
    final comp = _fx.acompressor;
    final bass = _fx.bass;
    final treble = _fx.treble;
    final cf = _fx.crossfeed;
    final cr = _fx.crystalizer;
    final st = _fx.extrastereo;
    final sb = _fx.asubboost;
    final ln = _fx.loudnorm;

    return [
      // ---- 18-band graphic EQ -----------------------------------------
      _Featured(
        title: 'Equalizer',
        subtitle: '18-band graphic',
        icon: Icons.equalizer_rounded,
        enabled: eq.enabled,
        onEnabled: (v) =>
            _commitNow(_fx.copyWith(superequalizer: eq.copyWith(enabled: v))),
        onReset: () => _commitNow(_fx.copyWith(
          superequalizer:
              SuperequalizerSettings(enabled: eq.enabled, params: const {}),
        )),
        graphic: Equalizer(
          bandsDb: {
            for (final b in kEqBands)
              b.key: eqLinearToDb(eq.params[b.key] ?? 1.0),
          },
          enabled: eq.enabled,
          onChanged: (key, db) {
            final params = Map<String, double>.from(eq.params);
            if (db.abs() < 0.05) {
              params.remove(key);
            } else {
              params[key] = eqDbToLinear(db);
            }
            _setLocal(_fx.copyWith(superequalizer: eq.copyWith(params: params)));
          },
          onChangeEnd: _commit,
        ),
        controls: const [],
      ),

      // ---- Compressor -------------------------------------------------
      _Featured(
        title: 'Compressor',
        subtitle: 'Dynamic range control',
        icon: Icons.compress_rounded,
        enabled: comp.enabled,
        onEnabled: (v) =>
            _commitNow(_fx.copyWith(acompressor: comp.copyWith(enabled: v))),
        onReset: () => _commitNow(
            _fx.copyWith(acompressor: AcompressorSettings(enabled: comp.enabled))),
        graphic: CompressorCurve(
          threshold: comp.threshold,
          ratio: comp.ratio,
          knee: comp.knee,
          makeup: comp.makeup,
          enabled: comp.enabled,
        ),
        controls: [
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
                  acompressor:
                      comp.copyWith(makeup: eqDbToLinear(v).clamp(1.0, 64.0))),
              format: (v) => '+${v.round()} dB'),
        ],
      ),

      // ---- Bass -------------------------------------------------------
      _Featured(
        title: 'Bass',
        subtitle: 'Low shelf',
        icon: Icons.graphic_eq_rounded,
        enabled: bass.enabled,
        onEnabled: (v) =>
            _commitNow(_fx.copyWith(bass: bass.copyWith(enabled: v))),
        onReset: () =>
            _commitNow(_fx.copyWith(bass: BassSettings(enabled: bass.enabled))),
        graphic: ResponseCurve(
          response: BiquadResponse.lowShelf(bass.frequency, bass.gain),
          markerHz: bass.frequency,
          enabled: bass.enabled,
        ),
        controls: [
          _spec('Gain', bass.gain, -24, 24,
              (v) => _fx.copyWith(bass: bass.copyWith(gain: v)),
              format: (v) => '${v.toStringAsFixed(1)} dB'),
          _spec('Frequency', bass.frequency, 20, 500,
              (v) => _fx.copyWith(bass: bass.copyWith(frequency: v)),
              format: (v) => '${v.round()} Hz'),
        ],
      ),

      // ---- Treble -----------------------------------------------------
      _Featured(
        title: 'Treble',
        subtitle: 'High shelf',
        icon: Icons.graphic_eq_rounded,
        enabled: treble.enabled,
        onEnabled: (v) =>
            _commitNow(_fx.copyWith(treble: treble.copyWith(enabled: v))),
        onReset: () => _commitNow(
            _fx.copyWith(treble: TrebleSettings(enabled: treble.enabled))),
        graphic: ResponseCurve(
          response: BiquadResponse.highShelf(treble.frequency, treble.gain),
          markerHz: treble.frequency,
          enabled: treble.enabled,
        ),
        controls: [
          _spec('Gain', treble.gain, -24, 24,
              (v) => _fx.copyWith(treble: treble.copyWith(gain: v)),
              format: (v) => '${v.toStringAsFixed(1)} dB'),
          _spec('Frequency', treble.frequency, 1000, 16000,
              (v) => _fx.copyWith(treble: treble.copyWith(frequency: v)),
              format: (v) => '${(v / 1000).toStringAsFixed(1)}k Hz'),
        ],
      ),

      // ---- Sub boost --------------------------------------------------
      _Featured(
        title: 'Sub boost',
        subtitle: 'Synthesised low end',
        icon: Icons.surround_sound_rounded,
        enabled: sb.enabled,
        onEnabled: (v) =>
            _commitNow(_fx.copyWith(asubboost: sb.copyWith(enabled: v))),
        onReset: () => _commitNow(
            _fx.copyWith(asubboost: AsubboostSettings(enabled: sb.enabled))),
        graphic: ResponseCurve(
          response: BiquadResponse.lowShelf(
              sb.cutoff, amplitudeToDb(sb.boost)),
          markerHz: sb.cutoff,
          enabled: sb.enabled,
        ),
        controls: [
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

      // ---- Stereo width -----------------------------------------------
      _Featured(
        title: 'Stereo width',
        subtitle: 'Widen the stereo image',
        icon: Icons.panorama_horizontal_rounded,
        enabled: st.enabled,
        onEnabled: (v) =>
            _commitNow(_fx.copyWith(extrastereo: st.copyWith(enabled: v))),
        onReset: () => _commitNow(
            _fx.copyWith(extrastereo: ExtrastereoSettings(enabled: st.enabled))),
        graphic: StereoScope(enabled: st.enabled),
        controls: [
          _spec('Amount', st.m, 0, 8,
              (v) => _fx.copyWith(extrastereo: st.copyWith(m: v)),
              format: (v) => v.toStringAsFixed(1)),
        ],
      ),

      // ---- Crossfeed --------------------------------------------------
      _Featured(
        title: 'Crossfeed',
        subtitle: 'Headphone channel blend',
        icon: Icons.headphones_rounded,
        enabled: cf.enabled,
        onEnabled: (v) =>
            _commitNow(_fx.copyWith(crossfeed: cf.copyWith(enabled: v))),
        onReset: () => _commitNow(
            _fx.copyWith(crossfeed: CrossfeedSettings(enabled: cf.enabled))),
        graphic: CrossfeedDiagram(
          strength: cf.strength,
          range: cf.range,
          enabled: cf.enabled,
        ),
        controls: [
          _spec('Strength', cf.strength, 0, 1,
              (v) => _fx.copyWith(crossfeed: cf.copyWith(strength: v)),
              format: _pct),
          _spec('Range', cf.range, 0, 1,
              (v) => _fx.copyWith(crossfeed: cf.copyWith(range: v)),
              format: _pct),
        ],
      ),

      // ---- Clarity (crystalizer) --------------------------------------
      _Featured(
        title: 'Clarity',
        subtitle: 'Crystalizer expander',
        icon: Icons.auto_awesome_rounded,
        enabled: cr.enabled,
        onEnabled: (v) =>
            _commitNow(_fx.copyWith(crystalizer: cr.copyWith(enabled: v))),
        onReset: () => _commitNow(
            _fx.copyWith(crystalizer: CrystalizerSettings(enabled: cr.enabled))),
        graphic: CrystalizerWaveform(intensity: cr.i, enabled: cr.enabled),
        controls: [
          _spec('Intensity', cr.i, -10, 10,
              (v) => _fx.copyWith(crystalizer: cr.copyWith(i: v)),
              format: (v) => v.toStringAsFixed(1)),
        ],
      ),

      // ---- Loudness ---------------------------------------------------
      _Featured(
        title: 'Loudness',
        subtitle: 'EBU R128 normalization',
        icon: Icons.volume_up_rounded,
        enabled: ln.enabled,
        onEnabled: (v) =>
            _commitNow(_fx.copyWith(loudnorm: ln.copyWith(enabled: v))),
        onReset: () => _commitNow(
            _fx.copyWith(loudnorm: LoudnormSettings(enabled: ln.enabled))),
        graphic: LoudnessGauge(
          target: ln.i,
          range: ln.lra,
          truePeak: ln.tp,
          enabled: ln.enabled,
        ),
        controls: [
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
    ];
  }

  @override
  Widget build(BuildContext context) {
    final featured = _featured();
    final pushed = _pushed != null && _pushed! < featured.length;
    final Widget body = pushed
        ? Column(
            children: [
              _BackRow(
                title: featured[_pushed!].title,
                onBack: () => setState(() => _pushed = null),
              ),
              const Divider(height: 1, thickness: 1, color: Tokens.line),
              Expanded(child: _FeaturedDetail(spec: featured[_pushed!])),
            ],
          )
        : SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          Tokens.s20, Tokens.s8, Tokens.s20, Tokens.s32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(Tokens.s4, 0, Tokens.s4, Tokens.s8),
            child: Text('FEATURED', style: Tokens.caption),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 168,
              crossAxisSpacing: Tokens.s12,
              mainAxisSpacing: Tokens.s12,
              childAspectRatio: 1,
            ),
            itemCount: featured.length,
            itemBuilder: (context, i) => _FxTile(
              spec: featured[i],
              onTap: () => setState(() => _pushed = i),
            ),
          ),
          const SizedBox(height: Tokens.s24),
          const Padding(
            padding: EdgeInsets.fromLTRB(Tokens.s4, 0, Tokens.s4, Tokens.s8),
            child: Text('ALL EFFECTS', style: Tokens.caption),
          ),
          for (final cat in kCatalogCategories) _CatalogTile(category: cat),
        ],
      ),
    );
    return SectionSwitcher(
      child: KeyedSubtree(
        key: ValueKey<int?>(pushed ? _pushed : null),
        child: body,
      ),
    );
  }
}

/// Bundles everything a featured effect needs for both its grid tile and
/// its detail editor.
class _Featured {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool enabled;
  final ValueChanged<bool> onEnabled;
  final VoidCallback onReset;

  /// Hero visualiser shown above the controls in the detail editor.
  final Widget graphic;

  /// Slider controls; empty for effects whose graphic *is* the control
  /// (the equalizer).
  final List<SliderRowSpec> controls;

  const _Featured({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.enabled,
    required this.onEnabled,
    required this.onReset,
    required this.graphic,
    required this.controls,
  });
}

/// Bundles a [SliderRow]'s parameters so a module can declare its controls
/// as a flat list and let the editor render them.
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

/// A squircle tile in the featured grid — icon, title, and an accent
/// "on" pip + border when the effect is engaged. Tapping opens its editor.
class _FxTile extends StatelessWidget {
  final _Featured spec;
  final VoidCallback onTap;

  const _FxTile({required this.spec, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final on = spec.enabled;
    final shape = ContinuousRectangleBorder(
      borderRadius: BorderRadius.circular(40),
      side: BorderSide(color: on ? Tokens.accentDim : Tokens.line, width: 1),
    );
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        customBorder:
            ContinuousRectangleBorder(borderRadius: BorderRadius.circular(40)),
        // Ink (not Container) so the hover/ink highlight paints on the
        // Material above the surface fill instead of being hidden behind it.
        child: Ink(
          decoration: ShapeDecoration(color: Tokens.surface, shape: shape),
          padding: const EdgeInsets.all(Tokens.s16),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(spec.icon,
                        size: 26, color: on ? Tokens.accent : Tokens.fgDim),
                    const SizedBox(height: Tokens.s12),
                    Text(
                      spec.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Tokens.fg,
                      ),
                    ),
                  ],
                ),
              ),
              // "On" pip, top-right.
              Positioned(
                top: 0,
                right: 0,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: on ? 1 : 0,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const ShapeDecoration(
                      color: Tokens.accent,
                      shape: CircleBorder(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The dedicated editor for one featured effect: a bypass toggle, the hero
/// graphic, the controls, and a reset — all in the flat card language.
class _FeaturedDetail extends StatelessWidget {
  final _Featured spec;
  const _FeaturedDetail({required this.spec});

  @override
  Widget build(BuildContext context) {
    return SectionBody(
      children: [
        // Bypass toggle.
        _DetailCard(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.s16),
          child: SwitchRow(
            label: 'Effect',
            subtitle: spec.subtitle,
            value: spec.enabled,
            onChanged: spec.onEnabled,
          ),
        ),
        // Hero graphic.
        _DetailCard(child: spec.graphic),
        // Controls.
        if (spec.controls.isNotEmpty)
          _DetailCard(
            child: Column(
              children: [
                for (var i = 0; i < spec.controls.length; i++) ...[
                  if (i > 0) const SizedBox(height: Tokens.s4),
                  spec.controls[i].build(spec.enabled),
                ],
              ],
            ),
          ),
        // Reset.
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: spec.onReset,
            icon: const Icon(Icons.restart_alt_rounded, size: 16),
            label: const Text('Reset'),
            style: TextButton.styleFrom(
              foregroundColor: Tokens.fgDim,
              textStyle: Tokens.label,
            ),
          ),
        ),
      ],
    );
  }
}

/// A flat bordered surface card used to frame the detail editor's blocks.
class _DetailCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _DetailCard({
    required this.child,
    this.padding = const EdgeInsets.all(Tokens.s16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: Tokens.s12),
      padding: padding,
      decoration: ShapeDecoration(
        color: Tokens.surface,
        shape: Tokens.squircle(
          Tokens.rMd,
          side: const BorderSide(color: Tokens.line, width: 1),
        ),
      ),
      child: child,
    );
  }
}

/// Back affordance shown atop a pushed editor — mirrors the Settings
/// detail header.
class _BackRow extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  const _BackRow({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onBack,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.s12),
            child: Row(
              children: [
                const Icon(Icons.chevron_left_rounded,
                    size: 22, color: Tokens.fgDim),
                const SizedBox(width: Tokens.s4),
                Text(title, style: Tokens.heading),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
            fadeSlidePageRoute(_CatalogCategoryScreen(category: category)),
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
