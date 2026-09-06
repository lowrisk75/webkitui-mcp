import Darwin
import Foundation

public enum WebKitUIStorageReadinessError: Error, Equatable, Sendable {
  case insufficientSpace(availableBytes: Int64, requiredBytes: Int64)
  case capacityUnavailable
}

public enum WebKitUISystemReadiness {
  public static let minimumRuntimeFreeBytes: Int64 = 128 * 1_024 * 1_024

  public static func requireRuntimeDiskSpace(
    at url: URL,
    minimumBytes: Int64 = minimumRuntimeFreeBytes,
    capacity: ((URL) throws -> Int64?)? = nil
  ) throws {
    let available: Int64?
    if let capacity {
      available = try capacity(url)
    } else {
      available = try url.resourceValues(
        forKeys: [.volumeAvailableCapacityForImportantUsageKey]
      ).volumeAvailableCapacityForImportantUsage
    }
    guard let available else { throw WebKitUIStorageReadinessError.capacityUnavailable }
    guard available >= minimumBytes else {
      throw WebKitUIStorageReadinessError.insufficientSpace(
        availableBytes: available, requiredBytes: minimumBytes)
    }
  }

  public static func storageDiagnostic(for error: Error) -> String? {
    if case WebKitUIStorageReadinessError.insufficientSpace(let available, let required) = error {
      return
        "disk_full (ENOSPC): available=\(available) required=\(required); free disk space and retry"
    }
    for candidate in flattened(error as NSError) {
      if candidate.domain == NSPOSIXErrorDomain && candidate.code == Int(ENOSPC) {
        return "disk_full (ENOSPC): free disk space and retry"
      }
      if candidate.domain == NSCocoaErrorDomain
        && candidate.code == CocoaError.fileWriteOutOfSpace.rawValue
      {
        return "disk_full (ENOSPC): free disk space and retry"
      }
      // Some Keychain bridges encode a POSIX error as 100000 + errno.
      if candidate.code == 100_000 + Int(ENOSPC) {
        return
          "disk_full (ENOSPC): keychain write failed because the disk is full; free disk space and retry"
      }
    }
    return nil
  }

  private static func flattened(_ error: NSError) -> [NSError] {
    var result = [error]
    if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
      result.append(contentsOf: flattened(underlying))
    }
    if let multiple = error.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError] {
      for nested in multiple { result.append(contentsOf: flattened(nested)) }
    }
    return result
  }
}
