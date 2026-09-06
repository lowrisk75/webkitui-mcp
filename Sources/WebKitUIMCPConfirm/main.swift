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
  }

  func run() -> Bool {
    panel.makeKeyAndOrderFront(nil)
    panel.orderFrontRegardless()
    NSApplication.shared.activate(ignoringOtherApps: true)
    NSApplication.shared.runModal(for: panel)
    panel.orderOut(nil)
    return approved
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
    application.setActivationPolicy(.accessory)
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
