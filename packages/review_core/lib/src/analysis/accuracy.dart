/// rreview accuracy: a documented, app-specific score. Not Chess.com's.
library;

import 'dart:math' as math;

/// Per-move accuracy from the expected-score loss (0..1) of the mover.
///
/// 0 loss → 100; 0.05 (a "good" move) → ~81; 0.10 → ~66; 0.20 → ~43; 0.30 → ~28.
/// Formula: 100 · exp(−4.2 · loss), floored at 0. See docs/CLASSIFICATION.md.
double moveAccuracy(double loss) {
  final l = loss.clamp(0.0, 1.0);
  return (100 * math.exp(-4.2 * l)).clamp(0.0, 100.0);
}

/// Game accuracy: mean of the harmonic and arithmetic means of per-move values.
double gameAccuracy(List<double> perMove) {
  if (perMove.isEmpty) return 0;
  var inv = 0.0;
  var sum = 0.0;
  for (final a in perMove) {
    inv += 1 / a.clamp(1.0, 100.0);
    sum += a;
  }
  final harmonic = perMove.length / inv;
  final arithmetic = sum / perMove.length;
  return ((harmonic + arithmetic) / 2).clamp(0.0, 100.0);
}
