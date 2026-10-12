import 'package:chess_core/chess_core.dart';
import 'package:flutter/material.dart' hide Color;
import 'package:review_core/review_core.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';
import 'label_chip.dart';

/// Two-column annotated move list. Tapping a move jumps to the position after it.
class MoveList extends StatefulWidget {
  const MoveList({super.key, required this.review, required this.cursor, required this.onSelect, this.shrinkWrap = false});
  final GameReview review;
  final int cursor;
  final void Function(int cursor) onSelect;
  final bool shrinkWrap;

  @override
  State<MoveList> createState() => _MoveListState();
}

class _MoveListState extends State<MoveList> {
  final _keys = <int, GlobalKey>{};

  @override
  void didUpdateWidget(MoveList old) {
    super.didUpdateWidget(old);
    if (old.cursor != widget.cursor) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final k = _keys[(widget.cursor - 1).clamp(0, 1 << 20) ~/ 2];
        final ctx = k?.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(ctx, alignment: 0.4, duration: motion(context, const Duration(milliseconds: 200)));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final plies = widget.review.game.plies;
    if (plies.isEmpty) return const SizedBox.shrink();
    final firstNumber = plies.first.moveNumber;
    final firstIsBlack = plies.first.color == Color.black;
    final rows = <List<int?>>[]; // [whitePly?, blackPly?]
    var i = 0;
    if (firstIsBlack) {
      rows.add([null, 0]);
      i = 1;
    }
    for (; i < plies.length; i += 2) {
      rows.add([i, i + 1 < plies.length ? i + 1 : null]);
    }
    return ListView.builder(
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: widget.shrinkWrap ? EdgeInsets.zero : const EdgeInsets.symmetric(vertical: Space.s),
      itemCount: rows.length,
      itemBuilder: (context, r) {
        final row = rows[r];
        final key = _keys.putIfAbsent(r, GlobalKey.new);
        final number = firstNumber + r;
        return SizedBox(
          key: key,
          height: 40,
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  '$number.',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 13, color: context.colors.textTertiary, fontFeatures: tabularFigures),
                ),
              ),
              const SizedBox(width: Space.s),
              Expanded(child: _cell(context, row[0])),
              Expanded(child: _cell(context, row[1])),
            ],
          ),
        );
      },
    );
  }

  Widget _cell(BuildContext context, int? ply) {
    if (ply == null) return const SizedBox.shrink();
    final c = context.colors;
    final p = widget.review.game.plies[ply];
    final m = ply < widget.review.moves.length ? widget.review.moves[ply] : null;
    final selected = widget.cursor == ply + 1;
    final label = m?.label;
    return Semantics(
      button: true,
      selected: selected,
      label: '${p.numbered}${label != null ? ', ${label.display}' : ''}',
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.small),
        onTap: () => widget.onSelect(ply + 1),
        child: Container(
          height: 36,
          margin: const EdgeInsets.only(right: Space.s),
          padding: const EdgeInsets.symmetric(horizontal: Space.s),
          decoration: BoxDecoration(
            color: selected ? c.accent.withValues(alpha: 0.14) : null,
            borderRadius: BorderRadius.circular(Radii.small),
          ),
          child: Row(
            children: [
              Text(
                p.san,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.textPrimary),
              ),
              if (label != null && label.glyph.isNotEmpty) ...[
                const SizedBox(width: 2),
                Text(label.glyph, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.forLabel(label))),
              ],
              const Spacer(),
              if (label != null && (label.isBad || label == MoveLabel.best)) LabelDot(label),
              if (m == null && widget.review.status == ReviewStatus.running)
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: c.textTertiary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
