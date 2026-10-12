/// The two-pass analysis pipeline. See docs/ARCHITECTURE.md.
library;

import 'dart:async';

import 'package:chess_core/chess_core.dart';

import '../book.dart';
import '../score.dart';
import '../uci/uci_client.dart';
import 'accuracy.dart';
import 'cache.dart';
import 'classify.dart';
import 'explain.dart';
import 'models.dart';

class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class Analyzer {
  Analyzer({
    required this.client,
    required this.cache,
    this.book,
    this.thresholds = ClassificationThresholds.standard,
  });

  final UciClient client;
  final EvalCache cache;
  final OpeningBook? book;
  final ClassificationThresholds thresholds;

  /// Analyses [review]'s game, emitting progressively updated reviews. The
  /// last emitted value has status complete, paused (cancelled) or failed.
  Stream<GameReview> analyze(GameReview review, {CancelToken? cancel}) async* {
    final token = cancel ?? CancelToken();
    final game = review.game;
    final settings = review.settings;
    final n = game.plies.length;
    try {
      await client.setOption('Threads', '${settings.threads}');
      await client.setOption('Hash', '${settings.hashMb}');
      await client.setOption('UCI_ShowWDL', 'true');
      if (client.optionNames.contains('UCI_Chess960')) {
        await client.setOption('UCI_Chess960', game.chess960 ? 'true' : 'false');
      }
      client.newGame();
      await client.isReady();
    } catch (e) {
      yield review.copyWith(status: ReviewStatus.failed, error: 'Engine did not start: $e');
      return;
    }

    final engineId = client.engineId;
    final positions = List<Position>.generate(n + 1, game.positionAt);
    final evals = List<PositionEval?>.filled(n + 1, null);
    final moves = List<MoveReview?>.from(review.moves.length == n ? review.moves : List.filled(n, null));

    // Opening book.
    final bookSet = book?.bookPlies(game) ?? const <int>{};
    String? openingName = review.openingName;
    String? openingEco = review.openingEco;
    final opening = book?.lookup(game);
    if (opening != null) {
      openingName = opening.$1.name;
      openingEco = opening.$1.eco;
    }

    var current = review.copyWith(
      status: ReviewStatus.running,
      engineId: engineId,
      openingName: openingName,
      openingEco: openingEco,
      bookPlies: bookSet.length,
      clearError: true,
      phase: 'Starting analysis',
    );
    yield current;

    // Reuse prior results (resume) where the settings match.
    for (var i = 0; i < n; i++) {
      final m = moves[i];
      if (m != null && m.before.depth >= settings.passDepth) {
        evals[i] = m.before;
        evals[i + 1] = m.after;
      } else {
        moves[i] = null;
      }
    }

    Future<PositionEval> evaluate(int i, int depth) async {
      final cached = evals[i];
      if (cached != null && cached.depth >= depth) return cached;
      final e = await _evaluate(positions[i], depth, engineId);
      evals[i] = e;
      return e;
    }

    MoveReview build(int i, {Score? playedOverride, bool refined = false}) {
      final before = evals[i]!;
      final after = evals[i + 1]!;
      final ply = game.plies[i];
      final pos = positions[i];
      final mover = ply.color;
      final playedScoreWhite = playedOverride ?? after.score;
      final moverSign = mover == Color.white ? 1 : -1;
      final eBeforeWhite = before.wdl.expectedScore;
      final eAfterWhite = playedOverride != null
          ? WinModel.wdlOf(playedOverride, WinModel.materialOf(pos)).expectedScore
          : after.wdl.expectedScore;
      final eBefore = mover == Color.white ? eBeforeWhite : 1 - eBeforeWhite;
      final eAfter = mover == Color.white ? eAfterWhite : 1 - eAfterWhite;
      final bestMoveUci = before.bestMove;
      final playedUci = pos.uci(ply.move);
      final isBest = bestMoveUci == playedUci;
      final bestMover = moverSign > 0 ? before.score : before.score.negated;
      final playedMover = moverSign > 0 ? playedScoreWhite : playedScoreWhite.negated;
      final outcome = MoveOutcome(
        expectedBefore: eBefore,
        expectedAfter: isBest ? eBefore : eAfter,
        playedIsEngineBest: isBest,
        bestScore: bestMover,
        playedScore: isBest ? bestMover : playedMover,
        inBook: bookSet.contains(i),
      );
      final label = classify(outcome, t: thresholds);
      final loss = label == MoveLabel.book ? 0.0 : outcome.loss;
      final bestMove = Move.parseUci(bestMoveUci);
      final bestSan = bestMove != null && pos.isLegal(bestMove) ? pos.san(bestMove) : (isBest ? ply.san : '—');
      final bestPvSan = _pvToSan(pos, before.pv);
      final explanation = Explainer.explain(ExplainContext(
        before: pos,
        played: ply.move,
        playedSan: ply.san,
        bestUci: bestMoveUci,
        bestPv: before.pv,
        afterPv: after.pv,
        bestScoreMover: bestMover,
        playedScoreMover: isBest ? bestMover : playedMover,
        label: label,
        openingName: openingName,
      ));
      return MoveReview(
        ply: i,
        before: before,
        after: after,
        playedScore: playedScoreWhite,
        loss: loss,
        label: label,
        bestSan: bestSan,
        bestPvSan: bestPvSan,
        explanation: explanation,
        accuracy: moveAccuracy(loss),
        refined: refined,
      );
    }

    // ---- Pass 1
    try {
      for (var i = 0; i <= n; i++) {
        if (token.isCancelled) {
          yield current.copyWith(moves: moves, status: ReviewStatus.paused, phase: 'Paused');
          return;
        }
        if (evals[i] == null || evals[i]!.depth < settings.passDepth) {
          await evaluate(i, settings.passDepth);
        }
        if (i > 0 && moves[i - 1] == null) {
          moves[i - 1] = build(i - 1);
        }
        current = current.copyWith(
          moves: List.of(moves),
          progress: 0.7 * (i + 1) / (n + 1),
          phase: i < n ? 'Analysing move ${i ~/ 2 + 1} of ${(n + 1) ~/ 2}' : 'Checking key moments',
        );
        yield current;
      }

      // ---- Pass 2: refine flagged plies.
      if (settings.refineDepth > settings.passDepth && n > 0) {
        final flagged = <(int, double)>[];
        for (var i = 0; i < n; i++) {
          final m = moves[i]!;
          var priority = m.loss;
          if (m.label == MoveLabel.book) continue;
          final swing = (m.after.score.clampedPawns(10) - m.before.score.clampedPawns(10)).abs();
          if (swing >= 1.0) priority += 0.05 * swing;
          if (m.before.score.isMate || m.after.score.isMate) priority += 0.1;
          if (priority >= thresholds.good) flagged.add((i, priority));
        }
        flagged.sort((a, b) => b.$2.compareTo(a.$2));
        final budget = (n * settings.refineBudget).ceil().clamp(0, n);
        final chosen = flagged.take(budget).map((e) => e.$1).toList()..sort();
        var done = 0;
        for (final i in chosen) {
          if (token.isCancelled) {
            yield current.copyWith(moves: moves, status: ReviewStatus.paused, phase: 'Paused');
            return;
          }
          await evaluate(i, settings.refineDepth);
          await evaluate(i + 1, settings.refineDepth);
          Score? playedOverride;
          final pos = positions[i];
          final playedUci = pos.uci(game.plies[i].move);
          if (evals[i]!.bestMove != playedUci && !evals[i]!.isTerminal) {
            final r = await _searchMove(pos, playedUci, settings.refineDepth);
            if (r != null) playedOverride = r;
          }
          moves[i] = build(i, playedOverride: playedOverride, refined: true);
          if (i > 0) moves[i - 1] = build(i - 1, refined: moves[i - 1]!.refined);
          if (i + 1 < n) moves[i + 1] = build(i + 1, refined: moves[i + 1]!.refined);
          done++;
          current = current.copyWith(
            moves: List.of(moves),
            progress: 0.7 + 0.3 * done / chosen.length,
            phase: 'Looking deeper at key moments ($done of ${chosen.length})',
          );
          yield current;
        }
      }
      yield current.copyWith(moves: List.of(moves), status: ReviewStatus.complete, progress: 1, phase: 'Complete');
    } catch (e) {
      yield current.copyWith(moves: moves, status: ReviewStatus.failed, error: '$e', phase: 'Failed');
    }
  }

