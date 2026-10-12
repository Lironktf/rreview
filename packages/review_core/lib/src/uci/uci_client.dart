/// A UCI client that serialises searches and parses `info` / `bestmove` lines.
library;

import 'dart:async';

import 'uci_engine.dart';

/// One principal variation as reported by the engine, side-to-move relative.
class UciLine {
  const UciLine({
    required this.multipv,
    required this.depth,
    required this.selDepth,
    required this.cp,
    required this.mate,
    required this.wdl,
    required this.pv,
    required this.nodes,
    required this.timeMs,
    required this.isLowerBound,
    required this.isUpperBound,
  });

  final int multipv;
  final int depth;
  final int selDepth;

  /// Centipawns from the side to move, null for mate scores.
  final int? cp;

  /// Mate distance in moves from the side to move (negative = being mated).
  final int? mate;

  /// Win/draw/loss per mille from the side to move, when UCI_ShowWDL is on.
  final (int, int, int)? wdl;
  final List<String> pv;
  final int nodes;
  final int timeMs;
  final bool isLowerBound;
  final bool isUpperBound;

  String? get firstMove => pv.isEmpty ? null : pv.first;

  static UciLine? parse(String line) {
    if (!line.startsWith('info ')) return null;
    final tokens = line.split(' ');
    int? depth, selDepth, multipv = 1, cp, mate, nodes, time;
    (int, int, int)? wdl;
    var lower = false, upper = false;
    List<String> pv = const [];
    for (var i = 1; i < tokens.length; i++) {
      switch (tokens[i]) {
        case 'depth':
          depth = int.tryParse(tokens[++i]);
        case 'seldepth':
          selDepth = int.tryParse(tokens[++i]);
        case 'multipv':
          multipv = int.tryParse(tokens[++i]) ?? 1;
        case 'nodes':
          nodes = int.tryParse(tokens[++i]);
        case 'time':
          time = int.tryParse(tokens[++i]);
        case 'score':
          final kind = tokens[++i];
          final value = int.tryParse(tokens[++i]);
          if (kind == 'cp') cp = value;
          if (kind == 'mate') mate = value;
          while (i + 1 < tokens.length && (tokens[i + 1] == 'lowerbound' || tokens[i + 1] == 'upperbound')) {
            i++;
            if (tokens[i] == 'lowerbound') lower = true;
            if (tokens[i] == 'upperbound') upper = true;
          }
        case 'wdl':
          final w = int.tryParse(tokens[++i]);
          final d = int.tryParse(tokens[++i]);
          final l = int.tryParse(tokens[++i]);
          if (w != null && d != null && l != null) wdl = (w, d, l);
        case 'pv':
          pv = tokens.sublist(i + 1);
          i = tokens.length;
        case 'string':
          return null;
        default:
          break;
      }
    }
    if (depth == null || (cp == null && mate == null)) return null;
    return UciLine(
      multipv: multipv ?? 1,
      depth: depth,
      selDepth: selDepth ?? depth,
      cp: cp,
      mate: mate,
      wdl: wdl,
      pv: pv,
      nodes: nodes ?? 0,
      timeMs: time ?? 0,
      isLowerBound: lower,
      isUpperBound: upper,
    );
  }
}

/// Final result of one search.
class SearchResult {
  const SearchResult({required this.bestMove, required this.ponder, required this.lines});

  /// `(none)` when there are no legal moves.
  final String bestMove;
  final String? ponder;

  /// Deepest complete line per multipv index (1-based), side-to-move relative.
  final Map<int, UciLine> lines;

  UciLine? get principal => lines[1];
}

/// Search limits for one `go` command.
class SearchLimits {
  const SearchLimits({this.depth, this.nodes, this.movetimeMs, this.searchMoves = const [], this.multiPv = 1});
  final int? depth;
  final int? nodes;
  final int? movetimeMs;
  final List<String> searchMoves;
  final int multiPv;

  String get key => 'd${depth ?? '-'}n${nodes ?? '-'}t${movetimeMs ?? '-'}m$multiPv';
}

class UciClient {
  UciClient(this.engine) {
    _sub = engine.lines.listen(_onLine);
  }

