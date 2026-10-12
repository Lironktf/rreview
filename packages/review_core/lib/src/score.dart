/// Engine scores, perspective handling and the expected-score model.
library;

import 'dart:math' as math;

import 'package:chess_core/chess_core.dart';

/// A score from White's point of view: either centipawns or mate-in-N.
///
/// Mate scores are kept separate from centipawns throughout the app. [mate] is
/// positive when White mates, negative when Black mates; the magnitude is the
/// number of moves (not plies). `mate == 0` is used for "checkmated now".
class Score {
  const Score.cp(this.cp)
      : mate = null,
        matedColor = null;
  const Score.mate(this.mate)
      : cp = null,
        matedColor = null;

  /// A position in which [matedColor] has already been checkmated.
  const Score.checkmated(Color this.matedColor)
      : cp = null,
        mate = 0;

  final int? cp;
  final int? mate;
  final Color? matedColor;

  bool get isMate => mate != null;

  /// Sign of the score for White: +1 winning, -1 losing, 0 level.
  int get sign {
    if (matedColor != null) return matedColor == Color.white ? -1 : 1;
    if (isMate) return mate! > 0 ? 1 : -1;
    return cp!.sign;
  }

  /// Converts a side-to-move relative UCI score to White's perspective.
  static Score fromUci({int? cp, int? mate, required Color sideToMove}) {
    final sign = sideToMove == Color.white ? 1 : -1;
    if (mate != null) return Score.mate(mate * sign);
    return Score.cp((cp ?? 0) * sign);
  }

  /// Negated score (perspective flip).
  Score get negated {
    if (matedColor != null) return Score.checkmated(matedColor!.opposite);
    return isMate ? Score.mate(-mate!) : Score.cp(-cp!);
  }

  /// A rough centipawn-like number for sorting; mates map to ±(10000 - moves).
  int get asCp {
    if (matedColor != null) return sign * 10000;
    return isMate ? (mate! > 0 ? 10000 - mate! : -10000 - mate!) : cp!;
  }

  /// Value clamped to ±[limit] in pawns for the evaluation graph.
  double clampedPawns([double limit = 6.0]) {
    if (isMate) return sign >= 0 ? limit : -limit;
    return (cp! / 100).clamp(-limit, limit);
  }

  /// Display text, e.g. `+0.3`, `-1.2`, `M3`, `-M2`, `0.0`.
  String get display {
    if (isMate) {
      if (mate == 0) return '#';
      return mate! > 0 ? 'M$mate' : '-M${-mate!}';
    }
    final pawns = cp! / 100;
    if (pawns.abs() < 0.05) return '0.0';
    return '${pawns > 0 ? '+' : ''}${pawns.toStringAsFixed(1)}';
  }

  /// Display for an evaluation bar (no sign on mates, short form).
  String get barLabel {
    if (isMate) return mate == 0 ? '#' : 'M${mate!.abs()}';
    final pawns = (cp!.abs() / 100);
    return pawns >= 10 ? pawns.toStringAsFixed(0) : pawns.toStringAsFixed(1);
  }

  Map<String, dynamic> toJson() {
    if (matedColor != null) return {'mated': matedColor!.index};
    return isMate ? {'mate': mate} : {'cp': cp};
  }

  static Score fromJson(Map<String, dynamic> j) {
    if (j.containsKey('mated')) return Score.checkmated(Color.values[j['mated'] as int]);
    return j.containsKey('mate') ? Score.mate(j['mate'] as int) : Score.cp(j['cp'] as int);
  }

  @override
  bool operator ==(Object other) =>
      other is Score && other.cp == cp && other.mate == mate && other.matedColor == matedColor;
  @override
  int get hashCode => Object.hash(cp, mate, matedColor);
  @override
  String toString() => display;
}

/// Win/draw/loss probabilities (sum 1) from White's point of view.
class Wdl {
  const Wdl(this.win, this.draw, this.loss);
  final double win;
  final double draw;
  final double loss;

  /// Expected score for White in [0, 1].
  double get expectedScore => win + draw / 2;

  Wdl get flipped => Wdl(loss, draw, win);

  static Wdl fromPerMille((int, int, int) wdl, {required Color sideToMove}) {
    final w = Wdl(wdl.$1 / 1000, wdl.$2 / 1000, wdl.$3 / 1000);
    return sideToMove == Color.white ? w : w.flipped;
  }

  Map<String, dynamic> toJson() => {'w': win, 'd': draw, 'l': loss};
  static Wdl fromJson(Map<String, dynamic> j) =>
      Wdl((j['w'] as num).toDouble(), (j['d'] as num).toDouble(), (j['l'] as num).toDouble());
}

/// Stockfish 19's win-rate model (src/uci.cpp, `win_rate_params` /
/// `win_rate_model`), used to convert centipawns to an expected score when the
/// engine did not report WDL (e.g. cached or foreign evaluations) and to
/// convert mate scores. The model's `a` depends on the material on the board.
class WinModel {
  WinModel._();

  static const _as = [-142.72052667, 372.35176398, -340.71073572, 415.23490212];
  static const _bs = [5.93832785, 15.61267078, -30.57816876, 69.63866711];

  /// Material count P + 3N + 3B + 5R + 9Q, clamped like Stockfish does.
  static int materialOf(Position pos) {
    var total = 0;
    for (final p in pos.board) {
      if (p == null) continue;
      total += switch (p.type) {
        PieceType.pawn => 1,
        PieceType.knight => 3,
        PieceType.bishop => 3,
        PieceType.rook => 5,
        PieceType.queen => 9,
        PieceType.king => 0,
      };
    }
    return total;
  }

  static (double, double) _params(int material) {
    final m = material.clamp(17, 78) / 58.0;
    final a = ((_as[0] * m + _as[1]) * m + _as[2]) * m + _as[3];
    final b = ((_bs[0] * m + _bs[1]) * m + _bs[2]) * m + _bs[3];
    return (a, b);
  }

  /// Win probability for the side whose *internal* value is [v], per mille.
  /// Stockfish reports `cp = 100 * v / a`, so we invert that first.
  static Wdl wdlFromCp(int cp, int material) {
    final (a, b) = _params(material);
    final v = cp * a / 100.0;
    final win = 1 / (1 + math.exp((a - v) / b));
    final loss = 1 / (1 + math.exp((a + v) / b));
    final draw = (1 - win - loss).clamp(0.0, 1.0);
    return Wdl(win, draw, loss);
  }

  /// Expected score for White from a White-perspective [score].
  static Wdl wdlOf(Score score, int material) {
    if (score.isMate) {
      return score.sign > 0 ? const Wdl(1, 0, 0) : const Wdl(0, 0, 1);
    }
    return wdlFromCp(score.cp!, material);
  }
}
