# Share intake flow (iOS + Android)

How a Chess.com link, a PGN text or a `.pgn` file gets from another app into
rreview. Written 2026-10-11 against Flutter 3.47.7 (iOS 15+ minimum,
UIScene-based template, Swift Package Manager by default).

## Dart API

`app/lib/platform/share_intake.dart` (pure Dart + platform channels, no packages):

```dart
enum SharedKind { text, url, file }

class SharedItem {
  final String id;          // native: lowercase UUID; Dart: time + random
  final SharedKind kind;
  final String value;       // text, URL string, or absolute file path inside the app's storage
  final String? fileName;   // for files
  final DateTime receivedAt;
  final String source;      // 'ios-share-extension' | 'ios-open-in' | 'android-intent' | 'manual'
  Map<String, dynamic> toJson();  factory SharedItem.fromJson(Map<String, dynamic>);
}

abstract class ShareIntake {
  Future<List<SharedItem>> takePending();   // returns AND clears items received while not running
  Stream<SharedItem> get incoming;          // items arriving while running (broadcast)
  static ShareIntake forPlatform();         // iOS/Android: ChannelShareIntake; else NoopShareIntake
}
```

Channels: `MethodChannel('rreview/share_intake')` with method `takePending`
(returns `List<Map>`), and `EventChannel('rreview/share_intake/events')`.
Wire format of one item: `{id, kind, value, fileName?, receivedAt (ISO 8601 UTC), source}`.

Recommended usage in the app shell: call `takePending()` on startup and on every
`AppLifecycleState.resumed`, and subscribe to `incoming` once. Each item is
delivered exactly once by one of the two paths (the native side removes an item
from its queue when it emits it).

## iOS

### Files

| File | Role |
|---|---|
| `app/ios/ShareExtension/ShareViewController.swift` | Share-extension principal class (no storyboard, `UIViewController` subclass) |
| `app/ios/ShareExtension/Info.plist` | `NSExtensionActivationRule` dict (WebURL max 1, Text, File max 1), `CFBundleDisplayName` "rreview" |
| `app/ios/ShareExtension/ShareExtension.entitlements` | App Group `group.com.lironkatsif.rreview` |
| `app/ios/Shared/ShareInbox.swift` | Constants + `pending.json` append/drain helpers; compiled into BOTH targets |
| `app/ios/Runner/ShareIntakePlugin.swift` | Method/Event channels, drains the App Group, imports "Open in" files |
| `app/ios/Runner/AppDelegate.swift` | Registers plugins and attaches `ShareIntakePlugin` in `didInitializeImplicitFlutterEngine` |
| `app/ios/Runner/SceneDelegate.swift` | Forwards `willConnectTo` / `openURLContexts` / `sceneWillEnterForeground` to the plugin |
| `app/ios/Runner/Info.plist` | `CFBundleURLTypes` (`rreview`), `UTImportedTypeDeclarations` (`com.apple.chess.pgn`), `CFBundleDocumentTypes`, `LSSupportsOpeningDocumentsInPlace=false`, `UISupportsDocumentBrowser=false`, `FlutterDeepLinkingEnabled=false` |
| `app/ios/Runner/Runner.entitlements` | Same App Group |
| `app/ios/Runner.xcodeproj/project.pbxproj` | New `ShareExtension` native target, embed phase, dependency, entitlements (edited by hand) |
| `app/ios/Podfile` | Created from the Flutter template with `platform :ios, '15.0'` and a nested `ShareExtension` target |

### Share extension (cold or warm start)

1. The user picks "rreview" in a share sheet. iOS launches `ShareExtension.appex`
   (bundle id `com.lironkatsif.rreview.ShareExtension`) with
   `ShareViewController` as the principal class; it shows a spinner for a moment.
2. `viewDidAppear` walks `extensionContext.inputItems[*].attachments` and, per
   provider, accepts in this order: `public.file-url` -> `public.url` ->
   `public.text` -> any UTI conforming to `public.data` (loaded with
   `loadFileRepresentation`, which is how Files hands over a `.pgn`).
   * Web URL -> `kind: url`.
   * Text -> `kind: text`, except when the trimmed text is exactly one http(s)
     URL (Chess.com shares links as text) -> `kind: url`.
   * File -> accepted only if the extension is `.pgn` or the UTI/extension
     conforms to text, and size <= 5 MB; copied into the App Group container at
     `shared/inbox/<uuid>-<name>`; `kind: file`, `value` = that path.
3. Items are appended to `pending.json` (a JSON array) in the App Group
   container (`FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`),
   under an `NSFileCoordinator` because two processes touch the file.
