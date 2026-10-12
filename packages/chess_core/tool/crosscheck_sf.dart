// Cross-checks chess_core's legal move generation against Stockfish on random
// games (standard and Chess960). Usage:
//   dart run tool/crosscheck_sf.dart <stockfish-binary> [games] [maxPlies]
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:chess_core/chess_core.dart';

const starts = [
  startFen,
  'rnkbbqrn/pppppppp/8/8/8/8/PPPPPPPP/RNKBBQRN w GAga - 0 1',
  'nrkrbbqn/pppppppp/8/8/8/8/PPPPPPPP/NRKRBBQN w DBdb - 0 1',
  'bbqnnrkr/pppppppp/8/8/8/8/PPPPPPPP/BBQNNRKR w HFhf - 0 1',
  'rkqbbnnr/pppppppp/8/8/8/8/PPPPPPPP/RKQBBNNR w HAha - 0 1',
  'nqbrnkrb/pppppppp/8/8/8/8/PPPPPPPP/NQBRNKRB w GDgd - 0 1',
  'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
  '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1',
];

Future<void> main(List<String> args) async {
  final sfPath = args[0];
  final games = args.length > 1 ? int.parse(args[1]) : 40;
  final maxPlies = args.length > 2 ? int.parse(args[2]) : 120;
  final sf = await Process.start(sfPath, []);
  final lines = sf.stdout.transform(utf8.decoder).transform(const LineSplitter()).asBroadcastStream();
  sf.stdin.writeln('setoption name UCI_Chess960 value true');
  final rng = Random(42);
  var positions = 0;
  var mismatches = 0;
  for (var g = 0; g < games; g++) {
    var pos = Position.fromFen(starts[g % starts.length], chess960: true);
    for (var ply = 0; ply < maxPlies; ply++) {
      final ours = pos.legalMoves.map(pos.uci).toSet();
      sf.stdin.writeln('position fen ${pos.fen}');
      sf.stdin.writeln('go perft 1');
      final theirs = <String>{};
      await for (final l in lines) {
        if (l.startsWith('Nodes searched')) break;
        final m = RegExp(r'^([a-h][1-8][a-h][1-8][nbrq]?): 1$').firstMatch(l);
        if (m != null) theirs.add(m.group(1)!);
        if (l.contains('CRITICAL ERROR')) {
          stderr.writeln('SF rejected ${pos.fen}: $l');
          break;
        }
      }
      positions++;
      if (ours.length != theirs.length || !ours.containsAll(theirs)) {
        mismatches++;
        print('MISMATCH at ${pos.fen}');
        print('  ours-only: ${ours.difference(theirs)}');
        print('  sf-only:   ${theirs.difference(ours)}');
      }
      if (ours.isEmpty) break;
      // Also check SAN round-trips.
      for (final m in pos.legalMoves) {
        final s = pos.san(m);
        final back = pos.parseSan(s);
        if (back != m) {
          mismatches++;
          print('SAN ROUNDTRIP FAIL ${pos.fen} ${m.uci} -> $s -> $back');
        }
      }
      final list = pos.legalMoves;
      pos = pos.play(list[rng.nextInt(list.length)]);
      if (pos.halfmoveClock > 150) break;
    }
  }
  sf.stdin.writeln('quit');
  print('checked $positions positions, $mismatches mismatches');
  exit(mismatches == 0 ? 0 : 1);
}
