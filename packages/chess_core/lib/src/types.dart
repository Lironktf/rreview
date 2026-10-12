/// Basic chess types: colours, pieces, squares and moves.
library;

enum Color {
  white,
  black;

  Color get opposite => this == Color.white ? Color.black : Color.white;

  /// `w` or `b`, as used in FEN.
  String get letter => this == Color.white ? 'w' : 'b';

  static Color? fromLetter(String s) => switch (s) {
        'w' => Color.white,
        'b' => Color.black,
        _ => null,
      };
}

enum PieceType {
  pawn('p', 1),
  knight('n', 3),
  bishop('b', 3),
  rook('r', 5),
  queen('q', 9),
  king('k', 0);

  const PieceType(this.letter, this.value);

  /// Lower-case FEN letter.
  final String letter;

  /// Conventional material value in pawns (king = 0).
  final int value;

  /// Upper-case SAN letter (`N`, `B`, `R`, `Q`, `K`; empty for pawns).
  String get san => this == PieceType.pawn ? '' : letter.toUpperCase();

  static PieceType? fromLetter(String s) {
    for (final t in PieceType.values) {
      if (t.letter == s.toLowerCase()) return t;
    }
    return null;
  }

  /// English name, lower case.
  String get name => switch (this) {
        PieceType.pawn => 'pawn',
        PieceType.knight => 'knight',
        PieceType.bishop => 'bishop',
        PieceType.rook => 'rook',
        PieceType.queen => 'queen',
        PieceType.king => 'king',
      };
}

class Piece {
  const Piece(this.color, this.type);

  final Color color;
  final PieceType type;

  /// FEN letter: upper case for White, lower case for Black.
  String get fenLetter =>
      color == Color.white ? type.letter.toUpperCase() : type.letter;

  static Piece? fromFenLetter(String s) {
    final t = PieceType.fromLetter(s);
    if (t == null) return null;
    return Piece(s == s.toUpperCase() ? Color.white : Color.black, t);
  }

  @override
  bool operator ==(Object other) =>
      other is Piece && other.color == color && other.type == type;

  @override
  int get hashCode => color.index * 8 + type.index;

  @override
  String toString() => fenLetter;
}

/// Squares are integers 0..63 with a1 = 0, b1 = 1, ..., h8 = 63.
extension type const Square(int index) {
  static Square? parse(String name) {
    if (name.length != 2) return null;
    final f = name.codeUnitAt(0) - 0x61; // 'a'
    final r = name.codeUnitAt(1) - 0x31; // '1'
    if (f < 0 || f > 7 || r < 0 || r > 7) return null;
    return Square(r * 8 + f);
  }

  static Square fromFileRank(int file, int rank) => Square(rank * 8 + file);

  int get file => index & 7;
  int get rank => index >> 3;
  String get name => '${'abcdefgh'[file]}${rank + 1}';
  bool get isLight => (file + rank).isOdd;

  /// Square mirrored vertically (a1 <-> a8), used for perspective flips.
  Square get flipped => Square(index ^ 56);
}

/// A move in coordinate form. [promotion] is set only for pawn promotions.
///
/// Castling is represented as the king moving two squares in standard chess
/// and as "king takes own rook" in Chess960, exactly as the UCI protocol does.
class Move {
  const Move(this.from, this.to, {this.promotion});

  final Square from;
  final Square to;
  final PieceType? promotion;

  /// Parses UCI coordinate notation (`e2e4`, `e7e8q`). Returns null if malformed.
  static Move? parseUci(String s) {
    if (s.length < 4 || s.length > 5) return null;
    final from = Square.parse(s.substring(0, 2));
    final to = Square.parse(s.substring(2, 4));
    if (from == null || to == null) return null;
    PieceType? promo;
    if (s.length == 5) {
      promo = PieceType.fromLetter(s[4]);
      if (promo == null || promo == PieceType.king || promo == PieceType.pawn) {
        return null;
      }
    }
    return Move(from, to, promotion: promo);
  }

  String get uci => '${from.name}${to.name}${promotion?.letter ?? ''}';

  @override
  bool operator ==(Object other) =>
      other is Move &&
      other.from == from &&
      other.to == to &&
      other.promotion == promotion;

  @override
  int get hashCode => Object.hash(from.index, to.index, promotion);

  @override
  String toString() => uci;
}

/// Castling sides.
enum CastlingSide { king, queen }

/// Standard starting position.
const String startFen =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
