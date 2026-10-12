/// Standard Algebraic Notation: generation and tolerant parsing.
library;

import 'position.dart';
import 'types.dart';

extension SanExtension on Position {
  /// SAN for a legal move in this position (with `+`/`#` suffix).
  String san(Move m) {
    final move = legalMoves.firstWhere((x) => x == m,
        orElse: () => throw ChessException('Illegal move ${m.uci}'));
    final piece = pieceAt(move.from)!;
    final side = castlingSideOf(move);
    final sb = StringBuffer();
    if (side != null) {
      sb.write(side == CastlingSide.king ? 'O-O' : 'O-O-O');
    } else if (piece.type == PieceType.pawn) {
      if (move.from.file != move.to.file) {
        sb.write('abcdefgh'[move.from.file]);
        sb.write('x');
      }
      sb.write(move.to.name);
      if (move.promotion != null) {
        sb.write('=');
        sb.write(move.promotion!.san);
      }
    } else {
      sb.write(piece.type.san);
      // Disambiguation: other pieces of the same type that can legally reach `to`.
      final others = legalMoves
          .where((x) =>
              x.to == move.to &&
              x.from != move.from &&
              pieceAt(x.from) == piece)
          .map((x) => x.from)
          .toSet()
          .toList();
      if (others.isNotEmpty) {
        final sameFile = others.any((s) => s.file == move.from.file);
        final sameRank = others.any((s) => s.rank == move.from.rank);
        if (!sameFile) {
          sb.write('abcdefgh'[move.from.file]);
        } else if (!sameRank) {
          sb.write('${move.from.rank + 1}');
        } else {
          sb.write(move.from.name);
        }
      }
      if (pieceAt(move.to) != null) sb.write('x');
      sb.write(move.to.name);
    }
    final next = play(move);
    if (next.isCheckmate) {
      sb.write('#');
    } else if (next.isCheck) {
      sb.write('+');
    }
    return sb.toString();
  }

  static final _sanRe = RegExp(
      r'^([NBRQK])?([a-h])?([1-8])?(x|:)?([a-h][1-8])(?:=?([NBRQKnbrq]))?$');

  /// Parses a SAN token tolerantly: ignores `+ # ! ?` suffixes, accepts `0-0`,
  /// `O-O`, `e8Q`, `e8=Q`, `exd6e.p.`, redundant or missing disambiguation,
  /// and plain UCI (`e2e4`). Returns null if the token matches no legal move.
  Move? parseSan(String token) {
    var s = token.trim();
    // Strip annotation suffixes and trailing punctuation.
    s = s.replaceAll(RegExp(r'[+#!?]+$'), '');
    s = s.replaceAll(RegExp(r'e\.p\.$', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'[+#!?]+$'), '');
    if (s.isEmpty) return null;
    final castle = s.replaceAll('0', 'O').toUpperCase();
    if (castle == 'O-O' || castle == 'O-O-O') {
      final side = castle == 'O-O' ? CastlingSide.king : CastlingSide.queen;
      for (final m in legalMoves) {
        if (castlingSideOf(m) == side) return m;
      }
      return null;
    }
    // UCI fallback (e2e4, e7e8q).
    final uci = Move.parseUci(s.toLowerCase());
    if (uci != null && RegExp(r'^[a-h][1-8][a-h][1-8][nbrq]?$').hasMatch(s)) {
      for (final m in legalMoves) {
        if (m == uci) return m;
        if (castlingSideOf(m) != null && m.from == uci.from) {
          // Accept e1g1 / e1h1 spellings for castling.
          final side = castlingSideOf(m)!;
          final rook = castling.rook(turn, side);
          final kingTo = Square.fromFileRank(side == CastlingSide.king ? 6 : 2, m.from.rank);
          if (uci.to == rook || uci.to == kingTo) return m;
        }
      }
      return null;
    }
    final match = _sanRe.firstMatch(s);
    if (match == null) return null;
    var pieceLetter = match.group(1);
    final fromFile = match.group(2);
    final fromRank = match.group(3);
    final to = Square.parse(match.group(5)!)!;
    final promoLetter = match.group(6);
    final promotion = promoLetter == null ? null : PieceType.fromLetter(promoLetter);
    if (promotion == PieceType.king || promotion == PieceType.pawn) return null;
    // Lower-case piece letters are sometimes used for pawns captures like "exd5";
    // the regex already treats a lone file letter as the pawn's file.
    final type = pieceLetter == null ? PieceType.pawn : PieceType.fromLetter(pieceLetter)!;
    final candidates = legalMoves.where((m) {
      if (m.to != to) return false;
      if (castlingSideOf(m) != null) return false;
      final p = pieceAt(m.from)!;
      if (p.type != type) return false;
      if (fromFile != null && m.from.file != fromFile.codeUnitAt(0) - 0x61) return false;
      if (fromRank != null && m.from.rank != int.parse(fromRank) - 1) return false;
      if (type == PieceType.pawn) {
        if ((m.promotion ?? PieceType.queen) != (promotion ?? PieceType.queen) &&
            !(m.promotion == null && promotion == null)) {
          return false;
        }
        if (m.promotion != null && promotion == null) return m.promotion == PieceType.queen;
        if (m.promotion == null && promotion != null) return false;
      }
      return true;
    }).toList();
    if (candidates.length == 1) return candidates.first;
    if (candidates.isEmpty) return null;
    // Ambiguous without further information: prefer a non-capture if the token
    // had no 'x', else give up.
    return null;
  }
}
