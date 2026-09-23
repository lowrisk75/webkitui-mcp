import AppKit
import CLaunchShim
import Darwin
import Foundation
import WebKit
import WebKitUIMCPLicensing
import WebKitUIMCPRuntime
import WebKitUIMCPServer

private let aquaClientAdmission = BoundedConnectionAdmission(maximum: 16)
private let aquaSocketDeadlines = LocalSocketDeadlinePolicy(
  receiveIdleSeconds: 30 * 60,
  sendSeconds: 30
)

@main
struct WebKitUIMCPAquaBroker {
  @MainActor private static var readSources: [any DispatchSourceRead] = []
  @MainActor private static var companionController: WebKitUICompanionController?

  @MainActor
  static func main() async {
    if CommandLine.arguments.contains("--print-setup-command") {
      do {
        print(
          WebKitUICompanionController.setupCommand(
            executableURL: Bundle.main.executableURL,
            socketPath: try selfHostedSocketPath()
          ))
      } catch {
        diagnostic("setup command unavailable", error: error)
      }
      return
    }
    let application = NSApplication.shared
    WebKitNativeApplicationMenu.install(on: application)
    application.finishLaunching()
    application.setActivationPolicy(.regular)
    if let auditIndex = CommandLine.arguments.firstIndex(of: "--verify-activity-clear-default"),
      CommandLine.arguments.indices.contains(auditIndex + 1)
    {
      do {
        let language = CommandLine.arguments[auditIndex + 1]
        guard ["en", "fr"].contains(language),
          let localizationURL = Bundle.main.url(forResource: language, withExtension: "lproj"),
          let localizationBundle = Bundle(url: localizationURL)
        else {
          throw CocoaError(.fileReadUnsupportedScheme)
        }
        let audit = ActivityLogWindowController.clearConfirmationAudit(
          language: language,
          bundle: localizationBundle)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(audit))
        FileHandle.standardOutput.write(Data([0x0A]))
      } catch {
        diagnostic("activity clear default verification failed", error: error)
        Foundation.exit(EXIT_FAILURE)
      }
      return
    }
    if let auditIndex = CommandLine.arguments.firstIndex(of: "--verify-status-ui-layout"),
      CommandLine.arguments.indices.contains(auditIndex + 1)
    {
      do {
        let language = CommandLine.arguments[auditIndex + 1]
        guard ["en", "fr"].contains(language),
          let localizationURL = Bundle.main.url(forResource: language, withExtension: "lproj"),
          let localizationBundle = Bundle(url: localizationURL)
        else {
          throw CocoaError(.fileReadUnsupportedScheme)
        }
        let controller = WebKitUICompanionController(
          application: application,
          activityLog: nil,
          localizationBundle: localizationBundle,
          automaticallyShowsStatus: false,
          automaticallyRefreshesStatus: false)
        let audit = try controller.auditStatusLayout(language: language)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(audit))
        FileHandle.standardOutput.write(Data([0x0A]))
      } catch {
        diagnostic("status UI layout verification failed", error: error)
        Foundation.exit(EXIT_FAILURE)
      }
      return
    }
    if let renderIndex = CommandLine.arguments.firstIndex(of: "--render-status-ui"),
      CommandLine.arguments.indices.contains(renderIndex + 1)
    {
      do {
        let destination = URL(fileURLWithPath: CommandLine.arguments[renderIndex + 1])
          .standardizedFileURL.resolvingSymlinksInPath()
        let processTemporaryRoot = FileManager.default.temporaryDirectory.standardizedFileURL.path
        let allowedTemporaryRoots = [
          processTemporaryRoot,
          "/private" + processTemporaryRoot,
          "/tmp",
          "/private/tmp",
        ]
        guard allowedTemporaryRoots.contains(where: { destination.path.hasPrefix($0 + "/") }) else {
          throw CocoaError(.fileWriteNoPermission)
        }
        let controller = WebKitUICompanionController(
          application: application,
          activityLog: nil,
          automaticallyShowsStatus: false)
        try controller.renderStatusSnapshot(to: destination)
      } catch {
        diagnostic("status UI rendering failed", error: error)
        Foundation.exit(EXIT_FAILURE)
      }
      return
    }
    if CommandLine.arguments.contains("--visual-smoke-test") {
      do {
        let smokeLogDirectory = FileManager.default.temporaryDirectory.appending(
          path: "WebKitUIMCP-VisualSmoke-\(ProcessInfo.processInfo.processIdentifier)",
          directoryHint: .isDirectory)
        companionController = WebKitUICompanionController(
          application: application,
          activityLog: try WebKitActivityLog(directoryURL: smokeLogDirectory)
        )
        runVisualSmokeTest()
      } catch {
        diagnostic("visual smoke test activity journal unavailable", error: error)
        Foundation.exit(EXIT_FAILURE)
      }
      return
    }
    do {
      let applicationSupport = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true)
      try WebKitUISystemReadiness.requireRuntimeDiskSpace(at: applicationSupport)
      // Several agents may drive their own window at once. The host lease stays
      // exclusive to this process; the CLI keeps one session.
      let registry = try WebKitSessionRegistry(
        maximumSessions: 3,
        enforceHostExclusiveSession: true
      )
      let transactionLedgerFactory = try WebKitTransactionLedgerFactory.durable()
      let activityLog = try WebKitActivityLog.durable()
      let goalDelegationMonitor = GoalDelegationMonitor()
      let sockets = try activatedOrSelfHostedSockets(named: "MCP")
      companionController = WebKitUICompanionController(
        application: application,
        ownedSocket: sockets.ownedSocket,
        activityLog: activityLog,
        goalDelegationMonitor: goalDelegationMonitor
      )
      companionController?.maintenance = WebKitUIMaintenanceActions(
        forceRender: { [weak registry] in
          guard let registry else { return }
          for handle in registry.openSessionHandles() {
            (try? registry.runtime(for: handle))?.forceRender()
          }
        },
        clearBrowsingData: { [weak registry] in
          // Sessions share the profile, so one clear empties it for all of them.
          guard let registry, let handle = registry.openSessionHandles().first,
            let runtime = try? registry.runtime(for: handle)
          else { return }
          Task { @MainActor in await runtime.clearBrowsingData() }
        },
        releaseHostLease: { [weak registry] report in
          // Sessions this host owns first, so a lease held by the host itself goes away.
          if let registry {
            for handle in registry.openSessionHandles() { try? registry.close(handle) }
          }
          // Then whoever actually holds the lock, which is normally a client in its own
          // process and was never reachable from the registry above.
          DispatchQueue.global(qos: .userInitiated).async {
            let outcome = HostLeaseEviction.evict()
            Task { @MainActor in report(outcome) }
          }
        }
      )
      for descriptor in sockets.descriptors {
        try makeNonBlocking(descriptor)
        let source = DispatchSource.makeReadSource(
          fileDescriptor: descriptor, queue: .global(qos: .userInitiated))
        configure(
          source,
          descriptor: descriptor,
          registry: registry,
          transactionLedgerFactory: transactionLedgerFactory,
          activityLog: activityLog,
          goalDelegationMonitor: goalDelegationMonitor
        )
        readSources.append(source)
      }
      application.run()
      sockets.ownedSocket?.removeIfStillOwned()
    } catch {
      diagnostic("aqua broker stopped", error: error)
      Foundation.exit(EXIT_FAILURE)
    }
  }

  @MainActor
  private static func runVisualSmokeTest() {
    Task { @MainActor in
      let runtime = WebKitRuntime(websiteDataStore: .nonPersistent())
      do {
        _ = try await runtime.loadHTML(
          """
          <!doctype html>
          <title>WebkitUIMCP visual smoke test</title>
          <style>
            html, body { margin: 0; width: 100%; height: 100%; background: #17324d; }
            h1 { color: white; font: 48px -apple-system; padding: 64px; }
          </style>
          <h1>WebkitUIMCP visual smoke test</h1>
          """,
          baseURL: URL(string: "https://fixture.invalid/visual-smoke"),
          timeout: .seconds(5),
          quietWindow: .milliseconds(50)
        )
        try runtime.requestHumanHandoff()
        try runtime.beginHumanControl(presentWindow: true)
      } catch {
        diagnostic("visual smoke test failed", error: error)
      }
    }
    NSApplication.shared.run()
  }

  nonisolated private static func activatedOrSelfHostedSockets(
    named name: String
  ) throws -> SocketConfiguration {
    var descriptors: UnsafeMutablePointer<Int32>?
    var count = 0
    let result = webkitui_launch_activate_socket(name, &descriptors, &count)
    if result == 0, let descriptors, count > 0 {
      defer { free(descriptors) }
      return SocketConfiguration(
        descriptors: Array(UnsafeBufferPointer(start: descriptors, count: count)),
        ownedSocket: nil
      )
    }
    if let descriptors { free(descriptors) }

    let path = try selfHostedSocketPath()
    let descriptor = try createSelfHostedListener(at: path)
    return SocketConfiguration(
      descriptors: [descriptor],
      ownedSocket: try SocketOwnership.capture(path: path)
    )
  }

  nonisolated private static func selfHostedSocketPath() throws -> String {
    if let override = ProcessInfo.processInfo.environment["WEBKITUI_MCP_SOCKET_PATH"] {
      guard override.hasPrefix("/") else { throw AquaBrokerError.socketPathMustBeAbsolute }
      let standardized = URL(fileURLWithPath: override).standardizedFileURL
      guard
        standardized.path != "/",
        standardized.deletingLastPathComponent().path != "/",
        !standardized.lastPathComponent.isEmpty
      else {
        throw AquaBrokerError.unsafeSocketDirectory
      }
      return standardized.path
    }
    return defaultSocketDirectory.appending(path: "mcp.sock", directoryHint: .notDirectory).path
  }

  nonisolated private static func createSelfHostedListener(at path: String) throws -> Int32 {
    let directory = URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL
    try secureSocketDirectory(directory)

    try removeStaleSocketIfPresent(at: path)
    let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
    do {
      try withUnixAddress(path) { address, length in
        guard Darwin.bind(descriptor, address, length) == 0 else {
          throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
      }
      guard path.withCString({ Darwin.chmod($0, 0o600) }) == 0 else {
        throw POSIXError(.init(rawValue: errno) ?? .EACCES)
      }
      guard Darwin.listen(descriptor, 16) == 0 else {
        throw POSIXError(.init(rawValue: errno) ?? .EIO)
      }
      return descriptor
    } catch {
      Darwin.close(descriptor)
      _ = path.withCString(Darwin.unlink)
      throw error
    }
  }

  nonisolated private static var defaultSocketDirectory: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appending(
        path: "Library/Application Support/WebkitUIMCP",
        directoryHint: .isDirectory
      )
      .standardizedFileURL
  }

  nonisolated private static func secureSocketDirectory(_ directory: URL) throws {
    let isDefault = directory == defaultSocketDirectory
    if !FileManager.default.fileExists(atPath: directory.path) {
      guard isDefault else { throw AquaBrokerError.unsafeSocketDirectory }
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
    }
    var information = stat()
    guard
      directory.path.withCString({ Darwin.lstat($0, &information) }) == 0,
      information.st_mode & S_IFMT == S_IFDIR,
      information.st_uid == geteuid()
    else {
      throw AquaBrokerError.unsafeSocketDirectory
    }
    if isDefault {
      guard directory.path.withCString({ Darwin.chmod($0, 0o700) }) == 0 else {
        throw POSIXError(.init(rawValue: errno) ?? .EACCES)
      }
    } else if information.st_mode & 0o077 != 0 {
      throw AquaBrokerError.unsafeSocketDirectory
    }
  }

  nonisolated private static func removeStaleSocketIfPresent(at path: String) throws {
    var information = stat()
    let status = path.withCString { Darwin.lstat($0, &information) }
    if status != 0 {
      guard errno == ENOENT else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
      return
    }
    guard information.st_mode & S_IFMT == S_IFSOCK else {
      throw AquaBrokerError.unsafeExistingSocketPath
    }

    let probe = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard probe >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
    defer { Darwin.close(probe) }
    let connection = try withUnixAddress(path) { address, length in
      Darwin.connect(probe, address, length)
    }
    if connection == 0 { throw AquaBrokerError.socketAlreadyActive }
    guard errno == ECONNREFUSED || errno == ENOENT else {
      throw POSIXError(.init(rawValue: errno) ?? .EIO)
    }
    guard path.withCString(Darwin.unlink) == 0 else {
      throw POSIXError(.init(rawValue: errno) ?? .EIO)
    }
  }

  nonisolated private static func withUnixAddress<Result>(
    _ path: String,
    body: (UnsafePointer<sockaddr>, socklen_t) throws -> Result
  ) throws -> Result {
    let bytes = Array(path.utf8CString)
    var address = sockaddr_un()
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard bytes.count <= capacity else { throw AquaBrokerError.socketPathTooLong }
    address.sun_family = sa_family_t(AF_UNIX)
    let length = socklen_t(MemoryLayout<sockaddr_un>.size)
    address.sun_len = UInt8(length)
    withUnsafeMutableBytes(of: &address.sun_path) { destination in
      bytes.withUnsafeBytes { source in destination.copyBytes(from: source) }
    }
    return try withUnsafePointer(to: &address) {
      try $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        try body($0, length)
      }
    }
  }

  nonisolated private static func makeNonBlocking(_ descriptor: Int32) throws {
    let flags = fcntl(descriptor, F_GETFL)
    guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
      throw AquaBrokerError.socketConfigurationFailed
    }
  }

  nonisolated private static func configure(
    _ source: any DispatchSourceRead,
    descriptor: Int32,
    registry: WebKitSessionRegistry,
    transactionLedgerFactory: WebKitTransactionLedgerFactory,
    activityLog: WebKitActivityLog,
    goalDelegationMonitor: GoalDelegationMonitor
  ) {
    source.setEventHandler {
      acceptAvailableConnections(
        from: descriptor,
        registry: registry,
        transactionLedgerFactory: transactionLedgerFactory,
        activityLog: activityLog,
        goalDelegationMonitor: goalDelegationMonitor
      )
    }
    source.setCancelHandler { Darwin.close(descriptor) }
    source.resume()
  }

  nonisolated private static func acceptAvailableConnections(
    from listener: Int32,
    registry: WebKitSessionRegistry,
    transactionLedgerFactory: WebKitTransactionLedgerFactory,
    activityLog: WebKitActivityLog,
    goalDelegationMonitor: GoalDelegationMonitor
  ) {
    while true {
      let client = Darwin.accept(listener, nil, nil)
      if client >= 0 {
        guard aquaClientAdmission.tryAcquire() else {
          diagnostic("aqua broker connection limit reached", error: POSIXError(.EMFILE))
          Darwin.close(client)
          continue
        }
        do {
          try makeBlocking(client)
          try aquaSocketDeadlines.apply(to: client)
        } catch {
          diagnostic("aqua broker client setup failed", error: error)
          Darwin.close(client)
          aquaClientAdmission.release()
          continue
        }
        Task.detached {
          defer { aquaClientAdmission.release() }
          await serve(
            client,
            registry: registry,
            transactionLedgerFactory: transactionLedgerFactory,
            activityLog: activityLog,
            goalDelegationMonitor: goalDelegationMonitor
          )
        }
        continue
      }
      guard errno != EAGAIN && errno != EWOULDBLOCK else { return }
      diagnostic("aqua broker accept failed", error: POSIXError(.init(rawValue: errno)!))
      return
    }
  }

  nonisolated private static func makeBlocking(_ descriptor: Int32) throws {
    let flags = fcntl(descriptor, F_GETFL)
    guard flags >= 0, fcntl(descriptor, F_SETFL, flags & ~O_NONBLOCK) == 0 else {
      throw AquaBrokerError.socketConfigurationFailed
    }
  }

  nonisolated private static func serve(
    _ descriptor: Int32,
    registry: WebKitSessionRegistry,
    transactionLedgerFactory: WebKitTransactionLedgerFactory,
    activityLog: WebKitActivityLog,
    goalDelegationMonitor: GoalDelegationMonitor
  ) async {
    defer { Darwin.close(descriptor) }
    var peerUserID: uid_t = 0
    var peerGroupID: gid_t = 0
    guard
      getpeereid(descriptor, &peerUserID, &peerGroupID) == 0,
      peerUserID == geteuid()
    else {
      return
    }

    let server = await WebKitMCPServer(
      durableRegistry: registry,
      transactionLedgerFactory: transactionLedgerFactory,
      activityLog: activityLog,
      goalDelegationMonitor: goalDelegationMonitor
    )
    var pending = Data()
    var bytes = [UInt8](repeating: 0, count: 16_384)
    connectionLoop: while true {
      let count = bytes.withUnsafeMutableBytes {
        Darwin.read(descriptor, $0.baseAddress, $0.count)
      }
      if count == 0 { break }
      if count < 0 {
        if errno == EINTR { continue }
        diagnostic(
          "aqua broker connection closed",
          error: POSIXError(.init(rawValue: errno) ?? .EIO))
        break
      }
      pending.append(contentsOf: bytes.prefix(count))
      guard pending.count <= 8 * 1_024 * 1_024 else {
        diagnostic("aqua broker frame too large", error: AquaBrokerError.frameTooLarge)
        break
      }
      while let newline = pending.firstIndex(of: 0x0A) {
        var line = pending[..<newline]
        if line.last == 0x0D { line = line.dropLast() }
        pending.removeSubrange(...newline)
        guard !line.isEmpty else { continue }
        guard let response = await server.handle(Data(line)) else { continue }
        do {
          try writeAll(response + Data("\n".utf8), to: descriptor)
        } catch {
          diagnostic("aqua broker response write failed", error: error)
          break connectionLoop
        }
      }
    }
    await server.prepareForClientReconnect()
  }

  nonisolated private static func writeAll(_ data: Data, to descriptor: Int32) throws {
    try data.withUnsafeBytes { rawBuffer in
      var offset = 0
      while offset < rawBuffer.count {
        let written = Darwin.write(
          descriptor, rawBuffer.baseAddress?.advanced(by: offset), rawBuffer.count - offset)
        if written < 0, errno == EINTR { continue }
        guard written > 0 else {
          throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        offset += written
      }
    }
  }

  nonisolated private static func diagnostic(_ message: String, error: Error) {
    if let storage = WebKitUISystemReadiness.storageDiagnostic(for: error) {
      FileHandle.standardError.write(Data("\(message): \(storage)\n".utf8))
      return
    }
    let nsError = error as NSError
    let type = String(describing: Swift.type(of: error))
    FileHandle.standardError.write(
      Data("\(message): \(type) \(nsError.domain)/\(nsError.code)\n".utf8))
  }
}

