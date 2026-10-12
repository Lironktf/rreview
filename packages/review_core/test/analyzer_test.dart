import 'package:chess_core/chess_core.dart';
import 'package:review_core/review_core.dart';
import 'package:test/test.dart';

import 'fake_engine.dart';

String k(String fen) => FakeEngine.key(fen);

GameReview newReview(Game g, AnalysisSettings s) => GameReview(
      id: 't',
      game: g,
      settings: s,
      engineId: '',
      moves: List.filled(g.plies.length, null),
      status: ReviewStatus.pending,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  test('blunder into mate and missed mate are classified with explanations', () async {
    // 1. f3 e5 2. g4 Qh4#  — 2. g4 allows mate in 1; Black plays it.
    final game = PgnReader.read('1. f3 e5 2. g4 Qh4# 0-1').game;
    final p0 = game.positionAt(0), p1 = game.positionAt(1), p2 = game.positionAt(2), p3 = game.positionAt(3);
    final script = <String, List<String>>{
      k(p0.fen): ['info depth 12 score cp 30 wdl 300 500 200 nodes 10 time 1 pv e2e4 e7e5', 'bestmove e2e4'],
      k(p1.fen): ['info depth 12 score cp -40 wdl 150 500 350 nodes 10 time 1 pv e7e5 e2e4', 'bestmove e7e5'],
      k(p2.fen): ['info depth 12 score cp -50 wdl 150 500 350 nodes 10 time 1 pv e2e4 d7d5', 'bestmove e2e4'],
      k(p3.fen): ['info depth 12 score mate 1 wdl 1000 0 0 nodes 10 time 1 pv d8h4', 'bestmove d8h4'],
      // searchmoves refinement of 2. g4 at depth 16: mated in 1 (from White's view mate -1)
      '${k(p2.fen)}|g2g4': ['info depth 16 score mate -1 wdl 0 0 1000 nodes 10 time 1 pv g2g4 d8h4', 'bestmove g2g4'],
    };
    // Deeper searches reuse the same script (depth is in the info line; analyzer accepts any).
    final engine = FakeEngine(script);
    final client = UciClient(engine);
    await client.init();
    final analyzer = Analyzer(client: client, cache: MemoryEvalCache());
    final reviews = await analyzer
        .analyze(newReview(game, const AnalysisSettings(preset: AnalysisPreset.quick, passDepth: 12, refineDepth: 16, refineBudget: 1)))
        .toList();
    final last = reviews.last;
    expect(last.status, ReviewStatus.complete, reason: last.error);
    expect(last.moves.every((m) => m != null), isTrue);
    final g4 = last.moves[2]!;
    expect(g4.label, MoveLabel.blunder);
    expect(g4.explanation, contains('forced mate in 1'));
    expect(g4.bestSan, 'e4');
    expect(g4.before.score, const Score.cp(-50));
    // The mating move itself is best.
    final qh4 = last.moves[3]!;
    expect(qh4.label, MoveLabel.best);
    expect(qh4.after.score, const Score.checkmated(Color.white));
    expect(qh4.explanation, 'Checkmate.');
    // Summaries: Black accuracy higher than White's.
    expect(last.summaryFor(Color.black).accuracy!, greaterThan(last.summaryFor(Color.white).accuracy!));
    expect(last.summaryFor(Color.white).count(MoveLabel.blunder), 1);
    expect(last.keyMoments, contains(2));
    // Progressive updates were emitted.
    expect(reviews.length, greaterThan(4));
    expect(reviews.first.status, ReviewStatus.running);
    await client.dispose();
  });

  test('black perspective: a Black blunder is a loss for Black, not White', () async {
    // 1. e4 e5 2. Nf3 f6?? (weak) — scripted evals: before f6 = -0.2 (white), after = +1.5
    final game = PgnReader.read('1. e4 e5 2. Nf3 f6 *').game;
    final fens = List.generate(5, (i) => game.positionAt(i).fen);
    final script = <String, List<String>>{
      k(fens[0]): ['info depth 12 score cp 20 wdl 250 600 150 nodes 1 time 1 pv e2e4', 'bestmove e2e4'],
      k(fens[1]): ['info depth 12 score cp -20 wdl 150 600 250 nodes 1 time 1 pv e7e5', 'bestmove e7e5'],
      k(fens[2]): ['info depth 12 score cp 20 wdl 250 600 150 nodes 1 time 1 pv g1f3', 'bestmove g1f3'],
      k(fens[3]): ['info depth 12 score cp -20 wdl 150 600 250 nodes 1 time 1 pv b8c6', 'bestmove b8c6'],
      k(fens[4]): ['info depth 12 score cp 150 wdl 650 300 50 nodes 1 time 1 pv f3e5 f6e5 d1h5', 'bestmove f3e5'],
    };
    final client = UciClient(FakeEngine(script));
    await client.init();
    final analyzer = Analyzer(client: client, cache: MemoryEvalCache());
    final last = (await analyzer
            .analyze(newReview(game, const AnalysisSettings(preset: AnalysisPreset.quick, passDepth: 12, refineDepth: 0, refineBudget: 0)))
            .toList())
        .last;
    expect(last.status, ReviewStatus.complete);
    final f6 = last.moves[3]!;
    expect(f6.loss, closeTo(0.45 - 0.2, 1e-9)); // Black's expected score 0.55 -> 0.20
    expect(f6.label, MoveLabel.blunder);
    expect(f6.bestSan, 'Nc6');
    // White's moves were all engine-best: no loss.
    expect(last.moves[0]!.label, MoveLabel.best);
    expect(last.moves[2]!.label, MoveLabel.best);
    expect(last.moves[0]!.loss, 0);
    await client.dispose();
  });

  test('cancellation pauses and resume continues from the cache', () async {
    final game = PgnReader.read('1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 *').game;
    final script = <String, List<String>>{};
    for (var i = 0; i <= 6; i++) {
      final p = game.positionAt(i);
      final best = p.legalMoves.first;
      final sign = p.turn == Color.white ? 1 : -1;
      script[k(p.fen)] = ['info depth 12 score cp ${10 * sign} wdl 300 400 300 nodes 1 time 1 pv ${p.uci(best)}', 'bestmove ${p.uci(best)}'];
    }
    final engine = FakeEngine(script);
    final client = UciClient(engine);
    await client.init();
    final cache = MemoryEvalCache();
    final analyzer = Analyzer(client: client, cache: cache);
    final token = CancelToken();
    final settings = const AnalysisSettings(preset: AnalysisPreset.quick, passDepth: 12, refineDepth: 0, refineBudget: 0);
    GameReview? paused;
    await for (final r in analyzer.analyze(newReview(game, settings), cancel: token)) {
      paused = r;
      if (r.analysedCount >= 2) token.cancel();
    }
    expect(paused!.status, ReviewStatus.paused);
    expect(paused.analysedCount, greaterThanOrEqualTo(2));
    expect(paused.analysedCount, lessThan(6));
    final sentBefore = engine.sent.where((c) => c.startsWith('go')).length;
    final resumed = (await analyzer.analyze(paused).toList()).last;
    expect(resumed.status, ReviewStatus.complete);
    expect(resumed.moves.every((m) => m != null), isTrue);
    final sentAfter = engine.sent.where((c) => c.startsWith('go')).length;
    // Only the positions not yet evaluated were searched again.
    expect(sentAfter - sentBefore, lessThan(7));
    await client.dispose();
  });

  test('review json round trip', () async {
    final game = PgnReader.read('1. e4 e5 *').game;
    final script = <String, List<String>>{};
    for (var i = 0; i <= 2; i++) {
      final p = game.positionAt(i);
      final best = p.legalMoves.first;
      script[k(p.fen)] = ['info depth 12 score cp 10 wdl 300 400 300 nodes 1 time 1 pv ${p.uci(best)}', 'bestmove ${p.uci(best)}'];
    }
    final client = UciClient(FakeEngine(script));
    await client.init();
    final last = (await Analyzer(client: client, cache: MemoryEvalCache())
            .analyze(newReview(game, const AnalysisSettings(preset: AnalysisPreset.quick, passDepth: 12, refineDepth: 0, refineBudget: 0)))
            .toList())
        .last;
    final j = GameReview.fromJson(last.toJson());
    expect(j.moves.length, 2);
    expect(j.moves[0]!.before.score, last.moves[0]!.before.score);
    expect(j.status, ReviewStatus.complete);
    expect(j.game.plies.length, 2);
    await client.dispose();
  });
}
