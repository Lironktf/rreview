import 'package:flutter/material.dart';
import 'package:review_core/review_core.dart';

import '../theme/tokens.dart';

/// Small coloured label, e.g. "Blunder".
class LabelChip extends StatelessWidget {
  const LabelChip({super.key, required this.label, this.compact = false});
  final MoveLabel label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = c.forLabel(label);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: compact ? 2 : 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(Radii.small),
      ),
      child: Text(
        label.display,
        style: TextStyle(fontSize: compact ? 11 : 13, fontWeight: FontWeight.w600, color: _darken(color, context)),
      ),
    );
  }

  static Color _darken(Color color, BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness + (dark ? 0.12 : -0.18)).clamp(0.0, 1.0)).toColor();
  }
}

/// A dot in the label colour, used in the move list.
class LabelDot extends StatelessWidget {
  const LabelDot(this.label, {super.key, this.size = 7});
  final MoveLabel label;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: context.colors.forLabel(label), shape: BoxShape.circle),
      );
}
