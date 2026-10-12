import 'package:chess_core/chess_core.dart';
import 'package:flutter/material.dart' hide Color;
import 'package:review_core/review_core.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';

/// Vertical evaluation bar. Fill = White's expected score; label = score.
class EvalBar extends StatelessWidget {
  const EvalBar({super.key, required this.eval, required this.orientation, this.width = 20, this.pending = false});

  final PositionEval? eval;
  final Color orientation;
  final double width;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = eval;
    final whiteShare = e == null ? 0.5 : _share(e);
    final label = e?.score.barLabel ?? '';
    final whiteAhead = e == null ? true : e.score.sign >= 0;
    final whiteAtBottom = orientation == Color.white;
    final labelStyle = TextStyle(
      fontSize: 9,
      fontWeight: FontWeight.w700,
      fontFeatures: tabularFigures,
      letterSpacing: -0.5,
      height: 1,
      color: whiteAhead ? c.evalDark : c.evalLight,
    );
    return Semantics(
      label: 'Evaluation ${e?.score.display ?? 'unknown'}',
      child: Opacity(
        opacity: pending ? 0.6 : 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.small),
          child: LayoutBuilder(builder: (context, box) {
            final h = box.maxHeight;
            final whiteH = h * whiteShare;
            return Stack(
              children: [
                Container(width: width, height: h, color: whiteAtBottom ? c.evalDark : c.evalLight),
                AnimatedPositioned(
                  duration: motion(context, const Duration(milliseconds: 350)),
                  curve: Curves.easeOutCubic,
                  left: 0,
                  right: 0,
                  top: whiteAtBottom ? h - whiteH : 0,
                  height: whiteH,
                  child: Container(color: whiteAtBottom ? c.evalLight : c.evalDark),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: (whiteAhead == whiteAtBottom) ? null : 3,
                  bottom: (whiteAhead == whiteAtBottom) ? 3 : null,
                  child: Text(label, textAlign: TextAlign.center, style: labelStyle),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  static double _share(PositionEval e) {
    if (e.score.isMate) return e.score.sign > 0 ? 1 : 0;
    // Expected score is too flat near 0 for a bar; blend with a cp curve so
    // +1.0 reads as clearly ahead without being near-full.
    final cp = e.score.cp!.clamp(-1000, 1000) / 100;
    final fromCp = 0.5 + 0.5 * (2 / (1 + _exp(-0.9 * cp)) - 1);
    return (0.5 * fromCp + 0.5 * e.wdl.expectedScore).clamp(0.03, 0.97);
  }

  static double _exp(double x) {
    // Avoid importing dart:math in a widget file for one call.
    var result = 1.0;
    var term = 1.0;
    for (var i = 1; i < 20; i++) {
      term *= x / i;
      result += term;
    }
    return result;
  }
}
