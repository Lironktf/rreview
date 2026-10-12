import 'dart:async';

import 'package:review_core/review_core.dart';

/// A scripted UCI engine: answers `go` for a FEN with pre-recorded lines.
class FakeEngine implements UciEngine {
  FakeEngine(this.script);

  /// FEN (first 4 fields) -> list of output lines (info..., bestmove ...).
  final Map<String, List<String>> script;
  final _out = StreamController<String>.broadcast();
  String? _fen;
  final sent = <String>[];

  @override
  Stream<String> get lines => _out.stream;

  static String key(String fen) => fen.split(' ').take(4).join(' ');

  @override
  void send(String command) {
    sent.add(command);
    if (command == 'uci') {
      _out.add('id name FakeFish 1');
      _out.add('option name UCI_ShowWDL type check default false');
      _out.add('option name UCI_Chess960 type check default false');
      _out.add('uciok');
    } else if (command == 'isready') {
      _out.add('readyok');
    } else if (command.startsWith('position fen ')) {
      _fen = key(command.substring(13));
    } else if (command.startsWith('go')) {
      final lines = script[_fen];
      if (lines == null) throw StateError('no script for $_fen (${command})');
      // searchmoves: emulate by returning a line whose pv starts with the move if present.
      final sm = RegExp(r'searchmoves (\S+)').firstMatch(command)?.group(1);
      if (sm != null) {
        final alt = script['$_fen|$sm'];
        if (alt != null) {
          alt.forEach(_out.add);
          return;
        }
      }
      lines.forEach(_out.add);
    } else if (command == 'quit') {
      _out.add('quitok');
    }
  }

  @override
  Future<void> dispose() async => _out.close();
}
