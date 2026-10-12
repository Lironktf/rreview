// Precomputes the opening book from the lichess chess-openings TSV files into a
// compact JSON asset: {"<uci moves>": ["ECO", "Name"]}. Run from packages/review_core:
//   dart run tool/build_book.dart ../../app/assets/openings ../../app/assets/openings/book.json
import 'dart:convert';
import 'dart:io';

import 'package:chess_core/chess_core.dart';

void main(List<String> args) {
  final dir = Directory(args[0]);
  final out = File(args[1]);
  final sw = Stopwatch()..start();
  final map = <String, List<String>>{};
  var lines = 0, skipped = 0;
  for (final name in ['a', 'b', 'c', 'd', 'e']) {
    final text = File('${dir.path}/$name.tsv').readAsStringSync();
    for (final line in text.split('\n')) {
      if (line.isEmpty || line.startsWith('eco\t')) continue;
      final cols = line.split('\t');
      if (cols.length < 3) continue;
      lines++;
      final tokens = cols[2].split(RegExp(r'\s+')).where((t) => t.isNotEmpty && !RegExp(r'^\d+\.$').hasMatch(t));
      var pos = Position.initial();
      final uci = <String>[];
      var ok = true;
      for (final t in tokens) {
        final m = pos.parseSan(t);
        if (m == null) {
          ok = false;
          break;
        }
        uci.add(pos.uci(m));
        pos = pos.play(m);
      }
      if (!ok) {
        skipped++;
        continue;
      }
      map[uci.join(' ')] = [cols[0], cols[1]];
    }
  }
  out.writeAsStringSync(jsonEncode(map));
  print('book: $lines lines, ${map.length} entries, $skipped skipped, ${out.lengthSync()} bytes, ${sw.elapsed}');
}
