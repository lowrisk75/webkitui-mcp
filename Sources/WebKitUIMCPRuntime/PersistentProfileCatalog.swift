import Darwin
import Foundation

public enum PersistentProfileCatalogError: Error, Equatable, Sendable {
  case storageUnavailable
  case corruptCatalog
  case insecurePermissions
  case unknownProfile
}

/// Stores opaque WebKit data-store identifiers only. Website data, cookies,
/// credentials, domains, and browsing history remain exclusively in WebKit.
public final class PersistentProfileCatalog {
  private struct Document: Codable {
    let version: Int
    var profileIDs: Set<UUID>
  }

  private let directoryURL: URL
  private let catalogURL: URL
  private let lockURL: URL

  public convenience init() throws {
    guard
      let applicationSupport = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first
    else { throw PersistentProfileCatalogError.storageUnavailable }
    try self.init(
      directoryURL: applicationSupport.appendingPathComponent(
        "com.lorislab.webkitui-mcp", isDirectory: true))
  }

  public init(directoryURL: URL) throws {
    self.directoryURL = directoryURL
    self.catalogURL = directoryURL.appendingPathComponent("persistent-profiles.json")
    self.lockURL = directoryURL.appendingPathComponent("persistent-profiles.lock")
    try prepareDirectory()
  }

  public func create() throws -> UUID {
    try withExclusiveLock {
      var document = try loadLocked()
      let identifier = UUID()
      document.profileIDs.insert(identifier)
      try saveLocked(document)
      return identifier
    }
  }

  public func contains(_ identifier: UUID) throws -> Bool {
    try withExclusiveLock { try loadLocked().profileIDs.contains(identifier) }
  }

  public func remove(_ identifier: UUID) throws {
    try withExclusiveLock {
      var document = try loadLocked()
      guard document.profileIDs.remove(identifier) != nil else {
        throw PersistentProfileCatalogError.unknownProfile
      }
      try saveLocked(document)
    }
  }

  private func prepareDirectory() throws {
    do {
      try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
    } catch {
      throw PersistentProfileCatalogError.storageUnavailable
    }
    var status = stat()
    guard
      lstat(directoryURL.path, &status) == 0,
      (status.st_mode & S_IFMT) == S_IFDIR,
      status.st_uid == geteuid()
    else { throw PersistentProfileCatalogError.insecurePermissions }
    guard chmod(directoryURL.path, S_IRWXU) == 0 else {
      throw PersistentProfileCatalogError.storageUnavailable
    }
  }

  private func withExclusiveLock<T>(_ body: () throws -> T) throws -> T {
    let descriptor = Darwin.open(
      lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw PersistentProfileCatalogError.storageUnavailable }
    defer { Darwin.close(descriptor) }
    guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0, flock(descriptor, LOCK_EX) == 0 else {
      throw PersistentProfileCatalogError.storageUnavailable
    }
    defer { flock(descriptor, LOCK_UN) }
    return try body()
  }

  private func loadLocked() throws -> Document {
    guard FileManager.default.fileExists(atPath: catalogURL.path) else {
      return Document(version: 1, profileIDs: [])
    }
    var status = stat()
    guard lstat(catalogURL.path, &status) == 0 else {
      throw PersistentProfileCatalogError.storageUnavailable
    }
    guard
      (status.st_mode & S_IFMT) == S_IFREG,
      status.st_uid == geteuid(),
      status.st_mode & (S_IRWXG | S_IRWXO) == 0
    else { throw PersistentProfileCatalogError.insecurePermissions }
    do {
      let document = try JSONDecoder().decode(
        Document.self, from: Data(contentsOf: catalogURL, options: .mappedIfSafe))
      guard document.version == 1 else { throw PersistentProfileCatalogError.corruptCatalog }
      return document
    } catch let error as PersistentProfileCatalogError {
      throw error
    } catch {
      throw PersistentProfileCatalogError.corruptCatalog
    }
  }

  private func saveLocked(_ document: Document) throws {
    let temporaryURL = directoryURL.appendingPathComponent(".profiles-\(UUID().uuidString).tmp")
    do {
      let data = try JSONEncoder().encode(document)
      try data.write(to: temporaryURL, options: [.atomic])
      guard chmod(temporaryURL.path, S_IRUSR | S_IWUSR) == 0 else {
        throw PersistentProfileCatalogError.storageUnavailable
      }
      if rename(temporaryURL.path, catalogURL.path) != 0 {
        throw PersistentProfileCatalogError.storageUnavailable
      }
    } catch let error as PersistentProfileCatalogError {
      try? FileManager.default.removeItem(at: temporaryURL)
      throw error
    } catch {
      try? FileManager.default.removeItem(at: temporaryURL)
      throw PersistentProfileCatalogError.storageUnavailable
    }
  }
}
