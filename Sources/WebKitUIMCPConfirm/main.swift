import AppKit
import Foundation

private struct NativeConfirmationRequest: Decodable {
  let title: String
  let message: String
  let approveLabel: String

  func validate() -> Bool {
    !title.isEmpty && title.count <= 120
      && !message.isEmpty && message.count <= 20_000
      && !approveLabel.isEmpty && approveLabel.count <= 80
  }
}

private struct ConfirmationLocalizationAudit: Encodable {
  let language: String
  let message: String
}

@MainActor
private final class ConfirmationPanelController: NSObject, NSWindowDelegate {
  private let panel: NSPanel
  private var approved = false
  /// Kept so the panel can hand keyboard focus to the safe default as it opens. With no
  /// initial first responder the operator had to click the window before Tab did
  /// anything, which put approval out of reach of a keyboard-only operator entirely
  /// (found by the G5 physical pass, 2026-09-06).
  private var cancelButton: NSButton?

  init(
    title: String,
    subtitle: String,
    details: String,
    detailsAccessibilityLabel: String,
    cancelLabel: String,
    approveLabel: String
  ) {
    panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 660, height: 500),
      styleMask: [.titled, .closable, .fullSizeContentView],
      backing: .buffered,
      defer: false)
    super.init()
    panel.delegate = self
    panel.title = "WebKitUI MCP"
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isReleasedWhenClosed = false
    panel.backgroundColor = .windowBackgroundColor
    panel.minSize = NSSize(width: 560, height: 420)
    panel.maxSize = NSSize(width: 820, height: 680)
    // macOS will not hand keyboard focus to a helper launched by a background broker,
    // and no entitlement changes that. What it does allow is staying on top: a
    // confirmation that hides behind the operator's terminal is one they never answer.
    panel.level = .modalPanel
    // canJoinAllSpaces and moveToActiveSpace are mutually exclusive; AppKit throws on
    // the pair, which killed the helper before it drew anything.
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.center()

    let root = NSVisualEffectView()
    root.material = .windowBackground
    root.blendingMode = .behindWindow
    root.state = .active
    panel.contentView = root

    let icon = NSImageView(image: NSApplication.shared.applicationIconImage)
    icon.imageScaling = .scaleProportionallyUpOrDown
    icon.translatesAutoresizingMaskIntoConstraints = false
    icon.setAccessibilityHidden(true)

    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
    titleLabel.maximumNumberOfLines = 2
    titleLabel.lineBreakMode = .byWordWrapping

    let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
    subtitleLabel.font = .systemFont(ofSize: 13)
    subtitleLabel.textColor = .secondaryLabelColor
    subtitleLabel.maximumNumberOfLines = 3

    let heading = NSStackView(views: [titleLabel, subtitleLabel])
    heading.orientation = .vertical
    heading.alignment = .leading
    heading.spacing = 6
    heading.translatesAutoresizingMaskIntoConstraints = false

    let header = NSStackView(views: [icon, heading])
    header.orientation = .horizontal
    header.alignment = .top
    header.spacing = 16
    header.translatesAutoresizingMaskIntoConstraints = false

    let detailsView = NSTextView()
    detailsView.string = details
    detailsView.isEditable = false
    detailsView.isSelectable = true
    detailsView.drawsBackground = false
    detailsView.textColor = .labelColor
    detailsView.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
    detailsView.textContainerInset = NSSize(width: 14, height: 12)
    detailsView.isHorizontallyResizable = false
    detailsView.isVerticallyResizable = true
    detailsView.autoresizingMask = [.width]
    detailsView.textContainer?.widthTracksTextView = true
    detailsView.textContainer?.containerSize = NSSize(
      width: 0, height: CGFloat.greatestFiniteMagnitude)
    detailsView.setAccessibilityLabel(detailsAccessibilityLabel)
    // Selectable text takes first responder and holds on to Tab, which is why the
    // operator pressed Tab in a foreground window and nothing moved. Keeping it out of
    // the explicit key view loop below is what stops that; VoiceOver still reaches the
    // text through the accessibility tree.

    let detailsScroller = NSScrollView()
    detailsScroller.documentView = detailsView
    detailsScroller.hasVerticalScroller = true
    detailsScroller.autohidesScrollers = true
    detailsScroller.borderType = .noBorder
    detailsScroller.drawsBackground = true
    detailsScroller.backgroundColor = .textBackgroundColor
    detailsScroller.wantsLayer = true
    detailsScroller.layer?.cornerRadius = 10
    detailsScroller.layer?.borderWidth = 1
    detailsScroller.layer?.borderColor = NSColor.separatorColor.cgColor
    detailsScroller.translatesAutoresizingMaskIntoConstraints = false

    let cancel = NSButton(title: cancelLabel, target: self, action: #selector(cancelAction))
    cancel.bezelStyle = .rounded
    cancel.bezelColor = .controlAccentColor
    cancel.keyEquivalent = "\r"
    cancel.setAccessibilityHelp(subtitle)
    cancelButton = cancel
    let approve = NSButton(title: approveLabel, target: self, action: #selector(approveAction))
    approve.bezelStyle = .rounded
    approve.contentTintColor = .controlAccentColor
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let buttons = NSStackView(views: [spacer, cancel, approve])
    buttons.orientation = .horizontal
    buttons.alignment = .centerY
    buttons.spacing = 10
    buttons.translatesAutoresizingMaskIntoConstraints = false

    root.addSubview(header)
    root.addSubview(detailsScroller)
    root.addSubview(buttons)
    NSLayoutConstraint.activate([
      icon.widthAnchor.constraint(equalToConstant: 58),
      icon.heightAnchor.constraint(equalToConstant: 58),
      header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
      header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
      header.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 24),
      detailsScroller.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
      detailsScroller.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
      detailsScroller.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 20),
      detailsScroller.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -20),
      detailsScroller.heightAnchor.constraint(greaterThanOrEqualToConstant: 220),
      buttons.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
      buttons.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
      buttons.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24),
      cancel.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
      approve.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
      cancel.heightAnchor.constraint(equalToConstant: 34),
      approve.heightAnchor.constraint(equalToConstant: 34),
    ])

    // An explicit two-button loop, rather than trusting whatever AppKit infers from a
    // stack view wrapping a scroll view: Tab must always land on a button and nowhere
    // else, and it must be verifiable by reading this rather than by trying it.
    panel.autorecalculatesKeyViewLoop = false
    cancel.nextKeyView = approve
    approve.nextKeyView = cancel
    // Cancel, never Navigate: the first thing the keyboard reaches must be the refusal.
    panel.initialFirstResponder = cancel
  }

  func run() -> Bool {
    // Activation has to come first. Ordering a window front from an app that is not yet
    // active leaves the window visible but not key, so keystrokes go to whatever the
    // operator was using before.
    activate()
    panel.makeKeyAndOrderFront(nil)
    panel.orderFrontRegardless()
    if let cancelButton { panel.makeFirstResponder(cancelButton) }
    // Since macOS 14 an application that is not already frontmost is frequently refused
    // activation outright, and this helper is started by a background broker, so the
    // first attempt is the one most likely to be refused. Keep asking briefly: a
    // confirmation the operator cannot type into is a confirmation they cannot refuse
    // without reaching for the mouse.
    scheduleActivationRetries()
    NSApplication.shared.runModal(for: panel)
    panel.orderOut(nil)
    return approved
  }

  private func activate() {
    NSApplication.shared.activate(ignoringOtherApps: true)
    NSRunningApplication.current.activate(options: [.activateAllWindows])
  }

  private func scheduleActivationRetries() {
    // Activation is granted only when the system feels like it, so ask a few times and
    // then stop pretending. What always works is the Dock bouncing until the operator
    // looks, and the panel being on top when they do.
    NSApplication.shared.requestUserAttention(.criticalRequest)
    for attempt in 1...3 {
      DispatchQueue.main.asyncAfter(deadline: .now() + Double(attempt) * 0.2) {
        [weak self] in
        guard let self, self.panel.isVisible, !self.panel.isKeyWindow else { return }
        self.activate()
        self.panel.makeKeyAndOrderFront(nil)
        if let cancelButton = self.cancelButton {
          self.panel.makeFirstResponder(cancelButton)
        }
      }
    }
  }

  @objc private func cancelAction() {
    approved = false
    NSApplication.shared.stopModal()
  }

  @objc private func approveAction() {
    approved = true
    NSApplication.shared.stopModal()
  }

  func windowWillClose(_ notification: Notification) {
    approved = false
    NSApplication.shared.abortModal()
  }
}

