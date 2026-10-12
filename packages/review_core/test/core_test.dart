import 'dart:convert';
import 'dart:io';

import 'package:chess_core/chess_core.dart';
import 'package:review_core/review_core.dart';
import 'package:test/test.dart';

void main() {
  group('Score', () {
    test('normalises side-to-move scores to White', () {
      expect(Score.fromUci(cp: 50, sideToMove: Color.white), const Score.cp(50));
      expect(Score.fromUci(cp: 50, sideToMove: Color.black), const Score.cp(-50));
      expect(Score.fromUci(mate: 3, sideToMove: Color.black), const Score.mate(-3));
      expect(Score.fromUci(mate: -2, sideToMove: Color.black), const Score.mate(2));
    });
    test('display and mate handling', () {
      expect(const Score.cp(34).display, '+0.3');
      expect(const Score.cp(-120).display, '-1.2');
      expect(const Score.cp(3).display, '0.0');
      expect(const Score.mate(3).display, 'M3');
      expect(const Score.mate(-1).display, '-M1');
      expect(const Score.checkmated(Color.white).display, '#');
      expect(const Score.checkmated(Color.white).sign, -1);
      expect(const Score.checkmated(Color.black).sign, 1);
      expect(const Score.mate(-4).clampedPawns(), -6.0);
    });
    test('json round trip', () {
      for (final s in [const Score.cp(-7), const Score.mate(2), const Score.checkmated(Color.black)]) {
        expect(Score.fromJson(s.toJson()), s);
      }
    });
  });

  group('WinModel', () {
    test('matches Stockfish behaviour: 100cp is about 50% win chance, 0cp is level', () {
      final mid = WinModel.materialOf(Position.initial());
      final w0 = WinModel.wdlFromCp(0, mid);
      expect(w0.win, closeTo(w0.loss, 1e-9));
      expect(w0.expectedScore, closeTo(0.5, 1e-9));
      final w100 = WinModel.wdlFromCp(100, mid);
      expect(w100.win, closeTo(0.5, 0.01));
      final w300 = WinModel.wdlFromCp(300, mid);
      expect(w300.win, greaterThan(0.9));
      expect(WinModel.wdlOf(const Score.mate(2), mid).expectedScore, 1.0);
      expect(WinModel.wdlOf(const Score.checkmated(Color.white), mid).expectedScore, 0.0);
    });
    test('WDL per mille flips for Black to move', () {
      final w = Wdl.fromPerMille((700, 200, 100), sideToMove: Color.black);
      expect(w.win, closeTo(0.1, 1e-9));
      expect(w.loss, closeTo(0.7, 1e-9));
    });
  });

  group('UciLine', () {
    test('parses a full Stockfish info line with wdl', () {
      final l = UciLine.parse(
          'info depth 12 seldepth 18 multipv 1 score cp 35 wdl 120 850 30 nodes 123456 nps 1000000 hashfull 10 tbhits 0 time 123 pv e2e4 e7e5 g1f3')!;
      expect(l.depth, 12);
      expect(l.cp, 35);
      expect(l.wdl, (120, 850, 30));
      expect(l.pv, ['e2e4', 'e7e5', 'g1f3']);
      expect(l.nodes, 123456);
      expect(l.isLowerBound, isFalse);
    });
    test('parses mate scores and bounds', () {
      final l = UciLine.parse('info depth 20 score mate -3 lowerbound nodes 1 time 1 pv a1a2')!;
      expect(l.mate, -3);
      expect(l.cp, isNull);
      expect(l.isLowerBound, isTrue);
    });
    test('ignores string and currmove lines', () {
      expect(UciLine.parse('info string NNUE evaluation using nn.nnue'), isNull);
      expect(UciLine.parse('info depth 5 currmove e2e4 currmovenumber 1'), isNull);
    });
  });

  group('classify', () {
    MoveOutcome o(double before, double after, {bool best = false, Score bs = const Score.cp(0), Score ps = const Score.cp(0)}) =>
        MoveOutcome(expectedBefore: before, expectedAfter: after, playedIsEngineBest: best, bestScore: bs, playedScore: ps, inBook: false);
    test('thresholds', () {
      expect(classify(o(0.5, 0.5, best: true)), MoveLabel.best);
      expect(classify(o(0.5, 0.497)), MoveLabel.best);
      expect(classify(o(0.5, 0.49)), MoveLabel.excellent);
      expect(classify(o(0.5, 0.46)), MoveLabel.good);
      expect(classify(o(0.5, 0.42)), MoveLabel.inaccuracy);
      expect(classify(o(0.5, 0.35)), MoveLabel.mistake);
      expect(classify(o(0.5, 0.20)), MoveLabel.blunder);
    });
    test('missed win when a winning position becomes unclear', () {
      expect(classify(o(0.9, 0.55)), MoveLabel.missedWin);
      expect(classify(o(0.9, 0.2)), MoveLabel.blunder);
    });
    test('mate handling', () {
      expect(classify(o(1.0, 0.95, bs: const Score.mate(2), ps: const Score.cp(900))), MoveLabel.mistake);
      expect(classify(o(1.0, 0.7, bs: const Score.mate(2), ps: const Score.cp(150))), MoveLabel.missedWin);
      expect(classify(o(0.5, 0.0, bs: const Score.cp(0), ps: const Score.mate(-3))), MoveLabel.blunder);
      expect(classify(o(1.0, 1.0, bs: const Score.mate(2), ps: const Score.mate(5))), MoveLabel.excellent);
      // Already lost: getting mated faster is not "a blunder" by the mate rule, only by loss.
      expect(classify(o(0.0, 0.0, bs: const Score.mate(-2), ps: const Score.mate(-1))), MoveLabel.best);
    });
    test('book wins over everything', () {
      expect(classify(MoveOutcome(expectedBefore: 0.5, expectedAfter: 0.1, playedIsEngineBest: false, bestScore: const Score.cp(0), playedScore: const Score.cp(0), inBook: true)), MoveLabel.book);
    });
  });

  group('accuracy', () {
    test('per move', () {
      expect(moveAccuracy(0), 100);
      expect(moveAccuracy(0.05), closeTo(81.1, 0.2));
      expect(moveAccuracy(0.10), closeTo(65.7, 0.2));
      expect(moveAccuracy(0.30), closeTo(28.4, 0.2));
      expect(moveAccuracy(1.0), lessThan(2));
    });
    test('game accuracy punishes a blunder more than the mean', () {
      final clean = List.filled(30, 100.0);
      expect(gameAccuracy(clean), closeTo(100, 1e-9));
      final oneBlunder = [...List.filled(29, 100.0), 10.0];
      expect(gameAccuracy(oneBlunder), lessThan(97));
      expect(gameAccuracy(oneBlunder), greaterThan(80));
    });
  });

  group('GameLink', () {
    test('chess.com shapes', () {
      for (final u in [
        'https://www.chess.com/game/live/97872578329',
        'https://www.chess.com/live/game/97872578329',
        'https://www.chess.com/game/97872578329',
        'https://www.chess.com/analysis/game/live/97872578329/review',
        'https://www.chess.com/de/live/game/97872578329?username=x',
        'Check out my game! https://www.chess.com/game/live/97872578329 so good',
      ]) {
        final l = GameLink.find(u);
        expect(l, isNotNull, reason: u);
        expect(l!.site, GameSite.chesscom);
        expect(l.id, '97872578329');
        expect(l.chesscomType, ChesscomGameType.live);
      }
      expect(GameLink.find('https://www.chess.com/game/daily/781647993')!.chesscomType, ChesscomGameType.daily);
      expect(GameLink.find('https://www.chess.com/daily/game/781647993')!.chesscomType, ChesscomGameType.daily);
      expect(GameLink.find('https://www.chess.com/game/computer/123')!.chesscomType, ChesscomGameType.computer);
      expect(GameLink.find('https://www.chess.com/member/hikaru'), isNull);
      expect(GameLink.find('https://www.chess.com/play/online'), isNull);
    });
    test('lichess shapes', () {
      for (final u in [
        'https://lichess.org/tkJnElwm',
        'https://lichess.org/tkJnElwm/black',
        'https://lichess.org/tkJnElwmAbCd',
        'https://lichess.org/embed/game/tkJnElwm',
        'game: https://lichess.org/tkJnElwm#12',
      ]) {
        final l = GameLink.find(u);
        expect(l, isNotNull, reason: u);
        expect(l!.site, GameSite.lichess);
        expect(l.id, 'tkJnElwm');
      }
      expect(GameLink.find('https://lichess.org/training'), isNull);
      expect(GameLink.find('https://lichess.org/@/thibault'), isNull);
      expect(GameLink.find('https://lichess.org/study/abcdefgh/ijklmnop'), isNull);
      expect(GameLink.find('hello world'), isNull);
    });
  });

  group('OpeningBook', () {
    test('precomputed JSON asset loads and finds the Italian', () {
      final file = File('../../app/assets/openings/book.json');
      if (!file.existsSync()) return;
      final book = OpeningBook.fromJson(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
      expect(book.size, greaterThan(3000));
      final g = Game.fromMoves('e4 e5 Nf3 Nc6 Bc4 Bc5 O-O Nf6 d3 d6'.split(' '));
      final hit = book.lookup(g)!;
      expect(hit.$1.name, contains('Italian'));
      expect(book.bookPlies(g).length, greaterThanOrEqualTo(6));
    });
    final book = OpeningBook.fromTsv([
      'eco\tname\tpgn\nC20\tKing\'s Pawn Game\t1. e4 e5\nC50\tItalian Game\t1. e4 e5 2. Nf3 Nc6 3. Bc4\nB20\tSicilian Defense\t1. e4 c5\n'
    ]);
    test('finds the longest matching line and book plies', () {
      final g = Game.fromMoves('e4 e5 Nf3 Nc6 Bc4 Bc5 c3'.split(' '));
      final hit = book.lookup(g)!;
      expect(hit.$1.name, 'Italian Game');
      expect(hit.$2, 5);
      expect(book.bookPlies(g), {0, 1, 2, 3, 4});
      final g2 = Game.fromMoves('d4 d5'.split(' '));
      expect(book.lookup(g2), isNull);
      expect(book.bookPlies(g2), isEmpty);
      final g3 = Game.fromMoves('e4 e5 Nf3 Nf6'.split(' '));
      expect(book.bookPlies(g3), {0, 1, 2}); // Nf3 is a prefix of the Italian line; Nf6 is not
    });
  });
}
