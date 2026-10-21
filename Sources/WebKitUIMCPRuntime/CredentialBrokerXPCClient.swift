import Foundation

public enum CredentialBrokerWireStatus: String, Codable, Equatable, Sendable {
  case filled
  case changed
  case credentialNotFound = "credential_not_found"
  case userPresenceUnavailable = "user_presence_unavailable"
  case denied
  case cancelled
  case stale
  case failed
}

public struct CredentialBrokerWireReceipt: Codable, Equatable, Sendable {
  public let status: CredentialBrokerWireStatus

  public init(status: CredentialBrokerWireStatus) {
    self.status = status
  }
}

public enum CredentialBrokerClientError: Error, Equatable, Sendable {
  case unavailable
  case invalidReply
  case transport(stage: CredentialBrokerCallStage, code: CredentialBrokerFailureCode)
}

public enum CredentialBrokerCallStage: String, Codable, Sendable {
  case request, delivery
}

public enum CredentialBrokerFailureCode: String, Codable, Sendable {
  case unavailable, cancelled, stale, rejected
  case timedOut = "timed_out"
  case invalidReply = "invalid_reply"
  case unexpectedFailure = "unexpected_failure"
  case providerFailed = "provider_failed"
}

enum CredentialBrokerTimeoutPolicy {
  static let request: Duration = .seconds(15)
  // The provider's native selection/create UI has a 300-second deadline; allow
  // its reply to arrive, without changing its one-shot grant or authentication.
  static let delivery: Duration = .seconds(330)
}

final class CredentialSinkLifetime: @unchecked Sendable {
  private let lock = NSLock()
  private var active = true
  var isActive: Bool { lock.withLock { active } }
  func invalidate() { lock.withLock { active = false } }
}

@MainActor
public protocol CredentialBrokerFilling: Sendable {
  func fill(
    binding: CredentialSinkFormBinding,
    runtime: WebKitRuntime
  ) async throws -> CredentialBrokerWireReceipt

  func rotatePassword(
    binding: CredentialSinkRotationBinding,
    runtime: WebKitRuntime
  ) async throws -> CredentialBrokerWireReceipt

  /// A fill the person asked for from the human control bar. Same broker round trip
  /// and binding format; the values land through the human sink.
  func fillForHuman(
    binding: CredentialSinkFormBinding,
    runtime: WebKitRuntime
  ) async throws -> CredentialBrokerWireReceipt
}

extension CredentialBrokerFilling {
  public func fillForHuman(
    binding: CredentialSinkFormBinding,
    runtime: WebKitRuntime
  ) async throws -> CredentialBrokerWireReceipt {
    _ = binding
    _ = runtime
    throw CredentialBrokerClientError.unavailable
  }

  public func rotatePassword(
    binding: CredentialSinkRotationBinding,
    runtime: WebKitRuntime
  ) async throws -> CredentialBrokerWireReceipt {
    _ = binding
    _ = runtime
    throw CredentialBrokerClientError.unavailable
  }
}

private enum CredentialBrokerXPCConstants {
  static let machServiceName = "com.lorislab.siliconpass.credential-broker"
  static let teamIdentifier = "TDV6D5L785"

  static func requirement(bundleIdentifier: String) -> String {
    "anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\" and identifier \"\(bundleIdentifier)\" and entitlement[\"com.apple.security.get-task-allow\"] absent"
  }
}

struct CredentialBrokerXPCPeerRequirements: Equatable, Sendable {
  let controlService: String
  let secretProvider: String

  init(
    brokerBundleIdentifier: String = "com.lorislab.siliconpass.credential-broker-service",
    secretProviderBundleIdentifier: String = "com.lorislab.siliconpass"
  ) {
    controlService = CredentialBrokerXPCConstants.requirement(
      bundleIdentifier: brokerBundleIdentifier
    )
    secretProvider = CredentialBrokerXPCConstants.requirement(
      bundleIdentifier: secretProviderBundleIdentifier
    )
  }
}

@objc(SPCredentialBrokerXPCProtocol)
private protocol CredentialBrokerRemoteXPCProtocol {
  func requestSyntheticFill(
    _ bindingData: Data,
    sinkEndpoint: NSXPCListenerEndpoint,
    withReply reply: @escaping @Sendable (Data?, String?) -> Void
  )

  func deliverSyntheticFill(
    _ requestData: Data,
    liveBindingData: Data,
    withReply reply: @escaping @Sendable (Data?, String?) -> Void
  )

  func requestPasswordRotation(
    _ bindingData: Data,
    sinkEndpoint: NSXPCListenerEndpoint,
    withReply reply: @escaping @Sendable (Data?, String?) -> Void
  )

