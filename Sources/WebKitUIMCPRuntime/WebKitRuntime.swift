import AppKit
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
  case targetNotUnique(Int)
  case targetNotActionable
  case targetGeometryChanged
  /// Nothing matched the address at all. Carries the required facts whose removal would
  /// have matched, which names what changed under the observation.
  case targetNotFound([String])
  case sensitiveInputRequiresHuman
  case downloadInProgress
  case downloadCancelled
  case downloadReceiptTimedOut(started: Bool)
  case unsupportedDownload(httpStatus: Int?)
  case downloadHTTPFailure(status: Int)
  case downloadFailed(String)
  case invalidCredentialOrigin
  case invalidCredentialBinding
  case invalidCredentialSecret
  case humanControlActive
  case authenticationOriginRequiresHuman(String)
  case noPendingCrossOriginNavigation
  case invalidControlTransition
  case nativeGestureReceiptUnavailable
  /// A handoff was requested but no window a human could act in could be shown.
  case handoffSurfaceUnavailable
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

public struct WebKitNavigationResult: Codable, Equatable, Sendable {
  public let documentID: String
  public let url: String
  public let readiness: PageReadiness
  public let elapsedNanoseconds: UInt64
  public let mutationCount: UInt64
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
  public let tag: ProvenancedText
  public let role: ProvenancedText?
  public let accessibleName: ProvenancedText?
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
  public let selectedOption: ProvenancedText?
  public let stateAttributes: [String: ProvenancedText]
  public let contextAnchors: [ObservedContextAnchor]
  public let stableAttributes: [String: ProvenancedText]
  public let visible: Bool
  public let actionability: ObservedActionability
  public var actionable: Bool { actionability == .actionable }
  public let boundingBox: ObservedBoundingBox
  public let locatorRecipe: LocatorRecipe
  public let locatorQuality: LocatorQuality
}

/// Why a control can or cannot be acted on, decided during observation so an agent
/// never has to spend a failed dispatch to find out. `locatorQuality` answers whether
/// the address is unique; it was read as whether the target can be clicked.
public enum ObservedActionability: String, Codable, Equatable, Sendable {
  case actionable
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

public enum ObservedValidationState: String, Codable, Equatable, Sendable {
  case valid
  case invalid
  case notApplicable = "not_applicable"
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
  public let semanticTextTruncated: Bool
  public let crossOriginFramesOpaque: Bool
  /// Controls the raw DOM renders, counted independently of the semantic matcher.
  public let renderedInteractiveCount: Int
  /// Rendered controls dropped only because an ancestor is aria-hidden or inert.
  /// A page that paints its controls and marks them hidden leaves an empty tree for
  /// a reason the caller must be able to see.
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
}

public struct WebKitCapture: Sendable {
  public let pngData: Data
  public let width: Int
  public let height: Int
  public let backingScaleFactor: Double
  public let compositorEffectsMayBeMissing: Bool
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
}

public enum WebKitActionOperation: Sendable {
  case click
  case fill(ProvenancedText)
  case pressKey(String)
  case blur
  case commitInput
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
  private var topLevelOriginLock: SecurityOrigin?
  private let formAuditKey = SymmetricKey(size: .bits256)
  private var formSubmissionEvents: [FormSubmissionAuditEvent] = []
  private var webContentTerminationEvents: [WebContentTerminationEvent] = []
  private var lastCommittedHTTPURL: URL?
  private var authenticationUIClassification: AuthenticationUIClassification?
  private var restrictedAuthenticationFrameOrigin: String?
  private var restrictedWebAuthnOrigin: String?
  private var pendingCrossOriginNavigationRequest: URLRequest?
  private let egressProxy: PinnedSOCKSProxy?
  private var armedNativeGestureTokens: Set<String> = []
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
      (@MainActor @Sendable (Bool, Bool) async -> [URL]?)? = nil
  ) {
    self.egressProxy = egressProxy
    self.managesApplicationActivationPolicy = managesApplicationActivationPolicy
    self.downloadDestinationProvider = downloadDestinationProvider
    self.uploadSelectionProvider = uploadSelectionProvider
    let configuration = WKWebViewConfiguration()
    let contentController = WKUserContentController()
    let world = WKContentWorld.world(name: "WebKitUIMCP.Instrumentation")
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
    webView.navigationDelegate = self
    webView.uiDelegate = self
    _ = makeBrowserWindow()
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
    let state = try await instrumentationState()
    await refreshAuthenticationUIClassification()
    let loadedURL = webView.url ?? baseURL
    return WebKitNavigationResult(
      documentID: documentID,
      url: agentSafeURLString(loadedURL) ?? "about:blank",
      readiness: readiness,
      elapsedNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
      mutationCount: state.mutationCount
    )
  }

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
    guard !processTerminated else { throw WebKitRuntimeError.webContentProcessTerminated }

