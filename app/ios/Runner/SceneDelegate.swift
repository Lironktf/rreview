import Flutter
import UIKit

/// Scene delegate (declared in Info.plist). Forwards URL opens and
/// foreground transitions to `ShareIntakePlugin` after letting Flutter do its
/// own plugin forwarding. Flutter's built-in deep linking is disabled in
/// Info.plist (`FlutterDeepLinkingEnabled` = false) because we handle
/// `openreview://` and `.pgn` file URLs here.
class SceneDelegate: FlutterSceneDelegate {

  // Cold start via URL (openreview://import or a .pgn "Open in").
  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
                      options connectionOptions: UIScene.ConnectionOptions) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    ShareIntakePlugin.shared.handle(urlContexts: connectionOptions.urlContexts)
  }

  // Warm start via URL.
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    ShareIntakePlugin.shared.handle(urlContexts: URLContexts)
  }

  // Fallback when the extension could not open the app: pick up whatever it
  // left in the App Group the next time we come to the foreground.
  override func sceneWillEnterForeground(_ scene: UIScene) {
    super.sceneWillEnterForeground(scene)
    ShareIntakePlugin.shared.drainSharedInbox()
  }
}
