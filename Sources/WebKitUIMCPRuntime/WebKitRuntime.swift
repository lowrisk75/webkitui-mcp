import AppKit
import CryptoKit
import Foundation
import WebKit
import WebKitUIMCPCore

public enum WebKitRuntimeError: Error, Equatable, Sendable {
  case unsupportedURLScheme
  case navigationFailed(String)
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
  case humanControlActive
  case invalidControlTransition
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

public enum WebKitActionOperation: Sendable {
  case click
  case fill(ProvenancedText)
}

public struct WebKitActionResult: Codable, Equatable, Sendable {
  public let elementID: String
  public let addressingOutcome: AddressingOutcome
  public let dispatched: Bool
  public let trustedUserGesture: Bool
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

@MainActor
public final class WebKitRuntime: NSObject, WKNavigationDelegate {
  public let webView: WKWebView

  private let instrumentationWorld: WKContentWorld
  private var documentID = UUID().uuidString
  private var observationGeneration: UInt64 = 0
  private var navigationFailure: String?
  private var processTerminated = false
  private var latestObservationID: String?
  private var latestTargets: [String: ObservedTargetRecord] = [:]
  private var addressingCounters = AddressingCounterSnapshot()
  private var controlState: InteractionControlState = .agentControlled
  private var handoffEvents: [HandoffAuditEvent] = []
  private var humanControlWindow: NSWindow?
  private var topLevelOriginLock: SecurityOrigin?
  private let formAuditKey = SymmetricKey(size: .bits256)
  private var formSubmissionEvents: [FormSubmissionAuditEvent] = []
  private var webContentTerminationEvents: [WebContentTerminationEvent] = []
  private var lastCommittedHTTPURL: URL?
  private let egressProxy: PinnedSOCKSProxy?

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
    webView.navigationDelegate = self
  }

  public func navigate(
    to url: URL,
    timeout: Duration = .seconds(30),
    quietWindow: Duration = .milliseconds(300),
    constrainToInitialOrigin: Bool = false
  ) async throws -> WebKitNavigationResult {
    try requireAgentControl()
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
    return WebKitNavigationResult(
      documentID: documentID,
      url: webView.url?.absoluteString ?? baseURL?.absoluteString ?? "about:blank",
      readiness: readiness,
      elapsedNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
      mutationCount: state.mutationCount
    )
  }

  public func observe(maximumElements: Int = 500) async throws -> WebKitPageObservation {
    guard controlState != .handoffRequested, controlState != .humanControlled else {
      throw WebKitRuntimeError.humanControlActive
    }
    guard maximumElements > 0 else { throw WebKitRuntimeError.malformedInstrumentationResult }
    guard !processTerminated else { throw WebKitRuntimeError.webContentProcessTerminated }

    let script = Self.observationSource.replacingOccurrences(
      of: "__MAXIMUM_ELEMENTS__",
      with: String(maximumElements)
    )
    guard
      let json = try await webView.callAsyncJavaScript(
        script,
        arguments: [:],
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
      crossOriginFramesOpaque: raw.crossOriginFrameCount > 0,
      capturedAtMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds
    )
    rememberRecoverableURL(URL(string: raw.url) ?? webView.url)
    if controlState == .resumeRequested {
      transition(to: .freshlyReobserved, observationID: observationID)
    }
    return observation
  }

  public func capture() async throws -> WebKitCapture {
    try requireAgentControl()
    guard !processTerminated else { throw WebKitRuntimeError.webContentProcessTerminated }
    let image = try await webView.takeSnapshot(configuration: nil)
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
    }

