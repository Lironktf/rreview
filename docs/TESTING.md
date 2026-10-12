# What was tested, and how

All of this ran on the Linux development machine (Arch Linux, Flutter 3.47.7, Dart 3.13.5, clang 22) on 2026-10-11.
Nothing below was run on an iPhone, an iPad or an Android device: there is no Xcode or Android SDK here.

## Chess rules (`packages/chess_core`, 48 tests + 2 tools)

- **Perft suite**: start position (to depth 4), Kiwipete, positions 3–6 of the chessprogramming.org suite, six Chess960
  positions whose counts were produced with Stockfish 19's `go perft` (`test/perft_test.dart`).
- **Cross-check against Stockfish**: `tool/crosscheck_sf.dart` plays 60 random games (standard, Chess960 and tactical
  start positions, up to 140 plies each) and compares our legal-move set with Stockfish's `go perft 1` at every
  position, plus SAN round-trips for every legal move: **7,897 positions, 0 mismatches**.
- **PGN corpus**: `tool/pgn_corpus.dart` replayed **3,000 games (249,012 plies) from the lichess elite database** with
  zero SAN disagreements and zero parse failures.
- Rules tests: en passant (including the pin case), promotions and underpromotion with capture and check, castling
  rights lost by king/rook moves and rook captures, castling through/out of check, Chess960 castling notation (king
  takes rook) and X-FEN output, checkmate, stalemate, insufficient material variants, threefold repetition, fifty-move
  rule, malformed FENs (missing rank, bad side, no king, pawns on the back rank), lenient FENs (short, bogus en passant,
  phantom castling rights), SAN disambiguation by file / rank / full square, tolerant SAN parsing.
- PGN tests: Chess.com export with `[%clk]` and renumbered Black moves, Lichess export with `[%eval]`, variations and
  NAGs, bare movetext with glyphs, truncation at an illegal move with a precise message ("3... Nf3 is not a legal move",
  "White is in check and must respond"), garbage tokens, non-PGN text, FEN start positions, invalid FEN header
  fallback, Chess960 games with Shredder castling fields, unsupported variants (Crazyhouse) flagged, multi-game files,
  null moves, result header vs. movetext disagreement, PGN and JSON round trips, a game ending in checkmate.

## Review core (`packages/review_core`, 21 unit tests + 3 real-engine tests)

- Score perspective: side-to-move → White for cp and mate, both colours; mate display; checkmated positions.
- Stockfish 19 win-rate model reimplementation: 0 cp = 50 %, 100 cp ≈ 50 % win probability, WDL per-mille flip for
  Black to move.
- UCI `info` parsing incl. `wdl`, mate scores, bounds, `string`/`currmove` lines.
- Classification thresholds for every label, the Missed-win band, forced-mate rules on both sides, Book precedence.
- Accuracy formula values and the harmonic/arithmetic blend.
- Game-link recognition for every Chess.com and Lichess URL shape found in research, with negatives.
- Opening book longest-prefix lookup and book-ply marking.
- **Analyzer with a scripted engine** (`test/fake_engine.dart`): blunder into mate + missed mate are labelled and
  explained; Black-perspective loss computed for Black, not White; cancellation pauses and resume reuses cached
  evaluations (fewer `go` commands); review JSON round trip; progressive updates emitted.
- **Analyzer with the real Stockfish 19 binary** (`test/real_engine_test.dart`, `STOCKFISH_BIN=…`): Scholar's mate
  game (mate detection on both sides, accuracies ordered correctly), a FEN-start game with promotion / capture
  (perspective sanity), and a 50-ply real game: every ply evaluated, two passes, key moments refined, every move
  explained, ≈1 s wall-clock at depth 10/14 on this machine.

## Engine bridge (`packages/stockfish_ffi`)

Built the plugin's native library with the project's CMake (x86-64-v3 flags) and ran `test/engine_smoke_test.dart`
against it with the real `nn-1a298aa575a0.nnue`: UCI handshake, option listing, `EvalFile`, `UCI_ShowWDL` output,
mate-in-1 found with `wdl 1000 0 0`, centipawn evaluation with WDL, `go infinite` + `stop`, `quit`, and a restart in
the same process.

## App (`app`, 10 widget/channel tests + goldens)

- `flutter analyze` clean; `flutter build linux --release` succeeds (Stockfish compiled through Flutter's plugin
  CMake flow).
- Widget tests: library shows an imported game and opens the review; stepping through moves; labels and explanation
  for a blunder; Try-again mode (prompt, Show solution, Continue); Summary tab; move-list tap jumps.
- Golden images (real Roboto + Material icon fonts) for the review screen (light and dark), the summary tab and the
  library: `app/test/goldens/*.png`. These are the screenshots used to check the design rules in docs/DESIGN.md.
- Share-intake channel tests (JSON round trip, lenient parsing, no-op platform implementation, mocked method and
  event channels).
- **Live desktop run with the real engine**: launched `rreview` with `RREVIEW_IMPORT=sample.pgn`. Observed in the
  persisted data: the 98 MB network was copied once, Stockfish 19 started in-process, all 50 plies were analysed at
  depth 16, 13 key positions were refined at depth 20 with `searchmoves`, the review reached `complete`, the
  evaluation cache was written, and the labels/explanations matched the real-engine unit test (e.g. "This leaves the
  queen on h5 undefended; Qxh5 wins it", "You missed a forced mate in 4, starting with Qxe2+"). A second launch with the
  same file reported the duplicate instead of re-importing. The screen was locked during the run, so the live window
  itself could not be captured; the goldens stand in for it.

## Failure cases exercised

| Case | Where |
|---|---|
| Invalid / truncated PGN | chess_core PGN tests, import sheet messages |
| FEN-based games | PGN tests, real-engine promotion test |
| Both colours' score perspectives | score tests, analyzer Black-blunder test, real-engine Scholar's mate |
| Forced mate and mate reversal | classify tests, analyzer and real-engine tests, live run |
| Underpromotion, castling, en passant | rules tests, Stockfish cross-check |
| Analysis cancellation / interruption | analyzer cancel-and-resume test; `paused` reviews resume on launch (store round trip) |
| Duplicate import | fingerprint and link de-duplication in ImportService (live run: second import reported duplicate) |
| Unresolvable game URLs | resolver failure kinds (`notFound`, `needsUsername`, `network`, `unsupported`) surfaced in the import sheet |
| Persistence across relaunch | review JSON + eval cache round trips; live run data re-read from disk |
| Long games / mobile constraints | 50-ply game timing; Threads 1 / Hash 16 MB defaults; lazy lists |

## Not verified (needs a device)

- iOS build, code signing, the share extension end to end with a real Chess.com share payload, Open-in for `.pgn`
  attachments, Android intents. See docs/SHARE_FLOW.md and docs/RELEASE_IOS.md.
- Network resolvers against the live Chess.com and Lichess APIs were researched (endpoints probed on 2026-10-11) but
  the Dart resolver was not exercised against the network from the test suite (no network calls in tests by design).
- Performance and thermals on a phone CPU.
- Variation exploration and Try-again with the live engine were exercised only through the controller logic and the
  scripted-engine paths, not on a device.