  func deliverPasswordRotation(
    _ requestData: Data,
    liveBindingData: Data,
    withReply reply: @escaping @Sendable (Data?, String?) -> Void
  )

  func invalidateAll(withReply reply: @escaping @Sendable () -> Void)
}

@objc(SPWebKitCredentialSinkXPCProtocol)
private protocol CredentialSinkExportedXPCProtocol {
  func fillSyntheticCredential(
    _ bindingData: Data,
    username: Data,
    password: Data,
    withReply reply: @escaping @Sendable (String?) -> Void
  )

  func fillPasswordRotation(
    _ bindingData: Data,
    currentPassword: Data,
    newPassword: Data,
    withReply reply: @escaping @Sendable (String?) -> Void
  )
}

final class DataReplyGate: @unchecked Sendable {
  private let lock = NSLock()
  private var completed = false
  private var result: (Data?, String?) = (nil, nil)
  private var timeoutTask: Task<Void, Never>?
  private var completion: (@Sendable ((Data?, String?)) -> Void)?

  func finish(data: Data?, error: String?) {
    let callback = lock.withLock { () -> (@Sendable ((Data?, String?)) -> Void)? in
      guard !completed else { return nil }
      completed = true
      result = (data, error)
      timeoutTask?.cancel()
      timeoutTask = nil
      defer { completion = nil }
      return completion
    }
    callback?((data, error))
  }

  func wait(
    timeout: Duration,
    start: (@escaping @Sendable (Data?, String?) -> Void) -> Void
  ) async -> (Data?, String?) {
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        let immediate = lock.withLock { () -> (Data?, String?)? in
          if completed { return result }
          completion = { continuation.resume(returning: $0) }
          return nil
        }
        if let immediate {
          continuation.resume(returning: immediate)
          return
        }
        let timer = Task { [weak self] in
          do { try await Task.sleep(for: timeout) } catch { return }
          self?.finish(data: nil, error: "timeout")
        }
        lock.withLock {
          if completed { timer.cancel() } else { timeoutTask = timer }
        }
        guard lock.withLock({ !completed }) else { return }
        start { [weak self] data, error in self?.finish(data: data, error: error) }
      }
    } onCancel: {
      self.finish(data: nil, error: "cancelled")
    }
  }
}

final class CredentialSinkExport: NSObject, CredentialSinkExportedXPCProtocol,
  @unchecked Sendable
{
  private let runtime: WebKitRuntime
  private let expectedBinding: CredentialSinkFormBinding?
  private let expectedRotationBinding: CredentialSinkRotationBinding?
  private let humanRequested: Bool
  private let lifetime: CredentialSinkLifetime

  init(
    runtime: WebKitRuntime, expectedBinding: CredentialSinkFormBinding,
    humanRequested: Bool = false, lifetime: CredentialSinkLifetime = CredentialSinkLifetime()
  ) {
    self.runtime = runtime
    self.expectedBinding = expectedBinding
    expectedRotationBinding = nil
    self.humanRequested = humanRequested
    self.lifetime = lifetime
  }

  init(
    runtime: WebKitRuntime, expectedRotationBinding: CredentialSinkRotationBinding,
    lifetime: CredentialSinkLifetime = CredentialSinkLifetime()
  ) {
    self.runtime = runtime
    expectedBinding = nil
    self.expectedRotationBinding = expectedRotationBinding
    humanRequested = false
    self.lifetime = lifetime
  }

  func fillSyntheticCredential(
    _ bindingData: Data,
    username: Data,
    password: Data,
    withReply reply: @escaping @Sendable (String?) -> Void
  ) {
    Task { @MainActor [runtime, expectedBinding, humanRequested, lifetime] in
      do {
        guard lifetime.isActive else {
          reply("stale")
          return
        }
        let binding = try JSONDecoder().decode(CredentialSinkFormBinding.self, from: bindingData)
        guard let expectedBinding, binding == expectedBinding else {
          reply("stale")
          return
        }
        var usernameCopy = username
        var passwordCopy = password
        defer {
          usernameCopy.resetBytes(in: usernameCopy.indices)
          passwordCopy.resetBytes(in: passwordCopy.indices)
        }
        let usernameBuffer = CredentialSecretBuffer(copying: usernameCopy)
        let passwordBuffer = CredentialSecretBuffer(copying: passwordCopy)
        if humanRequested {
          _ = try await runtime.performHumanCredentialFill(
            binding: binding, username: usernameBuffer, password: passwordBuffer)
        } else {
          _ = try await runtime.performCredentialFill(
            binding: binding,
            username: usernameBuffer,
            password: passwordBuffer
          )
        }
        reply(nil)
      } catch {
        reply("stale")
      }
    }
  }

  func fillPasswordRotation(
    _ bindingData: Data,
    currentPassword: Data,
    newPassword: Data,
    withReply reply: @escaping @Sendable (String?) -> Void
  ) {
    Task { @MainActor [runtime, expectedRotationBinding, lifetime] in
      do {
        guard lifetime.isActive else {
          reply("stale")
          return
        }
        let binding = try JSONDecoder().decode(
          CredentialSinkRotationBinding.self,
          from: bindingData
        )
        guard let expectedRotationBinding, binding == expectedRotationBinding else {
          reply("stale")
          return
        }
        var currentCopy = currentPassword
        var newCopy = newPassword
        defer {
          currentCopy.resetBytes(in: currentCopy.indices)
          newCopy.resetBytes(in: newCopy.indices)
        }
        _ = try await runtime.performCredentialRotationFill(
          binding: binding,
          currentPassword: CredentialSecretBuffer(copying: currentCopy),
          newPassword: CredentialSecretBuffer(copying: newCopy)
        )
        reply(nil)
      } catch {
        reply("stale")
      }
    }
  }
}

