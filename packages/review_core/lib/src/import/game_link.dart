/// Recognises game URLs from supported sites in shared text.
library;

enum GameSite { chesscom, lichess }

enum ChesscomGameType { live, daily, computer }

class GameLink {
  const GameLink({required this.site, required this.id, required this.url, this.chesscomType});

  final GameSite site;
  final String id;
  final String url;
  final ChesscomGameType? chesscomType;

  /// Numeric id for Chess.com.
  int? get numericId => int.tryParse(id);

  static final _urlRe = RegExp(r'https?://[^\s<>"\)\]]+', caseSensitive: false);

  // Verified URL shapes (docs/research/chesscom-lichess-import.md):
  //  www.chess.com/game/live/ID, /live/game/ID, /game/ID, /game/daily/ID,
  //  /daily/game/ID, /game/computer/ID, /analysis/game/live/ID[/review], with
  //  optional locale prefix and query string.
  static final _chesscomRe = RegExp(
    r'chess\.com/(?:[a-z]{2}(?:-[a-z]{2})?/)?(?:analysis/)?(?:game/(?:(live|daily|computer)/)?|(live|daily|computer)/game/)(\d+)',
    caseSensitive: false,
  );

  //  lichess.org/ID8, /ID8/white, /ID8ID4 (player view), /embed/game/ID8
  static final _lichessRe = RegExp(
    r'lichess\.org/(?:embed/game/)?([A-Za-z0-9]{8})(?:[A-Za-z0-9]{4})?(?:/(?:white|black))?(?:[/?#]|$)',
  );

  /// Finds the first supported game link in [text] (which may contain other
  /// words, as share-sheet payloads often do).
  static GameLink? find(String text) {
    for (final m in _urlRe.allMatches(text)) {
      final link = parse(m.group(0)!);
      if (link != null) return link;
    }
    // Also accept bare "chess.com/game/live/123" without a scheme.
    return parse(text.trim());
  }

  /// Parses a single URL.
  static GameLink? parse(String url) {
    final c = _chesscomRe.firstMatch(url);
    if (c != null) {
      final t = (c.group(1) ?? c.group(2) ?? 'live').toLowerCase();
      return GameLink(
        site: GameSite.chesscom,
        id: c.group(3)!,
        url: url,
        chesscomType: switch (t) {
          'daily' => ChesscomGameType.daily,
          'computer' => ChesscomGameType.computer,
          _ => ChesscomGameType.live,
        },
      );
    }
    final l = _lichessRe.firstMatch(url);
    if (l != null) {
      final id = l.group(1)!;
      // Avoid matching non-game paths like lichess.org/training or /@/user.
      const reserved = {'training', 'tournament', 'practice', 'analysis', 'broadcast', 'learn', 'study'};
      if (reserved.contains(id.toLowerCase())) return null;
      if (RegExp(r'lichess\.org/(?:@|study|tournament|swiss|team|forum|player|inbox|api)/').hasMatch(url)) return null;
      return GameLink(site: GameSite.lichess, id: id, url: url);
    }
    return null;
  }

  String get siteName => site == GameSite.chesscom ? 'Chess.com' : 'Lichess';

  /// Canonical URL for display/storage.
  String get canonicalUrl => switch (site) {
        GameSite.lichess => 'https://lichess.org/$id',
        GameSite.chesscom => 'https://www.chess.com/game/${chesscomType!.name}/$id',
      };
}
