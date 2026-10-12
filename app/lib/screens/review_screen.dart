import 'dart:ui' as ui;

import 'package:chess_core/chess_core.dart';
import 'package:flutter/material.dart' hide Color;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:review_core/review_core.dart';
import 'package:share_plus/share_plus.dart';

import '../services/app_scope.dart';
import '../theme/tokens.dart';
import '../widgets/board/board.dart';
import '../widgets/eval_bar.dart';
import '../widgets/eval_graph.dart';
import '../widgets/explanation_card.dart';
import '../widgets/move_list.dart';
import '../widgets/nav_bar.dart';
import '../widgets/player_bar.dart';
import '../widgets/summary_panel.dart';
import 'review_controller.dart';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.reviewId});
  final String reviewId;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late ReviewController ctrl;
  int _tab = 0;
  final _shareKey = GlobalKey();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    final s = AppScope.read(context);
    final review = s.analysis.byId(widget.reviewId)!;
    Color orientation = Color.white;
    if (s.settings.autoFlipToMe) {
      final mine = s.settings.chesscomUsernames
          .map((u) => u.toLowerCase())
          .toSet();
      if (mine.contains(review.game.black.toLowerCase()) &&
          !mine.contains(review.game.white.toLowerCase())) {
        orientation = Color.black;
      }
    }
    ctrl = ReviewController(
      analysis: s.analysis,
      reviewId: widget.reviewId,
      orientation: orientation,
    );
  }

  @override
  void dispose() {
    ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = context.colors;
    return ListenableBuilder(
      listenable: Listenable.merge([ctrl, s.settings]),
      builder: (context, _) {
        final r = ctrl.review;
        final g = r.game;
        final top = ctrl.orientation.opposite;
        final bottom = ctrl.orientation;
        final current = ctrl.currentMove;
        final showBadge =
            s.settings.showBadges &&
            ctrl.mode != ReviewMode.variation &&
            ctrl.mode != ReviewMode.retry &&
            current != null &&
            current.label != MoveLabel.good &&
            current.label != MoveLabel.book;
        final arrows = <BoardArrow>[];
        if (s.settings.showBestArrow &&
            ctrl.mode != ReviewMode.variation &&
            ctrl.mode != ReviewMode.retry &&
            current != null &&
            current.label.isBad) {
          final best = Move.parseUci(current.before.bestMove);
          if (best != null) {
            arrows.add(BoardArrow(best.from, best.to, c.arrowBest));
          }
        }
        if (ctrl.mode == ReviewMode.variation) {
          final e = ctrl.variationEval;
          final first = e != null && !e.isTerminal
              ? Move.parseUci(e.bestMove)
              : null;
          if (first != null) {
            arrows.add(BoardArrow(first.from, first.to, c.arrowBest));
          }
        }
        final clocks = _clocks();
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowLeft): ctrl.prev,
            const SingleActivator(LogicalKeyboardKey.arrowRight): ctrl.next,
            const SingleActivator(LogicalKeyboardKey.arrowUp): ctrl.first,
            const SingleActivator(LogicalKeyboardKey.arrowDown): ctrl.last,
            const SingleActivator(LogicalKeyboardKey.keyF): ctrl.flip,
            const SingleActivator(LogicalKeyboardKey.escape): ctrl.exitToGame,
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              appBar: AppBar(
                title: Text(
                  '${g.white} – ${g.black}',
                  overflow: TextOverflow.ellipsis,
                ),
                actions: [
                  IconButton(
                    tooltip: 'Share summary',
                    onPressed: _share,
                    icon: const Icon(Icons.ios_share_rounded),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'reanalyze') _reanalyze();
                      if (v == 'pgn') _sharePgn();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'reanalyze',
                        child: Text('Analyse again…'),
                      ),
                      const PopupMenuItem(
                        value: 'pgn',
                        child: Text('Share PGN'),
                      ),
                    ],
                  ),
                ],
              ),
              body: Column(
                children: [
                  if (r.status == ReviewStatus.running ||
                      r.status == ReviewStatus.pending)
                    LinearProgressIndicator(
                      value: r.status == ReviewStatus.pending
                          ? null
                          : r.progress,
                      minHeight: 2,
                      backgroundColor: c.surfaceSunken,
                      color: c.accent,
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.l,
                      Space.xs,
                      Space.l,
                      0,
                    ),
                    child: PlayerBar(review: r, color: top, clock: clocks[top]),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.l),
                    child: LayoutBuilder(
                      builder: (context, box) {
                        const barWidth = 20.0;
                        final maxBoard =
                            MediaQuery.sizeOf(context).height * 0.52;
                        final boardSize = (box.maxWidth - barWidth - Space.s)
                            .clamp(120.0, maxBoard);
                        return RepaintBoundary(
                          key: _shareKey,
                          child: SizedBox(
                            height: boardSize,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: barWidth,
                                  height: boardSize,
                                  child: EvalBar(
                                    eval: ctrl.displayedEval,
                                    orientation: ctrl.orientation,
                                    pending:
                                        ctrl.mode == ReviewMode.variation &&
                                        ctrl.variationEval == null,
                                  ),
                                ),
                                const SizedBox(width: Space.s),
                                SizedBox(
                                  width: boardSize,
                                  height: boardSize,
                                  child: ChessBoard(
                                    position: ctrl.position,
                                    orientation: ctrl.orientation,
                                    pieceSet: s.settings.pieceSet,
                                    boardStyle: s.settings.boardStyle,
                                    lastMove: ctrl.lastMove,
                                    arrows: arrows,
                                    badge: showBadge
                                        ? BoardBadge(
                                            g.plies[ctrl.cursor - 1].move.to,
                                            current.label,
                                          )
                                        : null,
                                    interactive: true,
                                    onMove: ctrl.onBoardMove,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.l,
                      0,
                      Space.l,
                      Space.xs,
                    ),
                    child: PlayerBar(
                      review: r,
                      color: bottom,
                      clock: clocks[bottom],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.l,
                      Space.xs,
                      Space.l,
                      Space.s,
                    ),
                    child: ExplanationCard(ctrl: ctrl),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.l),
                    child: SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<int>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 0, label: Text('Moves')),
                          ButtonSegment(value: 1, label: Text('Summary')),
                        ],
                        selected: {_tab},
                        onSelectionChanged: (v) {
                          setState(() => _tab = v.first);
                          if (_scroll.hasClients) _scroll.jumpTo(0);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.s),
                  Expanded(
                    child: ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(
                        Space.l,
                        0,
                        Space.l,
                        Space.l,
                      ),
                      children: [
                        if (_tab == 0)
                          MoveList(
                            review: r,
                            cursor: ctrl.cursor,
                            onSelect: ctrl.goTo,
                            shrinkWrap: true,
                          )
                        else ...[
                          EvalGraph(
                            review: r,
                            cursor: ctrl.cursor,
                            onSelect: (cur) {
                              ctrl.goTo(cur);
                              setState(() => _tab = 0);
                            },
                            height: 72,
                          ),
                          const SizedBox(height: Space.l),
                          SummaryPanel(
                            review: r,
                            onJump: (cur) {
                              ctrl.goTo(cur);
                              setState(() => _tab = 0);
                            },
                            onGuided: () {
                              ctrl.startGuided();
                              setState(() => _tab = 0);
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  NavBar(
                    onFirst: ctrl.first,
                    onPrev: ctrl.prev,
                    onNext: ctrl.next,
                    onLast: ctrl.last,
                    onFlip: ctrl.flip,
                    canPrev: ctrl.canPrev,
                    canNext: ctrl.canNext,
                    leading: ctrl.mode == ReviewMode.guided && ctrl.guidedActive
                        ? Row(
                            children: [
                              IconButton(
                                tooltip: 'Previous key moment',
                                onPressed: ctrl.guidedIndex > 0
                                    ? () => ctrl.guidedStep(-1)
                                    : null,
                                icon: const Icon(Icons.skip_previous_rounded),
                              ),
                              IconButton(
                                tooltip: 'Next key moment',
                                onPressed:
                                    ctrl.guidedIndex <
                                        ctrl.keyMoments.length - 1
                                    ? () => ctrl.guidedStep(1)
                                    : null,
                                icon: const Icon(Icons.skip_next_rounded),
                              ),
                            ],
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Map<Color, Duration?> _clocks() {
    final g = ctrl.game;
    Duration? find(Color color) {
      for (var i = ctrl.cursor - 1; i >= 0; i--) {
        if (g.plies[i].color == color) return g.plies[i].clock;
      }
      return null;
    }

    if (g.plies.every((p) => p.clock == null)) {
      return {Color.white: null, Color.black: null};
    }
    return {Color.white: find(Color.white), Color.black: find(Color.black)};
  }

  Future<void> _reanalyze() async {
    final s = AppScope.of(context);
    final preset = await showModalBottomSheet<AnalysisPreset>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(Space.l),
              child: Text(
                'Analyse again',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            for (final p in AnalysisPreset.values)
              ListTile(
                title: Text(AnalysisSettings.forPreset(p).label),
                subtitle: Text(_presetHint(p)),
                onTap: () => Navigator.pop(ctx, p),
              ),
            const SizedBox(height: Space.s),
          ],
        ),
      ),
    );
    if (preset == null) return;
    await s.analysis.reanalyze(
      widget.reviewId,
      AnalysisSettings.forPreset(
        preset,
        threads: s.settings.threads,
        hashMb: s.settings.hashMb,
      ),
    );
  }

  static String _presetHint(AnalysisPreset p) => switch (p) {
    AnalysisPreset.quick => 'Depth 12, about a minute',
    AnalysisPreset.standard => 'Depth 16, a few minutes',
    AnalysisPreset.deep => 'Depth 20, takes a while',
  };

  Future<void> _sharePgn() async {
    await SharePlus.instance.share(
      ShareParams(
        text: ctrl.game.toPgn(),
        subject: '${ctrl.game.white} vs ${ctrl.game.black}',
      ),
    );
  }

  Future<void> _share() async {
    final r = ctrl.review;
    final g = r.game;
    final w = r.summaryFor(Color.white);
    final b = r.summaryFor(Color.black);
    String acc(double? a) => a == null ? '–' : a.toStringAsFixed(1);
    final sb = StringBuffer()
      ..writeln('${g.white} ${g.result.pgn} ${g.black}')
      ..writeln(
        'Accuracy (rreview): ${g.white} ${acc(w.accuracy)} · ${g.black} ${acc(b.accuracy)}',
      );
    for (final l in [
      MoveLabel.blunder,
      MoveLabel.mistake,
      MoveLabel.missedWin,
      MoveLabel.inaccuracy,
    ]) {
      if (w.count(l) + b.count(l) > 0) {
        sb.writeln('${l.display}: ${w.count(l)} – ${b.count(l)}');
      }
    }
    if (r.openingName != null) sb.writeln('Opening: ${r.openingName}');
    for (final i in r.keyMoments.take(4)) {
      sb.writeln(
        '${g.plies[i].numbered} (${r.moves[i]!.label.display}): ${r.moves[i]!.explanation ?? ''}',
      );
    }
    if (r.sourceUrl != null) sb.writeln(r.sourceUrl);
    sb.writeln('Reviewed with rreview (${r.engineId}).');
    Uint8List? png;
    try {
      final boundary =
          _shareKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      final image = await boundary?.toImage(pixelRatio: 2);
      final bytes = await image?.toByteData(format: ui.ImageByteFormat.png);
      png = bytes?.buffer.asUint8List();
    } catch (_) {}
    await SharePlus.instance.share(
      ShareParams(
        text: sb.toString(),
        subject: 'Game review: ${g.white} vs ${g.black}',
        files: png == null
            ? null
            : [
                XFile.fromData(
                  png,
                  mimeType: 'image/png',
                  name: 'rreview.png',
                ),
              ],
      ),
    );
  }
}
