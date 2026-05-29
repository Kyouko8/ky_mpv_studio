import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../../state/player_scope.dart';
import '../../../ui/tokens.dart';
import '../../../ui/widgets/section_body.dart';
import '../../../util/reactive.dart';

/// Opens a compact, centred dialog with the read-only diagnostics for the
/// current file and playback — the same grouped cards and value badges the
/// Settings panel uses, so it reads as one with the rest of the app.
void showInfoDialog(BuildContext context) {
  final player = PlayerScope.of(context);
  showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (context) => _InfoDialog(player: player),
  );
}

class _InfoDialog extends StatelessWidget {
  final Player player;
  const _InfoDialog({required this.player});

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.8;
    return Dialog(
      backgroundColor: Tokens.surface,
      surfaceTintColor: Colors.transparent,
      shape: Tokens.squircle(
        Tokens.rLg,
        side: const BorderSide(color: Tokens.line2, width: 1),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 440, maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Tokens.s20,
                Tokens.s16,
                Tokens.s8,
                Tokens.s12,
              ),
              child: Row(
                children: [
                  const Expanded(child: Text('Info', style: Tokens.heading)),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    customBorder: Tokens.squircle(Tokens.rSm),
                    child: const Padding(
                      padding: EdgeInsets.all(Tokens.s4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Tokens.fgDim,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Tokens.line),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  Tokens.s20,
                  Tokens.s16,
                  Tokens.s20,
                  Tokens.s8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SettingsGroup(
                      label: 'Identity',
                      children: [
                        _live(player.stream.mediaTitle, player.state.mediaTitle,
                            'Title', _orDash),
                        _live(player.stream.fileFormat, player.state.fileFormat,
                            'Format', _orDash),
                        _live<int>(player.stream.fileSize,
                            player.state.fileSize, 'Size', _bytes),
                      ],
                    ),
                    SettingsGroup(
                      label: 'Signal',
                      children: [
                        _live<AudioParams>(player.stream.audioParams,
                            player.state.audioParams, 'Source', _params),
                        _live<double?>(player.stream.audioBitrate,
                            player.state.audioBitrate, 'Bitrate', _bitrate),
                        _live<double>(
                            player.stream.volumeGain,
                            player.state.volumeGain,
                            'Gain',
                            (v) => '${v.toStringAsFixed(1)} dB'),
                      ],
                    ),
                    SettingsGroup(
                      label: 'Open pipeline',
                      children: [
                        _live(player.stream.streamPath, player.state.streamPath,
                            'Requested', _orDash),
                        _live(player.stream.path, player.state.path, 'Resolved',
                            _orDash),
                        _live(player.stream.streamOpenFilename,
                            player.state.streamOpenFilename, 'Opened', _orDash),
                        _live(player.stream.filename, player.state.filename,
                            'Filename', _orDash),
                      ],
                    ),
                    SettingsGroup(
                      label: 'Lifecycle & timing',
                      children: [
                        StreamBuilder<MpvPlaybackState>(
                          stream: player.stream.playbackState,
                          initialData: MpvPlaybackState.idle,
                          builder: (c, s) => InfoRow(
                            label: 'State',
                            value: (s.data ?? MpvPlaybackState.idle).name,
                          ),
                        ),
                        _live<Duration>(player.stream.audioPts,
                            player.state.audioPts, 'Audio PTS', _secs),
                        _live<Duration>(player.stream.timeRemaining,
                            player.state.timeRemaining, 'Remaining', _secs),
                        _live<bool>(player.stream.eofReached,
                            player.state.eofReached, 'EOF', _yn),
                      ],
                    ),
                    SettingsGroup(
                      label: 'Seek capability',
                      children: [
                        _live<bool>(player.stream.seekable,
                            player.state.seekable, 'Seekable', _yn),
                        _live<bool>(player.stream.partiallySeekable,
                            player.state.partiallySeekable, 'Partial', _yn),
                        _live<bool>(player.stream.seeking, player.state.seeking,
                            'Seeking', _yn),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _live<T>(
    Stream<T> stream,
    T initial,
    String label,
    String Function(T) format,
  ) =>
      Live<T>(
        stream: stream,
        initial: initial,
        builder: (c, v) => InfoRow(label: label, value: format(v)),
      );

  static String _orDash(String v) => v.isEmpty ? '—' : v;
  static String _yn(bool v) => v ? 'yes' : 'no';
  static String _secs(Duration d) =>
      '${(d.inMicroseconds / 1e6).toStringAsFixed(3)} s';
  static String _bitrate(double? v) =>
      v == null || v <= 0 ? '—' : '${(v / 1000).toStringAsFixed(0)} kbps';
  static String _bytes(int b) {
    if (b <= 0) return '—';
    final mib = b / (1024 * 1024);
    return mib >= 1 ? '${mib.toStringAsFixed(2)} MiB' : '$b B';
  }

  static String _params(AudioParams p) {
    final desc = [
      if (p.format != null) p.format!,
      if (p.sampleRate != null)
        '${(p.sampleRate! / 1000).toStringAsFixed(1)} kHz',
      if (p.channels != null) p.channels!,
    ].join(' / ');
    return desc.isEmpty ? '—' : desc;
  }
}
