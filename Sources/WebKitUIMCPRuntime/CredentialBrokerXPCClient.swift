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
}

extension CredentialBrokerFilling {
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

private final class DataReplyGate: @unchecked Sendable {
  private let lock = NSLock()
  private var completion: (@Sendable ((Data?, String?)) -> Void)?

  init(completion: @escaping @Sendable ((Data?, String?)) -> Void) {
    self.completion = completion
  }

  func finish(data: Data?, error: String?) {
    let callback = lock.withLock { () -> (@Sendable ((Data?, String?)) -> Void)? in
      defer { completion = nil }
      return completion
    }
    callback?((data, error))
  }
}

private final class CredentialSinkExport: NSObject, CredentialSinkExportedXPCProtocol,
  @unchecked Sendable
{
  private let runtime: WebKitRuntime
  private let expectedBinding: CredentialSinkFormBinding?
  private let expectedRotationBinding: CredentialSinkRotationBinding?

  init(runtime: WebKitRuntime, expectedBinding: CredentialSinkFormBinding) {
    self.runtime = runtime
    self.expectedBinding = expectedBinding
    expectedRotationBinding = nil
  }

  init(runtime: WebKitRuntime, expectedRotationBinding: CredentialSinkRotationBinding) {
    self.runtime = runtime
    expectedBinding = nil
    self.expectedRotationBinding = expectedRotationBinding
  }

  func fillSyntheticCredential(
    _ bindingData: Data,
    username: Data,
    password: Data,
    withReply reply: @escaping @Sendable (String?) -> Void
  ) {
    Task { @MainActor [runtime, expectedBinding] in
      do {
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
        _ = try await runtime.performCredentialFill(
          binding: binding,
          username: usernameBuffer,
          password: passwordBuffer
        )
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
    Task { @MainActor [runtime, expectedRotationBinding] in
      do {
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
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let bindingData = try encoder.encode(binding)

    let sinkExport = CredentialSinkExport(runtime: runtime, expectedBinding: binding)
    let sinkDelegate = CredentialSinkListenerDelegate(
      exportedObject: sinkExport,
      secretProviderRequirement: peerRequirements.secretProvider
    )
    let sinkListener = NSXPCListener.anonymous()
    sinkListener.delegate = sinkDelegate
    sinkListener.resume()
    defer { sinkListener.suspend() }
    let sinkEndpoint = CredentialSinkEndpointBox(sinkListener.endpoint)

    let connection = NSXPCConnection(
      machServiceName: CredentialBrokerXPCConstants.machServiceName,
      options: []
    )
    connection.remoteObjectInterface = NSXPCInterface(with: CredentialBrokerRemoteXPCProtocol.self)
    connection.setCodeSigningRequirement(peerRequirements.controlService)
    connection.resume()
    defer { connection.invalidate() }

    let requestReply = await call(connection: connection) { broker, reply in
      broker.requestSyntheticFill(
        bindingData,
        sinkEndpoint: sinkEndpoint.endpoint,
        withReply: reply
      )
    }
    guard requestReply.1 == nil, let requestData = requestReply.0 else {
      throw CredentialBrokerClientError.unavailable
    }

    let deliveryReply = await call(connection: connection) { broker, reply in
      broker.deliverSyntheticFill(
        requestData,
        liveBindingData: bindingData,
        withReply: reply
      )
    }
    guard deliveryReply.1 == nil, let receiptData = deliveryReply.0 else {
      throw CredentialBrokerClientError.unavailable
    }
    guard
      let receipt = try? JSONDecoder().decode(
        CredentialBrokerWireReceipt.self,
        from: receiptData
      )
    else { throw CredentialBrokerClientError.invalidReply }
    return receipt
  }

  public func rotatePassword(
    binding: CredentialSinkRotationBinding,
    runtime: WebKitRuntime
  ) async throws -> CredentialBrokerWireReceipt {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let bindingData = try encoder.encode(binding)
    let sinkExport = CredentialSinkExport(
      runtime: runtime,
      expectedRotationBinding: binding
    )
    let sinkDelegate = CredentialSinkListenerDelegate(
      exportedObject: sinkExport,
      secretProviderRequirement: peerRequirements.secretProvider
    )
    let sinkListener = NSXPCListener.anonymous()
    sinkListener.delegate = sinkDelegate
    sinkListener.resume()
    defer { sinkListener.suspend() }
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

    let requestReply = await call(connection: connection) { broker, reply in
      broker.requestPasswordRotation(
        bindingData,
        sinkEndpoint: sinkEndpoint.endpoint,
        withReply: reply
      )
    }
    guard requestReply.1 == nil, let requestData = requestReply.0 else {
      throw CredentialBrokerClientError.unavailable
    }
    let deliveryReply = await call(connection: connection) { broker, reply in
      broker.deliverPasswordRotation(
        requestData,
        liveBindingData: bindingData,
        withReply: reply
      )
    }
    guard deliveryReply.1 == nil, let receiptData = deliveryReply.0,
      let receipt = try? JSONDecoder().decode(
        CredentialBrokerWireReceipt.self,
        from: receiptData
      )
    else { throw CredentialBrokerClientError.invalidReply }
    return receipt
  }

  private nonisolated func call(
    connection: NSXPCConnection,
    operation:
      @escaping @Sendable (
        CredentialBrokerRemoteXPCProtocol,
        @escaping @Sendable (Data?, String?) -> Void
      ) -> Void
  ) async -> (Data?, String?) {
    await withCheckedContinuation { (continuation: CheckedContinuation<(Data?, String?), Never>) in
      let gate = DataReplyGate { result in continuation.resume(returning: result) }
      Task {
        try? await Task.sleep(for: .seconds(15))
        gate.finish(data: nil, error: "timeout")
      }
      let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
        gate.finish(data: nil, error: "unavailable")
      }
      guard let broker = proxy as? CredentialBrokerRemoteXPCProtocol else {
        gate.finish(data: nil, error: "unavailable")
        return
      }
      operation(broker) { data, error in
        gate.finish(data: data, error: error)
      }
    }
  }
}
