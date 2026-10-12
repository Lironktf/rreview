/// Per-screen state for the interactive review: cursor, orientation, modes
/// (game, variation, retry, guided), ad-hoc evaluation of variation positions.
library;

import 'dart:async';

import 'package:chess_core/chess_core.dart';
import 'package:flutter/foundation.dart';
import 'package:review_core/review_core.dart';

import '../services/analysis_controller.dart';

enum ReviewMode { game, variation, retry, guided }

enum RetryState { waiting, correct, alsoGood, wrong, revealed }

class ReviewController extends ChangeNotifier {
  ReviewController({required this.analysis, required String reviewId, Color? orientation})
      : _reviewId = reviewId,
        orientation = orientation ?? Color.white {
    analysis.addListener(_onAnalysisChanged);
    _review = analysis.byId(reviewId)!;
  }

  final AnalysisController analysis;
  final String _reviewId;
  late GameReview _review;
  GameReview get review => _review;
  Game get game => _review.game;

  Color orientation;

  /// Plies played from the start of the game (0 = initial position).
  int cursor = 0;

  ReviewMode mode = ReviewMode.game;

  // Variation state: moves played from the game position at [cursor].
  final List<Move> variation = [];
  final List<Move> variationFuture = []; // e.g. the rest of an engine line
  Position? _variationPosition;
  PositionEval? variationEval;
  UciLine? variationLive;

  // Retry state.
  int? retryPly;
  RetryState retryState = RetryState.waiting;
  Move? retryMove;
  PositionEval? retryEval;

  // Guided state.
  int guidedIndex = 0;

