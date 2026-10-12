# OpenReview

Free, unlimited chess game reviews on your phone. Share a game from Chess.com (or paste a link, PGN, or a `.pgn`
file) and get an interactive review powered by Stockfish 19 running **on the device**: move labels, evaluation bar
and graph, best alternatives, key moments, verified explanations, a guided tour of the turning points and a
"try again" mode. No account, no quota, no server.

Status: working source for iOS (first target), Android and Linux desktop. Built and tested on Linux; the iOS and
Android native layers are written and validated but still need a first compile on a Mac / with the Android SDK
(see docs/RELEASE_IOS.md and docs/SHARE_FLOW.md for exactly what remains).

## Repository layout

```
app/                        Flutter app (lib/, ios/ with the share extension, android/, linux/, test/)
packages/chess_core/        chess rules, FEN, SAN, PGN (pure Dart, perft- and Stockfish-verified)
packages/review_core/       UCI client, two-pass analysis, labels, accuracy, explanations, opening book, importers
packages/stockfish_ffi/     Flutter FFI plugin: unmodified Stockfish 19 + a small in-process bridge
docs/                       architecture, design rules, engine & licensing, classification formulas, share flow,
                            testing account, iOS release steps, research notes
```

## Development setup

Requirements: Flutter 3.47.x (Dart 3.13), CMake ≥ 3.10, Ninja, clang or gcc, GTK 3 dev headers for the Linux
target. For iOS: Xcode 16+ on macOS. For Android: Android SDK + NDK.

```
scripts/fetch_nnue.sh         # one-time: downloads the 98 MB Stockfish network into app/assets/engine
cd app
flutter pub get
flutter run -d linux          # desktop build with the real engine
flutter run -d <ios-device>   # after the signing steps in docs/RELEASE_IOS.md
```

The 98 MB NNUE network ships as an asset (`app/assets/engine/`, downloaded by `scripts/fetch_nnue.sh`, not kept in git) and is copied once into the app's support directory.

## Tests

```
cd packages/chess_core  && dart test                      # rules, FEN, SAN, PGN (perft suite included)
cd packages/review_core && dart test                      # scores, WDL model, labels, accuracy, links, analyzer
STOCKFISH_BIN=/path/to/stockfish dart test test/real_engine_test.dart     # end-to-end with a real engine
cd packages/stockfish_ffi && STOCKFISH_FFI_LIB=… STOCKFISH_NNUE=… flutter test   # native bridge smoke test
cd app && flutter test                                    # widget tests, share-intake channel tests, goldens
```

Cross-checks against Stockfish's own move generator and a 3000-game lichess corpus live in
`packages/chess_core/tool/`. See docs/TESTING.md for the full account.

## How the review works

docs/ARCHITECTURE.md (pipeline), docs/CLASSIFICATION.md (labels, accuracy, explanations, with formulas),
docs/ENGINE.md (Stockfish integration and licensing), docs/DESIGN.md (visual rules).

## Privacy

Games and reviews are stored only on the device. Importing a game *link* needs internet (Chess.com's public
player archives or Lichess's export API); analysing an imported game does not. Nothing is uploaded.

## Licence

GPL-3.0-or-later (required by Stockfish). See LICENSE and THIRD_PARTY_NOTICES.md. The complete corresponding
source for every build is this repository.
