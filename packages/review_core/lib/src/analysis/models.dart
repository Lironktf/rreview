/// Data model of a reviewed game.
library;

import 'package:chess_core/chess_core.dart';

import '../score.dart';
import 'accuracy.dart';
import 'settings.dart';

/// Classification of a played move. See docs/CLASSIFICATION.md.
enum MoveLabel {
  book('Book'),
  best('Best'),
  excellent('Excellent'),
  good('Good'),
  inaccuracy('Inaccuracy'),
  mistake('Mistake'),
  missedWin('Missed win'),
  blunder('Blunder');

  const MoveLabel(this.display);
  final String display;

  bool get isBad => index >= MoveLabel.inaccuracy.index;

  /// Short glyph used in the move list.
  String get glyph => switch (this) {
        MoveLabel.book => '',
        MoveLabel.best => '',
        MoveLabel.excellent => '!',
        MoveLabel.good => '',
        MoveLabel.inaccuracy => '?!',
        MoveLabel.mistake => '?',
        MoveLabel.missedWin => '?',
        MoveLabel.blunder => '??',
      };
}

/// The engine's verdict on one position.
class PositionEval {
  const PositionEval({
    required this.fen,
    required this.depth,
    required this.score,
    required this.wdl,
    required this.bestMove,
    required this.pv,
    required this.nodes,
  });

  final String fen;
  final int depth;

  /// From White's perspective.
  final Score score;

  /// From White's perspective.
  final Wdl wdl;

  /// UCI; `(none)` for terminal positions.
  final String bestMove;
  final List<String> pv;
  final int nodes;

  bool get isTerminal => bestMove == '(none)';

  Map<String, dynamic> toJson() => {
        'fen': fen,
        'depth': depth,
        'score': score.toJson(),
        'wdl': wdl.toJson(),
        'best': bestMove,
        'pv': pv,
        'nodes': nodes,
      };

  static PositionEval fromJson(Map<String, dynamic> j) => PositionEval(
        fen: j['fen'] as String,
        depth: j['depth'] as int,
        score: Score.fromJson((j['score'] as Map).cast<String, dynamic>()),
        wdl: Wdl.fromJson((j['wdl'] as Map).cast<String, dynamic>()),
        bestMove: j['best'] as String,
        pv: (j['pv'] as List).cast<String>(),
        nodes: j['nodes'] as int? ?? 0,
      );
}

/// Everything the review knows about one played move.
class MoveReview {
  const MoveReview({
    required this.ply,
    required this.before,
    required this.after,
    required this.playedScore,
    required this.loss,
    required this.label,
    required this.bestSan,
    required this.bestPvSan,
    required this.explanation,
    required this.accuracy,
    required this.refined,
  });

  final int ply;

  /// Evaluation of the position before the move (engine's best line).
  final PositionEval before;

  /// Evaluation of the position after the move.
  final PositionEval after;

  /// Score of the played move at depth comparable to [before], White's
  /// perspective. Normally [after]'s score; a `searchmoves` refinement may
  /// replace it with a like-for-like value.
  final Score playedScore;

  /// Expected-score loss for the mover, in [0, 1].
  final double loss;
  final MoveLabel label;
  final String bestSan;
  final List<String> bestPvSan;
  final String? explanation;

  /// Per-move accuracy in [0, 100].
  final double accuracy;
  final bool refined;

  MoveReview copyWith({MoveLabel? label, String? explanation}) => MoveReview(
        ply: ply,
        before: before,
        after: after,
        playedScore: playedScore,
        loss: loss,
        label: label ?? this.label,
        bestSan: bestSan,
        bestPvSan: bestPvSan,
        explanation: explanation ?? this.explanation,
        accuracy: accuracy,
        refined: refined,
      );

  Map<String, dynamic> toJson() => {
        'ply': ply,
        'before': before.toJson(),
        'after': after.toJson(),
        'played': playedScore.toJson(),
        'loss': loss,
        'label': label.name,
        'bestSan': bestSan,
        'bestPv': bestPvSan,
        if (explanation != null) 'why': explanation,
        'acc': accuracy,
        'refined': refined,
      };

  static MoveReview fromJson(Map<String, dynamic> j) => MoveReview(
        ply: j['ply'] as int,
        before: PositionEval.fromJson((j['before'] as Map).cast<String, dynamic>()),
        after: PositionEval.fromJson((j['after'] as Map).cast<String, dynamic>()),
        playedScore: Score.fromJson((j['played'] as Map).cast<String, dynamic>()),
        loss: (j['loss'] as num).toDouble(),
        label: MoveLabel.values.firstWhere((l) => l.name == j['label'], orElse: () => MoveLabel.good),
        bestSan: j['bestSan'] as String,
        bestPvSan: (j['bestPv'] as List).cast<String>(),
        explanation: j['why'] as String?,
        accuracy: (j['acc'] as num).toDouble(),
        refined: j['refined'] as bool? ?? false,
      );
}

class PlayerSummary {
  const PlayerSummary({required this.accuracy, required this.counts, required this.moveCount});
  final double? accuracy;
  final Map<MoveLabel, int> counts;
  final int moveCount;

  int count(MoveLabel l) => counts[l] ?? 0;
}

