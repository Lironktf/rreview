/// Resolves game links into PGN through documented public endpoints only.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'game_link.dart';
import 'import_result.dart';

const userAgent = 'OpenReview/1.0 (open-source chess review app; https://github.com/Lironktf/openreview)';

class GameResolver {
  GameResolver({http.Client? client, this.maxChesscomMonths = 36}) : _client = client ?? http.Client();

  final http.Client _client;

  /// How many monthly archives (newest first) to scan per username.
  final int maxChesscomMonths;

  Future<ImportResult> resolve(GameLink link, {List<String> chesscomUsernames = const []}) {
    return switch (link.site) {
      GameSite.lichess => _resolveLichess(link),
      GameSite.chesscom => _resolveChesscom(link, chesscomUsernames),
    };
  }

  // Lichess: documented export endpoint, no auth, one request.
  Future<ImportResult> _resolveLichess(GameLink link) async {
    final uri = Uri.parse('https://lichess.org/game/export/${link.id}?clocks=true&evals=false&opening=true&literate=false');
    try {
      final r = await _client.get(uri, headers: {'Accept': 'application/x-chess-pgn', 'User-Agent': userAgent});
      if (r.statusCode == 404 || r.statusCode == 303) {
        return ImportResult.failed(ImportFailure.notFound, 'Lichess has no game with id ${link.id}.',
            sourceUrl: link.canonicalUrl);
      }
      if (r.statusCode == 429) {
        return ImportResult.failed(ImportFailure.network, 'Lichess asked us to slow down. Try again in a minute.',
            sourceUrl: link.canonicalUrl);
      }
      if (r.statusCode != 200) {
        return ImportResult.failed(ImportFailure.network, 'Lichess returned HTTP ${r.statusCode}.',
            sourceUrl: link.canonicalUrl);
      }
      final body = utf8.decode(r.bodyBytes);
      if (!body.contains('[')) {
        return ImportResult.failed(ImportFailure.notFound, 'Lichess returned no PGN for this game.',
            sourceUrl: link.canonicalUrl);
      }
      return ImportResult.success(body, source: 'lichess', sourceUrl: link.canonicalUrl);
    } catch (e) {
      return ImportResult.failed(ImportFailure.network, 'Could not reach Lichess: $e', sourceUrl: link.canonicalUrl);
    }
  }

  // Chess.com: the Published-Data API has no game-by-id endpoint, so we search
  // the given players' monthly archives (newest first) for a matching `url`.
  Future<ImportResult> _resolveChesscom(GameLink link, List<String> usernames) async {
    final id = link.numericId;
    if (id == null) {
      return ImportResult.failed(ImportFailure.unrecognised, 'Not a Chess.com game link.', sourceUrl: link.url);
    }
    final names = usernames.map((u) => u.trim().toLowerCase()).where((u) => u.isNotEmpty).toSet();
    if (names.isEmpty) {
      return ImportResult.failed(ImportFailure.needsUsername,
          'Chess.com links can only be looked up through a player\'s public game archive. Add your Chess.com username.',
          sourceUrl: link.canonicalUrl);
    }
    var sawNetworkError = false;
    for (final user in names) {
      try {
        final archives = await _json('https://api.chess.com/pub/player/$user/games/archives');
        if (archives == null) continue; // unknown user
        final months = ((archives['archives'] as List?) ?? const []).cast<String>().reversed.take(maxChesscomMonths);
        for (final monthUrl in months) {
          final month = await _json(monthUrl);
          if (month == null) continue;
          final games = (month['games'] as List?) ?? const [];
          int? minId;
          for (final g in games) {
            final url = (g as Map)['url'] as String?;
            if (url == null) continue;
            final gid = int.tryParse(url.split('/').last.split('?').first);
            if (gid == null) continue;
            if (minId == null || gid < minId) minId = gid;
            if (gid == id) {
              final rules = (g['rules'] as String?) ?? 'chess';
              if (rules != 'chess' && rules != 'chess960') {
                return ImportResult.failed(ImportFailure.unsupported,
                    'This is a Chess.com "$rules" game; only standard chess and Chess960 can be analysed.',
                    sourceUrl: link.canonicalUrl);
              }
              final pgn = g['pgn'] as String?;
              if (pgn == null || pgn.isEmpty) {
                return ImportResult.failed(ImportFailure.notFound, 'Chess.com has no PGN for this game.',
                    sourceUrl: link.canonicalUrl);
              }
              return ImportResult.success(pgn, source: 'chess.com', sourceUrl: link.canonicalUrl);
            }
          }
          // Live game ids grow over time; once a month's smallest id is above
          // ours, older months cannot contain it either... but daily/live ids
          // live in different ranges, so only prune within the same type.
          if (link.chesscomType == ChesscomGameType.live && minId != null && minId > id) {
            // Keep scanning: an older month may still hold it.
            continue;
          }
        }
      } on http.ClientException {
        sawNetworkError = true;
      } catch (_) {
        sawNetworkError = true;
      }
    }
    if (sawNetworkError) {
      return ImportResult.failed(ImportFailure.network, 'Could not reach Chess.com. Check your connection and try again.',
          sourceUrl: link.canonicalUrl);
    }
    return ImportResult.failed(ImportFailure.notFound,
        'Game $id was not found in the public archives of ${names.join(', ')}. Add the username of either player, or paste the PGN.',
        sourceUrl: link.canonicalUrl);
  }

  Future<Map<String, dynamic>?> _json(String url) async {
    final r = await _client.get(Uri.parse(url), headers: {'Accept': 'application/json', 'User-Agent': userAgent});
    if (r.statusCode == 404) return null;
    if (r.statusCode == 429) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final again = await _client.get(Uri.parse(url), headers: {'Accept': 'application/json', 'User-Agent': userAgent});
      if (again.statusCode != 200) throw http.ClientException('HTTP ${again.statusCode}');
      return jsonDecode(utf8.decode(again.bodyBytes)) as Map<String, dynamic>;
    }
    if (r.statusCode != 200) throw http.ClientException('HTTP ${r.statusCode}');
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  void close() => _client.close();
}
