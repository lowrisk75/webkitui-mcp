import AppKit
import WebKit

private func controlText(_ key: String) -> String {
  Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

/// Exactly one cancellable destination choice. Selecting a folder is not approval
/// to dispatch, nor evidence that WebKit has finished writing the file.
@MainActor
final class NativeDownloadDestinationPresenter {
  private var panel: NSSavePanel?
  private weak var parent: NSWindow?
  private var continuation: CheckedContinuation<URL?, Never>?
  private var monitor: Task<Void, Never>?

  func choose(filename: String, parent: NSWindow, isCurrent: @escaping @MainActor () -> Bool) async
    -> URL?
  {
    guard panel == nil, parent.isVisible, parent.attachedSheet == nil, isCurrent() else {
      return nil
    }
    let panel = NSSavePanel()
    panel.title = controlText("Save Browser Download")
    panel.prompt = controlText("Save")
    panel.message = controlText(
      "Choose a folder, then click Save. Download completion will be verified separately.")
    panel.nameFieldStringValue = filename
    panel.canCreateDirectories = true
    self.panel = panel
    self.parent = parent
    return await withCheckedContinuation { continuation in
      self.continuation = continuation
      monitor = Task { @MainActor [weak self, weak parent] in
        while !Task.isCancelled {
          do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
          guard let self else { return }
          if parent?.isVisible != true || !isCurrent() {
            self.cancel()
            return
          }
        }
      }
      panel.beginSheetModal(for: parent) { [weak self, weak panel] response in
        guard let self, self.panel === panel else { return }
        let destination = response == .OK && isCurrent() && parent.isVisible ? panel?.url : nil
        self.finish(destination)
      }
    }
  }

  func cancel() {
    guard let panel else { return }
    if let parent, panel.sheetParent === parent {
      parent.endSheet(panel, returnCode: .cancel)
    } else {
      panel.cancel(nil)
    }
    finish(nil)
  }

  private func finish(_ destination: URL?) {
    guard let continuation else { return }
    self.continuation = nil
    monitor?.cancel()
    monitor = nil
    panel?.orderOut(nil)
    panel = nil
    parent = nil
    continuation.resume(returning: destination)
  }
}

@MainActor
private final class PageFindPanel: NSPanel {
  var command: ((NSEvent) -> Bool)?
  override var canBecomeKey: Bool { true }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if command?(event) == true { return true }
    return super.performKeyEquivalent(with: event)
  }
}

/// Local chrome only. Neither query text nor find results are sent through MCP.
@MainActor
final class NativePageFindController: NSObject, NSSearchFieldDelegate, NSWindowDelegate {
  let field = NSSearchField(string: "")
  private let status = NSTextField(labelWithString: "")
  private let panel = PageFindPanel(
    contentRect: NSRect(x: 0, y: 0, width: 520, height: 52),
    styleMask: [.titled, .utilityWindow, .closable], backing: .buffered, defer: false)
  private weak var webView: WKWebView?
  private weak var parent: NSWindow?
  private let canSearch: @MainActor () -> Bool
  private var revision = UUID()
  private var work: Task<Void, Never>?
  private var parentCloseObserver: NSObjectProtocol?
  private(set) var matchFound: Bool?
  private(set) var isSearching = false
  var isVisible: Bool { panel.isVisible }

  init(webView: WKWebView, parent: NSWindow, canSearch: @escaping @MainActor () -> Bool) {
    self.webView = webView
    self.parent = parent
    self.canSearch = canSearch
    super.init()
    panel.isReleasedWhenClosed = false
    panel.title = controlText("Find in Page")
    panel.delegate = self
    panel.command = { [weak self] in self?.handleKeyEquivalent($0) ?? false }
    field.placeholderString = controlText("Find in Page")
    field.setAccessibilityLabel(controlText("Find in Page"))
    field.setAccessibilityIdentifier("webkitui.find.query")
    field.delegate = self
    field.maximumRecents = 0
    let previous = NSButton(title: "↑", target: self, action: #selector(previousMatch))
    previous.setAccessibilityLabel(controlText("Previous Match"))
    let next = NSButton(title: "↓", target: self, action: #selector(nextMatch))
    next.setAccessibilityLabel(controlText("Next Match"))
    let row = NSStackView(views: [field, status, previous, next])
    row.spacing = 8
    row.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    row.frame = NSRect(x: 0, y: 0, width: 520, height: 52)
    row.autoresizingMask = [.width, .height]
    field.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
    panel.contentView = row
    parentCloseObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification, object: parent, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.close() }
    }
  }

