import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreview/platform/share_intake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedItem', () {
    test('toJson/fromJson round trip', () {
      final item = SharedItem(
        id: 'abc',
        kind: SharedKind.file,
        value: '/tmp/x.pgn',
        fileName: 'x.pgn',
        receivedAt: DateTime.utc(2026, 10, 11, 12, 30, 15, 250),
        source: SharedItem.sourceIosShareExtension,
      );
      final back = SharedItem.fromJson(item.toJson());
      expect(back.id, 'abc');
      expect(back.kind, SharedKind.file);
      expect(back.value, '/tmp/x.pgn');
      expect(back.fileName, 'x.pgn');
      expect(back.receivedAt.toUtc(), item.receivedAt);
      expect(back.source, SharedItem.sourceIosShareExtension);
    });

    test('parses the native wire format leniently', () {
      final item = SharedItem.fromJson(<String, dynamic>{
        'id': '2f1c0b7e-9c6c-4a51-8b53-0d6f5b1b2c3d',
        'kind': 'url',
        'value': 'https://www.chess.com/game/live/97872578329',
        'receivedAt': '2026-10-11T12:30:15.250Z',
        'source': 'android-intent',
      });
      expect(item.kind, SharedKind.url);
      expect(item.fileName, isNull);
      expect(item.receivedAt.toUtc(), DateTime.utc(2026, 10, 11, 12, 30, 15, 250));

      final odd = SharedItem.fromJson(<String, dynamic>{
        'kind': 'something-new',
        'value': '1. e4 e5',
        'receivedAt': 'not a date',
      });
      expect(odd.kind, SharedKind.text);
      expect(odd.id, isNotEmpty);
      expect(odd.source, SharedItem.sourceManual);

      expect(() => SharedItem.fromJson(<String, dynamic>{'kind': 'text'}),
          throwsFormatException);
    });

    test('newId is unique', () {
      final ids = {for (var i = 0; i < 1000; i++) SharedItem.newId()};
      expect(ids.length, 1000);
    });
  });

  group('ShareIntake', () {
    test('no-op implementation returns nothing', () async {
      const intake = NoopShareIntake();
      expect(await intake.takePending(), isEmpty);
      expect(await intake.incoming.toList(), isEmpty);
    });

    test('channel implementation decodes takePending', () async {
      const channel = MethodChannel('openreview/share_intake');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'takePending');
        return <Object?>[
          <Object?, Object?>{
            'id': 'b',
            'kind': 'text',
            'value': '[Event "x"] 1. e4',
            'receivedAt': '2026-10-11T12:30:16.000Z',
            'source': 'ios-share-extension',
          },
          <Object?, Object?>{
            'id': 'a',
            'kind': 'url',
            'value': 'https://lichess.org/abcdefgh',
            'receivedAt': '2026-10-11T12:30:15.000Z',
            'source': 'ios-share-extension',
          },
          'garbage',
        ];
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final items = await ChannelShareIntake().takePending();
      expect(items.map((e) => e.id), ['a', 'b']); // sorted by receivedAt
      expect(items.first.kind, SharedKind.url);
    });

    test('channel implementation tolerates a missing native side', () async {
      const channel = MethodChannel('openreview/share_intake');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, null);
      expect(await ChannelShareIntake().takePending(), isEmpty);
    });

    test('channel implementation streams incoming items', () async {
      const events = EventChannel('openreview/share_intake/events');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(
          onListen: (arguments, sink) {
            sink.success(<Object?, Object?>{
              'id': 'f1',
              'kind': 'file',
              'value': '/data/imports/f1-game.pgn',
              'fileName': 'game.pgn',
              'receivedAt': '2026-10-11T12:31:00.000Z',
              'source': 'android-intent',
            });
            sink.success('not a map');
            sink.endOfStream();
          },
        ),
      );
      addTearDown(() => messenger.setMockStreamHandler(events, null));

      final received = await ChannelShareIntake().incoming.toList();
      expect(received, hasLength(1));
      expect(received.single.kind, SharedKind.file);
      expect(received.single.fileName, 'game.pgn');
      expect(received.single.source, SharedItem.sourceAndroidIntent);
    });
  });
}
