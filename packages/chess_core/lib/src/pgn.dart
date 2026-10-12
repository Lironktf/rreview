/// Tolerant PGN reader.
///
/// Reads one or more games from PGN text, replays the main line with full
/// legality checking, and reports problems (illegal moves, unsupported
/// variants, truncation) instead of silently dropping information.
library;

import 'game.dart';
import 'position.dart';
import 'san.dart';
import 'types.dart';

/// A non-fatal problem found while importing a game.
class PgnProblem {
  const PgnProblem(this.message, {this.ply, this.token});
  final String message;

  /// Ply index at which the problem occurred, if applicable.
  final int? ply;
  final String? token;

  @override
  String toString() => ply == null ? message : '$message (ply $ply, "$token")';
}

/// Thrown when the text contains no recognisable game at all.
class PgnException implements Exception {
  PgnException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Variants whose rules differ from standard chess and cannot be analysed.
const unsupportedVariants = {
  'crazyhouse', 'antichess', 'atomic', 'horde', 'king of the hill', 'kingofthehill',
  'racing kings', 'racingkings', 'three-check', 'threecheck', '3check', 'bughouse',
  'giveaway', 'suicide', 'losers', 'oddschess', 'doublechess', 'fog of war',
  'fogofwar', 'duck', 'duckchess',
};

/// One game read from PGN: the replayable [game] plus any problems.
class ParsedGame {
  ParsedGame({
    required this.game,
    required this.problems,
    required this.truncated,
    this.unsupportedVariant,
  });

  final Game game;
  final List<PgnProblem> problems;

  /// True when replay stopped before the end of the movetext.
  final bool truncated;

  /// Set when the Variant header names rules we cannot analyse.
  final String? unsupportedVariant;

  bool get isUsable => unsupportedVariant == null && game.plies.isNotEmpty;
}

class _Token {
  _Token(this.kind, this.text, this.offset);
  final String kind; // header, move, number, nag, comment, result
  final String text;
  final int offset;
}

class PgnReader {
  PgnReader._();

  /// Reads every game in [text]. Throws [PgnException] if there is none.
  static List<ParsedGame> readAll(String text) {
    final cleaned = text.replaceAll('﻿', '').replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rawGames = _split(cleaned);
    if (rawGames.isEmpty) {
      throw PgnException('No chess game found in the text.');
    }
    final out = <ParsedGame>[];
    for (final raw in rawGames) {
      final parsed = _replay(raw);
      if (parsed == null) continue;
      // Plain prose: no headers and not a single legal move.
      final hasHeaders = raw.any((t) => t.kind == 'header');
      if (!hasHeaders && parsed.game.plies.isEmpty && parsed.unsupportedVariant == null) continue;
      out.add(parsed);
    }
    if (out.isEmpty) {
      throw PgnException('The text has no moves that can be read as a chess game.');
    }
    return out;
  }

  /// Convenience: the first game in [text].
  static ParsedGame read(String text) => readAll(text).first;

  /// Quick check used by the import flow to decide whether text is PGN-like.
  static bool looksLikePgn(String text) {
    if (RegExp(r'^\s*\[\s*\w+\s+"', multiLine: true).hasMatch(text)) return true;
    return RegExp(r'(^|\s)1\.\s*(?:[NBRQK]?[a-h]?[1-8]?x?[a-h][1-8]|O-O|0-0)').hasMatch(text);
  }

  // ---------------------------------------------------------------------------

  static List<List<_Token>> _split(String text) {
    final tokens = _tokenize(text);
    final games = <List<_Token>>[];
    var current = <_Token>[];
    var seenMoves = false;
    for (final t in tokens) {
      if (t.kind == 'header' && seenMoves) {
        games.add(current);
        current = <_Token>[];
        seenMoves = false;
      }
      current.add(t);
      if (t.kind == 'move') seenMoves = true;
      if (t.kind == 'result') {
        games.add(current);
        current = <_Token>[];
        seenMoves = false;
      }
    }
    if (current.isNotEmpty) games.add(current);
    return games.where((g) => g.any((t) => t.kind == 'move' || t.kind == 'header')).toList();
  }

