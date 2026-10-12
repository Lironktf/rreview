import Flutter
import UIKit

/// Runner-side half of the share intake: exposes
///   MethodChannel "openreview/share_intake"          (takePending)
///   EventChannel  "openreview/share_intake/events"   (incoming items)
/// and receives URLs from `SceneDelegate`.
///
/// All state is touched on the main thread only (scene callbacks and
/// platform-channel handlers both run there).
final class ShareIntakePlugin: NSObject, FlutterStreamHandler {
  static let shared = ShareIntakePlugin()
  static let methodChannelName = "openreview/share_intake"
  static let eventChannelName = "openreview/share_intake/events"
  static let importsDirectoryName = "imports"

  private var methodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?
  private var eventSink: FlutterEventSink?
  /// Items received while no Dart listener was attached; drained by takePending
  /// or flushed when a listener attaches.
  private var queued: [[String: Any]] = []

  private override init() {
    super.init()
  }

  // MARK: - Channel wiring

  func attach(messenger: FlutterBinaryMessenger) {
    let methods = FlutterMethodChannel(name: Self.methodChannelName, binaryMessenger: messenger)
    methods.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      switch call.method {
      case "takePending":
        result(self.takePending())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    let events = FlutterEventChannel(name: Self.eventChannelName, binaryMessenger: messenger)
    events.setStreamHandler(self)
    methodChannel = methods
    eventChannel = events
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    let backlog = queued
    queued.removeAll()
    for item in backlog {
      events(item)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  // MARK: - Entry points (called from SceneDelegate)

  func handle(urlContexts: Set<UIOpenURLContext>) {
    for context in urlContexts {
      handle(url: context.url)
    }
  }

  func handle(url: URL) {
    if url.isFileURL {
      if let item = importOpenedFile(url) {
        deliver([item])
      }
    } else if url.scheme?.lowercased() == ShareInbox.urlScheme {
      // openreview://import (from the share extension): payload is in the App Group.
      drainSharedInbox()
    }
  }

  /// Moves whatever the extension left in the App Group into the app and
  /// delivers it. Safe to call often (foreground, URL, takePending).
  func drainSharedInbox() {
    let items = ShareInbox.drain().compactMap(relocate)
    if !items.isEmpty {
      deliver(items)
    }
  }

  // MARK: - Internals

  private func takePending() -> [[String: Any]] {
    var items = ShareInbox.drain().compactMap(relocate)
    items.append(contentsOf: queued)
    queued.removeAll()
    items.sort { lhs, rhs in
      (lhs["receivedAt"] as? String ?? "") < (rhs["receivedAt"] as? String ?? "")
    }
    return items
  }

  private func deliver(_ items: [[String: Any]]) {
    let work = {
      if let sink = self.eventSink {
        for item in items {
          sink(item)
        }
      } else {
        self.queued.append(contentsOf: items)
      }
    }
    if Thread.isMainThread {
      work()
    } else {
      DispatchQueue.main.async(execute: work)
    }
  }

  private var importsDirectoryURL: URL? {
    guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                              in: .userDomainMask).first else { return nil }
    let directory = base.appendingPathComponent(Self.importsDirectoryName, isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                              attributes: nil)
    } catch {
      return nil
    }
    return directory
  }

  /// For `file` items written by the extension: move the file from the App
  /// Group inbox into Application Support/imports and rewrite `value`.
  /// Returns nil when the file no longer exists.
  private func relocate(_ item: [String: Any]) -> [String: Any]? {
    guard (item["kind"] as? String) == "file", let path = item["value"] as? String else {
      return item
    }
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: path) else { return nil }
    let source = URL(fileURLWithPath: path)
    guard let imports = importsDirectoryURL else { return item }
    let destination = imports.appendingPathComponent(source.lastPathComponent, isDirectory: false)
    do {
      if fileManager.fileExists(atPath: destination.path) {
        try fileManager.removeItem(at: destination)
      }
      try fileManager.moveItem(at: source, to: destination)
    } catch {
      return item
    }
    var moved = item
    moved["value"] = destination.path
    return moved
  }

  /// "Open in OpenReview" for a .pgn (or text) file. With
  /// LSSupportsOpeningDocumentsInPlace = false the system hands us a copy in
  /// Documents/Inbox; we copy it into imports/ and remove the Inbox copy.
  private func importOpenedFile(_ url: URL) -> [String: Any]? {
    let fileName = url.lastPathComponent
    guard ShareInbox.isAcceptableFile(name: fileName, typeIdentifier: nil) else { return nil }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }

    let fileManager = FileManager.default
    guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
          let size = attributes[.size] as? NSNumber,
          size.intValue <= ShareInbox.maxFileBytes,
          let imports = importsDirectoryURL else {
      return nil
    }
    let id = ShareInbox.newId()
    let destination = imports.appendingPathComponent("\(id)-\(fileName)", isDirectory: false)
    do {
      try fileManager.copyItem(at: url, to: destination)
    } catch {
      return nil
    }
    if url.path.contains("/Documents/Inbox/") {
      try? fileManager.removeItem(at: url)
    }
    return ShareInbox.makeItem(id: id, kind: "file", value: destination.path, fileName: fileName,
                               source: ShareInbox.sourceOpenIn)
  }
}
