import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../../ui/tokens.dart';
import '../../../ui/widgets/controls.dart';
import '../../../ui/widgets/section_body.dart';
import '../../../util/reactive.dart';

/// Output-driver (`ao`) selection, engine fallbacks and live output
/// status. The driver list is discovered the mpv way — writing `ao=help`
/// prints the available drivers to the log, which we scrape once.
class AudioEngineGroup extends StatefulWidget {
  final Player player;
  const AudioEngineGroup(this.player, {super.key});

  @override
  State<AudioEngineGroup> createState() => _AudioEngineGroupState();
}

class _AudioEngineGroupState extends State<AudioEngineGroup> {
  Player get player => widget.player;
  List<String> _drivers = const ['auto'];

  @override
  void initState() {
    super.initState();
    _loadDrivers();
  }

  Future<void> _loadDrivers() async {
    final collected = <String>[];
    var collecting = false;
    final sub = player.stream.log.listen((entry) {
      final text = entry.text.trim();
      if (text.contains('Available audio outputs')) {
        collecting = true;
        return;
      }
      if (collecting && text.isNotEmpty) {
        final name = text.split(RegExp(r'\s+')).first;
        if (name.isNotEmpty) collected.add(name);
      }
    });
    // `ao=help` lists drivers as a log side-effect, then rejects the
    // write itself — the listing has already arrived, so swallow it.
    try {
      await player.setRawProperty('ao', 'help');
    } on MpvException {
      // Expected.
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await sub.cancel();
    if (collected.isNotEmpty && mounted) {
      setState(() => _drivers = ['auto', ...collected]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          label: 'Output driver',
          children: [
            Live<String>(
              stream: player.stream.audioDriver,
              initial: player.state.audioDriver,
              builder: (context, raw) {
                final val = raw.isEmpty ? 'auto' : raw;
                final options = [
                  ..._drivers,
                  if (!_drivers.contains(val)) val,
                ];
                return DropdownRow<String>(
                  label: 'Driver',
                  value: val,
                  items: [
                    for (final d in options)
                      DropdownMenuItem(value: d, child: Text(d)),
                  ],
                  onChanged: (v) {
                    if (v != null) player.setAudioDriver(v);
                  },
                );
              },
            ),
            Live<bool>(
              stream: player.stream.audioNullUntimed,
              initial: player.state.audioNullUntimed,
              builder: (context, v) => SwitchRow(
                label: 'Fallback to null',
                subtitle: 'Use the null driver when no output is available',
                value: v,
                onChanged: (x) => unawaited(player.setAudioNullUntimed(x)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Tokens.s6),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Reload audio engine', style: Tokens.body),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    color: Tokens.fgDim,
                    onPressed: player.reloadAudio,
                    tooltip: 'Reload',
                  ),
                ],
              ),
            ),
          ],
        ),
        SettingsGroup(
          label: 'Passthrough & identity',
          children: [
            StreamBuilder<Set<Spdif>>(
              stream: player.stream.audioSpdif,
              initialData: player.state.audioSpdif,
              builder: (context, snap) => _SpdifChips(
                selected: snap.data ?? const <Spdif>{},
                onChanged: player.setAudioSpdif,
              ),
            ),
            Live<String>(
              stream: player.stream.audioClientName,
              initial: player.state.audioClientName,
              builder: (context, v) => _ClientNameField(
                value: v,
                onSubmitted: player.setAudioClientName,
              ),
            ),
          ],
        ),
        SettingsGroup(
          label: 'Output status',
          children: [
            Live<String>(
              stream: player.stream.currentAo,
              initial: player.state.currentAo,
              builder: (context, v) =>
                  InfoRow(label: 'Active driver', value: v.isEmpty ? '—' : v),
            ),
            Live<AudioOutputState>(
              stream: player.stream.audioOutputState,
              initial: player.state.audioOutputState,
              builder: (context, v) =>
                  InfoRow(label: 'Output state', value: v.mpvValue),
            ),
            Live<AudioParams>(
              stream: player.stream.audioOutParams,
              initial: player.state.audioOutParams,
              builder: (context, p) {
                final desc = [
                  if (p.format != null) p.format!,
                  if (p.sampleRate != null)
                    '${(p.sampleRate! / 1000).toStringAsFixed(1)} kHz',
                  if (p.channels != null) p.channels!,
                ].join(' / ');
                return InfoRow(
                  label: 'Output params',
                  value: desc.isEmpty ? '—' : desc,
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// Multi-select pills for S/PDIF passthrough codecs. mpv treats the set
/// as a whitelist; an empty set disables passthrough entirely.
class _SpdifChips extends StatelessWidget {
  final Set<Spdif> selected;
  final ValueChanged<Set<Spdif>> onChanged;
  const _SpdifChips({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SettingTile(
      title: 'S/PDIF passthrough',
      below: Wrap(
        spacing: Tokens.s8,
        runSpacing: Tokens.s8,
        children: [
          for (final s in Spdif.values)
            _Chip(
              label: s.mpvValue,
              active: selected.contains(s),
              onTap: () {
                final next = {...selected};
                next.contains(s) ? next.remove(s) : next.add(s);
                onChanged(next);
              },
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        customBorder: Tokens.squircle(Tokens.rSm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Tokens.s12,
            vertical: Tokens.s6,
          ),
          decoration: ShapeDecoration(
            color: active ? Tokens.accent : Tokens.surface2,
            shape: Tokens.squircle(Tokens.rSm),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: active ? Tokens.onAccent : Tokens.fgDim,
            ),
          ),
        ),
      ),
    );
  }
}

/// An inline text field for the `audio-client-name` property (the name
/// the OS mixer shows). Commits on submit.
class _ClientNameField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onSubmitted;
  const _ClientNameField({required this.value, required this.onSubmitted});

  @override
  State<_ClientNameField> createState() => _ClientNameFieldState();
}

class _ClientNameFieldState extends State<_ClientNameField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(_ClientNameField old) {
    super.didUpdateWidget(old);
    // Keep in sync with the engine unless the user is mid-edit.
    if (widget.value != old.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SettingTile(
      title: 'Client name',
      below: Container(
        padding: const EdgeInsets.symmetric(horizontal: Tokens.s12),
        decoration: ShapeDecoration(
          color: Tokens.surface2,
          shape: Tokens.squircle(
            Tokens.rSm,
            side: const BorderSide(color: Tokens.line2, width: 1),
          ),
        ),
        child: TextField(
          controller: _controller,
          style: Tokens.body,
          cursorColor: Tokens.accent,
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            hintText: 'mpv_studio',
            hintStyle: Tokens.caption,
          ),
          onSubmitted: widget.onSubmitted,
        ),
      ),
    );
  }
}
