/// Native "share intake" layer: items handed to rreview by the OS
/// (iOS share extension / "Open in", Android share and VIEW intents).
///
/// Pure Dart + platform channels, no third-party packages. The native side
/// lives in `ios/Runner/ShareIntakePlugin.swift`, `ios/ShareExtension/` and
/// `android/app/src/main/kotlin/.../MainActivity.kt`.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';

/// What kind of payload a [SharedItem] carries.
enum SharedKind {
  /// Free text (typically a PGN, possibly with a URL embedded in it).
  text,

  /// A single http(s) URL (e.g. a Chess.com or Lichess game link).
  url,

  /// A file that has already been copied into the app's own storage;
  /// [SharedItem.value] is its absolute path.
  file,
}

/// One payload received from the OS.
class SharedItem {
  const SharedItem({
    required this.id,
    required this.kind,
    required this.value,
    required this.receivedAt,
    required this.source,
    this.fileName,
  });

  /// Creates an item originating inside the app (paste, file picker, ...).
  factory SharedItem.manual({
    required SharedKind kind,
    required String value,
    String? fileName,
    String source = sourceManual,
  }) {
    return SharedItem(
      id: newId(),
      kind: kind,
      value: value,
      fileName: fileName,
      receivedAt: DateTime.now(),
      source: source,
    );
  }

  /// Parses the JSON produced by the native side (or by [toJson]).
  /// Lenient: unknown kinds become [SharedKind.text], missing fields get
  /// sensible defaults. Throws [FormatException] only when `value` is absent.
  factory SharedItem.fromJson(Map<String, dynamic> json) {
    final value = json['value'];
    if (value is! String) {
      throw const FormatException('SharedItem.value is required');
    }
    final id = json['id'];
    final receivedRaw = json['receivedAt'];
    final fileName = json['fileName'];
    final source = json['source'];
    return SharedItem(
      id: id is String && id.isNotEmpty ? id : newId(),
      kind: _parseKind(json['kind']),
      value: value,
      fileName: fileName is String && fileName.isNotEmpty ? fileName : null,
      receivedAt: (receivedRaw is String ? DateTime.tryParse(receivedRaw) : null)
              ?.toLocal() ??
          DateTime.now(),
      source: source is String && source.isNotEmpty ? source : sourceManual,
    );
  }

  static const String sourceIosShareExtension = 'ios-share-extension';
  static const String sourceIosOpenIn = 'ios-open-in';
  static const String sourceAndroidIntent = 'android-intent';
  static const String sourceManual = 'manual';

  /// Unique id (native side uses a lowercase UUID; Dart uses time + random).
  final String id;
  final SharedKind kind;

  /// Text content, URL string, or absolute file path (already inside the
  /// app's own storage, so it stays readable across launches).
  final String value;

  /// Original file name, for [SharedKind.file] items.
  final String? fileName;
  final DateTime receivedAt;

  /// One of the `source*` constants above.
  final String source;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'kind': kind.name,
        'value': value,
        if (fileName != null) 'fileName': fileName,
        'receivedAt': receivedAt.toUtc().toIso8601String(),
        'source': source,
      };

  /// Generates an id that is unique enough for an inbox: millisecond
  /// timestamp plus 48 random bits.
  static String newId() {
    final ms = DateTime.now().toUtc().millisecondsSinceEpoch.toRadixString(16);
    final rnd = _random.nextInt(1 << 24).toRadixString(16).padLeft(6, '0') +
        _random.nextInt(1 << 24).toRadixString(16).padLeft(6, '0');
    return '$ms-$rnd';
  }

  static final Random _random = Random.secure();

  static SharedKind _parseKind(Object? raw) {
    if (raw is String) {
      for (final k in SharedKind.values) {
        if (k.name == raw) return k;
      }
    }
    return SharedKind.text;
  }

  @override
  String toString() =>
      'SharedItem($kind, id: $id, source: $source, fileName: $fileName)';
}

/// Access to items shared into the app by the operating system.
abstract class ShareIntake {
  const ShareIntake();

  /// Items that arrived while the app was not running (or that have not been
  /// consumed yet). Returns them and CLEARS them on the native side, so each
  /// item is handed out exactly once. Call this on startup and whenever the
  /// app returns to the foreground.
  Future<List<SharedItem>> takePending();

  /// New items arriving while the app runs (warm start via the `rreview://`
  /// URL scheme, "Open in", or a new Android intent). Broadcast stream.
  Stream<SharedItem> get incoming;

  /// Real implementation on iOS/Android; a no-op elsewhere (Linux, web, ...)
  /// that never touches platform channels.
  static ShareIntake forPlatform() {
    if (kIsWeb) return const NoopShareIntake();
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.android => ChannelShareIntake(),
      _ => const NoopShareIntake(),
    };
  }
}

/// Implementation for platforms without native share intake.
class NoopShareIntake extends ShareIntake {
  const NoopShareIntake();

  @override
  Future<List<SharedItem>> takePending() async => const <SharedItem>[];

  @override
  Stream<SharedItem> get incoming => const Stream<SharedItem>.empty();
}

/// MethodChannel/EventChannel implementation backed by the native code in
/// `ios/Runner` and `android/app`.
class ChannelShareIntake extends ShareIntake {
  ChannelShareIntake({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _methods = methodChannel ?? const MethodChannel(methodChannelName),
        _events = eventChannel ?? const EventChannel(eventChannelName);

  static const String methodChannelName = 'rreview/share_intake';
  static const String eventChannelName = 'rreview/share_intake/events';

  final MethodChannel _methods;
  final EventChannel _events;
  Stream<SharedItem>? _incoming;

  @override
  Future<List<SharedItem>> takePending() async {
    final List<Object?>? raw;
    try {
      raw = await _methods.invokeListMethod<Object?>('takePending');
    } on MissingPluginException {
      // Native side not wired up (e.g. tests, or an unexpected host).
      return const <SharedItem>[];
    }
    if (raw == null) return const <SharedItem>[];
    final items = raw.map(decodeItem).whereType<SharedItem>().toList()
      ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    return items;
  }

  @override
  Stream<SharedItem> get incoming => _incoming ??= _events
      .receiveBroadcastStream()
      .map(decodeItem)
      .where((item) => item != null)
      .cast<SharedItem>();

  /// Decodes one raw platform-channel value; returns null if unusable.
  static SharedItem? decodeItem(Object? raw) {
    if (raw is! Map) return null;
    final json = <String, dynamic>{
      for (final entry in raw.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
    try {
      return SharedItem.fromJson(json);
    } on FormatException {
      return null;
    }
  }
}
