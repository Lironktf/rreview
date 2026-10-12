import 'package:chess_core/chess_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../services/settings_service.dart';

String pieceAsset(PieceSet set, Piece p) {
  final c = p.color == Color.white ? 'w' : 'b';
  final t = p.type.san.isEmpty ? 'P' : p.type.san;
  return 'assets/pieces/${set.name}/$c$t.svg';
}

class PieceImage extends StatelessWidget {
  const PieceImage({super.key, required this.piece, required this.set, required this.size});
  final Piece piece;
  final PieceSet set;
  final double size;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        pieceAsset(set, piece),
        width: size,
        height: size,
        excludeFromSemantics: true,
      );
}

/// Warm the SVG cache so the first board paints without pops.
Future<void> precachePieces(BuildContext context, PieceSet set) async {
  for (final c in Color.values) {
    for (final t in PieceType.values) {
      final loader = SvgAssetLoader(pieceAsset(set, Piece(c, t)));
      await svg.cache.putIfAbsent(loader.cacheKey(context), () => loader.loadBytes(context));
    }
  }
}
