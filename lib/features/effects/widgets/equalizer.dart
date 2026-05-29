import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ui/tokens.dart';

/// The 18 fixed bands of ffmpeg's `superequalizer`, in order. The key is
/// the raw ffmpeg option name (digit-prefixed, so it lives in the
/// settings `params` map); the label is the band's centre frequency.
const List<({String key, String label})> kEqBands = [
  (key: '1b', label: '65'),
  (key: '2b', label: '92'),
  (key: '3b', label: '131'),
  (key: '4b', label: '185'),
  (key: '5b', label: '262'),
  (key: '6b', label: '370'),
  (key: '7b', label: '523'),
  (key: '8b', label: '740'),
  (key: '9b', label: '1k'),
  (key: '10b', label: '1.5k'),
  (key: '11b', label: '2.1k'),
  (key: '12b', label: '3k'),
  (key: '13b', label: '4.2k'),
  (key: '14b', label: '5.9k'),
  (key: '15b', label: '8.4k'),
  (key: '16b', label: '12k'),
  (key: '17b', label: '17k'),
  (key: '18b', label: '20k'),
];

/// EQ band gains are presented in dB (±[maxDb]) but `superequalizer`
/// takes a linear multiplier (1.0 = flat). These convert between the
/// two; 0 dB ⇒ 1.0.
const double kEqMaxDb = 12;
double eqLinearToDb(double linear) =>
    linear <= 0 ? -kEqMaxDb : 20 * (math.log(linear) / math.ln10);
double eqDbToLinear(double db) => math.pow(10, db / 20).toDouble();

/// A flat 18-band graphic equalizer: a row of vertical dB sliders with a
/// centre (0 dB) baseline. Emits per-band dB changes; the parent maps
/// them into the `superequalizer` params map.
class Equalizer extends StatelessWidget {
  /// Current gain per band key, in dB. Missing keys read as 0 dB.
  final Map<String, double> bandsDb;
  final void Function(String key, double db) onChanged;
  final VoidCallback onChangeEnd;
  final bool enabled;

  const Equalizer({
    super.key,
    required this.bandsDb,
    required this.onChanged,
    required this.onChangeEnd,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final band in kEqBands)
            _Band(
              freq: band.label,
              db: bandsDb[band.key] ?? 0,
              enabled: enabled,
              onChanged: (db) => onChanged(band.key, db),
              onChangeEnd: onChangeEnd,
            ),
        ],
      ),
    );
  }
}

class _Band extends StatelessWidget {
  final String freq;
  final double db;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;

  const _Band({
    required this.freq,
    required this.db,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = db.clamp(-kEqMaxDb, kEqMaxDb);
    return SizedBox(
      width: 32,
      child: Column(
        children: [
          SizedBox(
            height: 16,
            child: Text(
              clamped == 0 ? '0' : clamped.toStringAsFixed(0),
              style: Tokens.caption.copyWith(
                color: clamped == 0
                    ? Tokens.fgFaint
                    : (enabled ? Tokens.accent : Tokens.fgFaint),
              ),
            ),
          ),
          SizedBox(
            height: 150,
            child: RotatedBox(
              quarterTurns: 3,
              child: Slider(
                value: clamped,
                min: -kEqMaxDb,
                max: kEqMaxDb,
                onChanged: enabled ? onChanged : null,
                onChangeEnd: enabled ? (_) => onChangeEnd() : null,
              ),
            ),
          ),
          const SizedBox(height: Tokens.s4),
          SizedBox(
            height: 14,
            child: Text(
              freq,
              style: Tokens.caption.copyWith(fontSize: 9.5),
            ),
          ),
        ],
      ),
    );
  }
}
