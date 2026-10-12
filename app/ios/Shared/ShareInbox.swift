import Foundation
import UniformTypeIdentifiers

/// Constants and helpers for the App Group "inbox" that the ShareExtension
/// writes and the Runner app drains. This file is compiled into BOTH targets
/// (Runner and ShareExtension), so it must only depend on system frameworks
/// (Foundation, UniformTypeIdentifiers), never on Flutter.
///
/// Layout inside the App Group container:
///   pending.json        JSON array of items (see `makeItem`)
///   shared/inbox/<id>-<fileName>   files copied by the extension
enum ShareInbox {
  static let appGroupId = "group.com.lironkatsif.openreview"
  static let urlScheme = "openreview"
  static let importURLString = "openreview://import"
  static let pendingFileName = "pending.json"
  static let inboxDirectoryName = "shared/inbox"
  /// Files larger than this are refused (PGN files are tiny).
  static let maxFileBytes = 5 * 1024 * 1024

  static let sourceShareExtension = "ios-share-extension"
  static let sourceOpenIn = "ios-open-in"

  static var containerURL: URL? {
    return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
  }

  static var pendingFileURL: URL? {
    return containerURL?.appendingPathComponent(pendingFileName, isDirectory: false)
  }

  static var inboxDirectoryURL: URL? {
    return containerURL?.appendingPathComponent(inboxDirectoryName, isDirectory: true)
  }

  /// Builds one item dictionary in the wire format shared with Dart
  /// (`SharedItem.fromJson`).
  static func makeItem(id: String = newId(), kind: String, value: String,
                       fileName: String?, source: String) -> [String: Any] {
    var item: [String: Any] = [
      "id": id,
      "kind": kind,
      "value": value,
      "receivedAt": iso8601Now(),
      "source": source,
    ]
    if let fileName = fileName, !fileName.isEmpty {
      item["fileName"] = fileName
    }
    return item
  }

  static func newId() -> String {
    return UUID().uuidString.lowercased()
  }

  static func iso8601Now() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
  }

  /// True when a file with this name / type hint may be imported
  /// (`.pgn` extension, or a UTI/extension that conforms to text).
  static func isAcceptableFile(name: String, typeIdentifier: String?) -> Bool {
    let ext = (name as NSString).pathExtension.lowercased()
    if ext == "pgn" { return true }
    if let typeIdentifier = typeIdentifier, typeIdentifierIsText(typeIdentifier) { return true }
    if !ext.isEmpty, let utType = UTType(filenameExtension: ext), utType.conforms(to: .text) {
      return true
    }
    return false
  }

  static func typeIdentifierIsText(_ identifier: String) -> Bool {
    guard let utType = UTType(identifier) else { return false }
    return utType.conforms(to: .text)
  }

  /// Appends `items` to pending.json, creating the file when missing.
  /// Uses NSFileCoordinator because the extension and the app are separate
  /// processes writing the same App Group file.
  @discardableResult
  static func append(_ items: [[String: Any]]) -> Bool {
    guard !items.isEmpty, let url = pendingFileURL else { return false }
    var ok = false
    var coordinationError: NSError?
    NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging,
                                   error: &coordinationError) { writeURL in
      var existing = readItems(at: writeURL)
      existing.append(contentsOf: items)
      guard JSONSerialization.isValidJSONObject(existing),
            let data = try? JSONSerialization.data(withJSONObject: existing, options: []) else {
        return
      }
      do {
        try data.write(to: writeURL, options: .atomic)
        ok = true
      } catch {
        ok = false
      }
    }
    return ok && coordinationError == nil
  }

  /// Reads AND deletes pending.json. Returns the items it contained
  /// (empty when the file is missing or unreadable; an unreadable file is
  /// deleted as well so it cannot block future shares).
  static func drain() -> [[String: Any]] {
    guard let url = pendingFileURL else { return [] }
    var items: [[String: Any]] = []
    var coordinationError: NSError?
    NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting,
                                   error: &coordinationError) { writeURL in
      guard FileManager.default.fileExists(atPath: writeURL.path) else { return }
      items = readItems(at: writeURL)
      try? FileManager.default.removeItem(at: writeURL)
    }
    return items
  }

  private static func readItems(at url: URL) -> [[String: Any]] {
    guard let data = try? Data(contentsOf: url),
          let parsed = try? JSONSerialization.jsonObject(with: data, options: []),
          let array = parsed as? [[String: Any]] else {
      return []
    }
    return array
  }
}
