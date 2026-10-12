/// Opening book built from the lichess-org/chess-openings dataset (CC0).
library;

import 'package:chess_core/chess_core.dart';

class OpeningEntry {
  const OpeningEntry(this.eco, this.name, this.plyCount);
  final String eco;
  final String name;
  final int plyCount;
}

class OpeningBook {
  OpeningBook._(this._byLine);

  /// Keyed by space-separated UCI moves from the standard start position.
  final Map<String, OpeningEntry> _byLine;

  int get size => _byLine.length;

  /// Parses one or more TSV files with columns `eco name pgn`.
  static OpeningBook fromTsv(Iterable<String> tsvFiles) {
    final map = <String, OpeningEntry>{};
    for (final tsv in tsvFiles) {
      for (final line in tsv.split('\n')) {
        if (line.isEmpty || line.startsWith('eco\t')) continue;
        final cols = line.split('\t');
        if (cols.length < 3) continue;
        final tokens = cols[2]
            .split(RegExp(r'\s+'))
            .where((t) => t.isNotEmpty && !RegExp(r'^\d+\.$').hasMatch(t))
            .toList();
        try {
          final g = Game.fromMoves(tokens);
          final key = g.plies.map((p) => p.move.uci).join(' ');
          map[key] = OpeningEntry(cols[0], cols[1], g.plies.length);
        } on ChessException {
          continue;
        }
      }
    }
    return OpeningBook._(map);
  }

  /// Loads the precomputed asset produced by `tool/build_book.dart`
  /// ({"<uci moves>": ["ECO", "Name"]}).
  static OpeningBook fromJson(Map<String, dynamic> json) {
    final map = <String, OpeningEntry>{};
    for (final e in json.entries) {
      final v = (e.value as List).cast<String>();
      map[e.key] = OpeningEntry(v[0], v[1], e.key.split(' ').length);
    }
    return OpeningBook._(map);
  }

  /// Longest prefix of [game] that is a known opening line.
  /// Returns (entry, plies-in-book) or null when the game starts elsewhere.
  (OpeningEntry, int)? lookup(Game game) {
    if (game.startsFromCustomPosition) return null;
    OpeningEntry? best;
    var depth = 0;
    final sb = StringBuffer();
    for (var i = 0; i < game.plies.length && i < 40; i++) {
      if (i > 0) sb.write(' ');
      sb.write(game.plies[i].move.uci);
      final e = _byLine[sb.toString()];
      if (e != null) {
        best = e;
        depth = i + 1;
      }
    }
    if (best == null) return null;
    return (best, depth);
  }

  /// Whether the first [ply]+1 moves of the game are all in the book.
  /// A move is "book" when the sequence up to and including it is a known line
  /// prefix of some opening in the dataset.
  Set<int> bookPlies(Game game) {
    if (game.startsFromCustomPosition) return const {};
    final out = <int>{};
    final sb = StringBuffer();
    for (var i = 0; i < game.plies.length && i < 40; i++) {
      if (i > 0) sb.write(' ');
      sb.write(game.plies[i].move.uci);
      final key = sb.toString();
      if (_byLine.containsKey(key) || _hasPrefix(key)) {
        out.add(i);
      } else {
        break;
      }
    }
    return out;
  }

  // Prefix check without an index: openings are short, so scan lazily.
  late final Set<String> _prefixes = () {
    final s = <String>{};
    for (final k in _byLine.keys) {
      final parts = k.split(' ');
      for (var i = 1; i <= parts.length; i++) {
        s.add(parts.sublist(0, i).join(' '));
      }
    }
    return s;
  }();

  bool _hasPrefix(String key) => _prefixes.contains(key);
}
