import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../state/app_settings.dart';
import '../../state/player_scope.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/section_body.dart';
import '../../util/reactive.dart';

/// One settings category — a sidebar entry whose detail is built lazily.
class _Category {
  final String title;
  final IconData icon;
  final WidgetBuilder build;
  const _Category(this.title, this.icon, this.build);
}

/// Full engine configuration, split into categories. Every control writes
/// straight through to the live [Player]; the [AppSettings] observer
/// snapshots each change to disk, so the configuration is restored on the
/// next launch.
///
/// On a wide stage it's a master-detail (category list + detail); on a
/// narrow one the list pushes the selected category, with a back affordance.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _splitWidth = 640.0;

  int _selected = 0;
  // On a narrow layout, null = showing the category list.
  int? _pushed;

  List<_Category> get _categories => const [
        _Category('Playback', Icons.play_arrow_rounded, _playback),
        _Category('Audio output', Icons.speaker_rounded, _output),
        _Category('Normalization', Icons.equalizer_rounded, _normalization),
        _Category('Cache & network', Icons.cloud_outlined, _cache),
        _Category('Visualizer', Icons.graphic_eq_rounded, _visualizer),
        _Category('Cover art', Icons.image_outlined, _coverArt),
        _Category('About', Icons.info_outline_rounded, _about),
      ];

  static Widget _playback(BuildContext c) => _PlaybackGroup(PlayerScope.of(c));
  static Widget _output(BuildContext c) =>
      _OutputGroup(PlayerScope.of(c), PlayerScope.settingsOf(c));
  static Widget _normalization(BuildContext c) =>
      _NormalizationGroup(PlayerScope.of(c));
  static Widget _cache(BuildContext c) => _CacheGroup(PlayerScope.of(c));
  static Widget _visualizer(BuildContext c) =>
      _VisualizerGroup(PlayerScope.of(c));
  static Widget _coverArt(BuildContext c) => _CoverArtGroup(PlayerScope.of(c));
  static Widget _about(BuildContext c) => _AboutGroup(PlayerScope.of(c));

  Widget _detail(int index) => SectionBody(children: [_categories[index].build(context)]);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= _splitWidth;
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CategoryList(
                categories: _categories,
                selected: _selected,
                onSelect: (i) => setState(() => _selected = i),
                width: 210,
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: KeyedSubtree(
                    key: ValueKey(_selected),
                    child: _detail(_selected),
                  ),
                ),
              ),
            ],
          );
        }
        // Narrow: list, pushing the detail with a back row.
        if (_pushed == null) {
          return _CategoryList(
            categories: _categories,
            selected: -1,
            onSelect: (i) => setState(() => _pushed = i),
          );
        }
        final i = _pushed!;
        return Column(
          children: [
            _BackRow(
              title: _categories[i].title,
              onBack: () => setState(() => _pushed = null),
            ),
            const Divider(height: 1, thickness: 1, color: Tokens.line),
            Expanded(child: _detail(i)),
          ],
        );
      },
    );
  }
}

class _CategoryList extends StatelessWidget {
  final List<_Category> categories;
  final int selected;
  final ValueChanged<int> onSelect;
  final double? width;