    let second = try await resolveAndPerform(
      criteria: criteria,
      expectedBoundingBox: firstCandidate.boundingBox,
      operation: operationName,
      value: value
    )
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
      actionMonotonicNanoseconds: actionTime
    )
    if controlState == .freshlyReobserved {
      transition(to: .agentControlled, observationID: observationID)
    }
    return result
  }

  public func interactionControlState() -> InteractionControlState { controlState }

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
    if presentWindow {
      let window =
        humanControlWindow
        ?? NSWindow(
          contentRect: .init(x: 0, y: 0, width: 1280, height: 800),
          styleMask: [.titled, .closable, .miniaturizable, .resizable],
          backing: .buffered,
          defer: false
        )
      window.title = "WebkitUIMCP — Human control"
      window.contentView = webView
      window.center()
      window.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
      humanControlWindow = window
    }
    transition(to: .humanControlled, observationID: nil)
  }

  public func requestAgentResume() throws {
    guard controlState == .humanControlled else {
      throw WebKitRuntimeError.invalidControlTransition
    }
    humanControlWindow?.orderOut(nil)
    topLevelOriginLock = (webView.url ?? lastCommittedHTTPURL).flatMap {
      navigationOrigin(for: $0)
    }
    transition(to: .resumeRequested, observationID: nil)
  }

  /// The returned observation is the only address space valid after handoff.
  public func resumeAfterHumanControl(maximumElements: Int = 500) async throws
    -> WebKitPageObservation
  {
    guard controlState == .resumeRequested else {
      throw WebKitRuntimeError.invalidControlTransition
    }
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
    guard let lockedOrigin = topLevelOriginLock else { return .allow }
    guard navigationAction.targetFrame?.isMainFrame == true else {
      return navigationAction.targetFrame == nil ? .cancel : .allow
    }
    guard
      let targetURL = navigationAction.request.url,
      navigationOrigin(for: targetURL) == lockedOrigin
    else {
      navigationFailure = "top-level navigation escaped the approved origin"
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
    navigationFailure = String(describing: error)
  }

  public func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: any Error
  ) {
    navigationFailure = String(describing: error)
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
    rememberRecoverableURL(webView.url ?? request.url)
    processTerminated = false
    return WebKitNavigationResult(
      documentID: documentID,
      url: webView.url?.absoluteString ?? request.url?.absoluteString ?? "about:blank",
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
      if let navigationFailure { throw WebKitRuntimeError.navigationFailed(navigationFailure) }

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
    if let text = element.text, !text.isEmpty {
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

  private static let observationSource = """
    const collapse = value => String(value ?? '').replace(/\\s+/g, ' ').trim();
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
    const elements = Array.from(document.querySelectorAll(selector))
      .slice(0, __MAXIMUM_ELEMENTS__)
      .map(element => {
        const box = element.getBoundingClientRect();
        const style = getComputedStyle(element);
        let physicalIdentity = globalThis.__webkituiState.nodeIDs.get(element);
        if (!physicalIdentity) {
          physicalIdentity = `n${globalThis.__webkituiState.nextNodeID++}`;
          globalThis.__webkituiState.nodeIDs.set(element, physicalIdentity);
        }
        return {
          physicalIdentity,
          tag: element.localName,
          role: roleOf(element),
          accessibleName: nameOf(element),
          label: labelOf(element),
          text: collapse(element.innerText) || null,
          value: element.localName === 'input' && element.type === 'password'
            ? null : (typeof element.value === 'string' ? element.value : null),
          sensitive: element instanceof HTMLInputElement && element.type === 'password',
          submitsForm: Boolean(
            (element instanceof HTMLButtonElement
              && (element.type || 'submit').toLowerCase() === 'submit' && element.form)
            || (element instanceof HTMLInputElement
              && ['submit', 'image'].includes(element.type) && element.form)
          ),
          disabled: Boolean(element.disabled || element.getAttribute('aria-disabled') === 'true'),
          visible: box.width > 0 && box.height > 0 && style.visibility !== 'hidden'
            && style.display !== 'none' && Number(style.opacity) !== 0,
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
      const box = element.getBoundingClientRect();
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
      if (element && scrollIntoView) element.scrollIntoView({ block: 'center', inline: 'center' });
      return JSON.stringify({ count: matches.length, candidate: element ? describe(element) : null });
      """

  private static let performSource =
    actionHelpers + """
      const element = matches.length === 1 ? matches[0] : null;
      if (!element) return JSON.stringify({ count: matches.length, candidate: null });
      const candidate = describe(element);
      const box = element.getBoundingClientRect();
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
      const receivesEvents = Boolean(hit && (hit === element || element.contains(hit)));
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
        element.click();
        candidate.trustedUserGesture = trusted;
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
}

private struct RawInstrumentationState: Decodable {
  let mutationCount: UInt64
  let readyState: String
}

private struct RawObservation: Decodable {
  let url: String
  let title: String
  let readyState: String
  let mutationCount: UInt64
  let crossOriginFrameCount: Int
  let elements: [RawElement]
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
