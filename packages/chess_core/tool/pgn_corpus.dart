// Replays games from a PGN corpus and checks our SAN matches the source SAN.
// Usage: dart run tool/pgn_corpus.dart <file.pgn> [maxGames]
import 'dart:io';

import 'package:chess_core/chess_core.dart';

void main(List<String> args) {
  final file = File(args[0]);
  final maxGames = args.length > 1 ? int.parse(args[1]) : 2000;
  final text = file.readAsStringSync();
  // Split roughly into chunks of games to limit memory.
  final chunks = text.split(RegExp(r'\n\n(?=\[Event )'));
  var games = 0, plies = 0, problems = 0, sanMismatch = 0, failed = 0;
  final sw = Stopwatch()..start();
  for (final chunk in chunks) {
    if (games >= maxGames) break;
    List<ParsedGame> parsed;
    try {
      parsed = PgnReader.readAll(chunk);
    } catch (e) {
      failed++;
      print('FAILED: $e\n${chunk.substring(0, chunk.length.clamp(0, 200))}');
      continue;
    }
    for (final pg in parsed) {
      games++;
      plies += pg.game.plies.length;
      if (pg.problems.isNotEmpty) {
        problems++;
        print('PROBLEM in game ${pg.game.white} vs ${pg.game.black}: ${pg.problems}');
      }
      // Compare our SAN with the tokens in the source movetext.
      final body = chunk.split('\n\n').skip(1).join(' ');
      final tokens = body
          .replaceAll(RegExp(r'\{[^}]*\}'), ' ')
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty && !RegExp(r'^\d+\.+$').hasMatch(t) && !RegExp(r'^(1-0|0-1|1/2-1/2|\*)$').hasMatch(t))
          .map((t) => t.replaceAll(RegExp(r'^\d+\.+'), '').replaceAll(RegExp(r'[!?]+$'), ''))
          .toList();
      for (var i = 0; i < pg.game.plies.length && i < tokens.length; i++) {
        if (pg.game.plies[i].san != tokens[i]) {
          sanMismatch++;
          if (sanMismatch < 20) print('SAN differs ply $i: ours ${pg.game.plies[i].san} source ${tokens[i]}');
        }
      }
    }
  }
  print('games $games plies $plies problems $problems sanMismatch $sanMismatch failed $failed in ${sw.elapsed}');
}