  Future<PositionEval> _evaluate(Position pos, int depth, String engineId) async {
    final key = evalCacheKey(pos.fen, engineId, depth);
    final cached = await cache.get(key);
    if (cached != null && cached.depth >= depth) return cached;
    if (pos.legalMoves.isEmpty) {
      final e = pos.isCheckmate
          ? PositionEval(
              fen: pos.fen, depth: depth, score: Score.checkmated(pos.turn),
              wdl: pos.turn == Color.white ? const Wdl(0, 0, 1) : const Wdl(1, 0, 0),
              bestMove: '(none)', pv: const [], nodes: 0)
          : PositionEval(
              fen: pos.fen, depth: depth, score: const Score.cp(0), wdl: const Wdl(0, 1, 0),
              bestMove: '(none)', pv: const [], nodes: 0);
      await cache.put(key, e);
      return e;
    }
    final result = await client.search(pos.fen, SearchLimits(depth: depth));
    final line = result.principal;
    final e = _toEval(pos, depth, result.bestMove, line);
    await cache.put(key, e);
    return e;
  }

  /// Score of one specific move at the given depth (White's perspective).
  Future<Score?> _searchMove(Position pos, String uci, int depth) async {
    final result = await client.search(pos.fen, SearchLimits(depth: depth, searchMoves: [uci]));
    final line = result.principal;
    if (line == null) return null;
    return Score.fromUci(cp: line.cp, mate: line.mate, sideToMove: pos.turn);
  }

  PositionEval _toEval(Position pos, int depth, String bestMove, UciLine? line) {
    if (line == null) {
      // Engine gave a bestmove without info (should not happen); neutral eval.
      return PositionEval(fen: pos.fen, depth: depth, score: const Score.cp(0), wdl: const Wdl(0, 1, 0),
          bestMove: bestMove, pv: [bestMove], nodes: 0);
    }
    final score = Score.fromUci(cp: line.cp, mate: line.mate, sideToMove: pos.turn);
    final wdl = line.wdl != null
        ? Wdl.fromPerMille(line.wdl!, sideToMove: pos.turn)
        : WinModel.wdlOf(score, WinModel.materialOf(pos));
    return PositionEval(
      fen: pos.fen,
      depth: line.depth,
      score: score,
      wdl: wdl,
      bestMove: bestMove == '(none)' ? (line.firstMove ?? bestMove) : bestMove,
      pv: line.pv.isEmpty ? [bestMove] : line.pv,
      nodes: line.nodes,
    );
  }

  static List<String> _pvToSan(Position pos, List<String> pv) {
    final out = <String>[];
    var p = pos;
    for (final u in pv.take(10)) {
      final m = Move.parseUci(u);
      if (m == null || !p.isLegal(m)) break;
      out.add(p.san(m));
      p = p.play(m);
    }
    return out;
  }
}