enum ReviewStatus { pending, running, paused, complete, failed }

/// A game plus its (possibly partial) review.
class GameReview {
  GameReview({
    required this.id,
    required this.game,
    required this.settings,
    required this.engineId,
    required this.moves,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.openingName,
    this.openingEco,
    this.bookPlies = 0,
    this.sourceUrl,
    this.error,
    this.progress = 0,
    this.phase = '',
  });

  final String id;
  final Game game;
  final AnalysisSettings settings;
  final String engineId;

  /// One entry per ply; entries are filled in as analysis progresses.
  final List<MoveReview?> moves;
  final ReviewStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? openingName;
  final String? openingEco;

  /// Number of leading plies found in the opening book.
  final int bookPlies;
  final String? sourceUrl;
  final String? error;

  /// 0..1 overall progress across both passes.
  final double progress;

  /// Human-readable phase, e.g. "Analysing move 23 of 61".
  final String phase;

  int get analysedCount => moves.where((m) => m != null).length;
  bool get isComplete => status == ReviewStatus.complete;

  /// Evaluation after ply [i] (i = -1 or 0 = start). White's perspective.
  Score? scoreAfterPly(int i) {
    if (i < 0) return moves.isNotEmpty && moves[0] != null ? moves[0]!.before.score : null;
    final m = i < moves.length ? moves[i] : null;
    return m?.after.score;
  }

  PlayerSummary summaryFor(Color c) {
    final counts = <MoveLabel, int>{};
    final accs = <double>[];
    var n = 0;
    for (var i = 0; i < moves.length && i < game.plies.length; i++) {
      final m = moves[i];
      if (m == null) continue;
      if (game.plies[i].color != c) continue;
      n++;
      counts[m.label] = (counts[m.label] ?? 0) + 1;
      if (m.label != MoveLabel.book) accs.add(m.accuracy);
    }
    return PlayerSummary(
      accuracy: accs.isEmpty ? null : gameAccuracy(accs),
      counts: counts,
      moveCount: n,
    );
  }

  /// Key moments: the costliest mistakes and missed wins, in game order.
  List<int> get keyMoments {
    final scored = <(int, double)>[];
    for (var i = 0; i < moves.length; i++) {
      final m = moves[i];
      if (m == null) continue;
      if (m.label.index >= MoveLabel.mistake.index) {
        scored.add((i, m.loss + (m.label == MoveLabel.missedWin ? 0.1 : 0)));
      } else if (m.label == MoveLabel.inaccuracy && m.loss >= 0.08) {
        scored.add((i, m.loss));
      }
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return (scored.take(8).map((e) => e.$1).toList()..sort());
  }

  GameReview copyWith({
    List<MoveReview?>? moves,
    ReviewStatus? status,
    DateTime? updatedAt,
    String? openingName,
    String? openingEco,
    int? bookPlies,
    String? error,
    double? progress,
    String? phase,
    AnalysisSettings? settings,
    String? engineId,
    bool clearError = false,
  }) =>
      GameReview(
        id: id,
        game: game,
        settings: settings ?? this.settings,
        engineId: engineId ?? this.engineId,
        moves: moves ?? this.moves,
        status: status ?? this.status,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
        openingName: openingName ?? this.openingName,
        openingEco: openingEco ?? this.openingEco,
        bookPlies: bookPlies ?? this.bookPlies,
        sourceUrl: sourceUrl,
        error: clearError ? null : (error ?? this.error),
        progress: progress ?? this.progress,
        phase: phase ?? this.phase,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'game': game.toJson(),
        'settings': settings.toJson(),
        'engineId': engineId,
        'moves': moves.map((m) => m?.toJson()).toList(),
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        if (openingName != null) 'openingName': openingName,
        if (openingEco != null) 'openingEco': openingEco,
        'bookPlies': bookPlies,
        if (sourceUrl != null) 'sourceUrl': sourceUrl,
        if (error != null) 'error': error,
        'progress': progress,
      };

  static GameReview fromJson(Map<String, dynamic> j) {
    final status = ReviewStatus.values.firstWhere((s) => s.name == j['status'], orElse: () => ReviewStatus.pending);
    return GameReview(
      id: j['id'] as String,
      game: Game.fromJson((j['game'] as Map).cast<String, dynamic>()),
      settings: AnalysisSettings.fromJson((j['settings'] as Map).cast<String, dynamic>()),
      engineId: j['engineId'] as String,
      moves: (j['moves'] as List)
          .map((m) => m == null ? null : MoveReview.fromJson((m as Map).cast<String, dynamic>()))
          .toList(),
      // A review that was running when the app died resumes as paused.
      status: status == ReviewStatus.running ? ReviewStatus.paused : status,
      createdAt: DateTime.parse(j['createdAt'] as String),
      updatedAt: DateTime.parse(j['updatedAt'] as String),
      openingName: j['openingName'] as String?,
      openingEco: j['openingEco'] as String?,
      bookPlies: j['bookPlies'] as int? ?? 0,
      sourceUrl: j['sourceUrl'] as String?,
      error: j['error'] as String?,
      progress: (j['progress'] as num?)?.toDouble() ?? 0,
    );
  }
}
