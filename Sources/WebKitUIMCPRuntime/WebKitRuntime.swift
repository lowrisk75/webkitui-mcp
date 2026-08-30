import AppKit
import CryptoKit
import Foundation
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
  case sensitiveInputRequiresHuman
  case invalidCredentialOrigin
  case invalidCredentialBinding
  case invalidCredentialSecret
  case humanControlActive
  case authenticationOriginRequiresHuman(String)
  case noPendingCrossOriginNavigation
  case invalidControlTransition
  case nativeGestureReceiptUnavailable
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
}

public enum InteractionControlState: String, Codable, Equatable, Sendable {
  case agentControlled = "agent_controlled"
  case handoffRequested = "handoff_requested"
  case humanControlled = "human_controlled"
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

public struct ObservedBoundingBox: Codable, Equatable, Sendable {
  public let x: Double
  public let y: Double
  public let width: Double
  public let height: Double
}

public struct WebKitObservedElement: Codable, Equatable, Sendable {
  public let elementID: String
  public let tag: ProvenancedText
  public let role: ProvenancedText?
  public let accessibleName: ProvenancedText?
  public let label: ProvenancedText?
  public let text: ProvenancedText?
  public let value: ProvenancedText?
  public let sensitive: Bool
  public let submitsForm: Bool
  public let disabled: Bool
  public let checked: Bool?
  public let selected: Bool?
  public let selectedOption: ProvenancedText?
  public let stateAttributes: [String: ProvenancedText]
  public let visible: Bool
  public let boundingBox: ObservedBoundingBox
  public let locatorRecipe: LocatorRecipe
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
public final class WebKitRuntime: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
  public let webView: WKWebView

  private let instrumentationWorld: WKContentWorld
  private var documentID = UUID().uuidString
  private var observationGeneration: UInt64 = 0
  private var navigationFailure: WebKitRuntimeError?
  private var processTerminated = false
  private var latestObservationID: String?
  private var latestTargets: [String: ObservedTargetRecord] = [:]
  private var addressingCounters = AddressingCounterSnapshot()
  private var controlState: InteractionControlState = .agentControlled
  private var handoffEvents: [HandoffAuditEvent] = []
  private var browserWindow: NSWindow?
  private var topLevelOriginLock: SecurityOrigin?
  private let formAuditKey = SymmetricKey(size: .bits256)
  private var formSubmissionEvents: [FormSubmissionAuditEvent] = []
  private var webContentTerminationEvents: [WebContentTerminationEvent] = []
  private var lastCommittedHTTPURL: URL?
  private var authenticationUIClassification: AuthenticationUIClassification?
  private var restrictedAuthenticationFrameOrigin: String?
  private var pendingCrossOriginNavigationRequest: URLRequest?
  private let egressProxy: PinnedSOCKSProxy?
  private var armedNativeGestureTokens: Set<String> = []
  private var nativeGestureReceipts: [String: NativeGestureReceipt] = [:]

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