private final class CredentialSinkListenerDelegate: NSObject, NSXPCListenerDelegate,
  @unchecked Sendable
{
  private let exportedObject: CredentialSinkExport
  private let secretProviderRequirement: String

  init(exportedObject: CredentialSinkExport, secretProviderRequirement: String) {
    self.exportedObject = exportedObject
    self.secretProviderRequirement = secretProviderRequirement
  }

  func listener(
    _ listener: NSXPCListener,
    shouldAcceptNewConnection connection: NSXPCConnection
  ) -> Bool {
    connection.setCodeSigningRequirement(secretProviderRequirement)
    connection.exportedInterface = NSXPCInterface(with: CredentialSinkExportedXPCProtocol.self)
    connection.exportedObject = exportedObject
    connection.resume()
    return true
  }
}

private final class CredentialSinkEndpointBox: @unchecked Sendable {
  let endpoint: NSXPCListenerEndpoint

  init(_ endpoint: NSXPCListenerEndpoint) {
    self.endpoint = endpoint
  }
}

/// Concrete MCP-side shim. It transports only a binding and opaque broker
/// request on the control connection. Synthetic bytes travel solely on the
/// broker-initiated, mutually authenticated callback connection.
@MainActor
public final class SyntheticCredentialBrokerXPCClient: CredentialBrokerFilling {
  private let peerRequirements: CredentialBrokerXPCPeerRequirements

  public init(
    brokerBundleIdentifier: String = "com.lorislab.siliconpass.credential-broker-service",
    secretProviderBundleIdentifier: String = "com.lorislab.siliconpass"
  ) {
    peerRequirements = CredentialBrokerXPCPeerRequirements(
      brokerBundleIdentifier: brokerBundleIdentifier,
      secretProviderBundleIdentifier: secretProviderBundleIdentifier
    )
  }

  public func fill(
    binding: CredentialSinkFormBinding,
    runtime: WebKitRuntime
  ) async throws -> CredentialBrokerWireReceipt {
    try await fill(binding: binding, runtime: runtime, humanRequested: false)
  }

  public func fillForHuman(
    binding: CredentialSinkFormBinding,
    runtime: WebKitRuntime
  ) async throws -> CredentialBrokerWireReceipt {
    try await fill(binding: binding, runtime: runtime, humanRequested: true)
  }

  private func fill(
    binding: CredentialSinkFormBinding,
    runtime: WebKitRuntime,
    humanRequested: Bool
  ) async throws -> CredentialBrokerWireReceipt {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let bindingData = try encoder.encode(binding)

    let lifetime = CredentialSinkLifetime()
    let sinkExport = CredentialSinkExport(
      runtime: runtime, expectedBinding: binding, humanRequested: humanRequested, lifetime: lifetime
    )
    let sinkDelegate = CredentialSinkListenerDelegate(
      exportedObject: sinkExport,
      secretProviderRequirement: peerRequirements.secretProvider
    )
    let sinkListener = NSXPCListener.anonymous()
    sinkListener.delegate = sinkDelegate
    sinkListener.resume()
    defer {
      lifetime.invalidate()
      sinkListener.invalidate()
    }
    let sinkEndpoint = CredentialSinkEndpointBox(sinkListener.endpoint)

    let connection = NSXPCConnection(
      machServiceName: CredentialBrokerXPCConstants.machServiceName,
      options: []
    )
    connection.remoteObjectInterface = NSXPCInterface(with: CredentialBrokerRemoteXPCProtocol.self)
    connection.setCodeSigningRequirement(peerRequirements.controlService)
    connection.resume()
    defer { connection.invalidate() }

    let requestReply = await call(
      connection: connection, timeout: CredentialBrokerTimeoutPolicy.request
    ) { broker, reply in
      broker.requestSyntheticFill(
        bindingData,
        sinkEndpoint: sinkEndpoint.endpoint,
        withReply: reply
      )
    }
    guard requestReply.1 == nil, let requestData = requestReply.0 else {
      throw Self.failure(requestReply.1, stage: .request)
    }

    let deliveryReply = await call(
      connection: connection, timeout: CredentialBrokerTimeoutPolicy.delivery
    ) { broker, reply in
      broker.deliverSyntheticFill(
        requestData,
        liveBindingData: bindingData,
        withReply: reply
      )
    }
    guard deliveryReply.1 == nil, let receiptData = deliveryReply.0 else {
      throw Self.failure(deliveryReply.1, stage: .delivery)
    }
    guard
      let receipt = try? JSONDecoder().decode(
        CredentialBrokerWireReceipt.self,
        from: receiptData
      )
    else { throw CredentialBrokerClientError.transport(stage: .delivery, code: .invalidReply) }
    return receipt
  }

