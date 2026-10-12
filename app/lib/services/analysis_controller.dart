/// Runs analyses one at a time, persists progress, and serves ad-hoc position
/// evaluations for variation exploration.
library;

import 'dart:async';
import 'dart:collection';

import 'package:chess_core/chess_core.dart';
import 'package:flutter/foundation.dart';
import 'package:review_core/review_core.dart';

import 'engine_service.dart';
import 'review_store.dart';

class AnalysisController extends ChangeNotifier {
  AnalysisController({required this.engine, required this.store, required this.cache, this.book});

  final EngineService engine;
  final ReviewStore store;
  final FileEvalCache cache;
  OpeningBook? book;

  /// Set at startup so the first analysis waits for the opening book.
  Future<OpeningBook>? bookLoading;

  final Map<String, GameReview> _reviews = {};
  final Queue<String> _queue = Queue();
  String? _runningId;
  CancelToken? _runningToken;
  Timer? _flushTimer;

  /// Reviews by id, newest first.
  List<GameReview> get reviews {
    final l = _reviews.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return l;
  }

  GameReview? byId(String id) => _reviews[id];
  String? get runningId => _runningId;
  bool isQueued(String id) => _queue.contains(id) || _runningId == id;

  Future<void> loadFromDisk() async {
    for (final r in await store.loadAll()) {
      _reviews[r.id] = r;
    }
    notifyListeners();
    // Resume anything unfinished, oldest first.
    final unfinished = reviews.where((r) => r.status == ReviewStatus.paused || r.status == ReviewStatus.pending || r.status == ReviewStatus.running).toList()
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    for (final r in unfinished) {
      enqueue(r.id);
    }
  }

  /// Adds a new review (saves it) and queues it for analysis.
  Future<void> add(GameReview r, {bool analyze = true}) async {
    _reviews[r.id] = r;
    await store.save(r);
    notifyListeners();
    if (analyze) enqueue(r.id);
  }

  void enqueue(String id) {
    if (!_reviews.containsKey(id) || isQueued(id)) return;
    _queue.add(id);
    final r = _reviews[id]!;
    if (r.status == ReviewStatus.paused || r.status == ReviewStatus.failed) {
      _reviews[id] = r.copyWith(status: ReviewStatus.pending, clearError: true);
    }
    notifyListeners();
    _pump();
  }

  /// Stops analysing [id] (keeps partial results).
  void cancel(String id) {
    if (_runningId == id) {
      _runningToken?.cancel();
      engine.client.stop();
    } else if (_queue.remove(id)) {
      final r = _reviews[id];
      if (r != null) _reviews[id] = r.copyWith(status: ReviewStatus.paused);
      notifyListeners();
    }
  }

  Future<void> reanalyze(String id, AnalysisSettings settings) async {
    final r = _reviews[id];
    if (r == null) return;
    cancel(id);
    final fresh = GameReview(
      id: r.id,
      game: r.game,
      settings: settings,
      engineId: engine.engineId,
      moves: List.filled(r.game.plies.length, null),
      status: ReviewStatus.pending,
      createdAt: r.createdAt,
      updatedAt: DateTime.now(),
      sourceUrl: r.sourceUrl,
    );
    _reviews[id] = fresh;
    await store.save(fresh);
    notifyListeners();
    enqueue(id);
  }

  Future<void> delete(String id) async {
    cancel(id);
    _reviews.remove(id);
    await store.delete(id);
    notifyListeners();
  }

  /// Re-insert a deleted review (undo).
  Future<void> restore(GameReview r) async {
    _reviews[r.id] = r;
    await store.save(r);
    notifyListeners();
    if (!r.isComplete) enqueue(r.id);
  }

  bool _pumping = false;
  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (_queue.isNotEmpty) {
        if (!engine.isReady) {
          await engine.start();
          if (!engine.isReady) {
            // Engine unavailable: mark queued reviews failed so the UI can say so.
            for (final id in _queue) {
              final r = _reviews[id];
              if (r != null) _reviews[id] = r.copyWith(status: ReviewStatus.failed, error: engine.state.value.message);
            }
            _queue.clear();
            notifyListeners();
            return;
          }
        }
        if (book == null && bookLoading != null) {
          try {
            book = await bookLoading!.timeout(const Duration(seconds: 20));
          } catch (_) {
            bookLoading = null; // analyse without book names rather than wait forever
          }
        }
        final id = _queue.removeFirst();
        final review = _reviews[id];
        if (review == null) continue;
        _runningId = id;
        _runningToken = CancelToken();
        notifyListeners();
        final analyzer = Analyzer(client: engine.client, cache: cache, book: book);
        var lastSave = DateTime.now();
        await for (final update in analyzer.analyze(review, cancel: _runningToken)) {
          if (!_reviews.containsKey(id)) break; // deleted meanwhile
          _reviews[id] = update;
          notifyListeners();
          final now = DateTime.now();
          if (update.status != ReviewStatus.running || now.difference(lastSave).inSeconds >= 3) {
            await store.save(update);
            lastSave = now;
          }
        }
        _runningId = null;
        _runningToken = null;
        _scheduleFlush();
        notifyListeners();
      }
    } finally {
      _pumping = false;
    }
  }

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(seconds: 2), () => cache.flush());
  }

  // --- Ad-hoc evaluation for variations ------------------------------------

  int _adhocSerial = 0;

  /// Evaluates an arbitrary position (for variation exploration). Returns null
  /// if a newer request superseded this one or the engine is unavailable.
  Future<PositionEval?> evaluateAdHoc(Position pos, {int depth = 14, void Function(UciLine)? onInfo}) async {
    final serial = ++_adhocSerial;
    if (!engine.isReady) return null;
    final key = evalCacheKey(pos.fen, engine.engineId, depth);
    final cached = await cache.get(key);
    if (cached != null) return cached;
    if (pos.legalMoves.isEmpty) {
      return PositionEval(
        fen: pos.fen,
        depth: depth,
        score: pos.isCheckmate ? Score.checkmated(pos.turn) : const Score.cp(0),
        wdl: pos.isCheckmate ? (pos.turn == Color.white ? const Wdl(0, 0, 1) : const Wdl(1, 0, 0)) : const Wdl(0, 1, 0),
        bestMove: '(none)',
        pv: const [],
        nodes: 0,
      );
    }
    // If a background analysis is running, this waits for its current search.
    final result = await engine.client.search(pos.fen, SearchLimits(depth: depth), onInfo: (l) {
      if (serial == _adhocSerial) onInfo?.call(l);
    });
    if (serial != _adhocSerial) return null;
    final line = result.principal;
    if (line == null) return null;
    final score = Score.fromUci(cp: line.cp, mate: line.mate, sideToMove: pos.turn);
    final eval = PositionEval(
      fen: pos.fen,
      depth: line.depth,
      score: score,
      wdl: line.wdl != null ? Wdl.fromPerMille(line.wdl!, sideToMove: pos.turn) : WinModel.wdlOf(score, WinModel.materialOf(pos)),
      bestMove: result.bestMove,
      pv: line.pv,
      nodes: line.nodes,
    );
    await cache.put(key, eval);
    _scheduleFlush();
    return eval;
  }

  void cancelAdHoc() {
    _adhocSerial++;
    if (_runningId == null && engine.isReady) engine.client.stop();
  }
}
