import UIKit
import UniformTypeIdentifiers

/// Principal class of the OpenReview share extension (no storyboard; see
/// `NSExtensionPrincipalClass` in Info.plist).
///
/// Flow:
///  1. Collect every attachment of every input item: web URLs, plain text,
///     and `.pgn` / text files (copied into the App Group inbox, max 5 MB).
///  2. Append them to `pending.json` in the App Group container.
///  3. Ask the host app to open `openreview://import` through the responder
///     chain (not officially supported by Apple; see docs/SHARE_FLOW.md).
///  4. Complete the request. If step 3 does nothing, the main app still
///     drains `pending.json` on its next launch / foreground.
final class ShareViewController: UIViewController {
  private static let timeoutSeconds: TimeInterval = 8

  private var didStart = false
  private var didFinish = false
  private let group = DispatchGroup()
  private let lock = NSLock()
  private var collected: [[String: Any]] = []

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.92)

    let spinner = UIActivityIndicatorView(style: .large)
    spinner.translatesAutoresizingMaskIntoConstraints = false
    spinner.startAnimating()

    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.text = "Sending to OpenReview…"
    label.font = UIFont.preferredFont(forTextStyle: .body)
    label.textColor = .secondaryLabel
    label.textAlignment = .center

    view.addSubview(spinner)
    view.addSubview(label)
    NSLayoutConstraint.activate([
      spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -16),
      label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),
      label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
      label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
    ])
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard !didStart else { return }
    didStart = true
    processAttachments()
  }

  // MARK: - Collecting attachments

  private func processAttachments() {
    let inputItems = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
    let providers = inputItems.flatMap { $0.attachments ?? [] }
    guard !providers.isEmpty else {
      finish()
      return
    }
    for provider in providers {
      load(provider)
    }
    group.notify(queue: .main) { [weak self] in
      self?.finish()
    }
    // Safety net: never leave the host app waiting on a stuck provider.
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeoutSeconds) { [weak self] in
      self?.finish()
    }
  }

  private func load(_ provider: NSItemProvider) {
    group.enter()
    let done: ([String: Any]?) -> Void = { [weak self] item in
      guard let self = self else { return }
      if let item = item {
        self.lock.lock()
        self.collected.append(item)
        self.lock.unlock()
      }
      self.group.leave()
    }

    let fileURLType = UTType.fileURL.identifier
    let urlType = UTType.url.identifier
    let textType = UTType.text.identifier

    if provider.hasItemConformingToTypeIdentifier(fileURLType) {
      provider.loadItem(forTypeIdentifier: fileURLType, options: nil) { [weak self] data, _ in
        guard let self = self, let url = Self.url(from: data) else { return done(nil) }
        done(self.fileItem(from: url, typeIdentifier: nil))
      }
    } else if provider.hasItemConformingToTypeIdentifier(urlType) {
      provider.loadItem(forTypeIdentifier: urlType, options: nil) { [weak self] data, _ in
        guard let self = self, let url = Self.url(from: data) else { return done(nil) }
        if url.isFileURL {
          done(self.fileItem(from: url, typeIdentifier: nil))
        } else {
          done(ShareInbox.makeItem(kind: "url", value: url.absoluteString, fileName: nil,
                                   source: ShareInbox.sourceShareExtension))
        }
      }
    } else if provider.hasItemConformingToTypeIdentifier(textType) {
      provider.loadItem(forTypeIdentifier: textType, options: nil) { data, _ in
        guard let text = Self.text(from: data) else { return done(nil) }
        done(Self.textItem(text))
      }
    } else if let dataType = provider.registeredTypeIdentifiers.first(where: { identifier in
      UTType(identifier)?.conforms(to: .data) ?? false
    }) {
      // A file shared with its own UTI (e.g. com.apple.chess.pgn from Files).
      // The temporary URL is only valid inside the completion handler, so copy there.
      provider.loadFileRepresentation(forTypeIdentifier: dataType) { [weak self] url, _ in
        guard let self = self, let url = url else { return done(nil) }
        done(self.fileItem(from: url, typeIdentifier: dataType))
      }
    } else {
      done(nil)
    }
  }

  private static func url(from data: NSSecureCoding?) -> URL? {
    if let url = data as? URL { return url }
    if let string = data as? String { return URL(string: string) }
    if let raw = data as? Data, let string = String(data: raw, encoding: .utf8) {
      return URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return nil
  }

  private static func text(from data: NSSecureCoding?) -> String? {
    if let string = data as? String { return string }
    if let attributed = data as? NSAttributedString { return attributed.string }
    if let raw = data as? Data { return String(data: raw, encoding: .utf8) }
    if let url = data as? URL { return url.absoluteString }
    return nil
  }

  /// Plain text that is exactly one http(s) URL is reported as `url`
  /// (Chess.com shares game links as text); everything else is `text`.
  private static func textItem(_ text: String) -> [String: Any]? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let hasWhitespace = trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
    if !hasWhitespace, let url = URL(string: trimmed),
       let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
       url.host != nil {
      return ShareInbox.makeItem(kind: "url", value: url.absoluteString, fileName: nil,
                                 source: ShareInbox.sourceShareExtension)
    }
    return ShareInbox.makeItem(kind: "text", value: trimmed, fileName: nil,
                               source: ShareInbox.sourceShareExtension)
  }

  /// Copies an acceptable file into the App Group inbox and describes it.
  private func fileItem(from source: URL, typeIdentifier: String?) -> [String: Any]? {
    let fileName = source.lastPathComponent
    guard ShareInbox.isAcceptableFile(name: fileName, typeIdentifier: typeIdentifier) else {
      return nil
    }
    let scoped = source.startAccessingSecurityScopedResource()
    defer { if scoped { source.stopAccessingSecurityScopedResource() } }

    let fileManager = FileManager.default
    guard let attributes = try? fileManager.attributesOfItem(atPath: source.path),
          let size = attributes[.size] as? NSNumber,
          size.intValue <= ShareInbox.maxFileBytes,
          let inbox = ShareInbox.inboxDirectoryURL else {
      return nil
    }
    try? fileManager.createDirectory(at: inbox, withIntermediateDirectories: true, attributes: nil)

    let id = ShareInbox.newId()
    let destination = inbox.appendingPathComponent("\(id)-\(fileName)", isDirectory: false)
    do {
      try fileManager.copyItem(at: source, to: destination)
    } catch {
      return nil
    }
    return ShareInbox.makeItem(id: id, kind: "file", value: destination.path, fileName: fileName,
                               source: ShareInbox.sourceShareExtension)
  }

  // MARK: - Persist, hand off, complete

  private func finish() {
    guard !didFinish else { return }
    didFinish = true

    lock.lock()
    let items = collected
    lock.unlock()

    if !items.isEmpty, ShareInbox.append(items) {
      openHostApp()
    }
    extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
  }

  /// Walks the responder chain to the host `UIApplication` and asks it to open
  /// `openreview://import`. Apple does not officially allow extensions to open
  /// URLs; this is best-effort and the app drains `pending.json` anyway.
  private func openHostApp() {
    guard let url = URL(string: ShareInbox.importURLString) else { return }
    var responder: UIResponder? = self
    while let current = responder {
      if let application = current as? UIApplication {
        if #available(iOS 18.0, *) {
          Self.openViaModernSelector(application, url: url)
        } else {
          let legacySelector = sel_registerName("openURL:")
          if application.responds(to: legacySelector) {
            _ = application.perform(legacySelector, with: url)
          }
        }
        return
      }
      responder = current.next
    }
  }

  /// Calls `-[UIApplication openURL:options:completionHandler:]` through its
  /// IMP so the call compiles even with "Require Only App-Extension-Safe API".
  private static func openViaModernSelector(_ application: UIApplication, url: URL) {
    typealias OpenURLFunction = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
    let selector = sel_registerName("openURL:options:completionHandler:")
    guard application.responds(to: selector),
          let method = class_getInstanceMethod(type(of: application), selector) else { return }
    let function = unsafeBitCast(method_getImplementation(method), to: OpenURLFunction.self)
    function(application, selector, url as NSURL, NSDictionary(), nil)
  }
}
