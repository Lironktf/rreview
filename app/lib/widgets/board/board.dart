/// Interactive chess board: squares, coordinates, highlights, arrows,
/// classification badges, animated piece movement, tap and drag input.
library;

import 'package:chess_core/chess_core.dart';
import 'package:flutter/material.dart' hide Color;
import 'package:flutter/material.dart' as m show Color;
import 'package:review_core/review_core.dart';

import '../../services/settings_service.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import 'pieces.dart';

class BoardArrow {
  const BoardArrow(this.from, this.to, this.color);
  final Square from;
  final Square to;
  final m.Color color;
}

class BoardBadge {
  const BoardBadge(this.square, this.label);
  final Square square;
  final MoveLabel label;
}

class ChessBoard extends StatefulWidget {
  const ChessBoard({
    super.key,
    required this.position,
    required this.orientation,
    required this.pieceSet,
    this.lastMove,
    this.arrows = const [],
    this.badge,
    this.interactive = false,
    this.onMove,
    this.showCoordinates = true,
    this.boardStyle = BoardStyle.brown,
    this.dimmed = false,
  });

  final Position position;

  /// Colour shown at the bottom.
  final Color orientation;
  final PieceSet pieceSet;
  final Move? lastMove;
  final List<BoardArrow> arrows;
  final BoardBadge? badge;
  final bool interactive;
  final void Function(Move move)? onMove;
  final bool showCoordinates;
  final BoardStyle boardStyle;
  final bool dimmed;

  @override
  State<ChessBoard> createState() => _ChessBoardState();
}

class _Sprite {
  _Sprite(this.key, this.piece, this.square);
  final int key;
  Piece piece;
  Square square;
}

class _ChessBoardState extends State<ChessBoard> {
  final List<_Sprite> _sprites = [];
  int _nextKey = 0;
  Square? _selected;
  Square? _dragFrom;
  Offset? _dragPos;
  bool _animate = false;

  @override
  void initState() {
    super.initState();
    _rebuildSprites();
  }

  void _rebuildSprites() {
    _sprites.clear();
    for (var i = 0; i < 64; i++) {
      final p = widget.position.pieceAt(Square(i));
      if (p != null) _sprites.add(_Sprite(_nextKey++, p, Square(i)));
    }
  }

  @override
  void didUpdateWidget(ChessBoard old) {
    super.didUpdateWidget(old);
    if (old.position.fen == widget.position.fen) return;
    _selected = null;
    // Forward step: the new position is old + lastMove.
    final lm = widget.lastMove;
    if (lm != null && old.position.isLegal(lm) && _sameBoard(old.position.play(lm), widget.position)) {
      _applyMove(old.position, lm);
      _animate = true;
      return;
    }
    // Backward step: old position is new + old.lastMove.
    final olm = old.lastMove;
    if (olm != null && widget.position.isLegal(olm) && _sameBoard(widget.position.play(olm), old.position)) {
      _undoMove(widget.position, olm);
      _animate = true;
      return;
    }
    _animate = false;
    _rebuildSprites();
  }

  static bool _sameBoard(Position a, Position b) =>
      a.fen.split(' ').take(2).join(' ') == b.fen.split(' ').take(2).join(' ');

  _Sprite? _at(Square s) {
    for (final sp in _sprites) {
      if (sp.square == s) return sp;
    }
    return null;
  }

  void _applyMove(Position before, Move m) {
    final mover = _at(m.from);
    if (mover == null) {
      _rebuildSprites();
      return;
    }
    final side = before.castlingSideOf(m);
    if (side != null) {
      final rank = m.from.rank;
      final rookFrom = before.castling.rook(before.turn, side)!;
      final rook = _at(rookFrom);
      mover.square = Square.fromFileRank(side == CastlingSide.king ? 6 : 2, rank);
      rook?.square = Square.fromFileRank(side == CastlingSide.king ? 5 : 3, rank);
      return;
    }
    if (before.isEnPassant(m)) {
      final captured = Square(m.to.index + (before.turn == Color.white ? -8 : 8));
      _sprites.removeWhere((s) => s.square == captured);
    }
    _sprites.removeWhere((s) => s.square == m.to && s != mover);
    mover.square = m.to;
    if (m.promotion != null) mover.piece = Piece(before.turn, m.promotion!);
  }

