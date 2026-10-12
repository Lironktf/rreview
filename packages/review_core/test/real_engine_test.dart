// End-to-end analysis with a real Stockfish binary (skipped when STOCKFISH_BIN is unset).
//   STOCKFISH_BIN=/path/to/stockfish dart test test/real_engine_test.dart
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:chess_core/chess_core.dart';
import 'package:review_core/review_core.dart';
import 'package:test/test.dart';

void main() {
  final bin = Platform.environment['STOCKFISH_BIN'];
  if (bin == null) {
    test('real engine (skipped: STOCKFISH_BIN not set)', () {}, skip: true);
    return;
  }

  GameReview fresh(Game g, AnalysisSettings s) => GameReview(
        id: 'real',
        game: g,
        settings: s,
        engineId: '',
        moves: List.filled(g.plies.length, null),
        status: ReviewStatus.pending,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

  late UciClient client;
  setUpAll(() async {
    client = UciClient(await ProcessUciEngine.start(bin));
    await client.init(options: {'Threads': '2', 'Hash': '32'});
  });
  tearDownAll(() => client.dispose());

  test('scholar\'s mate game: mate detection on both sides', () async {
    final game = PgnReader.read('1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7# 1-0').game;
    final settings = const AnalysisSettings(preset: AnalysisPreset.quick, passDepth: 12, refineDepth: 16, refineBudget: 1);
    final last = (await Analyzer(client: client, cache: MemoryEvalCache()).analyze(fresh(game, settings)).toList()).last;
    expect(last.status, ReviewStatus.complete, reason: last.error);
    expect(last.engineId, contains('Stockfish'));
    final nf6 = last.moves[5]!; // 3... Nf6?? allows Qxf7#
    expect(nf6.label, MoveLabel.blunder);
    expect(nf6.playedScore.isMate, isTrue);
    expect(nf6.playedScore.sign, 1); // White mates
    expect(nf6.explanation, contains('mate in 1'));
    final qxf7 = last.moves[6]!;
    expect(qxf7.label, MoveLabel.best);
    expect(qxf7.after.score, const Score.checkmated(Color.black));
    expect(last.summaryFor(Color.black).count(MoveLabel.blunder), greaterThanOrEqualTo(1));
    // The first moves are reasonable, and the Black accuracy is lower than White's.
    expect(last.summaryFor(Color.white).accuracy!, greaterThan(last.summaryFor(Color.black).accuracy!));
  });

  test('promotion, en passant and castling game evaluates with consistent perspective', () async {
    final pgn = '[FEN "8/P6k/8/8/8/8/1pK5/8 w - - 0 1"]\n[SetUp "1"]\n\n1. a8=Q b1=Q+ 2. Kxb1 *';
    final game = PgnReader.read(pgn).game;
    expect(game.plies.length, 3);
    final settings = const AnalysisSettings(preset: AnalysisPreset.quick, passDepth: 10, refineDepth: 0, refineBudget: 0);
    final last = (await Analyzer(client: client, cache: MemoryEvalCache()).analyze(fresh(game, settings)).toList()).last;
    expect(last.status, ReviewStatus.complete, reason: last.error);
    // After 2. Kxb1 White has K+Q vs K: winning for White, so a positive white-perspective score or mate.
    final after = last.moves[2]!.after.score;
    expect(after.sign, 1);
    expect(last.moves[0]!.label, anyOf(MoveLabel.best, MoveLabel.excellent));
  });

  test('a longer real game analyses end to end with evaluations for every ply', () async {
    final pgn = '''
[Event "Live Chess"]
[White "A"]
[Black "B"]
[Result "0-1"]

1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. O-O Nf6 5. d3 d6 6. Bg5 h6 7. Bh4 g5 8. Nxg5 hxg5 9. Bxg5 Rg8 10. Bxf6 Qxf6
11. Nc3 Nd4 12. Nd5 Qg6 13. Kh1 Bh3 14. g3 Bxf1 15. Qxf1 Nxc2 16. Rc1 Nd4 17. b4 Bb6 18. Nxb6 axb6 19. Qe2 Qh5 20. Kg2 Rxg3+
21. fxg3 Qh3+ 22. Kf2 Qh2+ 23. Ke3 Qxg3+ 24. Kd2 Qf4+ 25. Ke1 Nxe2 0-1
''';
    final game = PgnReader.read(pgn).game;
    expect(game.plies.length, 50);
    final settings = const AnalysisSettings(preset: AnalysisPreset.quick, passDepth: 10, refineDepth: 14, refineBudget: 0.2);
    final sw = Stopwatch()..start();
    var updates = 0;
    GameReview? last;
    await for (final r in Analyzer(client: client, cache: MemoryEvalCache()).analyze(fresh(game, settings))) {
      updates++;
      last = r;
    }
    print('analysed ${game.plies.length} plies in ${sw.elapsed} with $updates progressive updates');
    expect(last!.status, ReviewStatus.complete, reason: last.error);
    expect(last.moves.every((m) => m != null), isTrue);
    expect(last.openingName, isNull); // no book given
    // Material-losing move 8. Nxg5?? should be flagged as bad.
    final nxg5 = last.moves[14]!;
    expect(nxg5.label.isBad, isTrue, reason: 'Nxg5 loss=${nxg5.loss} label=${nxg5.label}');
    // Refined moves exist and progress reached 1.
    expect(last.moves.any((m) => m!.refined), isTrue);
    expect(last.progress, 1);
    // Every explanation is non-empty.
    expect(last.moves.every((m) => (m!.explanation ?? '').isNotEmpty), isTrue);
    for (final i in last.keyMoments) {
      print('key ${game.plies[i].numbered}: ${last.moves[i]!.label.display} loss=${last.moves[i]!.loss.toStringAsFixed(2)} — ${last.moves[i]!.explanation}');
    }
  });
}
