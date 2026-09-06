import AppKit
import Foundation
import UniformTypeIdentifiers
import WebKitUIMCPServer

@MainActor
final class ActivityLogWindowController: NSObject, NSWindowDelegate {
  struct ClearConfirmationAudit: Codable {
    let language: String
    let buttonTitles: [String]
    let defaultButtonIndex: Int
    let destructiveButtonIndex: Int
  }

  private let activityLog: WebKitActivityLog?
  private let window: NSWindow
  private let textView = NSTextView()
  private let summary = NSTextField(labelWithString: "")

  init(activityLog: WebKitActivityLog?) {
    self.activityLog = activityLog
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    super.init()
    configureWindow()
  }

  func show() {
    window.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
    refresh()
  }

  private func configureWindow() {
    window.title = text("WebKitUI MCP Activity")
    window.isReleasedWhenClosed = false
    window.minSize = NSSize(width: 620, height: 380)
    window.delegate = self
    window.center()

    let title = NSTextField(labelWithString: text("Private activity journal"))
    title.font = .systemFont(ofSize: 24, weight: .semibold)
    title.setAccessibilityIdentifier("webkitui.activity.title")

    let privacy = NSTextField(
      wrappingLabelWithString: text(
        "Stored only on this Mac. Parameters, page content, credentials, cookies and keystrokes are never recorded."
      ))
    privacy.textColor = .secondaryLabelColor
    privacy.setAccessibilityIdentifier("webkitui.activity.privacy")

    summary.textColor = .secondaryLabelColor
    summary.setAccessibilityIdentifier("webkitui.activity.summary")

    textView.isEditable = false
    textView.isSelectable = true
    textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    textView.textContainerInset = NSSize(width: 10, height: 10)
    textView.setAccessibilityLabel(text("Activity events"))
    textView.setAccessibilityIdentifier("webkitui.activity.events")
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.borderType = .bezelBorder
    scrollView.documentView = textView
    scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true

    let refreshButton = NSButton(
      title: text("Refresh"), target: self, action: #selector(refreshAction))
    refreshButton.bezelStyle = .rounded
    refreshButton.setAccessibilityIdentifier("webkitui.activity.refresh")
    let exportButton = NSButton(
      title: text("Export…"), target: self, action: #selector(exportAction))
    exportButton.bezelStyle = .rounded
    exportButton.setAccessibilityIdentifier("webkitui.activity.export")
    let clearButton = NSButton(
      title: text("Clear…"), target: self, action: #selector(clearAction))
    clearButton.bezelStyle = .rounded
    clearButton.contentTintColor = .systemRed
    clearButton.setAccessibilityIdentifier("webkitui.activity.clear")
    let buttons = NSStackView(views: [refreshButton, exportButton, clearButton])
    buttons.orientation = .horizontal
    buttons.spacing = 8

    let content = NSStackView(views: [title, privacy, summary, scrollView, buttons])
    content.orientation = .vertical
    content.alignment = .leading
    content.spacing = 14
    content.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
    content.translatesAutoresizingMaskIntoConstraints = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    privacy.translatesAutoresizingMaskIntoConstraints = false

    let root = NSView()
    window.contentView = root
    root.addSubview(content)
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      content.topAnchor.constraint(equalTo: root.topAnchor),
      content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      privacy.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -48),
      scrollView.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -48),
    ])
    window.initialFirstResponder = refreshButton
  }

  @objc private func refreshAction() { refresh() }

  private func refresh() {
    Task { @MainActor [weak self] in
      guard let self else { return }
      guard let activityLog else {
        summary.stringValue = text("Activity journal unavailable")
        textView.string = ""
        return
      }
      do {
        let events = try await activityLog.events(limit: 500)
        let failure = await activityLog.failureType()
        summary.stringValue =
          String(
            format: text("%ld recent events · automatic rotation enabled"), events.count)
          + (failure.map { " · \(text("Write error")): \($0)" } ?? "")
        textView.string = events.map(Self.line).joined(separator: "\n")
      } catch {
        summary.stringValue = text("Activity journal unavailable")
        textView.string = String(describing: type(of: error))
      }
    }
  }

  @objc private func exportAction() {
    Task { @MainActor [weak self] in
      guard let self, let activityLog else { return }
      do {
        let data = try await activityLog.exportData()
        let panel = NSSavePanel()
        panel.title = text("Export private activity journal")
        panel.nameFieldStringValue = "WebKitUI-MCP-activity.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
      } catch {
        presentError(title: text("Export failed"), error: error)
      }
    }
  }

  @objc private func clearAction() {
    let audit = Self.clearConfirmationAudit(language: "current", bundle: .main)
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = text("Clear the activity journal?")
    alert.informativeText = text(
      "This removes the local activity files. Transaction receipts are kept.")
    let cancelButton = alert.addButton(withTitle: audit.buttonTitles[audit.defaultButtonIndex])
    cancelButton.keyEquivalent = "\r"
    let clearButton = alert.addButton(withTitle: audit.buttonTitles[audit.destructiveButtonIndex])
    clearButton.keyEquivalent = ""
    guard alert.runModal() == .alertSecondButtonReturn else { return }
    Task { @MainActor [weak self] in
      guard let self, let activityLog else { return }
      do {
        try await activityLog.clear()
        refresh()
      } catch {
        presentError(title: text("Journal could not be cleared"), error: error)
      }
    }
  }

  static func clearConfirmationAudit(language: String, bundle: Bundle) -> ClearConfirmationAudit {
    ClearConfirmationAudit(
      language: language,
      buttonTitles: [
        NSLocalizedString("Cancel", bundle: bundle, comment: "Safe activity journal default"),
        NSLocalizedString(
          "Clear Journal", bundle: bundle, comment: "Destructive activity journal action"),
      ],
      defaultButtonIndex: 0,
      destructiveButtonIndex: 1)
  }

  private func presentError(title: String, error: Error) {
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = title
    alert.informativeText = String(describing: type(of: error))
    alert.addButton(withTitle: text("OK"))
    alert.runModal()
  }

  private static func line(_ event: WebKitActivityEvent) -> String {
    let date = ISO8601DateFormatter().string(from: event.timestamp)
    let result = event.outcome == .succeeded ? "PASS" : "FAIL"
    let action = event.toolName ?? event.method
    let error = event.errorType.map { " · \($0)" } ?? ""
    return "\(date) · \(result) · \(action) · \(event.durationMilliseconds) ms\(error)"
  }

  private func text(_ value: String) -> String {
    NSLocalizedString(value, bundle: .main, comment: "WebKitUI MCP activity journal")
  }
}
