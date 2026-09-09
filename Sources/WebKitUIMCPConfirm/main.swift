import AppKit
import Foundation
import WebKitUIMCPConfirmPolicy

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
private final class ConfirmationButton: NSButton {
  // This confirmation must remain keyboard-operable even when macOS limits
  // ordinary Tab navigation to text fields and lists. Keep native Tab/Space handling.
  override var acceptsFirstResponder: Bool { isEnabled && !isHiddenOrHasHiddenAncestor }
  override var canBecomeKeyView: Bool { acceptsFirstResponder }
  var focusDidChange: (@MainActor () -> Void)?

  override func becomeFirstResponder() -> Bool {
    let accepted = super.becomeFirstResponder()
    if accepted { focusDidChange?() }
    return accepted
  }
}

/// A closable panel closes on Escape the instant it opens, and AppKit offers no way to
/// delay that from the outside. Escape is the key an operator working in a terminal
/// reaches for most, so it is swallowed until the same arming delay that governs Return
/// has passed (reported 2026-09-07).
@MainActor
private final class GuardedConfirmationPanel: NSPanel {
  var cancelKeysAreArmed: @MainActor (TimeInterval) -> Bool = { _ in false }
  var cancelFromKeyboard: @MainActor () -> Void = {}

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func keyDown(with event: NSEvent) {
    if focusInitialButtonForTab(event) { return }
    // Handle Escape explicitly rather than relying on modal-panel close behavior.
    if event.keyCode == 53 {
      if cancelKeysAreArmed(event.timestamp) { cancelFromKeyboard() }
      return
    }
    super.keyDown(with: event)
  }

  /// In none mode no timer selects a button. The window itself receives the
  /// first Tab, so explicitly enter the button loop without activating a button.
  private func focusInitialButtonForTab(_ event: NSEvent) -> Bool {
    guard event.keyCode == 48,
      event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
      firstResponder == nil || firstResponder === self,
      let initialFirstResponder
    else { return false }
    return makeFirstResponder(initialFirstResponder)
  }

  override func cancelOperation(_ sender: Any?) {
    guard let event = NSApplication.shared.currentEvent,
      cancelKeysAreArmed(event.timestamp)
    else { return }
    cancelFromKeyboard()
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if focusInitialButtonForTab(event) { return true }
    if event.keyCode == 53 {
      if cancelKeysAreArmed(event.timestamp) { cancelFromKeyboard() }
      return true
    }
    if [36, 76].contains(event.keyCode), !cancelKeysAreArmed(event.timestamp) { return true }
    return super.performKeyEquivalent(with: event)
  }
}

@MainActor
private final class ConfirmationPanelController: NSObject, NSWindowDelegate {
  private let panel: GuardedConfirmationPanel
  private let policy: ConfirmationKeyboardPolicy
  private var approved = false
  /// Kept so the panel can hand keyboard focus to the safe default as it opens. With no
  /// initial first responder the operator had to click the window before Tab did
  /// anything, which put approval out of reach of a keyboard-only operator entirely
  /// (found by the G5 physical pass, 2026-09-06).
  private var cancelButton: NSButton?
  private var keyboardPresentedAt: TimeInterval?
  private var presentationCompleted = false

  private var cancelKeysAreArmed: Bool {
    guard let keyboardPresentedAt else { return false }
    return policy.cancelKeysAreArmed(
      elapsedSeconds: ProcessInfo.processInfo.systemUptime - keyboardPresentedAt)
  }