  void _onAnalysisChanged() {
    final r = analysis.byId(_reviewId);
    if (r != null && !identical(r, _review)) {
      _review = r;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    analysis.removeListener(_onAnalysisChanged);
    analysis.cancelAdHoc();
    super.dispose();
  }

  // --- derived ---------------------------------------------------------------

  Position get gamePosition => game.positionAt(cursor);

  Position get position {
    if (mode == ReviewMode.variation) return _variationPosition ?? gamePosition;
    if (mode == ReviewMode.retry && retryPly != null) {
      final base = game.positionAt(retryPly!);
      final m = retryMove;
      if (m != null && retryState != RetryState.waiting && retryState != RetryState.revealed) {
        return base.tryPlay(m) ?? base;
      }
      if (retryState == RetryState.revealed) {
        final best = Move.parseUci(_review.moves[retryPly!]?.before.bestMove ?? '');
        if (best != null) return base.tryPlay(best) ?? base;
      }
      return base;
    }
    return gamePosition;
  }

  Move? get lastMove {
    if (mode == ReviewMode.variation) return variation.isNotEmpty ? variation.last : (cursor > 0 ? game.plies[cursor - 1].move : null);
    if (mode == ReviewMode.retry && retryPly != null) {
      if (retryState == RetryState.revealed) return Move.parseUci(_review.moves[retryPly!]?.before.bestMove ?? '');
      if (retryState != RetryState.waiting) return retryMove;
      return retryPly! > 0 ? game.plies[retryPly! - 1].move : null;
    }
    return cursor > 0 ? game.plies[cursor - 1].move : null;
  }

  /// The review entry for the move that led to the current cursor.
  MoveReview? get currentMove => cursor > 0 && cursor - 1 < _review.moves.length ? _review.moves[cursor - 1] : null;

  /// Evaluation shown on the bar.
  PositionEval? get displayedEval {
    if (mode == ReviewMode.variation) return variationEval;
    if (mode == ReviewMode.retry) return retryEval ?? (retryPly != null ? _review.moves[retryPly!]?.before : null);
    if (cursor == 0) return _review.moves.isNotEmpty ? _review.moves[0]?.before : null;
    return currentMove?.after;
  }

  bool get canPrev => mode == ReviewMode.variation ? true : cursor > 0;
  bool get canNext => mode == ReviewMode.variation ? variationFuture.isNotEmpty : cursor < game.plies.length;

  List<int> get keyMoments => _review.keyMoments;

  // --- navigation ------------------------------------------------------------

  void goTo(int c) {
    if (mode == ReviewMode.variation || mode == ReviewMode.retry) exitToGame();
    cursor = c.clamp(0, game.plies.length);
    notifyListeners();
  }

  void next() {
    if (mode == ReviewMode.variation) {
      if (variationFuture.isNotEmpty) playVariationMove(variationFuture.removeAt(0), keepFuture: true);
      return;
    }
    if (mode == ReviewMode.retry) {
      exitToGame();
      return;
    }
    if (cursor < game.plies.length) {
      cursor++;
      notifyListeners();
    }
  }

  void prev() {
    if (mode == ReviewMode.variation) {
      if (variation.isEmpty) {
        exitToGame();
        return;
      }
      final undone = variation.removeLast();
      variationFuture.insert(0, undone);
      _recomputeVariation();
      return;
    }
    if (mode == ReviewMode.retry) {
      exitToGame();
      return;
    }
    if (cursor > 0) {
      cursor--;
      notifyListeners();
    }
  }

  void first() => goTo(0);
  void last() => goTo(game.plies.length);

  void flip() {
    orientation = orientation.opposite;
    notifyListeners();
  }

  // --- variations ------------------------------------------------------------

  /// Called when the user moves a piece on the board.
  void onBoardMove(Move m) {
    switch (mode) {
      case ReviewMode.retry:
        _answerRetry(m);
      case ReviewMode.game:
      case ReviewMode.guided:
        mode = ReviewMode.variation;
        variation.clear();
        variationFuture.clear();
        playVariationMove(m);
      case ReviewMode.variation:
        variationFuture.clear();
        playVariationMove(m);
    }
  }

  void playVariationMove(Move m, {bool keepFuture = false}) {
    if (!keepFuture) variationFuture.clear();
    variation.add(m);
    _recomputeVariation();
  }

  /// Enter variation mode showing the engine's best line from the position
  /// before the current move.
  void showBestLine() {
    final mr = currentMove;
    if (mr == null || cursor == 0) return;
    cursor = cursor - 1;
    mode = ReviewMode.variation;
    variation.clear();
    variationFuture
      ..clear()
      ..addAll(mr.before.pv.map(Move.parseUci).whereType<Move>());
    if (variationFuture.isNotEmpty) {
      playVariationMove(variationFuture.removeAt(0), keepFuture: true);
    } else {
      _recomputeVariation();
    }
  }

  void _recomputeVariation() {
    var p = gamePosition;
    for (final m in variation) {
      final n = p.tryPlay(m);
      if (n == null) break;
      p = n;
    }
    _variationPosition = p;
    variationEval = null;
    variationLive = null;
    notifyListeners();
    _evaluateVariation(p);
  }

  Future<void> _evaluateVariation(Position p) async {
    final e = await analysis.evaluateAdHoc(p, depth: 14, onInfo: (l) {
      if (_variationPosition?.fen == p.fen) {
        variationLive = l;
        notifyListeners();
      }
    });
    if (e != null && _variationPosition?.fen == p.fen) {
      variationEval = e;
      variationLive = null;
      notifyListeners();
    }
  }

  void exitToGame() {
    analysis.cancelAdHoc();
    if (mode == ReviewMode.retry && retryPly != null) {
      cursor = retryPly! + 1;
    }
    mode = guidedIndex > 0 || _guidedActive ? ReviewMode.guided : ReviewMode.game;
    if (!_guidedActive) mode = ReviewMode.game;
    variation.clear();
    variationFuture.clear();
    _variationPosition = null;
    variationEval = null;
    variationLive = null;
    retryPly = null;
    retryMove = null;
    retryEval = null;
    retryState = RetryState.waiting;
    notifyListeners();
  }

  // --- retry -----------------------------------------------------------------

  /// Try to find a better move than the one played at [ply].
  void startRetry(int ply) {
    analysis.cancelAdHoc();
    retryPly = ply;
    retryMove = null;
    retryEval = null;
    retryState = RetryState.waiting;
    variation.clear();
    variationFuture.clear();
    mode = ReviewMode.retry;
    orientation = game.plies[ply].color;
    notifyListeners();
  }

  Future<void> _answerRetry(Move m) async {
    final ply = retryPly;
    if (ply == null) return;
    final mr = _review.moves[ply];
    final base = game.positionAt(ply);
    retryMove = m;
    final bestUci = mr?.before.bestMove;
    if (bestUci != null && base.uci(m) == bestUci) {
      retryState = RetryState.correct;
      retryEval = null;
      notifyListeners();
      return;
    }
    retryState = RetryState.wrong;
    notifyListeners();
    final after = base.tryPlay(m);
    if (after == null || mr == null) return;
    final e = await analysis.evaluateAdHoc(after, depth: 12);
    if (e == null || retryMove != m) return;
    retryEval = e;
    final mover = game.plies[ply].color;
    final eBest = mover == Color.white ? mr.before.wdl.expectedScore : 1 - mr.before.wdl.expectedScore;
    final ePlayed = mover == Color.white ? e.wdl.expectedScore : 1 - e.wdl.expectedScore;
    if (eBest - ePlayed <= 0.02) retryState = RetryState.alsoGood;
    notifyListeners();
  }

  void retryAgain() {
    retryMove = null;
    retryEval = null;
    retryState = RetryState.waiting;
    notifyListeners();
  }

  void revealRetry() {
    retryState = RetryState.revealed;
    retryMove = null;
    retryEval = null;
    notifyListeners();
  }

  // --- guided ----------------------------------------------------------------

  bool _guidedActive = false;
  bool get guidedActive => _guidedActive;

  void startGuided() {
    final k = keyMoments;
    if (k.isEmpty) return;
    _guidedActive = true;
    guidedIndex = 0;
    mode = ReviewMode.guided;
    cursor = k[0] + 1;
    orientation = game.plies[k[0]].color;
    notifyListeners();
  }

  void guidedStep(int delta) {
    final k = keyMoments;
    if (k.isEmpty) return;
    guidedIndex = (guidedIndex + delta).clamp(0, k.length - 1);
    mode = ReviewMode.guided;
    cursor = k[guidedIndex] + 1;
    notifyListeners();
  }

  void endGuided() {
    _guidedActive = false;
    mode = ReviewMode.game;
    notifyListeners();
  }
}