  void _undoMove(Position before, Move m) {
    // Rebuild from the target position but keep the moving piece's identity so
    // it slides back.
    final after = before.play(m);
    final side = before.castlingSideOf(m);
    final movedTo = side == null
        ? m.to
        : Square.fromFileRank(side == CastlingSide.king ? 6 : 2, m.from.rank);
    final moverSprite = _at(movedTo);
    final keep = <Square, int>{};
    if (moverSprite != null) keep[m.from] = moverSprite.key;
    if (side != null) {
      final rookTo = Square.fromFileRank(side == CastlingSide.king ? 5 : 3, m.from.rank);
      final rookSprite = _at(rookTo);
      if (rookSprite != null) keep[before.castling.rook(before.turn, side)!] = rookSprite.key;
    }
    _sprites.clear();
    for (var i = 0; i < 64; i++) {
      final p = before.pieceAt(Square(i));
      if (p == null) continue;
      _sprites.add(_Sprite(keep[Square(i)] ?? _nextKey++, p, Square(i)));
    }
    assert(after.fen.isNotEmpty);
  }

  // --- geometry --------------------------------------------------------------

  Offset _squareOrigin(Square s, double sq) {
    final file = widget.orientation == Color.white ? s.file : 7 - s.file;
    final rank = widget.orientation == Color.white ? 7 - s.rank : s.rank;
    return Offset(file * sq, rank * sq);
  }

  Square? _squareAt(Offset local, double sq) {
    var f = (local.dx / sq).floor();
    var r = (local.dy / sq).floor();
    if (f < 0 || f > 7 || r < 0 || r > 7) return null;
    if (widget.orientation == Color.white) {
      r = 7 - r;
    } else {
      f = 7 - f;
    }
    return Square.fromFileRank(f, r);
  }

  // --- input -----------------------------------------------------------------

  List<Move> _movesFrom(Square s) => widget.position.legalMoves.where((mv) => mv.from == s).toList();

  Future<void> _tryMove(Square from, Square to) async {
    final candidates = _movesFrom(from).where((mv) => mv.to == to).toList();
    if (candidates.isEmpty) return;
    Move chosen;
    if (candidates.length > 1 && candidates.first.promotion != null) {
      final promo = await _askPromotion(widget.position.turn);
      if (promo == null) return;
      chosen = candidates.firstWhere((c) => c.promotion == promo);
    } else {
      chosen = candidates.first;
    }
    setState(() => _selected = null);
    widget.onMove?.call(chosen);
  }