4. The extension then walks the responder chain (`self.next ...`) to the host
   `UIApplication` and opens `rreview://import`: on iOS 18+ through the IMP of
   `openURL:options:completionHandler:`, on older iOS through the `openURL:`
   selector. Apple's position is that extensions may not open URLs (it works in
   practice and ships in thousands of apps); if it does nothing, step 6 still
   delivers the payload.
5. `extensionContext.completeRequest` is called (also after an 8 s safety
   timeout if a provider never calls back).
6. In the Runner, `SceneDelegate` receives the URL in `scene(_:openURLContexts:)`
   (warm) or `scene(_:willConnectTo:options:)` (cold) and calls
   `ShareIntakePlugin.handle(url:)`, which drains `pending.json`, moves inbox
   files into `Application Support/imports/` (rewriting `value`), and either
   pushes the items on the EventChannel (Dart listener attached) or queues them
   for `takePending`. `sceneWillEnterForeground` drains the inbox too, so the
   payload also arrives when the URL hand-off failed and the user opens the app
   manually.

### "Open in rreview" for a `.pgn` file

`UTImportedTypeDeclarations` registers `com.apple.chess.pgn` (conforms to
`public.plain-text`, extension `pgn`, MIME `application/vnd.chess-pgn` and
`application/x-chess-pgn`) and `CFBundleDocumentTypes` declares the app as a
viewer. Because `LSSupportsOpeningDocumentsInPlace` is false, iOS copies the
file into `Documents/Inbox/` and opens the app with a file URL;
`ShareIntakePlugin.importOpenedFile` copies it to `Application Support/imports/`,
deletes the Inbox copy and reports `kind: file`, `source: ios-open-in`.

### Xcode project changes (by hand, validated structurally)

New objects in `project.pbxproj` (IDs prefixed `5E7A`): `PBXNativeTarget
ShareExtension` (`com.apple.product-type.app-extension`), its Sources /
Frameworks / Resources phases, `PBXFileReference ShareExtension.appex`, groups
`ShareExtension` and `Shared`, a Debug/Release/Profile `XCConfigurationList`
(`INFOPLIST_FILE`, `CODE_SIGN_ENTITLEMENTS`, `PRODUCT_BUNDLE_IDENTIFIER =
com.lironkatsif.rreview.ShareExtension`, `SKIP_INSTALL=YES`,
`IPHONEOS_DEPLOYMENT_TARGET=15.0`, `SWIFT_VERSION=5.0`,
`TARGETED_DEVICE_FAMILY="1,2"`, `GENERATE_INFOPLIST_FILE=NO`,
`CURRENT_PROJECT_VERSION=$(FLUTTER_BUILD_NUMBER)`,
`MARKETING_VERSION=$(FLUTTER_BUILD_NAME)`, `LD_RUNPATH_SEARCH_PATHS` with
`@executable_path/Frameworks` and `@executable_path/../../Frameworks`), a
`PBXContainerItemProxy` + `PBXTargetDependency` so Runner builds the extension
first, and an "Embed Foundation Extensions" `PBXCopyFilesBuildPhase`
(`dstSubfolderSpec = 13`, `RemoveHeadersOnCopy`) on Runner placed after "Embed
Frameworks" and before "Thin Binary". The extension configurations use
`Flutter/Debug.xcconfig` / `Flutter/Release.xcconfig` as base so
`$(FLUTTER_BUILD_NAME)` / `$(FLUTTER_BUILD_NUMBER)` resolve and the extension's
version matches the app (App Store validation requires that). Runner's three
configurations gained `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements`.

## Android

### Files

| File | Role |
|---|---|
| `app/android/app/src/main/AndroidManifest.xml` | `launchMode="singleTask"`, intent filters |
| `app/android/app/src/main/kotlin/com/lironkatsif/rreview/MainActivity.kt` | Intent -> items, SharedPreferences queue, Method/Event channels |

### Flow

* Intent filters on `MainActivity`: `ACTION_SEND text/plain`; `ACTION_SEND` for
  `application/x-chess-pgn`, `application/vnd.chess-pgn`, `text/*`,
  `application/octet-stream`; `ACTION_VIEW` for `content`/`file` URIs with the
  PGN MIME types or a path ending in `.pgn`; `ACTION_VIEW` for the `rreview`
  scheme.
