import 'package:chess_core/chess_core.dart';
import 'package:flutter/material.dart' hide Color;
import 'package:review_core/review_core.dart';

import '../theme/tokens.dart';

/// Name, rating and accuracy for one side.
class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key, required this.review, required this.color, this.clock});
  final GameReview review;
  final Color color;
  final Duration? clock;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final g = review.game;
    final name = color == Color.white ? g.white : g.black;
    final elo = color == Color.white ? g.whiteElo : g.blackElo;
    final summary = review.summaryFor(color);
    final acc = summary.accuracy;
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color == Color.white ? c.evalLight : c.evalDark,
              border: Border.all(color: c.hairline),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: Space.s),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.textPrimary)),
                if (elo != null)
                  TextSpan(text: '  $elo', style: TextStyle(fontSize: 13, color: c.textTertiary, fontFeatures: tabularFigures)),
              ]),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (clock != null)
            Padding(
              padding: const EdgeInsets.only(right: Space.m),
              child: Text(_clock(clock!), style: TextStyle(fontSize: 13, color: c.textTertiary, fontFeatures: tabularFigures)),
            ),
          if (acc != null)
            Semantics(
              label: 'Accuracy ${acc.toStringAsFixed(1)}',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: c.surfaceSunken, borderRadius: BorderRadius.circular(Radii.small)),
                child: Text(
                  acc.toStringAsFixed(1),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.textPrimary, fontFeatures: tabularFigures),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _clock(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (d.inHours > 0) return '${d.inHours}:${(m % 60).toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
