/// Cache of position evaluations keyed by (FEN, engine, depth).
library;

import 'models.dart';

String evalCacheKey(String fen, String engineId, int depth) {
  // Drop the move counters: they do not affect the evaluation.
  final parts = fen.split(' ');
  final core = parts.length >= 4 ? parts.sublist(0, 4).join(' ') : fen;
  return '$engineId|$depth|$core';
}

abstract class EvalCache {
  Future<PositionEval?> get(String key);
  Future<void> put(String key, PositionEval eval);
}

class MemoryEvalCache implements EvalCache {
  final Map<String, PositionEval> _map = {};

  @override
  Future<PositionEval?> get(String key) async => _map[key];

  @override
  Future<void> put(String key, PositionEval eval) async => _map[key] = eval;

  int get length => _map.length;
}
