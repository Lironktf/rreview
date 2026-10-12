/// Board representation, FEN, move generation and legality.
library;

import 'types.dart';

/// Castling rights as the squares of the rooks that may still castle.
///
/// Storing rook squares (rather than KQkq flags) makes Chess960 free: the king
/// always ends on the c- or g-file and the rook on the d- or f-file, whatever
/// the start squares were.
class CastlingRights {
  const CastlingRights({
    this.whiteKing,
    this.whiteQueen,
    this.blackKing,
    this.blackQueen,
  });

  static const none = CastlingRights();

  final Square? whiteKing;
  final Square? whiteQueen;
  final Square? blackKing;
  final Square? blackQueen;

  Square? rook(Color c, CastlingSide s) => switch ((c, s)) {
        (Color.white, CastlingSide.king) => whiteKing,
        (Color.white, CastlingSide.queen) => whiteQueen,
        (Color.black, CastlingSide.king) => blackKing,
        (Color.black, CastlingSide.queen) => blackQueen,
      };

  bool get isEmpty =>
      whiteKing == null &&
      whiteQueen == null &&
      blackKing == null &&
      blackQueen == null;

  CastlingRights without(Color c, CastlingSide s) => switch ((c, s)) {
        (Color.white, CastlingSide.king) => CastlingRights(
            whiteQueen: whiteQueen, blackKing: blackKing, blackQueen: blackQueen),
        (Color.white, CastlingSide.queen) => CastlingRights(
            whiteKing: whiteKing, blackKing: blackKing, blackQueen: blackQueen),
        (Color.black, CastlingSide.king) => CastlingRights(
            whiteKing: whiteKing, whiteQueen: whiteQueen, blackQueen: blackQueen),
        (Color.black, CastlingSide.queen) => CastlingRights(
            whiteKing: whiteKing, whiteQueen: whiteQueen, blackKing: blackKing),
      };

  CastlingRights withoutColor(Color c) => c == Color.white
      ? CastlingRights(blackKing: blackKing, blackQueen: blackQueen)
      : CastlingRights(whiteKing: whiteKing, whiteQueen: whiteQueen);

  /// Removes any right that refers to [sq] (used when a rook is captured).
  CastlingRights withoutRookOn(Square sq) => CastlingRights(
        whiteKing: whiteKing == sq ? null : whiteKing,
        whiteQueen: whiteQueen == sq ? null : whiteQueen,
        blackKing: blackKing == sq ? null : blackKing,
        blackQueen: blackQueen == sq ? null : blackQueen,
      );

  @override
  bool operator ==(Object other) =>
      other is CastlingRights &&
      other.whiteKing == whiteKing &&
      other.whiteQueen == whiteQueen &&
      other.blackKing == blackKing &&
      other.blackQueen == blackQueen;

  @override
  int get hashCode => Object.hash(whiteKing, whiteQueen, blackKing, blackQueen);
}

/// Why a position could not be built from a FEN or a move could not be made.
class ChessException implements Exception {
  ChessException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// An immutable chess position with full legality.
class Position {
  Position._(
    this._board,
    this.turn,
    this.castling,
    this.epSquare,
    this.halfmoveClock,
    this.fullmoveNumber,
    this.chess960,
  );

  /// The standard starting position.
  factory Position.initial() => Position.fromFen(startFen);

