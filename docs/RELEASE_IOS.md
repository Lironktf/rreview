# Building, signing and shipping the iOS app

The development machine for this project runs Linux, so everything below the "Verified on Linux" line has **not**
been executed. The iOS project files were written by hand against Flutter 3.47's generated Runner project and the
verified structure of lichess's production Stockfish plugin; expect small first-build fixes, not redesign.

## Verified on Linux

- `flutter analyze` clean for the app and both Dart packages; `flutter build linux --release` succeeds with the
  Stockfish FFI plugin compiled by Flutter's CMake integration.
- Dart test suites pass (chess rules, PGN, review core with a scripted engine and with real Stockfish, widget tests).
- The pbxproj was parsed and validated structurally (all referenced ids exist, no orphans, embed phase ordering).

## Prerequisites on the Mac

- Xcode 16 or newer, CocoaPods (`sudo gem install cocoapods`) **or** rely on Flutter's Swift Package Manager
  integration (`flutter config --enable-swift-package-manager`, on by default in 3.47). The plugin ships both a podspec
  and a `Package.swift`. If you want SPM only, delete `app/ios/Podfile`.
- Flutter 3.47.x: `flutter doctor` must show Xcode and the iOS toolchain green.
- An Apple Developer account. Bundle identifiers used: `com.lironkatsif.openreview` (Runner) and
  `com.lironkatsif.openreview.ShareExtension`. App Group: `group.com.lironkatsif.openreview`. Change them in
  `app/ios/Runner.xcodeproj/project.pbxproj`, both `.entitlements` files and `app/ios/Shared/ShareInbox.swift` if you
  need different ones.

## Steps

1. `cd app && flutter pub get && flutter precache --ios`.
2. `open ios/Runner.xcworkspace` (after `pod install` in `ios/`, or `Runner.xcodeproj` for SPM).
3. Signing & Capabilities, **Runner** target: set your Team; add the **App Groups** capability and tick
   `group.com.lironkatsif.openreview` (Xcode registers it with the developer portal).
4. Same for the **ShareExtension** target (Team + App Groups with the same group).
5. Build Phases of Runner: confirm "Embed Foundation Extensions" contains `ShareExtension.appex` and sits **before**
   "Thin Binary". Confirm the Runner's "Strip Style" is *Non-Global Symbols* (Build Settings) so the `sf_*` symbols
   survive release stripping (the plugin also pins them with `__attribute__((used))`).
6. `flutter run -d <device>` for a debug run; `flutter build ipa` for distribution. The first compile of Stockfish
   takes a few minutes (LTO in Release).
7. First-launch check on the device: Settings → Engine should read "Ready · Stockfish 19 · NNUE 1a298aa575a0" after the
   98 MB network copies out of the bundle (progress shown in the library banner).

## Device test plan (see docs/SHARE_FLOW.md for the share matrix)

1. Import by pasting `https://lichess.org/tkJnElwm` → review opens, analysis runs, badges appear progressively.
2. Import a Chess.com link without a stored username → the sheet asks for one, saves it, retries, finds the game.
3. Share from the Chess.com app: Options → Share Game (link) and Game Analysis → Share (PGN text): both must open
   OpenReview with the game imported. Cold start and warm start. Share the same game twice → "already in your library".
4. Share a `.pgn` file from Files; open a `.pgn` attachment from Mail with "Open in OpenReview".
5. Kill the app mid-analysis; relaunch → the review resumes where it stopped.
6. Airplane mode: paste PGN → analysis works offline; paste a link → clear network error with the PGN fallback.
7. Deep preset on a 100-move game: watch memory (Hash 16 MB ⇒ engine stays well under 150 MB) and thermals.
8. Accessibility: VoiceOver reads move list cells ("23. Nf3, Blunder"), eval bar, board; Reduce Motion disables slides.

## App Store notes

- The app is GPL-3.0-or-later (required by Stockfish). Publish the exact source for each build and keep the
  "Licences and source code" screen pointing at it.
- Privacy nutrition label: no data collected; network used only for user-initiated game imports.
- The share extension uses the common responder-chain hand-off to open the host app, which Apple documents as
  unsupported; the payload is persisted first, so the import still happens on the next launch if the hand-off is
  blocked. If App Review objects, remove `openHostApp()` in `ShareViewController.swift` and keep the persisted path.

## Android (not built here)

`flutter build apk --release` on a machine with the Android SDK/NDK; the plugin's CMake builds Stockfish for arm64-v8a
with NEON and 16 KB page alignment. The manifest already declares the share intents.
