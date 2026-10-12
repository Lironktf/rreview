/// Stockfish 19 in-process, driven over UCI text through Dart FFI.
///
/// The engine runs on a native thread; a helper isolate pumps its output lines
/// into [StockfishEngine.lines]. Nothing here blocks the calling isolate.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

typedef _StartC = Int32 Function();
typedef _StartDart = int Function();
typedef _SendC = Void Function(Pointer<Utf8>);
typedef _SendDart = void Function(Pointer<Utf8>);
typedef _ReadC = Pointer<Utf8> Function(Int32);
typedef _ReadDart = Pointer<Utf8> Function(int);
typedef _FreeC = Void Function(Pointer<Utf8>);
typedef _FreeDart = void Function(Pointer<Utf8>);
typedef _IntC = Int32 Function();
typedef _IntDart = int Function();
typedef _VoidC = Void Function();
typedef _VoidDart = void Function();
typedef _VersionC = Pointer<Utf8> Function();
typedef _VersionDart = Pointer<Utf8> Function();

class _Bindings {
  _Bindings(DynamicLibrary lib)
      : start = lib.lookupFunction<_StartC, _StartDart>('sf_start'),
        send = lib.lookupFunction<_SendC, _SendDart>('sf_send'),
        readLine = lib.lookupFunction<_ReadC, _ReadDart>('sf_read_line'),
        free = lib.lookupFunction<_FreeC, _FreeDart>('sf_free'),
        isRunning = lib.lookupFunction<_IntC, _IntDart>('sf_is_running'),
        join = lib.lookupFunction<_VoidC, _VoidDart>('sf_join'),
        version = lib.lookupFunction<_VersionC, _VersionDart>('sf_version');

  final _StartDart start;
  final _SendDart send;
  final _ReadDart readLine;
  final _FreeDart free;
  final _IntDart isRunning;
  final _VoidDart join;
  final _VersionDart version;
}

/// Where the native library lives on each platform.
///
/// [override] lets tests point at a freshly built `libstockfish_ffi.so`.
DynamicLibrary openStockfishLibrary({String? override}) {
  if (override != null) return DynamicLibrary.open(override);
  if (Platform.isIOS || Platform.isMacOS) return DynamicLibrary.process();
  if (Platform.isAndroid || Platform.isLinux) return DynamicLibrary.open('libstockfish_ffi.so');
  if (Platform.isWindows) return DynamicLibrary.open('stockfish_ffi.dll');
  throw UnsupportedError('Unsupported platform ${Platform.operatingSystem}');
}

/// A running Stockfish engine (native thread + reader isolate).
class StockfishEngine {
  StockfishEngine._(this._bindings);

  final _Bindings _bindings;
  final _controller = StreamController<String>.broadcast();
  Isolate? _reader;
  ReceivePort? _port;
  bool _disposed = false;

  /// Lines printed by the engine, one at a time, without newlines.
  Stream<String> get lines => _controller.stream;

  /// Stockfish version string, e.g. "19".
  String get version => _bindings.version().toDartString();

  bool get isRunning => _bindings.isRunning() != 0;

  /// Starts the engine. Only one instance may exist per process.
  static Future<StockfishEngine> start({String? libraryPath}) async {
    final lib = openStockfishLibrary(override: libraryPath);
    final bindings = _Bindings(lib);
    final engine = StockfishEngine._(bindings);
    if (bindings.start() == 0) {
      throw StateError('Stockfish is already running in this process');
    }
    final ready = ReceivePort();
    final port = ReceivePort();
    engine._port = port;
    engine._reader = await Isolate.spawn(
      _readerMain,
      _ReaderArgs(port.sendPort, ready.sendPort, libraryPath),
      debugName: 'stockfish-reader',
    );
    await ready.first;
    ready.close();
    port.listen((msg) {
      if (msg is String) {
        if (!engine._controller.isClosed) engine._controller.add(msg);
        if (msg == 'quitok') port.close();
      }
    });
    return engine;
  }

  /// Sends one UCI command.
  void send(String command) {
    if (_disposed) return;
    final p = command.toNativeUtf8();
    try {
      _bindings.send(p);
    } finally {
      malloc.free(p);
    }
  }

  /// Sends `quit`, waits for the engine thread to exit and releases resources.
  Future<void> dispose() async {
    if (_disposed) return;
    final done = lines.firstWhere((l) => l == 'quitok', orElse: () => '');
    send('quit');
    _disposed = true;
    await done.timeout(const Duration(seconds: 5), onTimeout: () => '');
    _bindings.join();
    _reader?.kill(priority: Isolate.immediate);
    _reader = null;
    _port?.close();
    await _controller.close();
  }

  static void _readerMain(_ReaderArgs args) {
    final bindings = _Bindings(openStockfishLibrary(override: args.libraryPath));
    args.ready.send(true);
    while (true) {
      final p = bindings.readLine(250);
      if (p == nullptr) {
        if (bindings.isRunning() == 0) {
          final rest = bindings.readLine(0);
          if (rest == nullptr) break;
          final s = rest.toDartString();
          bindings.free(rest);
          args.out.send(s);
          if (s == 'quitok') break;
        }
        continue;
      }
      final s = p.toDartString();
      bindings.free(p);
      args.out.send(s);
      if (s == 'quitok') break;
    }
  }
}

class _ReaderArgs {
  _ReaderArgs(this.out, this.ready, this.libraryPath);
  final SendPort out;
  final SendPort ready;
  final String? libraryPath;
}