  /// Parses a FEN string. Accepts 4-, 5- and 6-field FENs, X-FEN and
  /// Shredder-FEN castling fields. Throws [ChessException] on malformed input.
  factory Position.fromFen(String fen, {bool chess960 = false}) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) {
      throw ChessException('FEN needs at least a board and a side to move');
    }
    final board = List<Piece?>.filled(64, null);
    final ranks = parts[0].split('/');
    if (ranks.length != 8) {
      throw ChessException('FEN board must have 8 ranks, found ${ranks.length}');
    }
    for (var r = 0; r < 8; r++) {
      var file = 0;
      for (final ch in ranks[r].split('')) {
        final digit = int.tryParse(ch);
        if (digit != null) {
          if (digit < 1 || digit > 8) {
            throw ChessException('Invalid digit "$ch" in FEN rank ${8 - r}');
          }
          file += digit;
        } else {
          final piece = Piece.fromFenLetter(ch);
          if (piece == null) {
            throw ChessException('Invalid piece "$ch" in FEN rank ${8 - r}');
          }
          if (file > 7) {
            throw ChessException('Too many squares in FEN rank ${8 - r}');
          }
          board[(7 - r) * 8 + file] = piece;
          file++;
        }
      }
      if (file != 8) {
        throw ChessException('FEN rank ${8 - r} has $file squares, expected 8');
      }
    }
    final turn = Color.fromLetter(parts[1]);
    if (turn == null) {
      throw ChessException('Side to move must be "w" or "b", found "${parts[1]}"');
    }
    for (final c in Color.values) {
      final kings = board.where((p) => p == Piece(c, PieceType.king)).length;
      if (kings != 1) {
        throw ChessException('${c.name} must have exactly one king, found $kings');
      }
    }
    for (var f = 0; f < 8; f++) {
      if (board[f]?.type == PieceType.pawn || board[56 + f]?.type == PieceType.pawn) {
        throw ChessException('Pawns cannot stand on the first or eighth rank');
      }
    }

    var castling = CastlingRights.none;
    final castlingField = parts.length > 2 ? parts[2] : '-';
    var is960 = chess960;
    if (castlingField != '-') {
      for (final ch in castlingField.split('')) {
        final color = ch == ch.toUpperCase() ? Color.white : Color.black;
        final backRank = color == Color.white ? 0 : 7;
        final kingSq = _findKing(board, color);
        if (kingSq.rank != backRank) continue; // sloppy FEN: ignore the right
        Square? rookSq;
        final lower = ch.toLowerCase();
        if (lower == 'k' || lower == 'q') {
          // Outermost rook on the given side of the king.
          final step = lower == 'k' ? 1 : -1;
          for (var f = lower == 'k' ? 7 : 0; f != kingSq.file; f -= step) {
            final sq = Square.fromFileRank(f, backRank);
            if (board[sq.index] == Piece(color, PieceType.rook)) {
              rookSq = sq;
              break;
            }
          }
        } else if (lower.codeUnitAt(0) >= 0x61 && lower.codeUnitAt(0) <= 0x68) {
          rookSq = Square.fromFileRank(lower.codeUnitAt(0) - 0x61, backRank);
          if (board[rookSq.index] != Piece(color, PieceType.rook)) continue;
          is960 = true;
        } else {
          throw ChessException('Invalid castling field "$castlingField"');
        }
        if (rookSq == null) continue; // sloppy FEN: no rook for this right
        final side = rookSq.file > kingSq.file ? CastlingSide.king : CastlingSide.queen;
        castling = switch ((color, side)) {
          (Color.white, CastlingSide.king) => CastlingRights(
              whiteKing: rookSq, whiteQueen: castling.whiteQueen,
              blackKing: castling.blackKing, blackQueen: castling.blackQueen),
          (Color.white, CastlingSide.queen) => CastlingRights(
              whiteKing: castling.whiteKing, whiteQueen: rookSq,
              blackKing: castling.blackKing, blackQueen: castling.blackQueen),
          (Color.black, CastlingSide.king) => CastlingRights(
              whiteKing: castling.whiteKing, whiteQueen: castling.whiteQueen,
              blackKing: rookSq, blackQueen: castling.blackQueen),
          (Color.black, CastlingSide.queen) => CastlingRights(
              whiteKing: castling.whiteKing, whiteQueen: castling.whiteQueen,
              blackKing: castling.blackKing, blackQueen: rookSq),
        };
      }
      // Non-standard king or rook files imply Chess960 castling notation.
      if (!is960) {
        for (final c in Color.values) {
          final k = _findKing(board, c);
          if ((castling.rook(c, CastlingSide.king) != null ||
                  castling.rook(c, CastlingSide.queen) != null) &&
              k.file != 4) {
            is960 = true;
          }
          final kr = castling.rook(c, CastlingSide.king);
          final qr = castling.rook(c, CastlingSide.queen);
          if ((kr != null && kr.file != 7) || (qr != null && qr.file != 0)) is960 = true;
        }
      }
    }

