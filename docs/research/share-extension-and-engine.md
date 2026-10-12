# Research: iOS Share Extension for Flutter and Stockfish via Dart FFI (2026-10-11)

Sub-agent research summary. [V] verified from primary source, [I] inference.

## Share extension

- Packages: `receive_sharing_intent` 1.9 (SPM only, no podspec), `share_handler` 0.0.25 (stale),
  `flutter_sharing_intent` 2.0.4 (CocoaPods). All use the same mechanism: the extension writes the payload to
  `UserDefaults(suiteName: appGroup)` and then walks the responder chain to find `UIApplication` and call
  `open(url)` on a custom scheme. [V]
- Apple's position [V]: "App extensions are not allowed to open URLs directly" (DTS, forums thread 764570);
  `NSExtensionContext.open` only works for Today extensions. No documented App Review rejection of the responder-chain
  trick was found; thousands of apps ship it. Mitigation: always persist the payload in the App Group first, so the
  main app picks it up on its next launch/foreground regardless of whether the redirect works. rreview does this.
- Memory/lifecycle [V]: extensions have much lower memory limits (~120 MB per secondary sources), must launch in well
  under one second and must call `completeRequest`. Do not embed the Flutter engine in the extension.
- UTIs [V]: no system `com.chess.pgn`; Apple's Chess.app exports `com.apple.chess.pgn` (conforms to plain text).
  IANA MIME `application/vnd.chess-pgn`; legacy `application/x-chess-pgn`. Import `com.apple.chess.pgn` with
  `UTImportedTypeDeclarations`; also accept `public.plain-text`, `public.url`, `public.file-url` and check the
  `.pgn` extension in code. `TRUEPREDICATE` activation rules are rejected by App Review.
- Flutter 3.47 supports iOS 15+ [V]; use `IPHONEOS_DEPLOYMENT_TARGET = 15.0` on both targets.
- pbxproj without Xcode [V]: the Ruby gem `xcodeproj` is pure Ruby and has `new_target(:app_extension, …)`; Python
  `pbxproj` cannot add targets. We write the pbxproj entries by hand from the receive_sharing_intent example
  structure (PBXNativeTarget productType `com.apple.product-type.app-extension`, PBXTargetDependency,
  PBXContainerItemProxy, `Embed Foundation Extensions` copy phase with `dstSubfolderSpec = 13` placed before
  "Thin Binary").

## Stockfish via FFI

- lichess's `multistockfish` 0.6.1 bundles SF 19 (GPL-3) for Android/iOS only [V]; it is the model for our iOS
  podspec/SPM flags and Android CMake flags, which are production-proven:
  - iOS: `-std=c++17 -mdynamic-no-pic -DNNUE_EMBEDDING_OFF -DUSE_PTHREADS -DIS_64BIT -DUSE_POPCNT`, Release adds
    `-fno-exceptions -DNDEBUG -funroll-loops -O3 -DUSE_NEON=8 -flto=full`; exclude `Makefile`, `main.cpp`,
    `incbin/UNLICENCE`, `universal/**`.
  - Android arm64-v8a: same defines without `-mdynamic-no-pic`; other ABIs drop `IS_64BIT/POPCNT/NEON`;
    `-Wl,-z,max-page-size=16384` for 16 KB pages.
  - LTO + `INCBIN` fails under Xcode; irrelevant with `NNUE_EMBEDDING_OFF`.
- SF 19 [V]: released 2026-09-05, single net `nn-1a298aa575a0.nnue` (98,511,183 bytes), the small net and the
  `EvalFileSmall` option are gone. With `NNUE_EMBEDDING_OFF` the engine needs
  `setoption name EvalFile value <abs path>` before any search.
- WDL [V] (`uci.cpp`): `UCI_ShowWDL` appends `wdl w d l` (per mille, side to move) to info lines. Model:
  material = P+3N+3B+5R+9Q, m = clamp(material,17,78)/58, a = poly(as, m), b = poly(bs, m),
  as = {-142.72052667, 372.35176398, -340.71073572, 415.23490212}, bs = {5.93832785, 15.61267078, -30.57816876,
  69.63866711}, win‰ = round(1000/(1+exp((a−v)/b))). Reported `cp` = round(100·v/a), i.e. 100 cp ≡ 50 % win chance
  against the model. The old constant NormalizeToPawnValue no longer exists.
- Licensing [V]: GPLv3; the app must be GPLv3 and offer Corresponding Source (§6d: equivalent access through a
  network server is fine). lichess mobile (GPL-3) and the official Stockfish app are on the App Store.
- Dart FFI [V]: blocking engine loops belong on dedicated isolates; iOS statically links podspec sources, so exported
  C symbols need `__attribute__((used, visibility("default")))` and the Runner's Strip Style set to Non-Global
  Symbols; Android loads `libstockfish_ffi.so` by name.