  Future<PieceType?> _askPromotion(Color color) {
    final c = context.colors;
    return showModalBottomSheet<PieceType>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Promote to', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: Space.l),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final t in [PieceType.queen, PieceType.rook, PieceType.bishop, PieceType.knight])
                    Semantics(
                      button: true,
                      label: t.name,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(Radii.medium),
                        onTap: () => Navigator.pop(ctx, t),
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(color: c.surfaceSunken, borderRadius: BorderRadius.circular(Radii.medium)),
                          alignment: Alignment.center,
                          child: PieceImage(piece: Piece(color, t), set: widget.pieceSet, size: 52),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onTapUp(TapUpDetails d, double sq) {
    if (!widget.interactive) return;
    final s = _squareAt(d.localPosition, sq);
    if (s == null) return;
    final piece = widget.position.pieceAt(s);
    if (_selected != null) {
      if (_selected == s) {
        setState(() => _selected = null);
        return;
      }
      if (_movesFrom(_selected!).any((mv) => mv.to == s)) {
        _tryMove(_selected!, s);
        return;
      }
    }
    if (piece != null && piece.color == widget.position.turn) {
      setState(() => _selected = s);
    } else {
      setState(() => _selected = null);
    }
  }

  void _onPanStart(DragStartDetails d, double sq) {
    if (!widget.interactive) return;
    final s = _squareAt(d.localPosition, sq);
    if (s == null) return;
    final piece = widget.position.pieceAt(s);
    if (piece == null || piece.color != widget.position.turn) return;
    setState(() {
      _dragFrom = s;
      _selected = s;
      _dragPos = d.localPosition;
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_dragFrom == null) return;
    setState(() => _dragPos = d.localPosition);
  }

  void _onPanEnd(double sq) {
    final from = _dragFrom;
    final pos = _dragPos;
    setState(() {
      _dragFrom = null;
      _dragPos = null;
    });
    if (from == null || pos == null) return;
    final to = _squareAt(pos, sq);
    if (to != null && to != from) _tryMove(from, to);
  }

  // --- paint -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (light, dark) = _boardColors(widget.boardStyle, c);
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (context, constraints) {
        final size = constraints.biggest.shortestSide;
        final sq = size / 8;
        final dur = motion(context, const Duration(milliseconds: 170));
        final checkSquare = widget.position.isCheck ? widget.position.kingSquare(widget.position.turn) : null;
        final dests = _selected != null ? _movesFrom(_selected!).map((mv) => mv.to).toSet() : const <Square>{};
        return Semantics(
          label: 'Chess board',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _onTapUp(d, sq),
            onPanStart: (d) => _onPanStart(d, sq),
            onPanUpdate: _onPanUpdate,
            onPanEnd: (_) => _onPanEnd(sq),
            onPanCancel: () => _onPanEnd(sq),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.small),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CustomPaint(
                    size: Size.square(size),
                    painter: _SquaresPainter(
                      light: light,
                      dark: dark,
                      coordLight: c.boardCoordinatesOnLight,
                      coordDark: c.boardCoordinatesOnDark,
                      orientation: widget.orientation,
                      lastMove: widget.lastMove,
                      lastMoveColor: c.lastMove,
                      selected: _selected,
                      selectedColor: c.selected,
                      dests: dests,
                      destColor: c.destination,
                      occupied: {for (final s in _sprites) s.square},
                      check: checkSquare,
                      checkColor: c.check,
                      showCoordinates: widget.showCoordinates,
                    ),
                  ),
                  for (final s in _sprites)
                    if (s.square != _dragFrom || _dragPos == null)
                      AnimatedPositioned(
                        key: ValueKey(s.key),
                        duration: _animate ? dur : Duration.zero,
                        curve: Curves.easeOut,
                        left: _squareOrigin(s.square, sq).dx,
                        top: _squareOrigin(s.square, sq).dy,
                        width: sq,
                        height: sq,
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: widget.dimmed ? 0.55 : 1,
                            child: PieceImage(piece: s.piece, set: widget.pieceSet, size: sq),
                          ),
                        ),
                      ),
                  if (widget.arrows.isNotEmpty)
                    IgnorePointer(
                      child: CustomPaint(
                        size: Size.square(size),
                        painter: _ArrowPainter(widget.arrows, widget.orientation),
                      ),
                    ),
                  if (widget.badge != null) _badge(widget.badge!, sq, c, dur),
                  if (_dragFrom != null && _dragPos != null)
                    Positioned(
                      left: _dragPos!.dx - sq * 0.6,
                      top: _dragPos!.dy - sq * 0.6,
                      width: sq * 1.2,
                      height: sq * 1.2,
                      child: IgnorePointer(
                        child: PieceImage(piece: widget.position.pieceAt(_dragFrom!)!, set: widget.pieceSet, size: sq * 1.2),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _badge(BoardBadge b, double sq, ReviewColors c, Duration dur) {
    final glyph = switch (b.label) {
      MoveLabel.best => '★',
      MoveLabel.excellent => '!',
      MoveLabel.inaccuracy => '?!',
      MoveLabel.mistake => '?',
      MoveLabel.missedWin => '✕',
      MoveLabel.blunder => '??',
      _ => '',
    };
    if (glyph.isEmpty) return const SizedBox.shrink();
    final size = sq * 0.46;
    final o = _squareOrigin(b.square, sq);
    final onEdge = (widget.orientation == Color.white ? b.square.file == 7 : b.square.file == 0);
    final dx = onEdge ? o.dx + sq - size : o.dx + sq - size * 0.7;
    final dy = (widget.orientation == Color.white ? b.square.rank == 7 : b.square.rank == 0) ? o.dy : o.dy - size * 0.3;
    return Positioned(
      left: dx,
      top: dy,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          key: ValueKey('${b.square.index}-${b.label.name}'),
          tween: Tween(begin: dur == Duration.zero ? 1 : 0.6, end: 1),
          duration: dur,
          curve: Curves.easeOut,
          builder: (_, t, child) => Transform.scale(scale: t, child: child),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: c.forLabel(b.label),
              shape: BoxShape.circle,
              boxShadow: const [BoxShadow(color: m.Color(0x55000000), blurRadius: 1.5, offset: Offset(0, 1))],
            ),
            alignment: Alignment.center,
            child: FittedBox(
              child: Padding(
                padding: EdgeInsets.all(size * 0.14),
                child: Text(
                  glyph,
                  style: const TextStyle(color: m.Color(0xFFFFFFFF), fontWeight: FontWeight.w800, fontSize: 14, height: 1),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

(m.Color, m.Color) _boardColors(BoardStyle style, ReviewColors c) => switch (style) {
      BoardStyle.brown => (c.boardLight, c.boardDark),
      BoardStyle.blue => (const m.Color(0xFFDEE3E6), const m.Color(0xFF8CA2AD)),
      BoardStyle.green => (const m.Color(0xFFEEEED2), const m.Color(0xFF86A666)),
      BoardStyle.grey => (const m.Color(0xFFBDBDBD), const m.Color(0xFF7E7E7E)),
    };

class _SquaresPainter extends CustomPainter {
  _SquaresPainter({
    required this.light,
    required this.dark,
    required this.coordLight,
    required this.coordDark,
    required this.orientation,
    required this.lastMove,
    required this.lastMoveColor,
    required this.selected,
    required this.selectedColor,
    required this.dests,
    required this.destColor,
    required this.occupied,
    required this.check,
    required this.checkColor,
    required this.showCoordinates,
  });

  final m.Color light, dark, coordLight, coordDark, lastMoveColor, selectedColor, destColor, checkColor;
  final Color orientation;
  final Move? lastMove;
  final Square? selected;
  final Set<Square> dests;
  final Set<Square> occupied;
  final Square? check;
  final bool showCoordinates;

  Rect _rect(Square s, double sq) {
    final file = orientation == Color.white ? s.file : 7 - s.file;
    final rank = orientation == Color.white ? 7 - s.rank : s.rank;
    return Rect.fromLTWH(file * sq, rank * sq, sq, sq);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final sq = size.width / 8;
    final paint = Paint();
    for (var i = 0; i < 64; i++) {
      final s = Square(i);
      paint.color = s.isLight ? light : dark;
      canvas.drawRect(_rect(s, sq), paint);
    }
    if (lastMove != null) {
      paint.color = lastMoveColor;
      canvas.drawRect(_rect(lastMove!.from, sq), paint);
      canvas.drawRect(_rect(lastMove!.to, sq), paint);
    }
    if (check != null) {
      final r = _rect(check!, sq);
      canvas.drawCircle(r.center, sq * 0.45, Paint()
        ..shader = RadialGradient(colors: [checkColor, checkColor.withValues(alpha: 0)]).createShader(r));
    }
    if (selected != null) {
      paint.color = selectedColor;
      canvas.drawRect(_rect(selected!, sq), paint);
    }
    for (final d in dests) {
      final r = _rect(d, sq);
      paint.color = destColor;
      if (occupied.contains(d)) {
        canvas.drawCircle(r.center, sq * 0.46, Paint()
          ..color = destColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = sq * 0.08);
      } else {
        canvas.drawCircle(r.center, sq * 0.17, paint);
      }
    }
    if (showCoordinates) {
      final fontSize = sq * 0.19;
      for (var f = 0; f < 8; f++) {
        final file = orientation == Color.white ? f : 7 - f;
        final sqIsLight = Square.fromFileRank(file, orientation == Color.white ? 0 : 7).isLight;
        _text(canvas, 'abcdefgh'[file], Offset((f + 1) * sq - fontSize * 0.75, size.height - fontSize * 1.15),
            sqIsLight ? coordLight : coordDark, fontSize);
      }
      for (var r = 0; r < 8; r++) {
        final rank = orientation == Color.white ? 7 - r : r;
        final sqIsLight = Square.fromFileRank(orientation == Color.white ? 0 : 7, rank).isLight;
        _text(canvas, '${rank + 1}', Offset(sq * 0.08, r * sq + sq * 0.06), sqIsLight ? coordLight : coordDark, fontSize);
      }
    }
  }

  void _text(Canvas canvas, String s, Offset at, m.Color color, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_SquaresPainter o) =>
      o.light != light ||
      o.dark != dark ||
      o.orientation != orientation ||
      o.lastMove != lastMove ||
      o.selected != selected ||
      o.dests.length != dests.length ||
      !o.dests.containsAll(dests) ||
      o.check != check ||
      o.occupied.length != occupied.length ||
      o.showCoordinates != showCoordinates;
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter(this.arrows, this.orientation);
  final List<BoardArrow> arrows;
  final Color orientation;

  Offset _center(Square s, double sq) {
    final file = orientation == Color.white ? s.file : 7 - s.file;
    final rank = orientation == Color.white ? 7 - s.rank : s.rank;
    return Offset((file + 0.5) * sq, (rank + 0.5) * sq);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final sq = size.width / 8;
    for (final a in arrows) {
      final from = _center(a.from, sq);
      final to = _center(a.to, sq);
      final dir = (to - from);
      final len = dir.distance;
      if (len == 0) continue;
      final unit = dir / len;
      final width = sq * 0.16;
      final headLen = sq * 0.42;
      final headWidth = sq * 0.42;
      final start = from + unit * (sq * 0.33);
      final end = to - unit * (sq * 0.12);
      final shaftEnd = end - unit * headLen;
      final paint = Paint()
        ..color = a.color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.butt
        ..style = PaintingStyle.stroke;
      canvas.drawLine(start, shaftEnd, paint);
      final normal = Offset(-unit.dy, unit.dx);
      final path = Path()
        ..moveTo(end.dx, end.dy)
        ..lineTo(shaftEnd.dx + normal.dx * headWidth / 2, shaftEnd.dy + normal.dy * headWidth / 2)
        ..lineTo(shaftEnd.dx - normal.dx * headWidth / 2, shaftEnd.dy - normal.dy * headWidth / 2)
        ..close();
      canvas.drawPath(path, Paint()..color = a.color);
    }
  }

  @override
  bool shouldRepaint(_ArrowPainter o) => o.arrows != arrows || o.orientation != orientation;
}
