import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'platform/share_intake.dart';
import 'screens/import_sheet.dart';
import 'screens/library_screen.dart' show LibraryScreen, openReview;
import 'services/analysis_controller.dart';
import 'services/app_scope.dart';
import 'services/book_service.dart';
import 'services/engine_service.dart';
import 'services/import_service.dart';
import 'services/review_store.dart';
import 'services/settings_service.dart';
import 'theme/theme.dart';
import 'widgets/board/pieces.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final support = await getApplicationSupportDirectory();
  // Phones: the app-private documents directory. Desktop: keep everything under the support directory.
  final docs = (Platform.isIOS || Platform.isAndroid) ? await getApplicationDocumentsDirectory() : support;
  final settings = await AppSettings.load(
    File('${support.path}/settings.json'),
  );
  final engine = EngineService(supportDir: support);
  final store = ReviewStore(Directory('${docs.path}/openreview'));
  final cache = FileEvalCache(File('${support.path}/evals.json'));
  await cache.load();
  final analysis = AnalysisController(
    engine: engine,
    store: store,
    cache: cache,
  );
  final importer = ImportService(controller: analysis, settings: settings);
  final services = AppServices(
    settings: settings,
    engine: engine,
    analysis: analysis,
    importer: importer,
  );
  runApp(
    OpenReviewApp(
      services: services,
      intake: ShareIntake.forPlatform(),
      launchFiles: _launchFiles(args),
    ),
  );
}

/// Desktop: `openreview game.pgn` or OPENREVIEW_IMPORT=/path/game.pgn imports on start.
List<String> _launchFiles(List<String> args) {
  final out = <String>[...args.where((a) => a.toLowerCase().endsWith('.pgn'))];
  final env = Platform.environment['OPENREVIEW_IMPORT'];
  if (env != null && env.isNotEmpty) out.add(env);
  return out;
}

final navigatorKey = GlobalKey<NavigatorState>();

class OpenReviewApp extends StatefulWidget {
  const OpenReviewApp({
    super.key,
    required this.services,
    required this.intake,
    this.launchFiles = const [],
  });
  final AppServices services;
  final ShareIntake intake;
  final List<String> launchFiles;

  @override
  State<OpenReviewApp> createState() => _OpenReviewAppState();
}

class _OpenReviewAppState extends State<OpenReviewApp> {
  StreamSubscription<SharedItem>? _sub;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _boot();
    _lifecycle = AppLifecycleListener(
      onResume: _drainShares,
      onHide: () => widget.services.analysis.cache.flush(),
    );
  }

  Future<void> _boot() async {
    final s = widget.services;
    // Engine first so analysis can start as soon as games are loaded.
    unawaited(
      s.engine.start(threads: s.settings.threads, hashMb: s.settings.hashMb),
    );
    unawaited(
      loadOpeningBook().then((b) {
        s.book = b;
        s.analysis.book = b;
      }),
    );
    await s.analysis.loadFromDisk();
    _sub = widget.intake.incoming.listen(_handleShared);
    await _drainShares();
    for (final f in widget.launchFiles) {
      await _handleShared(
        SharedItem(
          id: SharedItem.newId(),
          kind: SharedKind.file,
          value: f,
          fileName: f.split('/').last,
          receivedAt: DateTime.now(),
          source: SharedItem.sourceManual,
        ),
      );
    }
  }

  Future<void> _drainShares() async {
    final items = await widget.intake.takePending();
    for (final item in items) {
      await _handleShared(item);
    }
  }

  Future<void> _handleShared(SharedItem item) async {
    final s = widget.services;
    final outcome = switch (item.kind) {
      SharedKind.file => await s.importer.importFile(
        File(item.value),
        source: item.source,
      ),
      _ => await s.importer.importText(item.value, source: item.source),
    };
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    final ctx = nav.context;
    if (!ctx.mounted) return;
    if (outcome.ok && outcome.review != null) {
      nav.popUntil((r) => r.isFirst);
      openReview(ctx, outcome.review!.id);
      if (outcome.kind == ImportKind.duplicate || outcome.problems.isNotEmpty) {
        final msg = outcome.kind == ImportKind.duplicate
            ? outcome.message!
            : outcome.problems.first.message;
        ScaffoldMessenger.maybeOf(ctx)
            ?.showSnackBar(SnackBar(content: Text(msg)));
      }
      return;
    }
    // Could not import automatically: open the sheet with the shared text so
    // the user can add a username, fix the text, or paste PGN instead.
    nav.popUntil((r) => r.isFirst);
    final id = await showImportSheet(
      ctx,
      initialText: item.kind == SharedKind.file ? '' : item.value,
    );
    if (id != null && ctx.mounted) openReview(ctx, id);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: widget.services,
      child: ListenableBuilder(
        listenable: widget.services.settings,
        builder: (context, _) => MaterialApp(
          title: 'OpenReview',
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          themeMode: widget.services.settings.themeMode,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          home: Builder(
            builder: (context) {
              precachePieces(context, widget.services.settings.pieceSet);
              return const LibraryScreen();
            },
          ),
        ),
      ),
    );
  }
}
