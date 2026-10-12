import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// First / previous / next / last + flip, in a bottom toolbar.
class NavBar extends StatelessWidget {
  const NavBar({
    super.key,
    required this.onFirst,
    required this.onPrev,
    required this.onNext,
    required this.onLast,
    required this.onFlip,
    this.canPrev = true,
    this.canNext = true,
    this.leading,
  });

  final VoidCallback onFirst, onPrev, onNext, onLast, onFlip;
  final bool canPrev, canNext;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.only(left: Space.s, right: Space.s, top: Space.xs, bottom: MediaQuery.paddingOf(context).bottom + Space.xs),
      decoration: BoxDecoration(color: c.background, border: Border(top: BorderSide(color: c.hairline))),
      child: Row(
        children: [
          IconButton(tooltip: 'Flip board', onPressed: onFlip, icon: const Icon(Icons.swap_vert_rounded)),
          ?leading,
          const Spacer(),
          IconButton(tooltip: 'First move', onPressed: canPrev ? onFirst : null, icon: const Icon(Icons.first_page_rounded)),
          IconButton(
            tooltip: 'Previous move',
            onPressed: canPrev ? onPrev : null,
            iconSize: 30,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          IconButton(
            tooltip: 'Next move',
            onPressed: canNext ? onNext : null,
            iconSize: 30,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          IconButton(tooltip: 'Last move', onPressed: canNext ? onLast : null, icon: const Icon(Icons.last_page_rounded)),
        ],
      ),
    );
  }
}
