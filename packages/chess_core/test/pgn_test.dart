import 'package:chess_core/chess_core.dart';
import 'package:test/test.dart';

const chesscomPgn = '''
[Event "Live Chess"]
[Site "Chess.com"]
[Date "2024.01.01"]
[Round "-"]
[White "Hikaru"]
[Black "Gravity_Chess"]
[Result "1-0"]
[CurrentPosition "8/5k2/8/5p1p/4b3/R7/PP1B1K1P/8 b - -"]
[Timezone "UTC"]
[ECO "B23"]
[WhiteElo "3236"]
[BlackElo "2867"]
[TimeControl "180"]
[Termination "Hikaru won by resignation"]
[Link "https://www.chess.com/game/live/97872578329"]

1. e4 {[%clk 0:03:00]} 1... c5 {[%clk 0:03:00]} 2. Nc3 {[%clk 0:02:59.9]} 2... g6 {[%clk 0:02:57.5]} 3. f4 {[%clk 0:02:59.8]} 3... Bg7 {[%clk 0:02:57.1]} 1-0
''';

const lichessPgn = '''
[Event "Rated Blitz game"]
[Site "https://lichess.org/tkJnElwm"]
[Date "2026.10.11"]
[White "A"]
[Black "B"]
[Result "0-1"]
[Variant "Standard"]
[TimeControl "300+0"]
[Opening "Scandinavian Defense"]

1. e4 { [%eval 0.2] [%clk 0:05:00] } 1... d5 { [%clk 0:05:00] } 2. exd5 { [%clk 0:04:58] } 2... Qxd5 { [%clk 0:04:57] } 3. Nc3 Qa5 (3... Qe5+ 4. Be2) 4. d4 Nf6 \$1 0-1
''';

