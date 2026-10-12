/// Owns the in-process Stockfish engine: installs the NNUE network, starts
/// the engine, and exposes a ready UciClient.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:review_core/review_core.dart';
import 'package:stockfish_ffi/stockfish_ffi.dart';

const nnueFileName = 'nn-1a298aa575a0.nnue';
const nnueAssetPath = 'assets/engine/$nnueFileName';
const nnueExpectedBytes = 98511183;

enum EngineStatus { idle, installing, starting, ready, failed }

class EngineState {
  const EngineState(this.status, {this.message = '', this.progress = 0});
  final EngineStatus status;
  final String message;
  final double progress;
}

/// Adapter so the review core can talk to the FFI engine.
class _FfiUciEngine implements UciEngine {
  _FfiUciEngine(this._e);
  final StockfishEngine _e;
  @override
  Stream<String> get lines => _e.lines;
  @override
  void send(String command) => _e.send(command);
  @override
  Future<void> dispose() => _e.dispose();
}

class EngineService {
  EngineService({required this.supportDir});

  final Directory supportDir;
  final ValueNotifier<EngineState> state = ValueNotifier(const EngineState(EngineStatus.idle));
  UciClient? _client;
  String engineId = 'Stockfish 19';
  String? networkPath;

  UciClient get client {
    final c = _client;
    if (c == null) throw StateError('engine not ready');
    return c;
  }

  bool get isReady => state.value.status == EngineStatus.ready && _client != null;

  Future<void>? _starting;

  /// Installs the network and starts the engine. Concurrent calls share one attempt.
  Future<void> start({int threads = 1, int hashMb = 16}) {
    if (isReady) return Future.value();
    return _starting ??= _start(threads: threads, hashMb: hashMb).whenComplete(() => _starting = null);
  }

  Future<void> _start({required int threads, required int hashMb}) async {
    try {
      state.value = const EngineState(EngineStatus.installing, message: 'Installing engine network');
      networkPath = await _ensureNetwork();
      state.value = const EngineState(EngineStatus.starting, message: 'Starting Stockfish');
      final engine = await StockfishEngine.start();
      final client = UciClient(_FfiUciEngine(engine));
      await client.init(options: {
        'EvalFile': networkPath!,
        'Threads': '$threads',
        'Hash': '$hashMb',
        'UCI_ShowWDL': 'true',
      });
      // Confirm the network really loaded: Stockfish answers `eval` only with a net.
      engineId = client.engineName.isEmpty ? engineId : client.engineName;
      _client = client;
      state.value = EngineState(EngineStatus.ready, message: '$engineId · NNUE ${nnueFileName.substring(3, 15)}');
    } catch (e) {
      state.value = EngineState(EngineStatus.failed, message: 'Engine failed to start: $e');
    }
  }

  /// Copies the bundled network to the support directory once (98 MB).
  Future<String> _ensureNetwork() async {
    final target = File('${supportDir.path}/engine/$nnueFileName');
    if (await target.exists() && await target.length() == nnueExpectedBytes) return target.path;
    await target.parent.create(recursive: true);
    final data = await rootBundle.load(nnueAssetPath);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final tmp = File('${target.path}.part');
    final sink = tmp.openWrite();
    const chunk = 4 << 20;
    for (var off = 0; off < bytes.length; off += chunk) {
      final end = (off + chunk).clamp(0, bytes.length);
      sink.add(bytes.sublist(off, end));
      state.value = EngineState(EngineStatus.installing, message: 'Installing engine network', progress: end / bytes.length);
      await sink.flush();
    }
    await sink.close();
    await tmp.rename(target.path);
    return target.path;
  }

  Future<void> applyResources({required int threads, required int hashMb}) async {
    final c = _client;
    if (c == null) return;
    await c.setOption('Threads', '$threads');
    await c.setOption('Hash', '$hashMb');
  }

  Future<void> dispose() async {
    await _client?.dispose();
    _client = null;
    state.value = const EngineState(EngineStatus.idle);
  }
}
