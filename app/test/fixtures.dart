import 'dart:io';

import 'package:chess_core/chess_core.dart';
import 'package:rreview/services/analysis_controller.dart';
import 'package:rreview/services/app_scope.dart';
import 'package:rreview/services/engine_service.dart';
import 'package:rreview/services/import_service.dart';
import 'package:rreview/services/review_store.dart';
import 'package:rreview/services/settings_service.dart';
import 'package:review_core/review_core.dart';

/// A completed review built from scripted evaluations (no engine needed).
GameReview sampleReview() {
  const pgn = '''
[Event "Live Chess"]
[Site "Chess.com"]
[Date "2026.10.11"]
[White "liron"]
[Black "opponent"]
[Result "0-1"]
[WhiteElo "1512"]
[BlackElo "1498"]
[TimeControl "600"]
[Link "https://www.chess.com/game/live/123456789"]

1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. O-O Nf6 5. d3 d6 6. Bg5 h6 7. Bh4 g5 8. Nxg5 hxg5 9. Bxg5 Rg8 10. Bxf6 Qxf6 0-1
''';
  final game = PgnReader.read(pgn).game;
  final evals = <double>[0.3, 0.2, 0.3, 0.2, 0.4, 0.3, 0.3, 0.2, 0.3, 0.1, 0.2, -0.1, 0.0, -0.2, -0.1, -4.9, -4.8, -5.0, -5.2, -5.1, -5.3];
  final moves = <MoveReview?>[];
  for (var i = 0; i < game.plies.length; i++) {
    final before = _eval(game.positionAt(i), evals[i], i);
    final after = _eval(game.positionAt(i + 1), evals[i + 1], i + 1);
    final mover = game.plies[i].color;
    final eb = mover == Color.white ? before.wdl.expectedScore : 1 - before.wdl.expectedScore;
    final ea = mover == Color.white ? after.wdl.expectedScore : 1 - after.wdl.expectedScore;
    final isBest = i != 14;
    final loss = isBest ? 0.0 : (eb - ea).clamp(0.0, 1.0);
    final label = i < 6 ? MoveLabel.book : isBest ? (i.isEven ? MoveLabel.best : MoveLabel.excellent) : MoveLabel.blunder;
    moves.add(MoveReview(
      ply: i,
      before: before,
      after: after,
      playedScore: after.score,
      loss: loss,
      label: label,
      bestSan: i == 14 ? 'Bg3' : game.plies[i].san,
      bestPvSan: i == 14 ? ['Bg3', 'Bg4', 'Nbd2'] : [game.plies[i].san],
      explanation: i == 14
          ? 'Bg3 was stronger (8. Bg3 Bg4 9. Nbd2): the evaluation drops from -0.1 to -4.9 for you.'
          : (label == MoveLabel.book ? 'Opening theory: Italian Game.' : 'The engine\'s first choice.'),
      accuracy: moveAccuracy(loss),
      refined: i == 14,
    ));
  }
  return GameReview(
    id: 'sample',
    game: game,
    settings: AnalysisSettings.standard,
    engineId: 'Stockfish 19',
    moves: moves,
    status: ReviewStatus.complete,
    createdAt: DateTime(2026, 10, 11, 12),
    updatedAt: DateTime(2026, 10, 11, 12, 5),
    openingName: 'Italian Game: Giuoco Piano',
    openingEco: 'C50',
    bookPlies: 6,
    sourceUrl: 'https://www.chess.com/game/live/123456789',
    progress: 1,
  );
}

PositionEval _eval(Position p, double pawns, int i) {
  final score = Score.cp((pawns * 100).round());
  final best = p.legalMoves.isEmpty ? '(none)' : p.uci(p.legalMoves.first);
  return PositionEval(
    fen: p.fen,
    depth: 16,
    score: score,
    wdl: WinModel.wdlOf(score, WinModel.materialOf(p)),
    bestMove: i == 14 ? 'h4g3' : best,
    pv: i == 14 ? ['h4g3', 'c8g4', 'b1d2'] : [best],
    nodes: 1000,
  );
}

Future<AppServices> testServices(Directory tmp, {List<GameReview> reviews = const []}) async {
  final settings = await AppSettings.load(File('${tmp.path}/settings.json'));
  final engine = EngineService(supportDir: tmp);
  final store = ReviewStore(Directory('${tmp.path}/docs'));
  final cache = FileEvalCache(File('${tmp.path}/evals.json'));
  final analysis = AnalysisController(engine: engine, store: store, cache: cache);
  for (final r in reviews) {
    await analysis.add(r, analyze: false);
  }
  final importer = ImportService(controller: analysis, settings: settings);
  return AppServices(settings: settings, engine: engine, analysis: analysis, importer: importer);
}