    Square? ep;
    if (parts.length > 3 && parts[3] != '-') {
      ep = Square.parse(parts[3]);
      final expectedRank = turn == Color.white ? 5 : 2;
      if (ep != null && ep.rank != expectedRank) ep = null;
      // Only keep it when a pawn actually just double-pushed there.
      if (ep != null) {
        final pawnSq = Square(ep.index + (turn == Color.white ? -8 : 8));
        if (board[pawnSq.index] != Piece(turn.opposite, PieceType.pawn) ||
            board[ep.index] != null) {
          ep = null;
        }
      }
    }
    var halfmove = 0;
    var fullmove = 1;
    if (parts.length > 4) {
      halfmove = int.tryParse(parts[4]) ?? 0;
      if (halfmove < 0) halfmove = 0;
    }
    if (parts.length > 5) {
      fullmove = int.tryParse(parts[5]) ?? 1;
      if (fullmove < 1) fullmove = 1;
    }
    final pos = Position._(board, turn, castling, ep, halfmove, fullmove, is960);
    if (pos.isAttacked(_findKing(board, turn.opposite), turn)) {
      throw ChessException('The side not to move is in check');
    }
    return pos;
  }

  final List<Piece?> _board;
  final Color turn;
  final CastlingRights castling;

  /// Square a pawn can capture onto en passant, if the last move was a double
  /// pawn push (regardless of whether such a capture is legal).
  final Square? epSquare;
  final int halfmoveClock;
  final int fullmoveNumber;

  /// Whether castling is written as "king takes rook" (UCI Chess960 style).
  final bool chess960;

  List<Move>? _legalCache;

  Piece? pieceAt(Square sq) => _board[sq.index];

  /// Read-only board view, index 0 = a1.
  List<Piece?> get board => List.unmodifiable(_board);

  Square kingSquare(Color c) => _findKing(_board, c);

  static Square _findKing(List<Piece?> board, Color c) {
    final k = Piece(c, PieceType.king);
    for (var i = 0; i < 64; i++) {
      if (board[i] == k) return Square(i);
    }
    throw ChessException('No ${c.name} king on the board');
  }

  /// All squares holding a piece of [color] (optionally of [type]).
  Iterable<Square> squaresOf(Color color, [PieceType? type]) sync* {
    for (var i = 0; i < 64; i++) {
      final p = _board[i];
      if (p != null && p.color == color && (type == null || p.type == type)) {
        yield Square(i);
      }
    }
  }

  /// Ply count since the start of a standard game (0 for the initial position).
  int get ply => (fullmoveNumber - 1) * 2 + (turn == Color.black ? 1 : 0);

  // ---------------------------------------------------------------------------
  // Attacks

  static const _knightDeltas = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)];
  static const _kingDeltas = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)];
  static const _bishopDirs = [(1, 1), (-1, 1), (-1, -1), (1, -1)];
  static const _rookDirs = [(1, 0), (0, 1), (-1, 0), (0, -1)];

  static Square? _offset(Square sq, int df, int dr) {
    final f = sq.file + df;
    final r = sq.rank + dr;
    if (f < 0 || f > 7 || r < 0 || r > 7) return null;
    return Square.fromFileRank(f, r);
  }

  /// Whether [sq] is attacked by any piece of [by] on [board].
  static bool _attacked(List<Piece?> board, Square sq, Color by) {
    // Pawns: a pawn of colour `by` attacks `sq` if it stands diagonally behind it.
    final pawnDr = by == Color.white ? -1 : 1;
    for (final df in [-1, 1]) {
      final s = _offset(sq, df, pawnDr);
      if (s != null && board[s.index] == Piece(by, PieceType.pawn)) return true;
    }
    for (final (df, dr) in _knightDeltas) {
      final s = _offset(sq, df, dr);
      if (s != null && board[s.index] == Piece(by, PieceType.knight)) return true;
    }
    for (final (df, dr) in _kingDeltas) {
      final s = _offset(sq, df, dr);
      if (s != null && board[s.index] == Piece(by, PieceType.king)) return true;
    }
    for (final (df, dr) in _bishopDirs) {
      var s = _offset(sq, df, dr);
      while (s != null) {
        final p = board[s.index];
        if (p != null) {
          if (p.color == by && (p.type == PieceType.bishop || p.type == PieceType.queen)) {
            return true;
          }
          break;
        }
        s = _offset(s, df, dr);
      }
    }
    for (final (df, dr) in _rookDirs) {
      var s = _offset(sq, df, dr);
      while (s != null) {
        final p = board[s.index];
        if (p != null) {
          if (p.color == by && (p.type == PieceType.rook || p.type == PieceType.queen)) {
            return true;
          }
          break;
        }
        s = _offset(s, df, dr);
      }
    }
    return false;
  }

  bool isAttacked(Square sq, Color by) => _attacked(_board, sq, by);

  /// Squares of pieces of colour [by] that attack [sq] (ignoring pins).
  List<Square> attackers(Square sq, Color by) {
    final out = <Square>[];
    final pawnDr = by == Color.white ? -1 : 1;
    for (final df in [-1, 1]) {
      final s = _offset(sq, df, pawnDr);
      if (s != null && _board[s.index] == Piece(by, PieceType.pawn)) out.add(s);
    }
    for (final (df, dr) in _knightDeltas) {
      final s = _offset(sq, df, dr);
      if (s != null && _board[s.index] == Piece(by, PieceType.knight)) out.add(s);
    }
    for (final (df, dr) in _kingDeltas) {
      final s = _offset(sq, df, dr);
      if (s != null && _board[s.index] == Piece(by, PieceType.king)) out.add(s);
    }
    for (final dirs in [_bishopDirs, _rookDirs]) {
      final diagonal = identical(dirs, _bishopDirs);
      for (final (df, dr) in dirs) {
        var s = _offset(sq, df, dr);
        while (s != null) {
          final p = _board[s.index];
          if (p != null) {
            if (p.color == by &&
                (p.type == PieceType.queen ||
                    p.type == (diagonal ? PieceType.bishop : PieceType.rook))) {
              out.add(s);
            }
            break;
          }
          s = _offset(s, df, dr);
        }
      }
    }
    return out;
  }

  bool get isCheck => isAttacked(kingSquare(turn), turn.opposite);

  /// Squares of enemy pieces giving check.
  List<Square> get checkers => attackers(kingSquare(turn), turn.opposite);

  // ---------------------------------------------------------------------------
  // Move generation

  /// All legal moves in this position.
  List<Move> get legalMoves {
    final cached = _legalCache;
    if (cached != null) return cached;
    final out = <Move>[];
    for (final m in _pseudoLegal()) {
      if (_leavesKingSafe(m)) out.add(m);
    }
    _legalCache = List.unmodifiable(out);
    return _legalCache!;
  }

  bool isLegal(Move m) => legalMoves.contains(_canonical(m) ?? m);

  /// Normalises alternative castling spellings (e1g1 vs e1h1) to the form used
  /// by this position; returns null if the move is not even pseudo-legal.
  Move? _canonical(Move m) {
    final p = _board[m.from.index];
    if (p == null || p.type != PieceType.king) return m;
    final target = _board[m.to.index];
    final fileDelta = m.to.file - m.from.file;
    CastlingSide? side;
    if (target == Piece(turn, PieceType.rook)) {
      side = m.to.file > m.from.file ? CastlingSide.king : CastlingSide.queen;
    } else if (fileDelta.abs() == 2 && m.from.rank == m.to.rank) {
      side = fileDelta > 0 ? CastlingSide.king : CastlingSide.queen;
    } else if (!chess960 || target == null) {
      return m;
    }
    if (side == null) return m;
    final rook = castling.rook(turn, side);
    if (rook == null) return null;
    return _castlingMove(m.from, rook, side);
  }

  Move _castlingMove(Square king, Square rook, CastlingSide side) {
    if (chess960) return Move(king, rook);
    return Move(king, Square.fromFileRank(side == CastlingSide.king ? 6 : 2, king.rank));
  }

  /// If [m] is a castling move, returns the side; otherwise null.
  CastlingSide? castlingSideOf(Move m) {
    final p = _board[m.from.index];
    if (p == null || p.type != PieceType.king) return null;
    final target = _board[m.to.index];
    if (target == Piece(turn, PieceType.rook)) {
      return m.to.file > m.from.file ? CastlingSide.king : CastlingSide.queen;
    }
    final d = m.to.file - m.from.file;
    if (d.abs() == 2 && m.from.rank == m.to.rank) {
      return d > 0 ? CastlingSide.king : CastlingSide.queen;
    }
    return null;
  }

  bool isCapture(Move m) =>
      _board[m.to.index] != null && castlingSideOf(m) == null || isEnPassant(m);

  bool isEnPassant(Move m) =>
      _board[m.from.index]?.type == PieceType.pawn &&
      epSquare != null &&
      m.to == epSquare &&
      m.from.file != m.to.file;

  Iterable<Move> _pseudoLegal() sync* {
    final us = turn;
    final them = turn.opposite;
    for (var i = 0; i < 64; i++) {
      final p = _board[i];
      if (p == null || p.color != us) continue;
      final from = Square(i);
      switch (p.type) {
        case PieceType.pawn:
          final dr = us == Color.white ? 1 : -1;
          final startRank = us == Color.white ? 1 : 6;
          final promoRank = us == Color.white ? 7 : 0;
          final one = _offset(from, 0, dr);
          if (one != null && _board[one.index] == null) {
            yield* _pawnMoves(from, one, promoRank);
            if (from.rank == startRank) {
              final two = _offset(from, 0, 2 * dr)!;
              if (_board[two.index] == null) yield Move(from, two);
            }
          }
          for (final df in [-1, 1]) {
            final t = _offset(from, df, dr);
            if (t == null) continue;
            final target = _board[t.index];
            if ((target != null && target.color == them) || t == epSquare) {
              yield* _pawnMoves(from, t, promoRank);
            }
          }
        case PieceType.knight:
          for (final (df, dr) in _knightDeltas) {
            final t = _offset(from, df, dr);
            if (t != null && _board[t.index]?.color != us) yield Move(from, t);
          }
        case PieceType.king:
          for (final (df, dr) in _kingDeltas) {
            final t = _offset(from, df, dr);
            if (t != null && _board[t.index]?.color != us) yield Move(from, t);
          }
          for (final side in CastlingSide.values) {
            final rook = castling.rook(us, side);
            if (rook != null && _canCastle(from, rook, side)) {
              yield _castlingMove(from, rook, side);
            }
          }
        case PieceType.bishop:
        case PieceType.rook:
        case PieceType.queen:
          final dirs = switch (p.type) {
            PieceType.bishop => _bishopDirs,
            PieceType.rook => _rookDirs,
            _ => [..._bishopDirs, ..._rookDirs],
          };
          for (final (df, dr) in dirs) {
            var t = _offset(from, df, dr);
            while (t != null) {
              final target = _board[t.index];
              if (target == null) {
                yield Move(from, t);
              } else {
                if (target.color == them) yield Move(from, t);
                break;
              }
              t = _offset(t, df, dr);
            }
          }
      }
    }
  }

  Iterable<Move> _pawnMoves(Square from, Square to, int promoRank) sync* {
    if (to.rank == promoRank) {
      for (final t in [PieceType.queen, PieceType.rook, PieceType.bishop, PieceType.knight]) {
        yield Move(from, to, promotion: t);
      }
    } else {
      yield Move(from, to);
    }
  }

  bool _canCastle(Square king, Square rook, CastlingSide side) {
    final rank = king.rank;
    final kingTo = Square.fromFileRank(side == CastlingSide.king ? 6 : 2, rank);
    final rookTo = Square.fromFileRank(side == CastlingSide.king ? 5 : 3, rank);
    // Every square the king or rook crosses or lands on must be empty, except
    // for the king and the castling rook themselves.
    bool pathClear(Square a, Square b) {
      final lo = a.file < b.file ? a.file : b.file;
      final hi = a.file < b.file ? b.file : a.file;
      for (var f = lo; f <= hi; f++) {
        final s = Square.fromFileRank(f, rank);
        if (s == king || s == rook) continue;
        if (_board[s.index] != null) return false;
      }
      return true;
    }
    if (!pathClear(king, kingTo) || !pathClear(rook, rookTo)) return false;
    // The king may not be in check, pass through check or land in check. Attacks
    // are evaluated with the rook already moved (matters in Chess960).
    final scratch = List<Piece?>.of(_board);
    scratch[rook.index] = null;
    scratch[king.index] = null;
    scratch[rookTo.index] = Piece(turn, PieceType.rook);
    final lo = king.file < kingTo.file ? king.file : kingTo.file;
    final hi = king.file < kingTo.file ? kingTo.file : king.file;
    for (var f = lo; f <= hi; f++) {
      final s = Square.fromFileRank(f, rank);
      scratch[s.index] = Piece(turn, PieceType.king);
      final attacked = _attacked(scratch, s, turn.opposite);
      scratch[s.index] = s == rookTo ? Piece(turn, PieceType.rook) : null;
      if (attacked) return false;
    }
    return true;
  }

  bool _leavesKingSafe(Move m) {
    final next = _apply(m);
    return !_attacked(next, _findKing(next, turn), turn.opposite);
  }

  /// Applies [m] to a copy of the board without validation; returns the board.
  List<Piece?> _apply(Move m) {
    final b = List<Piece?>.of(_board);
    final piece = b[m.from.index]!;
    final side = castlingSideOf(m);
    if (side != null) {
      final rook = castling.rook(turn, side) ??
          (chess960 ? m.to : Square.fromFileRank(side == CastlingSide.king ? 7 : 0, m.from.rank));
      final rank = m.from.rank;
      b[m.from.index] = null;
      b[rook.index] = null;
      b[Square.fromFileRank(side == CastlingSide.king ? 6 : 2, rank).index] = piece;
      b[Square.fromFileRank(side == CastlingSide.king ? 5 : 3, rank).index] =
          Piece(turn, PieceType.rook);
      return b;
    }
    if (isEnPassant(m)) {
      b[Square(m.to.index + (turn == Color.white ? -8 : 8)).index] = null;
    }
    b[m.from.index] = null;
    b[m.to.index] = m.promotion != null ? Piece(turn, m.promotion!) : piece;
    return b;
  }

  /// Plays a legal move and returns the resulting position.
  /// Throws [ChessException] if the move is illegal.
  Position play(Move m) {
    final canon = _canonical(m);
    if (canon == null || !legalMoves.contains(canon)) {
      throw ChessException('Illegal move ${m.uci}');
    }
    m = canon;
    final piece = _board[m.from.index]!;
    final captured = isEnPassant(m)
        ? const Piece(Color.white, PieceType.pawn) // placeholder, any pawn
        : (castlingSideOf(m) == null ? _board[m.to.index] : null);
    final b = _apply(m);
    var rights = castling;
    if (piece.type == PieceType.king) rights = rights.withoutColor(turn);
    if (piece.type == PieceType.rook) rights = rights.withoutRookOn(m.from);
    if (castlingSideOf(m) == null && _board[m.to.index]?.type == PieceType.rook) {
      rights = rights.withoutRookOn(m.to);
    }
    Square? ep;
    if (piece.type == PieceType.pawn && (m.to.rank - m.from.rank).abs() == 2) {
      ep = Square((m.from.index + m.to.index) ~/ 2);
    }
    final resetClock = piece.type == PieceType.pawn || captured != null;
    return Position._(
      b,
      turn.opposite,
      rights,
      ep,
      resetClock ? 0 : halfmoveClock + 1,
      turn == Color.black ? fullmoveNumber + 1 : fullmoveNumber,
      chess960,
    );
  }

  /// Like [play] but returns null instead of throwing.
  Position? tryPlay(Move m) {
    try {
      return play(m);
    } on ChessException {
      return null;
    }
  }

  /// Same position with the other side to move (en passant cleared). Returns
  /// null if the resulting position would be illegal.
  Position? withTurnPassed() {
    final p = Position._(List.of(_board), turn.opposite, castling, null,
        halfmoveClock, fullmoveNumber, chess960);
    if (p.isAttacked(p.kingSquare(p.turn.opposite), p.turn)) return null;
    return p;
  }

  // ---------------------------------------------------------------------------
  // Game state

  bool get isCheckmate => isCheck && legalMoves.isEmpty;
  bool get isStalemate => !isCheck && legalMoves.isEmpty;

  /// Dead position by the usual rule of thumb: no pawns, rooks or queens and
  /// at most one minor piece per side, or only same-coloured bishops.
  bool get isInsufficientMaterial {
    final minors = <Color, int>{Color.white: 0, Color.black: 0};
    var knights = 0;
    bool? bishopColor;
    var mixedBishops = false;
    for (var i = 0; i < 64; i++) {
      final p = _board[i];
      if (p == null || p.type == PieceType.king) continue;
      switch (p.type) {
        case PieceType.pawn:
        case PieceType.rook:
        case PieceType.queen:
          return false;
        case PieceType.knight:
          knights++;
          minors[p.color] = minors[p.color]! + 1;
        case PieceType.bishop:
          minors[p.color] = minors[p.color]! + 1;
          final light = Square(i).isLight;
          if (bishopColor == null) {
            bishopColor = light;
          } else if (bishopColor != light) {
            mixedBishops = true;
          }
        case PieceType.king:
          break;
      }
    }
    if (minors[Color.white]! <= 1 && minors[Color.black]! <= 1) return true;
    if (knights == 0 && !mixedBishops) return true;
    return false;
  }

  bool get isFiftyMoveRule => halfmoveClock >= 100;

  /// Whether [color] has only a king (relevant for timeout-vs-insufficient-material).
  bool hasOnlyKing(Color color) =>
      squaresOf(color).every((s) => _board[s.index]!.type == PieceType.king);

  // ---------------------------------------------------------------------------
  // FEN

  String get fen => '${_boardFen()} ${turn.letter} ${_castlingFen()} '
      '${epSquare?.name ?? '-'} $halfmoveClock $fullmoveNumber';

  /// FEN without the move counters; equal strings mean the same position for
  /// repetition purposes (en passant is only included when capturable).
  String get repetitionKey {
    var ep = '-';
    if (epSquare != null && legalMoves.any(isEnPassant)) ep = epSquare!.name;
    return '${_boardFen()} ${turn.letter} ${_castlingFen()} $ep';
  }

  String _boardFen() {
    final sb = StringBuffer();
    for (var r = 7; r >= 0; r--) {
      var empty = 0;
      for (var f = 0; f < 8; f++) {
        final p = _board[r * 8 + f];
        if (p == null) {
          empty++;
        } else {
          if (empty > 0) sb.write(empty);
          empty = 0;
          sb.write(p.fenLetter);
        }
      }
      if (empty > 0) sb.write(empty);
      if (r > 0) sb.write('/');
    }
    return sb.toString();
  }

  String _castlingFen() {
    if (castling.isEmpty) return '-';
    final sb = StringBuffer();
    for (final c in Color.values) {
      for (final side in CastlingSide.values) {
        final rook = castling.rook(c, side);
        if (rook == null) continue;
        // X-FEN: K/Q when the castling rook is the outermost rook on its side,
        // otherwise the rook's file letter (Shredder-FEN).
        var letter = side == CastlingSide.king ? 'k' : 'q';
        if (chess960) {
          final king = kingSquare(c);
          final step = side == CastlingSide.king ? 1 : -1;
          for (var f = rook.file + step; f >= 0 && f <= 7; f += step) {
            if (_board[Square.fromFileRank(f, king.rank).index] == Piece(c, PieceType.rook)) {
              letter = 'abcdefgh'[rook.file];
              break;
            }
          }
        }
        sb.write(c == Color.white ? letter.toUpperCase() : letter);
      }
    }
    return sb.toString();
  }

  /// Material balance in pawns from White's point of view (Q9 R5 B3 N3 P1).
  int get materialBalance {
    var total = 0;
    for (final p in _board) {
      if (p == null) continue;
      total += p.color == Color.white ? p.type.value : -p.type.value;
    }
    return total;
  }

  /// Number of non-king pieces on the board.
  int get pieceCount => _board.where((p) => p != null && p.type != PieceType.king).length;

  /// UCI string for a move, respecting the Chess960 castling convention.
  String uci(Move m) => (_canonical(m) ?? m).uci;

  @override
  String toString() => fen;

  /// Simple ASCII diagram for debugging.
  String get ascii {
    final sb = StringBuffer();
    for (var r = 7; r >= 0; r--) {
      sb.write('${r + 1} ');
      for (var f = 0; f < 8; f++) {
        sb.write(_board[r * 8 + f]?.fenLetter ?? '.');
        sb.write(' ');
      }
      sb.writeln();
    }
    sb.writeln('  a b c d e f g h');
    return sb.toString();
  }
}