* `onCreate` (first creation only; `savedInstanceState == null`) and
  `onNewIntent` convert the intent: `EXTRA_TEXT` -> `text`, or `url` when it is
  exactly one http(s) URL; `EXTRA_STREAM` / VIEW data -> the content is copied
  into `filesDir/imports/<uuid>-<name>` (max 5 MB, only when the display name
  ends in `.pgn` or the MIME is `text/*` or a PGN type) -> `file`.
  Relaunches from the recents screen (`FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY`) are
  ignored so a share is not processed twice.
* If a Dart listener is attached, items are emitted on the EventChannel;
  otherwise they are appended to a JSON array in SharedPreferences
  (`rreview_share_intake` / `pending`) until `takePending` is called (or
  until a listener attaches, which flushes the queue).

## What is verified here, and what is not

Verified on this Linux machine:

* `flutter pub get` and `flutter analyze` pass; `flutter test` covers
  `SharedItem` JSON, the no-op implementation, and `ChannelShareIntake` against
  mocked method/event channels.
* `project.pbxproj` was re-parsed with a custom old-style-plist parser: braces
  balance, every referenced object ID exists, no orphan objects, the embed
  phase precedes "Thin Binary", and every new file reference points at a file
  that exists on disk. All `Info.plist` / `.entitlements` files parse with
  `plistlib`.

NOT verified (no Xcode / Android SDK here):

* The Swift and Kotlin sources have never been compiled. They were
  self-reviewed against the Flutter 3.47 engine headers
  (`FlutterSceneDelegate`, `FlutterImplicitEngineBridge`, `FlutterStreamHandler`)
  and Flutter's own UIScene integration tests, but expect to fix a typo or two
  on first build.
* Xcode's acceptance of the hand-written target, code signing, App Group
  provisioning, and the real share-sheet behaviour.
* Whether the responder-chain `rreview://import` hand-off works on the
  installed iOS version (the fallback path does not depend on it).

## Steps for the owner on a Mac

1. `cd app && flutter pub get`, then open `app/ios/Runner.xcworkspace` in Xcode.
   (If Xcode complains about the project file, the hand-edit is at fault: tell
   me the exact error.) If you do not want CocoaPods involved at all, delete
   `app/ios/Podfile`; keep it if a CocoaPods-only dependency is planned.
2. Select the **Runner** target -> Signing & Capabilities: set your Team; add the
   **App Groups** capability and tick `group.com.lironkatsif.rreview` (create
   it if Xcode offers). Repeat for the **ShareExtension** target with the same
   Team and the same group. Both `.entitlements` files already list the group;
   Xcode should pick them up rather than create new ones.
3. Runner -> Build Phases: confirm the order ... "Embed Frameworks",
   "Embed Foundation Extensions" (contains `ShareExtension.appex`), "Thin Binary".
   Confirm the ShareExtension target's General tab shows deployment target 15.0
   and bundle id `com.lironkatsif.rreview.ShareExtension`.
4. Build and run the Runner scheme on a physical device (share extensions behave
   differently in the simulator). If Xcode asks to update the project format or
   recommended settings, accept.
5. Test matrix:
   1. Safari: open a Chess.com game page, Share -> rreview. Expect a
      `url` item (`https://www.chess.com/game/live/...`).
   2. Notes: paste a PGN, select all, Share -> rreview. Expect a `text` item.
      Also share a bare link from Notes/Messages: expect `url`.
   3. Files: long-press a `.pgn` -> Share -> rreview. Expect a `file` item
      whose `value` is under `Application Support/imports/`. Then also try
      "Open in rreview" from the Files preview (document-type path,
      `source: ios-open-in`).
   4. Cold start vs warm start: force-quit the app and share (the item must
      arrive from `takePending()` at launch, or from `incoming` if the URL
      hand-off opened the app); then share again while the app is in the
      background (expect `incoming` on `openURLContexts` or on foreground).
   5. Duplicate share: share the same link twice; expect two items with
      different ids and no item delivered twice (check that
      `pending.json` is gone from the App Group container afterwards).
6. Android: `flutter run`, then share a link from Chrome, PGN text from Keep,
   and a `.pgn` from the Files app; repeat with the app killed vs. in the
   background. Also reopen the app from Recents after a share and confirm the
   item is not delivered again.

## Policy caveat

Apple's documented stance is that app extensions may not open URLs
(`NSExtensionContext.open` is for Today widgets only). The responder-chain
trick used in `ShareViewController.openHostApp()` is widely shipped and no
rejection for it is documented, but it is unsupported and could stop working in
a future iOS. rreview therefore never depends on it: every payload is
persisted to the App Group first and the app drains it on the next launch or
foreground. If App Review ever objects, remove `openHostApp()`; everything else
keeps working (the user just has to open the app themselves).
