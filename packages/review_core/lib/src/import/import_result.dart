/// Outcome of resolving a shared link or text into PGN.
library;

enum ImportFailure {
  /// The text/URL is not something we recognise.
  unrecognised,

  /// Recognised site, but the game could not be found through public endpoints.
  notFound,

  /// Chess.com links need a player's username to search the public archives.
  needsUsername,

  /// Network problem or rate limit.
  network,

  /// The game exists but uses rules we cannot analyse.
  unsupported,
}

class ImportResult {
  const ImportResult.success(this.pgn, {required this.source, this.sourceUrl})
      : failure = null,
        message = null;
  const ImportResult.failed(this.failure, this.message, {this.sourceUrl})
      : pgn = null,
        source = null;

  final String? pgn;
  final String? source;
  final String? sourceUrl;
  final ImportFailure? failure;
  final String? message;

  bool get isSuccess => pgn != null;
}
