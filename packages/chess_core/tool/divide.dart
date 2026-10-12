import 'package:chess_core/chess_core.dart';
int perft(Position p, int d) { if (d == 0) return 1; if (d == 1) return p.legalMoves.length; var n = 0; for (final m in p.legalMoves) n += perft(p.play(m), d - 1); return n; }
void main(List<String> args) {
  final p = Position.fromFen(args[0]);
  final d = int.parse(args[1]);
  final out = <String>[];
  for (final m in p.legalMoves) out.add('${p.uci(m)}: ${perft(p.play(m), d - 1)}');
  out.sort();
  print(out.join('\n'));
  print('total ${perft(p, d)}');
}