  final UciEngine engine;
  late final StreamSubscription<String> _sub;
  final _idle = <Completer<void>>[];
  Completer<SearchResult>? _searchDone;
  Completer<void>? _readyDone;
  Completer<void>? _uciDone;
  final Map<int, UciLine> _current = {};
  void Function(UciLine line)? _onInfo;
  final Map<String, String> _options = {};
  String engineName = '';
  bool _searching = false;
  bool _disposed = false;

  /// Available option names reported by `uci`.
  final Set<String> optionNames = {};

  String get engineId => engineName.isEmpty ? 'unknown' : engineName;

  Future<void> init({Map<String, String> options = const {}}) async {
    _uciDone = Completer<void>();
    engine.send('uci');
    await _uciDone!.future.timeout(const Duration(seconds: 15));
    for (final e in options.entries) {
      await setOption(e.key, e.value);
    }
    await isReady();
  }

  Future<void> setOption(String name, String value) async {
    if (_options[name] == value) return;
    _options[name] = value;
    engine.send('setoption name $name value $value');
  }

  Future<void> isReady() async {
    _readyDone = Completer<void>();
    engine.send('isready');
    await _readyDone!.future.timeout(const Duration(seconds: 60));
  }

  void newGame() => engine.send('ucinewgame');

  /// Runs one search. Only one search may be active at a time; callers queue.
  Future<SearchResult> search(String fen, SearchLimits limits, {void Function(UciLine)? onInfo}) async {
    if (_disposed) throw StateError('client disposed');
    while (_searching) {
      final c = Completer<void>();
      _idle.add(c);
      await c.future;
    }
    _searching = true;
    try {
      await setOption('MultiPV', '${limits.multiPv}');
      _current.clear();
      _onInfo = onInfo;
      _searchDone = Completer<SearchResult>();
      engine.send('position fen $fen');
      final sb = StringBuffer('go');
      if (limits.depth != null) sb.write(' depth ${limits.depth}');
      if (limits.nodes != null) sb.write(' nodes ${limits.nodes}');
      if (limits.movetimeMs != null) sb.write(' movetime ${limits.movetimeMs}');
      if (limits.searchMoves.isNotEmpty) sb.write(' searchmoves ${limits.searchMoves.join(' ')}');
      engine.send(sb.toString());
      return await _searchDone!.future;
    } finally {
      _searching = false;
      _onInfo = null;
      if (_idle.isNotEmpty) _idle.removeAt(0).complete();
    }
  }

  /// Stops the current search (the pending [search] future completes with the
  /// best result so far).
  void stop() {
    if (_searching) engine.send('stop');
  }

  void _onLine(String line) {
    if (line == 'uciok') {
      _uciDone?.complete();
      return;
    }
    if (line == 'readyok') {
      _readyDone?.complete();
      return;
    }
    if (line.startsWith('id name ')) {
      engineName = line.substring(8).trim();
      return;
    }
    if (line.startsWith('option name ')) {
      final m = RegExp(r'^option name (.+?) type ').firstMatch(line);
      if (m != null) optionNames.add(m.group(1)!);
      return;
    }
    if (line.startsWith('bestmove')) {
      final parts = line.split(' ');
      final best = parts.length > 1 ? parts[1] : '(none)';
      final ponder = parts.length > 3 && parts[2] == 'ponder' ? parts[3] : null;
      final done = _searchDone;
      _searchDone = null;
      if (done != null && !done.isCompleted) {
        done.complete(SearchResult(bestMove: best, ponder: ponder, lines: Map.of(_current)));
      }
      return;
    }
    final info = UciLine.parse(line);
    if (info != null) {
      // Keep the deepest exact line for each multipv slot; bounds are hints.
      if (info.pv.isNotEmpty && !info.isLowerBound && !info.isUpperBound) {
        _current[info.multipv] = info;
        _onInfo?.call(info);
      } else if (info.pv.isNotEmpty && !_current.containsKey(info.multipv)) {
        _current[info.multipv] = info;
      }
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _sub.cancel();
    await engine.dispose();
  }
}
