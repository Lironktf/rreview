import 'package:flutter/material.dart';
import 'package:review_core/review_core.dart';

import '../theme/tokens.dart';

/// Evaluation over time. Tap or drag to jump to a ply.
class EvalGraph extends StatelessWidget {
  const EvalGraph({super.key, required this.review, required this.cursor, required this.onSelect, this.height = 88});

  final GameReview review;

  /// Number of plies played (0 = start position).
  final int cursor;
  final void Function(int cursor) onSelect;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = review.game.plies.length;
    return Semantics(
      label: 'Evaluation graph',
      child: LayoutBuilder(builder: (context, box) {
        void pick(Offset local) {
          final x = (local.dx / box.maxWidth).clamp(0.0, 1.0);
          onSelect((x * n).round().clamp(0, n));
        }
        return GestureDetector(
          onTapDown: (d) => pick(d.localPosition),
          onHorizontalDragUpdate: (d) => pick(d.localPosition),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.small),
            child: CustomPaint(
              size: Size(box.maxWidth, height),
              painter: _GraphPainter(review, cursor, c),
            ),
          ),
        );
      }),
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter(this.review, this.cursor, this.c);
  final GameReview review;
  final int cursor;
  final ReviewColors c;

  @override
  void paint(Canvas canvas, Size size) {
    final n = review.game.plies.length;
    canvas.drawRect(Offset.zero & size, Paint()..color = c.surfaceSunken);
    final mid = size.height / 2;
    const limit = 5.0;
    double y(double pawns) => mid - (pawns / limit) * (mid - 4);
    double x(int i) => n == 0 ? 0 : size.width * i / n;

    // Values per cursor position 0..n.
    final values = List<double?>.filled(n + 1, null);
    for (var i = 0; i < n; i++) {
      final m = review.moves[i];
      if (m == null) continue;
      values[i] ??= m.before.score.clampedPawns(limit);
      values[i + 1] = m.after.score.clampedPawns(limit);
    }
    final whiteFill = Path()..moveTo(0, mid);
    final blackFill = Path()..moveTo(0, mid);
    var any = false;
    for (var i = 0; i <= n; i++) {
      final v = values[i];
      if (v == null) continue;
      any = true;
      final px = x(i);
      final py = y(v);
      whiteFill.lineTo(px, v >= 0 ? py : mid);
      blackFill.lineTo(px, v < 0 ? py : mid);
    }
    if (any) {
      final lastX = x(values.lastIndexWhere((v) => v != null));
      whiteFill
        ..lineTo(lastX, mid)
        ..close();
      blackFill
        ..lineTo(lastX, mid)
        ..close();
      canvas.drawPath(whiteFill, Paint()..color = c.evalLight);
      canvas.drawPath(blackFill, Paint()..color = c.evalDark);
    }
    // Centre line.
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), Paint()
      ..color = c.textTertiary.withValues(alpha: 0.5)
      ..strokeWidth = 1);
    // Key-moment dots.
    for (var i = 0; i < n; i++) {
      final m = review.moves[i];
      if (m == null || !m.label.isBad) continue;
      final v = values[i + 1];
      if (v == null) continue;
      canvas.drawCircle(Offset(x(i + 1), y(v)), 3.5, Paint()..color = c.forLabel(m.label));
    }
    // Cursor.
    final cx = x(cursor.clamp(0, n));
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), Paint()
      ..color = c.accent
      ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_GraphPainter o) => o.cursor != cursor || o.review != review || o.c != c;
}