  const _CategoryList({
    required this.categories,
    required this.selected,
    required this.onSelect,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      padding: const EdgeInsets.all(Tokens.s12),
      children: [
        for (var i = 0; i < categories.length; i++)
          _CategoryTile(
            category: categories[i],
            active: i == selected,
            showChevron: width == null,
            onTap: () => onSelect(i),
          ),
      ],
    );
    if (width == null) return list;
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: Tokens.surface,
        border: Border(right: BorderSide(color: Tokens.line2, width: 1)),
      ),
      child: list,
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final _Category category;
  final bool active;
  final bool showChevron;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.category,
    required this.active,
    required this.showChevron,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Tokens.rSm),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: active ? Tokens.accentWash : Colors.transparent,
              borderRadius: BorderRadius.circular(Tokens.rSm),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: Tokens.s12,
              vertical: 11,
            ),
            child: Row(
              children: [
                Icon(
                  category.icon,
                  size: 18,
                  color: active ? Tokens.accent : Tokens.fgDim,
                ),
                const SizedBox(width: Tokens.s12),
                Expanded(
                  child: Text(
                    category.title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      color: active ? Tokens.fg : Tokens.fgDim,
                    ),
                  ),
                ),
                if (showChevron)
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

// ---- Playback -------------------------------------------------------

class _PlaybackGroup extends StatelessWidget {
  final Player player;
  const _PlaybackGroup(this.player);

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      label: 'Playback',
      children: [
        Live<double>(
          stream: player.stream.rate,
          initial: player.state.rate,
          builder: (context, v) => SliderRow(
            label: 'Speed',
            value: v,
            min: 0.25,
            max: 4,
            resetTo: 1,
            format: (x) => '${x.toStringAsFixed(2)}x',
            onChanged: player.setRate,
          ),
        ),
        Live<double>(
          stream: player.stream.pitch,
          initial: player.state.pitch,
          builder: (context, v) => SliderRow(
            label: 'Pitch',
            value: v,
            min: 0.5,
            max: 2,
            resetTo: 1,
            format: (x) => '${x.toStringAsFixed(2)}x',
            onChanged: player.setPitch,
          ),
        ),
        Live<bool>(
          stream: player.stream.pitchCorrection,
          initial: player.state.pitchCorrection,
          builder: (context, v) => SwitchRow(
            label: 'Pitch correction',
            subtitle: 'Keep pitch constant when changing speed',
            value: v,
            onChanged: player.setPitchCorrection,
          ),
        ),
        Live<Loop>(
          stream: player.stream.loop,
          initial: player.state.loop,
          builder: (context, v) => _LabelledControl(
            label: 'Repeat',
            child: SegmentedControl<Loop>(
              selected: v,
              onSelect: player.setLoop,
              options: const [
                SegmentOption(Loop.off, 'Off'),
                SegmentOption(Loop.file, 'Track'),
                SegmentOption(Loop.playlist, 'Queue'),
              ],
            ),
          ),
        ),
        Live<bool>(
          stream: player.stream.shuffle,
          initial: player.state.shuffle,
          builder: (context, v) => SwitchRow(
            label: 'Shuffle',
            value: v,
            onChanged: player.setShuffle,
          ),
        ),
        Live<Gapless>(
          stream: player.stream.gapless,
          initial: player.state.gapless,
          builder: (context, v) => _LabelledControl(
            label: 'Gapless',
            child: SegmentedControl<Gapless>(
              selected: v,
              onSelect: player.setGapless,
              options: const [
                SegmentOption(Gapless.no, 'Off'),
                SegmentOption(Gapless.weak, 'Weak'),
                SegmentOption(Gapless.yes, 'Strict'),
              ],
            ),
          ),
        ),
        Live<double>(
          stream: player.stream.volumeMax,
          initial: player.state.volumeMax,
          builder: (context, v) => SliderRow(
            label: 'Volume limit',
            value: v,
            min: 100,
            max: 1000,
            resetTo: 130,
            format: (x) => '${x.round()}%',
            onChanged: player.setVolumeMax,
          ),
        ),
      ],
    );
  }
}

// ---- Output ---------------------------------------------------------

class _OutputGroup extends StatelessWidget {
  final Player player;
  final AppSettings settings;
  const _OutputGroup(this.player, this.settings);

  static const _channels = <(Channels, String)>[
    (Channels.auto, 'Auto'),
    (Channels.mono, 'Mono'),
    (Channels.stereo, 'Stereo'),
    (Channels.twoOne, '2.1'),
    (Channels.quad, '4.0'),
    (Channels.fiveOne, '5.1'),
    (Channels.sevenOne, '7.1'),
  ];

