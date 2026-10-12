import 'package:chess_core/chess_core.dart';
import 'package:test/test.dart';

int perft(Position p, int depth) {
  if (depth == 0) return 1;
  final moves = p.legalMoves;
  if (depth == 1) return moves.length;
  var n = 0;
  for (final m in moves) {
    n += perft(p.play(m), depth - 1);
  }
  return n;
}

void main() {
  // Standard perft suite (https://www.chessprogramming.org/Perft_Results).
  final cases = <(String, String, List<int>)>[
    ('start', startFen, [20, 400, 8902, 197281]),
    ('kiwipete', 'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1', [48, 2039, 97862]),
    ('pos3', '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1', [14, 191, 2812, 43238]),
    ('pos4', 'r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1', [6, 264, 9467]),
    ('pos4-mirror', 'r2q1rk1/pP1p2pp/Q4n2/bbp1p3/Np6/1B3NBn/pPPP1PPP/R3K2R b KQ - 0 1', [6, 264, 9467]),
    ('pos5', 'rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8', [44, 1486, 62379]),
    ('pos6', 'r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10', [46, 2079, 89890]),
    // Chess960 positions; counts verified with Stockfish 19 (`go perft`).
    ('960-1', '2nnrbkr/p1qppppp/8/1ppb4/6PP/3PP3/1PP1P3/BQNNRBKR w HEhe - 1 9', [18, 693, 13696]),
    ('960-2', 'qbbnnrkr/2pp2pp/p7/1p2pp2/8/P3PP2/1PP3PP/QBBNNRKR w HFhf - 0 9', [19, 505, 10953]),
    ('960-3', 'b1q1rrkb/pppppppp/3nn3/8/P7/1PPP4/4PPPP/BQNNRKRB w GE - 1 9', [20, 479, 10471]),
    ('960-4', '1nbbnrkr/p1p1ppp1/3p4/1p3P1p/3Pq2P/8/PPP1P1P1/QNBBNRKR w HFhf - 0 9', [28, 1120, 31058]),
    ('960-5', 'rnkbbqrn/pppppppp/8/8/8/8/PPPPPPPP/RNKBBQRN w GAga - 0 1', [19, 361, 7775]),
    ('960-6', 'nrkrbbqn/pppppppp/8/8/8/8/PPPPPPPP/NRKRBBQN w DBdb - 0 1', [18, 324, 6674]),
  ];
  for (final (name, fen, counts) in cases) {
    test('perft $name', () {
      final p = Position.fromFen(fen);
      for (var d = 1; d <= counts.length; d++) {
        expect(perft(p, d), counts[d - 1], reason: 'depth $d');
      }
    });
  }

  test('fen round trip', () {
    for (final (_, fen, _) in cases) {
      final p = Position.fromFen(fen);
      expect(Position.fromFen(p.fen).fen, p.fen);
    }
  });
}
