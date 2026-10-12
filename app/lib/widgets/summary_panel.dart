import 'package:chess_core/chess_core.dart';
import 'package:flutter/material.dart' hide Color;
import 'package:review_core/review_core.dart';

import '../theme/tokens.dart';
import 'label_chip.dart';

/// Accuracy, move counts, opening and key moments for both players.
class SummaryPanel extends StatelessWidget {
  const SummaryPanel({super.key, required this.review, required this.onJump, required this.onGuided});
  final GameReview review;
  final void Function(int cursor) onJump;
  final VoidCallback onGuided;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final white = review.summaryFor(Color.white);
    final black = review.summaryFor(Color.black);
    final labels = [
      MoveLabel.best,
      MoveLabel.excellent,
      MoveLabel.good,
      MoveLabel.book,
      MoveLabel.inaccuracy,
      MoveLabel.mistake,
      MoveLabel.missedWin,
      MoveLabel.blunder,
    ];
    final key = review.keyMoments;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(context, 'Accuracy'),
        Container(
          padding: const EdgeInsets.all(Space.l),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.medium)),
          child: Row(
            children: [
              Expanded(child: _accuracy(context, review.game.white, white.accuracy)),
              Container(width: 1, height: 44, color: c.hairline),
              Expanded(child: _accuracy(context, review.game.black, black.accuracy)),
            ],
          ),
        ),
        const SizedBox(height: Space.xs),
        Text(
          'OpenReview accuracy: 100 × e^(−4.2 × expected-score loss) per move, averaged. Not comparable with other sites.',
          style: t.bodySmall?.copyWith(color: c.textTertiary),
        ),
        const SizedBox(height: Space.xl),
        _section(context, 'Moves'),
        Container(
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.medium)),
          child: Column(
            children: [
              for (final l in labels)
                if (white.count(l) + black.count(l) > 0 || l.isBad)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 36,
                          child: Text('${white.count(l)}',
                              textAlign: TextAlign.right,
                              style: t.bodyMedium?.copyWith(fontFeatures: tabularFigures, fontWeight: FontWeight.w600)),
                        ),
                        Expanded(
                          child: Center(child: LabelChip(label: l, compact: true)),
                        ),
                        SizedBox(
                          width: 36,
                          child: Text('${black.count(l)}',
                              style: t.bodyMedium?.copyWith(fontFeatures: tabularFigures, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: Space.xs),
            ],
          ),
        ),
        const SizedBox(height: Space.xl),
        if (review.openingName != null) ...[
          _section(context, 'Opening'),
          Container(
            padding: const EdgeInsets.all(Space.l),
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.medium)),
            child: Row(
              children: [
                Expanded(child: Text(review.openingName!, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                if (review.openingEco != null) Text(review.openingEco!, style: t.bodySmall),
                const SizedBox(width: Space.s),
                Text('${review.bookPlies} book plies', style: t.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: Space.xl),
        ],
        Row(
          children: [
            Expanded(child: _section(context, 'Key moments')),
            if (key.isNotEmpty) TextButton(onPressed: onGuided, child: const Text('Guided review')),
          ],
        ),
        if (key.isEmpty)
          Text(
            review.isComplete ? 'No serious mistakes found. Clean game.' : 'Available once the analysis has run.',
            style: t.bodyMedium?.copyWith(color: c.textSecondary),
          )
        else
          Material(
            color: c.surface,
            borderRadius: BorderRadius.circular(Radii.medium),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final i in key)
                  ListTile(
                    dense: true,
                    onTap: () => onJump(i + 1),
                    leading: LabelDot(review.moves[i]!.label, size: 10),
                    title: Text(review.game.plies[i].numbered, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    subtitle: Text(review.moves[i]!.explanation ?? review.moves[i]!.label.display,
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                    trailing: Text(
                      '${review.moves[i]!.before.score.display} → ${review.moves[i]!.after.score.display}',
                      style: t.bodySmall?.copyWith(fontFeatures: tabularFigures),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: Space.xl),
        _section(context, 'Analysis'),
        Text(
          '${review.engineId} · ${review.settings.label} (depth ${review.settings.passDepth}, key moments to ${review.settings.refineDepth})'
          '${review.status == ReviewStatus.complete ? '' : ' · ${review.phase}'}',
          style: t.bodySmall,
        ),
      ],
    );
  }

  Widget _section(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.only(bottom: Space.s, top: Space.xs),
        child: Text(title, style: Theme.of(context).textTheme.labelMedium),
      );

  Widget _accuracy(BuildContext context, String name, double? acc) {
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(
          acc == null ? '–' : acc.toStringAsFixed(1),
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, fontFeatures: tabularFigures, color: context.colors.textPrimary, height: 1.1),
        ),
        const SizedBox(height: 2),
        Text(name, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}