  static const _sampleRates = <int>[0, 44100, 48000, 88200, 96000, 192000];

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      label: 'Audio output',
      children: [
        // Device picker.
        StreamBuilder<List<Device>>(
          stream: player.stream.audioDevices,
          initialData: player.state.audioDevices,
          builder: (context, devSnap) {
            final devices = devSnap.data ?? const <Device>[];
            return Live<Device>(
              stream: player.stream.audioDevice,
              initial: player.state.audioDevice,
              builder: (context, current) {
                final known = devices.any((d) => d == current);
                return DropdownRow<Device>(
                  label: 'Device',
                  value: known ? current : null,
                  hint: known ? null : current.description,
                  items: [
                    for (final d in devices)
                      DropdownMenuItem(
                        value: d,
                        child: Text(
                          d.description,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (d) {
                    if (d != null) player.setAudioDevice(d);
                  },
                );
              },
            );
          },
        ),
        SwitchRow(
          label: 'Exclusive mode',
          subtitle: 'Take exclusive control of the output device',
          value: settings.audioExclusive,
          onChanged: (v) {
            player.setAudioExclusive(v);
            settings.recordExclusive(v);
          },
        ),
        Live<Format>(
          stream: player.stream.audioFormat,
          initial: player.state.audioFormat,
          builder: (context, v) {
            // The curated list omits planar variants; if the engine
            // reports one, show it as a hint rather than asserting.
            const shown = [
              Format.auto,
              Format.s16,
              Format.s32,
              Format.float32,
              Format.float64,
            ];
            final known = shown.contains(v);
            return DropdownRow<Format>(
              label: 'Sample format',
              value: known ? v : null,
              hint: known ? null : v.mpvValue,
              items: const [
                DropdownMenuItem(value: Format.auto, child: Text('Auto')),
                DropdownMenuItem(value: Format.s16, child: Text('16-bit int')),
                DropdownMenuItem(value: Format.s32, child: Text('32-bit int')),
                DropdownMenuItem(
                    value: Format.float32, child: Text('32-bit float')),
                DropdownMenuItem(
                    value: Format.float64, child: Text('64-bit float')),
              ],
              onChanged: (f) {
                if (f != null) player.setAudioFormat(f);
              },
            );
          },
        ),
        Live<Channels>(
          stream: player.stream.audioChannels,
          initial: player.state.audioChannels,
          builder: (context, v) {
            Channels? match;
            for (final c in _channels) {
              if (c.$1.mpvValue == v.mpvValue) {
                match = c.$1;
                break;
              }
            }
            return DropdownRow<Channels>(
              label: 'Channels',
              value: match,
              hint: match == null ? v.mpvValue : null,
              items: [
                for (final c in _channels)
                  DropdownMenuItem(value: c.$1, child: Text(c.$2)),
              ],
              onChanged: (c) {
                if (c != null) player.setAudioChannels(c);
              },
            );
          },
        ),
        Live<int>(
          stream: player.stream.audioSampleRate,
          initial: player.state.audioSampleRate,
          builder: (context, v) {
            final rates = {..._sampleRates, v}.toList()..sort();
            return DropdownRow<int>(
              label: 'Sample rate',
              value: v,
              items: [
                for (final r in rates)
                  DropdownMenuItem(
                    value: r,
                    child: Text(r == 0 ? 'Auto' : '${r ~/ 1000}.${(r % 1000) ~/ 100} kHz'),
                  ),
              ],
              onChanged: (r) {
                if (r != null) player.setAudioSampleRate(r);
              },
            );
          },
        ),
        Live<Duration>(
          stream: player.stream.audioBuffer,
          initial: player.state.audioBuffer,
          builder: (context, v) => SliderRow(
            label: 'Output buffer',
            value: v.inMilliseconds.toDouble(),
            min: 0,
            max: 2000,
            resetTo: 200,
            format: (x) => '${x.round()} ms',
            onChanged: (x) =>
                player.setAudioBuffer(Duration(milliseconds: x.round())),
          ),
        ),
      ],
    );
  }
}

// ---- Normalization --------------------------------------------------

class _NormalizationGroup extends StatelessWidget {
  final Player player;
  const _NormalizationGroup(this.player);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ReplayGainSettings>(
      stream: player.stream.replayGain,
      initialData: player.state.replayGain,
      builder: (context, snap) {
        final rg = snap.data ?? const ReplayGainSettings();
        return SettingsGroup(
          label: 'ReplayGain normalization',
          children: [
            _LabelledControl(
              label: 'Mode',
              child: SegmentedControl<ReplayGain>(
                selected: rg.mode,
                onSelect: (m) =>
                    player.setReplayGain(rg.copyWith(mode: m)),
                options: const [
                  SegmentOption(ReplayGain.no, 'Off'),
                  SegmentOption(ReplayGain.track, 'Track'),
                  SegmentOption(ReplayGain.album, 'Album'),
                ],
              ),
            ),
            SliderRow(
              label: 'Pre-amp',
              value: rg.preamp,
              min: -15,
              max: 15,
              resetTo: 0,
              format: (x) => '${x.toStringAsFixed(1)} dB',
              enabled: rg.mode != ReplayGain.no,
              onChanged: (x) => player.setReplayGain(rg.copyWith(preamp: x)),
            ),
            SliderRow(
              label: 'Fallback gain',
              value: rg.fallback,
              min: -15,
              max: 15,
              resetTo: 0,
              format: (x) => '${x.toStringAsFixed(1)} dB',
              enabled: rg.mode != ReplayGain.no,
              onChanged: (x) =>
                  player.setReplayGain(rg.copyWith(fallback: x)),
            ),
            SwitchRow(
              label: 'Allow clipping',
              subtitle: 'Permit output clipping on loud tracks',
              value: rg.clip,
              enabled: rg.mode != ReplayGain.no,
              onChanged: (v) => player.setReplayGain(rg.copyWith(clip: v)),
            ),
          ],
        );
      },
    );
  }
}