  init(websiteDataStore: WKWebsiteDataStore, egressProxy: PinnedSOCKSProxy?) {
    self.egressProxy = egressProxy
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
    contentController.add(
      WeakScriptMessageHandler(target: self),
      contentWorld: world,
      name: Self.nativeGestureMessageHandlerName)
    webView.navigationDelegate = self
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
    let started = DispatchTime.now().uptimeNanoseconds
    webView.loadHTMLString(html, baseURL: baseURL)
    let readiness = try await awaitReadiness(timeout: timeout, quietWindow: quietWindow)
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
    maximumFieldCharacters: Int = 512,
    roles: [String] = [],
    nameContains: String? = nil
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
    guard
      let json = try await webView.callAsyncJavaScript(
        script,
        arguments: [
          "roleFilters": roles.map { $0.lowercased() },
          "nameFilter": nameContains?.lowercased() ?? "",
          "elementOffset": elementOffset,
          "maximumFieldCharacters": maximumFieldCharacters,
        ],
        in: nil,
        contentWorld: instrumentationWorld
      ) as? String,
      let data = json.data(using: .utf8)
    else {
      throw WebKitRuntimeError.malformedInstrumentationResult
    }

    let raw: RawObservation
    do {
      raw = try JSONDecoder().decode(RawObservation.self, from: data)
    } catch {
      throw WebKitRuntimeError.malformedInstrumentationResult
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

    let elements = try raw.elements.enumerated().map { index, element in
      let elementID = "e\(index + 1)"
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
        visible: element.visible,
        boundingBox: element.boundingBox,
        locatorRecipe: try locatorRecipe(
          for: element,
          elementID: elementID,
          observationID: observationID,
          generation: nextGeneration
        )
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
    let resolution = try await resolveTarget(
      criteria: locatorCriteria(recipe), scrollIntoView: true)
    guard resolution.count == 1 else {
      throw WebKitRuntimeError.targetNotUnique(resolution.count)
    }
    return try await performScroll(
      source: Self.nearestScrollStateSource,
      arguments: ["criteria": locatorCriteria(recipe)]
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
    let resolution = try await resolveTarget(
      criteria: locatorCriteria(recipe), scrollIntoView: false)
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

    let criteria = locatorCriteria(target.recipe)
    let first = try await resolveTarget(criteria: criteria, scrollIntoView: true)
    try recordCardinality(first.count, target: target)
    guard let firstCandidate = first.candidate else {
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

    let second: RawActionResolution
    if dispatchMode == .nativeAppKit, operationName == "click" {
      second = try await resolveAndPerformNativeClick(
        criteria: criteria, expectedBoundingBox: firstCandidate.boundingBox)
    } else if dispatchMode == .nativeAppKit, operationName == "press_key", let value {
      second = try await resolveAndPerformNativeKey(
        criteria: criteria, expectedBoundingBox: firstCandidate.boundingBox, key: value)
    } else {
      second = try await resolveAndPerform(
        criteria: criteria,
        expectedBoundingBox: firstCandidate.boundingBox,
        operation: operationName,
        value: value
      )
    }
    try recordCardinality(second.count, target: target)
    guard let candidate = second.candidate else {
      throw WebKitRuntimeError.targetNotUnique(second.count)
    }

    let physicalIdentity: EvidenceComparison =
      candidate.physicalIdentity == target.physicalIdentity ? .same : .different
    let geometry: EvidenceComparison = candidate.geometryStable ? .same : .different
    let actionTime = DispatchTime.now().uptimeNanoseconds
    let attempt = try AddressingAttempt(
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
        && (operationName == "click" || operationName == "press_key")
        ? .nativeAppKit : .javascript,
      actionMonotonicNanoseconds: actionTime
    )
    if controlState == .freshlyReobserved {
      transition(to: .agentControlled, observationID: observationID)
    }
    return result
  }

  public func interactionControlState() -> InteractionControlState { controlState }

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
    nativeGestureReceipts[token] = NativeGestureReceipt(
      physicalIdentity: physicalIdentity, eventType: eventType, trusted: trusted)
  }

  public func authenticationRestrictionStatus() -> AuthenticationRestrictionStatus? {
    guard let origin = restrictedAuthenticationOrigin() else { return nil }
    return AuthenticationRestrictionStatus(
      origin: origin,
      classification: authenticationUIClassification ?? .humanHandoffRequired,
      environment: authenticationEnvironmentSnapshot()
    )
  }

  public func authenticationEnvironmentSnapshot() -> AuthenticationEnvironmentSnapshot {
    AuthenticationEnvironmentSnapshot(
      persistentWebsiteDataStore: webView.configuration.websiteDataStore.isPersistent,
      customUserAgentConfigured: !(webView.customUserAgent?.isEmpty ?? true),
      applicationNameForUserAgentConfigured:
        !(webView.configuration.applicationNameForUserAgent?.isEmpty ?? true),
      pinnedProxyConfigured: egressProxy != nil,
      contentBlockingConfigured: false,
      customProcessPoolConfigured: false
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
    if presentWindow { presentHumanControlWindow() }
    transition(to: .humanControlled, observationID: nil)
  }

  public func requestAgentResume() throws {
    guard controlState == .humanControlled else {
      throw WebKitRuntimeError.invalidControlTransition
    }
    if let origin = restrictedAuthenticationOrigin() {
      throw WebKitRuntimeError.authenticationOriginRequiresHuman(origin)
    }
    if let window = browserWindow {
      window.orderOut(nil)
      window.ignoresMouseEvents = true
      window.collectionBehavior.remove(.moveToActiveSpace)
      window.collectionBehavior.insert(.stationary)
      window.collectionBehavior.insert(.ignoresCycle)
    }
    NSApplication.shared.setActivationPolicy(.accessory)
    topLevelOriginLock = (webView.url ?? lastCommittedHTTPURL).flatMap {
      navigationOrigin(for: $0)
    }
    transition(to: .resumeRequested, observationID: nil)
  }

  private func makeBrowserWindow() -> NSWindow {
    let window = NSWindow(
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

  private func presentHumanControlWindow() {
    let application = NSApplication.shared
    WebKitNativeApplicationMenu.install(on: application)
    application.finishLaunching()
    application.setActivationPolicy(.regular)
    application.applicationIconImage = Self.humanControlApplicationIcon()
    let window = browserWindow ?? makeBrowserWindow()
    if webView.url == nil, lastCommittedHTTPURL == nil, !webView.isLoading {
      webView.loadHTMLString(Self.emptyHandoffDocument, baseURL: nil)
    }
    window.title = "WebkitUIMCP — Human control"
    window.ignoresMouseEvents = false
    window.collectionBehavior.remove(.stationary)
    window.collectionBehavior.remove(.ignoresCycle)
    window.collectionBehavior.insert(.moveToActiveSpace)
    webView.isHidden = false
    webView.alphaValue = 1
    attachWebView(to: window)
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
    application.activate(ignoringOtherApps: true)
    window.makeFirstResponder(webView)
    window.displayIfNeeded()
  }

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
    guard let lockedOrigin = topLevelOriginLock else { return .allow }
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
      return .cancel
    }
    return .allow
  }

  public func webView(
    _ webView: WKWebView,
    didStartProvisionalNavigation navigation: WKNavigation!
  ) {
    resetForNavigation()
  }

  public func webView(
    _ webView: WKWebView,
    didFail navigation: WKNavigation!,
    withError error: any Error
  ) {
    if navigationFailure == nil {
      navigationFailure = Self.sanitizedNavigationFailure(error)
    }
  }

  public func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: any Error
  ) {
    if navigationFailure == nil {
      navigationFailure = Self.sanitizedNavigationFailure(error)
    }
  }

  private func load(
    request: URLRequest,
    timeout: Duration,
    quietWindow: Duration
  ) async throws -> WebKitNavigationResult {
    try validate(quietWindow: quietWindow)
    resetForNavigation()
    let started = DispatchTime.now().uptimeNanoseconds
    webView.load(request)
    let readiness = try await awaitReadiness(timeout: timeout, quietWindow: quietWindow)
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

  private func locatorCriteria(_ recipe: LocatorRecipe) -> [[String: String]] {
    recipe.clauses.map { clause in
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
  }

  private func resolveTarget(
    criteria: [[String: String]],
    scrollIntoView: Bool
  ) async throws -> RawActionResolution {
    try await actionScript(
      source: Self.resolveSource,
      arguments: ["criteria": criteria, "scrollIntoView": scrollIntoView]
    )
  }

  private func resolveAndPerform(
    criteria: [[String: String]],
    expectedBoundingBox: ObservedBoundingBox,
    operation: String,
    value: String?
  ) async throws -> RawActionResolution {
    var arguments: [String: Any] = [
      "criteria": criteria,
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
        "expectedBox": Self.boxDictionary(expectedBoundingBox),
        "token": token,
      ])
    guard armed.count == 1, let candidate = armed.candidate else { return armed }
    guard candidate.geometryStable, candidate.actionable else { return armed }

    try dispatchNativeMouseClick(at: candidate.boundingBox)
    let deadline = ContinuousClock.now + .seconds(1)
    while ContinuousClock.now < deadline {
      if let receipt = nativeGestureReceipts[token],
        receipt.physicalIdentity == candidate.physicalIdentity,
        receipt.eventType == "click"
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
          ))
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
      if let receipt = nativeGestureReceipts[token],
        receipt.physicalIdentity == candidate.physicalIdentity,
        receipt.eventType == expectedReceiptEvent
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
          ))
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw WebKitRuntimeError.nativeGestureReceiptUnavailable
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

  private func recordCardinality(_ count: Int, target: ObservedTargetRecord) throws {
    guard count != 1 else { return }
    let now = DispatchTime.now().uptimeNanoseconds
    let attempt = try AddressingAttempt(
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
    )
    addressingCounters.record(AddressingClassifier.classify(attempt))
    throw WebKitRuntimeError.targetNotUnique(count)
  }

  private func requireAgentControl() throws {
    guard controlState == .agentControlled || controlState == .freshlyReobserved else {
      throw WebKitRuntimeError.humanControlActive
    }
    try requireNonAuthenticationOrigin()
  }

  private func requireObservationControl() throws {
    guard controlState != .handoffRequested, controlState != .humanControlled else {
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
    pendingCrossOriginNavigationRequest = nil
    latestObservationID = nil
    latestTargets.removeAll(keepingCapacity: true)
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
    return restrictedAuthenticationFrameOrigin
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
    guard restrictedAuthenticationOrigin() != nil else {
      authenticationUIClassification = nil
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
      authenticationUIClassification = .humanHandoffRequired
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
    const isRendered = element => {
      const box = element.getBoundingClientRect();
      if (!(box.width > 0 && box.height > 0) || element.getClientRects().length === 0) {
        return false;
      }
      for (let cursor = element; cursor; cursor = cursor.parentElement) {
        if (cursor.hidden || cursor.inert
            || collapse(cursor.getAttribute('aria-hidden')).toLowerCase() === 'true') {
          return false;
        }
        const style = getComputedStyle(cursor);
        if (style.display === 'none' || style.visibility === 'hidden'
            || style.visibility === 'collapse' || Number(style.opacity) === 0) {
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
    const authenticationControls = Array.from(document.querySelectorAll(authenticationSelector));
    const forms = Array.from(document.querySelectorAll('form'));
    const formHasOnlyInvisibleControls = forms.some(form => {
      const controls = Array.from(form.querySelectorAll('input, select, textarea, button'));
      return controls.length > 0 && !controls.some(isRendered);
    });
    return JSON.stringify({
      readyState: document.readyState,
      hasProgressIndicator: Boolean(
        document.querySelector('[role="progressbar"], progress, [aria-busy="true"]')),
      hasVisibleAuthenticationControl: authenticationControls.some(isRendered),
      hasInvisibleAuthenticationControl:
        authenticationControls.some(element => !isRendered(element)) || formHasOnlyInvisibleControls
    });
    """

  private static let observationSource = """
    const collapse = value => String(value ?? '').replace(/\\s+/g, ' ').trim();
    let semanticTextTruncated = false;
    const bounded = value => {
      if (value === null || value === undefined) return null;
      const text = collapse(value);
      if (text.length <= maximumFieldCharacters) return text;
      semanticTextTruncated = true;
      return text.slice(0, maximumFieldCharacters);
    };
    const isRendered = element => {
      const box = element.getBoundingClientRect();
      if (!(box.width > 0 && box.height > 0) || element.getClientRects().length === 0) {
        return false;
      }
      for (let cursor = element; cursor; cursor = cursor.parentElement) {
        if (cursor.hidden || cursor.inert
            || collapse(cursor.getAttribute('aria-hidden')).toLowerCase() === 'true') {
          return false;
        }
        const style = getComputedStyle(cursor);
        if (style.display === 'none' || style.visibility === 'hidden'
            || style.visibility === 'collapse' || Number(style.opacity) === 0) {
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
    const styledControlSurface = element => {
      if (!(element instanceof HTMLInputElement)
          || !['checkbox', 'radio'].includes(element.type)) return null;
      const labels = element.labels ? Array.from(element.labels) : [];
      return labels.find(isRendered) || null;
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
      if (element.localName === 'a' && element.hasAttribute('href')) return 'link';
      if (element.localName === 'button') return 'button';
      if (element.localName === 'select') return 'combobox';
      if (element.localName === 'textarea') return 'textbox';
      if (element.localName === 'summary') return 'button';
      if (element.localName === 'input') {
        const type = collapse(element.type).toLowerCase();
        if (['button', 'submit', 'reset', 'image'].includes(type)) return 'button';
        if (type === 'checkbox') return 'checkbox';
        if (type === 'radio') return 'radio';
        if (type === 'range') return 'slider';
        return 'textbox';
      }
      return null;
    };
    const labelOf = element => {
      if (element.labels && element.labels.length) {
        return collapse(Array.from(element.labels).map(label => label.innerText).join(' ')) || null;
      }
      const labelledBy = collapse(element.getAttribute('aria-labelledby'));
      if (labelledBy) {
        return collapse(labelledBy.split(/\\s+/).map(id => document.getElementById(id)?.innerText).join(' ')) || null;
      }
      return null;
    };
    const nameOf = element => collapse(element.getAttribute('aria-label')) || labelOf(element)
      || collapse(element.getAttribute('alt')) || collapse(element.getAttribute('title'))
      || collapse(element.innerText) || null;
    const selector = [
      'a[href]', 'button', 'input', 'select', 'textarea', 'summary',
      '[role]', '[contenteditable="true"]', '[tabindex]'
    ].join(',');
    const allowedRoles = new Set(Array.isArray(roleFilters) ? roleFilters : []);
    const wantedName = collapse(nameFilter).toLowerCase();
    const matchingElements = Array.from(document.querySelectorAll(selector))
      .filter(element => {
        if (!isRendered(element) && !styledControlSurface(element)) return false;
        const role = collapse(roleOf(element)).toLowerCase();
        if (allowedRoles.size > 0 && !allowedRoles.has(role)) return false;
        const name = collapse(nameOf(element)).toLowerCase();
        return !wantedName || name.includes(wantedName);
      });
    const elements = matchingElements
      .slice(elementOffset, elementOffset + __MAXIMUM_ELEMENTS__)
      .map(element => {
        const surface = isRendered(element) ? element : styledControlSurface(element);
        const box = surface.getBoundingClientRect();
        const rawValue = typeof element.value === 'string' ? element.value : null;
        const autocomplete = collapse(element.getAttribute('autocomplete')).toLowerCase();
        const autocompleteTokens = autocomplete.split(/\\s+/).filter(Boolean);
        const identifierMetadata = [
          element.getAttribute('name'), element.id, element.getAttribute('type'), autocomplete
        ].map(collapse).join(' ');
        const labelMetadata = [element.getAttribute('aria-label'), labelOf(element)]
          .map(collapse).join(' ');
        const sensitive = (element instanceof HTMLInputElement && element.type === 'password')
          || autocompleteTokens.some(token => sensitiveAutocomplete.has(token))
          || sensitiveIdentifierTerm.test(identifierMetadata)
          || sensitiveLabelTerm.test(labelMetadata)
          || (!(element instanceof HTMLSelectElement) && looksOpaque(rawValue));
        const editable = !element.disabled && !element.readOnly;
        let observableValue = null;
        if (!sensitive && editable && element instanceof HTMLSelectElement) {
          observableValue = collapse(
            Array.from(element.selectedOptions).map(option => option.textContent).join(' ')) || null;
        } else if (!sensitive && editable && element instanceof HTMLTextAreaElement) {
          observableValue = rawValue !== null && rawValue.length <= 1024 ? rawValue : null;
        } else if (!sensitive && editable && element instanceof HTMLInputElement
                   && ['text', 'search', 'email', 'tel', 'url', 'number'].includes(element.type)) {
          observableValue = rawValue !== null && rawValue.length <= 1024 ? rawValue : null;
        }
        const selectedLabel = element instanceof HTMLSelectElement
          ? collapse(Array.from(element.selectedOptions).map(option => option.textContent).join(' '))
          : null;
        const checked = (element instanceof HTMLInputElement
          && ['checkbox', 'radio'].includes(element.type))
          ? Boolean(element.checked)
          : (element.hasAttribute('aria-checked')
            ? collapse(element.getAttribute('aria-checked')).toLowerCase() === 'true' : null);
        const selected = element instanceof HTMLOptionElement
          ? Boolean(element.selected)
          : (element.hasAttribute('aria-selected')
            ? collapse(element.getAttribute('aria-selected')).toLowerCase() === 'true' : null);
        const stateAttributes = {};
        for (const name of [
          'aria-checked', 'aria-selected', 'aria-disabled', 'aria-expanded', 'data-state', 'open'
        ]) {
          if (element.hasAttribute(name)) stateAttributes[name] = element.getAttribute(name) ?? '';
        }
        let physicalIdentity = globalThis.__webkituiState.nodeIDs.get(element);
        if (!physicalIdentity) {
          physicalIdentity = `n${globalThis.__webkituiState.nextNodeID++}`;
          globalThis.__webkituiState.nodeIDs.set(element, physicalIdentity);
        }
        return {
          physicalIdentity,
          tag: element.localName,
          role: roleOf(element),
          accessibleName: bounded(nameOf(element)),
          label: bounded(labelOf(element)),
          text: sensitive ? null : bounded(selectedLabel || collapse(element.innerText) || null),
          value: bounded(observableValue),
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
          selectedOption: bounded(selectedLabel || null),
          stateAttributes: Object.fromEntries(
            Object.entries(stateAttributes).map(([key, value]) => [key, bounded(value) ?? ''])),
          visible: true,
          boundingBox: { x: box.x, y: box.y, width: box.width, height: box.height }
        };
      });
    let crossOriginFrameCount = 0;
    for (const frame of document.querySelectorAll('iframe')) {
      try { if (!frame.contentDocument) crossOriginFrameCount += 1; }
      catch { crossOriginFrameCount += 1; }
    }
    return JSON.stringify({
      url: location.href,
      title: document.title,
      readyState: document.readyState,
      mutationCount: globalThis.__webkituiState?.mutationCount ?? 0,
      crossOriginFrameCount,
      totalElementCount: matchingElements.length,
      semanticTextTruncated,
      elements
    });
    """

  private static let actionHelpers = """
    const collapse = value => String(value ?? '').replace(/\\s+/g, ' ').trim();
    const labelOf = element => {
      if (element.labels && element.labels.length) {
        return collapse(Array.from(element.labels).map(label => label.innerText).join(' ')) || null;
      }
      const labelledBy = collapse(element.getAttribute('aria-labelledby'));
      if (labelledBy) {
        return collapse(labelledBy.split(/\\s+/).map(id => document.getElementById(id)?.innerText).join(' ')) || null;
      }
      return null;
    };
    const roleOf = element => {
      const explicit = collapse(element.getAttribute('role'));
      if (explicit) return explicit;
      if (element.localName === 'a' && element.hasAttribute('href')) return 'link';
      if (element.localName === 'button') return 'button';
      if (element.localName === 'select') return 'combobox';
      if (element.localName === 'textarea') return 'textbox';
      if (element.localName === 'summary') return 'button';
      if (element.localName === 'input') {
        const type = collapse(element.type).toLowerCase();
        if (['button', 'submit', 'reset', 'image'].includes(type)) return 'button';
        if (type === 'checkbox') return 'checkbox';
        if (type === 'radio') return 'radio';
        if (type === 'range') return 'slider';
        return 'textbox';
      }
      return null;
    };
    const nameOf = element => collapse(element.getAttribute('aria-label')) || labelOf(element)
      || collapse(element.getAttribute('alt')) || collapse(element.getAttribute('title'))
      || collapse(element.innerText) || null;
    const isRendered = element => {
      const box = element.getBoundingClientRect();
      if (!(box.width > 0 && box.height > 0) || element.getClientRects().length === 0) return false;
      for (let cursor = element; cursor; cursor = cursor.parentElement) {
        const style = getComputedStyle(cursor);
        if (cursor.hidden || cursor.inert || style.display === 'none'
            || style.visibility === 'hidden' || Number(style.opacity) === 0) return false;
      }
      return true;
    };
    const surfaceOf = element => {
      if (isRendered(element)) return element;
      if (element instanceof HTMLInputElement && ['checkbox', 'radio'].includes(element.type)) {
        const labels = element.labels ? Array.from(element.labels) : [];
        return labels.find(isRendered) || element;
      }
      return element;
    };
    const factValue = (element, criterion) => {
      switch (criterion.fact) {
        case 'role': return roleOf(element);
        case 'accessibleName': return nameOf(element);
        case 'label': return labelOf(element);
        case 'text': return collapse(element.innerText) || null;
        case 'stableAttribute': return criterion.argument === 'tag'
          ? element.localName : element.getAttribute(criterion.argument);
        case 'contextAnchor': return collapse(element.closest(criterion.argument)?.innerText) || null;
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
      '[role]', '[contenteditable="true"]', '[tabindex]'
    ].join(',');
    const matches = Array.from(document.querySelectorAll(selector)).filter(element =>
      criteria.every(criterion => matchesCriterion(element, criterion))
    );
    const describe = element => {
      const box = surfaceOf(element).getBoundingClientRect();
      let physicalIdentity = globalThis.__webkituiState.nodeIDs.get(element);
      if (!physicalIdentity) {
        physicalIdentity = `n${globalThis.__webkituiState.nextNodeID++}`;
        globalThis.__webkituiState.nodeIDs.set(element, physicalIdentity);
      }
      return {
        physicalIdentity,
        boundingBox: { x: box.x, y: box.y, width: box.width, height: box.height },
        geometryStable: true,
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
      return JSON.stringify({ count: matches.length, candidate: element ? describe(element) : null });
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
      if (!element) return JSON.stringify({ count: matches.length, candidate: null });
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
      const hit = document.elementFromPoint(centerX, centerY);
      const receivesEvents = Boolean(hit && (
        hit === element || element.contains(hit) || hit === surface || surface.contains(hit)
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
      return JSON.stringify({ count: matches.length, candidate });
      """

  private static let nativeGestureMessageHandlerName = "webkituiNativeGesture"

  private static let armNativeClickSource =
    actionHelpers + """
      const element = matches.length === 1 ? matches[0] : null;
      if (!element) return JSON.stringify({ count: matches.length, candidate: null });
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
      return JSON.stringify({ count: matches.length, candidate });
      """

  private static let armNativeKeySource =
    actionHelpers + """
      const element = matches.length === 1 ? matches[0] : null;
      if (!element) return JSON.stringify({ count: matches.length, candidate: null });
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
      return JSON.stringify({ count: matches.length, candidate });
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
  let semanticTextTruncated: Bool
  let elements: [RawElement]
}

private struct RawAuthenticationUIState: Decodable {
  let readyState: String
  let hasProgressIndicator: Bool
  let hasVisibleAuthenticationControl: Bool
  let hasInvisibleAuthenticationControl: Bool
}

private struct RawElement: Decodable {
  let physicalIdentity: String
  let tag: String
  let role: String?
  let accessibleName: String?
  let label: String?
  let text: String?
  let value: String?
  let sensitive: Bool
  let submitsForm: Bool
  let disabled: Bool
  let checked: Bool?
  let selected: Bool?
  let selectedOption: String?
  let stateAttributes: [String: String]
  let visible: Bool
  let boundingBox: ObservedBoundingBox
}

private struct ObservedTargetRecord {
  let recipe: LocatorRecipe
  let physicalIdentity: String
  let boundingBox: ObservedBoundingBox
  let sensitive: Bool
  let observedAtMonotonicNanoseconds: UInt64
}

private struct RawActionResolution: Decodable {
  let count: Int
  let candidate: RawActionCandidate?
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
