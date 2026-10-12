/// A UCI engine running as an external process. Used for tests and tooling on
/// desktop; the app uses the in-process FFI engine.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'uci_engine.dart';

class ProcessUciEngine implements UciEngine {
  ProcessUciEngine._(this._process)
      : lines = _process.stdout.transform(utf8.decoder).transform(const LineSplitter()).asBroadcastStream();

  static Future<ProcessUciEngine> start(String path, {List<String> args = const []}) async {
    final p = await Process.start(path, args);
    return ProcessUciEngine._(p);
  }

  final Process _process;

  @override
  final Stream<String> lines;

  @override
  void send(String command) => _process.stdin.writeln(command);

  @override
  Future<void> dispose() async {
    send('quit');
    await _process.exitCode.timeout(const Duration(seconds: 5), onTimeout: () {
      _process.kill();
      return -1;
    });
  }
}
