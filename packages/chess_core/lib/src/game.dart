/// A replayed game: headers, plies with SAN/UCI/FEN, result and metadata.
library;

import 'position.dart';
import 'san.dart';
import 'types.dart';

/// Result of a game as written in PGN.
enum GameResult {
  whiteWins('1-0'),
  blackWins('0-1'),
  draw('1/2-1/2'),
  unknown('*');

  const GameResult(this.pgn);
  final String pgn;

  static GameResult fromPgn(String s) => switch (s.trim()) {
        '1-0' => GameResult.whiteWins,
        '0-1' => GameResult.blackWins,
        '1/2-1/2' || '½-½' || '1/2' => GameResult.draw,
        _ => GameResult.unknown,
      };

  Color? get winner => switch (this) {
        GameResult.whiteWins => Color.white,
        GameResult.blackWins => Color.black,
        _ => null,
      };
}

/// One half-move of the game.
class Ply {
  const Ply({
    required this.index,
    required this.move,
    required this.san,
    required this.fenBefore,
    required this.fenAfter,
    required this.color,
    this.comment,
    this.clock,
    this.nags = const [],
  });

  /// 0-based ply index (0 = White's first move in a standard game).
  final int index;
  final Move move;
  final String san;
  final String fenBefore;
  final String fenAfter;
  final Color color;

  /// Comment text with `[%clk …]`/`[%eval …]` tags removed, if any.
  final String? comment;

  /// Clock remaining after the move, from a `[%clk h:mm:ss]` tag.
  final Duration? clock;
  final List<int> nags;

  /// Move number as shown in notation (1 for both 1. e4 and 1... e5 in a
  /// standard game; derived from the position before the move).
  int get moveNumber => int.parse(fenBefore.split(' ')[5]);

  /// `1. e4` / `1... e5` style label.
  String get numbered => color == Color.white ? '$moveNumber. $san' : '$moveNumber... $san';

  Map<String, dynamic> toJson() => {
        'i': index,
        'uci': move.uci,
        'san': san,
        'fb': fenBefore,
        'fa': fenAfter,
        'c': color.index,
        if (comment != null) 'cm': comment,
        if (clock != null) 'clk': clock!.inMilliseconds,
        if (nags.isNotEmpty) 'nags': nags,
      };

  static Ply fromJson(Map<String, dynamic> j) => Ply(
        index: j['i'] as int,
        move: Move.parseUci(j['uci'] as String)!,
        san: j['san'] as String,
        fenBefore: j['fb'] as String,
        fenAfter: j['fa'] as String,
        color: Color.values[j['c'] as int],
        comment: j['cm'] as String?,
        clock: j['clk'] == null ? null : Duration(milliseconds: j['clk'] as int),
        nags: (j['nags'] as List?)?.cast<int>() ?? const [],
      );
}

/// A fully replayed, legal game.
class Game {
  Game({
    required this.headers,
    required this.initialFen,
    required this.plies,
    required this.result,
    this.chess960 = false,
  });

  final Map<String, String> headers;
  final String initialFen;
  final List<Ply> plies;
  final GameResult result;
  final bool chess960;