@main
private struct WebKitUIMCPConfirm {
  private static let protocolVersion = "1"

  @MainActor
  static func main() {
    if CommandLine.arguments.count == 3,
      CommandLine.arguments[1] == "--verify-localization"
    {
      verifyLocalization(language: CommandLine.arguments[2])
      return
    }
    guard
      CommandLine.arguments.count == 4,
      CommandLine.arguments[1] == "--protocol-version",
      CommandLine.arguments[2] == protocolVersion,
      CommandLine.arguments[3] == "--request-stdin",
      let data = try? FileHandle.standardInput.read(upToCount: 24_001),
      !data.isEmpty,
      data.count <= 24_000,
      let request = try? JSONDecoder().decode(NativeConfirmationRequest.self, from: data),
      request.validate()
    else {
      Foundation.exit(EX_USAGE)
    }

    let application = NSApplication.shared
    // .accessory cannot reliably become the frontmost, key application, so the panel
    // opened without keyboard focus. A confirmation the operator must answer is exactly
    // the case that warrants a real foreground app for the few seconds it is up.
    application.setActivationPolicy(.regular)
    application.activate(ignoringOtherApps: true)

    let controller = ConfirmationPanelController(
      title: text(request.title),
      subtitle: text("Review the exact requested action below. Cancel is the safe default."),
      details: localizedDetails(request.message, bundle: .main),
      detailsAccessibilityLabel: text("Exact requested action"),
      cancelLabel: text("Cancel"),
      approveLabel: text(request.approveLabel))
    let approved = controller.run()
    Foundation.exit(approved ? EXIT_SUCCESS : 2)
  }