  static List<_Token> _tokenize(String s) {
    final out = <_Token>[];
    var i = 0;
    var depth = 0; // variation nesting; tokens inside variations are skipped
    final n = s.length;
    while (i < n) {
      final c = s[i];
      if (c == ' ' || c == '\n' || c == '\t') {
        i++;
        continue;
      }
      if (c == '[' && depth == 0) {
        // Header or stray bracket. Headers look like [Key "value"].
        final m = RegExp(r'^\[\s*([A-Za-z0-9_]+)\s+"((?:[^"\\]|\\.)*)"\s*\]').firstMatch(s.substring(i));
        if (m != null) {
          out.add(_Token('header', '${m.group(1)}\u0000${_unescape(m.group(2)!)}', i));
          i += m.group(0)!.length;
          continue;
        }
        // Not a header: skip to the matching bracket on this line.
        final close = s.indexOf(']', i);
        final nl = s.indexOf('\n', i);
        if (close != -1 && (nl == -1 || close < nl)) {
          i = close + 1;
        } else {
          i++;
        }
        continue;
      }
      if (c == '{') {
        final close = s.indexOf('}', i);
        final end = close == -1 ? n : close;
        if (depth == 0) out.add(_Token('comment', s.substring(i + 1, end), i));
        i = end + 1;
        continue;
      }
      if (c == ';') {
        final nl = s.indexOf('\n', i);
        final end = nl == -1 ? n : nl;
        if (depth == 0) out.add(_Token('comment', s.substring(i + 1, end), i));
        i = end;
        continue;
      }
      if (c == '(') {
        depth++;
        i++;
        continue;
      }
      if (c == ')') {
        if (depth > 0) depth--;
        i++;
        continue;
      }
      // A word.
      var j = i;
      while (j < n && !' \n\t{};()'.contains(s[j]) && !(s[j] == '[' && depth == 0)) {
        j++;
      }
      if (j == i) {
        i++;
        continue;
      }
      final word = s.substring(i, j);
      if (depth == 0) _classifyWord(word, i, out);
      i = j;
    }
    return out;
  }

  static final _resultRe = RegExp(r'^(1-0|0-1|1/2-1/2|½-½|\*)$');
  static final _numberRe = RegExp(r'^(\d+)(\.+)?$');
  static final _numberMoveRe = RegExp(r'^(\d+)\.+(\S+)$');

  static void _classifyWord(String word, int offset, List<_Token> out) {
    if (_resultRe.hasMatch(word)) {
      out.add(_Token('result', word == '½-½' ? '1/2-1/2' : word, offset));
      return;
    }
    if (word.startsWith(r'$')) {
      out.add(_Token('nag', word.substring(1), offset));
      return;
    }
    if (_numberRe.hasMatch(word)) {
      out.add(_Token('number', word, offset));
      return;
    }
    final nm = _numberMoveRe.firstMatch(word);
    if (nm != null) {
      out.add(_Token('number', nm.group(1)!, offset));
      _classifyWord(nm.group(2)!, offset + nm.group(1)!.length, out);
      return;
    }
    // Pure glyph tokens like "!" or "?!" attached by a space belong to the previous move.
    if (RegExp(r'^[!?]+$').hasMatch(word)) {
      out.add(_Token('nag', _glyphToNag(word), offset));
      return;
    }
    out.add(_Token('move', word, offset));
  }

  static String _glyphToNag(String g) => switch (g) {
        '!' => '1',
        '?' => '2',
        '!!' => '3',
        '??' => '4',
        '!?' => '5',
        '?!' => '6',
        _ => '0',
      };

  static String _unescape(String s) => s.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');

  static final _clkRe = RegExp(r'\[%clk\s+(\d+):(\d{1,2}):(\d{1,2})(?:\.(\d+))?\]');
  static final _tagRe = RegExp(r'\[%[a-zA-Z]+[^\]]*\]');

