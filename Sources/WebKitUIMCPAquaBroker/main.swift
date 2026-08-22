import AppKit
import CLaunchShim
import Darwin
import Foundation
import WebKitUIMCPServer

@main
struct WebKitUIMCPAquaBroker {
  @MainActor private static var readSources: [any DispatchSourceRead] = []

  @MainActor
  static func main() async {
    NSApplication.shared.setActivationPolicy(.accessory)
    do {
      for descriptor in try activatedSockets(named: "MCP") {
        try makeNonBlocking(descriptor)
        let source = DispatchSource.makeReadSource(
          fileDescriptor: descriptor, queue: .global(qos: .userInitiated))
        configure(source, descriptor: descriptor)
        readSources.append(source)
      }
      while !Task.isCancelled {
        try await Task.sleep(for: .seconds(3_600))
      }
    } catch {
      diagnostic("aqua broker stopped", error: error)
      Foundation.exit(EXIT_FAILURE)
    }
  }

  nonisolated private static func activatedSockets(named name: String) throws -> [Int32] {
    var descriptors: UnsafeMutablePointer<Int32>?
    var count = 0
    let result = webkitui_launch_activate_socket(name, &descriptors, &count)
    guard result == 0, let descriptors, count > 0 else {
      throw AquaBrokerError.socketActivationFailed(result)
    }
    defer { free(descriptors) }
    return Array(UnsafeBufferPointer(start: descriptors, count: count))
  }

  nonisolated private static func makeNonBlocking(_ descriptor: Int32) throws {
    let flags = fcntl(descriptor, F_GETFL)
    guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
      throw AquaBrokerError.socketConfigurationFailed
    }
  }

  nonisolated private static func configure(
    _ source: any DispatchSourceRead, descriptor: Int32
  ) {
    source.setEventHandler {
      acceptAvailableConnections(from: descriptor)
    }
    source.setCancelHandler { Darwin.close(descriptor) }
    source.resume()
  }

  nonisolated private static func acceptAvailableConnections(from listener: Int32) {
    while true {
      let client = Darwin.accept(listener, nil, nil)
      if client >= 0 {
        do {
          try makeBlocking(client)
        } catch {
          diagnostic("aqua broker client setup failed", error: error)
          Darwin.close(client)
          continue
        }
        Task.detached { await serve(client) }
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

  nonisolated private static func serve(_ descriptor: Int32) async {
    var peerUserID: uid_t = 0
    var peerGroupID: gid_t = 0
    guard
      getpeereid(descriptor, &peerUserID, &peerGroupID) == 0,
      peerUserID == geteuid()
    else {
      Darwin.close(descriptor)
      return
    }

    let connection = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    do {
      let server = try await WebKitMCPServer(
        maximumSessions: 1, enforceHostExclusiveSession: true)
      for try await line in connection.bytes.lines {
        guard let response = await server.handle(Data(line.utf8)) else { continue }
        try connection.write(contentsOf: response)
        try connection.write(contentsOf: Data("\n".utf8))
      }
    } catch {
      diagnostic("aqua broker connection closed", error: error)
    }
    try? connection.close()
  }

  nonisolated private static func diagnostic(_ message: String, error: Error) {
    let nsError = error as NSError
    let type = String(describing: Swift.type(of: error))
    FileHandle.standardError.write(
      Data("\(message): \(type) \(nsError.domain)/\(nsError.code)\n".utf8))
  }
}

private enum AquaBrokerError: Error {
  case socketActivationFailed(Int32)
  case socketConfigurationFailed
}
