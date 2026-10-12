# Engine integration and licensing

## What ships

| Item | Value |
|---|---|
| Engine | Stockfish **19** (official `sf_19` tag), GPL-3.0-or-later |
| Source | `packages/stockfish_ffi/ios/stockfish_ffi/Sources/stockfish_ffi/Stockfish/` — byte-identical to https://github.com/official-stockfish/Stockfish/archive/refs/tags/sf_19.tar.gz (sha256 `519b653d0d1ffb96531d982ccbe5c6a19425e8388e0e3c2f70f34b424ab32d76`), verified with `diff -r`; only `src/Makefile` is omitted |
| Modifications to Stockfish | **None.** The bridge is a separate file (`sf_bridge.cpp`) that links against the unmodified sources |
| Network | `nn-1a298aa575a0.nnue` (98,511,183 bytes, sha256 prefix matches the file name), downloaded from `https://tests.stockfishchess.org/api/nn/nn-1a298aa575a0.nnue`, shipped as the asset `app/assets/engine/nn-1a298aa575a0.nnue` (fetched by `scripts/fetch_nnue.sh`; not kept in git) and copied once into the app's support directory. Stockfish 19 has a single network (the small net was retired) |
| Build flags (iOS, release) | `-std=c++17 -DNNUE_EMBEDDING_OFF -DUSE_PTHREADS -DIS_64BIT -DUSE_POPCNT -fno-exceptions -DNDEBUG -funroll-loops -O3 -DUSE_NEON=8 -flto=full` (the same flags lichess's production `multistockfish` package uses for SF 19 on iOS) |
| Build flags (Android arm64) | as above without LTO, plus `-Wl,-z,max-page-size=16384` |
| Build flags (Linux x86-64) | x86-64-v3 baseline: `-DUSE_AVX2 -DUSE_PEXT -DUSE_SSE41 -DUSE_SSSE3 -DUSE_SSE2 -mavx2 -mbmi2 -mfma …` |
| Runtime defaults | Threads 1 (user-selectable 1/2/4), Hash 16 MB (16/32/64), `UCI_ShowWDL true`, `UCI_Chess960` set per game, `EvalFile` set to the installed network path before the first search |

## How the bridge works (`sf_bridge.cpp`)

Stockfish's `UCIEngine::loop()` reads commands with `std::getline(std::cin, …)` and prints through `std::cout`
(`sync_cout`). The bridge replaces the stream buffers of `std::cin`, `std::cout` and `std::cerr` with two in-memory
queues and runs the loop on a `std::thread`:

- `sf_start()` – install the buffers, start the engine thread (runs `Attacks::init`, `Position::init`,
  `UCIEngine(cli).loop()` exactly like `main.cpp`).
- `sf_send(cmd)` – enqueue one UCI command line.
- `sf_read_line(timeout_ms)` – block up to the timeout for the next output line (malloc'd, `sf_free`).
- `sf_join()`, `sf_is_running()`, `sf_version()`.

No pipes, no `dup2`, no fork: nothing that iOS restricts. Dart (`packages/stockfish_ffi/lib/stockfish_ffi.dart`) calls
`sf_start` once, spawns one reader isolate that loops on `sf_read_line(250)` and forwards lines through a `SendPort`,
and exposes `Stream<String> lines` + `send(String)`. The review core's `UciClient` serialises searches, parses
`info`/`bestmove`, and converts every score to White's perspective immediately.

Only one engine instance per process is supported. `dispose()` sends `quit`, waits for `quitok`, joins the thread;
`start()` can then be called again (tested).

## Verified here (Linux)

- `packages/stockfish_ffi/test/engine_smoke_test.dart` against the compiled library and the real network: UCI
  handshake, `UCI_ShowWDL` output, mate-in-1 found with `wdl 1000 0 0`, centipawn evaluation with WDL from the start
  position, `go infinite` + `stop`, dispose and restart in the same process.
- `packages/review_core/test/real_engine_test.dart`: full two-pass analysis of real games through the UCI client
  (via the Stockfish binary), including mate detection on both sides and a 50-ply game (≈1 s at depth 10/14 on this
  machine).
- The Flutter Linux app builds with the plugin compiled by Flutter's CMake integration.

## Not verified here

iOS and Android compilation (no Xcode / Android SDK on the development machine). The podspec, `Package.swift` and
Android CMake are modelled on lichess's production configuration for the same Stockfish version; see
docs/RELEASE_IOS.md for what to check on a Mac.

## Licensing obligations

Stockfish is GPLv3. Linking it into the app makes the whole app a derivative work, so:

1. **OpenReview is licensed GPL-3.0-or-later** (`LICENSE` at the repository root, also shown in-app under
   Settings → Licences).
2. **Corresponding source**: the complete source of every released build is published at the repository URL shown in
   the app (GPLv3 §6d, equivalent access through a network server). Tag each App Store build in git so that the exact
   source is retrievable.
3. `THIRD_PARTY_NOTICES.md` lists every bundled third-party component with its licence: Stockfish (GPLv3, AUTHORS
   included), incbin (public domain, unused but present in the tree), chess piece sets (cburnett GPLv2+, merida GPLv2+,
   chessnut Apache 2.0, via lichess `COPYING.md`), lichess-org/chess-openings (CC0), Flutter and pub packages (BSD/MIT,
   listed by the in-app licence page).
4. No further restrictions are imposed on users (GPLv3 §10); the App Store terms are the known grey area that the
   Stockfish team, lichess and others accept for their own App Store releases.
