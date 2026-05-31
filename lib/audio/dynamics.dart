import 'dart:math' as math;

/// Dynamics-processing maths shared by the compressor visualiser.

/// Soft-knee compressor transfer function, all in dB (RBJ-cookbook style).
///
/// [inputDb] is the instantaneous input level; the result is the output
/// level after the threshold/ratio/knee bend plus [makeupDb]. [kneeDb] is
/// the knee *width* in dB (0 = hard knee). Below the knee the curve is
/// unity; across it the curve blends quadratically; above it the slope is
/// `1/ratio`.
double compressorKneeDb(
  double inputDb, {
  required double thresholdDb,
  required double ratio,
  required double kneeDb,
  required double makeupDb,
}) {
  final diff = inputDb - thresholdDb;
  double out;
  if (kneeDb > 0 && (2 * diff).abs() <= kneeDb) {
    final factor = (1.0 / ratio - 1.0) / (2.0 * kneeDb);
    out = inputDb + factor * math.pow(diff + kneeDb / 2, 2).toDouble();
  } else if (diff > kneeDb / 2) {
    out = thresholdDb + diff / ratio;
  } else {
    out = inputDb;
  }
  return out + makeupDb;
}
