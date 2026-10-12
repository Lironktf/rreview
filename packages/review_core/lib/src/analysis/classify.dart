/// Move classification by expected-score loss. Documented in docs/CLASSIFICATION.md.
library;

import '../score.dart';
import 'models.dart';

/// Thresholds in expected-score points (0..1). Configurable for tests/tuning.
class ClassificationThresholds {
  const ClassificationThresholds({
    this.best = 0.005,
    this.excellent = 0.02,
    this.good = 0.05,
    this.inaccuracy = 0.10,
    this.mistake = 0.20,
    this.missedWinFloor = 0.80,
    this.missedWinCeiling = 0.65,
  });

  /// Loss at or below which a non-engine-choice move still counts as Best
  /// (practically equal alternatives).
  final double best;
  final double excellent;
  final double good;
  final double inaccuracy;
  final double mistake;

  /// A "missed win" needs the mover's expected score before the move to be at
  /// least [missedWinFloor] and to fall below [missedWinCeiling] after it.
  final double missedWinFloor;
  final double missedWinCeiling;

  static const standard = ClassificationThresholds();
}

/// Inputs to the classifier, all from the *mover's* perspective.
class MoveOutcome {
  const MoveOutcome({
    required this.expectedBefore,
    required this.expectedAfter,
    required this.playedIsEngineBest,
    required this.bestScore,
    required this.playedScore,
    required this.inBook,
  });

  /// Expected score for the mover if they play the engine's best move.
  final double expectedBefore;

  /// Expected score for the mover after the move actually played.
  final double expectedAfter;
  final bool playedIsEngineBest;

  /// Mover-perspective scores (used for mate reasoning).
  final Score bestScore;
  final Score playedScore;
  final bool inBook;

  double get loss => (expectedBefore - expectedAfter).clamp(0.0, 1.0);
}

MoveLabel classify(MoveOutcome o, {ClassificationThresholds t = ClassificationThresholds.standard}) {
  if (o.inBook) return MoveLabel.book;
  if (o.playedIsEngineBest) return MoveLabel.best;
  final loss = o.loss;

  // Mate handling is explicit so that it never hides behind the continuous model.
  final bestMates = o.bestScore.isMate && o.bestScore.sign > 0;
  final playedMates = o.playedScore.isMate && o.playedScore.sign > 0;
  final playedGetsMated = o.playedScore.isMate && o.playedScore.sign < 0;
  final bestGetsMated = o.bestScore.isMate && o.bestScore.sign < 0;
  if (bestMates && !playedMates) {
    // Threw away a forced mate.
    return loss >= t.mistake ? MoveLabel.missedWin : MoveLabel.mistake;
  }
  if (playedGetsMated && !bestGetsMated) {
    // Walked into a forced mate that could have been avoided.
    return loss >= t.inaccuracy ? MoveLabel.blunder : MoveLabel.mistake;
  }
  if (bestMates && playedMates) {
    // Still mating, just slower.
    return loss <= t.excellent ? MoveLabel.excellent : MoveLabel.good;
  }

  if (loss <= t.best) return MoveLabel.best;
  if (loss <= t.excellent) return MoveLabel.excellent;
  if (loss <= t.good) return MoveLabel.good;
  if (loss <= t.inaccuracy) return MoveLabel.inaccuracy;
  if (loss <= t.mistake) {
    if (o.expectedBefore >= t.missedWinFloor && o.expectedAfter < t.missedWinCeiling) return MoveLabel.missedWin;
    return MoveLabel.mistake;
  }
  if (o.expectedBefore >= t.missedWinFloor && o.expectedAfter < t.missedWinCeiling && o.expectedAfter > 0.35) {
    return MoveLabel.missedWin;
  }
  return MoveLabel.blunder;
}
