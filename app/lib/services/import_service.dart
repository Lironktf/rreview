/// Turns shared text, links and files into saved reviews.
library;

import 'dart:io';

import 'package:chess_core/chess_core.dart';
import 'package:review_core/review_core.dart';

import 'analysis_controller.dart';
import 'settings_service.dart';

enum ImportKind { created, duplicate, unsupported, invalid, needsUsername, notFound, network, nothing }

class ImportOutcome {
  const ImportOutcome(this.kind, {this.review, this.message, this.problems = const [], this.link});
  final ImportKind kind;
  final GameReview? review;
  final String? message;
  final List<PgnProblem> problems;
  final GameLink? link;

  bool get ok => kind == ImportKind.created || kind == ImportKind.duplicate;
}

class ImportService {
  ImportService({required this.controller, required this.settings, GameResolver? resolver})
      : resolver = resolver ?? GameResolver();

  final AnalysisController controller;
  final AppSettings settings;
  final GameResolver resolver;

  /// Imports from arbitrary text: a URL inside text, or PGN.
  Future<ImportOutcome> importText(String text, {String source = 'manual'}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const ImportOutcome(ImportKind.nothing, message: 'Nothing to import.');
    if (PgnReader.looksLikePgn(trimmed)) {
      return importPgn(trimmed, source: source);
    }
    final link = GameLink.find(trimmed);
    if (link != null) return importLink(link, source: source);
    // Maybe it is PGN after all (movetext without numbers etc.)
    try {
      PgnReader.read(trimmed);
    } on PgnException {
      return const ImportOutcome(ImportKind.invalid,
          message: 'This is neither a game link nor PGN. Paste a Chess.com or Lichess game link, or the PGN text.');
    }
    return importPgn(trimmed, source: source);
  }

  Future<ImportOutcome> importFile(File file, {String source = 'file'}) async {
    String text;
    try {
      text = await file.readAsString();
    } catch (e) {
      return ImportOutcome(ImportKind.invalid, message: 'Could not read ${file.path.split('/').last}: $e');
    }
    return importPgn(text, source: source);
  }

  Future<ImportOutcome> importLink(GameLink link, {String source = 'link'}) async {
    // Duplicate by link id before touching the network.
    final existing = controller.reviews.where((r) => r.sourceUrl == link.canonicalUrl).toList();
    if (existing.isNotEmpty) {
      return ImportOutcome(ImportKind.duplicate, review: existing.first, message: 'This game is already in your library.', link: link);
    }
    final result = await resolver.resolve(link, chesscomUsernames: settings.chesscomUsernames);
    if (!result.isSuccess) {
      final kind = switch (result.failure!) {
        ImportFailure.needsUsername => ImportKind.needsUsername,
        ImportFailure.notFound => ImportKind.notFound,
        ImportFailure.network => ImportKind.network,
        ImportFailure.unsupported => ImportKind.unsupported,
        ImportFailure.unrecognised => ImportKind.invalid,
      };
      return ImportOutcome(kind, message: result.message, link: link);
    }
    return importPgn(result.pgn!, source: result.source!, sourceUrl: link.canonicalUrl);
  }

  Future<ImportOutcome> importPgn(String pgn, {String source = 'pgn', String? sourceUrl}) async {
    List<ParsedGame> parsed;
    try {
      parsed = PgnReader.readAll(pgn);
    } on PgnException catch (e) {
      return ImportOutcome(ImportKind.invalid, message: e.message);
    } on ChessException catch (e) {
      return ImportOutcome(ImportKind.invalid, message: e.message);
    }
    final first = parsed.first;
    if (first.unsupportedVariant != null) {
      return ImportOutcome(ImportKind.unsupported,
          message: '${first.unsupportedVariant} games use different rules and cannot be analysed.');
    }
    if (first.game.plies.isEmpty) {
      return ImportOutcome(ImportKind.invalid, message: 'The game has no moves to analyse.', problems: first.problems);
    }
    final game = first.game;
    final fingerprint = gameFingerprint(game);
    final dup = controller.reviews.where((r) => gameFingerprint(r.game) == fingerprint).toList();
    if (dup.isNotEmpty) {
      return ImportOutcome(ImportKind.duplicate, review: dup.first, message: 'This game is already in your library.', problems: first.problems);
    }
    final headers = Map<String, String>.from(game.headers);
    if (sourceUrl != null && !headers.containsKey('Link')) headers['Link'] = sourceUrl;
    final link = sourceUrl ?? _linkFromHeaders(game);
    final review = GameReview(
      id: _newId(),
      game: Game(headers: headers, initialFen: game.initialFen, plies: game.plies, result: game.result, chess960: game.chess960),
      settings: settings.analysisSettings,
      engineId: controller.engine.engineId,
      moves: List.filled(game.plies.length, null),
      status: ReviewStatus.pending,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      sourceUrl: link,
    );
    await controller.add(review);
    return ImportOutcome(ImportKind.created, review: review, problems: first.problems);
  }

  static String? _linkFromHeaders(Game g) {
    final raw = g.link ?? g.site;
    if (raw == null) return null;
    return GameLink.find(raw)?.canonicalUrl;
  }

  static String _newId() {
    final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final r = (DateTime.now().hashCode ^ t.hashCode).toUnsigned(20).toRadixString(36);
    return '$t$r';
  }
}

/// Stable identity of a game: start position plus the exact move sequence.
String gameFingerprint(Game g) {
  var h = 0xcbf29ce484222325;
  void mix(String s) {
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
  }
  mix(g.initialFen);
  for (final p in g.plies) {
    mix(p.move.uci);
  }
  return h.toRadixString(16);
}
