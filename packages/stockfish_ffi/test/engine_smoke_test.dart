// Smoke test for the native bridge. Needs a built library and the NNUE file:
//   STOCKFISH_FFI_LIB=/path/libstockfish_ffi.so STOCKFISH_NNUE=/path/nn-1a298aa575a0.nnue flutter test
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stockfish_ffi/stockfish_ffi.dart';

void main() {
  final lib = Platform.environment['STOCKFISH_FFI_LIB'];
  final nnue = Platform.environment['STOCKFISH_NNUE'];
  test('uci handshake, options, search, stop, quit', () async {
    final engine = await StockfishEngine.start(libraryPath: lib);
    final log = <String>[];
    engine.lines.listen(log.add);
    expect(engine.version, contains('Stockfish 19'));

    engine.send('uci');
    await engine.lines.firstWhere((l) => l == 'uciok').timeout(const Duration(seconds: 10));
    expect(log.any((l) => l.startsWith('id name Stockfish 19')), isTrue);
    expect(log.any((l) => l.contains('option name UCI_ShowWDL')), isTrue);

    engine.send('setoption name Threads value 1');
    engine.send('setoption name Hash value 16');
    engine.send('setoption name UCI_ShowWDL value true');
    if (nnue != null) engine.send('setoption name EvalFile value $nnue');
    engine.send('isready');
    await engine.lines.firstWhere((l) => l == 'readyok').timeout(const Duration(seconds: 30));

    // Mate in 1 from the famous Scholar's mate setup.
    engine.send('position fen r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4');
    engine.send('go depth 12');
    final best = await engine.lines.firstWhere((l) => l.startsWith('bestmove')).timeout(const Duration(seconds: 60));
    expect(best, startsWith('bestmove h5f7'));
    final info = log.lastWhere((l) => l.startsWith('info depth') && l.contains(' pv '));
    expect(info, contains('score mate 1'));
    expect(info, contains(' wdl 1000 0 0'));

    // A real NNUE evaluation (not just mate search) from the start position.
    log.clear();
    engine.send('position startpos moves e2e4');
    engine.send('go depth 10');
    final best2 = await engine.lines.firstWhere((l) => l.startsWith('bestmove')).timeout(const Duration(seconds: 60));
    expect(best2, matches(RegExp(r'^bestmove [a-h][1-8][a-h][1-8]')));
    final info2 = log.lastWhere((l) => l.startsWith('info depth') && l.contains(' pv '));
    expect(info2, contains('score cp'));
    expect(info2, contains(' wdl '));
    if (nnue != null) {
      expect(log.any((l) => l.contains('No network') || l.contains('ERROR')), isFalse, reason: log.join('\n'));
    }

    // Infinite search can be stopped.
    engine.send('position startpos');
    engine.send('go infinite');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    engine.send('stop');
    await engine.lines.firstWhere((l) => l.startsWith('bestmove')).timeout(const Duration(seconds: 10));

    await engine.dispose();
    expect(engine.isRunning, isFalse);
    // The engine can be restarted in the same process.
    final again = await StockfishEngine.start(libraryPath: lib);
    again.send('uci');
    await again.lines.firstWhere((l) => l == 'uciok').timeout(const Duration(seconds: 10));
    await again.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
