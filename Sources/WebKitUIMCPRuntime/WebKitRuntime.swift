import AppKit
// Text Input Services and UCKeyTranslate: the only route to what a key produces on the
// layout this Mac is actually using. Nothing else here comes from Carbon.
import Carbon
import CryptoKit
import Foundation
import OSLog
import Security
import WebKit
import WebKitUIMCPCore

public enum WebKitRuntimeError: Error, Equatable, Sendable {
  case unsupportedURLScheme
  case navigationFailed(String)
  case crossOriginRedirectRequiresHuman(fromOrigin: String, toOrigin: String)
  case navigationTimedOut
  case webContentProcessTerminated
  case networkBoundaryDenied
  case malformedInstrumentationResult
  case noDocument
  case invalidQuietWindow
  case staleObservation
  case unknownElement
  /// Carries why addressing by the identity the observation handed out did not settle
  /// it, because that is what tells a client whether to re-observe or look again.
  case targetNotUnique(Int, pinned: String)
  case targetNotActionable
  /// A native pointer operation cannot translate a frame-local rectangle into the
  /// top-level WebKit view with public API. Nothing was dispatched.
  case crossOriginNativeGeometryUnavailable(String)
  /// The control is visible inside a cross-origin frame, but public WebKit exposes no
  /// transform from that frame's viewport to top-level native pointer coordinates.
  /// Until an exact frame-local dispatch exists, every operation refuses before
  /// confirmation or dispatch and offers the live human handoff.
  case crossOriginFrameActionUnavailable(String)
  case targetGeometryChanged
  /// Nothing matched the address at all. Carries the required facts whose removal would
  /// have matched, which names what changed under the observation.
  case targetNotFound([String])
  /// The control exists and can be reached, but this operation is not one it accepts.
  /// Carries its role and the route that does work, because target_not_actionable was
  /// also what an overlay and a disabled button returned.
  case operationUnsupportedForControl(role: String, alternative: String)
  case sensitiveInputRequiresHuman
  case downloadInProgress
  case downloadCancelled
  case downloadReceiptTimedOut(started: Bool)
  case unsupportedDownload(httpStatus: Int?)
  case downloadHTTPFailure(status: Int)
  case downloadFailed(String)
  case invalidCredentialOrigin
  case invalidCredentialBinding
  /// The destination resolves only to private, loopback, link-local or carrier-grade
  /// NAT space (Tailscale's 100.64.0.0/10 among them), which the protected browser
  /// never connects to.
  case privateNetworkDestination(origin: String)
  /// The destination is on the owner's Tailscale network and has not been granted.
  case tailnetDestinationRequiresApproval(origin: String)
  case invalidCredentialSecret
  case humanControlActive
  case authenticationOriginRequiresHuman(String)
  case noPendingCrossOriginNavigation
  case invalidControlTransition
  case nativeGestureReceiptUnavailable
  /// A handoff was requested but no window a human could act in could be shown.
  case handoffSurfaceUnavailable
  /// A JavaScript panel is open, so the page's script is suspended on it and nothing
  /// else can be dispatched. Carries the kind and the pending dialog's identity; the
  /// panel's own message is deliberately absent, because it is site-authored text and
  /// an error string reaches a client with no provenance attached to it. The
  /// observation carries the message, labelled.
  case javaScriptDialogPending(kind: String, dialogID: String)
  /// The gesture that was dispatched opened the panel itself. The gesture landed; the
  /// page then stopped running, so nothing about the action can be verified until the
  /// panel is answered.
  case javaScriptDialogOpenedByAction(kind: String, dialogID: String)
  case noPendingJavaScriptDialog
  /// An answer named a dialog that is no longer the pending one — already answered,
  /// timed out, or replaced. An answer is bound to one panel and fails closed.
  case staleJavaScriptDialog
  case javaScriptDialogValueRequired
  case javaScriptDialogValueUnsupported
  /// No virtual key code exists for the requested key on the keyboard layout this Mac is
  /// using, so there is no keystroke that means what the confirmation named. Carries the
  /// key as asked for.
  case keyCodeUnavailable(String)
  /// The requested chord is a key equivalent this application's own main menu claims.
  /// Carries the chord.
  case keyChordReservedByApplicationMenu(String)
  /// A modifier that changes which character a real keyboard produces was asked for
  /// alongside the character itself, so the event's characters and its modifier mask
  /// would contradict each other. Carries the chord.
  case keyModifierChangesCharacter(String)
  /// The option label named none of the control's options, or more than one of them.
  /// Carries how many it matched, which is the same shape `targetNotUnique` reports for
  /// an address that settles on no single element: an option is addressed by what it
  /// says, never by where it sits, so a tie is refused rather than broken by position.
  case optionLabelNotUnique(Int)
  /// The selection was dispatched and the freshly re-resolved control does not report
  /// the requested option as selected. The gesture landed; its effect is unknown, so
  /// this is indeterminate and never a failure to dispatch.
  case selectedOptionMismatch
  /// The requested history direction has no entry. WebKit's `goBack()` and
  /// `goForward()` otherwise return nil and leave the caller unable to distinguish a
  /// refusal from a no-op.
  case historyEntryUnavailable(WebKitHistoryOperation)
  /// The entry WebKit offered before confirmation changed while the operator was
  /// reading it. History is re-read immediately before dispatch, just like an element
  /// is re-resolved after its confirmation.
  case historyDestinationChanged
  /// Reloading the response to a form submission can submit the same write twice.
  case formSubmissionReloadRefused
  case invalidViewportSize(width: Int, height: Int)
}

public enum AuthenticationUIClassification: String, Codable, Equatable, Sendable {
  case humanHandoffRequired = "authentication_origin_requires_human_handoff"
  case authUINotReady = "auth_ui_not_ready"
  case fullBrowserRequired = "full_browser_required"
}

public struct AuthenticationRestrictionStatus: Codable, Equatable, Sendable {
  public let origin: String
  public let classification: AuthenticationUIClassification
  public let environment: AuthenticationEnvironmentSnapshot
}

public struct AuthenticationEnvironmentSnapshot: Codable, Equatable, Sendable {
  public let persistentWebsiteDataStore: Bool
  public let customUserAgentConfigured: Bool
  public let applicationNameForUserAgentConfigured: Bool
  public let pinnedProxyConfigured: Bool
  public let contentBlockingConfigured: Bool
  public let customProcessPoolConfigured: Bool
  public let webAuthnAnyRelyingPartyEntitlementConfigured: Bool
}

public enum InteractionControlState: String, Codable, Equatable, Sendable {
  case agentControlled = "agent_controlled"
  case handoffRequested = "handoff_requested"
  case humanControlled = "human_controlled"
  case humanStepCompleted = "human_step_completed"
  case resumeRequested = "resume_requested"
  case freshlyReobserved = "freshly_reobserved"
}

public struct HandoffAuditEvent: Codable, Equatable, Sendable {
  public let from: InteractionControlState
  public let to: InteractionControlState
  public let documentID: String
  public let observationID: String?
  public let monotonicNanoseconds: UInt64
}

public enum PageReadiness: String, Codable, Equatable, Sendable {
  case ready
  case deadlineReached = "deadline_reached"
  case processTerminated = "process_terminated"
}

/// Whether a technically settled document exposes anything a person or an agent can
/// use. DOM completion is deliberately separate: a blank application shell can reach
/// `readyState=complete` and mutation quiescence while still rendering no page at all.
public enum PageContentState: String, Codable, Equatable, Sendable {
  case usable
  case emptyOrUnusable = "empty_or_unusable"
  case unknown
}

public struct WebKitNavigationResult: Codable, Equatable, Sendable {
  public let documentID: String
  public let url: String
  /// Where the caller asked to go. A single-page console sends several real paths to a
  /// dashboard, and the landing URL alone left an agent to notice the difference by
  /// comparing strings it was never told to compare.
  public let requestedURL: String
  public var redirected: Bool { requestedURL != url }
  public let readiness: PageReadiness
  public let contentState: PageContentState
  public let elapsedNanoseconds: UInt64
  public let mutationCount: UInt64
}

public enum WebKitHistoryOperation: String, Codable, Equatable, Sendable {
  case back
  case forward
  case reload
}

public struct WebKitViewportChangeResult: Codable, Equatable, Sendable {
  public let previousWidth: Int
  public let previousHeight: Int
  public let width: Int
  public let height: Int
  public let layoutChanged: Bool
  public let observationInvalidated: Bool
}

public enum WebKitNavigationActor: String, Codable, Equatable, Sendable {
  case agentNavigation = "agent_navigation"
  case agentAction = "agent_action"
  case human
  case webContent = "web_content"
  case unattributed
}

public struct WebKitNavigationAuditEvent: Codable, Equatable, Sendable {
  public let fromOrigin: String?
  public let toOrigin: String?
  public let actor: WebKitNavigationActor
  public let navigationType: String
  public let allowed: Bool
  public let monotonicNanoseconds: UInt64
}

public struct ObservedBoundingBox: Codable, Equatable, Sendable {
  public let x: Double
  public let y: Double
  public let width: Double
  public let height: Double
}

public enum ObservedContextAnchorKind: String, Codable, Equatable, Sendable {
  case fieldsetLegend = "fieldset_legend"
  case labelledRegion = "labelled_region"
  case nearestHeading = "nearest_heading"
  case previousSibling = "previous_sibling"
  case sameRowLabel = "same_row_label"
}

public struct ObservedContextAnchor: Codable, Equatable, Sendable {
  public let kind: ObservedContextAnchorKind
  public let text: ProvenancedText
}

public enum LocatorQualityStatus: String, Codable, Equatable, Sendable {
  case unique
  case ambiguous
  case insufficient
}

public struct LocatorQuality: Codable, Equatable, Sendable {
  public let status: LocatorQualityStatus
  public let candidateCount: Int
  public let candidateCountIsLowerBound: Bool
  public let facts: [String]
  public let recommendedAction: String?
}

public struct WebKitObservedElement: Codable, Equatable, Sendable {
  public let elementID: String
  /// Present only for a separately evaluated embedded frame. Main-document and
  /// same-origin descendant controls omit both fields to preserve the default wire
  /// budget. The origin contains no path, query, fragment, or credentials.
  public let frameOrigin: String?
  public let frameIsMain: Bool?
  public let tag: ProvenancedText
  public let role: ProvenancedText?
  public let accessibleName: ProvenancedText?
  /// Absolute URL this control's data would reach, from the DOM's own attributes.
  /// `nil` for a control that sends nothing. Site-authored, so it is shown to the
  /// human and never trusted as policy.
  public var submissionDestination: String?
  public let label: ProvenancedText?
  public let text: ProvenancedText?
  public let value: ProvenancedText?
  public let validationState: ObservedValidationState
  public let characterCount: Int?
  public let sensitive: Bool
  public let submitsForm: Bool
  public let disabled: Bool
  public let checked: Bool?
  public let selected: Bool?
  /// What is chosen in a `<select>`, which is the only form that control's value takes.
  /// `nil` for a sensitive control, exactly as `text` and `value` are `nil` there: a
  /// selected label is a value, and a sensitive control's value does not leave this
  /// machine. The control itself is still reported, with its role and its accessible
  /// name, so an agent can see it exists and hand it to a human.
  public let selectedOption: ProvenancedText?
  /// What a `<select>` will accept as an address. `select_option` names an option by its
  /// exact visible label and never by an index, so an observation that publishes only
  /// the selected one leaves an agent guessing the rest off the surrounding page — and a
  /// guess that misses is refused correctly and uselessly.
  ///
  /// `nil`, and absent from the wire payload, for anything that is not a `<select>` whose
  /// options are published — which is most of a page, and every byte of that absence was
  /// measured against the one-mebibyte wire budget. `nil` rather than empty for a
  /// sensitive select too: nothing published is not the same claim as a control with no
  /// choices in it.
  public let options: [ObservedOption]?
  /// How many options the control actually has, before the bound.
  public let optionCount: Int?
  /// The published list is a prefix, not the whole control. Said out loud rather than
  /// left to be inferred by comparing two numbers: an agent that reads a cut list as
  /// complete concludes an option does not exist and gives up.
  public let optionsTruncated: Bool?
  public let stateAttributes: [String: ProvenancedText]
  public let contextAnchors: [ObservedContextAnchor]
  public let stableAttributes: [String: ProvenancedText]
  public let visible: Bool
  public let actionability: ObservedActionability
  public var actionable: Bool { actionability == .actionable }
  /// Eligible frame-local dispatch modes, not a promise of success: the live target
  /// still has to pass exact-frame, state, uniqueness, and geometry checks. `nil` on
  /// the main page; empty for an embedded control reserved for human handling.
  public let frameActionModes: [WebKitFrameActionMode]?
  /// Absent for the main document and same-origin descendants, whose boxes use the
  /// top-level viewport. A separately evaluated frame cannot be transformed through
  /// public WebKit API, so its local coordinate space is named instead of implied.
  public let boundingBoxCoordinateSpace: ObservedBoundingBoxCoordinateSpace?
  public let boundingBox: ObservedBoundingBox
  public let locatorRecipe: LocatorRecipe
  public let locatorQuality: LocatorQuality
}

/// Why a control can or cannot be acted on, decided during observation so an agent
/// never has to spend a failed dispatch to find out. `locatorQuality` answers whether
/// the address is unique; it was read as whether the target can be clicked.
/// One choice a `<select>` offers, in the order the control offers it. Site-authored,
/// so the label carries the same provenance as every other page string.
public struct ObservedOption: Codable, Equatable, Sendable {
  public let label: ProvenancedText
  public let selected: Bool
  /// Marked, never dropped: an agent that cannot see a disabled option keeps asking for
  /// it and keeps being refused.
  public let disabled: Bool

  public init(label: ProvenancedText, selected: Bool, disabled: Bool) {
    self.label = label
    self.selected = selected
    self.disabled = disabled
  }
}

public enum ObservedActionability: String, Codable, Equatable, Sendable {
  case actionable
  /// Semantics are readable, but the bounding box is in the embedded frame's local
  /// viewport. Public `WKFrameInfo` exposes no exact native coordinate transform.
  case crossOriginFrameNativeGeometryUnavailable =
    "cross_origin_frame_native_geometry_unavailable"
  /// Laid out but collapsed to nothing. Reported because the only exit from a form can
  /// be one of these, but no click can reach it.
  case noLayoutBox = "no_layout_box"
  case notVisible = "not_visible"
  case disabled
  /// Scrolled out of the viewport. Recoverable with element_scroll_into_view.
  case offViewport = "off_viewport"
  /// Another element occupies the target's own centre, which is how Material paints a
  /// checkbox over its input.
  case covered
}

public enum WebKitFrameActionMode: String, Codable, Equatable, Sendable {
  case hoverJavaScript = "hover_javascript"
  case selectOptionJavaScript = "select_option_javascript"
  case pressKeyNativeAppKit = "press_key_native_appkit"
  case fillNativeAppKit = "fill_native_appkit"
}

public enum ObservedBoundingBoxCoordinateSpace: String, Codable, Equatable, Sendable {
  case frameViewport = "frame_viewport"
}

public enum ObservedValidationState: String, Codable, Equatable, Sendable {
  case valid
  case invalid
  case notApplicable = "not_applicable"
}

public enum WebKitDeniedPermission: String, Codable, Equatable, Sendable {
  case geolocation
  case camera
  case microphone
  case cameraAndMicrophone = "camera_and_microphone"
  /// A future WebKit capture kind is still denied and reported rather than silently
  /// inheriting a more permissive default.
  case mediaCapture = "media_capture"
}

public struct WebKitPermissionDenial: Codable, Equatable, Sendable {
  public let origin: String
  public let permission: WebKitDeniedPermission
  public let frameIsMain: Bool
  public let requestCount: UInt64
  public let lastDeniedAtMonotonicNanoseconds: UInt64
}

public struct WebKitPageObservation: Codable, Equatable, Sendable {
  public let observationID: String
  public let generation: UInt64
  public let documentID: String
  public let url: ProvenancedText
  public let title: ProvenancedText
  public let readyState: String
  public let mutationCount: UInt64
  public let elements: [WebKitObservedElement]
  public let totalElementCount: Int
  public let elementOffset: Int
  public let nextElementOffset: Int?
  /// The page held more than this observation returned. An agent that reads a partial
  /// observation as the whole page concludes things are absent that are on screen —
  /// which is how a complete declaration was reported to a user as missing.
  public var isPartial: Bool { totalElementCount > elements.count }
  /// Frames whose content could not be read at all. Same-origin frames are walked and
  /// registered cross-origin frames are evaluated independently; failures and native
  /// registry overflow stay explicit so a partial page is never reported as complete.
  public let unreadableFrameCount: Int
  /// Everything on this page was both returned and legible. Anything less has to be
  /// said out loud, or an absence gets reported as a fact.
  public var isComplete: Bool {
    !isPartial && unreadableFrameCount == 0 && pendingDialog == nil
  }
  public let semanticTextTruncated: Bool
  public let crossOriginFramesOpaque: Bool
  /// Controls the raw DOM renders, counted independently of the semantic matcher.
  public let renderedInteractiveCount: Int
  /// Visible text counts once, plus every rendered interactive control or visual-media
  /// element. Zero is stronger than an empty semantic tree: it means the settled page
  /// exposes no usable rendered content at all.
  public let renderedContentCount: Int
  public var contentState: PageContentState {
    if pendingDialog != nil { return .unknown }
    return renderedContentCount == 0 ? .emptyOrUnusable : .usable
  }
  /// Rendered controls dropped only because an ancestor is aria-hidden or inert.
  /// A page that paints its controls and marks them hidden leaves an empty tree for
  /// a reason the caller must be able to see.
  /// The interface language the page declares. A postcondition written against an
  /// English label fails silently on a French console, and nothing said which it was.
  public let documentLanguage: String?
  public let ariaHiddenDropCount: Int
  /// Controls dropped only because nothing up their row has a layout box. They cannot
  /// be clicked, but the only exit from a form can be one of them, so they are named
  /// rather than silently withheld.
  public let unrenderedControlCount: Int
  public let unrenderedControlNames: [String]
  /// Controls present in the walked tree before any layout filter.
  public let rawControlCount: Int
  /// True when a reported control sits under a fully transparent ancestor. The tree
  /// is usable, but nothing under it is visible to a person right now.
  public let obscuredByAncestorOpacity: Bool
  public let documentElementCount: Int
  public let bodyTextLength: Int
  /// One control described in full, so an empty tree can be diagnosed in one look.
  public let firstControlProbe: String
  public let capturedAtMonotonicNanoseconds: UInt64
  /// The JavaScript panel the page is suspended on, if any. While one is open the
  /// page's script does not run, so nothing else in this observation could be read:
  /// the dialog is the observation.
  public let pendingDialog: WebKitPendingJavaScriptDialog?
  /// Permissions this document asked for and WebKitUI denied. Repeated identical
  /// requests are counted so a polling page cannot grow the observation without bound.
  public let permissionDenials: [WebKitPermissionDenial]
  public let permissionDenialCount: UInt64
  public let permissionDenialsTruncated: Bool
}

public struct WebKitCapture: Sendable {
  public let pngData: Data
  public let width: Int
  public let height: Int
  public let backingScaleFactor: Double
  /// True only when the page actually has layered content that a snapshot can drop.
  /// It used to be hardcoded true, so it warned about nothing and meant nothing.
  public let compositorEffectsMayBeMissing: Bool
  /// What the page was showing when the shutter opened, so an image that disagrees
  /// with the page is detectable instead of believed. A capture is the one tool that
  /// looks like ground truth; it has to be checkable.
  public let topLayerElementCount: Int
  public let modalPresent: Bool
  public let renderedInteractiveCount: Int
}

public struct WebKitScrollResult: Codable, Equatable, Sendable {
  public let x: Double
  public let y: Double
  public let viewportWidth: Double
  public let viewportHeight: Double
  public let documentWidth: Double
  public let documentHeight: Double
  public let reachedTop: Bool
  public let reachedBottom: Bool
  public let observationInvalidated: Bool
}

public struct WebKitTextRegion: Codable, Equatable, Sendable {
  public let kind: String
  public let label: String?
  public let text: String
  public let scrollTop: Double
  public let scrollHeight: Double
  public let clientHeight: Double
}

public struct WebKitTextSnapshot: Codable, Equatable, Sendable {
  public let bodyText: String
  public let regions: [WebKitTextRegion]
  public let truncated: Bool
  public let contentState: PageContentState
  public let renderedContentCount: Int
}

/// A modifier held down for one key press. An explicit set, not a chord string: the
/// confirmation has to state each one, and nothing should have to parse operator text to
/// find out what is being approved.
public enum WebKitKeyModifier: String, Codable, CaseIterable, Equatable, Sendable {
  case control
  case option
  case shift
  case command

  /// Control-Option-Shift-Command, the order macOS writes a chord in.
  static let displayOrder: [WebKitKeyModifier] = [.control, .option, .shift, .command]
}

/// One key press: the key as the DOM names it — `Enter`, `ArrowDown`, `PageUp`, or a
/// single printable character — plus the modifiers held with it.
///
/// The DOM spelling is the wire format deliberately. Trust is measured by an isolated
/// handler in the page comparing `KeyboardEvent.key` against what was asked for, so a
/// second spelling would be a second thing that can disagree with itself.
public struct WebKitKeyPress: Equatable, Sendable, ExpressibleByStringLiteral {
  public let key: String
  public let modifiers: Set<WebKitKeyModifier>

  public init(_ key: String, modifiers: Set<WebKitKeyModifier> = []) {
    self.key = key
    self.modifiers = modifiers
  }

  /// A bare key name stays a bare key press, so every existing `.pressKey("Enter")`
  /// caller keeps meaning exactly what it meant.
  public init(stringLiteral value: String) {
    self.init(value)
  }

  /// The chord as the confirmation states it, and as a refusal names it.
  public var chordDescription: String {
    (WebKitKeyModifier.displayOrder.filter(modifiers.contains).map(\.rawValue) + [key])
      .joined(separator: "+")
  }

  /// The modifiers alone, in the same order, for the labelled section of a confirmation.
  public var modifierDescription: String? {
    let named = WebKitKeyModifier.displayOrder.filter(modifiers.contains).map(\.rawValue)
    return named.isEmpty ? nil : named.joined(separator: "+")
  }
}

/// Everything that decides which keystroke a confirmed key press is, in one place, so the
/// server refuses a key it cannot send before an operator is asked about it and the
/// runtime refuses the same key again at the moment of dispatch.
public enum WebKitKeyCatalogue {
  /// One resolved keystroke: exactly what `NSEvent.keyEvent` needs, decided before the
  /// keyboard is touched so a key that cannot be sent is refused rather than approximated.
  struct NativeKeyEvent {
    let keyCode: UInt16
    let characters: String
    let flags: NSEvent.ModifierFlags
  }

  /// The keys named by their DOM spelling, with the virtual key code AppKit reports for
  /// each. Codes are the `kVK_*` constants from `Carbon/HIToolbox/Events.h`; the
  /// characters are what AppKit puts in an `NSEvent`'s `characters` for that key — a
  /// control character for the four the ASCII table covers, and otherwise the reserved
  /// function-key unicodes from `NSEvent.h` (0xF700–0xF8FF).
  ///
  /// The two delete keys are crossed on purpose. The key labelled Delete on a Mac
  /// keyboard is `kVK_Delete`, and it is the DOM's `Backspace`; the DOM's `Delete` is the
  /// forward delete, `kVK_ForwardDelete`. Reading them the other way round would erase
  /// the character on the wrong side of the caret.
  static let namedKeys: [String: (characters: String, keyCode: UInt16)] = [
    "Enter": ("\r", 0x24),  // kVK_Return
    "Tab": ("\t", 0x30),  // kVK_Tab
    "Escape": ("\u{1B}", 0x35),  // kVK_Escape
    "Backspace": ("\u{8}", 0x33),  // kVK_Delete
    "Delete": ("\u{F728}", 0x75),  // kVK_ForwardDelete, NSDeleteFunctionKey
    "ArrowUp": ("\u{F700}", 0x7E),  // kVK_UpArrow, NSUpArrowFunctionKey
    "ArrowDown": ("\u{F701}", 0x7D),  // kVK_DownArrow, NSDownArrowFunctionKey
    "ArrowLeft": ("\u{F702}", 0x7B),  // kVK_LeftArrow, NSLeftArrowFunctionKey
    "ArrowRight": ("\u{F703}", 0x7C),  // kVK_RightArrow, NSRightArrowFunctionKey
    "Home": ("\u{F729}", 0x73),  // kVK_Home, NSHomeFunctionKey
    "End": ("\u{F72B}", 0x77),  // kVK_End, NSEndFunctionKey
    "PageUp": ("\u{F72C}", 0x74),  // kVK_PageUp, NSPageUpFunctionKey
    "PageDown": ("\u{F72D}", 0x79),  // kVK_PageDown, NSPageDownFunctionKey
  ]

  /// The keys a client may name, for the schema and its refusals.
  public static var keyNames: [String] { namedKeys.keys.sorted() }

  /// Whether this key press can be sent at all, throwing the refusal that says why not.
  /// Asked before an operator is shown anything.
  public static func validate(_ press: WebKitKeyPress) throws {
    _ = try event(for: press)
  }

  /// Resolves a confirmed key press into the one event that means it, or refuses.
  static func event(for press: WebKitKeyPress) throws -> NativeKeyEvent {
    // ⌘ first: whether the key is nameable does not matter if the chord never reaches
    // the page. The dispatch below goes through the window rather than NSApplication, so
    // the main menu is not offered the event — but AppKit's key-equivalent routing is not
    // a contract this product controls, and one of the claimed chords quits the process.
    // A keystroke whose destination cannot be stated is refused, not sent. ⌘A before
    // retyping, the one claimed chord a caller has a real use for, is not lost by this:
    // the native fill path already selects the field's contents before it inserts.
    if press.modifiers.contains(.command), press.key.count == 1,
      let character = press.key.lowercased().first,
      WebKitNativeApplicationMenu.commandKeyEquivalents.contains(character)
    {
      throw WebKitRuntimeError.keyChordReservedByApplicationMenu(press.chordDescription)
    }
    var flags = NSEvent.ModifierFlags()
    if press.modifiers.contains(.control) { flags.insert(.control) }
    if press.modifiers.contains(.option) { flags.insert(.option) }
    if press.modifiers.contains(.shift) { flags.insert(.shift) }
    if press.modifiers.contains(.command) { flags.insert(.command) }

    if let named = namedKeys[press.key] {
      // AppKit sets the function flag for every key in the reserved unicode range, and
      // the numeric-pad flag for the arrows as well. Enter, Tab, Escape and Backspace are
      // in neither set, so those keep the exact mask they were dispatched with before
      // this table existed.
      if let scalar = named.characters.unicodeScalars.first, scalar.value >= 0xF700 {
        flags.insert(.function)
      }
      if ["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"].contains(press.key) {
        flags.insert(.numericPad)
      }
      return NativeKeyEvent(
        keyCode: named.keyCode, characters: named.characters, flags: flags)
    }

    // A single printable character.
    guard press.key.unicodeScalars.count == 1, let scalar = press.key.unicodeScalars.first,
      !CharacterSet.controlCharacters.contains(scalar),
      let character = press.key.first
    else { throw WebKitRuntimeError.keyCodeUnavailable(press.key) }
    guard press.modifiers.isSubset(of: [.command]) else {
      // Control, option and shift each change which character a real keyboard produces:
      // shift+a is A, option+a is å, control+a is U+0001. Sending the requested character
      // with one of those flags raised would be an event no keyboard can generate, and
      // the page would read a keystroke nobody approved. The character wanted is the one
      // to ask for; shift is then inferred from the layout, below.
      throw WebKitRuntimeError.keyModifierChangesCharacter(press.chordDescription)
    }
    guard let derived = virtualKeyCode(for: character) else {
      throw WebKitRuntimeError.keyCodeUnavailable(press.key)
    }
    // `charactersIgnoringModifiers` honours shift and caps lock, so a shifted character
    // is the same string in both fields, exactly as AppKit reports a real ⇧A.
    if derived.shift { flags.insert(.shift) }
    return NativeKeyEvent(keyCode: derived.keyCode, characters: press.key, flags: flags)
  }

  /// The virtual key code that produces `character` on the keyboard layout this Mac is
  /// currently using, and whether shift is needed to reach it.
  ///
  /// Derived, never assumed. A hardcoded US-ANSI table would send `q` where an AZERTY
  /// operator approved `a` — the worst failure this product has, because the confirmation
  /// would have named the other key. The layout itself is asked what each key produces
  /// and the answer is inverted; the lowest code wins, which keeps the main row ahead of
  /// the keypad for the digits. A character no single key reaches — a CJK ideograph, or
  /// anything behind a dead key or option — has no answer here, and the caller refuses.
  private static func virtualKeyCode(for character: Character) -> (keyCode: UInt16, shift: Bool)? {
    guard let layout = currentUnicodeKeyLayout() else { return nil }
    let wanted = String(character)
    return layout.withUnsafeBytes { raw -> (keyCode: UInt16, shift: Bool)? in
      guard let base = raw.baseAddress else { return nil }
      let keyboardLayout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
      let keyboardType = UInt32(LMGetKbdType())
      for shifted in [false, true] {
        // UCKeyTranslate takes the modifier byte of an old Event Manager modifier word.
        let modifierKeyState = shifted ? UInt32(shiftKey >> 8) : UInt32(0)
        for keyCode in UInt16(0)...127 {
          var deadKeyState: UInt32 = 0
          var length = 0
          var produced = [UniChar](repeating: 0, count: 8)
          let status = UCKeyTranslate(
            keyboardLayout, keyCode, UInt16(kUCKeyActionDown), modifierKeyState,
            keyboardType, OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState,
            produced.count, &length, &produced)
          guard status == noErr, length > 0 else { continue }
          if String(utf16CodeUnits: produced, count: length) == wanted {
            return (keyCode, shifted)
          }
        }
      }
      return nil
    }
  }

  private static func currentUnicodeKeyLayout() -> Data? {
    // The layout input source is the one that answers for a keyboard; the current input
    // source is asked as well because an input method occupies that slot and carries no
    // layout data of its own.
    for source in [
      TISCopyCurrentKeyboardLayoutInputSource(), TISCopyCurrentKeyboardInputSource(),
    ] {
      guard let source = source?.takeRetainedValue(),
        let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
      else { continue }
      let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
      if !data.isEmpty { return data }
    }
    return nil
  }
}

public enum WebKitActionOperation: Sendable {
  case click
  case fill(ProvenancedText)
  case pressKey(WebKitKeyPress)
  case blur
  case commitInput
  /// Choose one of a `<select>`'s options by its exact visible label. Never by index:
  /// an index is a structural fact, and a list that re-renders one row shorter would
  /// silently select something else.
  case selectOption(ProvenancedText)
  /// Move the pointer onto a control, as far as an embedder can. See `performSource`
  /// for what a JavaScript pointer cannot do that a real one can.
  case hover
}

public enum WebKitActionDispatchMode: String, Codable, Equatable, Sendable {
  case javascript
  case nativeAppKit = "native_appkit"
}

public struct WebKitActionResult: Codable, Equatable, Sendable {
  public let elementID: String
  public let addressingOutcome: AddressingOutcome
  public let dispatched: Bool
  public let trustedUserGesture: Bool
  public let dispatchMode: WebKitActionDispatchMode
  public let actionMonotonicNanoseconds: UInt64
}

public struct WebKitDownloadReceipt: Codable, Equatable, Sendable {
  public let httpStatus: Int?
  public let suggestedFilename: String
  public let filename: String
  public let mimeType: String?
  public let byteCount: UInt64
  public let sha256: String
  public let provisioningProfileUUID: String?
}

/// Records who chose the files a file panel returned. `agentConfirmed` means the
/// selection was armed by an approved MCP call; `humanPanel` means a person picked
/// the files in the native open panel.
public enum WebKitFileUploadSelectionMode: String, Codable, Equatable, Sendable {
  case agentConfirmed = "agent_confirmed"
  case humanPanel = "human_panel"
}

public struct WebKitFileUploadReceipt: Codable, Equatable, Sendable {
  public let filenames: [String]
  public let byteCounts: [UInt64]
  public let sha256: [String]
  public let fileCount: Int
  public let selectionMode: WebKitFileUploadSelectionMode
  public let selectedByHuman: Bool
  public let localPathsExposed: Bool
  public let monotonicNanoseconds: UInt64
}

/// Which JavaScript panel WebKit is holding open.
///
/// There is deliberately no `beforeUnload` case. The public macOS 27 SDK's
/// `WKUIDelegate.h` declares no before-unload panel at all — no `BeforeUnload` symbol
/// exists in it — so an unload prompt cannot be observed or answered from an embedder,
/// and it is out of scope here rather than quietly mishandled.
public enum WebKitJavaScriptDialogKind: String, Codable, Equatable, Sendable {
  case alert
  case confirm
  case prompt
}

/// One JavaScript panel the page is suspended on, waiting for an answer.
public struct WebKitPendingJavaScriptDialog: Codable, Equatable, Sendable {
  /// Single-use identity an answer is bound to, exactly as a confirmed click is bound
  /// to a re-resolved target.
  public let dialogID: String
  public let kind: WebKitJavaScriptDialogKind
  /// Site-authored, carried with its provenance like every other page string.
  public let message: ProvenancedText
  /// What the site pre-filled a prompt with. Site-authored too.
  public let defaultText: ProvenancedText?
  public let frameOrigin: String?
  public let frameIsMain: Bool
  public let openedAtMonotonicNanoseconds: UInt64
}

public enum WebKitJavaScriptDialogOutcome: String, Codable, Equatable, Sendable {
  case accepted
  case dismissed
  /// Nobody answered inside the window. WebKit is released so neither the page nor the
  /// server can wedge, and the site does then read a cancel — but the outcome says
  /// plainly that no one answered, which is the fact an unimplemented panel destroyed.
  case unansweredTimeout = "indeterminate_unanswered_timeout"
  /// A second panel opened while one was still unanswered. Answering it would either
  /// overwrite the identity an approval was granted against or queue behind a panel
  /// nobody has answered yet, so it is refused and said out loud.
  case refusedConcurrent = "refused_second_dialog"
}

/// How one panel ended. The prompt text a caller supplied is deliberately not here:
/// this record is exported, and a prompt carries whatever the operator typed.
public struct WebKitJavaScriptDialogRecord: Codable, Equatable, Sendable {
  public let dialogID: String
  public let kind: WebKitJavaScriptDialogKind
  public let outcome: WebKitJavaScriptDialogOutcome
  public let valueSupplied: Bool
  public let monotonicNanoseconds: UInt64
}

public struct FormSubmissionAuditEvent: Codable, Equatable, Sendable {
  public let payloadHMAC: String
  public let httpMethod: String
  public let formValueCount: Int
  public let sourceFrameIsMain: Bool
  public let targetFrameIsMain: Bool
  public let monotonicNanoseconds: UInt64
}

public struct WebContentTerminationEvent: Codable, Equatable, Sendable {
  public let documentID: String
  public let observationID: String?
  public let monotonicNanoseconds: UInt64
}

/// A value-only view used when frame-local observations are combined. The retained
/// `WKFrameInfo` never crosses the runtime boundary, and this metadata is not yet
/// model-visible.
struct WebKitFrameCapabilitySnapshot: Equatable, Sendable {
  let capabilityID: String
  let origin: String
  let isMainFrame: Bool
}

struct WebKitFrameRegistrySnapshot: Equatable, Sendable {
  let capabilities: [WebKitFrameCapabilitySnapshot]
  let droppedRegistrationCount: UInt64
}

enum WebKitFrameDocumentProbe: Equatable, Sendable {
  case available(title: String)
  case unavailable
}

/// What WebKit reported it was about to submit. Values are deliberately absent: a form
/// carries passwords, card numbers and one-time codes, and this receipt is exported.
public struct WebKitSubmissionFacts: Codable, Equatable, Sendable {
  public let origin: String?
  public let httpMethod: String
  public let fieldCount: Int
  /// Field names only, bounded. A name is a schema; a value is a secret.
  public let fieldNames: [String]
}

/// One new window the page asked for and did not get.
///
/// The refusal of a second tab is the product's, and it stands: one session holds one
/// exclusive host lease, which is what lets an approval name an unambiguous page. What
/// changes is that the request is now said out loud. Until this existed, WebKit's own
/// default for an unimplemented `createWebViewWith` applied — the navigation was
/// cancelled and nil handed back — so a `target="_blank"` invoice link did nothing and
/// reported nothing, and a click on one was indistinguishable from a click that missed.
///
/// A link the person or agent activated in the main frame is followed in the same view
/// (`followedInSameView`), under the same navigation policy as a link without a target:
/// the origin lock applies, and a foreign destination is refused as a cross-origin
/// redirect. Anything else, `window.open()` from script above all, is not followed; the
/// agent reads `destination` and asks for it through `browser_navigate`.
public struct WebKitSuppressedNewWindowRequest: Codable, Equatable, Sendable {
  /// Origin and path with every query value redacted, sanitised exactly as an observed
  /// `href` is: a statement or invoice link routinely carries a session token in its
  /// query, and this record is exported. Nil when the address is not http(s), or carries
  /// embedded credentials, or has no readable origin.
  public let destination: String?
  /// WebKit's own classification of what asked: `link_activated` for `target="_blank"`,
  /// `other` for a `window.open()` call.
  public let navigationType: String
  public let sourceFrameIsMain: Bool
  public let monotonicNanoseconds: UInt64
  /// True when the destination was loaded in this view instead of a new window.
  public let followedInSameView: Bool
  // `WKWindowFeatures` is deliberately absent. Every field on it — the width, height and
  // toolbar flags the page asked for — is site-authored data, and recording it would put
  // unlabelled site content in an exported receipt to no benefit: the product refuses the
  // window whatever shape the site wanted it in.
}

/// AppKit keeps titled windows on a display, which would drag the offscreen layout
/// host back into view. Declining the constraint is what lets the window stay parked
/// outside every screen while WebKit still lays its content out.
private final class UnconstrainedWindow: NSWindow {
  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
    frameRect
  }
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
  weak var target: (any WKScriptMessageHandler)?

  init(target: any WKScriptMessageHandler) {
    self.target = target
  }

  func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    target?.userContentController(userContentController, didReceive: message)
  }
}

@MainActor
public final class WebKitRuntime: NSObject, WKNavigationDelegate, WKDownloadDelegate, WKUIDelegate,
  WKScriptMessageHandler
{
  public let webView: WKWebView

  private let instrumentationWorld: WKContentWorld
  private let managesApplicationActivationPolicy: Bool
  private var documentID = UUID().uuidString
  private var observationGeneration: UInt64 = 0
  private var navigationFailure: WebKitRuntimeError?
  private var armedNavigationActor: (actor: WebKitNavigationActor, expiresAt: UInt64)?
  private var navigationAuditEvents: [WebKitNavigationAuditEvent] = []
  private var processTerminated = false
  private var latestObservationID: String?
  private var latestTargets: [String: ObservedTargetRecord] = [:]
  private var addressingCounters = AddressingCounterSnapshot()
  private var controlState: InteractionControlState = .agentControlled
  private var handoffEvents: [HandoffAuditEvent] = []
  private var browserWindow: NSWindow?
  private weak var humanControlInstruction: NSTextField?
  private weak var humanControlCompletionButton: NSButton?
  private weak var humanCredentialButton: NSButton?
  private var humanControlActivationObserver: (any NSObjectProtocol)?
  /// The SiliconPass client behind the human control bar's fill button. Set by the
  /// production registry; nil hides the button, so no test or bare runtime shows it.
  public var humanCredentialFiller: (any CredentialBrokerFilling)?
  /// The one form the person asked to fill, in the frame that holds it. Cleared
  /// when the fill completes, fails, or control changes hands.
  private var pendingHumanCredentialFill:
    (binding: CredentialSinkFormBinding, frameInfo: WKFrameInfo?, token: String)?
  private var topLevelOriginLock: SecurityOrigin?
  private let formAuditKey = SymmetricKey(size: .bits256)
  private var formSubmissionEvents: [FormSubmissionAuditEvent] = []
  private var submissionFacts: WebKitSubmissionFacts?
  /// The origin the human approved for the action in flight, set where the confirmed
  /// action is dispatched and superseded by the next navigation, not by the action
  /// returning: WebKit delivers the submission hook on its own schedule.
  private var approvedSubmissionOrigin: String?
  private var pendingSubmissionDecision: SubmissionApproval.Decision?
  private var webContentTerminationEvents: [WebContentTerminationEvent] = []
  private var lastCommittedHTTPURL: URL?
  /// Navigation type is captured from WebKit's main-frame policy callback and applied
  /// only after that navigation finishes. A failed POST must not mark the page that
  /// remained behind as a form result.
  private var pendingMainFrameNavigationType: WKNavigationType?
  private var currentDocumentWasFormSubmission = false
  private var formSubmissionHistoryItems: Set<ObjectIdentifier> = []
  private var permissionDenials: [WebKitPermissionDenial] = []
  private var permissionDenialCount: UInt64 = 0
  private var permissionDenialsTruncated = false
  private var registeredFrameCapabilities: [RegisteredFrameCapability] = []
  /// Never serialized. Prevents a low-entropy third-party label from being recovered
  /// by guessing the digest in a public frame recipe's semantic identity.
  private var frameSemanticKey = SymmetricKey(size: .bits256)
  private var droppedFrameRegistrationCount: UInt64 = 0
  /// Advances for every document-start frame registration. A child navigation does not
  /// replace the main document ID, so observation races need this second generation to
  /// distinguish the frame tree they started reading from the one they would publish.
  private var frameRegistrationGeneration: UInt64 = 0
  private var frameObservationRaceToken: UInt64 = 0
  private var frameObservationRaceContinuations:
    [UInt64: CheckedContinuation<RawObservation, any Error>] = [:]
  /// The most recent new window the page asked for and was refused. Held until the
  /// document is replaced, so an observation can say a request is still outstanding, and
  /// cleared in `resetForNavigation()` so a later action cannot inherit an older page's
  /// suppression.
  private var suppressedNewWindowRequest: WebKitSuppressedNewWindowRequest?
  private var authenticationUIClassification: AuthenticationUIClassification?
  private var restrictedAuthenticationFrameOrigin: String?
  private var restrictedWebAuthnOrigin: String?
  private var pendingCrossOriginNavigationRequest: URLRequest?
  private let egressProxy: PinnedSOCKSProxy?
  private var armedNativeGestureTokens: [String: ArmedNativeGestureContext] = [:]
  private var nativeGestureReceipts: [String: [NativeGestureReceipt]] = [:]
  private let downloadDestinationProvider: (@MainActor @Sendable (String) async -> URL?)?
  private let uploadSelectionProvider: (@MainActor @Sendable (Bool, Bool) async -> [URL]?)?
  private var lastUploadReceipt: WebKitFileUploadReceipt?
  private var armedUploadSelection: [URL]?
  private var filePickerVisible = false
  private var downloadContinuation: CheckedContinuation<WebKitDownloadReceipt, any Error>?
  private var downloadExpectedOrigin: SecurityOrigin?
  private var downloadDestination: URL?
  private var downloadMIMEType: String?
  private var downloadHTTPStatus: Int?
  private var downloadSuggestedFilename: String?
  private var downloadExpectedProvisioningProfileUUID: String?
  private var downloadStarted = false
  private var downloadActionVerified = false
  private var completedDownloadReceipt: WebKitDownloadReceipt?
  private var activeDownload: WKDownload?
  private var downloadTimeoutTask: Task<Void, Never>?
  /// How long one unanswered JavaScript panel is held before it resolves indeterminate.
  /// It exists so that a panel nobody answers bounds every wait behind it instead of
  /// suspending the page, and the server, for as long as the site likes.
  private let javaScriptDialogAnswerTimeout: Duration
  private var pendingJavaScriptDialogState: PendingJavaScriptDialogState?
  private var javaScriptDialogTimeoutTask: Task<Void, Never>?
  private var lastJavaScriptDialogRecord: WebKitJavaScriptDialogRecord?
  private var dialogRaceToken: UInt64 = 0
  /// Keyed rather than single, so two overlapping dispatches cannot steal each other's
  /// continuation: a stolen one is never resumed, and a continuation nobody resumes is
  /// an unbounded wait — the one failure this whole feature exists to avoid.
  private var dialogRaceContinuations:
    [UInt64: CheckedContinuation<ActionDispatchRace, any Error>] = [:]

  public override convenience init() {
    self.init(websiteDataStore: .default())
  }

  public convenience init(websiteDataStore: WKWebsiteDataStore) {
    self.init(websiteDataStore: websiteDataStore, egressProxy: nil)
  }

  public convenience init(protectedWebsiteDataStore: WKWebsiteDataStore) throws {
    let proxy = try PinnedSOCKSProxy()
    protectedWebsiteDataStore.proxyConfigurations = [proxy.proxyConfiguration()]
    self.init(websiteDataStore: protectedWebsiteDataStore, egressProxy: proxy)
  }

  init(
    websiteDataStore: WKWebsiteDataStore,
    egressProxy: PinnedSOCKSProxy?,
    managesApplicationActivationPolicy: Bool = true,
    downloadDestinationProvider: (@MainActor @Sendable (String) async -> URL?)? = nil,
    uploadSelectionProvider:
      (@MainActor @Sendable (Bool, Bool) async -> [URL]?)? = nil,
    javaScriptDialogAnswerTimeout: Duration = .seconds(30)
  ) {
    self.javaScriptDialogAnswerTimeout = javaScriptDialogAnswerTimeout
    self.egressProxy = egressProxy
    self.managesApplicationActivationPolicy = managesApplicationActivationPolicy
    self.downloadDestinationProvider = downloadDestinationProvider
    self.uploadSelectionProvider = uploadSelectionProvider
    let configuration = WKWebViewConfiguration()
    let contentController = WKUserContentController()
    let world = WKContentWorld.world(name: "WebKitUIMCP.Instrumentation")
    contentController.addUserScript(
      WKUserScript(
        source: Self.frameRegistrationSource,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false,
        in: world
      )
    )
    contentController.addUserScript(
      WKUserScript(
        source: Self.instrumentationSource,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false,
        in: world
      )
    )
    configuration.userContentController = contentController
    configuration.websiteDataStore = websiteDataStore
    // The agent lands on pages nobody picked by hand, so WebKit's own fraudulent-site
    // check stays on by decision rather than by inherited default.
    //
    // It is not free of privacy cost, and an earlier version of this comment claimed it
    // was. Apple's Safari privacy notice names Google Safe Browsing and Apple, and
    // Tencent for mainland China and Hong Kong regions; it says the actual website
    // address is never shared, and that Google may log the IP address. Apple never
    // describes the protocol as hashed or prefixed, and WebKit hands the full NSURL to a
    // closed framework, so nothing here may assert one. It runs on main-frame and
    // subframe navigations, per URL in a redirect chain, and never on subresources.
    // A local denylist evaluated before the confirmation is the place for anything
    // stricter, and it is the only option that makes no request at all.
    configuration.preferences.isFraudulentWebsiteWarningEnabled = true

    self.instrumentationWorld = world
    self.webView = WKWebView(
      frame: .init(x: 0, y: 0, width: 1280, height: 800),
      configuration: configuration
    )
    super.init()
    // A WKWebView that belongs to no window can lay out to nothing: the DOM is
    // built and readable while every control reports a zero-sized box, so the
    // semantic tree comes back empty on a page that is perfectly loaded. Measured
    // on Play Console: 690 elements, 35 controls, 764 characters of text, zero
    // rendered. Hosting the view in an offscreen window from the start gives the
    // engine a real viewport without ever showing anything.
    _ = makeBrowserWindow()
    contentController.add(
      WeakScriptMessageHandler(target: self),
      contentWorld: world,
      name: Self.nativeGestureMessageHandlerName)
    contentController.add(
      WeakScriptMessageHandler(target: self),
      contentWorld: world,
      name: Self.frameRegistrationMessageHandlerName)
    webView.navigationDelegate = self
    webView.uiDelegate = self
    _ = makeBrowserWindow()
    keepPageVisibleWhileParked()
    // Park now rather than on the first observation: a page loaded or navigated
    // before anything observed it ran with its window ordered out, hidden.
    ensureLayoutViewport()
  }

  /// An ordered-in window is retained by AppKit's window list, and it holds the web
  /// view: without this a closed session kept its view, its web process and its
  /// website data store alive for the life of the broker.
  isolated deinit {
    browserWindow?.orderOut(nil)
    browserWindow?.contentView = nil
    browserWindow?.close()
  }

  /// The parked layout host sits outside every display, so macOS reports it occluded
  /// and WebKit marks the page hidden: `visibilityState` is `hidden` and animation
  /// frames never run. A Material dialog waits on a frame to insert its content, so
  /// after a handoff the backdrop covered the page and no dialog control ever
  /// appeared (Play Console, 2026-09-23; measured `hidden`, 0 frames). No public API
  /// decouples page visibility from window occlusion, so this uses WebKit's own
  /// switch, checked before use; without it the page keeps the previous behaviour.
  /// Distribution is a notarized direct download, where this is permitted.
  private func keepPageVisibleWhileParked() {
    let getter = Selector(("_windowOcclusionDetectionEnabled"))
    let setter = Selector(("_setWindowOcclusionDetectionEnabled:"))
    guard webView.responds(to: getter), webView.responds(to: setter),
      let implementation = webView.method(for: setter)
    else { return }
    // Key-value coding cannot reach an underscored accessor, and `perform(_:with:)`
    // would pass a non-nil object where the method expects NO.
    typealias SetBool = @convention(c) (AnyObject, Selector, ObjCBool) -> Void
    unsafeBitCast(implementation, to: SetBool.self)(webView, setter, false)
  }

  public func navigate(
    to url: URL,
    timeout: Duration = .seconds(30),
    quietWindow: Duration = .milliseconds(300),
    constrainToInitialOrigin: Bool = false
  ) async throws -> WebKitNavigationResult {
    try requireAgentControl()
    pendingCrossOriginNavigationRequest = nil
    guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
      throw WebKitRuntimeError.unsupportedURLScheme
    }
    if egressProxy != nil {
      guard let host = url.host else { throw WebKitRuntimeError.networkBoundaryDenied }
      do {
        try PublicNetworkAddressPolicy().validateNavigationHost(host)
      } catch {
        throw WebKitRuntimeError.networkBoundaryDenied
      }
      // The pinned proxy refuses a name that resolves only to private space — a
      // Tailscale 100.64.0.0/10 address, say — and WebKit reported that as
      // NSURLErrorDomain -1000, which read like a malformed URL and invited retries
      // (Home Assistant over Tailscale, 2026-09-23). Resolve with the proxy's own
      // policy first and say what it is. The proxy still decides every connection.
      let resolution = await Task.detached {
        Result { try PublicNetworkAddressPolicy().resolve(host) }
      }.value
      if case .failure(PublicNetworkAddressPolicyError.noPublicAddress) = resolution {
        let origin = navigationOrigin(for: url).map(Self.sanitizedOrigin) ?? "unavailable"
        let port = UInt16(url.port ?? (url.scheme?.lowercased() == "http" ? 80 : 443))
        let tailnet = await Task.detached {
          (try? PublicNetworkAddressPolicy().resolveTailnet(host)) != nil
        }.value
        guard tailnet else { throw WebKitRuntimeError.privateNetworkDestination(origin: origin) }
        guard TailnetOriginGrants.shared.isGranted(host: host, port: port) else {
          throw WebKitRuntimeError.tailnetDestinationRequiresApproval(origin: origin)
        }
      }
    }
    if constrainToInitialOrigin {
      guard let origin = navigationOrigin(for: url) else {
        throw WebKitRuntimeError.unsupportedURLScheme
      }
      topLevelOriginLock = origin
    }
    return try await load(
      request: URLRequest(url: url),
      timeout: timeout,
      quietWindow: quietWindow
    )
  }

  /// Continues the exact GET/HEAD redirect request retained inside WebKitUI
  /// after a separately approved cross-origin transition. The request URL,
  /// path, query, headers, and cookies are never returned through MCP.
  public func continueApprovedCrossOriginNavigation(
    timeout: Duration = .seconds(30),
    quietWindow: Duration = .milliseconds(300)
  ) async throws -> WebKitNavigationResult {
    try requireAgentControl()
    guard
      let request = pendingCrossOriginNavigationRequest,
      let url = request.url,
      let origin = navigationOrigin(for: url)
    else { throw WebKitRuntimeError.noPendingCrossOriginNavigation }
    pendingCrossOriginNavigationRequest = nil
    topLevelOriginLock = origin
    return try await load(request: request, timeout: timeout, quietWindow: quietWindow)
  }

  public func discardPendingCrossOriginNavigation() {
    pendingCrossOriginNavigationRequest = nil
  }

  public static let viewportWidthRange = 320...3_840
  public static let viewportHeightRange = 240...2_160

  /// Changes only the CSS-pixel viewport of the existing desktop WebKit document.
  /// Device/mobile emulation is deliberately absent: the public macOS SDK exposes no
  /// `ContentMode` API for WKWebView. Media emulation is likewise not inferred from a
  /// size; this is a layout operation, not a claim to be another device.
  public func setViewport(width: Int, height: Int) async throws -> WebKitViewportChangeResult {
    try requireAgentControl()
    guard Self.viewportWidthRange.contains(width), Self.viewportHeightRange.contains(height) else {
      throw WebKitRuntimeError.invalidViewportSize(width: width, height: height)
    }
    let previousWidth = Int(webView.bounds.width.rounded())
    let previousHeight = Int(webView.bounds.height.rounded())
    let changed = previousWidth != width || previousHeight != height
    if changed {
      let window = browserWindow ?? makeBrowserWindow()
      window.setContentSize(NSSize(width: width, height: height))
      webView.needsLayout = true
      webView.needsDisplay = true
      webView.layoutSubtreeIfNeeded()
      await awaitViewportSettled()
      invalidateCurrentObservation()
    }
    return WebKitViewportChangeResult(
      previousWidth: previousWidth,
      previousHeight: previousHeight,
      width: Int(webView.bounds.width.rounded()),
      height: Int(webView.bounds.height.rounded()),
      layoutChanged: changed,
      observationInvalidated: changed)
  }

  /// Returns WebKit's own exact target. The URL remains process-local; callers project
  /// it through `agentSafeURL` before it reaches a confirmation or MCP response.
  public func historyDestination(for operation: WebKitHistoryOperation) throws -> URL {
    try requireAgentControl()
    let destination: URL?
    switch operation {
    case .back:
      destination = webView.backForwardList.backItem?.url
    case .forward:
      destination = webView.backForwardList.forwardItem?.url
    case .reload:
      guard !reloadCouldResubmitForm else {
        throw WebKitRuntimeError.formSubmissionReloadRefused
      }
      destination = webView.url ?? lastCommittedHTTPURL
    }
    guard let destination else {
      throw WebKitRuntimeError.historyEntryUnavailable(operation)
    }
    guard
      let scheme = destination.scheme?.lowercased(), ["http", "https"].contains(scheme),
      destination.host != nil, destination.user == nil, destination.password == nil
    else { throw WebKitRuntimeError.networkBoundaryDenied }
    return destination
  }

  public func navigateHistory(
    _ operation: WebKitHistoryOperation,
    expectedDestination: URL,
    timeout: Duration = .seconds(30),
    quietWindow: Duration = .milliseconds(300)
  ) async throws -> WebKitNavigationResult {
    try requireAgentControl()
    let liveDestination = try historyDestination(for: operation)
    guard liveDestination == expectedDestination else {
      throw WebKitRuntimeError.historyDestinationChanged
    }
    if egressProxy != nil, let host = liveDestination.host {
      do {
        try PublicNetworkAddressPolicy().validateNavigationHost(host)
      } catch {
        throw WebKitRuntimeError.networkBoundaryDenied
      }
    }
    guard let origin = navigationOrigin(for: liveDestination) else {
      throw WebKitRuntimeError.unsupportedURLScheme
    }
    topLevelOriginLock = origin
    try validate(quietWindow: quietWindow)
    resetForNavigation()
    armNavigationActor(.agentNavigation)
    let started = DispatchTime.now().uptimeNanoseconds
    let navigation: WKNavigation?
    let destinationItemID: ObjectIdentifier?
    switch operation {
    case .back:
      guard let item = webView.backForwardList.backItem, item.url == liveDestination else {
        throw WebKitRuntimeError.historyDestinationChanged
      }
      destinationItemID = ObjectIdentifier(item)
      navigation = webView.go(to: item)
    case .forward:
      guard let item = webView.backForwardList.forwardItem, item.url == liveDestination else {
        throw WebKitRuntimeError.historyDestinationChanged
      }
      destinationItemID = ObjectIdentifier(item)
      navigation = webView.go(to: item)
    case .reload:
      // `historyDestination` checked this before confirmation and again above. Keep the
      // explicit guard adjacent to dispatch so a future preview refactor cannot reopen
      // form replay.
      guard !reloadCouldResubmitForm else {
        throw WebKitRuntimeError.formSubmissionReloadRefused
      }
      destinationItemID = webView.backForwardList.currentItem.map(ObjectIdentifier.init)
      navigation = webView.reload()
    }
    guard navigation != nil else {
      throw WebKitRuntimeError.historyEntryUnavailable(operation)
    }
    let readiness = try await awaitReadiness(timeout: timeout, quietWindow: quietWindow)
    if readiness == .deadlineReached { webView.stopLoading() }
    guard await historyListSettled(after: operation, at: destinationItemID) else {
      throw WebKitRuntimeError.navigationTimedOut
    }
    let state = try await instrumentationState(includeContentState: readiness == .ready)
    let contentState = readiness == .ready ? state.contentState ?? .unknown : .unknown
    await refreshAuthenticationUIClassification()
    rememberRecoverableURL(webView.url ?? liveDestination)
    processTerminated = false
    let loadedURL = webView.url ?? liveDestination
    return WebKitNavigationResult(
      documentID: documentID,
      url: agentSafeURLString(loadedURL) ?? "about:blank",
      requestedURL: agentSafeURLString(liveDestination) ?? "about:blank",
      readiness: readiness,
      contentState: contentState,
      elapsedNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
      mutationCount: state.mutationCount)
  }

  private var reloadCouldResubmitForm: Bool {
    if currentDocumentWasFormSubmission { return true }
    switch pendingMainFrameNavigationType {
    case .formSubmitted?, .formResubmitted?: return true
    default: return false
    }
  }

  /// `webView.url` can change one callback before the back/forward list moves its
  /// cursor. Returning in that gap makes an immediate inverse operation look absent.
  /// Bound the wait rather than sleeping a fixed duration or claiming the list is ready
  /// from the URL alone.
  private func historyListSettled(
    after operation: WebKitHistoryOperation,
    at destinationItemID: ObjectIdentifier?,
    timeout: Duration = .seconds(1)
  ) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
      let currentMatches =
        destinationItemID.map {
          webView.backForwardList.currentItem.map(ObjectIdentifier.init) == $0
        } ?? (webView.url != nil && !webView.isLoading)
      let inverseExists: Bool
      switch operation {
      case .back:
        inverseExists = webView.backForwardList.forwardItem != nil
      case .forward:
        inverseExists = webView.backForwardList.backItem != nil
      case .reload:
        inverseExists = true
      }
      if currentMatches && inverseExists { return true }
      try? await Task.sleep(for: .milliseconds(20))
    }
    return false
  }

  /// Useful for deterministic fixtures and local benchmarks. A non-nil base
  /// URL determines the page's security origin.
  public func loadHTML(
    _ html: String,
    baseURL: URL?,
    timeout: Duration = .seconds(10),
    quietWindow: Duration = .milliseconds(100)
  ) async throws -> WebKitNavigationResult {
    try requireAgentControl()
    try validate(quietWindow: quietWindow)
    resetForNavigation()
    armNavigationActor(.agentNavigation)
    let started = DispatchTime.now().uptimeNanoseconds
    webView.loadHTMLString(html, baseURL: baseURL)
    let readiness = try await awaitReadiness(timeout: timeout, quietWindow: quietWindow)
    if readiness == .deadlineReached { webView.stopLoading() }
    let state = try await instrumentationState(includeContentState: readiness == .ready)
    let contentState = readiness == .ready ? state.contentState ?? .unknown : .unknown
    await refreshAuthenticationUIClassification()
    let loadedURL = webView.url ?? baseURL
    return WebKitNavigationResult(
      documentID: documentID,
      url: agentSafeURLString(loadedURL) ?? "about:blank",
      // loadHTML is asked for a base URL and lands on it, so the two agree by
      // construction; the field exists for the request that does not.
      requestedURL: baseURL.flatMap(agentSafeURLString) ?? "about:blank",
      readiness: readiness,
      contentState: contentState,
      elapsedNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
      mutationCount: state.mutationCount
    )
  }

  /// How many of a `<select>`'s options one observation publishes. A country list is 250
  /// entries and a list of every timezone is more, and a payload that does not fit a
  /// client is a payload that does not work — so the list is bounded like every other
  /// list here, and `optionsTruncated` says when it cut one. Sized for the ordinary long
  /// control — a month, a title, a quantity, a set of provinces — to arrive whole.
  public static let maximumPublishedOptions = 64

  public func observe(
    maximumElements: Int = 200,
    elementOffset: Int = 0,
    maximumFieldCharacters: Int = 4_096,
    roles: [String] = [],
    nameContains: String? = nil,
    hydrationTimeout: Duration = .seconds(30)
  ) async throws -> WebKitPageObservation {
    try requireObservationControl()
    guard maximumElements > 0, elementOffset >= 0, maximumFieldCharacters > 0 else {
      throw WebKitRuntimeError.malformedInstrumentationResult
    }
    if let dialog = pendingJavaScriptDialogState?.dialog {
      return try dialogPendingObservation(dialog)
    }
    guard !processTerminated else { throw WebKitRuntimeError.webContentProcessTerminated }
    let observedDocumentID = documentID
    await bindFrameCapabilitiesToIsolatedWorld()
    let observedFrameRegistrationGeneration = frameRegistrationGeneration

    let (collectionLimit, collectionLimitOverflow) = elementOffset.addingReportingOverflow(
      maximumElements)
    guard !collectionLimitOverflow else {
      throw WebKitRuntimeError.malformedInstrumentationResult
    }
    let script = Self.observationSource.replacingOccurrences(
      of: "__MAXIMUM_ELEMENTS__",
      with: String(collectionLimit)
    )
    let arguments: [String: Any] = [
      "roleFilters": roles.map { $0.lowercased() },
      "nameFilter": nameContains?.lowercased() ?? "",
      // Each document group is filtered before serialization but not paginated on its
      // own. Native code applies one slice after the unique groups are combined.
      "elementOffset": 0,
      "maximumFieldCharacters": maximumFieldCharacters,
      "maximumOptions": Self.maximumPublishedOptions,
    ]
    func captureRawObservation(in frame: WKFrameInfo? = nil) async throws -> RawObservation {
      if let frame {
        return try await captureFrameRawObservation(
          script: script, arguments: arguments, frame: frame, timeout: .seconds(2))
      }
      guard
        let json = try await webView.callAsyncJavaScript(
          script, arguments: arguments, in: frame, contentWorld: instrumentationWorld) as? String,
        let data = json.data(using: .utf8),
        let decoded = try? JSONDecoder().decode(RawObservation.self, from: data)
      else { throw WebKitRuntimeError.malformedInstrumentationResult }
      return decoded
    }

    let hydrationDeadline = ContinuousClock.now + hydrationTimeout
    ensureLayoutViewport()
    webView.layoutSubtreeIfNeeded()
    var raw = try await captureRawObservation()
    while raw.transientLoading, ContinuousClock.now < hydrationDeadline {
      // WKWebView can be idle while a single-page app is still showing its
      // loading shell. Keep this observation alive until hydration completes.
      try await Task.sleep(for: .milliseconds(100))
      webView.needsLayout = true
      webView.layoutSubtreeIfNeeded()
      raw = try await captureRawObservation()
    }
    if raw.elements.isEmpty, raw.unfilteredCandidateCount > 0 {
      // A foreground/layout transition can leave WebKit geometry stale for one
      // turn. Refresh locally instead of requiring a human handoff as a cache bust.
      webView.needsLayout = true
      webView.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(50))
      raw = try await captureRawObservation()
    }

    var capturedGroups = [
      CapturedObservationGroup(raw: raw, frameCapabilityID: nil, frameOrigin: nil)
    ]
    var walkedFrameCapabilityIDs = Set(raw.walkedFrameCapabilityIDs)
    let registeredFrames = registeredFrameCapabilities.filter {
      $0.documentID == documentID && !$0.isMainFrame
    }
    for frame in registeredFrames where !walkedFrameCapabilityIDs.contains(frame.capabilityID) {
      do {
        let frameRaw = try await captureRawObservation(in: frame.frameInfo)
        guard
          frameRaw.walkedFrameCapabilityIDs.contains(frame.capabilityID),
          URL(string: frameRaw.url).flatMap(Self.sanitizedOrigin(for:)) == frame.origin
        else {
          registeredFrameCapabilities.removeAll { $0.capabilityID == frame.capabilityID }
          continue
        }
        capturedGroups.append(
          CapturedObservationGroup(
            raw: frameRaw,
            frameCapabilityID: frame.capabilityID,
            frameOrigin: frame.origin))
        walkedFrameCapabilityIDs.formUnion(frameRaw.walkedFrameCapabilityIDs)
      } catch {
        registeredFrameCapabilities.removeAll { $0.capabilityID == frame.capabilityID }
      }
    }

    guard documentID == observedDocumentID else { throw WebKitRuntimeError.staleObservation }
    guard frameRegistrationGeneration == observedFrameRegistrationGeneration else {
      throw WebKitRuntimeError.staleObservation
    }
    guard !processTerminated else { throw WebKitRuntimeError.webContentProcessTerminated }

    let (nextGeneration, overflow) = observationGeneration.addingReportingOverflow(1)
    guard !overflow else { throw WebKitRuntimeError.malformedInstrumentationResult }
    observationGeneration = nextGeneration
    let observationID = UUID().uuidString
    let origin = Self.securityOrigin(from: webView.url)
    let pageSource = ProvenanceSource(
      classification: .firstPartySiteContent,
      documentID: documentID,
      frameID: "main",
      securityOrigin: origin
    )
    let toolSource = ProvenanceSource(
      classification: .toolResult,
      documentID: documentID,
      frameID: "main",
      securityOrigin: origin
    )
    let enteredDataSource = ProvenanceSource(
      classification: .userEnteredSiteData,
      documentID: documentID,
      frameID: "main",
      securityOrigin: origin
    )

    let capturedElements = capturedGroups.enumerated().flatMap { groupIndex, group in
      group.raw.elements.map { (groupIndex: groupIndex, element: $0) }
    }
    let selectedElements = Array(
      capturedElements.dropFirst(elementOffset).prefix(maximumElements))
    let candidateCountIsLowerBound =
      elementOffset > 0 || capturedElements.count > maximumElements
      || capturedGroups.contains { $0.raw.totalElementCount > $0.raw.elements.count }
    // Build the complete frame-local recipe first. Its text stays native-only; the
    // public recipe carries a keyed identity for verification across observations.
    let resolutionRecipes = try selectedElements.enumerated().map { index, captured in
      let elementID = "e\(index + 1)"
      let group = capturedGroups[captured.groupIndex]
      return try locatorRecipe(
        for: captured.element,
        peers: group.raw.elements,
        elementID: elementID,
        observationID: observationID,
        generation: nextGeneration)
    }
    // Third-party text deliberately stays out of the public locator recipe because
    // that model has no provenance-bearing strings. The keyed identity is opaque and
    // stable only within this document and exact native frame capability.
    let recipes = try selectedElements.enumerated().map { index, captured in
      let group = capturedGroups[captured.groupIndex]
      guard let frameCapabilityID = group.frameCapabilityID else {
        return resolutionRecipes[index]
      }
      return try frameLocatorRecipe(
        for: captured.element,
        elementID: "e\(index + 1)",
        observationID: observationID,
        generation: nextGeneration,
        opaqueSemanticIdentity: frameSemanticIdentity(
          capabilityID: frameCapabilityID,
          privateIdentity: resolutionRecipes[index].semanticIdentity))
    }
    let elements = try selectedElements.enumerated().map { index, captured in
      let elementID = "e\(index + 1)"
      let recipe = recipes[index]
      let element = captured.element
      let group = capturedGroups[captured.groupIndex]
      let candidates = group.raw.elements.map(locatorCandidate)
      let resolution = LocatorResolver.resolve(recipe: recipe, candidates: candidates)
      let quality = locatorQuality(
        recipe: recipe,
        candidateCount: resolution.finalCandidateCount,
        candidateCountIsLowerBound: candidateCountIsLowerBound)
      let embedded = group.frameCapabilityID != nil
      let reportedFrameOrigin =
        element.frameCapabilityID.flatMap { capabilityID in
          registeredFrameCapabilities.first { $0.capabilityID == capabilityID }?.origin
        } ?? group.frameOrigin
      let embeddedOrigin = reportedFrameOrigin.flatMap { value in
        URL(string: value).flatMap(Self.securityOrigin(from:))
      }
      let contentSource =
        embedded
        ? ProvenanceSource(
          classification: .thirdPartyEmbed,
          documentID: documentID,
          frameID: "embedded",
          securityOrigin: embeddedOrigin)
        : pageSource
      return try WebKitObservedElement(
        elementID: elementID,
        frameOrigin: embedded ? reportedFrameOrigin : nil,
        frameIsMain: embedded ? false : nil,
        tag: ProvenancedText(text: element.tag, source: contentSource),
        role: try element.role.map { try ProvenancedText(text: $0, source: contentSource) },
        accessibleName: try element.accessibleName.map {
          try ProvenancedText(text: $0, source: contentSource)
        },
        // A destination is currently an unprovenanced String in this public model. Do
        // not launder one out of a third-party frame while every action is refused.
        submissionDestination: embedded ? nil : element.submissionDestination,
        label: try element.label.map { try ProvenancedText(text: $0, source: contentSource) },
        text: try element.text.map { try ProvenancedText(text: $0, source: contentSource) },
        value: try element.value.map {
          // An input's value is data entered into the site. A select's observable value
          // is different: the injected source deliberately exports the selected option's
          // visible label, which the site authored. Calling that label user-entered data
          // contradicts selectedOption and options, and launders hostile option text into
          // a provenance class the page does not own.
          let source =
            embedded ? contentSource : (element.tag == "select" ? pageSource : enteredDataSource)
          return try ProvenancedText(text: $0, source: source)
        },
        validationState: ObservedValidationState(rawValue: element.validationState)
          ?? .notApplicable,
        characterCount: element.characterCount,
        sensitive: element.sensitive,
        submitsForm: element.submitsForm,
        disabled: element.disabled,
        checked: element.checked,
        selected: element.selected,
        selectedOption: try element.selectedOption.map {
          try ProvenancedText(text: $0, source: contentSource)
        },
        options: try element.options.map { published in
          try published.map {
            ObservedOption(
              label: try ProvenancedText(text: $0.label, source: contentSource),
              selected: $0.selected,
              disabled: $0.disabled)
          }
        },
        optionCount: element.optionCount,
        optionsTruncated: element.optionsTruncated,
        stateAttributes: try element.stateAttributes.mapValues {
          try ProvenancedText(text: $0, source: contentSource)
        },
        contextAnchors: try element.contextAnchors.compactMap { anchor in
          guard let kind = ObservedContextAnchorKind(rawValue: anchor.kind) else { return nil }
          return ObservedContextAnchor(
            kind: kind,
            text: try ProvenancedText(text: anchor.text, source: contentSource))
        },
        stableAttributes: try element.stableAttributes.mapValues {
          try ProvenancedText(text: $0, source: contentSource)
        },
        visible: element.visible,
        actionability: embedded
          ? .crossOriginFrameNativeGeometryUnavailable
          : ObservedActionability(rawValue: element.actionability) ?? .actionable,
        frameActionModes: embedded ? Self.frameActionModes(for: element) : nil,
        boundingBoxCoordinateSpace: embedded ? .frameViewport : nil,
        boundingBox: element.boundingBox,
        locatorRecipe: recipe,
        locatorQuality: quality
      )
    }
    latestObservationID = observationID
    latestTargets = Dictionary(
      uniqueKeysWithValues: zip(elements, selectedElements).enumerated().map {
        index, pair in
        let (element, captured) = pair
        let group = capturedGroups[captured.groupIndex]
        let resolutionRecipe = resolutionRecipes[index]
        let resolution = LocatorResolver.resolve(
          recipe: resolutionRecipe,
          candidates: group.raw.elements.map(locatorCandidate))
        return (
          element.elementID,
          ObservedTargetRecord(
            recipe: element.locatorRecipe,
            resolutionRecipe: resolutionRecipe,
            physicalIdentity: captured.element.physicalIdentity,
            boundingBox: captured.element.boundingBox,
            sensitive: captured.element.sensitive,
            disabled: captured.element.disabled,
            checked: captured.element.checked,
            selected: captured.element.selected,
            selectedOption: captured.element.selectedOption,
            stateAttributes: captured.element.stateAttributes,
            frameCapabilityID: group.frameCapabilityID,
            frameOrigin: element.frameOrigin,
            maximumFieldCharacters: maximumFieldCharacters,
            observedAtMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds,
            observedCandidateCount: resolution.finalCandidateCount
          )
        )
      }
    )

    func saturatedSum(_ values: [Int]) -> Int {
      values.reduce(0) { partial, value in
        let (sum, overflow) = partial.addingReportingOverflow(value)
        return overflow ? Int.max : sum
      }
    }
    let totalElementCount = saturatedSum(capturedGroups.map(\.raw.totalElementCount))
    let encounteredOpaqueFrameCount = saturatedSum(
      capturedGroups.map(\.raw.crossOriginFrameCount))
    let successfullyReadOpaqueFrameCount = max(0, capturedGroups.count - 1)
    var unreadableFrameCount = max(
      0, encounteredOpaqueFrameCount - successfullyReadOpaqueFrameCount)
    if droppedFrameRegistrationCount > 0 { unreadableFrameCount = max(1, unreadableFrameCount) }
    let unrenderedControlNames = Array(
      Set(capturedGroups.flatMap(\.raw.unrenderedControlNames)).sorted().prefix(10))

    let observation = WebKitPageObservation(
      observationID: observationID,
      generation: nextGeneration,
      documentID: documentID,
      // `location.href` is exact instrumentation data and may carry session/token
      // values in its query. Preserve the live URL locally for recovery below, but put
      // only the redacted form into the model-visible observation and every digest that
      // derives from it.
      url: try ProvenancedText(
        text: URL(string: raw.url).map(Self.agentSafeURL) ?? "unavailable",
        source: toolSource),
      title: try ProvenancedText(text: raw.title, source: pageSource),
      readyState: raw.readyState,
      mutationCount: raw.mutationCount,
      elements: elements,
      totalElementCount: totalElementCount,
      elementOffset: elementOffset,
      nextElementOffset: elementOffset + elements.count < totalElementCount
        ? elementOffset + elements.count : nil,
      unreadableFrameCount: unreadableFrameCount,
      semanticTextTruncated: capturedGroups.contains { $0.raw.semanticTextTruncated },
      crossOriginFramesOpaque: unreadableFrameCount > 0,
      renderedInteractiveCount: saturatedSum(
        capturedGroups.map(\.raw.renderedInteractiveCount)),
      renderedContentCount: saturatedSum(capturedGroups.map(\.raw.renderedContentCount)),
      documentLanguage: raw.documentLanguage,
      ariaHiddenDropCount: saturatedSum(capturedGroups.map(\.raw.ariaHiddenDropCount)),
      unrenderedControlCount: saturatedSum(
        capturedGroups.map(\.raw.unrenderedControlCount)),
      unrenderedControlNames: unrenderedControlNames,
      rawControlCount: saturatedSum(capturedGroups.map(\.raw.rawControlCount)),
      obscuredByAncestorOpacity: capturedGroups.contains {
        $0.raw.obscuredByAncestorOpacity
      },
      documentElementCount: saturatedSum(capturedGroups.map(\.raw.documentElementCount)),
      bodyTextLength: saturatedSum(capturedGroups.map(\.raw.bodyTextLength)),
      firstControlProbe: raw.firstControlProbe,
      capturedAtMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds,
      pendingDialog: nil,
      permissionDenials: permissionDenials,
      permissionDenialCount: permissionDenialCount,
      permissionDenialsTruncated: permissionDenialsTruncated
    )
    rememberRecoverableURL(URL(string: raw.url) ?? webView.url)
    if controlState == .resumeRequested {
      transition(to: .freshlyReobserved, observationID: observationID)
    }
    return observation
  }

  public func scrollBy(deltaX: Double, deltaY: Double) async throws -> WebKitScrollResult {
    try requireAgentControl()
    guard deltaX.isFinite, deltaY.isFinite else {
      throw WebKitRuntimeError.malformedInstrumentationResult
    }
    return try await performScroll(
      source: Self.pageScrollSource,
      arguments: ["deltaX": deltaX, "deltaY": deltaY]
    )
  }

  public func scrollElementIntoView(
    observationID: String,
    elementID: String
  ) async throws -> WebKitScrollResult {
    try requireAgentControl()
    let recipe = try locatorRecipe(observationID: observationID, elementID: elementID)
    guard let target = latestTargets[elementID] else { throw WebKitRuntimeError.unknownElement }
    try requireMainFrameActionTarget(target)
    let criteria = locatorCriteria(
      recipe, expectedEnabled: !target.disabled,
      maximumFieldCharacters: target.maximumFieldCharacters)
    let resolution = try await resolveTarget(
      criteria: criteria, scrollIntoView: true)
    guard resolution.count == 1 else {
      throw WebKitRuntimeError.targetNotUnique(
        resolution.count, pinned: resolution.pinnedState ?? "not_requested")
    }
    return try await performScroll(
      source: Self.nearestScrollStateSource,
      arguments: [
        "criteria": criteria, "physicalIdentity": "", "expectedCandidateCount": 0,
      ]
    )
  }

  public func readText(maximumCharacters: Int = 20_000) async throws -> WebKitTextSnapshot {
    try requireAgentControl()
    guard maximumCharacters > 0 else {
      throw WebKitRuntimeError.malformedInstrumentationResult
    }
    ensureLayoutViewport()
    webView.layoutSubtreeIfNeeded()
    guard
      let json = try await webView.callAsyncJavaScript(
        Self.textSnapshotSource,
        arguments: ["maximumCharacters": maximumCharacters],
        in: nil,
        contentWorld: instrumentationWorld
      ) as? String,
      let data = json.data(using: .utf8),
      let snapshot = try? JSONDecoder().decode(WebKitTextSnapshot.self, from: data)
    else { throw WebKitRuntimeError.malformedInstrumentationResult }
    return snapshot
  }

  public func capture() async throws -> WebKitCapture {
    try requireAgentControl()
    guard !processTerminated else { throw WebKitRuntimeError.webContentProcessTerminated }
    webView.layoutSubtreeIfNeeded()
    let configuration = WKSnapshotConfiguration()
    configuration.rect = webView.bounds
    configuration.snapshotWidth = NSNumber(value: webView.bounds.width)
    let image = try await webView.takeSnapshot(configuration: configuration)
    guard
      let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
    else {
      throw WebKitRuntimeError.malformedInstrumentationResult
    }
    let onScreen = try await captureDOMState()
    return WebKitCapture(
      pngData: png,
      width: bitmap.pixelsWide,
      height: bitmap.pixelsHigh,
      backingScaleFactor: Double(bitmap.pixelsWide) / webView.bounds.width,
      compositorEffectsMayBeMissing: onScreen.topLayerElementCount > 0
        || onScreen.compositedLayerCount > 0,
      topLayerElementCount: onScreen.topLayerElementCount,
      modalPresent: onScreen.modalPresent,
      renderedInteractiveCount: onScreen.renderedInteractiveCount
    )
  }

  /// Read at snapshot time, so the two describe the same instant.
  private func captureDOMState() async throws -> RawCaptureDOMState {
    guard
      let json = try await webView.callAsyncJavaScript(
        Self.captureStateSource, arguments: [:], in: nil, contentWorld: instrumentationWorld
      ) as? String,
      let data = json.data(using: .utf8),
      let state = try? JSONDecoder().decode(RawCaptureDOMState.self, from: data)
    else { throw WebKitRuntimeError.malformedInstrumentationResult }
    return state
  }

  public func addressingCounterSnapshot() -> AddressingCounterSnapshot {
    addressingCounters
  }

  public func locatorRecipe(observationID: String, elementID: String) throws -> LocatorRecipe {
    try requireAgentControl()
    guard observationID == latestObservationID else { throw WebKitRuntimeError.staleObservation }
    guard let target = latestTargets[elementID] else { throw WebKitRuntimeError.unknownElement }
    return target.recipe
  }

  /// Captures the exact native address used by the private credential sink.
  /// This API is intentionally absent from the MCP server/tool catalogue.
  public func credentialFormBinding(
    observationID: String,
    usernameElementID: String,
    passwordElementID: String
  ) throws -> CredentialSinkFormBinding {
    try requireAgentControl()
    guard !processTerminated,
      observationID == latestObservationID,
      usernameElementID != passwordElementID,
      let username = latestTargets[usernameElementID],
      let password = latestTargets[passwordElementID],
      username.frameCapabilityID == nil,
      password.frameCapabilityID == nil,
      !username.sensitive,
      password.sensitive,
      username.recipe.observationGeneration == password.recipe.observationGeneration,
      let url = webView.url
    else { throw WebKitRuntimeError.invalidCredentialBinding }

    let origin: CredentialSinkOrigin
    do {
      origin = try CredentialSinkOrigin(url: url)
    } catch {
      throw WebKitRuntimeError.invalidCredentialOrigin
    }
    return CredentialSinkFormBinding(
      origin: origin,
      documentID: documentID,
      observationID: observationID,
      observationGeneration: username.recipe.observationGeneration,
      usernameTarget: CredentialSinkElementBinding(
        elementID: usernameElementID,
        physicalElementIdentity: username.physicalIdentity
      ),
      passwordTarget: CredentialSinkElementBinding(
        elementID: passwordElementID,
        physicalElementIdentity: password.physicalIdentity
      )
    )
  }

  /// Binds the sign-in form a person is looking at, for a fill they asked for from
  /// the human control bar. Unlike `credentialFormBinding`, this needs no agent
  /// observation: it runs only while a person holds the window, and it may bind a
  /// restricted authentication frame such as idmsa.apple.com, because the values go
  /// from SiliconPass into that frame and never to the agent.
  public func humanCredentialFormBinding() async throws -> CredentialSinkFormBinding {
    pendingHumanCredentialFill = nil
    guard controlState == .humanControlled, !processTerminated else {
      throw WebKitRuntimeError.invalidCredentialBinding
    }
    let token = UUID().uuidString
    var frames: [(WKFrameInfo?, String)] = [(nil, "main")]
    for capability in registeredFrameCapabilities
    where capability.documentID == documentID && !capability.isMainFrame {
      frames.append((capability.frameInfo, capability.capabilityID))
    }
    var found: [(frameInfo: WKFrameInfo?, focused: Bool)] = []
    for (frameInfo, _) in frames {
      guard
        let json = try? await webView.callAsyncJavaScript(
          Self.humanCredentialLocateSource, arguments: ["token": token],
          in: frameInfo, contentWorld: instrumentationWorld) as? String,
        let data = json.data(using: .utf8),
        let result = try? JSONDecoder().decode(RawHumanCredentialLocation.self, from: data),
        result.found
      else { continue }
      found.append((frameInfo, result.focused))
    }
    // The frame the person is typing in wins; otherwise the form must be unique.
    let focused = found.filter(\.focused)
    guard let chosen = focused.count == 1 ? focused.first : (found.count == 1 ? found.first : nil)
    else { throw WebKitRuntimeError.invalidCredentialBinding }
    // A child frame is bound to its own origin: idmsa.apple.com, not the page
    // that embeds it. SiliconPass matches the saved sign-in by that exact host.
    let securityOrigin = chosen.frameInfo?.securityOrigin
    let origin: CredentialSinkOrigin
    if let securityOrigin {
      guard securityOrigin.protocol == "https" else {
        throw WebKitRuntimeError.invalidCredentialOrigin
      }
      origin = try CredentialSinkOrigin(
        scheme: securityOrigin.protocol, asciiHost: securityOrigin.host,
        effectivePort: securityOrigin.port == 0 ? 443 : securityOrigin.port)
    } else {
      guard let url = webView.url, url.scheme == "https" else {
        throw WebKitRuntimeError.invalidCredentialOrigin
      }
      origin = try CredentialSinkOrigin(url: url)
    }
    let binding = CredentialSinkFormBinding(
      origin: origin,
      documentID: documentID,
      observationID: "human-\(token)",
      observationGeneration: frameRegistrationGeneration,
      usernameTarget: CredentialSinkElementBinding(
        elementID: "human-username", physicalElementIdentity: "human-username-\(token)"),
      passwordTarget: CredentialSinkElementBinding(
        elementID: "human-password", physicalElementIdentity: "human-password-\(token)"))
    pendingHumanCredentialFill = (binding, chosen.frameInfo, token)
    return binding
  }

  /// Private sink for a fill the person asked for. It types into the two fields
  /// through AppKit, as a person or Safari's AutoFill would, so the page sees real
  /// input events and enables its sign-in button. It never submits the form.
  public func performHumanCredentialFill(
    binding: CredentialSinkFormBinding,
    username: CredentialSecretBuffer,
    password: CredentialSecretBuffer
  ) async throws -> CredentialSinkReceipt {
    defer {
      username.wipe()
      password.wipe()
      pendingHumanCredentialFill = nil
    }
    guard controlState == .humanControlled, !processTerminated,
      let pending = pendingHumanCredentialFill,
      pending.binding == binding,
      binding.documentID == documentID,
      let window = webView.window
    else { throw WebKitRuntimeError.invalidCredentialBinding }
    let values = [
      ("username", try username.asciiString(maximumBytes: 320)),
      ("password", try password.asciiString(maximumBytes: 1_024)),
    ]
    for (field, value) in values {
      guard
        let json = try? await webView.callAsyncJavaScript(
          Self.humanCredentialFocusSource,
          arguments: ["token": pending.token, "field": field],
          in: pending.frameInfo, contentWorld: instrumentationWorld) as? String,
        let data = json.data(using: .utf8),
        let focus = try? JSONDecoder().decode(RawHumanCredentialFocus.self, from: data)
      else { throw WebKitRuntimeError.invalidCredentialBinding }
      if focus.skip { continue }
      guard focus.focused, window.makeFirstResponder(webView) else {
        throw WebKitRuntimeError.invalidCredentialBinding
      }
      webView.selectAll(nil)
      webView.insertText(value)
    }
    return CredentialSinkReceipt(status: .filled)
  }

  @objc private func fillWithSiliconPass() {
    guard let filler = humanCredentialFiller else { return }
    humanCredentialButton?.isEnabled = false
    Task { @MainActor [weak self] in
      guard let self else { return }
      defer { self.humanCredentialButton?.isEnabled = true }
      let message: String
      let color: NSColor
      do {
        let binding = try await self.humanCredentialFormBinding()
        let status = try await filler.fillForHuman(binding: binding, runtime: self).status
        (message, color) = Self.humanCredentialStatusText(status)
      } catch WebKitRuntimeError.invalidCredentialBinding {
        message = Self.localizedHandoff(
          "No sign-in form with a password field is visible.",
          fallback: "No sign-in form with a password field is visible.")
        color = .systemOrange
      } catch {
        (message, color) = Self.humanCredentialStatusText(.failed)
      }
      self.pendingHumanCredentialFill = nil
      self.humanControlInstruction?.stringValue = message
      self.humanControlInstruction?.textColor = color
      if let instruction = self.humanControlInstruction {
        NSAccessibility.post(element: instruction, notification: .valueChanged)
      }
    }
  }

  private static func humanCredentialStatusText(
    _ status: CredentialBrokerWireStatus
  ) -> (String, NSColor) {
    switch status {
    case .filled:
      return (
        localizedHandoff(
          "Filled by SiliconPass. Check the fields, then sign in.",
          fallback: "Filled by SiliconPass. Check the fields, then sign in."),
        .systemGreen
      )
    case .credentialNotFound:
      return (
        localizedHandoff(
          "SiliconPass has no saved sign-in for this site.",
          fallback: "SiliconPass has no saved sign-in for this site."),
        .systemOrange
      )
    case .cancelled, .denied, .userPresenceUnavailable:
      return (
        localizedHandoff(
          "SiliconPass fill was cancelled.", fallback: "SiliconPass fill was cancelled."),
        .secondaryLabelColor
      )
    case .changed, .stale, .failed:
      return (
        localizedHandoff(
          "SiliconPass is unavailable. Open and unlock SiliconPass, then try again.",
          fallback: "SiliconPass is unavailable. Open and unlock SiliconPass, then try again."),
        .systemRed
      )
    }
  }

  /// Captures exactly three password fields for an assisted rotation. This is
  /// private runtime state and is never exposed as a secret-bearing API.
  public func credentialRotationBinding(
    observationID: String,
    currentPasswordElementID: String,
    newPasswordElementID: String,
    confirmationElementID: String
  ) throws -> CredentialSinkRotationBinding {
    try requireAgentControl()
    let ids = [currentPasswordElementID, newPasswordElementID, confirmationElementID]
    guard !processTerminated,
      observationID == latestObservationID,
      Set(ids).count == ids.count,
      let current = latestTargets[currentPasswordElementID],
      let new = latestTargets[newPasswordElementID],
      let confirmation = latestTargets[confirmationElementID],
      current.frameCapabilityID == nil,
      new.frameCapabilityID == nil,
      confirmation.frameCapabilityID == nil,
      current.sensitive, new.sensitive, confirmation.sensitive,
      current.recipe.observationGeneration == new.recipe.observationGeneration,
      new.recipe.observationGeneration == confirmation.recipe.observationGeneration,
      let url = webView.url
    else { throw WebKitRuntimeError.invalidCredentialBinding }
    let origin = try CredentialSinkOrigin(url: url)
    return CredentialSinkRotationBinding(
      origin: origin,
      documentID: documentID,
      observationID: observationID,
      observationGeneration: current.recipe.observationGeneration,
      currentPasswordTarget: .init(
        elementID: currentPasswordElementID,
        physicalElementIdentity: current.physicalIdentity
      ),
      newPasswordTarget: .init(
        elementID: newPasswordElementID,
        physicalElementIdentity: new.physicalIdentity
      ),
      confirmationTarget: .init(
        elementID: confirmationElementID,
        physicalElementIdentity: confirmation.physicalIdentity
      )
    )
  }

  /// Private native sink. It resolves only the two physical nodes captured in
  /// `credentialFormBinding`; semantic fallback and form submission are absent.
  public func performCredentialFill(
    binding: CredentialSinkFormBinding,
    username: CredentialSecretBuffer,
    password: CredentialSecretBuffer
  ) async throws -> CredentialSinkReceipt {
    defer {
      username.wipe()
      password.wipe()
    }
    try requireAgentControl()
    guard !processTerminated,
      binding.documentID == documentID,
      binding.observationID == latestObservationID,
      let liveURL = webView.url,
      let liveOrigin = try? CredentialSinkOrigin(url: liveURL),
      liveOrigin == binding.origin,
      let usernameTarget = latestTargets[binding.usernameTarget.elementID],
      let passwordTarget = latestTargets[binding.passwordTarget.elementID],
      usernameTarget.frameCapabilityID == nil,
      passwordTarget.frameCapabilityID == nil,
      usernameTarget.recipe.observationGeneration == binding.observationGeneration,
      passwordTarget.recipe.observationGeneration == binding.observationGeneration,
      usernameTarget.physicalIdentity == binding.usernameTarget.physicalElementIdentity,
      passwordTarget.physicalIdentity == binding.passwordTarget.physicalElementIdentity,
      !usernameTarget.sensitive,
      passwordTarget.sensitive
    else { throw WebKitRuntimeError.invalidCredentialBinding }

    let usernameString = try username.asciiString(maximumBytes: 320)
    let passwordString = try password.asciiString(maximumBytes: 1_024)
    let arguments: [String: Any] = [
      "usernamePhysicalIdentity": binding.usernameTarget.physicalElementIdentity,
      "passwordPhysicalIdentity": binding.passwordTarget.physicalElementIdentity,
      "usernameExpectedBox": Self.boxDictionary(usernameTarget.boundingBox),
      "passwordExpectedBox": Self.boxDictionary(passwordTarget.boundingBox),
      "username": usernameString,
      "password": passwordString,
    ]
    guard
      let json = try await webView.callAsyncJavaScript(
        Self.credentialFillSource,
        arguments: arguments,
        in: nil,
        contentWorld: instrumentationWorld
      ) as? String,
      let data = json.data(using: .utf8),
      let result = try? JSONDecoder().decode(RawCredentialFillResult.self, from: data),
      result.filled
    else { throw WebKitRuntimeError.invalidCredentialBinding }

    return CredentialSinkReceipt(status: .filled)
  }

  public func performCredentialRotationFill(
    binding: CredentialSinkRotationBinding,
    currentPassword: CredentialSecretBuffer,
    newPassword: CredentialSecretBuffer
  ) async throws -> CredentialSinkReceipt {
    defer {
      currentPassword.wipe()
      newPassword.wipe()
    }
    try requireAgentControl()
    let targetBindings = [
      binding.currentPasswordTarget,
      binding.newPasswordTarget,
      binding.confirmationTarget,
    ]
    guard !processTerminated,
      binding.documentID == documentID,
      binding.observationID == latestObservationID,
      Set(targetBindings.map(\.elementID)).count == 3,
      let liveURL = webView.url,
      let liveOrigin = try? CredentialSinkOrigin(url: liveURL),
      liveOrigin == binding.origin,
      let current = latestTargets[binding.currentPasswordTarget.elementID],
      let new = latestTargets[binding.newPasswordTarget.elementID],
      let confirmation = latestTargets[binding.confirmationTarget.elementID],
      current.frameCapabilityID == nil,
      new.frameCapabilityID == nil,
      confirmation.frameCapabilityID == nil,
      current.recipe.observationGeneration == binding.observationGeneration,
      new.recipe.observationGeneration == binding.observationGeneration,
      confirmation.recipe.observationGeneration == binding.observationGeneration,
      current.physicalIdentity == binding.currentPasswordTarget.physicalElementIdentity,
      new.physicalIdentity == binding.newPasswordTarget.physicalElementIdentity,
      confirmation.physicalIdentity == binding.confirmationTarget.physicalElementIdentity,
      current.sensitive, new.sensitive, confirmation.sensitive
    else { throw WebKitRuntimeError.invalidCredentialBinding }

    let currentString = try currentPassword.asciiString(maximumBytes: 1_024)
    let newString = try newPassword.asciiString(maximumBytes: 1_024)
    let arguments: [String: Any] = [
      "currentIdentity": binding.currentPasswordTarget.physicalElementIdentity,
      "newIdentity": binding.newPasswordTarget.physicalElementIdentity,
      "confirmationIdentity": binding.confirmationTarget.physicalElementIdentity,
      "currentBox": Self.boxDictionary(current.boundingBox),
      "newBox": Self.boxDictionary(new.boundingBox),
      "confirmationBox": Self.boxDictionary(confirmation.boundingBox),
      "currentPassword": currentString,
      "newPassword": newString,
    ]
    guard
      let json = try await webView.callAsyncJavaScript(
        Self.credentialRotationFillSource,
        arguments: arguments,
        in: nil,
        contentWorld: instrumentationWorld
      ) as? String,
      let data = json.data(using: .utf8),
      let result = try? JSONDecoder().decode(RawCredentialFillResult.self, from: data),
      result.filled
    else { throw WebKitRuntimeError.invalidCredentialBinding }
    return CredentialSinkReceipt(status: .filled)
  }

  public func preflightResolution(
    observationID: String,
    elementID: String
  ) async throws -> LocatorResolution {
    let recipe = try locatorRecipe(observationID: observationID, elementID: elementID)
    guard let target = latestTargets[elementID] else { throw WebKitRuntimeError.unknownElement }
    let frameContext = try frameActionContext(for: target)
    // The transaction refuses before dispatch on this count, so it has to resolve the
    // same way the dispatch does. Without the identity and the population it saw four
    // identical buttons and stopped, while the actuation path would have reached the
    // right one — the write was refused by its own preflight.
    let resolution = try await resolveTarget(
      criteria: actionLocatorCriteria(for: target, publicRecipe: recipe),
      scrollIntoView: false,
      physicalIdentity: target.physicalIdentity,
      expectedCandidateCount: target.observedCandidateCount,
      frameContext: frameContext)
    return LocatorResolution(
      recipeElementID: elementID,
      evaluations: (0..<resolution.count).map {
        LocatorCandidateEvaluation(
          candidateID: "candidate-\($0)",
          requiredFailures: [],
          corroboratingMatches: 0,
          corroboratingAvailable: 0
        )
      }
    )
  }

  /// Re-resolves the observed control and reads where it would send data now. This is
  /// intentionally separate from the observation snapshot: a page can mutate a form's
  /// action while the caller is deciding what to do, and the confirmation must describe
  /// the live control that will be acted on rather than the destination it used to have.
  public func liveSubmissionDestination(
    observationID: String,
    elementID: String
  ) async throws -> String? {
    try requireAgentControl()
    guard observationID == latestObservationID else { throw WebKitRuntimeError.staleObservation }
    guard let target = latestTargets[elementID] else { throw WebKitRuntimeError.unknownElement }
    guard !processTerminated else { throw WebKitRuntimeError.webContentProcessTerminated }
    try requireMainFrameActionTarget(target)

    let resolution = try await resolveTarget(
      criteria: locatorCriteria(
        target.recipe, expectedEnabled: !target.disabled,
        maximumFieldCharacters: target.maximumFieldCharacters),
      scrollIntoView: false,
      physicalIdentity: target.physicalIdentity,
      expectedCandidateCount: target.observedCandidateCount)
    try recordCardinality(
      resolution.count, target: target, eliminatedBy: resolution.eliminatedBy ?? [],
      pinnedState: resolution.pinnedState ?? "not_requested")
    guard let candidate = resolution.candidate else {
      throw WebKitRuntimeError.malformedInstrumentationResult
    }
    return candidate.submissionDestination
  }

  public func perform(
    observationID: String,
    elementID: String,
    operation: WebKitActionOperation,
    dispatchMode: WebKitActionDispatchMode = .javascript,
    stabilityInterval: Duration = .milliseconds(50)
  ) async throws -> WebKitActionResult {
    try requireAgentControl()
    guard observationID == latestObservationID else { throw WebKitRuntimeError.staleObservation }
    guard let target = latestTargets[elementID] else { throw WebKitRuntimeError.unknownElement }
    guard !processTerminated else { throw WebKitRuntimeError.webContentProcessTerminated }
    let frameContext = try frameActionContext(for: target)

    let criteria = actionLocatorCriteria(for: target, publicRecipe: target.recipe)
    let first = try await resolveTarget(
      criteria: criteria, scrollIntoView: frameContext == nil,
      physicalIdentity: target.physicalIdentity,
      expectedCandidateCount: target.observedCandidateCount,
      frameContext: frameContext)
    do {
      try recordCardinality(
        first.count, target: target, eliminatedBy: first.eliminatedBy ?? [],
        pinnedState: first.pinnedState ?? "not_requested")
    } catch {
      if frameContext != nil { invalidateCurrentObservation() }
      throw error
    }
    guard let firstCandidate = first.candidate else {
      if first.count == 0 {
        throw WebKitRuntimeError.targetNotFound(first.eliminatedBy ?? [])
      }
      throw WebKitRuntimeError.targetNotUnique(
        first.count, pinned: first.pinnedState ?? "not_requested")
    }
    if frameContext != nil {
      let physicalIdentity: EvidenceComparison =
        firstCandidate.physicalIdentity == target.physicalIdentity ? .same : .different
      let geometry: EvidenceComparison =
        Self.boxesMatch(
          firstCandidate.boundingBox, target.boundingBox) ? .same : .different
      let actionTime = DispatchTime.now().uptimeNanoseconds
      let attempt: AddressingAttempt
      do {
        attempt = try AddressingAttempt(
          observationID: observationID,
          locatorRecipeID: elementID,
          observationGeneration: target.recipe.observationGeneration,
          actionGeneration: observationGeneration,
          observationMonotonicNanoseconds: target.observedAtMonotonicNanoseconds,
          actionMonotonicNanoseconds: actionTime,
          finalCandidateCount: first.count,
          semanticComparison: .same,
          physicalIdentity: physicalIdentity,
          geometryComparison: geometry)
      } catch {
        throw WebKitRuntimeError.staleObservation
      }
      addressingCounters.record(AddressingClassifier.classify(attempt))
      guard geometry == .same else {
        invalidateCurrentObservation()
        throw WebKitRuntimeError.targetGeometryChanged
      }
      switch (operation, dispatchMode) {
      case (.hover, .javascript):
        guard !target.sensitive else {
          throw WebKitRuntimeError.sensitiveInputRequiresHuman
        }
      case (.selectOption, .javascript):
        guard !target.sensitive else {
          throw WebKitRuntimeError.sensitiveInputRequiresHuman
        }
      case (.pressKey, .nativeAppKit):
        guard !target.sensitive else {
          throw WebKitRuntimeError.sensitiveInputRequiresHuman
        }
      case (.fill, .nativeAppKit):
        guard !target.sensitive else {
          throw WebKitRuntimeError.sensitiveInputRequiresHuman
        }
      case (.click, .nativeAppKit):
        throw WebKitRuntimeError.crossOriginNativeGeometryUnavailable(
          target.frameOrigin ?? "unavailable")
      default:
        throw WebKitRuntimeError.crossOriginFrameActionUnavailable(
          target.frameOrigin ?? "unavailable")
      }
    }
    try await Task.sleep(for: stabilityInterval)

    let value: String?
    let operationName: String
    var keyPress: WebKitKeyPress?
    switch operation {
    case .click:
      operationName = "click"
      value = nil
    case .fill(let provenancedValue):
      guard !target.sensitive else { throw WebKitRuntimeError.sensitiveInputRequiresHuman }
      operationName = "fill"
      value = provenancedValue.segments.map(\.text).joined()
    case .pressKey(let press):
      operationName = "press_key"
      value = press.key
      keyPress = press
    case .blur:
      operationName = "blur"
      value = nil
    case .commitInput:
      operationName = "commit_input"
      value = nil
    case .selectOption(let provenancedLabel):
      // A `<select>` carrying a card type or a security question is as sensitive as a
      // text field carrying the same thing, and the rule is already written.
      guard !target.sensitive else { throw WebKitRuntimeError.sensitiveInputRequiresHuman }
      operationName = "select_option"
      value = provenancedLabel.segments.map(\.text).joined()
    case .hover:
      operationName = "hover"
      value = nil
    }

    // Ambiguity is refused before the gesture, not resolved after it. The count is
    // reported for the same reason `targetNotUnique` reports one: a client told only
    // "no" goes looking for a second option that may not exist.
    if operationName == "select_option", let label = value {
      let survey = try await surveySelectedOption(
        criteria: criteria, physicalIdentity: target.physicalIdentity,
        expectedCandidateCount: target.observedCandidateCount, label: label,
        alreadyDispatched: false, frameContext: frameContext)
      guard survey.matchingOptionCount == 1 else {
        throw WebKitRuntimeError.optionLabelNotUnique(survey.matchingOptionCount ?? 0)
      }
    }

    armNavigationActor(.agentAction)
    // The origin the operator's approval was granted on: the page the confirmation named.
    // WKFormInfo then reports where a submission would actually go, and a destination
    // outside this origin is refused in the navigation policy handler. Like the armed
    // actor, this is not cleared when the action returns — WebKit delivers the submission
    // hook on its own schedule, and clearing early would refuse the very submission the
    // operator approved. A fresh navigation supersedes it.
    approvedSubmissionOrigin =
      frameContext?.origin
      ?? (webView.url ?? lastCommittedHTTPURL).flatMap(Self.sanitizedOrigin(for:))
    let expectedBoundingBox = firstCandidate.boundingBox
    let physicalIdentityHint = target.physicalIdentity
    let expectedCandidateCount = target.observedCandidateCount
    let race = try await dispatchRacingJavaScriptDialog { [self] in
      if dispatchMode == .nativeAppKit, operationName == "click" {
        return try await resolveAndPerformNativeClick(
          criteria: criteria, physicalIdentity: physicalIdentityHint,
          expectedCandidateCount: expectedCandidateCount,
          expectedBoundingBox: expectedBoundingBox)
      }
      if dispatchMode == .nativeAppKit, let keyPress {
        return try await resolveAndPerformNativeKey(
          criteria: criteria, physicalIdentity: physicalIdentityHint,
          expectedCandidateCount: expectedCandidateCount,
          expectedBoundingBox: expectedBoundingBox, press: keyPress,
          frameContext: frameContext)
      }
      if dispatchMode == .nativeAppKit, operationName == "fill", let value {
        return try await resolveAndPerformNativeFill(
          criteria: criteria, physicalIdentity: physicalIdentityHint,
          expectedCandidateCount: expectedCandidateCount,
          expectedBoundingBox: expectedBoundingBox, value: value,
          frameContext: frameContext)
      }
      return try await resolveAndPerform(
        criteria: criteria,
        physicalIdentity: physicalIdentityHint,
        expectedCandidateCount: expectedCandidateCount,
        expectedBoundingBox: expectedBoundingBox,
        operation: operationName,
        value: value,
        modifiers: keyPress?.modifiers ?? [],
        frameContext: frameContext
      )
    }
    let second: RawActionResolution
    switch race {
    case .resolved(let resolution):
      second = resolution
    case .interruptedByDialog(let dialog):
      // The gesture landed and the page then stopped running inside a panel. Saying so
      // is the whole point: the caller learns that its own click opened this dialog, and
      // which one to answer, instead of waiting on a script only it can unblock.
      throw WebKitRuntimeError.javaScriptDialogOpenedByAction(
        kind: dialog.kind.rawValue, dialogID: dialog.dialogID)
    }
    try recordCardinality(
      second.count, target: target, eliminatedBy: second.eliminatedBy ?? [],
      pinnedState: second.pinnedState ?? "not_requested")
    guard let candidate = second.candidate else {
      if second.count == 0 {
        throw WebKitRuntimeError.targetNotFound(second.eliminatedBy ?? [])
      }
      throw WebKitRuntimeError.targetNotUnique(
        second.count, pinned: second.pinnedState ?? "not_requested")
    }

    let physicalIdentity: EvidenceComparison =
      candidate.physicalIdentity == target.physicalIdentity ? .same : .different
    let geometry: EvidenceComparison = candidate.geometryStable ? .same : .different
    let actionTime = DispatchTime.now().uptimeNanoseconds
    // A telemetry enum must never surface as this API's error. The only constructible
    // failure here is a generation that moved backwards, which means the document was
    // replaced between observation and action: that is a stale observation, and the
    // caller is told so.
    let attempt: AddressingAttempt
    do {
      attempt = try AddressingAttempt(
        observationID: observationID,
        locatorRecipeID: elementID,
        observationGeneration: target.recipe.observationGeneration,
        actionGeneration: observationGeneration,
        observationMonotonicNanoseconds: target.observedAtMonotonicNanoseconds,
        actionMonotonicNanoseconds: actionTime,
        finalCandidateCount: second.count,
        semanticComparison: .same,
        physicalIdentity: physicalIdentity,
        geometryComparison: geometry
      )
    } catch {
      throw WebKitRuntimeError.staleObservation
    }
    let outcome = AddressingClassifier.classify(attempt)
    addressingCounters.record(outcome)

    guard candidate.geometryStable else { throw WebKitRuntimeError.targetGeometryChanged }
    if let role = candidate.unsupportedOperationRole {
      throw WebKitRuntimeError.operationUnsupportedForControl(
        role: role,
        alternative:
          "A \(role) does not accept typed input. Click it to open its options, then click "
          + "the option you want.")
    }
    guard candidate.actionable, candidate.dispatched else {
      throw WebKitRuntimeError.targetNotActionable
    }
    // Verified against a control resolved again from scratch, not against the handle
    // held before the gesture: a framework that replaces its `<select>` on change would
    // otherwise have its old node confirm a selection the live one never made. Exactly
    // what `fill` does with its exact value, one layer down.
    if operationName == "select_option", let label = value {
      let survey = try await surveySelectedOption(
        criteria: actionLocatorCriteria(
          for: target, publicRecipe: target.recipe, includeObservedState: false),
        physicalIdentity: physicalIdentityHint,
        expectedCandidateCount: expectedCandidateCount, label: label,
        alreadyDispatched: true, frameContext: frameContext)
      guard survey.selectedOptionMatchesRequest == true else {
        throw WebKitRuntimeError.selectedOptionMismatch
      }
    }
    let result = WebKitActionResult(
      elementID: elementID,
      addressingOutcome: outcome,
      dispatched: true,
      trustedUserGesture: candidate.trustedUserGesture,
      dispatchMode: dispatchMode == .nativeAppKit
        && (operationName == "click" || operationName == "press_key" || operationName == "fill")
        ? .nativeAppKit : .javascript,
      actionMonotonicNanoseconds: actionTime
    )
    if controlState == .freshlyReobserved {
      transition(to: .agentControlled, observationID: observationID)
    }
    // The armed actor is not cleared here. WebKit delivers the navigation policy callback
    // for a click on its own schedule, and on a loaded Mac that was after this call had
    // returned: the audit then filed the agent's own navigation as web content. The arm
    // is consumed by the first main-frame navigation and expires on its own otherwise.
    return result
  }

  public func interactionControlState() -> InteractionControlState { controlState }

  public func latestNavigationAuditEvent() -> WebKitNavigationAuditEvent? {
    navigationAuditEvents.last
  }

  public func navigationAuditEventCount() -> Int { navigationAuditEvents.count }

  public func latestSubmissionFacts() -> WebKitSubmissionFacts? { submissionFacts }

  /// The new window this document asked for and did not get, if one is still outstanding.
  public func outstandingSuppressedNewWindowRequest() -> WebKitSuppressedNewWindowRequest? {
    suppressedNewWindowRequest
  }

  /// Hosts this session's data store holds credential-bearing storage for, so a
  /// client can tell whether a profile is already signed in to an origin. Host names
  /// only: cookie names, values, paths and expiries never leave the store.
  public func authenticatedOrigins() async -> [String] {
    let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
    // Only the domain leaves this function. Names, values, paths and expiries stay
    // inside the store.
    let hosts = cookies.map { cookie -> String in
      let domain = cookie.domain
      return domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
    }
    return Set(hosts.filter { !$0.isEmpty }).sorted()
  }

  public func latestFileUploadReceipt() -> WebKitFileUploadReceipt? {
    lastUploadReceipt
  }

  public func isFilePickerVisible() -> Bool { filePickerVisible }

  /// Arms a single-use file-panel selection. The next panel this runtime opens
  /// consumes it; the selection is spent whether or not it passed validation, so an
  /// approved selection can never satisfy a second panel opened by the site.
  public func armUploadSelection(_ urls: [URL]) {
    armedUploadSelection = urls
  }

  public func hasArmedUploadSelection() -> Bool { armedUploadSelection != nil }

  /// Discards an armed selection that no panel consumed.
  public func disarmUploadSelection() {
    armedUploadSelection = nil
  }

  /// WebKit asks for a web view here for `window.open()` and for a `target="_blank"`
  /// activation, and gets nil — exactly what it got when this method did not exist. The
  /// refusal is the product's own and it stands: one session holds one exclusive host
  /// lease, and a second tab would make an approval ambiguous about which page it named.
  ///
  /// What changed is the silence. An unimplemented `createWebViewWith` makes WebKit cancel
  /// the navigation and report nothing at all, so an invoice or statement link on a
  /// billing portal — overwhelmingly `target="_blank"` — did nothing, and a click on one
  /// was indistinguishable from a click that missed (measured 2026-09-09).
  ///
  /// A `target="_blank"` link activated in the main frame is followed here, in this same
  /// view: a click on it carries exactly the authority of a click on the same link
  /// without a target, and the load below goes through the same navigation policy, so
  /// the origin lock and cross-origin refusal apply unchanged. There is still no second
  /// window. A `window.open()` from script, or anything not a GET to http(s), is only
  /// recorded; reaching it costs the caller a `browser_navigate` of its own.
  public func webView(
    _ webView: WKWebView,
    createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction,
    windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    // `windowFeatures` is read and dropped. Its every field is site-authored, and this
    // record is exported: the shape a page wanted for a window it is not getting is not
    // worth carrying unlabelled site content for.
    let request = navigationAction.request
    let follow =
      navigationAction.navigationType == .linkActivated
      && navigationAction.sourceFrame.isMainFrame
      && ["http", "https"].contains(request.url?.scheme?.lowercased() ?? "")
      && (request.httpMethod ?? "GET").uppercased() == "GET"
      && !processTerminated
    suppressedNewWindowRequest = WebKitSuppressedNewWindowRequest(
      destination: Self.sanitizedNewWindowDestination(request.url),
      navigationType: Self.navigationTypeName(navigationAction.navigationType),
      sourceFrameIsMain: navigationAction.sourceFrame.isMainFrame,
      monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds,
      followedInSameView: follow)
    if follow {
      // After this delegate call returns: WebKit is still inside the activation.
      DispatchQueue.main.async { [weak self] in
        guard let self, let url = request.url else { return }
        self.webView.load(URLRequest(url: url))
      }
    }
    return nil
  }

  // WebKit treats a panel whose delegate method is not implemented as dismissed, so
  // until these three existed `confirm()` returned `false` and `prompt()` returned `nil`
  // on every page, silently: a site that guards a delete or a save behind `confirm()`
  // always received Cancel, the action never happened, and the failure surfaced as an
  // unverified postcondition rather than as a dialog nobody answered (measured
  // 2026-09-09). All three are public API in `WKUIDelegate.h`.
  //
  // These three are the whole surface. A reader looking for a before-unload panel will
  // not find one: the public macOS 27 SDK's `WKUIDelegate.h` declares no such method —
  // there is no `BeforeUnload` symbol in it — so an unload prompt cannot be observed or
  // answered from an embedder at all, and `beforeunload` is out of scope here.
  public func webView(
    _ webView: WKWebView,
    runJavaScriptAlertPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo
  ) async {
    _ = await awaitJavaScriptDialogAnswer(
      kind: .alert, message: message, defaultText: nil, frame: frame)
  }

  public func webView(
    _ webView: WKWebView,
    runJavaScriptConfirmPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo
  ) async -> Bool {
    switch await awaitJavaScriptDialogAnswer(
      kind: .confirm, message: message, defaultText: nil, frame: frame)
    {
    case .accepted: true
    case .dismissed, .unanswered: false
    }
  }

  public func webView(
    _ webView: WKWebView,
    runJavaScriptTextInputPanelWithPrompt prompt: String,
    defaultText: String?,
    initiatedByFrame frame: WKFrameInfo
  ) async -> String? {
    switch await awaitJavaScriptDialogAnswer(
      kind: .prompt, message: prompt, defaultText: defaultText, frame: frame)
    {
    case .accepted(let value): value
    case .dismissed, .unanswered: nil
    }
  }

  /// Holds one panel open until it is answered, or until the answer window closes.
  ///
  /// The main thread is never blocked here: only the web content process is suspended,
  /// which is what lets the server keep serving while the operator decides. The timeout
  /// is not an answer — it releases WebKit so nothing wedges, and files the outcome as
  /// nobody having answered.
  private func awaitJavaScriptDialogAnswer(
    kind: WebKitJavaScriptDialogKind,
    message: String,
    defaultText: String?,
    frame: WKFrameInfo
  ) async -> JavaScriptDialogAnswer {
    let dialogID = UUID().uuidString
    guard pendingJavaScriptDialogState == nil else {
      // Answering a second panel would either overwrite the identity an approval was
      // granted against or queue behind a panel nobody has answered yet. Refuse it, and
      // say which it was: the first panel stays answerable.
      recordJavaScriptDialog(
        dialogID: dialogID, kind: kind, outcome: .refusedConcurrent, valueSupplied: false)
      return .dismissed
    }
    let frameURL = frame.request.url ?? webView.url
    let dialog: WebKitPendingJavaScriptDialog
    do {
      let source = ProvenanceSource(
        // A panel raised by a subframe is not this page speaking, and its text is what
        // the confirmation shows an operator.
        classification: frame.isMainFrame ? .firstPartySiteContent : .thirdPartyEmbed,
        documentID: documentID,
        frameID: frame.isMainFrame ? "main" : "subframe",
        securityOrigin: Self.securityOrigin(from: frameURL))
      dialog = WebKitPendingJavaScriptDialog(
        dialogID: dialogID,
        kind: kind,
        message: try ProvenancedText(
          text: String(message.prefix(Self.maximumJavaScriptDialogTextLength)), source: source),
        defaultText: try defaultText.map {
          try ProvenancedText(
            text: String($0.prefix(Self.maximumJavaScriptDialogTextLength)), source: source)
        },
        frameOrigin: frameURL.flatMap(Self.sanitizedOrigin(for:)),
        frameIsMain: frame.isMainFrame,
        openedAtMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
    } catch {
      // A panel that cannot even be described cannot be presented for approval, so it
      // is released rather than held open against an operator who would never see it.
      recordJavaScriptDialog(
        dialogID: dialogID, kind: kind, outcome: .refusedConcurrent, valueSupplied: false)
      return .dismissed
    }
    return await withCheckedContinuation { continuation in
      pendingJavaScriptDialogState = PendingJavaScriptDialogState(
        dialog: dialog, continuation: continuation)
      javaScriptDialogTimeoutTask = Task { @MainActor [weak self] in
        try? await Task.sleep(for: self?.javaScriptDialogAnswerTimeout ?? .seconds(30))
        guard let self, let state = self.pendingJavaScriptDialogState,
          state.dialog.dialogID == dialogID
        else { return }
        self.pendingJavaScriptDialogState = nil
        self.javaScriptDialogTimeoutTask = nil
        self.recordJavaScriptDialog(
          dialogID: dialogID, kind: kind, outcome: .unansweredTimeout, valueSupplied: false)
        state.continuation.resume(returning: .unanswered)
      }
      // If a gesture this runtime dispatched is what opened the panel, its dispatch
      // script is suspended inside the panel and cannot return until somebody answers.
      // Stop waiting for it now, or the caller waits for an answer only it can give.
      // Every outstanding dispatch is suspended behind this one panel, so every one of
      // them is released.
      for token in dialogRaceContinuations.keys {
        settleActionDispatchRace(token: token, .success(.interruptedByDialog(dialog)))
      }
    }
  }

  private static let maximumJavaScriptDialogTextLength = 2_048

  /// Dispatches one gesture, and stops waiting for it if the gesture opens a panel.
  ///
  /// A `confirm()` inside an `onclick` handler suspends the page inside the very call
  /// that dispatched the gesture. The dispatch task is abandoned rather than cancelled:
  /// it does complete once the panel is answered, and its result is irrelevant by then
  /// because the action's own verification was lost the moment the page stopped running.
  private func dispatchRacingJavaScriptDialog(
    _ body: @escaping @MainActor @Sendable () async throws -> RawActionResolution
  ) async throws -> ActionDispatchRace {
    dialogRaceToken &+= 1
    let token = dialogRaceToken
    Task { @MainActor [weak self] in
      do {
        let resolution = try await body()
        self?.settleActionDispatchRace(token: token, .success(.resolved(resolution)))
      } catch {
        self?.settleActionDispatchRace(token: token, .failure(error))
      }
    }
    return try await withCheckedThrowingContinuation { continuation in
      dialogRaceContinuations[token] = continuation
    }
  }

  /// First settlement of a given dispatch wins; the loser is dropped. An abandoned
  /// dispatch script that finally returns long after a panel decided its race finds
  /// nothing to resume.
  private func settleActionDispatchRace(
    token: UInt64,
    _ result: Result<ActionDispatchRace, any Error>
  ) {
    guard let continuation = dialogRaceContinuations.removeValue(forKey: token) else { return }
    continuation.resume(with: result)
  }

  /// The JavaScript panel this session is suspended on, if any.
  public func pendingJavaScriptDialog() -> WebKitPendingJavaScriptDialog? {
    pendingJavaScriptDialogState?.dialog
  }

  /// How the last panel ended. Nothing is inferred from its absence: a panel that is
  /// still pending has no record yet.
  public func latestJavaScriptDialogRecord() -> WebKitJavaScriptDialogRecord? {
    lastJavaScriptDialogRecord
  }

  /// Answers the one panel this runtime is holding open.
  ///
  /// Nothing here is automatic. The caller names the exact dialog it was shown, and an
  /// answer for any other one — a dialog already answered, one that timed out, one the
  /// page replaced — fails closed rather than landing on whatever is open now. A prompt
  /// is accepted only with an exact value, because the value is what the confirmation
  /// showed the operator.
  @discardableResult
  public func answerJavaScriptDialog(
    dialogID: String,
    accept: Bool,
    promptValue: ProvenancedText? = nil
  ) throws -> WebKitJavaScriptDialogRecord {
    try requireAgentControlIgnoringJavaScriptDialog()
    guard let state = pendingJavaScriptDialogState else {
      throw WebKitRuntimeError.noPendingJavaScriptDialog
    }
    guard state.dialog.dialogID == dialogID else {
      throw WebKitRuntimeError.staleJavaScriptDialog
    }
    if promptValue != nil, state.dialog.kind != .prompt {
      throw WebKitRuntimeError.javaScriptDialogValueUnsupported
    }
    if accept, state.dialog.kind == .prompt, promptValue == nil {
      throw WebKitRuntimeError.javaScriptDialogValueRequired
    }
    pendingJavaScriptDialogState = nil
    javaScriptDialogTimeoutTask?.cancel()
    javaScriptDialogTimeoutTask = nil
    let value = promptValue.map { $0.segments.map(\.text).joined() }
    let record = recordJavaScriptDialog(
      dialogID: dialogID,
      kind: state.dialog.kind,
      outcome: accept ? .accepted : .dismissed,
      valueSupplied: value != nil)
    state.continuation.resume(returning: accept ? .accepted(value) : .dismissed)
    return record
  }

  @discardableResult
  private func recordJavaScriptDialog(
    dialogID: String,
    kind: WebKitJavaScriptDialogKind,
    outcome: WebKitJavaScriptDialogOutcome,
    valueSupplied: Bool
  ) -> WebKitJavaScriptDialogRecord {
    let record = WebKitJavaScriptDialogRecord(
      dialogID: dialogID,
      kind: kind,
      outcome: outcome,
      valueSupplied: valueSupplied,
      monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
    lastJavaScriptDialogRecord = record
    return record
  }

  /// A panel suspends the page's script, so the observation instrumentation cannot run
  /// at all: nothing about the DOM can be read until somebody answers. Waiting on a
  /// script only the caller can unblock would hang the call, so the observation reports
  /// the one thing that is true — this dialog is open — and reports itself incomplete.
  private func dialogPendingObservation(
    _ dialog: WebKitPendingJavaScriptDialog
  ) throws -> WebKitPageObservation {
    let (nextGeneration, overflow) = observationGeneration.addingReportingOverflow(1)
    guard !overflow else { throw WebKitRuntimeError.malformedInstrumentationResult }
    observationGeneration = nextGeneration
    let observationID = UUID().uuidString
    let origin = Self.securityOrigin(from: webView.url)
    let pageSource = ProvenanceSource(
      classification: .firstPartySiteContent,
      documentID: documentID,
      frameID: "main",
      securityOrigin: origin)
    let toolSource = ProvenanceSource(
      classification: .toolResult,
      documentID: documentID,
      frameID: "main",
      securityOrigin: origin)
    latestObservationID = observationID
    // No element in this observation can be addressed, so none is handed out. Anything
    // the caller held from before is superseded, which is honest: the page will have
    // moved on by the time the panel is answered.
    latestTargets.removeAll(keepingCapacity: true)
    return WebKitPageObservation(
      observationID: observationID,
      generation: nextGeneration,
      documentID: documentID,
      url: try ProvenancedText(
        text: agentSafeURLString(webView.url) ?? "about:blank", source: toolSource),
      title: try ProvenancedText(text: webView.title ?? "", source: pageSource),
      readyState: "javascript_dialog_pending",
      mutationCount: 0,
      elements: [],
      totalElementCount: 0,
      elementOffset: 0,
      nextElementOffset: nil,
      unreadableFrameCount: 0,
      semanticTextTruncated: false,
      crossOriginFramesOpaque: false,
      renderedInteractiveCount: 0,
      renderedContentCount: 0,
      documentLanguage: nil,
      ariaHiddenDropCount: 0,
      unrenderedControlCount: 0,
      unrenderedControlNames: [],
      rawControlCount: 0,
      obscuredByAncestorOpacity: false,
      documentElementCount: 0,
      bodyTextLength: 0,
      firstControlProbe: "javascript_dialog_pending",
      capturedAtMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds,
      pendingDialog: dialog,
      permissionDenials: permissionDenials,
      permissionDenialCount: permissionDenialCount,
      permissionDenialsTruncated: permissionDenialsTruncated)
  }

  public func webView(
    _ webView: WKWebView,
    requestMediaCapturePermissionFor origin: WKSecurityOrigin,
    initiatedByFrame frame: WKFrameInfo,
    type: WKMediaCaptureType,
    decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
  ) {
    let permission: WebKitDeniedPermission
    switch type {
    case .camera:
      permission = .camera
    case .microphone:
      permission = .microphone
    case .cameraAndMicrophone:
      permission = .cameraAndMicrophone
    @unknown default:
      permission = .mediaCapture
    }
    recordPermissionDenial(permission, origin: origin, frameIsMain: frame.isMainFrame)
    decisionHandler(.deny)
  }

  @available(macOS 27.0, *)
  public func webView(
    _ webView: WKWebView,
    requestGeolocationPermissionFor origin: WKSecurityOrigin,
    initiatedByFrame frame: WKFrameInfo,
    decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
  ) {
    recordPermissionDenial(.geolocation, origin: origin, frameIsMain: frame.isMainFrame)
    decisionHandler(.deny)
  }

  public func webView(
    _ webView: WKWebView,
    runOpenPanelWith parameters: WKOpenPanelParameters,
    initiatedByFrame frame: WKFrameInfo
  ) async -> [URL]? {
    filePickerVisible = true
    defer { filePickerVisible = false }
    let selectionMode: WebKitFileUploadSelectionMode
    let selectedURLs: [URL]?
    if let armed = armedUploadSelection {
      // Spent unconditionally: a rejected or partial selection must not survive
      // into a second panel.
      armedUploadSelection = nil
      selectionMode = .agentConfirmed
      selectedURLs = armed
    } else if let uploadSelectionProvider {
      selectionMode = .agentConfirmed
      selectedURLs = await uploadSelectionProvider(
        parameters.allowsMultipleSelection, parameters.allowsDirectories)
    } else {
      selectionMode = .humanPanel
      let panel = NSOpenPanel()
      panel.allowsMultipleSelection = parameters.allowsMultipleSelection
      panel.canChooseDirectories = false
      panel.canChooseFiles = true
      panel.resolvesAliases = true
      panel.message =
        "Choose the exact local file. Its name, size, and SHA-256 will be returned to the MCP client; its local path and contents will not."
      panel.prompt = "Choose"
      let response: NSApplication.ModalResponse
      if let window = browserWindow, browserWindowIsOnScreen {
        response = await withCheckedContinuation { continuation in
          panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
        }
      } else {
        NSApp.activate()
        response = await withCheckedContinuation { continuation in
          panel.begin { continuation.resume(returning: $0) }
        }
      }
      selectedURLs = response == .OK ? panel.urls : nil
    }
    guard let selectedURLs, !selectedURLs.isEmpty, selectedURLs.count <= 10 else {
      lastUploadReceipt = nil
      return nil
    }

    var filenames: [String] = []
    var byteCounts: [UInt64] = []
    var digests: [String] = []
    for url in selectedURLs {
      guard let filename = Self.safeUploadFilename(url.lastPathComponent) else {
        lastUploadReceipt = nil
        return nil
      }
      guard url.isFileURL,
        let values = try? url.resourceValues(forKeys: [
          .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
        ]),
        values.isRegularFile == true, values.isSymbolicLink != true,
        let size = values.fileSize, (0...52_428_800).contains(size),
        let data = try? Data(contentsOf: url, options: [.mappedIfSafe])
      else {
        lastUploadReceipt = nil
        return nil
      }
      filenames.append(filename)
      byteCounts.append(UInt64(data.count))
      digests.append(
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }
    lastUploadReceipt = WebKitFileUploadReceipt(
      filenames: filenames,
      byteCounts: byteCounts,
      sha256: digests,
      fileCount: selectedURLs.count,
      selectionMode: selectionMode,
      selectedByHuman: selectionMode == .humanPanel,
      localPathsExposed: false,
      monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
    return selectedURLs
  }

  public func download(
    observationID: String,
    elementID: String,
    expectedProvisioningProfileUUID: String? = nil,
    timeout: Duration = .seconds(120)
  ) async throws -> WebKitDownloadReceipt {
    try requireAgentControl()
    guard downloadContinuation == nil else { throw WebKitRuntimeError.downloadInProgress }
    guard let currentURL = webView.url, let origin = navigationOrigin(for: currentURL) else {
      throw WebKitRuntimeError.noDocument
    }
    return try await beginDownloadRequest(
      origin: origin,
      expectedProvisioningProfileUUID: expectedProvisioningProfileUUID,
      timeout: timeout
    ) {
      Task { @MainActor [weak self] in
        guard let self else { return }
        do {
          _ = try await self.perform(
            observationID: observationID,
            elementID: elementID,
            operation: .click,
            dispatchMode: .nativeAppKit)
          self.downloadActionVerified = true
          if let receipt = self.completedDownloadReceipt {
            self.finishDownload(.success(receipt))
          }
        } catch {
          self.finishDownload(.failure(error))
        }
      }
    }
  }

  public func download(
    url: URL,
    expectedProvisioningProfileUUID: String? = nil,
    timeout: Duration = .seconds(120)
  ) async throws -> WebKitDownloadReceipt {
    try requireAgentControl()
    guard downloadContinuation == nil else { throw WebKitRuntimeError.downloadInProgress }
    guard let currentURL = webView.url, let origin = navigationOrigin(for: currentURL) else {
      throw WebKitRuntimeError.noDocument
    }
    guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
      throw WebKitRuntimeError.unsupportedURLScheme
    }
    guard navigationOrigin(for: url) == origin else {
      throw WebKitRuntimeError.networkBoundaryDenied
    }
    return try await beginDownloadRequest(
      origin: origin,
      expectedProvisioningProfileUUID: expectedProvisioningProfileUUID,
      timeout: timeout
    ) {
      downloadActionVerified = true
      webView.load(URLRequest(url: url))
    }
  }

  private func beginDownloadRequest(
    origin: SecurityOrigin,
    expectedProvisioningProfileUUID: String?,
    timeout: Duration,
    trigger: () -> Void
  ) async throws -> WebKitDownloadReceipt {
    try await withCheckedThrowingContinuation { continuation in
      downloadContinuation = continuation
      downloadExpectedOrigin = origin
      downloadDestination = nil
      downloadMIMEType = nil
      downloadHTTPStatus = nil
      downloadSuggestedFilename = nil
      downloadExpectedProvisioningProfileUUID = expectedProvisioningProfileUUID
      downloadStarted = false
      downloadActionVerified = false
      completedDownloadReceipt = nil
      downloadTimeoutTask = Task { @MainActor [weak self] in
        try? await Task.sleep(for: timeout)
        guard let self else { return }
        self.finishDownload(
          .failure(WebKitRuntimeError.downloadReceiptTimedOut(started: self.downloadStarted)))
      }
      trigger()
    }
  }

  public func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    if message.name == Self.frameRegistrationMessageHandlerName {
      registerFrameCapability(message.frameInfo)
      return
    }
    guard message.name == Self.nativeGestureMessageHandlerName,
      let body = message.body as? [String: Any],
      let token = body["token"] as? String,
      let armedContext = armedNativeGestureTokens[token],
      let physicalIdentity = body["physicalIdentity"] as? String,
      let eventType = body["eventType"] as? String,
      let trusted = body["trusted"] as? Bool
    else { return }
    if let expectedCapabilityID = armedContext.frameCapabilityID {
      guard
        body["frameCapabilityID"] as? String == expectedCapabilityID,
        !message.frameInfo.isMainFrame,
        let expectedOrigin = armedContext.frameOrigin,
        Self.agentSafeSecurityOrigin(message.frameInfo.securityOrigin) == expectedOrigin
      else { return }
    }
    nativeGestureReceipts[token, default: []].append(
      NativeGestureReceipt(
        physicalIdentity: physicalIdentity, eventType: eventType, trusted: trusted))
  }

  func frameRegistrySnapshot() -> WebKitFrameRegistrySnapshot {
    WebKitFrameRegistrySnapshot(
      capabilities: registeredFrameCapabilities.map {
        WebKitFrameCapabilitySnapshot(
          capabilityID: $0.capabilityID,
          origin: $0.origin,
          isMainFrame: $0.isMainFrame)
      },
      droppedRegistrationCount: droppedFrameRegistrationCount)
  }

  func probeFrameDocument(capabilityID: String) async -> WebKitFrameDocumentProbe {
    guard
      !processTerminated,
      controlState != .handoffRequested,
      controlState != .humanControlled,
      controlState != .humanStepCompleted,
      let capability = registeredFrameCapabilities.first(where: {
        $0.capabilityID == capabilityID && $0.documentID == documentID
      })
    else { return .unavailable }
    do {
      let result = try await webView.callAsyncJavaScript(
        "return String(document.title || '').slice(0, 256);",
        arguments: [:],
        in: capability.frameInfo,
        contentWorld: instrumentationWorld)
      guard let title = result as? String else {
        registeredFrameCapabilities.removeAll { $0.capabilityID == capabilityID }
        return .unavailable
      }
      return .available(title: title)
    } catch {
      registeredFrameCapabilities.removeAll { $0.capabilityID == capabilityID }
      return .unavailable
    }
  }

  public func authenticationRestrictionStatus() -> AuthenticationRestrictionStatus? {
    guard let origin = restrictedAuthenticationOrigin() else { return nil }
    return AuthenticationRestrictionStatus(
      origin: origin,
      classification: authenticationUIClassification ?? .humanHandoffRequired,
      environment: authenticationEnvironmentSnapshot()
    )
  }

  /// Returns the exact private URL only to the in-process compatibility
  /// presenter. Callers must never serialize, log, or place it in an MCP
  /// confirmation; paths and queries may contain authentication state.
  public func privateFullBrowserHandoffURL() throws -> URL {
    guard
      authenticationRestrictionStatus()?.classification == .fullBrowserRequired,
      let url = webView.url ?? lastCommittedHTTPURL,
      url.scheme?.lowercased() == "https",
      url.host != nil
    else { throw WebKitRuntimeError.authenticationOriginRequiresHuman("unavailable") }
    return url
  }

  public func authenticationEnvironmentSnapshot() -> AuthenticationEnvironmentSnapshot {
    AuthenticationEnvironmentSnapshot(
      persistentWebsiteDataStore: webView.configuration.websiteDataStore.isPersistent,
      customUserAgentConfigured: !(webView.customUserAgent?.isEmpty ?? true),
      applicationNameForUserAgentConfigured:
        !(webView.configuration.applicationNameForUserAgent?.isEmpty ?? true),
      pinnedProxyConfigured: egressProxy != nil,
      contentBlockingConfigured: false,
      customProcessPoolConfigured: false,
      webAuthnAnyRelyingPartyEntitlementConfigured:
        Self.webAuthnAnyRelyingPartyEntitlementConfigured()
    )
  }

  public func agentSafeCurrentURL() -> String? {
    agentSafeURLString(webView.url ?? lastCommittedHTTPURL)
  }

  public static func agentSafeURL(_ url: URL) -> String {
    guard
      let host = url.host?.lowercased().trimmingCharacters(
        in: CharacterSet(charactersIn: ".")),
      restrictedAuthenticationHosts.contains(host)
    else {
      // The request keeps its exact query locally, but no value from that query belongs
      // in an observation, confirmation, transaction state, or model-visible URL. Keep
      // the names so the page remains identifiable and replace every value before the
      // URL crosses that boundary. Fragments deliberately remain visible pending the
      // separately recorded HashJack product decision.
      guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        return sanitizedOrigin(for: url) ?? "unavailable"
      }
      if components.percentEncodedQuery != nil {
        let items = components.queryItems ?? []
        components.queryItems = items.prefix(16).map {
          URLQueryItem(name: $0.name, value: "<redacted>")
        }
      }
      return components.string ?? sanitizedOrigin(for: url) ?? "unavailable"
    }
    return sanitizedOrigin(for: url) ?? "unavailable"
  }

  public func handoffAuditEvents() -> [HandoffAuditEvent] { handoffEvents }

  public func formSubmissionAuditEvents() -> [FormSubmissionAuditEvent] {
    formSubmissionEvents
  }

  public func terminationAuditEvents() -> [WebContentTerminationEvent] {
    webContentTerminationEvents
  }

  public func webContentProcessIsTerminated() -> Bool { processTerminated }

  public func egressProxyMetrics() -> PinnedProxyMetrics? {
    egressProxy?.metricsSnapshot()
  }

  public func requestHumanHandoff() throws {
    guard controlState == .agentControlled || controlState == .freshlyReobserved else {
      throw WebKitRuntimeError.invalidControlTransition
    }
    transition(to: .handoffRequested, observationID: latestObservationID)
  }

  public func beginHumanControl(presentWindow: Bool = true) throws {
    guard controlState == .handoffRequested else {
      throw WebKitRuntimeError.invalidControlTransition
    }
    latestObservationID = nil
    latestTargets.removeAll(keepingCapacity: true)
    topLevelOriginLock = nil
    transition(to: .humanControlled, observationID: nil)
    if presentWindow {
      presentHumanControlWindow()
      // Fail closed rather than delegate to a human who has nothing to act in: the
      // step would wait forever on a control that was never presented.
      guard humanControlSurfaceIsPresented else {
        throw WebKitRuntimeError.handoffSurfaceUnavailable
      }
    }
  }

  public func markHumanStepCompleted() throws {
    guard controlState == .humanControlled else {
      throw WebKitRuntimeError.invalidControlTransition
    }
    transition(to: .humanStepCompleted, observationID: nil)
  }

  public func humanStepCompletionMonotonicNanoseconds() -> UInt64? {
    handoffEvents.last(where: { $0.to == .humanStepCompleted })?.monotonicNanoseconds
  }

  public func requestAgentResume() throws {
    guard controlState == .humanControlled || controlState == .humanStepCompleted else {
      throw WebKitRuntimeError.invalidControlTransition
    }
    if let origin = restrictedAuthenticationOrigin() {
      throw WebKitRuntimeError.authenticationOriginRequiresHuman(origin)
    }
    if let window = browserWindow {
      // Give the page its whole viewport back. The handoff bar is 54 points tall and
      // was never removed, so a page kept laying out against a viewport that short for
      // the rest of the session — a dialog opened afterwards came back with every
      // element crushed to a fraction of a pixel against that edge, and reported as
      // covered. The bar belongs to the human's turn, not to the agent's.
      attachWebView(to: window)
      // Return to the offscreen layout host rather than hiding outright: WebKit stops
      // laying the page out for a window that was ordered out, and the next
      // observation would come back empty.
      window.setFrameOrigin(NSPoint(x: -32_000, y: -32_000))
      window.orderFrontRegardless()
      window.ignoresMouseEvents = true
      window.collectionBehavior.remove(.moveToActiveSpace)
      window.collectionBehavior.insert(.stationary)
      window.collectionBehavior.insert(.ignoresCycle)
      // Give up key status and drop back below everything. A parked window left key
      // at normal level is still the app's front window, and a confirmation panel
      // positioned against it lands off screen — the prompt is never seen and the
      // request times out with no decision taken.
      window.collectionBehavior.insert(.transient)
      window.level = .init(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
      window.title = Self.localizedHandoff(
        "WebkitUIMCP — Agent control", fallback: "WebkitUIMCP — Agent control")
      window.resignKey()
      window.resignMain()
    }
    if managesApplicationActivationPolicy {
      NSApplication.shared.setActivationPolicy(.accessory)
    }
    topLevelOriginLock = (webView.url ?? lastCommittedHTTPURL).flatMap {
      navigationOrigin(for: $0)
    }
    transition(to: .resumeRequested, observationID: nil)
  }

  private func makeBrowserWindow() -> NSWindow {
    let window = UnconstrainedWindow(
      contentRect: .init(x: 0, y: 0, width: 1280, height: 800),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    window.center()
    attachWebView(to: window)
    window.orderOut(nil)
    browserWindow = window
    return window
  }

  /// WebKit does not lay out a view whose window was never ordered in, so a page can
  /// build its whole DOM while every control reports a zero-sized box. Ordering the
  /// window in at coordinates outside every screen gives the engine a real viewport
  /// and shows the user nothing.
  /// A window ordered in for layout may still sit outside every display. Anything a
  /// person must actually see — a file panel, the handoff window — must key off this,
  /// never off `isVisible`, which is true for the offscreen layout host.
  var browserWindowIsOnScreen: Bool {
    guard let window = browserWindow, window.isVisible else { return false }
    return NSScreen.screens.contains { $0.frame.intersects(window.frame) }
  }

  private func ensureLayoutViewport() {
    let window = browserWindow ?? makeBrowserWindow()
    guard !window.isVisible else { return }
    window.ignoresMouseEvents = true
    window.level = .init(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
    window.collectionBehavior.insert([.stationary, .ignoresCycle, .transient])
    window.setFrameOrigin(NSPoint(x: -32_000, y: -32_000))
    window.orderFrontRegardless()
    webView.needsLayout = true
    webView.layoutSubtreeIfNeeded()
  }

  private func presentHumanControlWindow() {
    let application = NSApplication.shared
    WebKitNativeApplicationMenu.install(on: application)
    if managesApplicationActivationPolicy {
      application.finishLaunching()
      application.setActivationPolicy(.regular)
    }
    application.applicationIconImage = Self.humanControlApplicationIcon()
    let window = browserWindow ?? makeBrowserWindow()
    if webView.url == nil, lastCommittedHTTPURL == nil, !webView.isLoading {
      webView.loadHTMLString(Self.emptyHandoffDocument, baseURL: nil)
    }
    window.title = Self.localizedHandoff(
      "WebkitUIMCP — Human control", fallback: "WebkitUIMCP — Human control")
    window.ignoresMouseEvents = false
    window.collectionBehavior.remove(.stationary)
    window.collectionBehavior.remove(.ignoresCycle)
    window.collectionBehavior.insert(.moveToActiveSpace)
    webView.isHidden = false
    webView.alphaValue = 1
    attachHumanControlView(to: window)
    // The window is parked outside every display so pages lay out without being
    // shown. Handing control to a human must undo that, or the user is asked to act
    // in a window that is nowhere on screen.
    // Since macOS 14 an app cannot take the foreground from the one the person is
    // using, so activation alone left this window behind the agent's terminal and the
    // person did not know a sign-in was waiting (FPS/TSP session, 2026-09-23). Float it
    // above other apps and bounce the Dock icon; the first time the person brings the
    // app forward it drops back to an ordinary window.
    window.level = .floating
    window.collectionBehavior.remove(.transient)
    window.setFrame(
      NSRect(origin: .zero, size: window.frame.size), display: false)
    window.center()
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
    if managesApplicationActivationPolicy {
      application.activate(ignoringOtherApps: true)
    }
    application.requestUserAttention(.informationalRequest)
    humanControlActivationObserver.map(NotificationCenter.default.removeObserver)
    humanControlActivationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self, weak window] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        if let window, window.level == .floating { window.level = .normal }
        self.humanControlActivationObserver.map(NotificationCenter.default.removeObserver)
        self.humanControlActivationObserver = nil
      }
    }
    window.makeFirstResponder(webView)
    window.displayIfNeeded()
  }

  /// Re-establishes the layout viewport and forces a layout pass. An operator can
  /// reach for this when a page has built its DOM but reports nothing observable,
  /// which is what a hidden window used to cause.
  public func forceRender() {
    ensureLayoutViewport()
    webView.needsLayout = true
    webView.needsDisplay = true
    webView.layoutSubtreeIfNeeded()
    webView.displayIfNeeded()
  }

  /// Removes every website data record this profile holds: cookies, caches and local
  /// storage. Signed-in origins are dropped with it, so the next run starts clean.
  public func clearBrowsingData() async {
    let store = webView.configuration.websiteDataStore
    let types = WKWebsiteDataStore.allWebsiteDataTypes()
    let records = await store.dataRecords(ofTypes: types)
    await store.removeData(ofTypes: types, for: records)
    for cookie in await store.httpCookieStore.allCookies() {
      await store.httpCookieStore.deleteCookie(cookie)
    }
  }

  /// True once a human can actually see and act in the browser window.
  public var humanControlSurfaceIsPresented: Bool { browserWindowIsOnScreen }

  private static let emptyHandoffDocument = """
    <!doctype html>
    <html lang="en">
    <meta charset="utf-8">
    <meta name="color-scheme" content="light dark">
    <title>No approved page loaded</title>
    <style>
      :root { font: -apple-system-body; color-scheme: light dark; }
      body { margin: 0; min-height: 100vh; display: grid; place-items: center;
             background: Canvas; color: CanvasText; }
      main { max-width: 34rem; padding: 2rem; text-align: center; }
      h1 { font: -apple-system-title1; margin-bottom: .6rem; }
      p { font: -apple-system-body; opacity: .75; line-height: 1.45; }
    </style>
    <main role="status">
      <h1>No approved page is loaded</h1>
      <p>Approve a browser navigation, then request human control again.</p>
    </main>
    </html>
    """

  private func attachWebView(to window: NSWindow) {
    webView.removeFromSuperview()
    window.contentViewController = nil
    window.contentView = webView
    webView.frame = window.contentView?.bounds ?? .zero
    webView.autoresizingMask = [.width, .height]
    webView.translatesAutoresizingMaskIntoConstraints = true
    webView.needsLayout = true
    webView.needsDisplay = true
    webView.layoutSubtreeIfNeeded()
  }

  private func attachHumanControlView(to window: NSWindow) {
    webView.removeFromSuperview()
    window.contentViewController = nil
    let root = NSView()
    let bar = NSVisualEffectView()
    bar.material = .headerView
    bar.blendingMode = .withinWindow
    bar.state = .active
    let instruction = NSTextField(
      labelWithString: Self.localizedHandoff(
        "Complete the private step, then return control explicitly.",
        fallback: "Complete the private step, then return control explicitly."))
    instruction.textColor = .secondaryLabelColor
    instruction.setAccessibilityIdentifier("webkitui.handoff.status")
    let done = NSButton(
      title: Self.localizedHandoff(
        "Done — Return Control", fallback: "Done — Return Control"),
      target: self,
      action: #selector(completeHumanStep))
    done.bezelStyle = .rounded
    done.bezelColor = .controlAccentColor
    done.setAccessibilityIdentifier("webkitui.handoff.done")
    done.setAccessibilityHelp(
      Self.localizedHandoff(
        "Marks the private step complete so the requesting agent can resume this session.",
        fallback:
          "Marks the private step complete so the requesting agent can resume this session."))
    var controlViews: [NSView] = [instruction]
    if humanCredentialFiller != nil {
      let fill = NSButton(
        title: Self.localizedHandoff(
          "Fill with SiliconPass", fallback: "Fill with SiliconPass"),
        target: self,
        action: #selector(fillWithSiliconPass))
      fill.bezelStyle = .rounded
      fill.image = NSImage(systemSymbolName: "key.fill", accessibilityDescription: nil)
      fill.imagePosition = .imageLeading
      fill.setAccessibilityIdentifier("webkitui.handoff.siliconpass")
      fill.setAccessibilityHelp(
        Self.localizedHandoff(
          "Asks SiliconPass to fill the visible sign-in form. The agent never sees the values, and nothing is submitted.",
          fallback:
            "Asks SiliconPass to fill the visible sign-in form. The agent never sees the values, and nothing is submitted."
        ))
      humanCredentialButton = fill
      controlViews.append(fill)
    }
    controlViews.append(done)
    let controls = NSStackView(views: controlViews)
    controls.orientation = .horizontal
    controls.alignment = .centerY
    controls.distribution = .fill
    controls.spacing = 12
    controls.translatesAutoresizingMaskIntoConstraints = false
    webView.translatesAutoresizingMaskIntoConstraints = false
    bar.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(webView)
    root.addSubview(bar)
    bar.addSubview(controls)
    window.contentView = root
    humanControlInstruction = instruction
    humanControlCompletionButton = done
    NSLayoutConstraint.activate([
      webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      webView.topAnchor.constraint(equalTo: root.topAnchor),
      webView.bottomAnchor.constraint(equalTo: bar.topAnchor),
      bar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      bar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      bar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      bar.heightAnchor.constraint(equalToConstant: 54),
      controls.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
      controls.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),
      controls.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
    ])
  }

  @objc private func completeHumanStep() {
    do {
      try markHumanStepCompleted()
      humanControlInstruction?.stringValue =
        Self.localizedHandoff(
          "Private step complete. Waiting for the requesting agent to resume.",
          fallback: "Private step complete. Waiting for the requesting agent to resume.")
      humanControlInstruction?.textColor = .systemGreen
      humanControlCompletionButton?.title = Self.localizedHandoff(
        "Ready — Waiting for Agent", fallback: "Ready — Waiting for Agent")
      humanControlCompletionButton?.isEnabled = false
      humanControlCompletionButton?.setAccessibilityLabel(
        Self.localizedHandoff(
          "Private step complete; waiting for the requesting agent",
          fallback: "Private step complete; waiting for the requesting agent"))
      if let button = humanControlCompletionButton {
        NSAccessibility.post(element: button, notification: .valueChanged)
      }
      Self.handoffLogger.notice("Human handoff completion accepted")
    } catch {
      humanControlInstruction?.stringValue =
        Self.localizedHandoff(
          "Control could not be returned. Keep this window open and try again.",
          fallback: "Control could not be returned. Keep this window open and try again.")
      humanControlInstruction?.textColor = .systemRed
      humanControlCompletionButton?.title = Self.localizedHandoff(
        "Try Again — Return Control", fallback: "Try Again — Return Control")
      humanControlCompletionButton?.isEnabled = true
      humanControlCompletionButton?.setAccessibilityLabel(
        Self.localizedHandoff(
          "Return control failed; try again", fallback: "Return control failed; try again"))
      if let button = humanControlCompletionButton {
        NSAccessibility.post(element: button, notification: .valueChanged)
      }
      Self.handoffLogger.error(
        "Human handoff completion rejected: \(String(describing: error), privacy: .public)")
    }
  }

  private static let handoffLogger = Logger(
    subsystem: "com.lorislab.webkitui-mcp", category: "human-handoff")

  private static func localizedHandoff(_ key: String, fallback: String) -> String {
    Bundle.main.localizedString(forKey: key, value: fallback, table: nil)
  }

  private static func humanControlApplicationIcon() -> NSImage? {
    NSImage(
      systemSymbolName: "globe.americas.fill",
      accessibilityDescription: "WebkitUIMCP")?
      .withSymbolConfiguration(.init(pointSize: 128, weight: .medium))
  }

  /// The returned observation is the only address space valid after handoff.
  public func resumeAfterHumanControl(maximumElements: Int = 500) async throws
    -> WebKitPageObservation
  {
    guard controlState == .resumeRequested else {
      throw WebKitRuntimeError.invalidControlTransition
    }
    do {
      if processTerminated {
        guard
          let url = lastCommittedHTTPURL,
          let scheme = url.scheme?.lowercased(),
          ["http", "https"].contains(scheme)
        else { throw WebKitRuntimeError.webContentProcessTerminated }
        _ = try await load(
          request: URLRequest(url: url),
          timeout: .seconds(30),
          quietWindow: .milliseconds(300)
        )
      }
      // Restoring the view is not the same as the page knowing about it. Observing
      // before WebKit has propagated the new size measures everything against the
      // viewport the human's turn left behind.
      await awaitViewportSettled()
      return try await observe(maximumElements: maximumElements)
    } catch {
      if controlState == .resumeRequested {
        presentHumanControlWindow()
        transition(to: .humanControlled, observationID: nil)
      }
      throw error
    }
  }

  /// Waits, briefly and boundedly, for the page's own viewport to agree with the view
  /// it lives in. Never fails: a page that cannot answer is observed anyway, and the
  /// observation still reports what it measured.
  private func awaitViewportSettled(timeout: Duration = .milliseconds(500)) async {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
      let expectedWidth = webView.bounds.width
      let expectedHeight = webView.bounds.height
      guard expectedWidth > 0, expectedHeight > 0 else { return }
      let reportedWidth =
        (try? await webView.evaluateJavaScript("window.innerWidth")) as? Double
      let reportedHeight =
        (try? await webView.evaluateJavaScript("window.innerHeight")) as? Double
      if let reportedWidth, let reportedHeight,
        abs(reportedWidth - expectedWidth) < 1,
        abs(reportedHeight - expectedHeight) < 1
      {
        return
      }
      webView.needsLayout = true
      webView.layoutSubtreeIfNeeded()
      try? await Task.sleep(for: .milliseconds(20))
    }
  }

  public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    webContentTerminationEvents.append(
      WebContentTerminationEvent(
        documentID: documentID,
        observationID: latestObservationID,
        monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds
      ))
    if webContentTerminationEvents.count > 128 {
      webContentTerminationEvents.removeFirst(webContentTerminationEvents.count - 128)
    }
    processTerminated = true
    latestObservationID = nil
    latestTargets.removeAll(keepingCapacity: true)
    registeredFrameCapabilities.removeAll(keepingCapacity: true)
    droppedFrameRegistrationCount = 0
  }

  @available(macOS 27.0, *)
  @objc(webView:willSubmitForm:submissionHandler:)
  public func webView(
    _ webView: WKWebView,
    willSubmitForm formInfo: WKFormInfo,
    submissionHandler: @escaping @MainActor () -> Void
  ) {
    struct Field: Codable {
      let name: String
      let value: String
    }
    struct Payload: Codable {
      let method: String
      let url: String
      let fields: [Field]
    }
    let method = formInfo.httpMethod.uppercased()
    let payload = Payload(
      method: method,
      url: formInfo.submissionURL.absoluteString,
      fields: formInfo.formValues.map { Field(name: $0.key, value: $0.value) }
        .sorted { lhs, rhs in
          lhs.name == rhs.name ? lhs.value < rhs.value : lhs.name < rhs.name
        }
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let digest: String
    if let data = try? encoder.encode(payload) {
      digest = HMAC<SHA256>.authenticationCode(for: data, using: formAuditKey)
        .map { String(format: "%02x", $0) }
        .joined()
    } else {
      digest = String(repeating: "0", count: 64)
    }
    formSubmissionEvents.append(
      FormSubmissionAuditEvent(
        payloadHMAC: digest,
        httpMethod: method,
        formValueCount: formInfo.formValues.count,
        sourceFrameIsMain: formInfo.sourceFrame.isMainFrame,
        targetFrameIsMain: formInfo.targetFrame.isMainFrame,
        monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds
      ))
    if formSubmissionEvents.count > 128 {
      formSubmissionEvents.removeFirst(formSubmissionEvents.count - 128)
    }
    // The exported receipt. Names, count, method and origin; never a value.
    submissionFacts = WebKitSubmissionFacts(
      origin: Self.sanitizedOrigin(for: formInfo.submissionURL),
      httpMethod: method,
      fieldCount: formInfo.formValues.count,
      fieldNames: Array(formInfo.formValues.keys.sorted().prefix(50)))
    // submissionHandler is a delay and not a veto: it carries no decision. The refusal
    // is recorded here and applied in the navigation policy handler.
    pendingSubmissionDecision = SubmissionApproval.decide(
      approvedOrigin: approvedSubmissionOrigin,
      submissionURL: formInfo.submissionURL,
      httpMethod: method)
    submissionHandler()
  }

  public func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction
  ) async -> WKNavigationActionPolicy {
    if navigationAction.targetFrame?.isMainFrame == false,
      let targetURL = navigationAction.request.url,
      Self.isRestrictedAuthenticationHost(targetURL.host)
    {
      restrictedAuthenticationFrameOrigin = Self.sanitizedOrigin(for: targetURL)
      if Self.requiresFullBrowserBackend(
        topLevelURL: webView.url ?? lastCommittedHTTPURL,
        restrictedFrameOrigin: restrictedAuthenticationFrameOrigin
      ) {
        authenticationUIClassification = .fullBrowserRequired
      }
    }
    if let expectedOrigin = downloadExpectedOrigin {
      guard let targetURL = navigationAction.request.url,
        navigationOrigin(for: targetURL) == expectedOrigin
      else {
        finishDownload(.failure(WebKitRuntimeError.networkBoundaryDenied))
        return .cancel
      }
      if navigationAction.shouldPerformDownload { return .download }
    }
    // WebKit's own account of the submission, taken from WKFormInfo a moment ago. It is
    // applied here because `submissionHandler` carries no decision, and it is applied
    // before the origin-lock branches so that a refusal does not depend on a lock being
    // held. The armed navigation actor is deliberately left alone: this path files no
    // audit event, so an agent-caused navigation keeps its attribution.
    if let decision = pendingSubmissionDecision {
      pendingSubmissionDecision = nil
      switch decision {
      case .refuseForeignOrigin, .refuseUnapproved:
        navigationFailure = WebKitRuntimeError.networkBoundaryDenied
        return .cancel
      case .allow:
        break
      }
    }
    guard let lockedOrigin = topLevelOriginLock else {
      prepareForAllowedMainFrameNavigation(navigationAction)
      recordNavigationAudit(navigationAction, allowed: true)
      return .allow
    }
    guard navigationAction.targetFrame?.isMainFrame == true else {
      guard navigationAction.targetFrame == nil else { return .allow }
      // A new-window request, asked here before `createWebViewWith`. A link to the
      // locked origin goes on and is followed in this view there; anything else is
      // refused here. It used to be refused without a word, which is exactly the
      // silent `target="_blank"` the suppression record exists to end.
      if navigationAction.navigationType == .linkActivated,
        let url = navigationAction.request.url,
        navigationOrigin(for: url) == lockedOrigin
      {
        return .allow
      }
      suppressedNewWindowRequest = WebKitSuppressedNewWindowRequest(
        destination: Self.sanitizedNewWindowDestination(navigationAction.request.url),
        navigationType: Self.navigationTypeName(navigationAction.navigationType),
        sourceFrameIsMain: navigationAction.sourceFrame.isMainFrame,
        monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds,
        followedInSameView: false)
      return .cancel
    }
    guard
      let targetURL = navigationAction.request.url,
      navigationOrigin(for: targetURL) == lockedOrigin
    else {
      let targetOrigin = navigationAction.request.url.flatMap(navigationOrigin(for:))
      let method = navigationAction.request.httpMethod?.uppercased() ?? "GET"
      pendingCrossOriginNavigationRequest =
        ["GET", "HEAD"].contains(method)
        ? navigationAction.request : nil
      navigationFailure = .crossOriginRedirectRequiresHuman(
        fromOrigin: Self.sanitizedOrigin(lockedOrigin),
        toOrigin: targetOrigin.map(Self.sanitizedOrigin) ?? "unavailable"
      )
      recordNavigationAudit(navigationAction, allowed: false)
      return .cancel
    }
    prepareForAllowedMainFrameNavigation(navigationAction)
    recordNavigationAudit(navigationAction, allowed: true)
    return .allow
  }

  public func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationResponse: WKNavigationResponse
  ) async -> WKNavigationResponsePolicy {
    guard downloadContinuation != nil else { return .allow }
    guard let responseURL = navigationResponse.response.url,
      let expectedOrigin = downloadExpectedOrigin,
      navigationOrigin(for: responseURL) == expectedOrigin
    else {
      finishDownload(.failure(WebKitRuntimeError.networkBoundaryDenied))
      return .cancel
    }
    let disposition =
      (navigationResponse.response as? HTTPURLResponse)?
      .value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
    if let response = navigationResponse.response as? HTTPURLResponse {
      downloadHTTPStatus = response.statusCode
      guard (200...299).contains(response.statusCode) else {
        finishDownload(
          .failure(WebKitRuntimeError.downloadHTTPFailure(status: response.statusCode)))
        return .cancel
      }
    }
    if !navigationResponse.canShowMIMEType || disposition.contains("attachment") {
      return .download
    }
    finishDownload(
      .failure(WebKitRuntimeError.unsupportedDownload(httpStatus: downloadHTTPStatus)))
    return .cancel
  }

  public func webView(
    _ webView: WKWebView,
    navigationAction: WKNavigationAction,
    didBecome download: WKDownload
  ) {
    beginDownload(download)
  }

  public func webView(
    _ webView: WKWebView,
    navigationResponse: WKNavigationResponse,
    didBecome download: WKDownload
  ) {
    beginDownload(download)
  }

  public func webView(
    _ webView: WKWebView,
    didStartProvisionalNavigation navigation: WKNavigation!
  ) {
    if downloadContinuation == nil { resetForNavigation() }
  }

  public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    let completedType = pendingMainFrameNavigationType
    let currentItem = webView.backForwardList.currentItem
    let currentItemID = currentItem.map(ObjectIdentifier.init)
    let resultedFromForm: Bool
    switch completedType {
    case .formSubmitted?, .formResubmitted?:
      resultedFromForm = true
    case .reload?:
      resultedFromForm = currentDocumentWasFormSubmission
    case .backForward?:
      resultedFromForm = currentItemID.map(formSubmissionHistoryItems.contains) ?? false
    default:
      resultedFromForm = false
    }
    currentDocumentWasFormSubmission = resultedFromForm
    if let currentItemID {
      if resultedFromForm {
        formSubmissionHistoryItems.insert(currentItemID)
      } else {
        formSubmissionHistoryItems.remove(currentItemID)
      }
    }
    let liveItems =
      webView.backForwardList.backList + [webView.backForwardList.currentItem].compactMap { $0 }
      + webView.backForwardList.forwardList
    let liveItemIDs = Set(liveItems.map(ObjectIdentifier.init))
    formSubmissionHistoryItems.formIntersection(liveItemIDs)
    pendingMainFrameNavigationType = nil
    rememberRecoverableURL(webView.url)
  }

  public func webView(
    _ webView: WKWebView,
    didFail navigation: WKNavigation!,
    withError error: any Error
  ) {
    pendingMainFrameNavigationType = nil
    if navigationFailure == nil && !(downloadStarted && Self.isDownloadCancellation(error)) {
      navigationFailure = Self.sanitizedNavigationFailure(error)
    }
  }

  public func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: any Error
  ) {
    pendingMainFrameNavigationType = nil
    if navigationFailure == nil && !(downloadStarted && Self.isDownloadCancellation(error)) {
      navigationFailure = Self.sanitizedNavigationFailure(error)
    }
  }

  public func download(
    _ download: WKDownload,
    decideDestinationUsing response: URLResponse,
    suggestedFilename: String,
    completionHandler: @escaping @MainActor (URL?) -> Void
  ) {
    guard download === activeDownload, downloadContinuation != nil else {
      completionHandler(nil)
      return
    }
    downloadMIMEType = response.mimeType
    downloadHTTPStatus = (response as? HTTPURLResponse)?.statusCode ?? downloadHTTPStatus
    downloadSuggestedFilename = Self.safeSuggestedFilename(suggestedFilename)
    Task { @MainActor [weak self] in
      guard let self else {
        completionHandler(nil)
        return
      }
      let proposed = await self.proposedDownloadDestination(suggestedFilename: suggestedFilename)
      guard let proposed else {
        completionHandler(nil)
        self.finishDownload(.failure(WebKitRuntimeError.downloadCancelled))
        return
      }
      let destination = Self.collisionSafeDestination(for: proposed)
      self.downloadDestination = destination
      completionHandler(destination)
    }
  }

  public func downloadDidFinish(_ download: WKDownload) {
    guard download === activeDownload, let destination = downloadDestination else { return }
    do {
      let data = try Data(contentsOf: destination, options: .mappedIfSafe)
      let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
      let profileUUID = Self.provisioningProfileUUID(from: data)
      if let expected = downloadExpectedProvisioningProfileUUID,
        profileUUID?.localizedCaseInsensitiveCompare(expected) != .orderedSame
      {
        finishDownload(
          .failure(WebKitRuntimeError.downloadFailed("provisioning_profile_uuid_mismatch")))
        return
      }
      let receipt = WebKitDownloadReceipt(
        httpStatus: downloadHTTPStatus,
        suggestedFilename: downloadSuggestedFilename ?? destination.lastPathComponent,
        filename: destination.lastPathComponent,
        mimeType: downloadMIMEType,
        byteCount: UInt64(data.count),
        sha256: digest,
        provisioningProfileUUID: profileUUID)
      if downloadActionVerified {
        finishDownload(.success(receipt))
      } else {
        completedDownloadReceipt = receipt
      }
    } catch {
      finishDownload(.failure(WebKitRuntimeError.downloadFailed("integrity_receipt_unavailable")))
    }
  }

  public func download(
    _ download: WKDownload,
    didFailWithError error: any Error,
    resumeData: Data?
  ) {
    guard download === activeDownload else { return }
    if let destination = downloadDestination {
      try? FileManager.default.removeItem(at: destination)
    }
    finishDownload(.failure(WebKitRuntimeError.downloadFailed(Self.sanitizedError(error))))
  }

  public func download(
    _ download: WKDownload,
    decidedPolicyForHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest
  ) async -> WKDownload.RedirectPolicy {
    guard download === activeDownload,
      let expectedOrigin = downloadExpectedOrigin,
      let url = request.url,
      navigationOrigin(for: url) == expectedOrigin
    else { return .cancel }
    return .allow
  }

  private func beginDownload(_ download: WKDownload) {
    guard downloadContinuation != nil else {
      download.cancel { _ in }
      return
    }
    downloadStarted = true
    activeDownload = download
    download.delegate = self
    navigationFailure = nil
  }

  private func proposedDownloadDestination(suggestedFilename: String) async -> URL? {
    let filename = Self.safeSuggestedFilename(suggestedFilename)
    if let downloadDestinationProvider {
      return await downloadDestinationProvider(filename)
    }
    let panel = NSSavePanel()
    panel.title = "Save Browser Download"
    panel.prompt = "Save"
    panel.canCreateDirectories = true
    panel.nameFieldStringValue = filename
    return panel.runModal() == .OK ? panel.url : nil
  }

  private func finishDownload(_ result: Result<WebKitDownloadReceipt, any Error>) {
    guard let continuation = downloadContinuation else { return }
    if case .failure = result, let downloadDestination {
      try? FileManager.default.removeItem(at: downloadDestination)
    }
    downloadTimeoutTask?.cancel()
    downloadTimeoutTask = nil
    downloadContinuation = nil
    downloadExpectedOrigin = nil
    downloadDestination = nil
    downloadMIMEType = nil
    downloadHTTPStatus = nil
    downloadSuggestedFilename = nil
    downloadExpectedProvisioningProfileUUID = nil
    downloadStarted = false
    downloadActionVerified = false
    completedDownloadReceipt = nil
    activeDownload = nil
    continuation.resume(with: result)
  }

  private static func safeSuggestedFilename(_ value: String) -> String {
    let component = URL(fileURLWithPath: value).lastPathComponent
      .filter { !$0.isNewline && !$0.isASCII || ($0.asciiValue.map { $0 >= 32 } ?? false) }
    return component.isEmpty || component == "." || component == ".." ? "download" : component
  }

  private static func safeUploadFilename(_ value: String) -> String? {
    guard !value.isEmpty, value.count <= 255, value != ".", value != ".." else { return nil }
    let bidiControls: Set<UInt32> = [
      0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
      0x2066, 0x2067, 0x2068, 0x2069,
    ]
    let rejected = CharacterSet.controlCharacters.union(.illegalCharacters)
    guard
      value.unicodeScalars.allSatisfy({
        !rejected.contains($0) && !bidiControls.contains($0.value)
      })
    else { return nil }
    return value
  }

  static func provisioningProfileUUID(from data: Data) -> String? {
    if let value = propertyListUUID(from: data) { return value }
    guard !data.isEmpty else { return nil }
    var decoder: CMSDecoder?
    guard CMSDecoderCreate(&decoder) == errSecSuccess, let decoder else { return nil }
    let updateStatus = data.withUnsafeBytes { bytes in
      CMSDecoderUpdateMessage(decoder, bytes.baseAddress!, bytes.count)
    }
    guard updateStatus == errSecSuccess,
      CMSDecoderFinalizeMessage(decoder) == errSecSuccess
    else { return nil }
    var content: CFData?
    guard CMSDecoderCopyContent(decoder, &content) == errSecSuccess, let content else { return nil }
    return propertyListUUID(from: content as Data)
  }

  private static func propertyListUUID(from data: Data) -> String? {
    guard
      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
      let dictionary = plist as? [String: Any],
      let uuid = dictionary["UUID"] as? String,
      !uuid.isEmpty
    else { return nil }
    return uuid
  }

  private static func collisionSafeDestination(for requested: URL) -> URL {
    guard FileManager.default.fileExists(atPath: requested.path) else { return requested }
    let directory = requested.deletingLastPathComponent()
    let extensionName = requested.pathExtension
    let stem = requested.deletingPathExtension().lastPathComponent
    for index in 2...10_000 {
      let name = extensionName.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(extensionName)"
      let candidate = directory.appendingPathComponent(name, isDirectory: false)
      if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
    }
    return directory.appendingPathComponent("\(UUID().uuidString)-\(requested.lastPathComponent)")
  }

  private static func isDownloadCancellation(_ error: any Error) -> Bool {
    let error = error as NSError
    return error.domain == WKError.errorDomain && error.code == 102
  }

  private static func sanitizedError(_ error: any Error) -> String {
    let error = error as NSError
    return "\(error.domain) code=\(error.code)"
  }

  private func load(
    request: URLRequest,
    timeout: Duration,
    quietWindow: Duration
  ) async throws -> WebKitNavigationResult {
    try validate(quietWindow: quietWindow)
    resetForNavigation()
    armNavigationActor(.agentNavigation)
    let started = DispatchTime.now().uptimeNanoseconds
    webView.load(request)
    let readiness = try await awaitReadiness(timeout: timeout, quietWindow: quietWindow)
    if readiness == .deadlineReached { webView.stopLoading() }
    let state = try await instrumentationState(includeContentState: readiness == .ready)
    let contentState = readiness == .ready ? state.contentState ?? .unknown : .unknown
    await refreshAuthenticationUIClassification()
    rememberRecoverableURL(webView.url ?? request.url)
    processTerminated = false
    let loadedURL = webView.url ?? request.url
    return WebKitNavigationResult(
      documentID: documentID,
      url: agentSafeURLString(loadedURL) ?? "about:blank",
      requestedURL: request.url.flatMap(agentSafeURLString) ?? "about:blank",
      readiness: readiness,
      contentState: contentState,
      elapsedNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
      mutationCount: state.mutationCount
    )
  }

  private func locatorCriteria(
    _ recipe: LocatorRecipe,
    expectedEnabled: Bool? = nil,
    maximumFieldCharacters: Int = 4_096
  ) -> [[String: String]] {
    var criteria = recipe.clauses.map { clause in
      let fact: String
      let argument: String
      switch clause.fact {
      case .role:
        fact = "role"
        argument = ""
      case .accessibleName:
        fact = "accessibleName"
        argument = ""
      case .label:
        fact = "label"
        argument = ""
      case .contextAnchor(let name):
        fact = "contextAnchor"
        argument = name
      case .stableAttribute(let name):
        fact = "stableAttribute"
        argument = name
      case .framePath:
        fact = "framePath"
        argument = ""
      case .value:
        fact = "text"
        argument = ""
      case .domPath:
        fact = "domPath"
        argument = ""
      }
      return [
        "fact": fact,
        "argument": argument,
        "expected": clause.expectedValue,
        "strength": clause.strength.rawValue,
        "comparison": clause.comparison.rawValue,
        // The observation bounded these facts before constructing the recipe. Apply
        // the same bound when resolving it again, or a long but unchanged label can
        // never equal the address the observation handed out.
        "maximumCharacters": String(maximumFieldCharacters),
      ]
    }
    if let expectedEnabled {
      criteria.append([
        "fact": "enabled",
        "argument": "",
        "expected": String(expectedEnabled),
        "strength": "required",
        "comparison": "exact",
        "maximumCharacters": String(maximumFieldCharacters),
      ])
    }
    return criteria
  }

  /// Builds the live checks for an action. Main-document behaviour keeps using its
  /// public recipe. An embedded target uses a provenance-private semantic recipe and
  /// also binds the mutable state that was actually observed, so a changed checkbox,
  /// option, or ARIA state cannot be mistaken for the confirmed control.
  private func actionLocatorCriteria(
    for target: ObservedTargetRecord,
    publicRecipe: LocatorRecipe,
    includeObservedState: Bool = true
  ) -> [[String: String]] {
    let recipe = target.frameCapabilityID == nil ? publicRecipe : target.resolutionRecipe
    var criteria = locatorCriteria(
      recipe,
      expectedEnabled: !target.disabled,
      maximumFieldCharacters: target.maximumFieldCharacters)
    guard target.frameCapabilityID != nil, includeObservedState else { return criteria }

    func appendState(_ fact: String, argument: String = "", expected: String) {
      criteria.append([
        "fact": fact,
        "argument": argument,
        "expected": expected,
        "strength": "required",
        "comparison": "exact",
        "maximumCharacters": String(target.maximumFieldCharacters),
      ])
    }
    if let checked = target.checked {
      appendState("checked", expected: String(checked))
    }
    if let selected = target.selected {
      appendState("selected", expected: String(selected))
    }
    if let selectedOption = target.selectedOption {
      appendState("selectedOption", expected: selectedOption)
    }
    for (name, value) in target.stateAttributes.sorted(by: { $0.key < $1.key }) {
      appendState("stateAttribute", argument: name, expected: value)
    }
    return criteria
  }

  private func frameActionContext(
    for target: ObservedTargetRecord
  ) throws -> FrameActionContext? {
    guard let capabilityID = target.frameCapabilityID else { return nil }
    guard
      let expectedOrigin = target.frameOrigin,
      let capability = registeredFrameCapabilities.first(where: {
        $0.capabilityID == capabilityID && $0.documentID == documentID && !$0.isMainFrame
      }),
      capability.origin == expectedOrigin
    else {
      invalidateCurrentObservation()
      throw WebKitRuntimeError.staleObservation
    }
    return FrameActionContext(
      capabilityID: capabilityID,
      documentID: documentID,
      observationID: target.recipe.observationID,
      origin: expectedOrigin,
      frameInfo: capability.frameInfo)
  }

  private func resolveTarget(
    criteria: [[String: String]],
    scrollIntoView: Bool,
    physicalIdentity: String = "",
    expectedCandidateCount: Int = 0,
    frameContext: FrameActionContext? = nil
  ) async throws -> RawActionResolution {
    try await actionScript(
      source: Self.resolveSource,
      arguments: [
        "criteria": criteria,
        "physicalIdentity": physicalIdentity,
        "expectedCandidateCount": expectedCandidateCount,
        "scrollIntoView": scrollIntoView,
      ],
      frameContext: frameContext
    )
  }

  private func resolveAndPerform(
    criteria: [[String: String]],
    physicalIdentity: String,
    expectedCandidateCount: Int,
    expectedBoundingBox: ObservedBoundingBox,
    operation: String,
    value: String?,
    modifiers: Set<WebKitKeyModifier> = [],
    frameContext: FrameActionContext? = nil
  ) async throws -> RawActionResolution {
    var arguments: [String: Any] = [
      "criteria": criteria,
      "physicalIdentity": physicalIdentity,
      "expectedCandidateCount": expectedCandidateCount,
      "expectedBox": [
        "x": expectedBoundingBox.x,
        "y": expectedBoundingBox.y,
        "width": expectedBoundingBox.width,
        "height": expectedBoundingBox.height,
      ],
      "operation": operation,
    ]
    if let value { arguments["value"] = value }
    // The JavaScript route is untrusted and says so, but it must still dispatch the
    // chord that was approved: an unmodified event where a modified one was confirmed
    // would be a different keystroke than the operator read.
    arguments["modifiers"] = WebKitKeyModifier.displayOrder.filter(modifiers.contains)
      .map(\.rawValue)
    return try await actionScript(
      source: Self.performSource, arguments: arguments, frameContext: frameContext)
  }

  /// Resolves the control again from its own criteria and reads what its options say.
  /// Used twice for one selection — once to refuse an ambiguous label before anything is
  /// dispatched, once afterwards to verify what a freshly re-resolved control now
  /// reports as selected — because both questions are about the live control rather than
  /// about a handle that may already have been replaced.
  ///
  /// It runs through the dialog race like the dispatch itself: a `change` handler that
  /// opens a panel suspends the page, and a script waiting on a suspended page never
  /// returns.
  private func surveySelectedOption(
    criteria: [[String: String]],
    physicalIdentity: String,
    expectedCandidateCount: Int,
    label: String,
    alreadyDispatched: Bool,
    frameContext: FrameActionContext? = nil
  ) async throws -> RawActionResolution {
    let race = try await dispatchRacingJavaScriptDialog { [self] in
      try await actionScript(
        source: Self.selectedOptionSurveySource,
        arguments: [
          "criteria": criteria,
          "physicalIdentity": physicalIdentity,
          "expectedCandidateCount": expectedCandidateCount,
          "label": label,
        ],
        frameContext: frameContext)
    }
    let survey: RawActionResolution
    switch race {
    case .resolved(let resolution):
      survey = resolution
    case .interruptedByDialog(let dialog):
      // Before dispatch nothing has been sent, so this is a panel that was already in
      // the page's way. After dispatch the gesture landed and the page then stopped
      // running, which is the same uncertainty the dispatch path reports.
      throw alreadyDispatched
        ? WebKitRuntimeError.javaScriptDialogOpenedByAction(
          kind: dialog.kind.rawValue, dialogID: dialog.dialogID)
        : WebKitRuntimeError.javaScriptDialogPending(
          kind: dialog.kind.rawValue, dialogID: dialog.dialogID)
    }
    if alreadyDispatched {
      // A control that no longer resolves uniquely cannot confirm anything, and saying
      // "not unique" here would claim nothing was dispatched when something was.
      guard survey.count == 1 else { throw WebKitRuntimeError.selectedOptionMismatch }
      return survey
    }
    guard survey.count == 1, let candidate = survey.candidate else {
      if survey.count == 0 { throw WebKitRuntimeError.targetNotFound(survey.eliminatedBy ?? []) }
      throw WebKitRuntimeError.targetNotUnique(
        survey.count, pinned: survey.pinnedState ?? "not_requested")
    }
    guard survey.matchingOptionCount != nil else {
      throw WebKitRuntimeError.operationUnsupportedForControl(
        role: candidate.role ?? "control",
        alternative:
          "select_option addresses a native <select> and its <option> labels. A custom "
          + "combobox is driven by clicking it open and pressing the arrow keys.")
    }
    return survey
  }

  private func resolveAndPerformNativeClick(
    criteria: [[String: String]],
    physicalIdentity: String,
    expectedCandidateCount: Int,
    expectedBoundingBox: ObservedBoundingBox
  ) async throws -> RawActionResolution {
    let token = UUID().uuidString
    armedNativeGestureTokens[token] = ArmedNativeGestureContext(
      frameCapabilityID: nil, frameOrigin: nil)
    defer {
      armedNativeGestureTokens.removeValue(forKey: token)
      nativeGestureReceipts.removeValue(forKey: token)
    }
    let armed = try await actionScript(
      source: Self.armNativeClickSource,
      arguments: [
        "criteria": criteria,
        "physicalIdentity": physicalIdentity,
        "expectedCandidateCount": expectedCandidateCount,
        "expectedBox": Self.boxDictionary(expectedBoundingBox),
        "token": token,
      ])
    guard armed.count == 1, let candidate = armed.candidate else { return armed }
    guard candidate.geometryStable, candidate.actionable else { return armed }

    try dispatchNativeMouseClick(at: candidate.boundingBox)
    let deadline = ContinuousClock.now + .seconds(1)
    while ContinuousClock.now < deadline {
      if let receipt = nativeGestureReceipt(
        token: token, physicalIdentity: candidate.physicalIdentity, eventType: "click")
      {
        return RawActionResolution(
          count: armed.count,
          candidate: RawActionCandidate(
            physicalIdentity: candidate.physicalIdentity,
            boundingBox: candidate.boundingBox,
            geometryStable: candidate.geometryStable,
            actionable: candidate.actionable,
            dispatched: true,
            trustedUserGesture: receipt.trusted,
            unsupportedOperationRole: nil
          ),
          eliminatedBy: nil, pinnedState: nil)
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw WebKitRuntimeError.nativeGestureReceiptUnavailable
  }

  private func dispatchNativeMouseClick(at box: ObservedBoundingBox) throws {
    guard let window = webView.window else { throw WebKitRuntimeError.targetNotActionable }
    let localPoint = NSPoint(
      x: box.x + box.width / 2,
      y: webView.isFlipped
        ? box.y + box.height / 2
        : webView.bounds.height - (box.y + box.height / 2)
    )
    let windowPoint = webView.convert(localPoint, to: nil)
    let timestamp = ProcessInfo.processInfo.systemUptime
    guard
      let down = NSEvent.mouseEvent(
        with: .leftMouseDown, location: windowPoint, modifierFlags: [],
        timestamp: timestamp, windowNumber: window.windowNumber, context: nil,
        eventNumber: 0, clickCount: 1, pressure: 1),
      let up = NSEvent.mouseEvent(
        with: .leftMouseUp, location: windowPoint, modifierFlags: [],
        timestamp: timestamp + 0.001, windowNumber: window.windowNumber, context: nil,
        eventNumber: 0, clickCount: 1, pressure: 0)
    else { throw WebKitRuntimeError.targetNotActionable }
    webView.mouseDown(with: down)
    webView.mouseUp(with: up)
  }

  private func resolveAndPerformNativeKey(
    criteria: [[String: String]],
    physicalIdentity: String,
    expectedCandidateCount: Int,
    expectedBoundingBox: ObservedBoundingBox,
    press: WebKitKeyPress,
    frameContext: FrameActionContext? = nil
  ) async throws -> RawActionResolution {
    // Before the page is touched at all, and before the operator's approval turns into a
    // keystroke: a key with no code, or a chord the app's own menu claims, is refused
    // while the keyboard is still idle rather than approximated.
    let event = try WebKitKeyCatalogue.event(for: press)
    let key = press.key
    guard let window = webView.window, window.makeFirstResponder(webView) else {
      throw WebKitRuntimeError.targetNotActionable
    }
    let token = UUID().uuidString
    armedNativeGestureTokens[token] = ArmedNativeGestureContext(
      frameCapabilityID: frameContext?.capabilityID,
      frameOrigin: frameContext?.origin)
    defer {
      armedNativeGestureTokens.removeValue(forKey: token)
      nativeGestureReceipts.removeValue(forKey: token)
    }
    let armed = try await actionScript(
      source: Self.armNativeKeySource,
      arguments: [
        "criteria": criteria,
        "physicalIdentity": physicalIdentity,
        "expectedCandidateCount": expectedCandidateCount,
        "expectedBox": Self.boxDictionary(expectedBoundingBox),
        "token": token,
        "expectedKey": key,
      ],
      frameContext: frameContext)
    guard armed.count == 1, let candidate = armed.candidate else { return armed }
    guard candidate.geometryStable, candidate.actionable else { return armed }
    try dispatchNativeKey(event)
    let expectedReceiptEvent = key == "Tab" ? "blur" : "keydown"
    let deadline = ContinuousClock.now + .seconds(1)
    while ContinuousClock.now < deadline {
      if let receipt = nativeGestureReceipt(
        token: token, physicalIdentity: candidate.physicalIdentity,
        eventType: expectedReceiptEvent)
      {
        if frameContext != nil, !receipt.trusted {
          throw WebKitRuntimeError.nativeGestureReceiptUnavailable
        }
        return RawActionResolution(
          count: armed.count,
          candidate: RawActionCandidate(
            physicalIdentity: candidate.physicalIdentity,
            boundingBox: candidate.boundingBox,
            geometryStable: candidate.geometryStable,
            actionable: candidate.actionable,
            dispatched: true,
            trustedUserGesture: receipt.trusted,
            unsupportedOperationRole: nil
          ),
          eliminatedBy: nil, pinnedState: nil)
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw WebKitRuntimeError.nativeGestureReceiptUnavailable
  }

  private func resolveAndPerformNativeFill(
    criteria: [[String: String]],
    physicalIdentity: String,
    expectedCandidateCount: Int,
    expectedBoundingBox: ObservedBoundingBox,
    value: String,
    frameContext: FrameActionContext? = nil
  ) async throws -> RawActionResolution {
    guard let window = webView.window, window.makeFirstResponder(webView) else {
      throw WebKitRuntimeError.targetNotActionable
    }
    let token = UUID().uuidString
    armedNativeGestureTokens[token] = ArmedNativeGestureContext(
      frameCapabilityID: frameContext?.capabilityID,
      frameOrigin: frameContext?.origin)
    defer {
      armedNativeGestureTokens.removeValue(forKey: token)
      nativeGestureReceipts.removeValue(forKey: token)
    }
    let armed = try await actionScript(
      source: Self.armNativeFillSource,
      arguments: [
        "criteria": criteria,
        "physicalIdentity": physicalIdentity,
        "expectedCandidateCount": expectedCandidateCount,
        "expectedBox": Self.boxDictionary(expectedBoundingBox),
        "token": token,
      ],
      frameContext: frameContext)
    guard armed.count == 1, let candidate = armed.candidate else { return armed }
    guard candidate.geometryStable, candidate.actionable else { return armed }

    // The arming script selected the old contents, but a rich-text editor restores
    // its own caret on the task after focus: Reddit's composer kept its draft and
    // the new text was appended to it (2026-09-23). Select All is WebKit's own
    // editing command, scoped to the focused editable and issued in the same turn as
    // the insertion, so it is what the insertion replaces.
    webView.selectAll(nil)
    webView.insertText(value)
    let deadline = ContinuousClock.now + .seconds(1)
    while ContinuousClock.now < deadline {
      if let inputReceipt = nativeGestureReceipt(
        token: token, physicalIdentity: candidate.physicalIdentity, eventType: "input")
      {
        // Commit within the same confirmed action. A later action can address
        // a framework replacement node and leave validation state untouched.
        try dispatchNativeKey(WebKitKeyCatalogue.event(for: "Tab"))
        let commitDeadline = ContinuousClock.now + .seconds(1)
        while ContinuousClock.now < commitDeadline {
          if let commitReceipt = nativeGestureReceipt(
            token: token, physicalIdentity: candidate.physicalIdentity,
            eventType: "commit_keydown")
          {
            if frameContext != nil, !(inputReceipt.trusted && commitReceipt.trusted) {
              throw WebKitRuntimeError.nativeGestureReceiptUnavailable
            }
            return RawActionResolution(
              count: armed.count,
              candidate: RawActionCandidate(
                physicalIdentity: candidate.physicalIdentity,
                boundingBox: candidate.boundingBox,
                geometryStable: candidate.geometryStable,
                actionable: candidate.actionable,
                dispatched: true,
                trustedUserGesture: inputReceipt.trusted && commitReceipt.trusted,
                unsupportedOperationRole: nil
              ),
              eliminatedBy: nil, pinnedState: nil)
          }
          try await Task.sleep(for: .milliseconds(10))
        }
        throw WebKitRuntimeError.nativeGestureReceiptUnavailable
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw WebKitRuntimeError.nativeGestureReceiptUnavailable
  }

  private func nativeGestureReceipt(
    token: String,
    physicalIdentity: String,
    eventType: String
  ) -> NativeGestureReceipt? {
    nativeGestureReceipts[token]?.first {
      $0.physicalIdentity == physicalIdentity && $0.eventType == eventType
    }
  }

  private func dispatchNativeKey(_ event: WebKitKeyCatalogue.NativeKeyEvent) throws {
    guard let window = webView.window else { throw WebKitRuntimeError.targetNotActionable }
    let timestamp = ProcessInfo.processInfo.systemUptime
    guard
      let down = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: event.flags, timestamp: timestamp,
        windowNumber: window.windowNumber, context: nil, characters: event.characters,
        charactersIgnoringModifiers: event.characters, isARepeat: false,
        keyCode: event.keyCode),
      let up = NSEvent.keyEvent(
        with: .keyUp, location: .zero, modifierFlags: event.flags, timestamp: timestamp + 0.001,
        windowNumber: window.windowNumber, context: nil, characters: event.characters,
        charactersIgnoringModifiers: event.characters, isARepeat: false,
        keyCode: event.keyCode)
    else { throw WebKitRuntimeError.targetNotActionable }
    window.sendEvent(down)
    window.sendEvent(up)
  }

  private func actionScript(
    source: String,
    arguments: [String: Any],
    frameContext: FrameActionContext? = nil
  ) async throws -> RawActionResolution {
    var evaluatedSource = source
    var evaluatedArguments = arguments
    if let frameContext {
      evaluatedSource = Self.frameActionGuardSource + source
      evaluatedArguments["expectedFrameCapabilityID"] = frameContext.capabilityID
      evaluatedArguments["expectedFrameOrigin"] = frameContext.origin
    }
    let rawResult: Any?
    do {
      rawResult = try await webView.callAsyncJavaScript(
        evaluatedSource,
        arguments: evaluatedArguments,
        in: frameContext?.frameInfo,
        contentWorld: instrumentationWorld)
    } catch {
      if let frameContext {
        registeredFrameCapabilities.removeAll {
          $0.capabilityID == frameContext.capabilityID
        }
        invalidateCurrentObservation()
        throw WebKitRuntimeError.staleObservation
      }
      throw error
    }
    guard
      let json = rawResult as? String,
      let data = json.data(using: .utf8),
      let result = try? JSONDecoder().decode(RawActionResolution.self, from: data)
    else { throw WebKitRuntimeError.malformedInstrumentationResult }
    if let frameContext {
      guard
        result.frameContextMatches != false,
        documentID == frameContext.documentID,
        latestObservationID == frameContext.observationID,
        registeredFrameCapabilities.contains(where: {
          $0.capabilityID == frameContext.capabilityID
            && $0.documentID == frameContext.documentID
            && $0.origin == frameContext.origin
            && !$0.isMainFrame
        })
      else {
        registeredFrameCapabilities.removeAll {
          $0.capabilityID == frameContext.capabilityID
        }
        invalidateCurrentObservation()
        throw WebKitRuntimeError.staleObservation
      }
    }
    return result
  }

  private func performScroll(
    source: String,
    arguments: [String: Any]
  ) async throws -> WebKitScrollResult {
    guard
      let json = try await webView.callAsyncJavaScript(
        source,
        arguments: arguments,
        in: nil,
        contentWorld: instrumentationWorld
      ) as? String,
      let data = json.data(using: .utf8),
      let result = try? JSONDecoder().decode(WebKitScrollResult.self, from: data)
    else { throw WebKitRuntimeError.malformedInstrumentationResult }
    latestObservationID = nil
    latestTargets.removeAll(keepingCapacity: true)
    return result
  }

  private func recordCardinality(
    _ count: Int, target: ObservedTargetRecord, eliminatedBy: [String] = [],
    pinnedState: String = "not_requested"
  ) throws {
    guard count != 1 else { return }
    let now = DispatchTime.now().uptimeNanoseconds
    // Measuring a failure must never replace it. An attempt that cannot be recorded
    // — a document replaced under us moves the generation backwards — is dropped,
    // and the caller still learns why addressing failed.
    if let attempt = try? AddressingAttempt(
      observationID: target.recipe.observationID,
      locatorRecipeID: target.recipe.elementID,
      observationGeneration: target.recipe.observationGeneration,
      actionGeneration: observationGeneration,
      observationMonotonicNanoseconds: target.observedAtMonotonicNanoseconds,
      actionMonotonicNanoseconds: now,
      finalCandidateCount: count,
      semanticComparison: .unknown,
      physicalIdentity: .unknown,
      geometryComparison: .unknown
    ) {
      addressingCounters.record(AddressingClassifier.classify(attempt))
    }
    if count == 0 { throw WebKitRuntimeError.targetNotFound(eliminatedBy) }
    throw WebKitRuntimeError.targetNotUnique(count, pinned: pinnedState)
  }

  private func requireMainFrameActionTarget(_ target: ObservedTargetRecord) throws {
    guard target.frameCapabilityID == nil else {
      throw WebKitRuntimeError.crossOriginFrameActionUnavailable(
        target.frameOrigin ?? "unavailable")
    }
  }

  private func requireAgentControl() throws {
    try requireAgentControlIgnoringJavaScriptDialog()
    try requireNoPendingJavaScriptDialog()
  }

  /// The one route that may run while a panel is open: answering it. Everything else
  /// goes through `requireAgentControl`.
  private func requireAgentControlIgnoringJavaScriptDialog() throws {
    guard controlState == .agentControlled || controlState == .freshlyReobserved else {
      throw WebKitRuntimeError.humanControlActive
    }
    try requireNonAuthenticationOrigin()
  }

  /// A JavaScript panel suspends the page's script, so every route into the page —
  /// acting, scrolling, reading text, capturing — would block on instrumentation that
  /// cannot run until somebody answers. The state that forbids acting is named rather
  /// than waited on, exactly as human control is.
  private func requireNoPendingJavaScriptDialog() throws {
    if let dialog = pendingJavaScriptDialogState?.dialog {
      throw WebKitRuntimeError.javaScriptDialogPending(
        kind: dialog.kind.rawValue, dialogID: dialog.dialogID)
    }
  }

  private func requireObservationControl() throws {
    guard
      controlState != .handoffRequested,
      controlState != .humanControlled,
      controlState != .humanStepCompleted
    else {
      throw WebKitRuntimeError.humanControlActive
    }
    try requireNonAuthenticationOrigin()
  }

  private func requireNonAuthenticationOrigin() throws {
    if let origin = restrictedAuthenticationOrigin() {
      throw WebKitRuntimeError.authenticationOriginRequiresHuman(origin)
    }
  }

  private func transition(to next: InteractionControlState, observationID: String?) {
    let previous = controlState
    controlState = next
    handoffEvents.append(
      HandoffAuditEvent(
        from: previous,
        to: next,
        documentID: documentID,
        observationID: observationID,
        monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds
      ))
  }

  private func resetForNavigation() {
    documentID = UUID().uuidString
    frameSemanticKey = SymmetricKey(size: .bits256)
    observationGeneration = 0
    navigationFailure = nil
    processTerminated = false
    authenticationUIClassification = nil
    restrictedAuthenticationFrameOrigin = nil
    restrictedWebAuthnOrigin = nil
    pendingCrossOriginNavigationRequest = nil
    // A suppressed window belongs to the document that asked for it. Left standing, a
    // later unrelated action would report a suppression that happened on a page nobody is
    // looking at any more.
    suppressedNewWindowRequest = nil
    // An approval is granted for the page the operator was shown. A fresh navigation
    // supersedes it, and a decision nothing consumed must not cancel a later navigation.
    approvedSubmissionOrigin = nil
    pendingSubmissionDecision = nil
    permissionDenials.removeAll(keepingCapacity: true)
    permissionDenialCount = 0
    permissionDenialsTruncated = false
    registeredFrameCapabilities.removeAll(keepingCapacity: true)
    droppedFrameRegistrationCount = 0
    invalidateCurrentObservation()
  }

  private func registerFrameCapability(_ frameInfo: WKFrameInfo) {
    frameRegistrationGeneration &+= 1
    // A document-start message from a child means the address space observed before it
    // no longer describes the complete frame tree. There is no public stable frame ID
    // with which to expire only one exported element set, so the observation lease is
    // invalidated and the next observation rebuilds every bounded target honestly.
    if !frameInfo.isMainFrame, latestObservationID != nil {
      invalidateCurrentObservation()
    }
    if registeredFrameCapabilities.count == Self.maximumRegisteredFrameCapabilities {
      registeredFrameCapabilities.removeFirst()
      let (nextCount, overflow) = droppedFrameRegistrationCount.addingReportingOverflow(1)
      droppedFrameRegistrationCount = overflow ? UInt64.max : nextCount
    }
    registeredFrameCapabilities.append(
      RegisteredFrameCapability(
        capabilityID: UUID().uuidString,
        documentID: documentID,
        frameInfo: frameInfo,
        origin: Self.agentSafeSecurityOrigin(frameInfo.securityOrigin),
        isMainFrame: frameInfo.isMainFrame))
  }

  private func bindFrameCapabilitiesToIsolatedWorld() async {
    let capabilities = registeredFrameCapabilities.filter { $0.documentID == documentID }
    for capability in capabilities {
      do {
        let result = try await webView.callAsyncJavaScript(
          Self.bindFrameCapabilitySource,
          arguments: ["capabilityID": capability.capabilityID],
          in: capability.frameInfo,
          contentWorld: instrumentationWorld)
        guard result as? Bool == true else {
          registeredFrameCapabilities.removeAll {
            $0.capabilityID == capability.capabilityID
          }
          continue
        }
      } catch {
        registeredFrameCapabilities.removeAll {
          $0.capabilityID == capability.capabilityID
        }
      }
    }
  }

  /// A separately evaluated process must not make the whole observation wait forever.
  /// The JavaScript task is deliberately abandoned after the first settlement: WebKit's
  /// async evaluation is not cancellable, but its eventual reply finds no continuation.
  private func captureFrameRawObservation(
    script: String,
    arguments: [String: Any],
    frame: WKFrameInfo,
    timeout: Duration
  ) async throws -> RawObservation {
    frameObservationRaceToken &+= 1
    let token = frameObservationRaceToken
    Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        guard
          let json = try await self.webView.callAsyncJavaScript(
            script, arguments: arguments, in: frame,
            contentWorld: self.instrumentationWorld) as? String,
          let data = json.data(using: .utf8),
          let raw = try? JSONDecoder().decode(RawObservation.self, from: data)
        else { throw WebKitRuntimeError.malformedInstrumentationResult }
        self.settleFrameObservation(token: token, .success(raw))
      } catch {
        self.settleFrameObservation(token: token, .failure(error))
      }
    }
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: timeout)
      self?.settleFrameObservation(
        token: token, .failure(FrameObservationEvaluationError.timedOut))
    }
    return try await withCheckedThrowingContinuation { continuation in
      frameObservationRaceContinuations[token] = continuation
    }
  }

  private func settleFrameObservation(
    token: UInt64,
    _ result: Result<RawObservation, any Error>
  ) {
    guard let continuation = frameObservationRaceContinuations.removeValue(forKey: token) else {
      return
    }
    continuation.resume(with: result)
  }

  private func recordPermissionDenial(
    _ permission: WebKitDeniedPermission,
    origin: WKSecurityOrigin,
    frameIsMain: Bool
  ) {
    let requestedOrigin = Self.agentSafeSecurityOrigin(origin)
    let now = DispatchTime.now().uptimeNanoseconds
    let (nextTotal, totalOverflow) = permissionDenialCount.addingReportingOverflow(1)
    permissionDenialCount = totalOverflow ? UInt64.max : nextTotal
    if let index = permissionDenials.firstIndex(where: {
      $0.origin == requestedOrigin && $0.permission == permission
        && $0.frameIsMain == frameIsMain
    }) {
      let existing = permissionDenials.remove(at: index)
      let (nextCount, countOverflow) = existing.requestCount.addingReportingOverflow(1)
      permissionDenials.append(
        WebKitPermissionDenial(
          origin: requestedOrigin,
          permission: permission,
          frameIsMain: frameIsMain,
          requestCount: countOverflow ? UInt64.max : nextCount,
          lastDeniedAtMonotonicNanoseconds: now))
      return
    }
    if permissionDenials.count == 32 {
      permissionDenials.removeFirst()
      permissionDenialsTruncated = true
    }
    permissionDenials.append(
      WebKitPermissionDenial(
        origin: requestedOrigin,
        permission: permission,
        frameIsMain: frameIsMain,
        requestCount: 1,
        lastDeniedAtMonotonicNanoseconds: now))
  }

  private static func agentSafeSecurityOrigin(_ origin: WKSecurityOrigin) -> String {
    let scheme = origin.protocol.lowercased()
    let host = origin.host.lowercased().trimmingCharacters(
      in: CharacterSet(charactersIn: "."))
    guard ["http", "https"].contains(scheme), !host.isEmpty else { return "unavailable" }
    return sanitizedOrigin(
      SecurityOrigin(
        scheme: scheme,
        host: host,
        port: origin.port > 0 ? origin.port : nil))
  }

  private func invalidateCurrentObservation() {
    latestObservationID = nil
    latestTargets.removeAll(keepingCapacity: true)
  }

  private func armNavigationActor(_ actor: WebKitNavigationActor) {
    let now = DispatchTime.now().uptimeNanoseconds
    let (expiry, overflow) = now.addingReportingOverflow(2_000_000_000)
    armedNavigationActor = (actor, overflow ? UInt64.max : expiry)
  }

  private func recordNavigationAudit(
    _ action: WKNavigationAction,
    allowed: Bool
  ) {
    guard action.targetFrame?.isMainFrame == true else { return }
    let now = DispatchTime.now().uptimeNanoseconds
    let actor: WebKitNavigationActor
    if controlState == .humanControlled || controlState == .humanStepCompleted {
      actor = .human
    } else if let armedNavigationActor, now <= armedNavigationActor.expiresAt {
      actor = armedNavigationActor.actor
    } else if action.sourceFrame.isMainFrame {
      actor = .webContent
    } else {
      actor = .unattributed
    }
    armedNavigationActor = nil
    let navigationType = Self.navigationTypeName(action.navigationType)
    navigationAuditEvents.append(
      WebKitNavigationAuditEvent(
        fromOrigin: webView.url.flatMap(Self.sanitizedOrigin(for:)),
        toOrigin: action.request.url.flatMap(Self.sanitizedOrigin(for:)),
        actor: actor,
        navigationType: navigationType,
        allowed: allowed,
        monotonicNanoseconds: now))
    if navigationAuditEvents.count > 128 {
      navigationAuditEvents.removeFirst(navigationAuditEvents.count - 128)
    }
  }

  private func prepareForAllowedMainFrameNavigation(_ action: WKNavigationAction) {
    guard action.targetFrame?.isMainFrame == true else { return }
    pendingMainFrameNavigationType = action.navigationType
  }

  private func navigationOrigin(for url: URL) -> SecurityOrigin? {
    guard
      let scheme = url.scheme?.lowercased(),
      ["http", "https"].contains(scheme),
      let host = url.host
    else { return nil }
    let effectivePort = url.port ?? (scheme == "https" ? 443 : 80)
    return SecurityOrigin(scheme: scheme, host: host, port: effectivePort)
  }

  private func restrictedAuthenticationOrigin() -> String? {
    if let url = webView.url ?? lastCommittedHTTPURL,
      let host = url.host?.lowercased().trimmingCharacters(
        in: CharacterSet(charactersIn: ".")),
      Self.restrictedAuthenticationHosts.contains(host)
    {
      return Self.sanitizedOrigin(for: url)
    }
    return restrictedAuthenticationFrameOrigin ?? restrictedWebAuthnOrigin
  }

  private func agentSafeURLString(_ url: URL?) -> String? {
    guard let url else { return nil }
    return Self.agentSafeURL(url)
  }

  /// WebKit's own classification of what asked for a navigation. Shared by the
  /// main-frame navigation audit and the suppressed-new-window record so the two never
  /// disagree about what to call a link activation.
  private static func navigationTypeName(_ type: WKNavigationType) -> String {
    switch type {
    case .linkActivated: "link_activated"
    case .formSubmitted: "form_submitted"
    case .backForward: "back_forward"
    case .reload: "reload"
    case .formResubmitted: "form_resubmitted"
    case .other: "other"
    @unknown default: "unknown"
    }
  }

  /// The address a refused new window was for, sanitised by the same rule the injected
  /// observation applies to an `href`: http(s) only, no embedded credentials, origin and
  /// path kept, the first sixteen query names kept with every value replaced, the fragment
  /// dropped, the whole string bounded. A `target="_blank"` invoice link routinely carries
  /// a session token in its query, and this string is exported with the action result.
  private static func sanitizedNewWindowDestination(_ url: URL?) -> String? {
    guard let url,
      let origin = sanitizedOrigin(for: url),
      (url.user(percentEncoded: false) ?? "").isEmpty,
      (url.password(percentEncoded: false) ?? "").isEmpty
    else { return nil }
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let names = (components?.percentEncodedQueryItems ?? []).prefix(16).map(\.name)
    let query =
      names.isEmpty
      ? ""
      : "?" + names.map { "\($0.prefix(64))=<redacted>" }.joined(separator: "&")
    let path = url.path(percentEncoded: true)
    return String("\(origin)\(path.isEmpty ? "/" : path)\(query)".prefix(512))
  }

  private static func sanitizedOrigin(for url: URL) -> String? {
    guard
      let scheme = url.scheme?.lowercased(),
      ["http", "https"].contains(scheme),
      let host = url.host?.lowercased().trimmingCharacters(
        in: CharacterSet(charactersIn: "."))
    else { return nil }
    let defaultPort = scheme == "https" ? 443 : 80
    let portSuffix = url.port.map { $0 == defaultPort ? "" : ":\($0)" } ?? ""
    return "\(scheme)://\(host)\(portSuffix)"
  }

  private static func sanitizedOrigin(_ origin: SecurityOrigin) -> String {
    let defaultPort = origin.scheme == "https" ? 443 : 80
    let portSuffix = origin.port.map { $0 == defaultPort ? "" : ":\($0)" } ?? ""
    return "\(origin.scheme)://\(origin.host)\(portSuffix)"
  }

  private static func sanitizedNavigationFailure(_ error: any Error) -> WebKitRuntimeError {
    let cocoaError = error as NSError
    return .navigationFailed("\(cocoaError.domain) code=\(cocoaError.code)")
  }

  private func refreshAuthenticationUIClassification() async {
    restrictedWebAuthnOrigin = nil
    if let url = webView.url ?? lastCommittedHTTPURL,
      url.scheme?.lowercased() == "https",
      url.host?.lowercased() == "dash.cloudflare.com",
      url.path == "/two-factor"
    {
      restrictedWebAuthnOrigin = Self.sanitizedOrigin(for: url)
      authenticationUIClassification = .fullBrowserRequired
      return
    }
    guard
      let json = try? await webView.callAsyncJavaScript(
        Self.authenticationUIStateSource,
        arguments: [:],
        in: nil,
        contentWorld: instrumentationWorld
      ) as? String,
      let data = json.data(using: .utf8),
      let state = try? JSONDecoder().decode(RawAuthenticationUIState.self, from: data)
    else {
      authenticationUIClassification =
        restrictedAuthenticationOrigin() == nil ? nil : .humanHandoffRequired
      return
    }
    if state.hasWebAuthnControl,
      !Self.webAuthnAnyRelyingPartyEntitlementConfigured(),
      let url = webView.url ?? lastCommittedHTTPURL
    {
      restrictedWebAuthnOrigin = Self.sanitizedOrigin(for: url)
      authenticationUIClassification = .fullBrowserRequired
      return
    }
    guard restrictedAuthenticationOrigin() != nil else {
      authenticationUIClassification = nil
      return
    }
    if Self.requiresFullBrowserBackend(
      topLevelURL: webView.url ?? lastCommittedHTTPURL,
      restrictedFrameOrigin: restrictedAuthenticationFrameOrigin
    ) {
      authenticationUIClassification = .fullBrowserRequired
    } else {
      authenticationUIClassification =
        state.readyState == "complete" && state.hasProgressIndicator
          && state.hasInvisibleAuthenticationControl && !state.hasVisibleAuthenticationControl
        ? .authUINotReady : .humanHandoffRequired
    }
  }

  private static let restrictedAuthenticationHosts: Set<String> = ["idmsa.apple.com"]
  /// Embeddings whose authentication frame cannot work in this engine at all. App
  /// Store Connect → idmsa used to be listed: measured on 2026-08-24 as a sign-in
  /// frame stuck on its spinner, it was the hidden-page defect (no animation
  /// frames while parked), not a WKWebView limit. With the page kept visible the
  /// same route renders the Apple Account form (2026-09-23), so it now takes the
  /// native human handoff like any other restricted origin. idmsa stays
  /// restricted: the agent still cannot read, capture or fill it.
  private static let fullBrowserAuthenticationParents: [String: Set<String>] = [:]

  private static func isRestrictedAuthenticationHost(_ rawHost: String?) -> Bool {
    guard
      let host = rawHost?.lowercased().trimmingCharacters(
        in: CharacterSet(charactersIn: "."))
    else { return false }
    return restrictedAuthenticationHosts.contains(host)
  }

  static func requiresFullBrowserBackend(
    topLevelURL: URL?, restrictedFrameOrigin: String?
  ) -> Bool {
    guard
      let parentHost = topLevelURL?.host?.lowercased().trimmingCharacters(
        in: CharacterSet(charactersIn: ".")),
      let restrictedFrameOrigin,
      let childHost = URL(string: restrictedFrameOrigin)?.host?.lowercased()
    else { return false }
    return fullBrowserAuthenticationParents[parentHost]?.contains(childHost) == true
  }

  private static func webAuthnAnyRelyingPartyEntitlementConfigured() -> Bool {
    guard
      let task = SecTaskCreateFromSelf(nil),
      let value = SecTaskCopyValueForEntitlement(
        task,
        "com.apple.developer.web-browser.public-key-credential" as CFString,
        nil
      )
    else { return false }
    return (value as? Bool) == true
  }

  private func rememberRecoverableURL(_ url: URL?) {
    guard
      let url,
      let scheme = url.scheme?.lowercased(),
      ["http", "https"].contains(scheme)
    else { return }
    lastCommittedHTTPURL = url
  }

  private func validate(quietWindow: Duration) throws {
    guard quietWindow > .zero else { throw WebKitRuntimeError.invalidQuietWindow }
  }

  private func awaitReadiness(
    timeout: Duration,
    quietWindow: Duration
  ) async throws -> PageReadiness {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    var lastMutationCount: UInt64?
    var quietSince = clock.now

    while clock.now < deadline {
      if processTerminated { return .processTerminated }
      if let navigationFailure { throw navigationFailure }

      if !webView.isLoading, let state = try? await instrumentationState() {
        if lastMutationCount != state.mutationCount {
          lastMutationCount = state.mutationCount
          quietSince = clock.now
        }
        if state.readyState == "complete", clock.now - quietSince >= quietWindow {
          return .ready
        }
      }
      try await Task.sleep(for: .milliseconds(20))
    }
    return processTerminated ? .processTerminated : .deadlineReached
  }

  private func instrumentationState(
    includeContentState: Bool = false
  ) async throws -> RawInstrumentationState {
    let source: String
    if includeContentState {
      source = """
        const state = globalThis.__webkituiState;
        const content = globalThis.__webkituiPageContentProbe?.(false);
        return JSON.stringify(state && content ? { ...state, ...content } : null);
        """
    } else {
      source = "return JSON.stringify(globalThis.__webkituiState ?? null);"
    }
    guard
      let json = try await webView.callAsyncJavaScript(
        source,
        arguments: [:],
        in: nil,
        contentWorld: instrumentationWorld
      ) as? String,
      json != "null",
      let data = json.data(using: .utf8),
      let state = try? JSONDecoder().decode(RawInstrumentationState.self, from: data)
    else {
      throw WebKitRuntimeError.noDocument
    }
    return state
  }

  private func locatorRecipe(
    for element: RawElement,
    peers: [RawElement],
    elementID: String,
    observationID: String,
    generation: UInt64
  ) throws -> LocatorRecipe {
    var clauses: [LocatorClause] = []
    if let role = element.role, !role.isEmpty {
      clauses.append(.init(fact: .role, expectedValue: role, strength: .required))
    }
    if let name = element.accessibleName, !name.isEmpty {
      clauses.append(
        .init(
          fact: .accessibleName,
          expectedValue: name,
          strength: .required,
          comparison: .whitespaceCollapsed
        )
      )
    }
    if let label = element.label, !label.isEmpty, element.accessibleName == nil {
      clauses.append(
        .init(
          fact: .label,
          expectedValue: label,
          strength: .required,
          comparison: .whitespaceCollapsed
        )
      )
    }
    let basePeerCount = peers.filter {
      $0.role == element.role
        && $0.accessibleName == element.accessibleName
        && $0.label == element.label
    }.count
    let uniquelyIdentifyingAnchor = element.contextAnchors.first { anchor in
      guard basePeerCount > 1 else { return false }
      guard !anchor.text.isEmpty else { return false }
      let matchingPeers = peers.filter { peer in
        peer.role == element.role
          && peer.accessibleName == element.accessibleName
          && peer.label == element.label
          && peer.contextAnchors.contains(where: {
            $0.kind == anchor.kind && $0.text == anchor.text
          })
      }
      return matchingPeers.count == 1
    }
    for anchor in element.contextAnchors where !anchor.text.isEmpty {
      clauses.append(
        .init(
          fact: .contextAnchor(anchor.kind),
          expectedValue: anchor.text,
          strength: element.accessibleName == nil && element.label == nil
            || (anchor.kind == uniquelyIdentifyingAnchor?.kind
              && anchor.text == uniquelyIdentifyingAnchor?.text)
            ? .required : .corroborating,
          comparison: .whitespaceCollapsed))
    }
    for name in ["href", "data-testid", "id", "name", "title"] {
      guard let value = element.stableAttributes[name], !value.isEmpty else { continue }
      let strongIdentity = ["href", "data-testid", "id"].contains(name)
      clauses.append(
        .init(
          fact: .stableAttribute(name),
          expectedValue: value,
          strength: strongIdentity ? .required : .corroborating,
          comparison: .exact))
    }
    if !element.domPath.isEmpty {
      clauses.append(
        .init(fact: .domPath, expectedValue: element.domPath, strength: .corroborating))
    }
    if clauses.isEmpty {
      clauses.append(
        .init(
          fact: .stableAttribute("tag"),
          expectedValue: element.tag,
          strength: .required
        )
      )
    }
    if !element.sensitive, element.visible,
      element.boundingBox.width > 0, element.boundingBox.height > 0,
      let text = element.text, !text.isEmpty
    {
      clauses.append(
        .init(
          fact: .value,
          expectedValue: text,
          strength: .corroborating,
          comparison: .whitespaceCollapsed
        )
      )
    }
    return try LocatorRecipe(
      elementID: elementID,
      observationID: observationID,
      observationGeneration: generation,
      clauses: clauses
    )
  }

  /// Only the tag and a keyed opaque identity leave the native frame recipe. The
  /// semantic clauses remain private so third-party text is never republished without
  /// provenance; the opaque identity allows exact postcondition attribution.
  private func frameLocatorRecipe(
    for element: RawElement,
    elementID: String,
    observationID: String,
    generation: UInt64,
    opaqueSemanticIdentity: String
  ) throws -> LocatorRecipe {
    try LocatorRecipe(
      elementID: elementID,
      observationID: observationID,
      observationGeneration: generation,
      clauses: [
        LocatorClause(
          fact: .stableAttribute("tag"),
          expectedValue: element.tag,
          strength: .required)
      ],
      opaqueSemanticIdentity: opaqueSemanticIdentity)
  }

  private func frameSemanticIdentity(
    capabilityID: String,
    privateIdentity: String
  ) -> String {
    let message = Data("\(capabilityID)\u{1F}\(privateIdentity)".utf8)
    let digest = HMAC<SHA256>.authenticationCode(for: message, using: frameSemanticKey)
      .map { String(format: "%02x", $0) }.joined()
    return "locator:\(digest)"
  }

  private static func frameActionModes(for element: RawElement) -> [WebKitFrameActionMode] {
    guard !element.sensitive, !element.disabled, element.visible,
      element.boundingBox.width > 0, element.boundingBox.height > 0
    else { return [] }
    var modes: [WebKitFrameActionMode] = [.hoverJavaScript, .pressKeyNativeAppKit]
    if element.tag == "select" { modes.append(.selectOptionJavaScript) }
    if element.tag == "input" || element.tag == "textarea" || element.role == "textbox" {
      modes.append(.fillNativeAppKit)
    }
    return modes
  }

  private func locatorCandidate(_ element: RawElement) -> LocatorCandidate {
    var facts: [LocatorFact: String] = [.stableAttribute("tag"): element.tag]
    if let role = element.role { facts[.role] = role }
    if let name = element.accessibleName { facts[.accessibleName] = name }
    if let label = element.label { facts[.label] = label }
    if let text = element.text { facts[.value] = text }
    for anchor in element.contextAnchors { facts[.contextAnchor(anchor.kind)] = anchor.text }
    for (name, value) in element.stableAttributes {
      facts[.stableAttribute(name)] = value
    }
    return LocatorCandidate(candidateID: element.physicalIdentity, facts: facts)
  }

  private func locatorQuality(
    recipe: LocatorRecipe,
    candidateCount: Int,
    candidateCountIsLowerBound: Bool
  ) -> LocatorQuality {
    let required = recipe.clauses.filter { $0.strength == .required }
    let facts = required.map { clause -> String in
      switch clause.fact {
      case .role: "role"
      case .accessibleName: "accessible_name"
      case .label: "label"
      case .contextAnchor(let kind): "context_anchor:\(kind)"
      case .stableAttribute(let name): "stable_attribute:\(name)"
      case .framePath: "frame_path"
      case .value: "value"
      case .domPath: "dom_path"
      }
    }.sorted()
    let hasStrongIdentity = required.contains { clause in
      switch clause.fact {
      case .accessibleName, .label, .contextAnchor: true
      case .stableAttribute(let name): name != "tag"
      default: false
      }
    }
    let status: LocatorQualityStatus
    let recommended: String?
    if !hasStrongIdentity || candidateCount == 0 {
      status = .insufficient
      recommended = "contextual_reobserve_or_handoff"
    } else if candidateCount == 1, candidateCountIsLowerBound {
      // Truncation is a caveat on the verdict, not a replacement for it. Forcing every
      // element to insufficient because the page was long left the one field meant to
      // say whether a target is unambiguous saying nothing on exactly the pages where
      // that mattered. The lower-bound flag carries the honesty.
      status = .unique
      recommended = "observation_is_partial_page_further_to_confirm_uniqueness"
    } else if candidateCount > 1 {
      status = .ambiguous
      recommended = "inspect_or_contextual_reobserve"
    } else {
      status = .unique
      recommended = nil
    }
    return LocatorQuality(
      status: status,
      candidateCount: candidateCount,
      candidateCountIsLowerBound: candidateCountIsLowerBound,
      facts: facts,
      recommendedAction: recommended)
  }

  private static func securityOrigin(from url: URL?) -> SecurityOrigin? {
    guard let url, let scheme = url.scheme, let host = url.host else { return nil }
    return SecurityOrigin(scheme: scheme, host: host, port: url.port)
  }

  private static let instrumentationSource = """
    (() => {
      const collapse = value => String(value ?? '').replace(/\\s+/g, ' ').trim();
      const composedParent = element =>
        element?.parentElement || element?.getRootNode?.()?.host || null;
      const pageContentProbe = (requireRenderedGeometry = true) => {
        const roots = [document];
        const elements = [];
        for (let index = 0; index < roots.length; index += 1) {
          const current = roots[index];
          const descendants = Array.from(current.querySelectorAll('*'));
          elements.push(...descendants);
          for (const candidate of descendants) {
            if (candidate.shadowRoot) roots.push(candidate.shadowRoot);
            if (candidate.localName === 'iframe' || candidate.localName === 'frame') {
              let inner = null;
              try { inner = candidate.contentDocument; } catch { inner = null; }
              if (inner) roots.push(inner);
            }
          }
        }
        const isRendered = element => {
          if (requireRenderedGeometry) {
            const box = element.getBoundingClientRect();
            if (!(box.width > 0 && box.height > 0) || element.getClientRects().length === 0) {
              return false;
            }
          }
          for (let cursor = element; cursor; cursor = composedParent(cursor)) {
            if (cursor.hidden || cursor.inert
                || collapse(cursor.getAttribute?.('aria-hidden')).toLowerCase() === 'true') {
              return false;
            }
            const view = cursor.ownerDocument?.defaultView;
            const style = view?.getComputedStyle(cursor);
            if (!style || style.display === 'none' || style.visibility === 'hidden'
                || style.visibility === 'collapse' || Number(style.opacity) === 0) {
              return false;
            }
          }
          return true;
        };
        const contentSelector = [
          'a[href]', 'button', 'input', 'select', 'textarea', 'summary',
          '[contenteditable="true"]', '[role="button"]', '[role="link"]', '[role="tab"]',
          '[role="checkbox"]', '[role="radio"]', '[role="switch"]', '[role="textbox"]',
          'img', 'picture', 'svg', 'canvas', 'video', 'audio[controls]',
          'iframe', 'frame', 'object', 'embed'
        ].join(',');
        const renderedObjects = elements.filter(
          element => element.matches(contentSelector) && isRendered(element));
        const hasVisibleText = roots.some(root => {
          const body = root.nodeType === Node.DOCUMENT_NODE ? root.body : root.host;
          return Boolean(body && collapse(body.innerText));
        });
        const hasGeneratedContent = elements.some(element => {
          if (!isRendered(element)) return false;
          const view = element.ownerDocument?.defaultView;
          return ['::before', '::after'].some(pseudo => {
            const content = view?.getComputedStyle(element, pseudo)?.content;
            return Boolean(content && content !== 'none' && content !== 'normal'
              && content !== '""' && content !== "''");
          });
        });
        const renderedContentCount = renderedObjects.length
          + (hasVisibleText ? 1 : 0) + (hasGeneratedContent ? 1 : 0);
        return {
          contentState: renderedContentCount === 0 ? 'empty_or_unusable' : 'usable',
          renderedContentCount
        };
      };
      Object.defineProperty(globalThis, '__webkituiPageContentProbe', {
        value: pageContentProbe,
        configurable: false,
        enumerable: false,
        writable: false
      });
      const state = {
        mutationCount: 0,
        readyState: document.readyState,
        nodeIDs: new WeakMap(),
        // The reverse direction, so an element observed a moment ago can be acted on by
        // the identity it was given rather than re-derived from a name it may not have.
        nodesByID: new Map(),
        nextNodeID: 1
      };
      Object.defineProperty(globalThis, '__webkituiState', {
        value: state,
        configurable: false,
        enumerable: false,
        writable: false
      });
      document.addEventListener('readystatechange', () => {
        state.readyState = document.readyState;
      });
      new MutationObserver((records) => {
        if (records.length > 0) state.mutationCount += records.length;
      }).observe(document, {
        subtree: true,
        childList: true,
        attributes: true,
        characterData: true
      });
    })();
    """

  private static let authenticationUIStateSource = """
    const collapse = value => String(value ?? '').replace(/\\s+/g, ' ').trim();
    const composedParent = element => element?.parentElement || element?.getRootNode?.()?.host || null;
    const deepQueryAll = (root, selector) => {
      const matches = [];
      const roots = [root];
      for (let index = 0; index < roots.length; index += 1) {
        const current = roots[index];
        matches.push(...current.querySelectorAll(selector));
        for (const host of current.querySelectorAll('*')) {
          if (host.shadowRoot) roots.push(host.shadowRoot);
          // A same-origin frame is part of the page a person sees. Skipping it made
          // every control inside one invisible, which an agent reads as absent.
          if (host.localName === 'iframe' || host.localName === 'frame') {
            let inner = null;
            try { inner = host.contentDocument; } catch { inner = null; }
            if (inner) roots.push(inner);
          }
        }
      }
      return matches;
    };
    let obscuredByAncestorOpacity = false;
    const isRendered = element => {
      const box = element.getBoundingClientRect();
      if (!(box.width > 0 && box.height > 0) || element.getClientRects().length === 0) {
        return false;
      }
      for (let cursor = element; cursor; cursor = composedParent(cursor)) {
        if (cursor.hidden || cursor.inert
            || collapse(cursor.getAttribute('aria-hidden')).toLowerCase() === 'true') {
          return false;
        }
        const style = getComputedStyle(cursor);
        if (style.display === 'none' || style.visibility === 'hidden'
            || style.visibility === 'collapse') {
          return false;
        }
        // A transparent ancestor is reported, not dropped. A single-page app whose
        // entrance animation never ran leaves its whole tree at opacity 0 while the
        // controls are laid out and interactive; dropping them makes the page look
        // empty. Every write still passes an exact human confirmation, and the
        // observation says the target is obscured.
        if (Number(style.opacity) === 0 && cursor !== element) {
          obscuredByAncestorOpacity = true;
        } else if (Number(style.opacity) === 0) {
          return false;
        }
      }
      return true;
    };
    const authenticationSelector = [
      'input[type="password"]',
      'input[autocomplete="username"]',
      'input[autocomplete="current-password"]',
      'input[autocomplete="new-password"]',
      'input[autocomplete="one-time-code"]'
    ].join(',');
    const authenticationControls = deepQueryAll(document, authenticationSelector);
    const webAuthnText = /(?:security key|passkey|yubikey|clé de sécurité|clé d’accès|cle de securite|cle d'acces)/i;
    const webAuthnControls = deepQueryAll(document,
      'a, button, h1, h2, h3, [role="button"], [role="heading"], input[autocomplete~="webauthn"]'
    ).filter(element => {
      if (element.matches('input[autocomplete~="webauthn"]')) return true;
      return webAuthnText.test(collapse(
        element.getAttribute('aria-label') || element.textContent || element.value));
    });
    const bodyHasWebAuthnText = webAuthnText.test(collapse(document.body?.innerText));
    const forms = deepQueryAll(document, 'form');
    const formHasOnlyInvisibleControls = forms.some(form => {
      const controls = deepQueryAll(form, 'input, select, textarea, button');
      return controls.length > 0 && !controls.some(isRendered);
    });
    return JSON.stringify({
      readyState: document.readyState,
      hasProgressIndicator: Boolean(
        document.querySelector('[role="progressbar"], progress, [aria-busy="true"]')),
      hasVisibleAuthenticationControl: authenticationControls.some(isRendered),
      hasInvisibleAuthenticationControl:
        authenticationControls.some(element => !isRendered(element)) || formHasOnlyInvisibleControls,
      hasWebAuthnControl: webAuthnControls.some(isRendered) || bodyHasWebAuthnText
    });
    """

  private static let observationSource = """
    const collapse = value => String(value ?? '').replace(/\\s+/g, ' ').trim();
    const composedParent = element => element?.parentElement || element?.getRootNode?.()?.host || null;
    const walkedFrameDocuments = new Set([document]);
    const deepQueryAll = (root, selector) => {
      const matches = [];
      const roots = [root];
      for (let index = 0; index < roots.length; index += 1) {
        const current = roots[index];
        matches.push(...current.querySelectorAll(selector));
        for (const host of current.querySelectorAll('*')) {
          if (host.shadowRoot) roots.push(host.shadowRoot);
          // A same-origin frame is part of the page a person sees. Skipping it made
          // every control inside one invisible, which an agent reads as absent.
          if (host.localName === 'iframe' || host.localName === 'frame') {
            let inner = null;
            try { inner = host.contentDocument; } catch { inner = null; }
            if (inner) {
              walkedFrameDocuments.add(inner);
              roots.push(inner);
            }
          }
        }
      }
      return matches;
    };
    const labelledNode = (element, id) => {
      const root = element?.getRootNode?.();
      return (typeof root?.getElementById === 'function' ? root.getElementById(id) : null)
        || document.getElementById(id);
    };
    let semanticTextTruncated = false;
    const bounded = value => {
      if (value === null || value === undefined) return null;
      const text = collapse(value);
      if (text.length <= maximumFieldCharacters) return text;
      semanticTextTruncated = true;
      return text.slice(0, maximumFieldCharacters);
    };
    const boundedFieldValue = value => {
      if (value === null || value === undefined) return null;
      const text = String(value).normalize('NFC').replace(/\\r\\n?/g, '\\n');
      if (text.length <= maximumFieldCharacters) return text;
      semanticTextTruncated = true;
      return text.slice(0, maximumFieldCharacters);
    };
    let obscuredByAncestorOpacity = false;
    const isRendered = element => {
      const box = element.getBoundingClientRect();
      if (!(box.width > 0 && box.height > 0) || element.getClientRects().length === 0) {
        return false;
      }
      for (let cursor = element; cursor; cursor = composedParent(cursor)) {
        if (cursor.hidden || cursor.inert
            || collapse(cursor.getAttribute('aria-hidden')).toLowerCase() === 'true') {
          return false;
        }
        const style = getComputedStyle(cursor);
        if (style.display === 'none' || style.visibility === 'hidden'
            || style.visibility === 'collapse') {
          return false;
        }
        // A transparent ancestor is reported, not dropped. A single-page app whose
        // entrance animation never ran leaves its whole tree at opacity 0 while the
        // controls are laid out and interactive; dropping them makes the page look
        // empty. Every write still passes an exact human confirmation, and the
        // observation says the target is obscured.
        if (Number(style.opacity) === 0 && cursor !== element) {
          obscuredByAncestorOpacity = true;
        } else if (Number(style.opacity) === 0) {
          return false;
        }
      }
      return true;
    };
    const sensitiveIdentifierTerm = /(token|state|csrf|nonce|session|assertion|secret|password|passcode|otp|one[-_ ]?time)/i;
    const sensitiveLabelTerm = /(?:^|[^a-z0-9])(token|state|csrf|nonce|session|assertion|secret|password|passcode|otp|one[-_ ]?time)(?:$|[^a-z0-9])/i;
    const sensitiveAutocomplete = new Set([
      'current-password', 'new-password', 'one-time-code', 'webauthn',
      'cc-name', 'cc-given-name', 'cc-additional-name', 'cc-family-name',
      'cc-number', 'cc-exp', 'cc-exp-month', 'cc-exp-year', 'cc-csc', 'cc-type'
    ]);
    // A Material-style control renders in two halves: the real input, given no size
    // or clipped away, and the painted box beside it marked aria-hidden. Neither half
    // survives a visibility filter on its own, so the form observes as a group with no
    // children and cannot be filled at all. Stand the pair up as one unit, addressed by
    // the visible half. The walk stops at the first ancestor owning a second control,
    // so a surface is never shared between two checkboxes.
    const hiddenControlSurface = element => {
      if (!(element instanceof HTMLInputElement)
          || !['checkbox', 'radio'].includes(element.type)) return null;
      const labels = element.labels ? Array.from(element.labels) : [];
      const label = labels.find(isRendered);
      if (label) return label;
      const labelledBy = collapse(element.getAttribute('aria-labelledby'));
      for (const id of labelledBy.split(/\\s+/).slice(0, 8).filter(Boolean)) {
        const node = labelledNode(element, id);
        if (node && isRendered(node)) return node;
      }
      // Climb to the outermost ancestor that still owns this one control and nothing
      // else interactive: that is the labelled row, which carries both the visible text
      // and the click handler. The tight wrapper around the input holds neither — it is
      // the painted box, and its text is empty.
      let widest = null;
      for (let cursor = composedParent(element); cursor; cursor = composedParent(cursor)) {
        if (cursor === document.body || cursor === document.documentElement) break;
        if (deepQueryAll(cursor, soleControl).length !== 1) break;
        if (isRendered(cursor)) widest = cursor;
      }
      return widest;
    };
    // A control can be rendered, sized and enabled and still be unable to receive its
    // own click: Material paints the box in a sibling that covers it. Hit testing is
    // the only way to tell, and without it every radio on the page costs a failed
    // round trip reported as indeterminate.
    // Hit testing belongs to the document the element lives in, at that document's own
    // coordinates. Asking the top-level document about a point measured inside a frame
    // answers about whatever sits at those numbers in the outer page.
    const hitAtCentreOfLocal = (node, box) => {
      const owner = node?.ownerDocument ?? document;
      const view = owner.defaultView ?? window;
      const x = Math.min(view.innerWidth - 1, Math.max(0, box.left + box.width / 2));
      const y = Math.min(view.innerHeight - 1, Math.max(0, box.top + box.height / 2));
      let hit = owner.elementFromPoint(x, y);
      while (hit?.shadowRoot && typeof hit.shadowRoot.elementFromPoint === 'function') {
        const nested = hit.shadowRoot.elementFromPoint(x, y);
        if (!nested || nested === hit) break;
        hit = nested;
      }
      return hit;
    };
    const hitReaches = (hit, ...targets) => {
      for (let cursor = hit; cursor; cursor = composedParent(cursor)) {
        if (targets.includes(cursor)) return true;
      }
      return false;
    };
    const receivesOwnEvents = element => {
      const box = element.getBoundingClientRect();
      if (!(box.width > 0 && box.height > 0)) return false;
      return hitReaches(hitAtCentreOfLocal(element, box), element);
    };
    // An ordinal path from the document root. Structure is never identity — a recycled
    // row keeps its position while meaning changes — so this only ever separates
    // candidates that already satisfy every identity clause. Without it, twenty-two
    // checkboxes that carry no name, no id and no distinguishing attribute have exactly
    // one address between them.
    const domPathOf = element => {
      const steps = [];
      for (let node = element; node && node.nodeType === 1; node = composedParent(node)) {
        const parent = composedParent(node);
        if (!parent) { steps.push(node.localName); break; }
        let index = 0;
        for (const sibling of parent.children) {
          if (sibling === node) break;
          if (sibling.localName === node.localName) index += 1;
        }
        steps.push(node.localName + '[' + index + ']');
        if (steps.length >= 32) break;
      }
      return steps.reverse().join('/');
    };
    // Offset of an element's own frame within the top-level viewport. Geometry inside a
    // frame is measured against that frame, so a click computed from it would land
    // wherever that offset happens to be — usually somewhere else entirely.
    const frameOffsetOf = element => {
      let offsetX = 0;
      let offsetY = 0;
      let view = element?.ownerDocument?.defaultView ?? null;
      let guard = 0;
      while (view && view !== window && guard < 16) {
        let host = null;
        try { host = view.frameElement; } catch { host = null; }
        if (!host) break;
        const box = host.getBoundingClientRect();
        offsetX += box.left;
        offsetY += box.top;
        view = host.ownerDocument?.defaultView ?? null;
        guard += 1;
      }
      return { x: offsetX, y: offsetY };
    };
    // A rect in top-level viewport coordinates, whatever frame the element lives in.
    const viewportRectOf = element => {
      const box = element.getBoundingClientRect();
      const offset = frameOffsetOf(element);
      if (offset.x === 0 && offset.y === 0) return box;
      return {
        x: box.x + offset.x, y: box.y + offset.y,
        left: box.left + offset.x, top: box.top + offset.y,
        right: box.right + offset.x, bottom: box.bottom + offset.y,
        width: box.width, height: box.height
      };
    };
    const frameCapabilityIDOf = element => {
      try {
        const value = element?.ownerDocument?.defaultView?.__webkituiFrameCapabilityID;
        return typeof value === 'string' && value ? value : null;
      } catch (_) {
        return null;
      }
    };
    const soleControl =
      'input, button, select, textarea, a[href], summary,'
      + ' [role="button"], [role="link"], [role="checkbox"], [role="radio"]';
    const controlSurfaceOf = element => {
      const fallback = hiddenControlSurface(element);
      if (fallback && (!isRendered(element) || !receivesOwnEvents(element))) return fallback;
      return isRendered(element) ? element : fallback;
    };
    // A control that borrows a surface for its geometry borrows its label with it.
    // Play's checkboxes carry no aria-label and no aria-labelledby — the visible text
    // is a sibling — so without this they are exposed and anonymous, their locator
    // holds role and nothing else, and every act on them fails as not unique.
    const borrowedLabel = element => {
      const surface = controlSurfaceOf(element);
      if (surface === element) return null;
      if (surface) {
        return collapse(surface.getAttribute?.('aria-label') || surface.innerText) || null;
      }
      // Nothing rendered to borrow from. A control that cannot be clicked must still be
      // nameable, or the agent cannot report what it is unable to reach.
      for (let cursor = composedParent(element); cursor; cursor = composedParent(cursor)) {
        if (cursor === document.body || cursor === document.documentElement) break;
        if (deepQueryAll(cursor, soleControl).length !== 1) break;
        const text = collapse(cursor.textContent);
        // Bounded inline: this helper is shared with the action script, which has no
        // bounded(). Reaching this branch there threw a ReferenceError that no fixture
        // exercised and the first real page found on the first click.
        if (text) return text.length > 512 ? text.slice(0, 512) : text;
      }
      return null;
    };
    // Why a control cannot be acted on, decided once and reported before the agent
    // spends a round trip finding out. locatorQuality answers "is this the only match";
    // it was read as "can I click this", and nothing answered that question.
    const actionabilityOf = (element, surface) => {
      const box = surface.getBoundingClientRect();
      if (!(box.width > 0 && box.height > 0)) return 'no_layout_box';
      const style = getComputedStyle(surface);
      if (style.visibility === 'hidden' || style.display === 'none') return 'not_visible';
      if (element.disabled
          || collapse(element.getAttribute?.('aria-disabled')).toLowerCase() === 'true') {
        return 'disabled';
      }
      const visible = viewportRectOf(surface);
      if (visible.bottom <= 0 || visible.right <= 0
          || visible.top >= innerHeight || visible.left >= innerWidth) {
        return 'off_viewport';
      }
      return hitReaches(hitAtCentreOfLocal(surface, box), element, surface)
        ? 'actionable' : 'covered';
    };
    const classTokens = element => collapse(element?.getAttribute?.('class'));
    const hasTabToken = element => /(^|[\\s_-])tabs?($|[\\s_-])/i.test(classTokens(element));
    const hasSelectedToken = element =>
      /(^|[\\s_-])(active|current|selected)($|[\\s_-])/i.test(classTokens(element));
    const isPointerControl = element => {
      if (!['a', 'div', 'li', 'span'].includes(element.localName) || !isRendered(element)) {
        return false;
      }
      if (getComputedStyle(element).cursor !== 'pointer') return false;
      const name = collapse(element.getAttribute('aria-label') || element.innerText);
      if (!name || name.length > maximumFieldCharacters) return false;
      return !Array.from(element.children).some(child =>
        isRendered(child) && getComputedStyle(child).cursor === 'pointer'
        && collapse(child.getAttribute('aria-label') || child.innerText) === name);
    };
    const hasImplicitTabSemantics = element => {
      if (element.hasAttribute('aria-selected')) return true;
      const parent = composedParent(element);
      return isPointerControl(element)
        && (collapse(parent?.getAttribute?.('role')).toLowerCase() === 'tablist'
          || hasTabToken(element) || hasTabToken(parent));
    };
    const looksOpaque = value => {
      const text = String(value ?? '');
      if (/^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$/.test(text)) return true;
      if (text.length < 32 || /\\s/.test(text)
          || !/^[A-Za-z0-9._~+/=-]+$/.test(text)) return false;
      return new Set(text).size >= 12;
    };
    const roleOf = element => {
      const explicit = collapse(element.getAttribute('role'));
      if (explicit) return explicit;
      if (hasImplicitTabSemantics(element)) return 'tab';
      if (element.localName === 'a' && element.hasAttribute('href')) return 'link';
      if (element.localName === 'button') return 'button';
      if (/^h[1-6]$/.test(element.localName)) return 'heading';
      if (element.localName === 'table') return 'table';
      if (element.localName === 'tr') return 'row';
      if (element.localName === 'th') return 'columnheader';
      if (element.localName === 'td') return 'cell';
      if (element.localName === 'select') return 'combobox';
      if (element.localName === 'textarea') return 'textbox';
      if (element.localName === 'summary') return 'button';
      if (element.localName === 'input') {
        const type = collapse(element.type).toLowerCase();
        if (type === 'search') return 'searchbox';
        if (['button', 'submit', 'reset', 'image'].includes(type)) return 'button';
        if (type === 'checkbox') return 'checkbox';
        if (type === 'radio') return 'radio';
        if (type === 'range') return 'slider';
        return 'textbox';
      }
      if (isPointerControl(element)) return 'button';
      return null;
    };
    const labelOf = element => {
      if (element.labels && element.labels.length) {
        return collapse(Array.from(element.labels).map(label => label.innerText).join(' ')) || null;
      }
      const labelledBy = collapse(element.getAttribute('aria-labelledby'));
      if (labelledBy) {
        return collapse(labelledBy.split(/\\s+/).map(id => labelledNode(element, id)?.innerText).join(' ')) || null;
      }
      return borrowedLabel(element);
    };
    const nameOf = element => collapse(element.getAttribute('aria-label')) || labelOf(element)
      || collapse(element.getAttribute('placeholder'))
      || collapse(element.getAttribute('alt')) || collapse(element.getAttribute('title'))
      || collapse(element.innerText) || null;
    const directLabelledText = element => {
      const labelledBy = collapse(element?.getAttribute?.('aria-labelledby'));
      if (!labelledBy) return null;
      return collapse(labelledBy.split(/\\s+/)
        .slice(0, 8)
        .map(id => labelledNode(element, id)?.innerText)
        .join(' ')) || null;
    };
    const safeContextValue = value => {
      const text = collapse(value);
      if (!text || looksOpaque(text) || sensitiveLabelTerm.test(text)) return null;
      return bounded(text);
    };
    const sameRowLabelOf = element => {
      const row = element.closest(
        'tr, [role="row"], li, [data-row], [class~="row"], [class*="form-row"], [class*="capability"]');
      if (!row) return null;
      const labelled = Array.from(row.querySelectorAll(
        'label, legend, h1, h2, h3, h4, h5, h6, [role="heading"], th, [role="rowheader"]'));
      const candidates = labelled.length > 0 ? labelled : Array.from(row.children);
      for (const candidate of candidates) {
        if (candidate === element || candidate.contains(element) || !isRendered(candidate)) continue;
        const text = safeContextValue(
          candidate.getAttribute?.('aria-label') || candidate.innerText || candidate.textContent);
        if (text && text !== safeContextValue(nameOf(element))) return text;
      }
      return null;
    };
    const contextAnchorsOf = element => {
      const anchors = [];
      const fieldset = element.closest('fieldset');
      const legend = fieldset?.querySelector(':scope > legend');
      const legendText = safeContextValue(legend?.innerText);
      if (legendText) anchors.push({ kind: 'fieldset_legend', text: legendText });

      const region = element.closest(
        'section, article, nav, main, form, [role="region"], [aria-label], [aria-labelledby]');
      const regionText = safeContextValue(
        region?.getAttribute('aria-label') || directLabelledText(region));
      if (regionText) anchors.push({ kind: 'labelled_region', text: regionText });

      const structural = element.closest('section, article, nav, main, form, fieldset')
        || document.body;
      const headings = Array.from(
        structural.querySelectorAll('h1, h2, h3, h4, h5, h6, [role="heading"]'));
      const heading = headings.filter(candidate =>
        candidate !== element
        && Boolean(candidate.compareDocumentPosition(element) & Node.DOCUMENT_POSITION_FOLLOWING)
      ).pop();
      const headingText = safeContextValue(heading?.innerText || heading?.getAttribute('aria-label'));
      if (headingText) anchors.push({ kind: 'nearest_heading', text: headingText });

      let sibling = element.previousElementSibling;
      while (sibling && !isRendered(sibling)) sibling = sibling.previousElementSibling;
      const siblingText = safeContextValue(sibling?.innerText || sibling?.textContent);
      if (siblingText) anchors.push({ kind: 'previous_sibling', text: siblingText });
      const rowLabel = sameRowLabelOf(element);
      if (rowLabel) anchors.unshift({ kind: 'same_row_label', text: rowLabel });
      return anchors.slice(0, 5);
    };
    const sanitizedHref = element => {
      if (!element.hasAttribute('href')) return null;
      try {
        const url = new URL(element.getAttribute('href'), document.baseURI);
        if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) return null;
        const keys = Array.from(url.searchParams.keys()).slice(0, 16);
        const query = keys.length
          ? `?${keys.map(key => `${encodeURIComponent(key)}=<redacted>`).join('&')}` : '';
        return bounded(`${url.origin}${url.pathname}${query}`);
      } catch { return null; }
    };
    // Query values are redacted here exactly as they are for href: this string is
    // exported with the observation, and a query is where a session token sits. An
    // address with no readable origin is reported as its scheme rather than dropped,
    // because staying silent would hide the case worth showing.
    const sanitizedDestination = value => {
      if (value === null || value === undefined || value === '') return null;
      try {
        const url = new URL(value, document.baseURI);
        if (!['http:', 'https:'].includes(url.protocol)) return url.protocol;
        const keys = Array.from(url.searchParams.keys()).slice(0, 16);
        const query = keys.length
          ? `?${keys.map(key => `${encodeURIComponent(key)}=<redacted>`).join('&')}` : '';
        return bounded(`${url.origin}${url.pathname}${query}`);
      } catch { return 'about:invalid'; }
    };
    const stableAttributesOf = (element, sensitive) => {
      if (sensitive) return {};
      const attributes = {};
      const href = sanitizedHref(element);
      if (href && !looksOpaque(href)) attributes.href = href;
      for (const name of ['id', 'name', 'title', 'data-testid']) {
        const value = collapse(element.getAttribute(name));
        if (!value || value.length > maximumFieldCharacters || looksOpaque(value)
            || sensitiveIdentifierTerm.test(value)) continue;
        attributes[name] = bounded(value);
      }
      return attributes;
    };
    const selector = [
      'a[href]', 'button', 'input', 'select', 'textarea', 'summary',
      'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
      'table', 'tr', 'th', 'td',
      '[role]', '[aria-selected]', '[aria-controls]', '[contenteditable="true"]', '[tabindex]'
    ].join(',');
    const allowedRoles = new Set(Array.isArray(roleFilters) ? roleFilters : []);
    const wantedName = collapse(nameFilter).toLowerCase();
    const semanticElements = deepQueryAll(document, selector);
    const pointerElements = deepQueryAll(document, 'a:not([href]), div, li, span')
      .filter(isPointerControl);
    // Diagnostic: how many otherwise-matching controls are dropped only because an
    // ancestor is aria-hidden or inert. A page that renders its controls and marks
    // them hidden leaves the tree empty for a reason worth reporting.
    let ariaHiddenDropCount = 0;
    // A control with no layout box anywhere up its row cannot be clicked, so reporting
    // it as actionable would be a lie. Reporting nothing at all is worse: the only exit
    // from a form can be one of these, and an agent that cannot see it concludes the
    // page is complete instead of handing over to a human.
    let unrenderedControlCount = 0;
    const unrenderedControlNames = [];
    const unrenderedControlName = element =>
      collapse(element.getAttribute('aria-label')) || labelOf(element);
    // Laid out but collapsed to nothing is not the same as deliberately hidden. The
    // only exit from a Play form is a control like this — the "none of these features"
    // option that keeps Next disabled — so it is reported with the truth about why it
    // cannot be clicked, rather than dropped as if it did not exist.
    const hiddenOnlyByGeometry = element => {
      const box = element.getBoundingClientRect();
      if (box.width > 0 && box.height > 0) return false;
      for (let cursor = element; cursor; cursor = composedParent(cursor)) {
        if (cursor.hidden || cursor.inert
            || collapse(cursor.getAttribute?.('aria-hidden')).toLowerCase() === 'true') {
          return false;
        }
        const style = getComputedStyle(cursor);
        if (style.display === 'none' || style.visibility === 'hidden'
            || style.visibility === 'collapse' || Number(style.opacity) === 0) {
          return false;
        }
      }
      return element.matches(soleControl);
    };
    const hiddenOnlyBySemantics = element => {
      const box = element.getBoundingClientRect();
      if (!(box.width > 0 && box.height > 0)) return false;
      for (let cursor = element; cursor; cursor = composedParent(cursor)) {
        if (cursor.inert
            || collapse(cursor.getAttribute && cursor.getAttribute('aria-hidden')).toLowerCase()
              === 'true') {
          return true;
        }
      }
      return false;
    };
    const matchingElements = Array.from(new Set([...semanticElements, ...pointerElements]))
      .filter(element => {
        if (!controlSurfaceOf(element)) {
          if (hiddenOnlyBySemantics(element)) {
            ariaHiddenDropCount += 1;
            return false;
          }
          if (!hiddenOnlyByGeometry(element)) return false;
          unrenderedControlCount += 1;
          const name = unrenderedControlName(element);
          if (name && unrenderedControlNames.length < 10
              && !unrenderedControlNames.includes(name)) {
            unrenderedControlNames.push(name);
          }
        }
        const role = collapse(roleOf(element)).toLowerCase();
        if (allowedRoles.size > 0 && !allowedRoles.has(role)) return false;
        const name = collapse(nameOf(element)).toLowerCase();
        return !wantedName || name.includes(wantedName);
      });
    const elements = matchingElements
      .slice(elementOffset, elementOffset + __MAXIMUM_ELEMENTS__)
      .map(element => {
        const surface = controlSurfaceOf(element) || element;
        const actionability = actionabilityOf(element, surface);
        // Reported where a person sees it, not where its own frame measures it.
        const reportedBox = viewportRectOf(surface);
        // A control nobody can see is reported so the agent knows it exists and what it
        // is called. What is written inside it is a different matter: reading the value
        // of a box the user cannot see is exactly the leak the visibility filter was
        // there to prevent.
        const withheldForInvisibility =
          actionability === 'no_layout_box' || actionability === 'not_visible';
        const box = surface.getBoundingClientRect();
        const rawValue = typeof element.value === 'string' ? element.value : null;
        const autocomplete = collapse(element.getAttribute('autocomplete')).toLowerCase();
        const autocompleteTokens = autocomplete.split(/\\s+/).filter(Boolean);
        const identifierMetadata = [
          element.getAttribute('name'), element.id, element.getAttribute('type'), autocomplete
        ].map(collapse).join(' ');
        const labelMetadata = [element.getAttribute('aria-label'), labelOf(element)]
          .map(collapse).join(' ');
        const bundleIdentifierMetadata = /(?:^|[^a-z0-9])bundle(?:[ _-]*(?:id|identifier))?(?:$|[^a-z0-9])/i
          .test(`${identifierMetadata} ${labelMetadata}`);
        const publicReverseDNSIdentifier = bundleIdentifierMetadata
          && /^[A-Za-z0-9][A-Za-z0-9-]*(?:\\.[A-Za-z0-9][A-Za-z0-9-]*){2,}$/.test(rawValue ?? '');
        const sensitive = (element instanceof HTMLInputElement && element.type === 'password')
          || autocompleteTokens.some(token => sensitiveAutocomplete.has(token))
          || sensitiveIdentifierTerm.test(identifierMetadata)
          || sensitiveLabelTerm.test(labelMetadata)
          || (!(element instanceof HTMLSelectElement) && looksOpaque(rawValue)
            && !publicReverseDNSIdentifier);
        // A disabled or read-only field shows its value to anyone looking at the page, so
        // it is reported like any other: an account page whose address fields were all
        // disabled read as empty, and the agent had to take a screenshot to learn a
        // postal address (FPS/TSP, 2026-09-23). Sensitivity and visibility still decide.
        let observableValue = null;
        if (!sensitive && element instanceof HTMLSelectElement) {
          observableValue = collapse(
            Array.from(element.selectedOptions).map(option => option.textContent).join(' ')) || null;
        } else if (!sensitive && element instanceof HTMLTextAreaElement) {
          observableValue = rawValue !== null && rawValue.length <= maximumFieldCharacters ? rawValue : null;
        } else if (!sensitive && element instanceof HTMLInputElement
                   && ['text', 'search', 'email', 'tel', 'url', 'number'].includes(element.type)) {
          observableValue = rawValue !== null && rawValue.length <= maximumFieldCharacters ? rawValue : null;
        } else if (!sensitive && element.isContentEditable) {
          // WebKit's own editing leaves a trailing newline in a contenteditable's text.
          // Reported verbatim it makes every exact-text postcondition fail on a write
          // that landed perfectly.
          const editableValue = (element.textContent ?? '').replace(/\\s+$/, '');
          observableValue = editableValue.length <= maximumFieldCharacters ? editableValue : null;
        }
        // What is chosen in a `<select>` is that control's value, in the one form a
        // `<select>` has one. So a sensitive select's selection is never read here, on
        // the same rule that withholds its `value` and its `text` and that makes `fill`
        // and `select_option` refuse it: a two-factor delivery method, a reason for
        // closing an account and a clinic's appointment type are each a secret spelled
        // out in a label.
        const selectedLabel = element instanceof HTMLSelectElement && !sensitive
          ? collapse(Array.from(element.selectedOptions).map(option => option.textContent).join(' '))
          : null;
        // `select_option` addresses an option by its exact visible label, so the labels
        // are published or the agent has to guess them from the surrounding page. Each
        // one goes through bounded(), the same rule every other published label goes
        // through, because the writer collapses the label it is given by that rule too:
        // publish them collapsed any other way and the two halves disagree in silence.
        // Nothing is published for a sensitive control, which is the rule `fill` and
        // `select_option` already apply, nor for one whose value is withheld because
        // nobody can see it.
        const optionElements =
          element instanceof HTMLSelectElement && !sensitive && !withheldForInvisibility
            ? Array.from(element.options) : null;
        const options = optionElements?.slice(0, maximumOptions).map(option => {
          const group = option.parentElement;
          return {
            label: bounded(option.textContent) ?? '',
            selected: Boolean(option.selected),
            // A disabled optgroup disables every option inside it, and the IDL getter
            // reflects only the option's own attribute. Read both, or a whole group
            // reads as choosable and every request for one is refused.
            disabled: Boolean(
              option.disabled || (group instanceof HTMLOptGroupElement && group.disabled))
          };
        }) ?? null;
        const isEditableField = element instanceof HTMLInputElement
          || element instanceof HTMLTextAreaElement || element.isContentEditable;
        const characterCount = !sensitive && isEditableField
          ? String(element.isContentEditable ? (element.textContent ?? '') : (rawValue ?? '')).length
          : null;
        const ariaInvalid = collapse(element.getAttribute('aria-invalid')).toLowerCase();
        const invalidByARIA = ['true', 'grammar', 'spelling'].includes(ariaInvalid);
        const invalidByConstraint = Boolean(element.willValidate && element.validity
          && !element.validity.valid);
        const validationReferenceIDs = [
          ...collapse(element.getAttribute('aria-errormessage')).split(/\\s+/),
          ...collapse(element.getAttribute('aria-describedby')).split(/\\s+/)
        ].filter(Boolean);
        const invalidByVisibleMessage = validationReferenceIDs.some(id => {
          const node = labelledNode(element, id);
          if (!node || !isRendered(node) || !collapse(node.textContent)) return false;
          if (collapse(element.getAttribute('aria-errormessage')).split(/\\s+/).includes(id)) {
            return true;
          }
          const metadata = `${node.id} ${node.className ?? ''} ${node.getAttribute('role') ?? ''}`;
          return /error|invalid|alert/i.test(metadata) || node.hasAttribute('aria-live');
        });
        let validationState = 'not_applicable';
        if (invalidByARIA || invalidByConstraint || invalidByVisibleMessage) {
          validationState = 'invalid';
        }
        else if (element.willValidate || ariaInvalid === 'false') validationState = 'valid';
        const checked = (element instanceof HTMLInputElement
          && ['checkbox', 'radio'].includes(element.type))
          ? Boolean(element.checked)
          : (element.hasAttribute('aria-checked')
            ? collapse(element.getAttribute('aria-checked')).toLowerCase() === 'true' : null);
        const selected = element instanceof HTMLOptionElement
          ? Boolean(element.selected)
          : (element.hasAttribute('aria-selected')
            ? collapse(element.getAttribute('aria-selected')).toLowerCase() === 'true'
            : (roleOf(element) === 'tab'
              ? (element.hasAttribute('aria-current') || hasSelectedToken(element)) : null));
        const stateAttributes = {};
        for (const name of [
          'aria-checked', 'aria-selected', 'aria-current', 'aria-disabled', 'aria-expanded',
          'data-state', 'open'
        ]) {
          if (element.hasAttribute(name)) stateAttributes[name] = element.getAttribute(name) ?? '';
        }
        let physicalIdentity = globalThis.__webkituiState.nodeIDs.get(element);
        if (!physicalIdentity) {
          physicalIdentity = `n${globalThis.__webkituiState.nextNodeID++}`;
          globalThis.__webkituiState.nodeIDs.set(element, physicalIdentity);
          globalThis.__webkituiState.nodesByID.set(physicalIdentity, new WeakRef(element));
        }
        const submitsForm = Boolean(
          (element instanceof HTMLButtonElement
            && (element.type || 'submit').toLowerCase() === 'submit' && element.form)
          || (element instanceof HTMLInputElement
            && ['submit', 'image'].includes(element.type) && element.form)
        );
        return {
          physicalIdentity,
          frameCapabilityID: frameCapabilityIDOf(element),
          tag: element.localName,
          role: roleOf(element),
          accessibleName: bounded(nameOf(element)),
          submissionDestination: sanitizedDestination((() => {
            // formaction wins over the owning form's action, which is the precedence
            // HTML gives the two. The formAction IDL getter falls back to the document
            // URL rather than to the form, so the form's own action is read directly
            // instead: a form posting off-site under a button with no formaction is
            // exactly the case that must not be reported as this page's origin.
            if (submitsForm) {
              if (element.hasAttribute('formaction') && element.formAction) {
                return element.formAction;
              }
              return element.form.action || null;
            }
            if (element.tagName === 'FORM' && typeof element.action === 'string') {
              return element.action;
            }
            if (element.tagName === 'A' && element.hasAttribute('href')) {
              return element.href;
            }
            return null;
          })()),
          label: bounded(labelOf(element)),
          text: sensitive || withheldForInvisibility
            ? null : bounded(selectedLabel || collapse(element.innerText) || null),
          value: withheldForInvisibility ? null : boundedFieldValue(observableValue),
          validationState,
          characterCount: withheldForInvisibility ? null : characterCount,
          sensitive,
          submitsForm,
          disabled: Boolean(element.disabled || element.getAttribute('aria-disabled') === 'true'),
          checked,
          selected,
          // Both conditions, stated here rather than left to the definition above: this
          // key was gated on invisibility alone, and published the chosen label of every
          // sensitive select on every page until it was found.
          selectedOption: sensitive || withheldForInvisibility
            ? null : bounded(selectedLabel || null),
          // Three keys a page of buttons never pays for: absent, not empty, wherever
          // there is no list to publish.
          options,
          optionCount: optionElements ? optionElements.length : null,
          optionsTruncated: options ? optionElements.length > options.length : null,
          stateAttributes: sensitive ? {} : Object.fromEntries(
            Object.entries(stateAttributes).map(([key, value]) => [key, bounded(value) ?? ''])),
          contextAnchors: sensitive ? [] : contextAnchorsOf(element),
          domPath: domPathOf(element),
          stableAttributes: stableAttributesOf(element, sensitive),
          visible: actionability !== 'no_layout_box' && actionability !== 'not_visible',
          actionability,
          boundingBox: {
            x: reportedBox.x, y: reportedBox.y,
            width: reportedBox.width, height: reportedBox.height
          }
        };
      });
    // Counted through the whole tree, frames nested inside readable frames included:
    // an unreadable region one level down is exactly as invisible as one at the top.
    let crossOriginFrameCount = 0;
    for (const frame of deepQueryAll(document, 'iframe, frame')) {
      try { if (!frame.contentDocument) crossOriginFrameCount += 1; }
      catch { crossOriginFrameCount += 1; }
    }
    const visibleLoadingIndicators = deepQueryAll(
      document, '[aria-busy="true"], [role="progressbar"], progress'
    ).some(isRendered);
    const loadingShellText = collapse(document.body?.innerText);
    // Counted from the raw DOM, not the semantic matcher: a page whose matcher finds
    // nothing may still be fully rendered, and must not be mistaken for a shell that
    // has not painted its controls yet.
    const rawControls = deepQueryAll(
      document, 'button, a[href], input, select, textarea, [role="button"]');
    const renderedInteractiveCount = rawControls.filter(isRendered).length;
    // Separates "not in this tree" from "in the tree but not laid out": the first
    // means the script is walking the wrong document, the second a layout problem.
    const rawControlCount = rawControls.length;
    const documentElementCount = document.querySelectorAll('*').length;
    // One control described in full: enough to tell a layout problem from a filter
    // problem without another round trip.
    const probe = rawControls[0];
    let firstControlProbe = 'none';
    if (probe) {
      const box = probe.getBoundingClientRect();
      const style = getComputedStyle(probe);
      firstControlProbe = [
        probe.tagName.toLowerCase(),
        'w=' + Math.round(box.width), 'h=' + Math.round(box.height),
        'rects=' + probe.getClientRects().length,
        'display=' + style.display, 'visibility=' + style.visibility,
        'opacity=' + style.opacity,
        'offsetParent=' + (probe.offsetParent ? 'yes' : 'no'),
        'connected=' + probe.isConnected,
        'docW=' + document.documentElement.clientWidth,
        'docH=' + document.documentElement.clientHeight,
        'innerW=' + window.innerWidth, 'innerH=' + window.innerHeight
      ].join(' ');
      // Which ancestor disqualifies it, and on which property.
      let reason = 'accepted';
      for (let cursor = probe; cursor; cursor = composedParent(cursor)) {
        const tag = cursor.tagName ? cursor.tagName.toLowerCase() : String(cursor.nodeName);
        if (cursor.hidden) { reason = 'hidden@' + tag; break; }
        if (cursor.inert) { reason = 'inert@' + tag; break; }
        if (cursor.getAttribute
            && collapse(cursor.getAttribute('aria-hidden')).toLowerCase() === 'true') {
          reason = 'aria-hidden@' + tag; break;
        }
        const cs = getComputedStyle(cursor);
        if (!cs) { reason = 'no-style@' + tag; break; }
        if (cs.display === 'none') { reason = 'display-none@' + tag; break; }
        if (cs.visibility === 'hidden' || cs.visibility === 'collapse') {
          reason = 'visibility-' + cs.visibility + '@' + tag; break;
        }
        if (Number(cs.opacity) === 0) { reason = 'opacity0@' + tag; break; }
      }
      firstControlProbe += ' | ' + reason;
    }
    const bodyTextLength = (document.body?.innerText || '').length;
    const pageContentProbe = globalThis.__webkituiPageContentProbe?.() ?? {
      contentState: bodyTextLength > 0 || renderedInteractiveCount > 0
        ? 'usable' : 'empty_or_unusable',
      renderedContentCount: (bodyTextLength > 0 ? 1 : 0) + renderedInteractiveCount
    };
    // The entire visible text of the document is one short loading phrase. A shell that
    // has already painted a menu button still says only this, and requiring zero
    // controls handed such a page over as complete — the agent then read an empty form.
    // The bound is deliberately tight: Play's rendered app list keeps the same phrase at
    // the top of its text and must stay ready, so anything that says more than the
    // phrase alone is a page, not a shell. Being wrong the other way costs a stall on
    // every observation.
    const bodyIsOnlyTheLoadingPhrase =
      /^(loading|chargement)\\b/i.test(loadingShellText) && loadingShellText.length <= 32;
    const transientLoading = bodyIsOnlyTheLoadingPhrase || (
      matchingElements.length === 0 && (
        visibleLoadingIndicators
        // Anchored on the start, not the whole body: a loading shell usually renders
        // its navigation labels too, so requiring the entire text to be the phrase
        // never matched a real single-page app. Zero matching controls is what makes
        // this safe — a hydrated page with controls is never treated as loading.
        || (renderedInteractiveCount === 0
          && /^(loading|chargement)\\b/i.test(loadingShellText))
      )
    );
    return JSON.stringify({
      url: location.href,
      title: document.title,
      readyState: document.readyState,
      mutationCount: globalThis.__webkituiState?.mutationCount ?? 0,
      walkedFrameCapabilityIDs: Array.from(walkedFrameDocuments).map(frameDocument => {
        try {
          const value = frameDocument.defaultView?.__webkituiFrameCapabilityID;
          return typeof value === 'string' && value ? value : null;
        } catch (_) {
          return null;
        }
      }).filter(Boolean),
      crossOriginFrameCount,
      totalElementCount: matchingElements.length,
      unfilteredCandidateCount: Array.from(new Set([...semanticElements, ...pointerElements])).length,
      renderedInteractiveCount,
      renderedContentCount: pageContentProbe.renderedContentCount,
      documentLanguage: bounded(
        collapse(document.documentElement.getAttribute('lang'))
          || collapse(document.body?.getAttribute('lang'))
          || null),
      ariaHiddenDropCount,
      unrenderedControlCount,
      unrenderedControlNames,
      rawControlCount,
      obscuredByAncestorOpacity,
      documentElementCount,
      bodyTextLength,
      firstControlProbe,
      transientLoading,
      semanticTextTruncated,
      elements
    });
    """

  private static let actionHelpers = """
    const collapse = value => String(value ?? '').replace(/\\s+/g, ' ').trim();
    const composedParent = element => element?.parentElement || element?.getRootNode?.()?.host || null;
    const deepQueryAll = (root, selector) => {
      const matches = [];
      const roots = [root];
      for (let index = 0; index < roots.length; index += 1) {
        const current = roots[index];
        matches.push(...current.querySelectorAll(selector));
        for (const host of current.querySelectorAll('*')) {
          if (host.shadowRoot) roots.push(host.shadowRoot);
          // A same-origin frame is part of the page a person sees. Skipping it made
          // every control inside one invisible, which an agent reads as absent.
          if (host.localName === 'iframe' || host.localName === 'frame') {
            let inner = null;
            try { inner = host.contentDocument; } catch { inner = null; }
            if (inner) roots.push(inner);
          }
        }
      }
      return matches;
    };
    const labelledNode = (element, id) => {
      const root = element?.getRootNode?.();
      return (typeof root?.getElementById === 'function' ? root.getElementById(id) : null)
        || document.getElementById(id);
    };
    const labelOf = element => {
      if (element.labels && element.labels.length) {
        return collapse(Array.from(element.labels).map(label => label.innerText).join(' ')) || null;
      }
      const labelledBy = collapse(element.getAttribute('aria-labelledby'));
      if (labelledBy) {
        return collapse(labelledBy.split(/\\s+/).map(id => labelledNode(element, id)?.innerText).join(' ')) || null;
      }
      return borrowedLabel(element);
    };
    const classTokens = element => collapse(element?.getAttribute?.('class'));
    const hasTabToken = element => /(^|[\\s_-])tabs?($|[\\s_-])/i.test(classTokens(element));
    const isPointerControl = element => {
      if (!['a', 'div', 'li', 'span'].includes(element.localName)) return false;
      if (getComputedStyle(element).cursor !== 'pointer') return false;
      const name = collapse(element.getAttribute('aria-label') || element.innerText);
      if (!name) return false;
      return !Array.from(element.children).some(child =>
        isRendered(child) && getComputedStyle(child).cursor === 'pointer'
        && collapse(child.getAttribute('aria-label') || child.innerText) === name);
    };
    const hasImplicitTabSemantics = element => {
      if (element.hasAttribute('aria-selected')) return true;
      const parent = composedParent(element);
      return isPointerControl(element)
        && (collapse(parent?.getAttribute?.('role')).toLowerCase() === 'tablist'
          || hasTabToken(element) || hasTabToken(parent));
    };
    const roleOf = element => {
      const explicit = collapse(element.getAttribute('role'));
      if (explicit) return explicit;
      if (hasImplicitTabSemantics(element)) return 'tab';
      if (element.localName === 'a' && element.hasAttribute('href')) return 'link';
      if (element.localName === 'button') return 'button';
      if (/^h[1-6]$/.test(element.localName)) return 'heading';
      if (element.localName === 'table') return 'table';
      if (element.localName === 'tr') return 'row';
      if (element.localName === 'th') return 'columnheader';
      if (element.localName === 'td') return 'cell';
      if (element.localName === 'select') return 'combobox';
      if (element.localName === 'textarea') return 'textbox';
      if (element.localName === 'summary') return 'button';
      if (element.localName === 'input') {
        const type = collapse(element.type).toLowerCase();
        if (type === 'search') return 'searchbox';
        if (['button', 'submit', 'reset', 'image'].includes(type)) return 'button';
        if (type === 'checkbox') return 'checkbox';
        if (type === 'radio') return 'radio';
        if (type === 'range') return 'slider';
        return 'textbox';
      }
      if (isPointerControl(element)) return 'button';
      return null;
    };
    const nameOf = element => collapse(element.getAttribute('aria-label')) || labelOf(element)
      || collapse(element.getAttribute('placeholder'))
      || collapse(element.getAttribute('alt')) || collapse(element.getAttribute('title'))
      || collapse(element.innerText) || null;
    let obscuredByAncestorOpacity = false;
    const isRendered = element => {
      const box = element.getBoundingClientRect();
      if (!(box.width > 0 && box.height > 0) || element.getClientRects().length === 0) return false;
      for (let cursor = element; cursor; cursor = composedParent(cursor)) {
        const style = getComputedStyle(cursor);
        if (cursor.hidden || cursor.inert || style.display === 'none'
            || style.visibility === 'hidden' || Number(style.opacity) === 0) return false;
      }
      return true;
    };
    // Context anchors are re-derived here and compared with the text the observation
    // recorded, so the neighbour must be chosen by the observation's rule, not the
    // action rule above: aria-hidden is skipped, and only the element's own opacity
    // hides it. The two rules differed and a Material tab whose previous sibling is an
    // aria-hidden paginator was observed as unique, then refused as targetNotFound on
    // every retry with no mutation (Play Console, 2026-09-23).
    const isAnchorRendered = element => {
      const box = element.getBoundingClientRect();
      if (!(box.width > 0 && box.height > 0) || element.getClientRects().length === 0) return false;
      for (let cursor = element; cursor; cursor = composedParent(cursor)) {
        if (cursor.hidden || cursor.inert
            || collapse(cursor.getAttribute?.('aria-hidden')).toLowerCase() === 'true') {
          return false;
        }
        const style = getComputedStyle(cursor);
        if (style.display === 'none' || style.visibility === 'hidden'
            || style.visibility === 'collapse') return false;
        if (Number(style.opacity) === 0 && cursor === element) return false;
      }
      return true;
    };
    // A Material-style control renders in two halves: the real input, given no size
    // or clipped away, and the painted box beside it marked aria-hidden. Neither half
    // survives a visibility filter on its own, so the form observes as a group with no
    // children and cannot be filled at all. Stand the pair up as one unit, addressed by
    // the visible half. The walk stops at the first ancestor owning a second control,
    // so a surface is never shared between two checkboxes.
    const hiddenControlSurface = element => {
      if (!(element instanceof HTMLInputElement)
          || !['checkbox', 'radio'].includes(element.type)) return null;
      const labels = element.labels ? Array.from(element.labels) : [];
      const label = labels.find(isRendered);
      if (label) return label;
      const labelledBy = collapse(element.getAttribute('aria-labelledby'));
      for (const id of labelledBy.split(/\\s+/).slice(0, 8).filter(Boolean)) {
        const node = labelledNode(element, id);
        if (node && isRendered(node)) return node;
      }
      // Climb to the outermost ancestor that still owns this one control and nothing
      // else interactive: that is the labelled row, which carries both the visible text
      // and the click handler. The tight wrapper around the input holds neither — it is
      // the painted box, and its text is empty.
      let widest = null;
      for (let cursor = composedParent(element); cursor; cursor = composedParent(cursor)) {
        if (cursor === document.body || cursor === document.documentElement) break;
        if (deepQueryAll(cursor, soleControl).length !== 1) break;
        if (isRendered(cursor)) widest = cursor;
      }
      return widest;
    };
    // A control can be rendered, sized and enabled and still be unable to receive its
    // own click: Material paints the box in a sibling that covers it. Hit testing is
    // the only way to tell, and without it every radio on the page costs a failed
    // round trip reported as indeterminate.
    // Hit testing belongs to the document the element lives in, at that document's own
    // coordinates. Asking the top-level document about a point measured inside a frame
    // answers about whatever sits at those numbers in the outer page.
    const hitAtCentreOfLocal = (node, box) => {
      const owner = node?.ownerDocument ?? document;
      const view = owner.defaultView ?? window;
      const x = Math.min(view.innerWidth - 1, Math.max(0, box.left + box.width / 2));
      const y = Math.min(view.innerHeight - 1, Math.max(0, box.top + box.height / 2));
      let hit = owner.elementFromPoint(x, y);
      while (hit?.shadowRoot && typeof hit.shadowRoot.elementFromPoint === 'function') {
        const nested = hit.shadowRoot.elementFromPoint(x, y);
        if (!nested || nested === hit) break;
        hit = nested;
      }
      return hit;
    };
    const hitReaches = (hit, ...targets) => {
      for (let cursor = hit; cursor; cursor = composedParent(cursor)) {
        if (targets.includes(cursor)) return true;
      }
      return false;
    };
    const receivesOwnEvents = element => {
      const box = element.getBoundingClientRect();
      if (!(box.width > 0 && box.height > 0)) return false;
      return hitReaches(hitAtCentreOfLocal(element, box), element);
    };
    // An ordinal path from the document root. Structure is never identity — a recycled
    // row keeps its position while meaning changes — so this only ever separates
    // candidates that already satisfy every identity clause. Without it, twenty-two
    // checkboxes that carry no name, no id and no distinguishing attribute have exactly
    // one address between them.
    const domPathOf = element => {
      const steps = [];
      for (let node = element; node && node.nodeType === 1; node = composedParent(node)) {
        const parent = composedParent(node);
        if (!parent) { steps.push(node.localName); break; }
        let index = 0;
        for (const sibling of parent.children) {
          if (sibling === node) break;
          if (sibling.localName === node.localName) index += 1;
        }
        steps.push(node.localName + '[' + index + ']');
        if (steps.length >= 32) break;
      }
      return steps.reverse().join('/');
    };
    // Offset of an element's own frame within the top-level viewport. Geometry inside a
    // frame is measured against that frame, so a click computed from it would land
    // wherever that offset happens to be — usually somewhere else entirely.
    const frameOffsetOf = element => {
      let offsetX = 0;
      let offsetY = 0;
      let view = element?.ownerDocument?.defaultView ?? null;
      let guard = 0;
      while (view && view !== window && guard < 16) {
        let host = null;
        try { host = view.frameElement; } catch { host = null; }
        if (!host) break;
        const box = host.getBoundingClientRect();
        offsetX += box.left;
        offsetY += box.top;
        view = host.ownerDocument?.defaultView ?? null;
        guard += 1;
      }
      return { x: offsetX, y: offsetY };
    };
    // A rect in top-level viewport coordinates, whatever frame the element lives in.
    const viewportRectOf = element => {
      const box = element.getBoundingClientRect();
      const offset = frameOffsetOf(element);
      if (offset.x === 0 && offset.y === 0) return box;
      return {
        x: box.x + offset.x, y: box.y + offset.y,
        left: box.left + offset.x, top: box.top + offset.y,
        right: box.right + offset.x, bottom: box.bottom + offset.y,
        width: box.width, height: box.height
      };
    };
    const soleControl =
      'input, button, select, textarea, a[href], summary,'
      + ' [role="button"], [role="link"], [role="checkbox"], [role="radio"]';
    const controlSurfaceOf = element => {
      const fallback = hiddenControlSurface(element);
      if (fallback && (!isRendered(element) || !receivesOwnEvents(element))) return fallback;
      return isRendered(element) ? element : fallback;
    };
    // A control that borrows a surface for its geometry borrows its label with it.
    // Play's checkboxes carry no aria-label and no aria-labelledby — the visible text
    // is a sibling — so without this they are exposed and anonymous, their locator
    // holds role and nothing else, and every act on them fails as not unique.
    const borrowedLabel = element => {
      const surface = controlSurfaceOf(element);
      if (surface === element) return null;
      if (surface) {
        return collapse(surface.getAttribute?.('aria-label') || surface.innerText) || null;
      }
      // Nothing rendered to borrow from. A control that cannot be clicked must still be
      // nameable, or the agent cannot report what it is unable to reach.
      for (let cursor = composedParent(element); cursor; cursor = composedParent(cursor)) {
        if (cursor === document.body || cursor === document.documentElement) break;
        if (deepQueryAll(cursor, soleControl).length !== 1) break;
        const text = collapse(cursor.textContent);
        // Bounded inline: this helper is shared with the action script, which has no
        // bounded(). Reaching this branch there threw a ReferenceError that no fixture
        // exercised and the first real page found on the first click.
        if (text) return text.length > 512 ? text.slice(0, 512) : text;
      }
      return null;
    };
    // Why a control cannot be acted on, decided once and reported before the agent
    // spends a round trip finding out. locatorQuality answers "is this the only match";
    // it was read as "can I click this", and nothing answered that question.
    const actionabilityOf = (element, surface) => {
      const box = surface.getBoundingClientRect();
      if (!(box.width > 0 && box.height > 0)) return 'no_layout_box';
      const style = getComputedStyle(surface);
      if (style.visibility === 'hidden' || style.display === 'none') return 'not_visible';
      if (element.disabled
          || collapse(element.getAttribute?.('aria-disabled')).toLowerCase() === 'true') {
        return 'disabled';
      }
      const visible = viewportRectOf(surface);
      if (visible.bottom <= 0 || visible.right <= 0
          || visible.top >= innerHeight || visible.left >= innerWidth) {
        return 'off_viewport';
      }
      return hitReaches(hitAtCentreOfLocal(surface, box), element, surface)
        ? 'actionable' : 'covered';
    };
    const surfaceOf = element => controlSurfaceOf(element) || element;
    const directLabelledText = element => {
      const labelledBy = collapse(element?.getAttribute?.('aria-labelledby'));
      if (!labelledBy) return null;
      return collapse(labelledBy.split(/\\s+/)
        .slice(0, 8)
        .map(id => labelledNode(element, id)?.innerText)
        .join(' ')) || null;
    };
    const sameRowLabelOf = element => {
      const row = element.closest(
        'tr, [role="row"], li, [data-row], [class~="row"], [class*="form-row"], [class*="capability"]');
      if (!row) return null;
      const labelled = Array.from(row.querySelectorAll(
        'label, legend, h1, h2, h3, h4, h5, h6, [role="heading"], th, [role="rowheader"]'));
      const candidates = labelled.length > 0 ? labelled : Array.from(row.children);
      for (const candidate of candidates) {
        if (candidate === element || candidate.contains(element) || !isAnchorRendered(candidate)) {
          continue;
        }
        const text = collapse(
          candidate.getAttribute?.('aria-label') || candidate.innerText || candidate.textContent);
        if (text && text !== collapse(nameOf(element))) return text;
      }
      return null;
    };
    const contextAnchorOf = (element, kind) => {
      if (kind === 'same_row_label') return sameRowLabelOf(element);
      if (kind === 'fieldset_legend') {
        return collapse(element.closest('fieldset')?.querySelector(':scope > legend')?.innerText)
          || null;
      }
      if (kind === 'labelled_region') {
        const region = element.closest(
          'section, article, nav, main, form, [role="region"], [aria-label], [aria-labelledby]');
        return collapse(region?.getAttribute('aria-label') || directLabelledText(region)) || null;
      }
      if (kind === 'nearest_heading') {
        const structural = element.closest('section, article, nav, main, form, fieldset')
          || document.body;
        const headings = Array.from(
          structural.querySelectorAll('h1, h2, h3, h4, h5, h6, [role="heading"]'));
        const heading = headings.filter(candidate =>
          candidate !== element
          && Boolean(candidate.compareDocumentPosition(element) & Node.DOCUMENT_POSITION_FOLLOWING)
        ).pop();
        return collapse(heading?.innerText || heading?.getAttribute('aria-label')) || null;
      }
      if (kind === 'previous_sibling') {
        let sibling = element.previousElementSibling;
        while (sibling && !isAnchorRendered(sibling)) sibling = sibling.previousElementSibling;
        return collapse(sibling?.innerText || sibling?.textContent) || null;
      }
      return null;
    };
    const sanitizedHref = element => {
      if (!element.hasAttribute('href')) return null;
      try {
        const url = new URL(element.getAttribute('href'), document.baseURI);
        if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) return null;
        const keys = Array.from(url.searchParams.keys()).slice(0, 16);
        const query = keys.length
          ? `?${keys.map(key => `${encodeURIComponent(key)}=<redacted>`).join('&')}` : '';
        return `${url.origin}${url.pathname}${query}`;
      } catch { return null; }
    };
    // Kept aligned with the observation mapper. This copy runs at confirmation time,
    // after the target has been resolved again, so a page cannot make the operator
    // approve the destination from an older observation by mutating `formaction`.
    const sanitizedSubmissionDestination = value => {
      if (value === null || value === undefined || value === '') return null;
      try {
        const url = new URL(value, document.baseURI);
        if (!['http:', 'https:'].includes(url.protocol)) return url.protocol;
        const keys = Array.from(url.searchParams.keys()).slice(0, 16);
        const query = keys.length
          ? `?${keys.map(key => `${encodeURIComponent(key)}=<redacted>`).join('&')}` : '';
        const result = `${url.origin}${url.pathname}${query}`;
        return result.length > 4096 ? result.slice(0, 4096) : result;
      } catch { return 'about:invalid'; }
    };
    const submissionDestinationOf = element => {
      const submitsForm = Boolean(
        (element instanceof HTMLButtonElement
          && (element.type || 'submit').toLowerCase() === 'submit' && element.form)
        || (element instanceof HTMLInputElement
          && ['submit', 'image'].includes(element.type) && element.form)
      );
      // The formAction getter falls back to the document URL. Only use it when the
      // control actually carries the overriding attribute; otherwise the form wins.
      if (submitsForm) {
        if (element.hasAttribute('formaction') && element.formAction) {
          return sanitizedSubmissionDestination(element.formAction);
        }
        return sanitizedSubmissionDestination(element.form.action || null);
      }
      if (element.tagName === 'FORM' && typeof element.action === 'string') {
        return sanitizedSubmissionDestination(element.action);
      }
      if (element.tagName === 'A' && element.hasAttribute('href')) {
        return sanitizedSubmissionDestination(element.href);
      }
      return null;
    };
    const boundedFactValue = (value, criterion) => {
      if (value === null || value === undefined) return null;
      const text = String(value);
      const maximum = Number(criterion.maximumCharacters);
      if (!Number.isSafeInteger(maximum) || maximum <= 0 || text.length <= maximum) return text;
      return text.slice(0, maximum);
    };
    const factValue = (element, criterion) => {
      switch (criterion.fact) {
        case 'role': return roleOf(element);
        case 'accessibleName': return boundedFactValue(nameOf(element), criterion);
        case 'label': return boundedFactValue(labelOf(element), criterion);
        case 'text': return boundedFactValue(collapse(element.innerText) || null, criterion);
        case 'stableAttribute':
          if (criterion.argument === 'tag') return element.localName;
          if (criterion.argument === 'href') {
            return boundedFactValue(sanitizedHref(element), criterion);
          }
          return collapse(element.getAttribute(criterion.argument)) || null;
        case 'contextAnchor':
          return boundedFactValue(contextAnchorOf(element, criterion.argument), criterion);
        case 'domPath': return domPathOf(element);
        case 'enabled': return String(
          !(element.disabled || element.getAttribute('aria-disabled') === 'true'));
        case 'checked':
          if ('checked' in element) return String(Boolean(element.checked));
          if (element.hasAttribute('aria-checked')) {
            return String(element.getAttribute('aria-checked') === 'true');
          }
          return null;
        case 'selected':
          if ('selected' in element) return String(Boolean(element.selected));
          if (element.hasAttribute('aria-selected')) {
            return String(element.getAttribute('aria-selected') === 'true');
          }
          return null;
        case 'selectedOption':
          if (!(element instanceof HTMLSelectElement)) return null;
          return boundedFactValue(collapse(
            Array.from(element.selectedOptions).map(option => option.textContent).join(' ')
          ), criterion);
        case 'stateAttribute':
          if (!element.hasAttribute(criterion.argument)) return null;
          return boundedFactValue(element.getAttribute(criterion.argument) ?? '', criterion);
        default: return null;
      }
    };
    const matchesCriterion = (element, criterion) => {
      const actual = factValue(element, criterion);
      if (actual === null) return criterion.strength !== 'required';
      if (criterion.comparison === 'whitespaceCollapsed') {
        return collapse(actual) === collapse(criterion.expected);
      }
      return actual === criterion.expected;
    };
    const selector = [
      'a[href]', 'button', 'input', 'select', 'textarea', 'summary',
      'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
      'table', 'tr', 'th', 'td',
      '[role]', '[aria-selected]', '[aria-controls]', '[contenteditable="true"]', '[tabindex]'
    ].join(',');
    const candidates = Array.from(new Set([
      ...deepQueryAll(document, selector),
      ...deepQueryAll(document, 'a:not([href]), div, li, span').filter(isPointerControl)
    ]));
    const reportedFactNames = {
      role: 'role', accessibleName: 'accessible_name', label: 'label',
      contextAnchor: 'context_anchor', stableAttribute: 'stable_attribute',
      framePath: 'frame_path', text: 'value', domPath: 'dom_path', enabled: 'enabled',
      checked: 'checked', selected: 'selected', selectedOption: 'selected_option',
      stateAttribute: 'state_attribute'
    };
    const reportedFactName = criterion => {
      const base = reportedFactNames[criterion.fact] || criterion.fact;
      return criterion.argument ? base + ':' + criterion.argument : base;
    };
    // Required clauses decide what the target is. Corroborating ones were filtering just
    // as hard whenever they had a value, which made "corroborating" a lie and let a
    // single structural fact pick an element on its own — the exact thing a DOM path
    // must never be allowed to do.
    const requiredCriteria = criteria.filter(criterion => criterion.strength === 'required');
    const locatorMatches = candidates.filter(element =>
      requiredCriteria.every(criterion => matchesCriterion(element, criterion))
    );
    // The observation handed out this element's identity and browser_act was given it
    // back. Re-deriving the target from a name the element may not have throws that
    // away: twenty-two anonymous checkboxes are one address each, and every one of them
    // resolved to twenty-two candidates. The identity is the disambiguation.
    // It is not a licence to skip the locator. A virtual list recycles its rows, so the
    // pinned node still has to satisfy every required clause, or it is not the element
    // that was observed and this falls back to addressing by meaning.
    // When the pin does not save an ambiguous address, the reason decides what the
    // client should do, and guessing it from the outside costs a round trip each time.
    let pinnedState = 'not_requested';
    const pinnedNode = (() => {
      if (typeof physicalIdentity !== 'string' || !physicalIdentity) return null;
      const reference = globalThis.__webkituiState?.nodesByID?.get(physicalIdentity);
      if (!reference) { pinnedState = 'absent_from_registry'; return null; }
      const node = typeof reference.deref === 'function' ? reference.deref() : null;
      if (!node) { pinnedState = 'collected'; return null; }
      if (!node.isConnected) { pinnedState = 'detached'; return null; }
      const failed = criteria
        .filter(criterion => criterion.strength === 'required')
        .filter(criterion => !matchesCriterion(node, criterion))
        .map(reportedFactName);
      if (failed.length > 0) {
        pinnedState = 'clause_mismatch:' + failed.join(',');
        return null;
      }
      pinnedState = 'used';
      return node;
    })();
    // Identity clauses say what the target is; when several elements are the same
    // thing, the corroborating clauses say which one. Refusing at that point left
    // twenty-two identical checkboxes permanently unreachable, while the observation
    // had already recorded exactly what separates them. This can only ever narrow a set
    // that already satisfies every required clause, so it cannot promote a wrong
    // element — and if it does not land on exactly one, the ambiguity stands.
    const narrowed = (() => {
      if (locatorMatches.length <= 1) return locatorMatches;
      // Position only means something while the set it indexes is the same set. If a row
      // has been added or removed since the observation, the eighth checkbox is no
      // longer the eighth thing the user saw, and picking by structure would silently
      // tick the wrong box — worse than refusing. Same population, or no narrowing.
      if (locatorMatches.length !== expectedCandidateCount) return locatorMatches;
      const corroborating = criteria.filter(criterion => criterion.strength !== 'required');
      if (corroborating.length === 0) return locatorMatches;
      const singled = clauses => {
        const exact = locatorMatches.filter(element =>
          clauses.every(criterion => matchesCriterion(element, criterion)));
        return exact.length === 1 ? exact : null;
      };
      // All of them first: agreement across every corroborating fact is the strongest
      // evidence available. But one volatile fact — a neighbouring label that moved, a
      // caption that changed — must not veto the rest, so fall back to position alone,
      // which is the one corroborator guaranteed to single out a member of a set that
      // has not itself changed.
      const byEverything = singled(corroborating);
      if (byEverything) return byEverything;
      const positional = corroborating.filter(criterion => criterion.fact === 'domPath');
      return (positional.length > 0 ? singled(positional) : null) ?? locatorMatches;
    })();
    const matches = pinnedNode ? [pinnedNode] : narrowed;
    // Zero matches is an absence, not an ambiguity. A client told "not unique" goes
    // looking for a second candidate that does not exist; what it needs is which
    // required fact stopped matching, because that is usually one re-observation away.
    const eliminatedBy = matches.length > 0 ? [] : criteria
      .filter(criterion => criterion.strength === 'required')
      .filter(criterion => !candidates.some(element => matchesCriterion(element, criterion)))
      .map(reportedFactName);
    const describe = element => {
      // The native dispatch computes a screen point from this, so it has to be in
      // top-level coordinates or the click lands at the frame's offset instead.
      const box = viewportRectOf(surfaceOf(element));
      let physicalIdentity = globalThis.__webkituiState.nodeIDs.get(element);
      if (!physicalIdentity) {
        physicalIdentity = `n${globalThis.__webkituiState.nextNodeID++}`;
        globalThis.__webkituiState.nodeIDs.set(element, physicalIdentity);
        globalThis.__webkituiState.nodesByID.set(physicalIdentity, new WeakRef(element));
      }
      return {
        physicalIdentity,
        submissionDestination: submissionDestinationOf(element),
        boundingBox: { x: box.x, y: box.y, width: box.width, height: box.height },
        geometryStable: false,
        actionable: false,
        dispatched: false,
        trustedUserGesture: false
      };
    };
    """

  private static let resolveSource =
    actionHelpers + """
      const element = matches.length === 1 ? matches[0] : null;
      if (element && scrollIntoView) surfaceOf(element).scrollIntoView({ block: 'center', inline: 'center' });
      return JSON.stringify({
        count: matches.length, candidate: element ? describe(element) : null, eliminatedBy,
        pinnedState });
      """

  private static let captureStateSource = """
    const inTopLayer = Array.from(
      document.querySelectorAll('dialog[open], :popover-open')).length;
    const modal = Array.from(document.querySelectorAll('dialog[open], [role="dialog"], [role="alertdialog"]'))
      .some(node => {
        const box = node.getBoundingClientRect();
        return box.width > 0 && box.height > 0;
      });
    // Layers a snapshot can render separately from the page, and therefore drop.
    let composited = 0;
    for (const node of document.querySelectorAll('*')) {
      const style = getComputedStyle(node);
      if (style.position === 'fixed' || style.willChange === 'transform'
          || (style.transform && style.transform !== 'none')) {
        const box = node.getBoundingClientRect();
        if (box.width > 0 && box.height > 0) composited += 1;
      }
      if (composited > 64) break;
    }
    const interactive = Array.from(document.querySelectorAll(
      'button, a[href], input, select, textarea, [role="button"]')).filter(node => {
        const box = node.getBoundingClientRect();
        return box.width > 0 && box.height > 0;
      }).length;
    return JSON.stringify({
      topLayerElementCount: inTopLayer,
      modalPresent: modal,
      compositedLayerCount: composited,
      renderedInteractiveCount: interactive
    });
    """

  /// Which element the page really scrolls in. A single-page app commonly scrolls a
  /// pane while the document itself is fixed, so scrolling the document moved nothing
  /// and then reported the bottom had been reached — the tool said it had finished a
  /// job it had not started.
  private static let scrollerSource = """
    const documentRoot = document.scrollingElement || document.documentElement;
    const documentScrolls = documentRoot.scrollHeight > documentRoot.clientHeight + 1;
    const paneScroller = () => {
      let best = null;
      let bestArea = 0;
      for (const node of document.querySelectorAll('*')) {
        const style = getComputedStyle(node);
        const scrollable = ['auto', 'scroll', 'overlay'].includes(style.overflowY);
        if (!scrollable) continue;
        if (node.scrollHeight <= node.clientHeight + 1) continue;
        const box = node.getBoundingClientRect();
        const area = box.width * box.height;
        if (area > bestArea) { best = node; bestArea = area; }
      }
      return best;
    };
    const scroller = documentScrolls ? documentRoot : (paneScroller() ?? documentRoot);
    const scrollerIsDocument = scroller === documentRoot;
    """

  private static let scrollStateSource = """
    const viewportHeight = scrollerIsDocument ? innerHeight : scroller.clientHeight;
    const viewportWidth = scrollerIsDocument ? innerWidth : scroller.clientWidth;
    const offsetY = scrollerIsDocument ? scrollY : scroller.scrollTop;
    const offsetX = scrollerIsDocument ? scrollX : scroller.scrollLeft;
    const maximumY = Math.max(0, scroller.scrollHeight - viewportHeight);
    return JSON.stringify({
      x: offsetX,
      y: offsetY,
      viewportWidth,
      viewportHeight,
      documentWidth: scroller.scrollWidth,
      documentHeight: scroller.scrollHeight,
      reachedTop: offsetY <= 0,
      reachedBottom: offsetY >= maximumY - 1,
      observationInvalidated: true
    });
    """

  private static let nearestScrollStateSource =
    actionHelpers + """
      const element = matches.length === 1 ? matches[0] : null;
      if (!element) return JSON.stringify({
        x: scrollX, y: scrollY, viewportWidth: innerWidth, viewportHeight: innerHeight,
        documentWidth: document.documentElement.scrollWidth,
        documentHeight: document.documentElement.scrollHeight,
        reachedTop: scrollY <= 0, reachedBottom: false, observationInvalidated: true
      });
      const canScroll = candidate => {
        const style = getComputedStyle(candidate);
        const scrollableY = ['auto', 'scroll', 'overlay'].includes(style.overflowY)
          && candidate.scrollHeight > candidate.clientHeight + 1;
        const scrollableX = ['auto', 'scroll', 'overlay'].includes(style.overflowX)
          && candidate.scrollWidth > candidate.clientWidth + 1;
        return scrollableY || scrollableX;
      };
      let region = element.parentElement;
      while (region && !canScroll(region)) region = region.parentElement;
      if (!region) region = document.scrollingElement || document.documentElement;
      element.scrollIntoView({ block: 'center', inline: 'center', behavior: 'instant' });
      const isRoot = region === document.scrollingElement || region === document.documentElement
        || region === document.body;
      const x = isRoot ? scrollX : region.scrollLeft;
      const y = isRoot ? scrollY : region.scrollTop;
      const viewportWidth = isRoot ? innerWidth : region.clientWidth;
      const viewportHeight = isRoot ? innerHeight : region.clientHeight;
      const documentWidth = region.scrollWidth;
      const documentHeight = region.scrollHeight;
      return JSON.stringify({
        x, y, viewportWidth, viewportHeight, documentWidth, documentHeight,
        reachedTop: y <= 0,
        reachedBottom: y >= Math.max(0, documentHeight - viewportHeight) - 1,
        observationInvalidated: true
      });
      """

  private static let pageScrollSource =
    scrollerSource + """
      if (scrollerIsDocument) {
        scrollBy({ left: deltaX, top: deltaY, behavior: 'instant' });
      } else {
        scroller.scrollBy({ left: deltaX, top: deltaY, behavior: 'instant' });
      }
      """ + scrollStateSource

  private static let textSnapshotSource = """
    const collapseLines = value => String(value ?? '')
      .split(/\\n/).map(line => line.replace(/[\\t ]+/g, ' ').trimEnd()).join('\\n').trim();
    const limit = Math.max(1, Number(maximumCharacters));
    let remaining = limit;
    let truncated = false;
    const take = value => {
      const text = collapseLines(value);
      if (text.length <= remaining) { remaining -= text.length; return text; }
      truncated = true;
      const result = text.slice(0, remaining);
      remaining = 0;
      return result;
    };
    const candidates = Array.from(document.querySelectorAll(
      '[role="log"], [role="terminal"], pre, code, [aria-live], [data-testid*="log" i], [class*="log" i]'
    ));
    for (const element of document.querySelectorAll('div, section, article')) {
      if (element.scrollHeight > element.clientHeight + 8 && collapseLines(element.innerText)) {
        candidates.push(element);
      }
    }
    const seen = new Set();
    const regions = [];
    for (const element of candidates) {
      if (remaining <= 0 || seen.has(element)) continue;
      seen.add(element);
      const text = take(element.innerText || element.textContent);
      if (!text) continue;
      regions.push({
        kind: element.getAttribute('role') || element.localName,
        label: element.getAttribute('aria-label') || element.getAttribute('data-testid') || null,
        text,
        scrollTop: element.scrollTop,
        scrollHeight: element.scrollHeight,
        clientHeight: element.clientHeight
      });
    }
    const bodyText = remaining > 0 ? take(document.body?.innerText || '') : '';
    const pageContentProbe = globalThis.__webkituiPageContentProbe?.() ?? {
      contentState: bodyText ? 'usable' : 'empty_or_unusable',
      renderedContentCount: bodyText ? 1 : 0
    };
    return JSON.stringify({
      bodyText, regions, truncated,
      contentState: pageContentProbe.contentState,
      renderedContentCount: pageContentProbe.renderedContentCount
    });
    """

  private static let performSource =
    actionHelpers + """
      const element = matches.length === 1 ? matches[0] : null;
      if (!element) return JSON.stringify({ count: matches.length, candidate: null, eliminatedBy, pinnedState });
      const candidate = describe(element);
      const surface = surfaceOf(element);
      const box = viewportRectOf(surface);
      const tolerance = 0.5;
      candidate.geometryStable = ['x', 'y', 'width', 'height'].every(key =>
        Math.abs(box[key] - expectedBox[key]) <= tolerance
      );
      const style = getComputedStyle(element);
      const visible = box.width > 0 && box.height > 0 && style.visibility !== 'hidden'
        && style.display !== 'none';
      const enabled = !element.matches(':disabled')
        && element.getAttribute('aria-disabled') !== 'true';
      // box is in top-level coordinates for dispatch; hit testing needs the element's
      // own document and its own coordinates, or a frame's content answers for the
      // outer page.
      let hit = hitAtCentreOfLocal(surface, surface.getBoundingClientRect());
      const composedContains = (ancestor, node) => {
        for (let cursor = node; cursor; cursor = composedParent(cursor)) {
          if (cursor === ancestor) return true;
        }
        return false;
      };
      const receivesEvents = Boolean(hit && (
        composedContains(element, hit) || composedContains(surface, hit)
      ));
      const editable = operation !== 'fill' || (
        (element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement
          || element.isContentEditable) && !element.readOnly
      );
      // A control that cannot be typed into is not the same failure as one behind an
      // overlay or a disabled one, and target_not_actionable was all three.
      if (!editable) candidate.unsupportedOperationRole = roleOf(element) || element.localName;
      candidate.actionable = visible && enabled && receivesEvents && editable
        && candidate.geometryStable && element.isConnected;
      if (candidate.actionable && operation === 'click') {
        let trusted = false;
        const listener = event => { trusted = event.isTrusted; };
        element.addEventListener('click', listener, { capture: true, once: true });
        surface.click();
        candidate.trustedUserGesture = trusted;
        candidate.dispatched = true;
      } else if (candidate.actionable && operation === 'press_key') {
        const options = {
          key: value, bubbles: true, cancelable: true,
          ctrlKey: modifiers.includes('control'), altKey: modifiers.includes('option'),
          shiftKey: modifiers.includes('shift'), metaKey: modifiers.includes('command')
        };
        element.focus({ preventScroll: true });
        element.dispatchEvent(new KeyboardEvent('keydown', options));
        element.dispatchEvent(new KeyboardEvent('keyup', options));
        candidate.trustedUserGesture = false;
        candidate.dispatched = true;
      } else if (candidate.actionable && operation === 'blur') {
        element.focus({ preventScroll: true });
        element.blur();
        candidate.trustedUserGesture = false;
        candidate.dispatched = true;
      } else if (candidate.actionable && operation === 'commit_input') {
        element.focus({ preventScroll: true });
        element.dispatchEvent(new Event('change', { bubbles: true }));
        element.blur();
        candidate.trustedUserGesture = false;
        candidate.dispatched = true;
      } else if (candidate.actionable && operation === 'fill') {
        let trusted = false;
        const listener = event => { trusted = event.isTrusted; };
        element.addEventListener('input', listener, { capture: true, once: true });
        if (element.isContentEditable) {
          // A framework editor keeps its own model and only trusts input events.
          // Assigning textContent went behind its back: the node changed, the model did
          // not, and the field stayed visibly empty while the write reported half a
          // success. Select the contents and let the editor perform the insertion.
          element.focus({ preventScroll: true });
          const selection = getSelection();
          const range = document.createRange();
          range.selectNodeContents(element);
          selection.removeAllRanges();
          selection.addRange(range);
          // execCommand is the only route WebKit exposes that drives its own editing
          // pipeline, so the editor sees the beforeinput and input it is listening for.
          // Raising those events by hand as well would deliver the text twice.
          if (!document.execCommand('insertText', false, value)) {
            element.textContent = value;
          }
        } else {
          const prototype = element instanceof HTMLTextAreaElement
            ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
          const setter = Object.getOwnPropertyDescriptor(prototype, 'value')?.set;
          if (setter) setter.call(element, value); else element.value = value;
        }
        element.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText' }));
        element.dispatchEvent(new Event('change', { bubbles: true }));
        candidate.trustedUserGesture = trusted;
        candidate.dispatched = true;
      } else if (candidate.actionable && operation === 'select_option') {
        // By label, never by index. The label is collapsed exactly as the observation
        // collapses the one it published, so the two cannot disagree about whitespace.
        const wanted = collapse(value);
        const options = Array.from(element.options ?? []);
        const chosen = options.filter(option => collapse(option.textContent) === wanted);
        if (chosen.length === 1) {
          const option = chosen[0];
          const setter =
            Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'value')?.set;
          if (setter) setter.call(element, option.value); else element.value = option.value;
          // Two options may carry the same value attribute under different labels, and
          // assigning the value would then land on the first of them. Select the option
          // that was actually named.
          if (element.selectedOptions[0] !== option) {
            for (const other of options) other.selected = other === option;
          }
          // What a real selection raises, in the order it raises it, both bubbling. A
          // site listens for one of these and nothing else; without them the property
          // is right and the page has not been told.
          element.dispatchEvent(new Event('input', { bubbles: true }));
          element.dispatchEvent(new Event('change', { bubbles: true }));
          // Assigning a property is not a user gesture and never claims to be one.
          candidate.trustedUserGesture = false;
          candidate.dispatched = true;
        }
      } else if (candidate.actionable && operation === 'hover') {
        // WebKit forwards no NSEventTypeMouseMoved to an embedder, so this is the only
        // route there is. It has a real limit: CSS `:hover` is driven by WebKit's own
        // pointer state, which a synthesised MouseEvent does not move, so a menu that
        // opens purely through a `:hover` rule will not open. A menu opened by a
        // mouseover, mouseenter or mousemove listener — the ordinary shape of one that
        // has to work on a touch screen too — will.
        const box = surface.getBoundingClientRect();
        const view = element.ownerDocument?.defaultView ?? window;
        const pointer = {
          bubbles: true, cancelable: true, composed: true, view,
          clientX: box.left + box.width / 2, clientY: box.top + box.height / 2
        };
        surface.dispatchEvent(new MouseEvent('mouseover', pointer));
        // mouseenter neither bubbles nor cancels. A real pointer entering raises it on
        // every element it entered, outermost first, so a wrapper holding the listener —
        // which is where a hover menu usually keeps it — never sees one dispatched at
        // the leaf alone.
        const entered = [];
        for (let cursor = surface; cursor && entered.length < 32; cursor = composedParent(cursor)) {
          entered.push(cursor);
        }
        for (const node of entered.reverse()) {
          node.dispatchEvent(
            new MouseEvent('mouseenter', { ...pointer, bubbles: false, cancelable: false }));
        }
        surface.dispatchEvent(new MouseEvent('mousemove', pointer));
        candidate.trustedUserGesture = false;
        candidate.dispatched = true;
      }
      return JSON.stringify({ count: matches.length, candidate, eliminatedBy, pinnedState });
      """

  /// Reads a `<select>`'s own options: how many carry the requested label, and what it
  /// currently reports as selected. The label is collapsed the way the observation
  /// collapses every label it publishes, so what a caller reads and what this compares
  /// are the same string.
  private static let selectedOptionSurveySource =
    actionHelpers + """
      const element = matches.length === 1 ? matches[0] : null;
      if (!element) return JSON.stringify({ count: matches.length, candidate: null, eliminatedBy, pinnedState });
      const candidate = describe(element);
      candidate.role = roleOf(element);
      if (!(element instanceof HTMLSelectElement)) {
        return JSON.stringify({ count: matches.length, candidate, eliminatedBy, pinnedState });
      }
      const wanted = collapse(label);
      const options = Array.from(element.options);
      const selected = collapse(
        Array.from(element.selectedOptions).map(option => option.textContent).join(' '));
      return JSON.stringify({
        count: matches.length, candidate, eliminatedBy, pinnedState,
        matchingOptionCount:
          options.filter(option => collapse(option.textContent) === wanted).length,
        selectedOptionMatchesRequest: selected === wanted
      });
      """

  private static let maximumRegisteredFrameCapabilities = 32
  private static let frameRegistrationMessageHandlerName = "webkituiFrameRegistration"
  private static let frameRegistrationSource = """
    (() => {
      try {
        globalThis.webkit.messageHandlers.webkituiFrameRegistration.postMessage(true);
      } catch (_) {}
    })();
    """
  private static let bindFrameCapabilitySource = """
    globalThis.__webkituiFrameCapabilityID = capabilityID;
    return globalThis.__webkituiFrameCapabilityID === capabilityID;
    """
  /// Runs in the same async-function body as the resolver. Capability and origin are
  /// checked before any locator or dispatch code, so a navigation cannot turn a retained
  /// `WKFrameInfo` into authority over its replacement document.
  private static let frameActionGuardSource = """
    const __webkituiFrameContextMatches = (() => {
      try {
        return globalThis.__webkituiFrameCapabilityID === expectedFrameCapabilityID
          && String(location.origin) === expectedFrameOrigin;
      } catch (_) { return false; }
    })();
    if (!__webkituiFrameContextMatches) {
      return JSON.stringify({
        count: 0, candidate: null, eliminatedBy: [], pinnedState: 'frame_context_changed',
        frameContextMatches: false
      });
    }
    """
  private static let nativeGestureMessageHandlerName = "webkituiNativeGesture"

  private static let armNativeClickSource =
    actionHelpers + """
      const element = matches.length === 1 ? matches[0] : null;
      if (!element) return JSON.stringify({ count: matches.length, candidate: null, eliminatedBy, pinnedState });
      const candidate = describe(element);
      const surface = surfaceOf(element);
      const box = viewportRectOf(surface);
      const tolerance = 0.5;
      candidate.geometryStable = ['x', 'y', 'width', 'height'].every(key =>
        Math.abs(box[key] - expectedBox[key]) <= tolerance
      );
      const style = getComputedStyle(surface);
      const visible = box.width > 0 && box.height > 0 && style.visibility !== 'hidden'
        && style.display !== 'none' && Number(style.opacity) !== 0;
      const enabled = !element.matches(':disabled')
        && element.getAttribute('aria-disabled') !== 'true';
      // Hit testing in the element's own document: box is in top-level coordinates so
      // the dispatch lands correctly, but a frame answers only about its own points.
      const hit = hitAtCentreOfLocal(surface, surface.getBoundingClientRect());
      const receivesEvents = Boolean(hit && (
        hit === element || element.contains(hit) || hit === surface || surface.contains(hit)
      ));
      candidate.actionable = visible && enabled && receivesEvents
        && candidate.geometryStable && element.isConnected && surface.isConnected;
      if (candidate.actionable) {
        const physicalIdentity = candidate.physicalIdentity;
        const report = event => {
          globalThis.webkit.messageHandlers.webkituiNativeGesture.postMessage({
            token, physicalIdentity, eventType: event.type, trusted: event.isTrusted,
            frameCapabilityID: globalThis.__webkituiFrameCapabilityID ?? null
          });
        };
        element.addEventListener('click', report, { capture: true, once: true });
        if (surface !== element) {
          surface.addEventListener('click', report, { capture: true, once: true });
        }
      }
      return JSON.stringify({ count: matches.length, candidate, eliminatedBy, pinnedState });
      """

  private static let armNativeKeySource =
    actionHelpers + """
      const element = matches.length === 1 ? matches[0] : null;
      if (!element) return JSON.stringify({ count: matches.length, candidate: null, eliminatedBy, pinnedState });
      const candidate = describe(element);
      const surface = surfaceOf(element);
      const box = viewportRectOf(surface);
      const tolerance = 0.5;
      candidate.geometryStable = ['x', 'y', 'width', 'height'].every(key =>
        Math.abs(box[key] - expectedBox[key]) <= tolerance
      );
      const enabled = !element.matches(':disabled')
        && element.getAttribute('aria-disabled') !== 'true';
      candidate.actionable = enabled && candidate.geometryStable
        && element.isConnected && typeof element.focus === 'function';
      if (candidate.actionable) {
        element.focus({ preventScroll: true });
        const physicalIdentity = candidate.physicalIdentity;
        element.addEventListener('keydown', event => {
          if (event.key !== expectedKey) return;
          globalThis.webkit.messageHandlers.webkituiNativeGesture.postMessage({
            token, physicalIdentity, eventType: event.type, trusted: event.isTrusted,
            frameCapabilityID: globalThis.__webkituiFrameCapabilityID ?? null
          });
        }, { capture: true, once: true });
        if (expectedKey === 'Tab') {
          element.addEventListener('blur', event => {
            globalThis.webkit.messageHandlers.webkituiNativeGesture.postMessage({
              token, physicalIdentity, eventType: event.type, trusted: event.isTrusted,
              frameCapabilityID: globalThis.__webkituiFrameCapabilityID ?? null
            });
          }, { capture: true, once: true });
        }
      }
      return JSON.stringify({ count: matches.length, candidate, eliminatedBy, pinnedState });
      """

  private static let armNativeFillSource =
    actionHelpers + """
      const element = matches.length === 1 ? matches[0] : null;
      if (!element) return JSON.stringify({ count: matches.length, candidate: null, eliminatedBy, pinnedState });
      const candidate = describe(element);
      const surface = surfaceOf(element);
      const box = viewportRectOf(surface);
      const tolerance = 0.5;
      candidate.geometryStable = ['x', 'y', 'width', 'height'].every(key =>
        Math.abs(box[key] - expectedBox[key]) <= tolerance
      );
      const editable = element instanceof HTMLInputElement
        || element instanceof HTMLTextAreaElement || element.isContentEditable;
      const enabled = !element.matches(':disabled') && !element.readOnly
        && element.getAttribute('aria-disabled') !== 'true';
      candidate.actionable = editable && enabled && candidate.geometryStable
        && element.isConnected && typeof element.focus === 'function';
      if (candidate.actionable) {
        element.focus({ preventScroll: true });
        if (typeof element.select === 'function') {
          element.select();
        } else if (element.isContentEditable) {
          const selection = getSelection();
          const range = document.createRange();
          range.selectNodeContents(element);
          selection.removeAllRanges();
          selection.addRange(range);
        }
        const physicalIdentity = candidate.physicalIdentity;
        element.addEventListener('input', event => {
          globalThis.webkit.messageHandlers.webkituiNativeGesture.postMessage({
            token, physicalIdentity, eventType: event.type, trusted: event.isTrusted,
            frameCapabilityID: globalThis.__webkituiFrameCapabilityID ?? null
          });
        }, { capture: true, once: true });
        document.addEventListener('keydown', event => {
          if (event.key !== 'Tab') return;
          globalThis.webkit.messageHandlers.webkituiNativeGesture.postMessage({
            token, physicalIdentity, eventType: 'commit_keydown', trusted: event.isTrusted,
            frameCapabilityID: globalThis.__webkituiFrameCapabilityID ?? null
          });
        }, { capture: true, once: true });
      }
      return JSON.stringify({ count: matches.length, candidate, eliminatedBy, pinnedState });
      """

  private static func boxDictionary(_ box: ObservedBoundingBox) -> [String: Double] {
    ["x": box.x, "y": box.y, "width": box.width, "height": box.height]
  }

  private static func boxesMatch(
    _ lhs: ObservedBoundingBox,
    _ rhs: ObservedBoundingBox,
    tolerance: Double = 0.5
  ) -> Bool {
    abs(lhs.x - rhs.x) <= tolerance
      && abs(lhs.y - rhs.y) <= tolerance
      && abs(lhs.width - rhs.width) <= tolerance
      && abs(lhs.height - rhs.height) <= tolerance
  }

  /// Finds the one visible password field in this frame and the username field
  /// before it, and keeps both in the isolated world under a per-request token. It
  /// returns only whether a form was found and whether this frame has focus.
  private static let humanCredentialLocateSource = """
    const usable = (element, allowReadOnly) => {
      if (!(element instanceof HTMLInputElement) || !element.isConnected || element.disabled) {
        return false;
      }
      if (!allowReadOnly && element.readOnly) return false;
      const box = element.getBoundingClientRect();
      const style = getComputedStyle(element);
      return box.width > 0 && box.height > 0 && style.visibility !== 'hidden'
        && style.display !== 'none' && Number(style.opacity) !== 0;
    };
    const passwords = Array.from(document.querySelectorAll('input[type=password]'))
      .filter(element => usable(element, false));
    if (passwords.length !== 1) {
      return JSON.stringify({ found: false, focused: document.hasFocus() });
    }
    const password = passwords[0];
    const scope = password.form || document;
    const inputs = Array.from(scope.querySelectorAll('input'));
    const username = inputs.slice(0, inputs.indexOf(password)).reverse().find(element =>
      usable(element, true)
      && (['text', 'email', 'tel', ''].includes((element.getAttribute('type') || '').toLowerCase())
        || element.autocomplete === 'username'));
    if (!username) return JSON.stringify({ found: false, focused: document.hasFocus() });
    globalThis.__webkituiHumanCredential = { token, username, password };
    return JSON.stringify({ found: true, focused: document.hasFocus() });
    """

  /// Focuses one bound field for a native insertion. A read-only username, as on a
  /// two-step sign-in that already shows the account, is skipped rather than typed.
  private static let humanCredentialFocusSource = """
    const state = globalThis.__webkituiHumanCredential;
    if (!state || state.token !== token) return JSON.stringify({ focused: false, skip: false });
    const element = field === 'username' ? state.username : state.password;
    if (!(element instanceof HTMLInputElement) || !element.isConnected || element.disabled) {
      return JSON.stringify({ focused: false, skip: false });
    }
    if (field === 'username' && element.readOnly) {
      return JSON.stringify({ focused: false, skip: true });
    }
    if (field === 'password' && element.type !== 'password') {
      return JSON.stringify({ focused: false, skip: false });
    }
    element.focus({ preventScroll: false });
    return JSON.stringify({ focused: document.activeElement === element, skip: false });
    """

  private static let credentialFillSource = """
    const nodeFor = identity => {
      for (const element of document.querySelectorAll('input')) {
        if (globalThis.__webkituiState?.nodeIDs?.get(element) === identity) return element;
      }
      return null;
    };
    const usernameElement = nodeFor(usernamePhysicalIdentity);
    const passwordElement = nodeFor(passwordPhysicalIdentity);
    const stable = (element, expectedBox, requiresPassword) => {
      if (!(element instanceof HTMLInputElement) || !element.isConnected) return false;
      if (requiresPassword ? element.type !== 'password' : element.type === 'password') return false;
      if (element.disabled || element.readOnly || element.getAttribute('aria-disabled') === 'true') {
        return false;
      }
      const box = element.getBoundingClientRect();
      const style = getComputedStyle(element);
      if (!(box.width > 0 && box.height > 0) || style.visibility === 'hidden'
          || style.display === 'none' || Number(style.opacity) === 0) return false;
      const tolerance = 0.5;
      if (!['x', 'y', 'width', 'height'].every(key =>
          Math.abs(box[key] - expectedBox[key]) <= tolerance)) return false;
      // This script stands alone and never leaves the top-level document: a credential
      // field is only ever filled where the human confirmed it.
      const centreX = Math.min(innerWidth - 1, Math.max(0, box.left + box.width / 2));
      const centreY = Math.min(innerHeight - 1, Math.max(0, box.top + box.height / 2));
      const hit = document.elementFromPoint(centreX, centreY);
      return Boolean(hit && (hit === element || element.contains(hit)));
    };
    if (!stable(usernameElement, usernameExpectedBox, false)
        || !stable(passwordElement, passwordExpectedBox, true)) {
      return JSON.stringify({ filled: false });
    }
    const setValue = (element, value) => {
      const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set;
      if (setter) setter.call(element, value); else element.value = value;
    };
    // MVP0 deliberately dispatches no DOM event: hostile input/change handlers
    // must not gain an opportunity to autosave or submit the synthetic values.
    setValue(usernameElement, username);
    setValue(passwordElement, password);
    return JSON.stringify({ filled: true });
    """

  private static let credentialRotationFillSource = """
    const nodeFor = identity => {
      for (const element of document.querySelectorAll('input')) {
        if (globalThis.__webkituiState?.nodeIDs?.get(element) === identity) return element;
      }
      return null;
    };
    const current = nodeFor(currentIdentity);
    const next = nodeFor(newIdentity);
    const confirmation = nodeFor(confirmationIdentity);
    const stable = (element, expectedBox) => {
      if (!(element instanceof HTMLInputElement) || !element.isConnected
          || element.type !== 'password' || element.disabled || element.readOnly
          || element.getAttribute('aria-disabled') === 'true') return false;
      const box = element.getBoundingClientRect();
      const style = getComputedStyle(element);
      if (!(box.width > 0 && box.height > 0) || style.visibility === 'hidden'
          || style.display === 'none' || Number(style.opacity) === 0) return false;
      const tolerance = 0.5;
      if (!['x', 'y', 'width', 'height'].every(key =>
          Math.abs(box[key] - expectedBox[key]) <= tolerance)) return false;
      const x = Math.min(innerWidth - 1, Math.max(0, box.left + box.width / 2));
      const y = Math.min(innerHeight - 1, Math.max(0, box.top + box.height / 2));
      const hit = document.elementFromPoint(x, y);
      return Boolean(hit && (hit === element || element.contains(hit)));
    };
    if (!stable(current, currentBox) || !stable(next, newBox)
        || !stable(confirmation, confirmationBox)) {
      return JSON.stringify({ filled: false });
    }
    const setValue = (element, value) => {
      const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set;
      if (setter) setter.call(element, value); else element.value = value;
    };
    // No input/change event and no submit: the human remains the commit point.
    setValue(current, currentPassword);
    setValue(next, newPassword);
    setValue(confirmation, newPassword);
    return JSON.stringify({ filled: true });
    """
}

private struct RawInstrumentationState: Decodable {
  let mutationCount: UInt64
  let readyState: String
  let contentState: PageContentState?
}

private struct RawCredentialFillResult: Decodable {
  let filled: Bool
}

private struct RawObservation: Decodable {
  let url: String
  let title: String
  let readyState: String
  let mutationCount: UInt64
  let walkedFrameCapabilityIDs: [String]
  let crossOriginFrameCount: Int
  let totalElementCount: Int
  let unfilteredCandidateCount: Int
  let transientLoading: Bool
  let renderedInteractiveCount: Int
  let renderedContentCount: Int
  let documentLanguage: String?
  let ariaHiddenDropCount: Int
  let unrenderedControlCount: Int
  let unrenderedControlNames: [String]
  let rawControlCount: Int
  let obscuredByAncestorOpacity: Bool
  let documentElementCount: Int
  let bodyTextLength: Int
  let firstControlProbe: String
  let semanticTextTruncated: Bool
  let elements: [RawElement]
}

private enum FrameObservationEvaluationError: Error {
  case timedOut
}

private struct CapturedObservationGroup {
  let raw: RawObservation
  /// Nil for the top-level collector. A non-nil value is native-only authority used by
  /// future frame-local resolution and is never encoded in an observation.
  let frameCapabilityID: String?
  let frameOrigin: String?
}

private struct RawAuthenticationUIState: Decodable {
  let readyState: String
  let hasProgressIndicator: Bool
  let hasVisibleAuthenticationControl: Bool
  let hasInvisibleAuthenticationControl: Bool
  let hasWebAuthnControl: Bool
}

private struct RawElement: Decodable {
  let physicalIdentity: String
  let frameCapabilityID: String?
  let tag: String
  let role: String?
  let accessibleName: String?
  let submissionDestination: String?
  let label: String?
  let text: String?
  let value: String?
  let validationState: String
  let characterCount: Int?
  let sensitive: Bool
  let submitsForm: Bool
  let disabled: Bool
  let checked: Bool?
  let selected: Bool?
  let selectedOption: String?
  let options: [RawOption]?
  let optionCount: Int?
  let optionsTruncated: Bool?
  let stateAttributes: [String: String]
  let contextAnchors: [RawContextAnchor]
  let domPath: String
  let stableAttributes: [String: String]
  let visible: Bool
  let actionability: String
  let boundingBox: ObservedBoundingBox
}

private struct RawOption: Decodable {
  let label: String
  let selected: Bool
  let disabled: Bool
}

private struct RawContextAnchor: Decodable {
  let kind: String
  let text: String
}

private struct ObservedTargetRecord {
  let recipe: LocatorRecipe
  /// A provenance-private address used only inside the retained native frame. The
  /// public recipe omits third-party strings because `LocatorRecipe` cannot label them.
  let resolutionRecipe: LocatorRecipe
  let physicalIdentity: String
  let boundingBox: ObservedBoundingBox
  let sensitive: Bool
  let disabled: Bool
  let checked: Bool?
  let selected: Bool?
  let selectedOption: String?
  let stateAttributes: [String: String]
  let frameCapabilityID: String?
  let frameOrigin: String?
  /// The bound applied before the locator recipe was constructed. Live resolution must
  /// apply the same bound or an unchanged long fact can never equal its observed value.
  let maximumFieldCharacters: Int
  let observedAtMonotonicNanoseconds: UInt64
  /// How many candidates the address matched when it was handed out. Structure can
  /// separate identical controls only while the set it indexes is unchanged.
  let observedCandidateCount: Int
}

private struct RawHumanCredentialLocation: Decodable {
  let found: Bool
  let focused: Bool
}

private struct RawHumanCredentialFocus: Decodable {
  let focused: Bool
  let skip: Bool
}

private struct FrameActionContext {
  let capabilityID: String
  let documentID: String
  let observationID: String
  let origin: String
  let frameInfo: WKFrameInfo
}

private struct RegisteredFrameCapability {
  let capabilityID: String
  let documentID: String
  let frameInfo: WKFrameInfo
  let origin: String
  let isMainFrame: Bool
}

private struct RawCaptureDOMState: Decodable {
  let topLayerElementCount: Int
  let modalPresent: Bool
  let compositedLayerCount: Int
  let renderedInteractiveCount: Int
}

/// What one panel's caller asked for. `unanswered` is not a decision: it is the
/// absence of one, and it is recorded as such.
private enum JavaScriptDialogAnswer: Sendable {
  case accepted(String?)
  case dismissed
  case unanswered
}

private struct PendingJavaScriptDialogState {
  let dialog: WebKitPendingJavaScriptDialog
  let continuation: CheckedContinuation<JavaScriptDialogAnswer, Never>
}

/// Which of two things happened first: the dispatch script returned, or the gesture it
/// dispatched opened a JavaScript panel and stopped the page.
private enum ActionDispatchRace: Sendable {
  case resolved(RawActionResolution)
  case interruptedByDialog(WebKitPendingJavaScriptDialog)
}

private struct RawActionResolution: Decodable, Sendable {
  let count: Int
  let candidate: RawActionCandidate?
  let eliminatedBy: [String]?
  let pinnedState: String?
  /// Present only on the early frame guard failure. A successful guarded resolution
  /// omits it, and main-document scripts never know the field exists.
  var frameContextMatches: Bool? = nil
  /// How many of a `<select>`'s options carry the requested label. `nil` everywhere the
  /// resolved element is not a `<select>`, and from every script that is not the option
  /// survey.
  var matchingOptionCount: Int?
  /// Whether the freshly re-resolved control now reports the requested label as its
  /// selection. Only the option survey answers it.
  var selectedOptionMatchesRequest: Bool?
}

private struct RawActionCandidate: Decodable, Sendable {
  let physicalIdentity: String
  var submissionDestination: String? = nil
  var role: String?
  let boundingBox: ObservedBoundingBox
  let geometryStable: Bool
  let actionable: Bool
  let dispatched: Bool
  let trustedUserGesture: Bool
  let unsupportedOperationRole: String?
}

private struct NativeGestureReceipt {
  let physicalIdentity: String
  let eventType: String
  let trusted: Bool
}

private struct ArmedNativeGestureContext {
  let frameCapabilityID: String?
  let frameOrigin: String?
}
