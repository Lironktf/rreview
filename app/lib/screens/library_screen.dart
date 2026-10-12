import 'package:chess_core/chess_core.dart';
import 'package:flutter/material.dart' hide Color;
import 'package:review_core/review_core.dart';

import '../services/app_scope.dart';
import '../services/engine_service.dart';
import '../theme/tokens.dart';
import '../widgets/label_chip.dart';
import 'import_sheet.dart';
import 'review_screen.dart';
import 'settings_screen.dart';

void openReview(BuildContext context, String id) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReviewScreen(reviewId: id)));
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final id = await showImportSheet(context);
    if (id != null && mounted) openReview(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('rreview'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([s.analysis, s.engine.state]),
        builder: (context, _) {
          final all = s.analysis.reviews;
          final q = _query.trim().toLowerCase();
          final list = q.isEmpty
              ? all
              : all.where((r) {
                  final g = r.game;
                  return g.white.toLowerCase().contains(q) ||
                      g.black.toLowerCase().contains(q) ||
                      (r.openingName ?? '').toLowerCase().contains(q) ||
                      (g.event ?? '').toLowerCase().contains(q) ||
                      (g.date ?? '').contains(q);
                }).toList();
          final engine = s.engine.state.value;
          return Column(
            children: [
              if (engine.status == EngineStatus.installing || engine.status == EngineStatus.failed)
                _engineBanner(context, engine),
              if (all.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
                  child: TextField(
                    controller: _search,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Search players, openings, events',
                      prefixIcon: Icon(Icons.search_rounded, color: c.textTertiary),
                      isDense: true,
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              }),
                    ),
                  ),
                ),
              Expanded(
                child: all.isEmpty
                    ? _empty(context)
                    : list.isEmpty
                        ? Center(child: Text('No games match "$_query"', style: t.bodyMedium?.copyWith(color: c.textSecondary)))
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, 96),
                            itemCount: list.length,
                            separatorBuilder: (_, _) => const SizedBox(height: Space.s),
                            itemBuilder: (context, i) => _GameTile(review: list[i], onOpen: () => openReview(context, list[i].id)),
                          ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _import,
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        elevation: 1,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Import game'),
      ),
    );
  }

  Widget _engineBanner(BuildContext context, EngineState e) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.medium)),
      child: Row(
        children: [
          if (e.status == EngineStatus.installing)
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, value: e.progress > 0 ? e.progress : null))
          else
            Icon(Icons.error_outline_rounded, color: c.danger, size: 20),
          const SizedBox(width: Space.m),
          Expanded(child: Text(e.message, style: t.bodySmall?.copyWith(color: c.textPrimary))),
          if (e.status == EngineStatus.failed)
            TextButton(onPressed: () => AppScope.of(context).engine.start(), child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('No games yet', style: t.titleLarge),
            const SizedBox(height: Space.s),
            Text(
              'Finish a game on Chess.com, tap Share, and pick rreview. '
              'Or import a game link, paste PGN, or open a .pgn file.',
              style: t.bodyMedium?.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: Space.l),
            Text('Every review runs on this device with Stockfish 19. No account, no limits.',
                style: t.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({required this.review, required this.onOpen});
  final GameReview review;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final g = review.game;
    final w = review.summaryFor(Color.white);
    final b = review.summaryFor(Color.black);
    final worst = _worstLabel();
    return Dismissible(
      key: ValueKey(review.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: Space.l),
        decoration: BoxDecoration(color: c.danger, borderRadius: BorderRadius.circular(Radii.medium)),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) async {
        final removed = review;
        await s.analysis.delete(review.id);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Deleted ${g.white} – ${g.black}'),
          action: SnackBarAction(label: 'Undo', onPressed: () => s.analysis.restore(removed)),
        ));
      },
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.medium),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.medium),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('${g.white} – ${g.black}',
                          style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: Space.s),
                    Text(_resultText(g), style: t.bodyMedium?.copyWith(fontFeatures: tabularFigures, color: c.textSecondary)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(_subtitle(g), style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: Space.s),
                Row(
                  children: [
                    if (review.status == ReviewStatus.complete) ...[
                      _acc(context, w.accuracy),
                      const SizedBox(width: Space.xs),
                      Text('·', style: t.bodySmall),
                      const SizedBox(width: Space.xs),
                      _acc(context, b.accuracy),
                      const Spacer(),
                      if (worst != null) LabelChip(label: worst, compact: true),
                    ] else ...[
                      Expanded(
                        child: Row(
                          children: [
                            if (review.status == ReviewStatus.running || review.status == ReviewStatus.pending)
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                    strokeWidth: 1.5, value: review.status == ReviewStatus.pending ? null : review.progress, color: c.accent),
                              )
                            else
                              Icon(review.status == ReviewStatus.failed ? Icons.error_outline_rounded : Icons.pause_circle_outline_rounded,
                                  size: 14, color: c.textTertiary),
                            const SizedBox(width: Space.s),
                            Expanded(
                              child: Text(
                                switch (review.status) {
                                  ReviewStatus.pending => 'Queued',
                                  ReviewStatus.running => review.phase,
                                  ReviewStatus.paused => 'Paused · ${review.analysedCount} of ${g.plies.length} moves',
                                  ReviewStatus.failed => review.error ?? 'Failed',
                                  ReviewStatus.complete => '',
                                },
                                style: t.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (review.status == ReviewStatus.running || review.status == ReviewStatus.pending)
                        TextButton(onPressed: () => s.analysis.cancel(review.id), child: const Text('Pause'))
                      else
                        TextButton(onPressed: () => s.analysis.enqueue(review.id), child: const Text('Resume')),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  MoveLabel? _worstLabel() {
    MoveLabel? worst;
    for (final m in review.moves) {
      if (m == null || !m.label.isBad) continue;
      if (worst == null || m.label.index > worst.index) worst = m.label;
    }
    return worst;
  }

  Widget _acc(BuildContext context, double? a) => Text(
        a == null ? '–' : a.toStringAsFixed(1),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, fontFeatures: tabularFigures),
      );

  static String _resultText(Game g) => switch (g.result) {
        GameResult.whiteWins => '1–0',
        GameResult.blackWins => '0–1',
        GameResult.draw => '½–½',
        GameResult.unknown => '*',
      };

  static String _subtitle(Game g) {
    final parts = <String>[];
    final date = g.date;
    if (date != null && date.isNotEmpty && !date.contains('?')) parts.add(date.replaceAll('.', '-'));
    final tc = g.timeControl;
    if (tc != null && tc != '-') parts.add(_timeControl(tc));
    final site = g.link ?? g.site;
    if (site != null) {
      if (site.contains('chess.com')) parts.add('Chess.com');
      if (site.contains('lichess')) parts.add('Lichess');
    }
    if (g.chess960) parts.add('Chess960');
    parts.add('${(g.plies.length + 1) ~/ 2} moves');
    return parts.join(' · ');
  }

  static String _timeControl(String tc) {
    final m = RegExp(r'^(\d+)(?:\+(\d+))?$').firstMatch(tc);
    if (m == null) return tc;
    final secs = int.parse(m.group(1)!);
    final inc = m.group(2);
    final base = secs % 60 == 0 ? '${secs ~/ 60}' : (secs / 60).toStringAsFixed(1);
    return inc == null || inc == '0' ? '$base min' : '$base+$inc';
  }
}