private enum AquaBrokerError: Error {
  case frameTooLarge
  case socketAlreadyActive
  case socketConfigurationFailed
  case socketPathMustBeAbsolute
  case socketPathTooLong
  case unsafeSocketDirectory
  case unsafeExistingSocketPath
}

private struct SocketConfiguration {
  let descriptors: [Int32]
  let ownedSocket: SocketOwnership?
}

struct SocketOwnership {
  let path: String
  let device: dev_t
  let inode: ino_t

  nonisolated static func capture(path: String) throws -> Self {
    var information = stat()
    guard path.withCString({ Darwin.lstat($0, &information) }) == 0 else {
      throw POSIXError(.init(rawValue: errno) ?? .EIO)
    }
    guard information.st_mode & S_IFMT == S_IFSOCK else {
      throw AquaBrokerError.unsafeExistingSocketPath
    }
    return Self(path: path, device: information.st_dev, inode: information.st_ino)
  }

  nonisolated func removeIfStillOwned() {
    var information = stat()
    guard
      path.withCString({ Darwin.lstat($0, &information) }) == 0,
      information.st_mode & S_IFMT == S_IFSOCK,
      information.st_dev == device,
      information.st_ino == inode
    else { return }
    _ = path.withCString(Darwin.unlink)
  }
}
