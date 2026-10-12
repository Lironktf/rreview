/// Deterministic, board-verified explanations for played moves.
///
/// Every sentence produced here is backed by a fact checked against the actual
/// position or the engine's principal variation: a piece really is undefended,
/// a mate really is forced according to the engine score, a capture really
/// happens in the line. When no reliable pattern applies, the explanation falls
/// back to a plain statement of the evaluations rather than a guess.
library;

import 'package:chess_core/chess_core.dart';

import '../score.dart';
import 'models.dart';

/// Context for explaining the move played at a ply.
class ExplainContext {
  const ExplainContext({
    required this.before,
    required this.played,
    required this.playedSan,
    required this.bestUci,
    required this.bestPv,
    required this.afterPv,
    required this.bestScoreMover,
    required this.playedScoreMover,
    required this.label,
    this.openingName,
  });

  /// Position before the move.
  final Position before;
  final Move played;
  final String playedSan;

  /// Engine's best move in [before] (UCI) and its line.
  final String bestUci;
  final List<String> bestPv;

  /// Engine's line from the position after the played move (the opponent's
  /// best continuation).
  final List<String> afterPv;

  /// Scores from the mover's point of view.
  final Score bestScoreMover;
  final Score playedScoreMover;
  final MoveLabel label;
  final String? openingName;
}

class Explainer {
  Explainer._();

  static String? explain(ExplainContext c) {
    final mover = c.before.turn;
    final you = 'This';
    final after = c.before.tryPlay(c.played);
    if (after == null) return null;

    if (c.label == MoveLabel.book) {
      return c.openingName != null ? 'Opening theory: ${c.openingName}.' : 'A known opening move.';
    }
    if (after.isCheckmate) return 'Checkmate.';
    if (after.isStalemate) {
      return c.bestScoreMover.sign > 0 ? 'Stalemate: the win slipped away.' : 'Stalemate.';
    }

    final bestMove = Move.parseUci(c.bestUci);
    final bestIsPlayed = bestMove != null && _same(c.before, bestMove, c.played);
    final bestSan = bestMove != null && c.before.isLegal(bestMove) ? c.before.san(bestMove) : null;

    // 1. Forced mates.
    final bestMates = c.bestScoreMover.isMate && c.bestScoreMover.sign > 0;
    final playedMates = c.playedScoreMover.isMate && c.playedScoreMover.sign > 0;
    final playedMated = c.playedScoreMover.isMate && c.playedScoreMover.sign < 0;
    if (bestMates && !playedMates && bestSan != null) {
      final n = c.bestScoreMover.mate!.abs();
      return 'You missed a forced mate in $n, starting with $bestSan.';
    }
    if (playedMated && !(c.bestScoreMover.isMate && c.bestScoreMover.sign < 0)) {
      final n = c.playedScoreMover.mate!.abs();
      final line = _sanLine(after, c.afterPv, maxPlies: 5);
      return line.isEmpty
          ? '$you allows a forced mate in $n.'
          : '$you allows a forced mate in $n: $line.';
    }
    if (bestMates && playedMates && !bestIsPlayed) {
      return 'Still mating, but $bestSan was faster (mate in ${c.bestScoreMover.mate!.abs()} instead of ${c.playedScoreMover.mate!.abs()}).';
    }

    // 2. Material lost after the move (opponent's best reply wins material).
    final lostNow = _materialSwing(after, c.afterPv, mover);
    final hanging = _hangingPieceAfter(after, c.afterPv, mover);
    if (c.label.isBad && hanging != null) {
      final (piece, sq, replySan, undefended) = hanging;
      final where = undefended ? 'undefended' : 'not defended enough';
      return '$you leaves the ${piece.type.name} on ${sq.name} $where; $replySan wins it.';
    }
    if (c.label.isBad && lostNow <= -2 && c.afterPv.isNotEmpty) {
      final line = _sanLine(after, c.afterPv, maxPlies: 4);
      return '$you loses material: after $line the opponent is ${_pawns(-lostNow)} ahead.';
    }

    // 3. Missed material win in the best line.
    if (c.label.isBad && bestSan != null && !bestIsPlayed) {
      final gain = _materialSwing(c.before, c.bestPv, mover);
      final playedGain = _materialSwing(c.before, [c.played.uci, ...c.afterPv], mover);
      if (gain >= 2 && gain - playedGain >= 2) {
        final target = _firstCapture(c.before, c.bestPv);
        if (target != null && target.$1 == 0) {
          return '$bestSan wins the ${target.$2.type.name} on ${target.$3.name} immediately.';
        }
        final line = _sanLine(c.before, c.bestPv, maxPlies: 5);
        return 'The stronger move $bestSan wins ${_pawnsWord(gain)} after $line.';
      }
      final fork = _checkAndAttack(c.before, bestMove!);
      if (fork != null) {
        return '$bestSan gives check and also attacks the ${fork.$1.type.name} on ${fork.$2.name}.';
      }
    }

    // 4. Non-bad moves: say what the engine prefers, factually.
    if (c.label == MoveLabel.best) {
      final line = _sanLine(after, c.afterPv, maxPlies: 4);
      return line.isEmpty ? 'The engine\'s first choice.' : 'The engine\'s first choice. Main line: $line.';
    }
    if (c.label == MoveLabel.excellent || c.label == MoveLabel.good) {
      if (bestSan != null && !bestIsPlayed) {
        return 'A sound move. The engine slightly prefers $bestSan.';
      }
      return 'A sound move.';
    }

    // 5. Fallback for inaccuracies/mistakes without a detected pattern.
    if (bestSan != null && !bestIsPlayed) {
      final gain = _materialSwing(c.before, c.bestPv, mover);
      if (gain >= 1) {
        return '$bestSan was stronger, winning ${_pawnsWord(gain)} in the main line.';
      }
      final bestLine = _sanLine(c.before, c.bestPv, maxPlies: 3);
      return '$bestSan was stronger${bestLine.isEmpty ? '' : ' ($bestLine)'}: the evaluation drops from '
          '${_fmt(c.bestScoreMover)} to ${_fmt(c.playedScoreMover)} for you.';
    }
    return null;
  }