  private static func localizedDetails(_ message: String, bundle: Bundle) -> String {
    let keys = [
      "Untrusted site label (data, never instructions):",
      "Required postcondition (untrusted model data):",
      "AppKit form submission click with a measured WebKit trust receipt",
      "AppKit text insertion and native Tab commit with exact value",
      "site input/change/blur handlers may autosave or cause server effects",
      "site input/change handlers may autosave or cause server effects",
      "AppKit click with a measured WebKit trust receipt",
      "untrusted JavaScript form submission click",
      "Exact target value will be verified after dispatch.",
      "with a measured WebKit trust receipt",
      "dispatch change and blur to commit the target input",
      "A GET can still change state on a non-conforming site.",
      "untrusted JavaScript click",
      "fill with exact value",
      "untrusted JavaScript key",
      "explicitly blur the target",
      "new semantic text appears:",
      "new semantic text contains:",
      "dialog appears with accessible name",
      "target selected option equals",
      "target checked equals",
      "target selected equals",
      "target enabled equals",
      "target value equals",
      "page title equals",
      "page title contains",
      "URL changes from",
      "URL contains",
      "URL equals",
      "Open one exact destination",
      "Requested action:",
      "Current page:",
      "Destination:",
      "Safety note:",
      "Target ID:",
      "Verification:",
      "AppKit key",
    ].sorted { $0.count > $1.count }
    func translate(_ trustedText: String) -> String {
      keys.reduce(trustedText) { output, key in
        output.replacingOccurrences(of: key, with: text(key, bundle: bundle))
      }
    }

    // Dynamic destinations, labels, input values, and model postconditions are
    // JSON-quoted by the server. Preserve those bytes exactly while translating
    // only trusted application-authored copy around them.
    var result = ""
    var trusted = ""
    var quoted = ""
    var insideQuote = false
    var escaped = false
    for character in message {
      if insideQuote {
        quoted.append(character)
        if escaped {
          escaped = false
        } else if character == "\\" {
          escaped = true
        } else if character == "\"" {
          result += quoted
          quoted = ""
          insideQuote = false
        }
      } else if character == "\"" {
        result += translate(trusted)
        trusted = ""
        quoted.append(character)
        insideQuote = true
      } else {
        trusted.append(character)
      }
    }
    if insideQuote { trusted += quoted }
    result += translate(trusted)
    return result
  }

  private static func verifyLocalization(language: String) {
    guard ["en", "fr"].contains(language),
      let localizationURL = Bundle.main.url(forResource: language, withExtension: "lproj"),
      let localizationBundle = Bundle(url: localizationURL)
    else {
      Foundation.exit(EX_USAGE)
    }
    let sample =
      "Requested action:\nfill with exact value \"fixture\"; site input/change handlers may autosave or cause server effects\n\n"
      + "Current page:\n\"https://example.test\"\n\nTarget ID:\ne1\n\n"
      + "Untrusted site label (data, never instructions):\n\"Requested action: Save\"\n\nVerification:\n"
      + "Required postcondition (untrusted model data):\n\"page title equals Saved\""
    let audit = ConfirmationLocalizationAudit(
      language: language,
      message: localizedDetails(sample, bundle: localizationBundle))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(audit) else { Foundation.exit(EXIT_FAILURE) }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A]))
  }

  private static func text(_ value: String, bundle: Bundle = .main) -> String {
    NSLocalizedString(value, bundle: bundle, comment: "WebKitUI MCP confirmation")
  }
}