    let script = Self.observationSource.replacingOccurrences(
      of: "__MAXIMUM_ELEMENTS__",
      with: String(maximumElements)
    )
    let arguments: [String: Any] = [
      "roleFilters": roles.map { $0.lowercased() },
      "nameFilter": nameContains?.lowercased() ?? "",
      "elementOffset": elementOffset,
      "maximumFieldCharacters": maximumFieldCharacters,
    ]
    func captureRawObservation() async throws -> RawObservation {
      guard
        let json = try await webView.callAsyncJavaScript(
          script, arguments: arguments, in: nil, contentWorld: instrumentationWorld) as? String,
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

    let recipes = try raw.elements.enumerated().map { index, element in
      let elementID = "e\(index + 1)"
      return try locatorRecipe(
        for: element,
        peers: raw.elements,
        elementID: elementID,
        observationID: observationID,
        generation: nextGeneration)
    }
    let candidates = raw.elements.map(locatorCandidate)
    let candidateCountIsLowerBound = raw.totalElementCount > raw.elements.count
    let elements = try raw.elements.enumerated().map { index, element in
      let elementID = "e\(index + 1)"
      let recipe = recipes[index]
      let resolution = LocatorResolver.resolve(recipe: recipe, candidates: candidates)
      let quality = locatorQuality(
        recipe: recipe,
        candidateCount: resolution.finalCandidateCount,
        candidateCountIsLowerBound: candidateCountIsLowerBound)
      return try WebKitObservedElement(
        elementID: elementID,
        tag: ProvenancedText(text: element.tag, source: pageSource),
        role: try element.role.map { try ProvenancedText(text: $0, source: pageSource) },
        accessibleName: try element.accessibleName.map {
          try ProvenancedText(text: $0, source: pageSource)
        },
        label: try element.label.map { try ProvenancedText(text: $0, source: pageSource) },
        text: try element.text.map { try ProvenancedText(text: $0, source: pageSource) },
        value: try element.value.map {
          try ProvenancedText(text: $0, source: enteredDataSource)
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
          try ProvenancedText(text: $0, source: pageSource)
        },
        stateAttributes: try element.stateAttributes.mapValues {
          try ProvenancedText(text: $0, source: pageSource)
        },
        contextAnchors: try element.contextAnchors.compactMap { anchor in
          guard let kind = ObservedContextAnchorKind(rawValue: anchor.kind) else { return nil }
          return ObservedContextAnchor(
            kind: kind,
            text: try ProvenancedText(text: anchor.text, source: pageSource))
        },
        stableAttributes: try element.stableAttributes.mapValues {
          try ProvenancedText(text: $0, source: pageSource)
        },
        visible: element.visible,
        actionability: ObservedActionability(rawValue: element.actionability) ?? .actionable,
        boundingBox: element.boundingBox,
        locatorRecipe: recipe,
        locatorQuality: quality
      )
    }
    latestObservationID = observationID
    latestTargets = Dictionary(
      uniqueKeysWithValues: zip(elements, raw.elements).map { element, rawElement in
        (
          element.elementID,
          ObservedTargetRecord(
            recipe: element.locatorRecipe,
            physicalIdentity: rawElement.physicalIdentity,
            boundingBox: rawElement.boundingBox,
            sensitive: rawElement.sensitive,
            disabled: rawElement.disabled,
            observedAtMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds
          )
        )
      }
    )

    let observation = WebKitPageObservation(
      observationID: observationID,
      generation: nextGeneration,
      documentID: documentID,
      url: try ProvenancedText(text: raw.url, source: toolSource),
      title: try ProvenancedText(text: raw.title, source: pageSource),
      readyState: raw.readyState,
      mutationCount: raw.mutationCount,
      elements: elements,
      totalElementCount: raw.totalElementCount,
      elementOffset: elementOffset,
      nextElementOffset: elementOffset + elements.count < raw.totalElementCount
        ? elementOffset + elements.count : nil,
      semanticTextTruncated: raw.semanticTextTruncated,
      crossOriginFramesOpaque: raw.crossOriginFrameCount > 0,
      renderedInteractiveCount: raw.renderedInteractiveCount,
      ariaHiddenDropCount: raw.ariaHiddenDropCount,
      unrenderedControlCount: raw.unrenderedControlCount,
      unrenderedControlNames: raw.unrenderedControlNames,
      rawControlCount: raw.rawControlCount,
      obscuredByAncestorOpacity: raw.obscuredByAncestorOpacity,
      documentElementCount: raw.documentElementCount,
      bodyTextLength: raw.bodyTextLength,
      firstControlProbe: raw.firstControlProbe,
      capturedAtMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds
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
    let criteria = locatorCriteria(recipe, expectedEnabled: !target.disabled)
    let resolution = try await resolveTarget(
      criteria: criteria, scrollIntoView: true)
    guard resolution.count == 1 else {
      throw WebKitRuntimeError.targetNotUnique(resolution.count)
    }
    return try await performScroll(
      source: Self.nearestScrollStateSource,
      arguments: ["criteria": criteria, "physicalIdentity": ""]
    )
  }

  public func readText(maximumCharacters: Int = 20_000) async throws -> WebKitTextSnapshot {
    try requireAgentControl()
    guard maximumCharacters > 0 else {
      throw WebKitRuntimeError.malformedInstrumentationResult
    }
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
    return WebKitCapture(
      pngData: png,
      width: bitmap.pixelsWide,
      height: bitmap.pixelsHigh,
      backingScaleFactor: Double(bitmap.pixelsWide) / webView.bounds.width,
      compositorEffectsMayBeMissing: true
    )
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
    let resolution = try await resolveTarget(
      criteria: locatorCriteria(recipe, expectedEnabled: !target.disabled), scrollIntoView: false)
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

    let criteria = locatorCriteria(target.recipe, expectedEnabled: !target.disabled)
    let first = try await resolveTarget(
      criteria: criteria, scrollIntoView: true, physicalIdentity: target.physicalIdentity)
    try recordCardinality(
      first.count, target: target, eliminatedBy: first.eliminatedBy ?? [])
    guard let firstCandidate = first.candidate else {
      if first.count == 0 {
        throw WebKitRuntimeError.targetNotFound(first.eliminatedBy ?? [])
      }
      throw WebKitRuntimeError.targetNotUnique(first.count)
    }
    try await Task.sleep(for: stabilityInterval)

    let value: String?
    let operationName: String
    switch operation {
    case .click:
      operationName = "click"
      value = nil
    case .fill(let provenancedValue):
      guard !target.sensitive else { throw WebKitRuntimeError.sensitiveInputRequiresHuman }
      operationName = "fill"
      value = provenancedValue.segments.map(\.text).joined()
    case .pressKey(let key):
      operationName = "press_key"
      value = key
    case .blur:
      operationName = "blur"
      value = nil
    case .commitInput:
      operationName = "commit_input"
      value = nil
    }

    armNavigationActor(.agentAction)
    let second: RawActionResolution
    if dispatchMode == .nativeAppKit, operationName == "click" {
      second = try await resolveAndPerformNativeClick(
        criteria: criteria, physicalIdentity: target.physicalIdentity,
        expectedBoundingBox: firstCandidate.boundingBox)
    } else if dispatchMode == .nativeAppKit, operationName == "press_key", let value {
      second = try await resolveAndPerformNativeKey(
        criteria: criteria, physicalIdentity: target.physicalIdentity,
        expectedBoundingBox: firstCandidate.boundingBox, key: value)
    } else if dispatchMode == .nativeAppKit, operationName == "fill", let value {
      second = try await resolveAndPerformNativeFill(
        criteria: criteria, physicalIdentity: target.physicalIdentity,
        expectedBoundingBox: firstCandidate.boundingBox, value: value)
    } else {
      second = try await resolveAndPerform(
        criteria: criteria,
        physicalIdentity: target.physicalIdentity,
        expectedBoundingBox: firstCandidate.boundingBox,
        operation: operationName,
        value: value
      )
    }
    try recordCardinality(
      second.count, target: target, eliminatedBy: second.eliminatedBy ?? [])
    guard let candidate = second.candidate else {
      if second.count == 0 {
        throw WebKitRuntimeError.targetNotFound(second.eliminatedBy ?? [])
      }
      throw WebKitRuntimeError.targetNotUnique(second.count)
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
    guard candidate.actionable, candidate.dispatched else {
      throw WebKitRuntimeError.targetNotActionable
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
    if armedNavigationActor?.actor == .agentAction {
      armedNavigationActor = nil
    }
    return result
  }

  public func interactionControlState() -> InteractionControlState { controlState }

  public func latestNavigationAuditEvent() -> WebKitNavigationAuditEvent? {
    navigationAuditEvents.last
  }

  public func navigationAuditEventCount() -> Int { navigationAuditEvents.count }

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
    guard message.name == Self.nativeGestureMessageHandlerName,
      let body = message.body as? [String: Any],
      let token = body["token"] as? String,
      armedNativeGestureTokens.contains(token),
      let physicalIdentity = body["physicalIdentity"] as? String,
      let eventType = body["eventType"] as? String,
      let trusted = body["trusted"] as? Bool
    else { return }
    nativeGestureReceipts[token, default: []].append(
      NativeGestureReceipt(
        physicalIdentity: physicalIdentity, eventType: eventType, trusted: trusted))
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
    else { return url.absoluteString }
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
    window.level = .normal
    window.collectionBehavior.remove(.transient)
    window.setFrame(
      NSRect(origin: .zero, size: window.frame.size), display: false)
    window.center()
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
    if managesApplicationActivationPolicy {
      application.activate(ignoringOtherApps: true)
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
    let controls = NSStackView(views: [instruction, done])
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
      return try await observe(maximumElements: maximumElements)
    } catch {
      if controlState == .resumeRequested {
        presentHumanControlWindow()
        transition(to: .humanControlled, observationID: nil)
      }
      throw error
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
    guard let lockedOrigin = topLevelOriginLock else {
      recordNavigationAudit(navigationAction, allowed: true)
      return .allow
    }
    guard navigationAction.targetFrame?.isMainFrame == true else {
      return navigationAction.targetFrame == nil ? .cancel : .allow
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

  public func webView(
    _ webView: WKWebView,
    didFail navigation: WKNavigation!,
    withError error: any Error
  ) {
    if navigationFailure == nil && !(downloadStarted && Self.isDownloadCancellation(error)) {
      navigationFailure = Self.sanitizedNavigationFailure(error)
    }
  }

  public func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: any Error
  ) {
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
    let state = try await instrumentationState()
    await refreshAuthenticationUIClassification()
    rememberRecoverableURL(webView.url ?? request.url)
    processTerminated = false
    let loadedURL = webView.url ?? request.url
    return WebKitNavigationResult(
      documentID: documentID,
      url: agentSafeURLString(loadedURL) ?? "about:blank",
      readiness: readiness,
      elapsedNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
      mutationCount: state.mutationCount
    )
  }

  private func locatorCriteria(
    _ recipe: LocatorRecipe,
    expectedEnabled: Bool? = nil
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
      ]
    }
    if let expectedEnabled {
      criteria.append([
        "fact": "enabled",
        "argument": "",
        "expected": String(expectedEnabled),
        "strength": "required",
        "comparison": "exact",
      ])
    }
    return criteria
  }

  private func resolveTarget(
    criteria: [[String: String]],
    scrollIntoView: Bool,
    physicalIdentity: String = ""
  ) async throws -> RawActionResolution {
    try await actionScript(
      source: Self.resolveSource,
      arguments: [
        "criteria": criteria,
        "physicalIdentity": physicalIdentity,
        "scrollIntoView": scrollIntoView,
      ]
    )
  }

  private func resolveAndPerform(
    criteria: [[String: String]],
    physicalIdentity: String,
    expectedBoundingBox: ObservedBoundingBox,
    operation: String,
    value: String?
  ) async throws -> RawActionResolution {
    var arguments: [String: Any] = [
      "criteria": criteria,
      "physicalIdentity": physicalIdentity,
      "expectedBox": [
        "x": expectedBoundingBox.x,
        "y": expectedBoundingBox.y,
        "width": expectedBoundingBox.width,
        "height": expectedBoundingBox.height,
      ],
      "operation": operation,
    ]
    if let value { arguments["value"] = value }
    return try await actionScript(source: Self.performSource, arguments: arguments)
  }

  private func resolveAndPerformNativeClick(
    criteria: [[String: String]],
    physicalIdentity: String,
    expectedBoundingBox: ObservedBoundingBox
  ) async throws -> RawActionResolution {
    let token = UUID().uuidString
    armedNativeGestureTokens.insert(token)
    defer {
      armedNativeGestureTokens.remove(token)
      nativeGestureReceipts.removeValue(forKey: token)
    }
    let armed = try await actionScript(
      source: Self.armNativeClickSource,
      arguments: [
        "criteria": criteria,
        "physicalIdentity": physicalIdentity,
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
            trustedUserGesture: receipt.trusted
          ),
          eliminatedBy: nil)
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
    expectedBoundingBox: ObservedBoundingBox,
    key: String
  ) async throws -> RawActionResolution {
    guard let window = webView.window, window.makeFirstResponder(webView) else {
      throw WebKitRuntimeError.targetNotActionable
    }
    let token = UUID().uuidString
    armedNativeGestureTokens.insert(token)
    defer {
      armedNativeGestureTokens.remove(token)
      nativeGestureReceipts.removeValue(forKey: token)
    }
    let armed = try await actionScript(
      source: Self.armNativeKeySource,
      arguments: [
        "criteria": criteria,
        "physicalIdentity": physicalIdentity,
        "expectedBox": Self.boxDictionary(expectedBoundingBox),
        "token": token,
        "expectedKey": key,
      ])
    guard armed.count == 1, let candidate = armed.candidate else { return armed }
    guard candidate.geometryStable, candidate.actionable else { return armed }
    try dispatchNativeKey(key)
    let expectedReceiptEvent = key == "Tab" ? "blur" : "keydown"
    let deadline = ContinuousClock.now + .seconds(1)
    while ContinuousClock.now < deadline {
      if let receipt = nativeGestureReceipt(
        token: token, physicalIdentity: candidate.physicalIdentity,
        eventType: expectedReceiptEvent)
      {
        return RawActionResolution(
          count: armed.count,
          candidate: RawActionCandidate(
            physicalIdentity: candidate.physicalIdentity,
            boundingBox: candidate.boundingBox,
            geometryStable: candidate.geometryStable,
            actionable: candidate.actionable,
            dispatched: true,
            trustedUserGesture: receipt.trusted
          ),
          eliminatedBy: nil)
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw WebKitRuntimeError.nativeGestureReceiptUnavailable
  }

  private func resolveAndPerformNativeFill(
    criteria: [[String: String]],
    physicalIdentity: String,
    expectedBoundingBox: ObservedBoundingBox,
    value: String
  ) async throws -> RawActionResolution {
    guard let window = webView.window, window.makeFirstResponder(webView) else {
      throw WebKitRuntimeError.targetNotActionable
    }
    let token = UUID().uuidString
    armedNativeGestureTokens.insert(token)
    defer {
      armedNativeGestureTokens.remove(token)
      nativeGestureReceipts.removeValue(forKey: token)
    }
    let armed = try await actionScript(
      source: Self.armNativeFillSource,
      arguments: [
        "criteria": criteria,
        "physicalIdentity": physicalIdentity,
        "expectedBox": Self.boxDictionary(expectedBoundingBox),
        "token": token,
      ])
    guard armed.count == 1, let candidate = armed.candidate else { return armed }
    guard candidate.geometryStable, candidate.actionable else { return armed }

    webView.insertText(value)
    let deadline = ContinuousClock.now + .seconds(1)
    while ContinuousClock.now < deadline {
      if let inputReceipt = nativeGestureReceipt(
        token: token, physicalIdentity: candidate.physicalIdentity, eventType: "input")
      {
        // Commit within the same confirmed action. A later action can address
        // a framework replacement node and leave validation state untouched.
        try dispatchNativeKey("Tab")
        let commitDeadline = ContinuousClock.now + .seconds(1)
        while ContinuousClock.now < commitDeadline {
          if let commitReceipt = nativeGestureReceipt(
            token: token, physicalIdentity: candidate.physicalIdentity,
            eventType: "commit_keydown")
          {
            return RawActionResolution(
              count: armed.count,
              candidate: RawActionCandidate(
                physicalIdentity: candidate.physicalIdentity,
                boundingBox: candidate.boundingBox,
                geometryStable: candidate.geometryStable,
                actionable: candidate.actionable,
                dispatched: true,
                trustedUserGesture: inputReceipt.trusted && commitReceipt.trusted
              ),
              eliminatedBy: nil)
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

  private func dispatchNativeKey(_ key: String) throws {
    guard let window = webView.window else { throw WebKitRuntimeError.targetNotActionable }
    let mapping: (characters: String, keyCode: UInt16)
    switch key {
    case "Enter": mapping = ("\r", 36)
    case "Tab": mapping = ("\t", 48)
    case "Escape": mapping = ("\u{1B}", 53)
    default: throw WebKitRuntimeError.targetNotActionable
    }
    let timestamp = ProcessInfo.processInfo.systemUptime
    guard
      let down = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: timestamp,
        windowNumber: window.windowNumber, context: nil, characters: mapping.characters,
        charactersIgnoringModifiers: mapping.characters, isARepeat: false, keyCode: mapping.keyCode),
      let up = NSEvent.keyEvent(
        with: .keyUp, location: .zero, modifierFlags: [], timestamp: timestamp + 0.001,
        windowNumber: window.windowNumber, context: nil, characters: mapping.characters,
        charactersIgnoringModifiers: mapping.characters, isARepeat: false, keyCode: mapping.keyCode)
    else { throw WebKitRuntimeError.targetNotActionable }
    window.sendEvent(down)
    window.sendEvent(up)
  }

  private func actionScript(
    source: String,
    arguments: [String: Any]
  ) async throws -> RawActionResolution {
    guard
      let json = try await webView.callAsyncJavaScript(
        source,
        arguments: arguments,
        in: nil,
        contentWorld: instrumentationWorld
      ) as? String,
      let data = json.data(using: .utf8),
      let result = try? JSONDecoder().decode(RawActionResolution.self, from: data)
    else {
      throw WebKitRuntimeError.malformedInstrumentationResult
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
    _ count: Int, target: ObservedTargetRecord, eliminatedBy: [String] = []
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
    throw WebKitRuntimeError.targetNotUnique(count)
  }

  private func requireAgentControl() throws {
    guard controlState == .agentControlled || controlState == .freshlyReobserved else {
      throw WebKitRuntimeError.humanControlActive
    }
    try requireNonAuthenticationOrigin()
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
    observationGeneration = 0
    navigationFailure = nil
    processTerminated = false
    authenticationUIClassification = nil
    restrictedAuthenticationFrameOrigin = nil
    restrictedWebAuthnOrigin = nil
    pendingCrossOriginNavigationRequest = nil
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
    let navigationType: String
    switch action.navigationType {
    case .linkActivated: navigationType = "link_activated"
    case .formSubmitted: navigationType = "form_submitted"
    case .backForward: navigationType = "back_forward"
    case .reload: navigationType = "reload"
    case .formResubmitted: navigationType = "form_resubmitted"
    case .other: navigationType = "other"
    @unknown default: navigationType = "unknown"
    }
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
  private static let fullBrowserAuthenticationParents: [String: Set<String>] = [
    "appstoreconnect.apple.com": ["idmsa.apple.com"]
  ]

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

  private func instrumentationState() async throws -> RawInstrumentationState {
    guard
      let json = try await webView.callAsyncJavaScript(
        "return JSON.stringify(globalThis.__webkituiState ?? null);",
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
    if !hasStrongIdentity || candidateCount == 0 || candidateCountIsLowerBound {
      status = .insufficient
      recommended = "contextual_reobserve_or_handoff"
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
    const deepQueryAll = (root, selector) => {
      const matches = [];
      const roots = [root];
      for (let index = 0; index < roots.length; index += 1) {
        const current = roots[index];
        matches.push(...current.querySelectorAll(selector));
        for (const host of current.querySelectorAll('*')) {
          if (host.shadowRoot) roots.push(host.shadowRoot);
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
      'current-password', 'new-password', 'one-time-code', 'webauthn'
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
    const hitAtCentreOf = box => {
      const x = Math.min(innerWidth - 1, Math.max(0, box.left + box.width / 2));
      const y = Math.min(innerHeight - 1, Math.max(0, box.top + box.height / 2));
      let hit = document.elementFromPoint(x, y);
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
      return hitReaches(hitAtCentreOf(box), element);
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
        if (text) return bounded(text);
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
      if (box.bottom <= 0 || box.right <= 0 || box.top >= innerHeight || box.left >= innerWidth) {
        return 'off_viewport';
      }
      return hitReaches(hitAtCentreOf(box), element, surface) ? 'actionable' : 'covered';
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
        const editable = !element.disabled && !element.readOnly;
        let observableValue = null;
        if (!sensitive && editable && element instanceof HTMLSelectElement) {
          observableValue = collapse(
            Array.from(element.selectedOptions).map(option => option.textContent).join(' ')) || null;
        } else if (!sensitive && editable && element instanceof HTMLTextAreaElement) {
          observableValue = rawValue !== null && rawValue.length <= maximumFieldCharacters ? rawValue : null;
        } else if (!sensitive && editable && element instanceof HTMLInputElement
                   && ['text', 'search', 'email', 'tel', 'url', 'number'].includes(element.type)) {
          observableValue = rawValue !== null && rawValue.length <= maximumFieldCharacters ? rawValue : null;
        } else if (!sensitive && editable && element.isContentEditable) {
          const editableValue = element.textContent ?? '';
          observableValue = editableValue.length <= maximumFieldCharacters ? editableValue : null;
        }
        const selectedLabel = element instanceof HTMLSelectElement
          ? collapse(Array.from(element.selectedOptions).map(option => option.textContent).join(' '))
          : null;
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
        return {
          physicalIdentity,
          tag: element.localName,
          role: roleOf(element),
          accessibleName: bounded(nameOf(element)),
          label: bounded(labelOf(element)),
          text: sensitive || withheldForInvisibility
            ? null : bounded(selectedLabel || collapse(element.innerText) || null),
          value: withheldForInvisibility ? null : boundedFieldValue(observableValue),
          validationState,
          characterCount: withheldForInvisibility ? null : characterCount,
          sensitive,
          submitsForm: Boolean(
            (element instanceof HTMLButtonElement
              && (element.type || 'submit').toLowerCase() === 'submit' && element.form)
            || (element instanceof HTMLInputElement
              && ['submit', 'image'].includes(element.type) && element.form)
          ),
          disabled: Boolean(element.disabled || element.getAttribute('aria-disabled') === 'true'),
          checked,
          selected,
          selectedOption: withheldForInvisibility ? null : bounded(selectedLabel || null),
          stateAttributes: Object.fromEntries(
            Object.entries(stateAttributes).map(([key, value]) => [key, bounded(value) ?? ''])),
          contextAnchors: sensitive ? [] : contextAnchorsOf(element),
          stableAttributes: stableAttributesOf(element, sensitive),
          visible: actionability !== 'no_layout_box' && actionability !== 'not_visible',
          actionability,
          boundingBox: { x: box.x, y: box.y, width: box.width, height: box.height }
        };
      });
    let crossOriginFrameCount = 0;
    for (const frame of document.querySelectorAll('iframe')) {
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
      crossOriginFrameCount,
      totalElementCount: matchingElements.length,
      unfilteredCandidateCount: Array.from(new Set([...semanticElements, ...pointerElements])).length,
      renderedInteractiveCount,
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
    const hitAtCentreOf = box => {
      const x = Math.min(innerWidth - 1, Math.max(0, box.left + box.width / 2));
      const y = Math.min(innerHeight - 1, Math.max(0, box.top + box.height / 2));
      let hit = document.elementFromPoint(x, y);
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
      return hitReaches(hitAtCentreOf(box), element);
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
        if (text) return bounded(text);
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
      if (box.bottom <= 0 || box.right <= 0 || box.top >= innerHeight || box.left >= innerWidth) {
        return 'off_viewport';
      }
      return hitReaches(hitAtCentreOf(box), element, surface) ? 'actionable' : 'covered';
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
        if (candidate === element || candidate.contains(element) || !isRendered(candidate)) continue;
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
        while (sibling && !isRendered(sibling)) sibling = sibling.previousElementSibling;
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
    const factValue = (element, criterion) => {
      switch (criterion.fact) {
        case 'role': return roleOf(element);
        case 'accessibleName': return nameOf(element);
        case 'label': return labelOf(element);
        case 'text': return collapse(element.innerText) || null;
        case 'stableAttribute':
          if (criterion.argument === 'tag') return element.localName;
          if (criterion.argument === 'href') return sanitizedHref(element);
          return collapse(element.getAttribute(criterion.argument)) || null;
        case 'contextAnchor': return contextAnchorOf(element, criterion.argument);
        case 'enabled': return String(
          !(element.disabled || element.getAttribute('aria-disabled') === 'true'));
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
    const locatorMatches = candidates.filter(element =>
      criteria.every(criterion => matchesCriterion(element, criterion))
    );
    // The observation handed out this element's identity and browser_act was given it
    // back. Re-deriving the target from a name the element may not have throws that
    // away: twenty-two anonymous checkboxes are one address each, and every one of them
    // resolved to twenty-two candidates. The identity is the disambiguation.
    // It is not a licence to skip the locator. A virtual list recycles its rows, so the
    // pinned node still has to satisfy every required clause, or it is not the element
    // that was observed and this falls back to addressing by meaning.
    const pinnedNode = (() => {
      if (typeof physicalIdentity !== 'string' || !physicalIdentity) return null;
      const reference = globalThis.__webkituiState?.nodesByID?.get(physicalIdentity);
      const node = typeof reference?.deref === 'function' ? reference.deref() : null;
      if (!node || !node.isConnected) return null;
      return criteria.every(criterion => matchesCriterion(node, criterion)) ? node : null;
    })();
    const matches = pinnedNode ? [pinnedNode] : locatorMatches;
    // Zero matches is an absence, not an ambiguity. A client told "not unique" goes
    // looking for a second candidate that does not exist; what it needs is which
    // required fact stopped matching, because that is usually one re-observation away.
    const reportedFactNames = {
      role: 'role', accessibleName: 'accessible_name', label: 'label',
      contextAnchor: 'context_anchor', stableAttribute: 'stable_attribute',
      framePath: 'frame_path', text: 'value', domPath: 'dom_path', enabled: 'enabled'
    };
    const reportedFactName = criterion => {
      const base = reportedFactNames[criterion.fact] || criterion.fact;
      return criterion.argument ? base + ':' + criterion.argument : base;
    };
    const eliminatedBy = matches.length > 0 ? [] : criteria
      .filter(criterion => criterion.strength === 'required')
      .filter(criterion => !candidates.some(element => matchesCriterion(element, criterion)))
      .map(reportedFactName);
    const describe = element => {
      const box = surfaceOf(element).getBoundingClientRect();
      let physicalIdentity = globalThis.__webkituiState.nodeIDs.get(element);
      if (!physicalIdentity) {
        physicalIdentity = `n${globalThis.__webkituiState.nextNodeID++}`;
        globalThis.__webkituiState.nodeIDs.set(element, physicalIdentity);
        globalThis.__webkituiState.nodesByID.set(physicalIdentity, new WeakRef(element));
      }
      return {
        physicalIdentity,
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
        count: matches.length, candidate: element ? describe(element) : null, eliminatedBy });
      """

  private static let scrollStateSource = """
    const root = document.scrollingElement || document.documentElement;
    const maximumY = Math.max(0, root.scrollHeight - innerHeight);
    return JSON.stringify({
      x: scrollX,
      y: scrollY,
      viewportWidth: innerWidth,
      viewportHeight: innerHeight,
      documentWidth: root.scrollWidth,
      documentHeight: root.scrollHeight,
      reachedTop: scrollY <= 0,
      reachedBottom: scrollY >= maximumY - 1,
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

  private static let pageScrollSource = """
    scrollBy({ left: deltaX, top: deltaY, behavior: 'instant' });
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
    return JSON.stringify({ bodyText, regions, truncated });
    """

  private static let performSource =
    actionHelpers + """
      const element = matches.length === 1 ? matches[0] : null;
      if (!element) return JSON.stringify({ count: matches.length, candidate: null, eliminatedBy });
      const candidate = describe(element);
      const surface = surfaceOf(element);
      const box = surface.getBoundingClientRect();
      const tolerance = 0.5;
      candidate.geometryStable = ['x', 'y', 'width', 'height'].every(key =>
        Math.abs(box[key] - expectedBox[key]) <= tolerance
      );
      const style = getComputedStyle(element);
      const visible = box.width > 0 && box.height > 0 && style.visibility !== 'hidden'
        && style.display !== 'none';
      const enabled = !element.matches(':disabled')
        && element.getAttribute('aria-disabled') !== 'true';
      const centerX = Math.min(innerWidth - 1, Math.max(0, box.left + box.width / 2));
      const centerY = Math.min(innerHeight - 1, Math.max(0, box.top + box.height / 2));
      let hit = document.elementFromPoint(centerX, centerY);
      while (hit?.shadowRoot && typeof hit.shadowRoot.elementFromPoint === 'function') {
        const nested = hit.shadowRoot.elementFromPoint(centerX, centerY);
        if (!nested || nested === hit) break;
        hit = nested;
      }
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
        const options = { key: value, bubbles: true, cancelable: true };
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
          element.textContent = value;
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
      }
      return JSON.stringify({ count: matches.length, candidate, eliminatedBy });
      """

  private static let nativeGestureMessageHandlerName = "webkituiNativeGesture"

  private static let armNativeClickSource =
    actionHelpers + """
      const element = matches.length === 1 ? matches[0] : null;
      if (!element) return JSON.stringify({ count: matches.length, candidate: null, eliminatedBy });
      const candidate = describe(element);
      const surface = surfaceOf(element);
      const box = surface.getBoundingClientRect();
      const tolerance = 0.5;
      candidate.geometryStable = ['x', 'y', 'width', 'height'].every(key =>
        Math.abs(box[key] - expectedBox[key]) <= tolerance
      );
      const style = getComputedStyle(surface);
      const visible = box.width > 0 && box.height > 0 && style.visibility !== 'hidden'
        && style.display !== 'none' && Number(style.opacity) !== 0;
      const enabled = !element.matches(':disabled')
        && element.getAttribute('aria-disabled') !== 'true';
      const centerX = Math.min(innerWidth - 1, Math.max(0, box.left + box.width / 2));
      const centerY = Math.min(innerHeight - 1, Math.max(0, box.top + box.height / 2));
      const hit = document.elementFromPoint(centerX, centerY);
      const receivesEvents = Boolean(hit && (
        hit === element || element.contains(hit) || hit === surface || surface.contains(hit)
      ));
      candidate.actionable = visible && enabled && receivesEvents
        && candidate.geometryStable && element.isConnected && surface.isConnected;
      if (candidate.actionable) {
        const physicalIdentity = candidate.physicalIdentity;
        const report = event => {
          globalThis.webkit.messageHandlers.webkituiNativeGesture.postMessage({
            token, physicalIdentity, eventType: event.type, trusted: event.isTrusted
          });
        };
        element.addEventListener('click', report, { capture: true, once: true });
        if (surface !== element) {
          surface.addEventListener('click', report, { capture: true, once: true });
        }
      }
      return JSON.stringify({ count: matches.length, candidate, eliminatedBy });
      """

  private static let armNativeKeySource =
    actionHelpers + """
      const element = matches.length === 1 ? matches[0] : null;
      if (!element) return JSON.stringify({ count: matches.length, candidate: null, eliminatedBy });
      const candidate = describe(element);
      const surface = surfaceOf(element);
      const box = surface.getBoundingClientRect();
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
            token, physicalIdentity, eventType: event.type, trusted: event.isTrusted
          });
        }, { capture: true, once: true });
        if (expectedKey === 'Tab') {
          element.addEventListener('blur', event => {
            globalThis.webkit.messageHandlers.webkituiNativeGesture.postMessage({
              token, physicalIdentity, eventType: event.type, trusted: event.isTrusted
            });
          }, { capture: true, once: true });
        }
      }
      return JSON.stringify({ count: matches.length, candidate, eliminatedBy });
      """

  private static let armNativeFillSource =
    actionHelpers + """
      const element = matches.length === 1 ? matches[0] : null;
      if (!element) return JSON.stringify({ count: matches.length, candidate: null, eliminatedBy });
      const candidate = describe(element);
      const surface = surfaceOf(element);
      const box = surface.getBoundingClientRect();
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
            token, physicalIdentity, eventType: event.type, trusted: event.isTrusted
          });
        }, { capture: true, once: true });
        document.addEventListener('keydown', event => {
          if (event.key !== 'Tab') return;
          globalThis.webkit.messageHandlers.webkituiNativeGesture.postMessage({
            token, physicalIdentity, eventType: 'commit_keydown', trusted: event.isTrusted
          });
        }, { capture: true, once: true });
      }
      return JSON.stringify({ count: matches.length, candidate, eliminatedBy });
      """

  private static func boxDictionary(_ box: ObservedBoundingBox) -> [String: Double] {
    ["x": box.x, "y": box.y, "width": box.width, "height": box.height]
  }

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
      const centerX = Math.min(innerWidth - 1, Math.max(0, box.left + box.width / 2));
      const centerY = Math.min(innerHeight - 1, Math.max(0, box.top + box.height / 2));
      const hit = document.elementFromPoint(centerX, centerY);
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
}

private struct RawCredentialFillResult: Decodable {
  let filled: Bool
}

private struct RawObservation: Decodable {
  let url: String
  let title: String
  let readyState: String
  let mutationCount: UInt64
  let crossOriginFrameCount: Int
  let totalElementCount: Int
  let unfilteredCandidateCount: Int
  let transientLoading: Bool
  let renderedInteractiveCount: Int
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

private struct RawAuthenticationUIState: Decodable {
  let readyState: String
  let hasProgressIndicator: Bool
  let hasVisibleAuthenticationControl: Bool
  let hasInvisibleAuthenticationControl: Bool
  let hasWebAuthnControl: Bool
}

private struct RawElement: Decodable {
  let physicalIdentity: String
  let tag: String
  let role: String?
  let accessibleName: String?
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
  let stateAttributes: [String: String]
  let contextAnchors: [RawContextAnchor]
  let stableAttributes: [String: String]
  let visible: Bool
  let actionability: String
  let boundingBox: ObservedBoundingBox
}

private struct RawContextAnchor: Decodable {
  let kind: String
  let text: String
}

private struct ObservedTargetRecord {
  let recipe: LocatorRecipe
  let physicalIdentity: String
  let boundingBox: ObservedBoundingBox
  let sensitive: Bool
  let disabled: Bool
  let observedAtMonotonicNanoseconds: UInt64
}

private struct RawActionResolution: Decodable {
  let count: Int
  let candidate: RawActionCandidate?
  let eliminatedBy: [String]?
}

private struct RawActionCandidate: Decodable {
  let physicalIdentity: String
  let boundingBox: ObservedBoundingBox
  let geometryStable: Bool
  let actionable: Bool
  let dispatched: Bool
  let trustedUserGesture: Bool
}

private struct NativeGestureReceipt {
  let physicalIdentity: String
  let eventType: String
  let trusted: Bool
}
