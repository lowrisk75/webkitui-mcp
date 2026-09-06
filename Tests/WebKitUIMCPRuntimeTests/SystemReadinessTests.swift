import Darwin
import Foundation
import Testing

@testable import WebKitUIMCPRuntime

struct SystemReadinessTests {
  @Test("Disk preflight fails closed below its required capacity")
  func diskPreflight() throws {
    let url = URL(fileURLWithPath: "/private/tmp")
    #expect(
      throws: WebKitUIStorageReadinessError.insufficientSpace(
        availableBytes: 63, requiredBytes: 64
      )
    ) {
      try WebKitUISystemReadiness.requireRuntimeDiskSpace(
        at: url, minimumBytes: 64, capacity: { _ in 63 })
    }
    try WebKitUISystemReadiness.requireRuntimeDiskSpace(
      at: url, minimumBytes: 64, capacity: { _ in 64 })
  }

  @Test("POSIX, Cocoa, nested, and bridged Keychain disk-full errors are readable")
  func diskFullMapping() {
    let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
    let cocoa = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteOutOfSpace.rawValue)
    let bridged = NSError(domain: "keychain", code: 100_000 + Int(ENOSPC))
    let nested = NSError(
      domain: "outer", code: 1,
      userInfo: [NSUnderlyingErrorKey: posix])
    #expect(WebKitUISystemReadiness.storageDiagnostic(for: posix)?.contains("ENOSPC") == true)
    #expect(WebKitUISystemReadiness.storageDiagnostic(for: cocoa)?.contains("ENOSPC") == true)
    #expect(WebKitUISystemReadiness.storageDiagnostic(for: bridged)?.contains("keychain") == true)
    #expect(WebKitUISystemReadiness.storageDiagnostic(for: nested)?.contains("ENOSPC") == true)
  }
}