  static ParsedGame? _replay(List<_Token> tokens) {
    final headers = <String, String>{};
    final problems = <PgnProblem>[];
    for (final t in tokens.where((t) => t.kind == 'header')) {
      final parts = t.text.split('\u0000');
      headers[parts[0]] = parts[1];
    }
    final moveTokens = tokens.where((t) => t.kind != 'header').toList();
    if (moveTokens.isEmpty && headers.isEmpty) return null;

    String? variantProblem;
    final variant = (headers['Variant'] ?? headers['Rules'] ?? '').trim().toLowerCase();
    if (variant.isNotEmpty && unsupportedVariants.contains(variant)) {
      variantProblem = headers['Variant'] ?? headers['Rules'];
    }
    final is960 = variant.contains('960') || variant == 'fischerandom' || variant.contains('fischer');

    var initialFen = startFen;
    final fenHeader = headers['FEN'];
    if (fenHeader != null && fenHeader.trim().isNotEmpty) {
      try {
        initialFen = Position.fromFen(fenHeader, chess960: is960).fen;
      } on ChessException catch (e) {
        problems.add(PgnProblem('The FEN header is invalid: $e. Starting from the standard position instead.'));
        initialFen = startFen;
      }
    } else if (headers['SetUp'] == '1') {
      problems.add(const PgnProblem('SetUp "1" without a FEN header; starting from the standard position.'));
    }

    Position pos;
    try {
      pos = Position.fromFen(initialFen, chess960: is960);
    } on ChessException catch (e) {
      throw PgnException('Invalid starting position: $e');
    }

    final plies = <Ply>[];
    var result = GameResult.unknown;
    var truncated = false;
    var pendingComment = <String>[];
    var pendingNags = <int>[];
    var preGameComments = <String>[];

    void flushAnnotationsToLastPly() {
      if (plies.isEmpty) {
        preGameComments.addAll(pendingComment);
        pendingComment = [];
        pendingNags = [];
        return;
      }
      if (pendingComment.isEmpty && pendingNags.isEmpty) return;
      final last = plies.removeLast();
      final merged = _mergeComment(last.comment, pendingComment);
      plies.add(Ply(
        index: last.index,
        move: last.move,
        san: last.san,
        fenBefore: last.fenBefore,
        fenAfter: last.fenAfter,
        color: last.color,
        comment: merged.$1,
        clock: last.clock ?? merged.$2,
        nags: [...last.nags, ...pendingNags],
      ));
      pendingComment = [];
      pendingNags = [];
    }

    for (final t in moveTokens) {
      if (truncated) break;
      switch (t.kind) {
        case 'comment':
          pendingComment.add(t.text);
        case 'nag':
          final n = int.tryParse(t.text);
          if (n != null) pendingNags.add(n);
        case 'number':
          break;
        case 'result':
          flushAnnotationsToLastPly();
          result = GameResult.fromPgn(t.text);
        case 'move':
          flushAnnotationsToLastPly();
          final token = t.text;
          if (token == '--' || token == 'Z0' || token == '0000' || token.toLowerCase() == 'null') {
            problems.add(PgnProblem('Null moves are not supported; the game was cut here.',
                ply: plies.length, token: token));
            truncated = true;
            break;
          }
          if (variantProblem != null) break; // do not try to replay variant rules
          final glyph = RegExp(r'[!?]+$').firstMatch(token);
          if (glyph != null) {
            final n = int.tryParse(_glyphToNag(glyph.group(0)!));
            if (n != null && n > 0) pendingNags.add(n);
          }
          final m = pos.parseSan(token);
          if (m == null) {
            problems.add(PgnProblem(_describeIllegal(pos, token), ply: plies.length, token: token));
            truncated = true;
            break;
          }
          final next = pos.play(m);
          plies.add(Ply(
            index: plies.length,
            move: m,
            san: pos.san(m),
            fenBefore: pos.fen,
            fenAfter: next.fen,
            color: pos.turn,
            nags: List.of(pendingNags),
          ));
          pendingNags = [];
          pos = next;
      }
    }
    flushAnnotationsToLastPly();

    final headerResult = headers['Result'];
    if (headerResult != null && result == GameResult.unknown) {
      result = GameResult.fromPgn(headerResult);
    } else if (headerResult != null && GameResult.fromPgn(headerResult) != result &&
        GameResult.fromPgn(headerResult) != GameResult.unknown) {
      problems.add(PgnProblem(
          'Result header "$headerResult" disagrees with the movetext result "${result.pgn}"; using the movetext.'));
    }
    if (truncated) {
      problems.add(PgnProblem('Imported the first ${plies.length} half-moves only.'));
    }
    if (plies.isEmpty && variantProblem == null) {
      problems.add(const PgnProblem('The game has no moves.'));
    }
    if (preGameComments.isNotEmpty) {
      headers.putIfAbsent('_PreComment', () => preGameComments.join(' ').trim());
    }
    final game = Game(
      headers: headers,
      initialFen: initialFen,
      plies: plies,
      result: result,
      chess960: is960 || Position.fromFen(initialFen, chess960: is960).chess960,
    );
    return ParsedGame(
      game: game,
      problems: problems,
      truncated: truncated,
      unsupportedVariant: variantProblem,
    );
  }

  static (String?, Duration?) _mergeComment(String? existing, List<String> comments) {
    Duration? clock;
    final texts = <String>[];
    if (existing != null && existing.isNotEmpty) texts.add(existing);
    for (final c in comments) {
      final m = _clkRe.firstMatch(c);
      if (m != null && clock == null) {
        final h = int.parse(m.group(1)!);
        final mi = int.parse(m.group(2)!);
        final s = int.parse(m.group(3)!);
        final frac = m.group(4);
        var ms = 0;
        if (frac != null) {
          ms = (double.parse('0.$frac') * 1000).round();
        }
        clock = Duration(hours: h, minutes: mi, seconds: s, milliseconds: ms);
      }
      final stripped = c.replaceAll(_tagRe, '').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (stripped.isNotEmpty) texts.add(stripped);
    }
    return (texts.isEmpty ? null : texts.join(' '), clock);
  }

  static String _describeIllegal(Position pos, String token) {
    final moveNo = pos.fullmoveNumber;
    final side = pos.turn == Color.white ? 'White' : 'Black';
    final label = pos.turn == Color.white ? '$moveNo. $token' : '$moveNo... $token';
    final cleaned = token.replaceAll(RegExp(r'[+#!?]+$'), '');
    if (!RegExp(r'^([NBRQK]?[a-h]?[1-8]?x?[a-h][1-8](=?[NBRQ])?|O-O(-O)?|0-0(-0)?|[a-h][1-8][a-h][1-8][nbrq]?)$')
        .hasMatch(cleaned.replaceAll('0', 'O').replaceAll('O-O', 'O-O'))) {
      return '"$token" is not a chess move.';
    }
    if (pos.isCheck && !pos.isCheckmate) {
      return '$label is illegal here: $side is in check and must respond to it.';
    }
    if (pos.legalMoves.isEmpty) {
      return '$label comes after the game has already ended.';
    }
    return '$label is not a legal move in this position.';
  }
}
