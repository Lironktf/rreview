import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreview/screens/library_screen.dart';
import 'package:openreview/screens/review_screen.dart';
import 'package:openreview/services/app_scope.dart';
import 'package:openreview/theme/theme.dart';
import 'package:openreview/widgets/eval_graph.dart';

import 'fixtures.dart';

Future<void> settle(WidgetTester tester) =>
    tester.pumpAndSettle(const Duration(milliseconds: 50), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));

Widget app(AppServices s, Widget home, {Brightness brightness = Brightness.light}) => AppScope(
      services: s,
      child: MaterialApp(
        theme: buildTheme(brightness, fontFamily: 'Roboto'),
        home: home,
        debugShowCheckedModeBanner: false,
      ),
    );

/// Real fonts so goldens look like the shipped app (tests default to a block font).
Future<void> loadRealFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/dev/flutter';
  final fontsDir = Directory('$flutterRoot/bin/cache/artifacts/material_fonts');
  if (!fontsDir.existsSync()) return;
  final roboto = FontLoader('Roboto');
  for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']) {
    final file = File('${fontsDir.path}/$f');
    if (file.existsSync()) roboto.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons');
  final iconFile = File('${fontsDir.path}/MaterialIcons-Regular.otf');
  if (iconFile.existsSync()) {
    icons.addFont(Future.value(ByteData.sublistView(iconFile.readAsBytesSync())));
    await icons.load();
  }
}

void main() {
  late Directory tmp;
  setUpAll(loadRealFonts);
  setUp(() async => tmp = await Directory.systemTemp.createTemp('openreview_test'));
  tearDown(() => tmp.delete(recursive: true));

  testWidgets('library shows the imported game and opens the review', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final s = (await tester.runAsync(() => testServices(tmp, reviews: [sampleReview()])))!;
    await tester.pumpWidget(app(s, const LibraryScreen()));
    await settle(tester);
    expect(find.text('liron – opponent'), findsOneWidget);
    expect(find.text('0–1'), findsOneWidget);
    expect(find.text('Blunder'), findsOneWidget);
    await tester.tap(find.text('liron – opponent'));
    await settle(tester);
    expect(find.byType(ReviewScreen), findsOneWidget);
    expect(find.text('Start position'), findsOneWidget);
  });

  testWidgets('review navigation, labels, try again and variations', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final s = (await tester.runAsync(() => testServices(tmp, reviews: [sampleReview()])))!;
    await tester.pumpWidget(app(s, const ReviewScreen(reviewId: 'sample')));
    await settle(tester);
    // Step forward to the blunder (8. Nxg5 is ply 15).
    for (var i = 0; i < 15; i++) {
      await tester.tap(find.byTooltip('Next move'));
      await settle(tester);
    }
    expect(find.text('8. Nxg5'), findsOneWidget);
    expect(find.textContaining('Bg3 was stronger'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Best line'), findsOneWidget);
    // Try again mode.
    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(find.textContaining('Find a better move'), findsOneWidget);
    await tester.tap(find.text('Show solution'));
    await settle(tester);
    expect(find.textContaining('Bg3 was best'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await settle(tester);
    expect(find.text('8. Nxg5'), findsOneWidget);
    // Next / previous keep working.
    await tester.tap(find.byTooltip('Next move'));
    await settle(tester);
    expect(find.text('8... hxg5'), findsOneWidget);
    await tester.tap(find.byTooltip('First move'));
    await settle(tester);
    expect(find.text('Start position'), findsOneWidget);
    // Tapping a move in the list jumps there.
    await tester.dragUntilVisible(find.text('Nxg5'), find.byType(Scrollable).first, const Offset(0, -80));
    await settle(tester);
    await tester.tap(find.text('Nxg5').first);
    await settle(tester);
    expect(find.text('8. Nxg5'), findsOneWidget);
    // Summary tab.
    await tester.tap(find.text('Summary'));
    await settle(tester);
    expect(find.text('Accuracy'), findsOneWidget);
    // The summary starts at the top (graph first) even after the move list had scrolled.
    final screenH = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(tester.getTopLeft(find.byType(EvalGraph)).dy, lessThan(screenH - 100));
    expect(tester.getTopLeft(find.text('Accuracy')).dy, lessThan(screenH));
    expect(find.text('Key moments'), findsOneWidget);
    expect(find.textContaining('Italian Game'), findsWidgets);
  });

  testWidgets('golden: review screen light and dark', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final s = (await tester.runAsync(() => testServices(tmp, reviews: [sampleReview()])))!;
    for (final b in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(app(s, const ReviewScreen(reviewId: 'sample'), brightness: b));
      await settle(tester);
      for (var i = 0; i < 15; i++) {
        await tester.tap(find.byTooltip('Next move'));
        await settle(tester);
      }
      await expectLater(find.byType(ReviewScreen), matchesGoldenFile('goldens/review_${b.name}.png'));
      await tester.tap(find.text('Summary'));
      await settle(tester);
      await expectLater(find.byType(ReviewScreen), matchesGoldenFile('goldens/summary_${b.name}.png'));
    }
    await tester.pumpWidget(app(s, const LibraryScreen()));
    await settle(tester);
    await expectLater(find.byType(LibraryScreen), matchesGoldenFile('goldens/library_light.png'));
  }, tags: ['golden']);
}