void main() {
  test('reads a Chess.com PGN with clocks and renumbered black moves', () {
    final g = PgnReader.read(chesscomPgn);
    expect(g.problems, isEmpty);
    expect(g.game.plies, hasLength(6));
    expect(g.game.white, 'Hikaru');
    expect(g.game.result, GameResult.whiteWins);
    expect(g.game.plies[2].clock, const Duration(minutes: 2, seconds: 59, milliseconds: 900));
    expect(g.game.plies[0].clock, const Duration(minutes: 3));
    expect(g.game.plies[0].comment, isNull);
    expect(g.game.plies.last.san, 'Bg7');
    expect(g.game.link, 'https://www.chess.com/game/live/97872578329');
  });

  test('reads a Lichess PGN with evals, variations and NAGs', () {
    final g = PgnReader.read(lichessPgn);
    expect(g.problems, isEmpty);
    expect(g.game.plies.map((p) => p.san).join(' '), 'e4 d5 exd5 Qxd5 Nc3 Qa5 d4 Nf6');
    expect(g.game.plies.last.nags, [1]);
    expect(g.game.result, GameResult.blackWins);
    expect(g.game.plies[0].clock, const Duration(minutes: 5));
  });

  test('handles bare movetext without headers and glyphs', () {
    final g = PgnReader.read('1.e4 e5 2.Nf3! Nc6?! 3.Bb5 a6 *');
    expect(g.problems, isEmpty);
    expect(g.game.plies, hasLength(6));
    expect(g.game.plies[2].nags, [1]);
    expect(g.game.plies[3].nags, [6]);
    expect(g.game.result, GameResult.unknown);
  });

  test('truncates at an illegal move with a precise message', () {
    final g = PgnReader.read('1. e4 e5 2. Nf3 Nc6 3. Bb5 Nf3 4. d4');
    expect(g.truncated, isTrue);
    expect(g.game.plies, hasLength(5));
    expect(g.problems.first.ply, 5);
    expect(g.problems.first.message, contains('3... Nf3 is not a legal move'));
  });

  test('illegal move while in check is explained', () {
    final g = PgnReader.read('1. e4 e5 2. Qh5 Nc6 3. Qxf7+ Nf6');
    expect(g.truncated, isTrue);
    expect(g.problems.first.message, contains('in check'));
  });

  test('garbage token is reported', () {
    final g = PgnReader.read('1. e4 e5 2. hello');
    expect(g.truncated, isTrue);
    expect(g.problems.first.message, contains('is not a chess move'));
  });

  test('non-PGN text throws', () {
    expect(() => PgnReader.read('Hello, this is just a sentence.'), throwsA(isA<PgnException>()));
    expect(() => PgnReader.read(''), throwsA(isA<PgnException>()));
    expect(PgnReader.looksLikePgn('Check out my game https://www.chess.com/game/live/1'), isFalse);
    expect(PgnReader.looksLikePgn('[Event "x"]\n\n1. e4'), isTrue);
    expect(PgnReader.looksLikePgn('1. e4 e5 2. Nf3'), isTrue);
  });

  test('FEN start position via SetUp/FEN headers', () {
    final g = PgnReader.read('[SetUp "1"]\n[FEN "8/P6k/8/8/8/8/8/K7 w - - 0 1"]\n\n1. a8=Q Kg7 2. Qa7+ *');
    expect(g.problems, isEmpty);
    expect(g.game.startsFromCustomPosition, isTrue);
    expect(g.game.plies[0].san, 'a8=Q');
    expect(g.game.plies[0].moveNumber, 1);
    expect(g.game.positionAt(0).fen, '8/P6k/8/8/8/8/8/K7 w - - 0 1');
  });

  test('invalid FEN header falls back with a problem', () {
    final g = PgnReader.read('[SetUp "1"]\n[FEN "nonsense"]\n\n1. e4 *');
    expect(g.problems.first.message, contains('FEN header is invalid'));
    expect(g.game.plies, hasLength(1));
  });

  test('Chess960 game with Shredder castling', () {
    final g = PgnReader.read('[Variant "Chess960"]\n[SetUp "1"]\n[FEN "rnkbbqrn/pppppppp/8/8/8/8/PPPPPPPP/RNKBBQRN w GAga - 0 1"]\n\n1. c4 c5 2. Nc3 Nc6 3. Bc2 Bc7 4. O-O-O *');
    expect(g.problems, isEmpty, reason: g.problems.toString());
    expect(g.game.chess960, isTrue);
    expect(g.game.plies.last.san, 'O-O-O');
    expect(g.game.positionAt(7).fen, startsWith('r1k1bqrn/ppbppppp/2n5/2p5/2P5/2N5/PPBPPPPP/2KRBQRN b kq'));
    expect(g.game.positionAt(6).uci(g.game.plies.last.move), 'c1a1');
  });

  test('unsupported variant is flagged, not replayed', () {
    final g = PgnReader.read('[Variant "Crazyhouse"]\n\n1. e4 e5 2. Nf3 Nc6 *');
    expect(g.unsupportedVariant, 'Crazyhouse');
    expect(g.isUsable, isFalse);
  });

  test('multiple games are split', () {
    final games = PgnReader.readAll('[White "a"]\n\n1. e4 e5 1/2-1/2\n\n[White "b"]\n\n1. d4 d5 *\n');
    expect(games, hasLength(2));
    expect(games[0].game.white, 'a');
    expect(games[1].game.plies.first.san, 'd4');
  });

  test('null moves cut the game', () {
    final g = PgnReader.read('1. e4 -- 2. d4 *');
    expect(g.truncated, isTrue);
    expect(g.game.plies, hasLength(1));
  });

  test('result header disagreement is reported and movetext wins', () {
    final g = PgnReader.read('[Result "1-0"]\n\n1. e4 e5 0-1');
    expect(g.game.result, GameResult.blackWins);
    expect(g.problems.single.message, contains('disagrees'));
  });

  test('PGN export round-trips', () {
    final g = PgnReader.read(chesscomPgn).game;
    final again = PgnReader.read(g.toPgn()).game;
    expect(again.plies.map((p) => p.san).toList(), g.plies.map((p) => p.san).toList());
    expect(again.plies[2].clock, g.plies[2].clock);
    expect(again.result, g.result);
  });

  test('JSON round-trips', () {
    final g = PgnReader.read(lichessPgn).game;
    final j = Game.fromJson(g.toJson());
    expect(j.plies.length, g.plies.length);
    expect(j.plies.last.nags, [1]);
    expect(j.headers['Opening'], 'Scandinavian Defense');
  });

  test('a game with a forced mate ends in checkmate', () {
    final g = PgnReader.read('1. f3 e5 2. g4 Qh4# 0-1');
    expect(g.game.finalPosition.isCheckmate, isTrue);
    expect(g.game.finalStateDescription, 'checkmate');
    expect(g.game.plies.last.san, 'Qh4#');
  });
}
