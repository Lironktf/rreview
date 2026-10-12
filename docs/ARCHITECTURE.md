# OpenReview — architecture and build plan

Written 2026-10-11. OpenReview is a mobile chess analysis app: share a game from Chess.com (or paste a PGN /
URL / .pgn file), get an unlimited, local, Stockfish-powered review with move labels, an evaluation graph,
explanations, a guided tour of the key moments, and a "try again" mode.

## Stack decision

| Concern | Choice | Why |
|---|---|---|
| App framework | **Flutter 3.47 (Dart 3.13)** | One codebase for iOS (first) and Android; real native binaries; Dart isolates keep analysis off the UI thread; Dart FFI runs C++ in-process. The development machine is Linux without Xcode, and Flutter is the only stack here whose UI, domain logic and engine integration can all be built and tested locally (Linux desktop target + `dart test`) while compiling unchanged for iOS. |
| Engine | **Stockfish 19 (official `sf_19` tag, GPLv3) with NNUE `nn-1a298aa575a0.nnue`**, compiled from source into the app via a Flutter FFI plugin (`packages/stockfish_ffi`) | Current stable release; the source in `../chess/tools/stockfish` is byte-identical to the GitHub tag (verified with `diff -r`). Built with `-DNNUE_EMBEDDING_OFF`; the net ships as an app asset and is copied once to app support storage. |
| Engine bridge | Replace `std::cin`/`std::cout` stream buffers with queues inside the process, run `UCIEngine::loop()` on a C++ thread | No pipes/dup2 (fragile on iOS), plain UCI text in and out, so any UCI engine (e.g. the owner's Rust engine *Anna*) can be swapped behind the same Dart interface. |
| Chess rules | Own pure-Dart package `packages/chess_core` (0x88 mailbox, full legality, SAN, FEN, PGN) | Needed for legal replay, PGN tolerance and precise error messages. Verified with the standard perft suite and cross-checked against the Anna engine's perft (`../chess/target/release/engine perft`). |
| Review logic | Pure-Dart package `packages/review_core`: analysis scheduler, score normalisation, WDL/expected-score model, classification, accuracy, explanations, opening book | Portable to Android unchanged; fully unit-tested without an engine via recorded UCI fixtures. |
| Persistence | JSON file per review (app documents on phones, app support on desktop) + a file-backed evaluation cache keyed by (engine id, depth, FEN) | Simple, local-only, survives relaunch, easy to export. |
| Share intake | Hand-written iOS Share Extension (Swift) → App Group container → main app via `MethodChannel` / `app_links` | Lightweight: validate, persist, hand off. No analysis in the extension. |
| Remote import | Chess.com Published-Data API (player monthly archives), Lichess game export API | Documented public endpoints only. |

## Packages

```
chessy/
  app/                     Flutter app "OpenReview" (ios/, android/, linux/, lib/, test/)
  packages/chess_core/     rules, FEN, SAN, PGN, perft tests
  packages/review_core/    UCI client, analysis pipeline, classification, accuracy, explanations, book
  packages/stockfish_ffi/  Flutter FFI plugin: Stockfish 19 + bridge (podspec, CMake)
  docs/                    this file, ENGINE.md, CLASSIFICATION.md, SHARE_FLOW.md, TESTING.md, RELEASE_IOS.md
```

## Status (2026-10-11)

Built and verified on Linux: PGN text → `chess_core` parse + legal replay → `review_core` two-pass analysis with the
real in-process Stockfish 19 → interactive review (board, eval bar, move list, labels, graph, explanations, summary,
key moments, guided review, try-again, variations) → saved locally → reopened. Plus: library with search, delete/undo,
pause/resume/reanalyse; import sheet (link, PGN, `.pgn` file); Chess.com (public archives) and Lichess resolvers;
share summary (text + board image); light/dark themes; three piece sets; settings; licences screen.

Written but not compiled here (no Xcode / Android SDK): the iOS share extension and Open-in handling, the Android
intent handling, the iOS/Android native builds of the engine plugin. See docs/SHARE_FLOW.md, docs/RELEASE_IOS.md and
docs/TESTING.md.

## Analysis pipeline

1. Replay the game; produce FEN per ply.
2. Pass 1 (preview): for each position, `go depth D1` with `MultiPV 1` and `UCI_ShowWDL true`.
   Store best move, PV, score (cp or mate, side-to-move → normalised to White), WDL.
3. Pass 2 (refine): positions flagged as important (large expected-score loss, eval swing between
   consecutive plies, mate boundaries) are re-searched deeper (`D2`), and the played move is searched with
   `searchmoves` at the same depth so the loss compares like with like.
4. Each move's loss = E(best) − E(played) in expected-score points, both from the mover's perspective.
   Labels, accuracy, key moments and explanations are recomputed; the UI updates in place.
5. Everything is cached by (FEN, engine id, depth/limits). Cancellation is cooperative between plies; a
   partially analysed game is persisted and resumes where it stopped.

Quick / Standard / Deep settings differ in D1, D2, and the number of refined positions. Threads default to 1
(2 on devices with ≥ 6 cores), Hash 16–32 MB.

## Assumptions (to be confirmed by the owner)

- Bundle id `com.lironkatsif.openreview`, App Group `group.com.lironkatsif.openreview` (placeholders; change
  in one place, see docs/RELEASE_IOS.md).
- The app is distributed under GPLv3 (required by Stockfish); the full source is the corresponding source.
- Chess.com game links are resolved through the public player-archives API, which needs the player's
  username; the app asks for it once and stores it locally.