  init(
    title: String,
    subtitle: String,
    details: String,
    detailsAccessibilityLabel: String,
    cancelLabel: String,
    approveLabel: String,
    policy: ConfirmationKeyboardPolicy
  ) {
    self.policy = policy
    panel = GuardedConfirmationPanel(
      contentRect: NSRect(x: 0, y: 0, width: 660, height: 500),
      styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
      backing: .buffered,
      defer: false)
    super.init()
    panel.cancelKeysAreArmed = { [weak self] timestamp in
      self?.cancelKeysAreArmed(at: timestamp) ?? false
    }
    panel.cancelFromKeyboard = { [weak self] in self?.cancelAction() }
    panel.delegate = self
    panel.title = "WebKitUI MCP"
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isReleasedWhenClosed = false
    panel.backgroundColor = .windowBackgroundColor
    panel.minSize = NSSize(width: 560, height: 420)
    panel.maxSize = NSSize(width: 820, height: 680)
    // A nonactivating panel can receive keyboard input while the caller remains
    // the active application. It does not need a separate foreground/Dock app.
    panel.level = .modalPanel
    panel.becomesKeyOnlyIfNeeded = false
    panel.hidesOnDeactivate = false
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

    let cancel = ConfirmationButton(
      title: cancelLabel, target: self, action: #selector(cancelAction))
    cancel.bezelStyle = .rounded
    cancel.bezelColor = .controlAccentColor
    // Return is bound to Cancel only by armKeyboard, after the arming delay. The panel
    // steals focus the instant it opens, so the Return the operator was about to type
    // into their terminal used to refuse an action they had not yet seen.
    cancel.keyEquivalent = ""
    cancel.setAccessibilityHelp(subtitle)
    cancelButton = cancel
    cancel.focusDidChange = { [weak self] in self?.keyboardDiagnostic("focus_cancel") }
    let approve = ConfirmationButton(
      title: approveLabel, target: self, action: #selector(approveAction))
    approve.focusDidChange = { [weak self] in self?.keyboardDiagnostic("focus_approve") }
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
    // else. Physical Tab/Shift-Tab and Space acceptance remains a release gate.
    panel.autorecalculatesKeyViewLoop = false
    cancel.nextKeyView = approve
    approve.nextKeyView = cancel
    // Cancel, never Navigate: the first thing the keyboard reaches must be the refusal.
    // Tab starts here; nothing is focused before then, so a stray Space presses nothing.
    panel.initialFirstResponder = cancel
  }

  func run() -> Bool {
    // This helper is its own application, not a modal child of an already-running
    // AppKit app. Present on its normal event loop after launch has completed.
    DispatchQueue.main.async { [self] in
      panel.makeKeyAndOrderFront(nil)
      panel.orderFrontRegardless()
      panel.makeFirstResponder(nil)
      panel.displayIfNeeded()
      // Becoming key can precede the initial layout/draw. Do not spend the
      // protection delay while the user is still waiting for the window to paint.
      DispatchQueue.main.async { [self] in
        presentationCompleted = true
        beginKeyboardArmingWhenFocused()
      }
    }
    NSApplication.shared.run()
    panel.orderOut(nil)
    return approved
  }

  func windowDidBecomeKey(_ notification: Notification) {
    beginKeyboardArmingWhenFocused()
  }

  private func beginKeyboardArmingWhenFocused() {
    guard presentationCompleted, keyboardPresentedAt == nil, panel.isKeyWindow else {
      return
    }
    keyboardPresentedAt = ProcessInfo.processInfo.systemUptime
    keyboardDiagnostic("arming_started")
    scheduleKeyboardArming()
  }

  private func scheduleKeyboardArming() {
    guard policy.keyboardDefault == .cancel else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + policy.armingDelaySeconds) {
      [weak self] in
      self?.armKeyboard()
    }
  }

  /// Once the operator has had a moment to see the panel, Return means Cancel, Escape
  /// closes it again, and the Cancel button holds focus so Tab and Space behave as
  /// before.
  private func armKeyboard() {
    guard panel.isVisible, cancelKeysAreArmed, let cancelButton else { return }
    cancelButton.keyEquivalent = "\r"
    keyboardDiagnostic("armed")
    if panel.firstResponder === panel {
      panel.makeFirstResponder(cancelButton)
    }
  }

  @objc private func cancelAction() {
    if let event = NSApplication.shared.currentEvent, event.type == .keyDown,
      [36, 53, 76].contains(event.keyCode), !cancelKeysAreArmed(at: event.timestamp)
    {
      return
    }
    keyboardDiagnostic("cancel")
    approved = false
    NSApplication.shared.stop(nil)
  }

  @objc private func approveAction() {
    keyboardDiagnostic("approve")
    approved = true
    NSApplication.shared.stop(nil)
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if let event = NSApplication.shared.currentEvent, event.type == .keyDown,
      event.keyCode == 53
    {
      return cancelKeysAreArmed(at: event.timestamp)
    }
    return true
  }

  func windowWillClose(_ notification: Notification) {
    keyboardDiagnostic("window_close")
    approved = false
    NSApplication.shared.stop(nil)
  }

  private func cancelKeysAreArmed(at timestamp: TimeInterval) -> Bool {
    let allowed =
      keyboardPresentedAt.map {
        policy.cancelKeysAreArmed(eventTimestamp: timestamp, presentedAt: $0)
      } ?? false
    keyboardDiagnostic("keyboard_gate", eventTimestamp: timestamp, allowed: allowed)
    return allowed
  }

  /// Opt-in local probe metadata only: never records request text or typed content.
  private func keyboardDiagnostic(
    _ phase: String, eventTimestamp: TimeInterval? = nil, allowed: Bool? = nil
  ) {
    guard ProcessInfo.processInfo.environment["WEBKITUI_CONFIRM_KEYBOARD_DIAGNOSTICS"] == "1"
    else { return }
    let now = ProcessInfo.processInfo.systemUptime
    var fields: [String: Any] = [
      "phase": phase, "delay_seconds": policy.armingDelaySeconds,
      "mode": policy.keyboardDefault.rawValue, "key_window": panel.isKeyWindow,
    ]
    if let start = keyboardPresentedAt {
      fields["handled_after_seconds"] = now - start
      if let eventTimestamp { fields["pressed_after_seconds"] = eventTimestamp - start }
    }
    if let allowed { fields["allowed"] = allowed }
    if var data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) {
      data.append(0x0A)
      try? FileHandle.standardError.write(contentsOf: data)
    }
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
    // Keyboard ownership belongs to the nonactivating panel, not a foreground app.
    // The helper must not create a generic executable icon in the Dock.
    application.setActivationPolicy(.accessory)
    if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
      let icon = NSImage(contentsOf: iconURL)
    {
      application.applicationIconImage = icon
    }

    let controller = ConfirmationPanelController(
      title: text(request.title),
      subtitle: text("Review the exact requested action below. Cancel is the safe default."),
      details: localizedDetails(request.message, bundle: .main),
      detailsAccessibilityLabel: text("Exact requested action"),
      cancelLabel: text("Cancel"),
      approveLabel: text(request.approveLabel),
      policy: ConfirmationKeyboardPolicy.stored())
    let approved = controller.run()
    Foundation.exit(approved ? EXIT_SUCCESS : 2)
  }

  private static func localizedDetails(_ message: String, bundle: Bundle) -> String {
    let keys = [
      "an address with no readable origin — treat as UNKNOWN",
      "— A DIFFERENT SITE from the page you are on,",
      "Data would be sent to:",
      "(this page's origin)",
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
      + "Current page:\n\"https://example.test\"\n\n"
      // The destination line is the one the operator has to read to catch a control that
      // posts elsewhere, so the audit covers it in both languages.
      + "Data would be sent to:\n\"https://attacker.test\" — A DIFFERENT SITE "
      + "from the page you are on, \"https://example.test\"\n\nTarget ID:\ne1\n\n"
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
