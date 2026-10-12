/// Local persistence: one JSON file per review plus a file-backed eval cache.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:review_core/review_core.dart';

class ReviewStore {
  ReviewStore(this.root);

  final Directory root;
  Directory get _reviews => Directory('${root.path}/reviews');

  Future<List<GameReview>> loadAll() async {
    if (!await _reviews.exists()) return [];
    final out = <GameReview>[];
    await for (final f in _reviews.list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      try {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        out.add(GameReview.fromJson(j));
      } catch (e) {
        debugPrint('Skipping unreadable review ${f.path}: $e');
      }
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  Future<void> save(GameReview r) async {
    await _reviews.create(recursive: true);
    final f = File('${_reviews.path}/${r.id}.json');
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(r.toJson()));
    await tmp.rename(f.path);
  }

  Future<void> delete(String id) async {
    final f = File('${_reviews.path}/$id.json');
    if (await f.exists()) await f.delete();
  }
}

/// Eval cache kept in memory and flushed to disk, bounded in size.
class FileEvalCache implements EvalCache {
  FileEvalCache(this.file, {this.maxEntries = 40000});

  final File file;
  final int maxEntries;
  final Map<String, PositionEval> _map = {};
  bool _dirty = false;

  Future<void> load() async {
    try {
      if (await file.exists()) {
        final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        for (final e in j.entries) {
          _map[e.key] = PositionEval.fromJson((e.value as Map).cast<String, dynamic>());
        }
      }
    } catch (_) {
      _map.clear();
    }
  }

  @override
  Future<PositionEval?> get(String key) async => _map[key];

  @override
  Future<void> put(String key, PositionEval eval) async {
    _map[key] = eval;
    _dirty = true;
    if (_map.length > maxEntries) {
      final remove = _map.keys.take(_map.length - maxEntries).toList();
      remove.forEach(_map.remove);
    }
  }

  int get length => _map.length;

  Future<void> flush() async {
    if (!_dirty) return;
    _dirty = false;
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode({for (final e in _map.entries) e.key: e.value.toJson()}));
    await tmp.rename(file.path);
  }
}