  isolated deinit {
    work?.cancel()
    parentCloseObserver.map(NotificationCenter.default.removeObserver)
    panel.orderOut(nil)
  }

  func handleKeyEquivalent(_ event: NSEvent) -> Bool {
    guard canSearch(), parent?.attachedSheet == nil else { return false }
    let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
    if event.keyCode == 53, isVisible {
      close(restoreFocus: true)
      return true
    }
    guard flags == .command || flags == [.command, .shift] else { return false }
    switch event.charactersIgnoringModifiers?.lowercased() {
    case "f":
      open()
      return true
    case "g":
      search(backwards: flags.contains(.shift))
      return true
    default: return false
    }
  }

  func open() {
    guard canSearch(), let parent, parent.attachedSheet == nil else { return }
    if panel.parent == nil { parent.addChildWindow(panel, ordered: .above) }
    panel.setFrameOrigin(
      NSPoint(
        x: parent.frame.midX - panel.frame.width / 2, y: parent.frame.maxY - panel.frame.height - 40
      ))
    panel.makeKeyAndOrderFront(nil)
    panel.makeFirstResponder(field)
    field.selectText(nil)
  }

  func updateQuery(_ query: String) {
    field.stringValue = String(query.prefix(2_000))
    search(debounce: true)
  }

  private func search(backwards: Bool = false, debounce: Bool = false) {
    guard canSearch(), isVisible else { return }
    work?.cancel()
    revision = UUID()
    let token = revision
    let query = field.stringValue
    matchFound = nil
    isSearching = !query.isEmpty
    status.stringValue = ""
    work = Task { @MainActor [weak self] in
      if debounce { do { try await Task.sleep(for: .milliseconds(100)) } catch { return } }
      guard let self, self.revision == token, self.canSearch(), self.isVisible,
        let webView = self.webView
      else { return }
      let configuration = WKFindConfiguration()
      configuration.backwards = backwards
      configuration.caseSensitive = false
      configuration.wraps = true
      webView.find(query, configuration: configuration) { [weak self] result in
        guard let self, self.revision == token, self.isVisible, self.canSearch() else { return }
        self.isSearching = false
        self.matchFound = query.isEmpty ? nil : result.matchFound
        self.status.stringValue =
          query.isEmpty ? "" : controlText(result.matchFound ? "Match Found" : "No Match")
      }
      do { try await Task.sleep(for: .seconds(5)) } catch { return }
      guard self.revision == token, self.isSearching else { return }
      self.revision = UUID()
      self.isSearching = false
      self.status.stringValue = controlText("Search Unavailable")
    }
  }

  func close(restoreFocus: Bool = false) {
    let hadSearch = panel.isVisible || !field.stringValue.isEmpty
    revision = UUID()
    work?.cancel()
    work = nil
    isSearching = false
    matchFound = nil
    field.stringValue = ""
    status.stringValue = ""
    parent?.removeChildWindow(panel)
    panel.orderOut(nil)
    if hadSearch {
      webView?.find("", configuration: WKFindConfiguration(), completionHandler: { _ in })
    }
    if restoreFocus, hadSearch, let parent, parent.isVisible, parent.attachedSheet == nil {
      parent.makeKeyAndOrderFront(nil)
      parent.makeFirstResponder(webView)
    }
  }
  func windowWillClose(_ notification: Notification) { close(restoreFocus: true) }
  func controlTextDidChange(_ notification: Notification) { updateQuery(field.stringValue) }
  func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    if selector == #selector(NSResponder.cancelOperation(_:)) {
      close(restoreFocus: true)
      return true
    }
    if selector == #selector(NSResponder.insertNewline(_:)) {
      search(backwards: NSApp.currentEvent?.modifierFlags.contains(.shift) == true)
      return true
    }
    return false
  }
  @objc private func previousMatch() { search(backwards: true) }
  @objc private func nextMatch() { search() }
}