  String? header(String key) {
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == key.toLowerCase()) return e.value;
    }
    return null;
  }

  String get white => header('White') ?? 'White';
  String get black => header('Black') ?? 'Black';
  int? get whiteElo => int.tryParse(header('WhiteElo') ?? '');
  int? get blackElo => int.tryParse(header('BlackElo') ?? '');
  String? get event => header('Event');
  String? get site => header('Site');
  String? get date => header('UTCDate') ?? header('Date');
  String? get timeControl => header('TimeControl');
  String? get termination => header('Termination');
  String? get link => header('Link');
  String? get eco => header('ECO');
  String? get openingName => header('Opening');
  bool get startsFromCustomPosition => initialFen != startFen;

  /// Position before ply [i] (i == plies.length gives the final position).
  Position positionAt(int i) {
    if (i == 0) return Position.fromFen(initialFen, chess960: chess960);
    return Position.fromFen(plies[i - 1].fenAfter, chess960: chess960);
  }

  Position get finalPosition => positionAt(plies.length);

  /// Whether the final position is checkmate / stalemate / etc.
  String? get finalStateDescription {
    final p = finalPosition;
    if (p.isCheckmate) return 'checkmate';
    if (p.isStalemate) return 'stalemate';
    if (p.isInsufficientMaterial) return 'insufficient material';
    if (p.isFiftyMoveRule) return 'fifty-move rule';
    if (isThreefoldRepetitionAt(plies.length)) return 'threefold repetition';
    return null;
  }

  /// Whether the position after [plyCount] plies has occurred three times.
  bool isThreefoldRepetitionAt(int plyCount) {
    if (plyCount < 8) return false;
    final key = positionAt(plyCount).repetitionKey;
    var count = 0;
    for (var i = plyCount; i >= 0; i--) {
      if (positionAt(i).repetitionKey == key) count++;
      if (count >= 3) return true;
    }
    return false;
  }

  /// Exports the game as PGN (main line only, with clock comments preserved).
  String toPgn({bool includeClocks = true}) {
    final sb = StringBuffer();
    final order = ['Event', 'Site', 'Date', 'Round', 'White', 'Black', 'Result'];
    final written = <String>{};
    for (final k in order) {
      final v = header(k);
      if (v != null) {
        sb.writeln('[$k "${_escape(v)}"]');
        written.add(k.toLowerCase());
      }
    }
    if (header('Result') == null) sb.writeln('[Result "${result.pgn}"]');
    if (startsFromCustomPosition && header('FEN') == null) {
      sb.writeln('[SetUp "1"]');
      sb.writeln('[FEN "$initialFen"]');
    }
    for (final e in headers.entries) {
      if (!written.contains(e.key.toLowerCase())) {
        sb.writeln('[${e.key} "${_escape(e.value)}"]');
      }
    }
    sb.writeln();
    final line = StringBuffer();
    var first = true;
    for (final p in plies) {
      if (p.color == Color.white || first) {
        line.write(p.color == Color.white ? '${p.moveNumber}. ' : '${p.moveNumber}... ');
      }
      first = false;
      line.write(p.san);
      final tags = <String>[];
      if (includeClocks && p.clock != null) tags.add('[%clk ${_formatClock(p.clock!)}]');
      if (p.comment != null && p.comment!.isNotEmpty) tags.add(p.comment!);
      if (tags.isNotEmpty) line.write(' {${tags.join(' ')}}');
      line.write(' ');
    }
    line.write(result.pgn);
    sb.writeln(_wrap(line.toString(), 80));
    return sb.toString();
  }

  static String _escape(String s) => s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

  static String _formatClock(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    final tenths = (d.inMilliseconds % 1000) ~/ 100;
    final base = '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return tenths == 0 ? base : '$base.$tenths';
  }

  static String _wrap(String text, int width) {
    final words = text.split(' ');
    final sb = StringBuffer();
    var col = 0;
    for (final w in words) {
      if (col > 0 && col + 1 + w.length > width) {
        sb.write('\n');
        col = 0;
      } else if (col > 0) {
        sb.write(' ');
        col++;
      }
      sb.write(w);
      col += w.length;
    }
    return sb.toString();
  }

  Map<String, dynamic> toJson() => {
        'headers': headers,
        'initialFen': initialFen,
        'plies': plies.map((p) => p.toJson()).toList(),
        'result': result.pgn,
        'chess960': chess960,
      };

  static Game fromJson(Map<String, dynamic> j) => Game(
        headers: (j['headers'] as Map).cast<String, String>(),
        initialFen: j['initialFen'] as String,
        plies: (j['plies'] as List).map((e) => Ply.fromJson((e as Map).cast<String, dynamic>())).toList(),
        result: GameResult.fromPgn(j['result'] as String),
        chess960: j['chess960'] as bool? ?? false,
      );

  /// Builds a game from a start position and a list of moves (UCI or SAN).
  static Game fromMoves(Iterable<String> moves,
      {String initialFen = startFen, Map<String, String> headers = const {}, GameResult result = GameResult.unknown, bool chess960 = false}) {
    var pos = Position.fromFen(initialFen, chess960: chess960);
    final plies = <Ply>[];
    var i = 0;
    for (final token in moves) {
      final m = pos.parseSan(token);
      if (m == null) throw ChessException('Illegal or unparsable move "$token" at ply $i');
      final next = pos.play(m);
      plies.add(Ply(
        index: i,
        move: m,
        san: pos.san(m),
        fenBefore: pos.fen,
        fenAfter: next.fen,
        color: pos.turn,
      ));
      pos = next;
      i++;
    }
    return Game(headers: Map.of(headers), initialFen: initialFen, plies: plies, result: result, chess960: chess960);
  }
}