// ---- Cache / network ------------------------------------------------

class _CacheGroup extends StatelessWidget {
  final Player player;
  const _CacheGroup(this.player);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CacheSettings>(
      stream: player.stream.cache,
      initialData: player.state.cache,
      builder: (context, snap) {
        final cache = snap.data ?? const CacheSettings();
        return SettingsGroup(
          label: 'Cache & network',
          children: [
            _LabelledControl(
              label: 'Cache',
              child: SegmentedControl<Cache>(
                selected: cache.mode,
                onSelect: (m) => player.setCache(cache.copyWith(mode: m)),
                options: const [
                  SegmentOption(Cache.auto, 'Auto'),
                  SegmentOption(Cache.yes, 'On'),
                  SegmentOption(Cache.no, 'Off'),
                ],
              ),
            ),
            SliderRow(
              label: 'Cache duration',
              value: cache.secs.inSeconds.toDouble(),
              min: 30,
              max: 7200,
              format: (x) => '${(x / 60).round()} min',
              onChanged: (x) => player
                  .setCache(cache.copyWith(secs: Duration(seconds: x.round()))),
            ),
            SwitchRow(
              label: 'Cache on disk',
              subtitle: 'Spill cache to disk instead of memory',
              value: cache.onDisk,
              onChanged: (v) => player.setCache(cache.copyWith(onDisk: v)),
            ),
            Live<Duration>(
              stream: player.stream.networkTimeout,
              initial: player.state.networkTimeout,
              builder: (context, v) => SliderRow(
                label: 'Network timeout',
                value: v.inSeconds.toDouble().clamp(5, 120),
                min: 5,
                max: 120,
                resetTo: 60,
                format: (x) => '${x.round()} s',
                onChanged: (x) =>
                    player.setNetworkTimeout(Duration(seconds: x.round())),
              ),
            ),
            Live<bool>(
              stream: player.stream.tlsVerify,
              initial: player.state.tlsVerify,
              builder: (context, v) => SwitchRow(
                label: 'Verify TLS certificates',
                value: v,
                onChanged: player.setTlsVerify,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---- Visualizer -----------------------------------------------------

class _VisualizerGroup extends StatelessWidget {
  final Player player;
  const _VisualizerGroup(this.player);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SpectrumSettings>(
      stream: player.stream.spectrum,
      initialData: player.spectrumSettings,
      builder: (context, snap) {
        final spec = snap.data ?? const SpectrumSettings();
        return SettingsGroup(
          label: 'Visualizer',
          children: [
            _LabelledControl(
              label: 'FFT window',
              child: SegmentedControl<WindowFunction>(
                selected: spec.window,
                onSelect: (w) => player.setSpectrum(spec.copyWith(window: w)),
                options: const [
                  SegmentOption(WindowFunction.hann, 'Hann'),
                  SegmentOption(WindowFunction.blackmanHarris, 'Blackman'),
                  SegmentOption(WindowFunction.rectangular, 'Rect'),
                ],
              ),
            ),
            _LabelledControl(
              label: 'FFT size',
              child: SegmentedControl<int>(
                selected: spec.fftSize,
                onSelect: (s) => player.setSpectrum(spec.copyWith(fftSize: s)),
                options: const [
                  SegmentOption(512, '512'),
                  SegmentOption(1024, '1024'),
                  SegmentOption(2048, '2048'),
                  SegmentOption(4096, '4096'),
                ],
              ),
            ),
            SliderRow(
              label: 'Bands',
              value: spec.bandCount.toDouble(),
              min: 16,
              max: 128,
              divisions: 112,
              format: (x) => x.round().toString(),
              onChanged: (x) =>
                  player.setSpectrum(spec.copyWith(bandCount: x.round())),
            ),
          ],
        );
      },
    );
  }
}

// ---- Cover art ------------------------------------------------------

class _CoverArtGroup extends StatelessWidget {
  final Player player;
  const _CoverArtGroup(this.player);

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      label: 'Cover art',
      children: [
        Live<Cover>(
          stream: player.stream.coverArtAuto,
          initial: player.state.coverArtAuto,
          builder: (context, v) => _LabelledControl(
            label: 'Load external art',
            child: SegmentedControl<Cover>(
              selected: v,
              onSelect: player.setCoverArtAuto,
              options: const [
                SegmentOption(Cover.no, 'Off'),
                SegmentOption(Cover.exact, 'Exact'),
                SegmentOption(Cover.fuzzy, 'Fuzzy'),
                SegmentOption(Cover.all, 'All'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---- About ----------------------------------------------------------

class _AboutGroup extends StatelessWidget {
  final Player player;
  const _AboutGroup(this.player);

  @override
  Widget build(BuildContext context) {
    final mpv = player.state.mpvVersion;
    final ffmpeg = player.state.ffmpegVersion;
    return SettingsGroup(
      label: 'About',
      children: [
        const InfoRow(label: 'App', value: 'MPV Studio'),
        InfoRow(label: 'Engine', value: mpv.isEmpty ? '—' : mpv),
        InfoRow(label: 'FFmpeg', value: ffmpeg.isEmpty ? '—' : ffmpeg),
      ],
    );
  }
}

// ---- Shared ---------------------------------------------------------

/// A caption label above a full-width control (segmented pickers).
class _LabelledControl extends StatelessWidget {
  final String label;
  final Widget child;
  const _LabelledControl({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Tokens.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: Tokens.s8),
            child: Text(label, style: Tokens.body),
          ),
          child,
        ],
      ),
    );
  }
}