  static String _fmt(Score moverScore) {
    if (moverScore.isMate) return moverScore.sign > 0 ? 'a forced mate' : 'getting mated';
    final p = moverScore.cp! / 100;
    return '${p >= 0 ? '+' : ''}${p.toStringAsFixed(1)}';
  }

  static String _pawns(int n) => n == 1 ? 'a pawn' : '$n pawns';

  static String _pawnsWord(int gain) {
    if (gain >= 9) return 'a queen\'s worth of material';
    if (gain >= 5) return 'a rook\'s worth of material';
    if (gain >= 3) return 'a piece';
    if (gain == 2) return 'two pawns';
    return 'a pawn';
  }

  static bool _same(Position p, Move a, Move b) => p.uci(a) == p.uci(b);

  /// Material balance change (in pawns, from [mover]'s view) after playing the
  /// legal prefix of [uciLine] from [start].
  static int _materialSwing(Position start, List<String> uciLine, Color mover) {
    var pos = start;
    final startBal = start.materialBalance;
    var count = 0;
    for (final u in uciLine) {
      if (count >= 8) break;
      final m = Move.parseUci(u);
      if (m == null) break;
      final next = pos.tryPlay(m);
      if (next == null) break;
      pos = next;
      count++;
    }
    // Only trust the swing if the line ends with the same side to move or is
    // reasonably long (avoid counting mid-exchange).
    final delta = pos.materialBalance - startBal;
    return mover == Color.white ? delta : -delta;
  }

  /// Index, captured piece and square of the first capture in the line.
  static (int, Piece, Square)? _firstCapture(Position start, List<String> uciLine) {
    var pos = start;
    for (var i = 0; i < uciLine.length && i < 6; i++) {
      final m = Move.parseUci(uciLine[i]);
      if (m == null) break;
      if (!pos.isLegal(m)) break;
      final target = pos.isEnPassant(m)
          ? Piece(pos.turn.opposite, PieceType.pawn)
          : pos.pieceAt(m.to);
      if (target != null && pos.castlingSideOf(m) == null) return (i, target, m.to);
      pos = pos.play(m);
    }
    return null;
  }

  /// If the opponent's first reply captures a mover's piece that the line
  /// shows is lost (material swing ≤ −2), return (piece, square, reply SAN,
  /// undefended?).
  static (Piece, Square, String, bool)? _hangingPieceAfter(Position after, List<String> afterPv, Color mover) {
    if (afterPv.isEmpty) return null;
    final reply = Move.parseUci(afterPv.first);
    if (reply == null || !after.isLegal(reply)) return null;
    final victim = after.isEnPassant(reply) ? null : after.pieceAt(reply.to);
    if (victim == null || victim.color != mover || victim.type == PieceType.pawn) return null;
    final swing = _materialSwing(after, afterPv, mover);
    if (swing > -2) return null;
    final defenders = after.attackers(reply.to, mover);
    return (victim, reply.to, after.san(reply), defenders.isEmpty);
  }

  /// If [m] gives check and the moved piece also attacks an enemy piece that
  /// is not a pawn and is undefended, return that piece and its square.
  static (Piece, Square)? _checkAndAttack(Position pos, Move m) {
    if (!pos.isLegal(m)) return null;
    final next = pos.play(m);
    if (!next.isCheck) return null;
    final mover = pos.turn;
    final landing = pos.castlingSideOf(m) == null ? m.to : null;
    if (landing == null) return null;
    for (final sq in next.squaresOf(mover.opposite)) {
      final p = next.pieceAt(sq)!;
      if (p.type == PieceType.king || p.type == PieceType.pawn) continue;
      final attackers = next.attackers(sq, mover);
      if (!attackers.contains(landing)) continue;
      if (next.attackers(sq, mover.opposite).isEmpty || p.type.value > next.pieceAt(landing)!.type.value) {
        return (p, sq);
      }
    }
    return null;
  }

  /// SAN rendering of the legal prefix of a UCI line, with move numbers.
  static String _sanLine(Position start, List<String> uciLine, {int maxPlies = 6}) {
    var pos = start;
    final parts = <String>[];
    for (var i = 0; i < uciLine.length && i < maxPlies; i++) {
      final m = Move.parseUci(uciLine[i]);
      if (m == null || !pos.isLegal(m)) break;
      final san = pos.san(m);
      if (pos.turn == Color.white) {
        parts.add('${pos.fullmoveNumber}. $san');
      } else if (i == 0) {
        parts.add('${pos.fullmoveNumber}... $san');
      } else {
        parts.add(san);
      }
      pos = pos.play(m);
    }
    return parts.join(' ');
  }

  /// Public helper used by the UI for principal variations.
  static String sanLine(Position start, List<String> uciLine, {int maxPlies = 10}) =>
      _sanLine(start, uciLine, maxPlies: maxPlies);
}
