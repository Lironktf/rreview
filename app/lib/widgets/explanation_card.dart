import 'package:chess_core/chess_core.dart';
import 'package:flutter/material.dart' hide Color;
import 'package:review_core/review_core.dart';

import '../screens/review_controller.dart';
import '../theme/tokens.dart';
import 'label_chip.dart';

/// The card under the board: what happened on the current move and what to do
/// about it. Adapts to game / variation / retry / guided modes.
class ExplanationCard extends StatefulWidget {
  const ExplanationCard({super.key, required this.ctrl});
  final ReviewController ctrl;

  @override
  State<ExplanationCard> createState() => _ExplanationCardState();
}

class _ExplanationCardState extends State<ExplanationCard> {
  bool _expanded = false;
  ReviewController get ctrl => widget.ctrl;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 150),
        alignment: Alignment.topCenter,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.medium)),
          child: switch (ctrl.mode) {
            ReviewMode.variation => _variation(context, c, t),
            ReviewMode.retry => _retry(context, c, t),
            _ => _game(context, c, t),
          },
        ),
      ),
    );
  }

  Widget _game(BuildContext context, ReviewColors c, TextTheme t) {
    final r = ctrl.review;
    if (ctrl.cursor == 0) {
      final opening = r.openingName;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Start position', style: t.titleMedium),
          const SizedBox(height: Space.xs),
          Text(
            opening != null ? 'Opening: $opening${r.openingEco != null ? ' (${r.openingEco})' : ''}' : _statusLine(r),
            style: t.bodyMedium?.copyWith(color: c.textSecondary),
          ),
          if (r.keyMoments.isNotEmpty && !ctrl.guidedActive) ...[
            const SizedBox(height: Space.m),
            FilledButton.tonal(
              onPressed: ctrl.startGuided,
              style: FilledButton.styleFrom(backgroundColor: c.surfaceSunken, foregroundColor: c.textPrimary),
              child: Text('Review ${r.keyMoments.length} key moments'),
            ),
          ],
        ],
      );
    }
    final ply = r.game.plies[ctrl.cursor - 1];
    final m = ctrl.currentMove;
    if (m == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ply.numbered, style: t.titleMedium),
          const SizedBox(height: Space.xs),
          Text(r.status == ReviewStatus.running ? 'Analysing…' : _statusLine(r), style: t.bodyMedium?.copyWith(color: c.textSecondary)),
        ],
      );
    }
    final guided = ctrl.mode == ReviewMode.guided && ctrl.guidedActive;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(child: Text(ply.numbered, style: t.titleMedium, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: Space.s),
            LabelChip(label: m.label),
            const Spacer(),
            if (guided)
              Text('${ctrl.guidedIndex + 1} of ${ctrl.keyMoments.length}',
                  style: t.bodySmall?.copyWith(fontFeatures: tabularFigures)),
          ],
        ),
        if (m.explanation != null) ...[
          const SizedBox(height: Space.xs),
          Text(m.explanation!, style: t.bodyMedium, maxLines: _expanded ? null : 2, overflow: _expanded ? null : TextOverflow.ellipsis),
        ],
        if (m.label != MoveLabel.best && m.label != MoveLabel.book && !(m.explanation ?? '').contains(m.bestSan)) ...[
          const SizedBox(height: Space.xs),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: 'Best was ', style: t.bodySmall),
              TextSpan(text: m.bestSan, style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: c.textPrimary)),
              if (m.bestPvSan.length > 1)
                TextSpan(text: '  ${m.bestPvSan.skip(1).take(5).join(' ')}', style: t.bodySmall),
            ]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (m.label != MoveLabel.best && m.label != MoveLabel.book || guided) ...[
          const SizedBox(height: Space.s),
          Wrap(
            runSpacing: Space.s,
            children: [
              if (m.label.isBad)
                _smallButton(context, 'Try again', primary: true, onTap: () => ctrl.startRetry(ctrl.cursor - 1)),
              if (m.label != MoveLabel.best && m.label != MoveLabel.book)
                _smallButton(context, 'Best line', onTap: ctrl.showBestLine),
              if (guided)
                if (ctrl.guidedIndex < ctrl.keyMoments.length - 1)
                  _smallButton(context, 'Next moment', onTap: () => ctrl.guidedStep(1))
                else
                  _smallButton(context, 'Done', onTap: ctrl.endGuided),
            ],
          ),
        ],
      ],
    );
  }

  Widget _smallButton(BuildContext context, String label, {required VoidCallback onTap, bool primary = false}) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(right: Space.s),
      child: primary
          ? FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(minimumSize: const Size(44, 36), padding: const EdgeInsets.symmetric(horizontal: Space.m)),
              child: Text(label),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(44, 36), padding: const EdgeInsets.symmetric(horizontal: Space.m), foregroundColor: c.textPrimary),
              child: Text(label),
            ),
    );
  }

  Widget _variation(BuildContext context, ReviewColors c, TextTheme t) {
    final pos = ctrl.position;
    final e = ctrl.variationEval;
    final live = ctrl.variationLive;
    String line;
    String evalText;
    if (e != null) {
      line = Explainer.sanLine(pos, e.pv, maxPlies: 8);
      evalText = e.isTerminal ? (pos.isCheckmate ? 'Checkmate' : 'Draw') : '${e.score.display} · depth ${e.depth}';
    } else if (live != null) {
      final s = Score.fromUci(cp: live.cp, mate: live.mate, sideToMove: pos.turn);
      line = Explainer.sanLine(pos, live.pv, maxPlies: 8);
      evalText = '${s.display} · depth ${live.depth}…';
    } else {
      line = '';
      evalText = pos.legalMoves.isEmpty ? (pos.isCheckmate ? 'Checkmate' : 'Draw') : 'Evaluating…';
    }
    final varSan = <String>[];
    var p = ctrl.gamePosition;
    for (final m in ctrl.variation) {
      if (!p.isLegal(m)) break;
      varSan.add(p.turn == Color.white ? '${p.fullmoveNumber}. ${p.san(m)}' : (varSan.isEmpty ? '${p.fullmoveNumber}... ${p.san(m)}' : p.san(m)));
      p = p.play(m);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Variation', style: t.titleMedium)),
            TextButton(onPressed: ctrl.exitToGame, child: const Text('Back to game')),
          ],
        ),
        if (varSan.isNotEmpty) Text(varSan.join(' '), style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: Space.xs),
        Text(evalText, style: t.bodySmall?.copyWith(fontFeatures: tabularFigures)),
        if (line.isNotEmpty) ...[
          const SizedBox(height: Space.xs),
          Text(line, style: t.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ],
    );
  }

  Widget _retry(BuildContext context, ReviewColors c, TextTheme t) {
    final ply = ctrl.retryPly!;
    final mr = ctrl.review.moves[ply];
    final played = ctrl.game.plies[ply];
    final mover = played.color == Color.white ? 'White' : 'Black';
    Widget body;
    switch (ctrl.retryState) {
      case RetryState.waiting:
        body = Text('$mover played ${played.san}. Find a better move.', style: t.bodyMedium);
      case RetryState.correct:
        body = Text('That is the best move.', style: t.bodyMedium?.copyWith(color: c.success, fontWeight: FontWeight.w600));
      case RetryState.alsoGood:
        body = Text('Also good. The engine\'s first choice was ${mr?.bestSan}.', style: t.bodyMedium?.copyWith(color: c.success));
      case RetryState.wrong:
        final e = ctrl.retryEval;
        body = Text(
          e == null ? 'Checking…' : 'Not the best. After that the evaluation is ${e.score.display}.',
          style: t.bodyMedium,
        );
      case RetryState.revealed:
        body = Text('${mr?.bestSan} was best.${mr?.explanation != null ? ' ${mr!.explanation}' : ''}', style: t.bodyMedium);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Try again · ${played.numbered}', style: t.titleMedium, overflow: TextOverflow.ellipsis)),
            TextButton(onPressed: ctrl.exitToGame, child: const Text('Back to game')),
          ],
        ),
        const SizedBox(height: Space.xs),
        body,
        const SizedBox(height: Space.m),
        Wrap(
          spacing: Space.s,
          children: [
            if (ctrl.retryState == RetryState.wrong) FilledButton(onPressed: ctrl.retryAgain, child: const Text('Try another')),
            if (ctrl.retryState == RetryState.waiting || ctrl.retryState == RetryState.wrong)
              OutlinedButton(onPressed: ctrl.revealRetry, child: const Text('Show solution')),
            if (ctrl.retryState == RetryState.correct || ctrl.retryState == RetryState.alsoGood || ctrl.retryState == RetryState.revealed)
              OutlinedButton(onPressed: ctrl.exitToGame, child: const Text('Continue')),
          ],
        ),
      ],
    );
  }

  static String _statusLine(GameReview r) => switch (r.status) {
        ReviewStatus.pending => 'Waiting for the engine',
        ReviewStatus.running => r.phase,
        ReviewStatus.paused => 'Analysis paused',
        ReviewStatus.failed => r.error ?? 'Analysis failed',
        ReviewStatus.complete => 'Tap a move to see the engine\'s view',
      };
}
