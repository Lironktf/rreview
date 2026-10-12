# Move labels, accuracy and explanations

Everything below is implemented in `packages/review_core` (`classify.dart`, `accuracy.dart`, `score.dart`,
`explain.dart`) and covered by unit tests. Thresholds are constants in `ClassificationThresholds` and can be changed
in one place.

## 1. Scores and perspective

- The engine reports scores relative to the side to move. rreview converts every score to **White's
  perspective** immediately (`Score.fromUci`) and stores it that way. Displayed numbers are always White-relative:
  `+1.2` means White is better.
- **Mate scores are kept separate from centipawns** (`Score.mate(n)`, n in moves, negative = Black mates) and never
  converted to a fake centipawn value except for sorting/graph clamping. A position that is already checkmate is
  `Score.checkmated(color)` and shows as `#`.

## 2. Expected score (the quantity every label is based on)

A move is judged by how much it changes the mover's **expected score** E ∈ [0, 1], where E = W + D/2 from
win/draw/loss probabilities.

- Primary source: Stockfish's own **WDL output** (`UCI_ShowWDL true`), which is reported per mille from the side to
  move and flipped to White's perspective, then to the mover's perspective (`Wdl.fromPerMille`).
- Fallback (no WDL line available, mate scores, cached foreign evaluations): Stockfish 19's published win-rate
  model, re-implemented in `WinModel`:

  ```
  material = P + 3N + 3B + 5R + 9Q, clamped to [17, 78]; m = material / 58
  a = ((−142.72052667·m + 372.35176398)·m − 340.71073572)·m + 415.23490212
  b = ((5.93832785·m + 15.61267078)·m − 30.57816876)·m + 69.63866711
  v = cp · a / 100                      (Stockfish prints cp = 100·v/a)
  P(win)  = 1 / (1 + exp((a − v) / b))
  P(loss) = 1 / (1 + exp((a + v) / b))
  P(draw) = 1 − P(win) − P(loss)
  ```
  so 100 cp means a 50 % win probability, exactly as in Stockfish's `uci.cpp`. A forced mate for the mover is E = 1,
  being mated is E = 0.

## 3. Loss and labels

For the move played at ply *i* (mover M):

```
E_best   = expected score for M in the position before the move (engine's best line, depth D)
E_played = expected score for M after the played move
           (depth-D evaluation of the next position; for key moments a `searchmoves` search of the
            played move at the refinement depth replaces it, so both sides of the comparison come
            from the same search depth and position)
loss     = max(0, E_best − E_played)
```

| Label | Rule (first match wins) |
|---|---|
| Book | the move sequence so far is a prefix of a line in the lichess `chess-openings` dataset (CC0) |
| Best | the move is the engine's first choice, **or** loss ≤ 0.005 (practically equal alternative) |
| Excellent | loss ≤ 0.02 |
| Good | loss ≤ 0.05 |
| Inaccuracy | loss ≤ 0.10 |
| Mistake | loss ≤ 0.20 |
| Missed win | the mover's E_best ≥ 0.80 and E_played < 0.65 (a winning position became unclear), and loss > 0.10; also when a forced mate was available and the move throws it away while staying ahead |
| Blunder | loss > 0.20 |

Mate-specific rules sit in front of the continuous model: throwing away a forced mate is at least a Mistake (Missed
win when the loss is large); allowing a forced mate that was avoidable is a Blunder when loss > 0.10, otherwise a
Mistake; a slower mate than the engine's is Excellent/Good. These are checked against actual mate scores, not
heuristics.

Loss is always measured for the **mover**, so a Black blunder increases White's evaluation and is still a loss for
Black. Unit tests cover both colours, mate reversals, and the Missed-win band.

"Brilliant" is deliberately not awarded: reliable detection needs sacrifice verification beyond what a single engine
line proves, and a wrong "brilliant" is worse than none.

## 4. rreview accuracy

This is rreview's own number. It is **not** Chess.com's accuracy and no parity is claimed.

- Per move: `accuracy = 100 · exp(−4.2 · loss)`, clamped to [0, 100]. 0 loss → 100; 0.05 → 81; 0.10 → 66; 0.20 → 43.
- Per player: the mean of the harmonic mean and the arithmetic mean of the per-move values (book moves excluded).
  The harmonic component makes a single disaster weigh more than its share, which matches how a game is lost.

## 5. Key moments

The eight largest losses among Mistake / Missed win / Blunder (plus inaccuracies with loss ≥ 0.08), in game order.
These drive the guided review and the second analysis pass.

## 6. Explanations

Produced by `Explainer.explain`, deterministically, in priority order, and only when the claim is verified against
the board or the engine line:

1. Checkmate / stalemate: checked on the resulting position.
2. Missed forced mate: the engine's best score is a mate for the mover and the played move's score is not.
3. Allowed forced mate: the played move's score is a mate against the mover; the line shown is the engine PV.
4. Hanging piece: the opponent's first reply in the engine line captures a mover's piece and the material count after
   the legal prefix of that line is ≥ 2 pawns worse for the mover. "Undefended" is stated only when the capture square
   has no defenders.
5. Material loss / missed material: material balance along the legal prefix of the engine line (up to 8 plies) differs
   by ≥ 2 pawns between the best line and the played line; the first capture of the line is named.
6. Check-and-attack: the best move gives check and the moved piece also attacks an undefended (or more valuable) piece.
7. Otherwise a factual fallback: which move the engine preferred and how the evaluation changed for the mover.

Nothing is generated from templates that cannot be verified ("you should develop your pieces", etc.). An optional
language-model explainer could sit behind the same `ExplainContext` interface; the free review never calls one.
