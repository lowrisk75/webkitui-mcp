import Darwin
import Foundation

/// A small, thread-safe admission gate for blocking local socket workers.
public final class BoundedConnectionAdmission: @unchecked Sendable {
  private let lock = NSLock()
  private let maximum: Int
  private var active = 0

  public init(maximum: Int) {
    precondition(maximum > 0)
    self.maximum = maximum
  }

  public func tryAcquire() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard active < maximum else { return false }
    active += 1
    return true
  }

  public func release() {
    lock.lock()
    defer { lock.unlock() }
    precondition(active > 0)
    active -= 1
  }

  public func activeCount() -> Int {
    lock.lock()
    defer { lock.unlock() }
    return active
  }
}

/// Kernel-enforced deadlines for local blocking sockets.
public struct LocalSocketDeadlinePolicy: Sendable {
  public let receiveIdleSeconds: Int
  public let sendSeconds: Int

  public init(receiveIdleSeconds: Int, sendSeconds: Int) {
    precondition(receiveIdleSeconds > 0)
    precondition(sendSeconds > 0)
    self.receiveIdleSeconds = receiveIdleSeconds
    self.sendSeconds = sendSeconds
  }

  public func apply(to descriptor: Int32) throws {
    try setTimeout(SO_RCVTIMEO, seconds: receiveIdleSeconds, on: descriptor)
    try setTimeout(SO_SNDTIMEO, seconds: sendSeconds, on: descriptor)
  }

  private func setTimeout(_ option: Int32, seconds: Int, on descriptor: Int32) throws {
    var timeout = timeval(tv_sec: seconds, tv_usec: 0)
    let result = withUnsafePointer(to: &timeout) {
      setsockopt(descriptor, SOL_SOCKET, option, $0, socklen_t(MemoryLayout<timeval>.size))
    }
    guard result == 0 else {
      throw POSIXError(.init(rawValue: errno) ?? .EIO)
    }
  }
}