  public func rotatePassword(
    binding: CredentialSinkRotationBinding,
    runtime: WebKitRuntime
  ) async throws -> CredentialBrokerWireReceipt {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let bindingData = try encoder.encode(binding)
    let lifetime = CredentialSinkLifetime()
    let sinkExport = CredentialSinkExport(
      runtime: runtime,
      expectedRotationBinding: binding, lifetime: lifetime
    )
    let sinkDelegate = CredentialSinkListenerDelegate(
      exportedObject: sinkExport,
      secretProviderRequirement: peerRequirements.secretProvider
    )
    let sinkListener = NSXPCListener.anonymous()
    sinkListener.delegate = sinkDelegate
    sinkListener.resume()
    defer {
      lifetime.invalidate()
      sinkListener.invalidate()
    }
    let sinkEndpoint = CredentialSinkEndpointBox(sinkListener.endpoint)

    let connection = NSXPCConnection(
      machServiceName: CredentialBrokerXPCConstants.machServiceName,
      options: []
    )
    connection.remoteObjectInterface = NSXPCInterface(
      with: CredentialBrokerRemoteXPCProtocol.self
    )
    connection.setCodeSigningRequirement(peerRequirements.controlService)
    connection.resume()
    defer { connection.invalidate() }

    let requestReply = await call(
      connection: connection, timeout: CredentialBrokerTimeoutPolicy.request
    ) { broker, reply in
      broker.requestPasswordRotation(
        bindingData,
        sinkEndpoint: sinkEndpoint.endpoint,
        withReply: reply
      )
    }
    guard requestReply.1 == nil, let requestData = requestReply.0 else {
      throw Self.failure(requestReply.1, stage: .request)
    }
    let deliveryReply = await call(
      connection: connection, timeout: CredentialBrokerTimeoutPolicy.delivery
    ) { broker, reply in
      broker.deliverPasswordRotation(
        requestData,
        liveBindingData: bindingData,
        withReply: reply
      )
    }
    guard deliveryReply.1 == nil, let receiptData = deliveryReply.0 else {
      throw Self.failure(deliveryReply.1, stage: .delivery)
    }
    guard
      let receipt = try? JSONDecoder().decode(
        CredentialBrokerWireReceipt.self,
        from: receiptData
      )
    else { throw CredentialBrokerClientError.transport(stage: .delivery, code: .invalidReply) }
    return receipt
  }

  private nonisolated func call(
    connection: NSXPCConnection,
    timeout: Duration,
    operation:
      @escaping @Sendable (
        CredentialBrokerRemoteXPCProtocol,
        @escaping @Sendable (Data?, String?) -> Void
      ) -> Void
  ) async -> (Data?, String?) {
    let gate = DataReplyGate()
    connection.interruptionHandler = { gate.finish(data: nil, error: "unavailable") }
    connection.invalidationHandler = { gate.finish(data: nil, error: "unavailable") }
    return await gate.wait(timeout: timeout) { reply in
      let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
        gate.finish(data: nil, error: "unavailable")
      }
      guard let broker = proxy as? CredentialBrokerRemoteXPCProtocol else {
        gate.finish(data: nil, error: "unavailable")
        return
      }
      operation(broker, reply)
    }
  }

  private nonisolated static func failure(
    _ wireError: String?, stage: CredentialBrokerCallStage
  ) -> CredentialBrokerClientError {
    let code: CredentialBrokerFailureCode
    switch wireError {
    case "timeout": code = .timedOut
    case "unavailable": code = .unavailable
    case "cancelled": code = .cancelled
    case "stale": code = .stale
    case nil: code = .invalidReply
    default: code = .rejected
    }
    return .transport(stage: stage, code: code)
  }
}
