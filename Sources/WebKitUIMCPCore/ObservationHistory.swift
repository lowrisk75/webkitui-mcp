import CryptoKit
import Foundation

public struct ObservationFieldKey: Codable, Hashable, Comparable, Sendable {
  public let frameID: String
  public let elementID: String
  public let field: String

  public init(frameID: String, elementID: String, field: String) {
    self.frameID = frameID
    self.elementID = elementID
    self.field = field
  }

  private var orderingKey: String { "\(frameID)\u{1F}\(elementID)\u{1F}\(field)" }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.orderingKey < rhs.orderingKey
  }
}

public struct ObservationStateEntry: Codable, Equatable, Sendable {
  public let key: ObservationFieldKey
  public let value: ProvenancedText

  public init(key: ObservationFieldKey, value: ProvenancedText) {
    self.key = key
    self.value = value
  }
}

public enum ObservationHistoryError: Error, Equatable, Sendable {
  case emptyDocumentID
  case emptyKeyComponent
  case duplicateKey(ObservationFieldKey)
  case invalidMaximumDeltaDepth(Int)
  case generationGap(expected: UInt64, actual: UInt64)
  case generationOverflow
  case baseGenerationMismatch
  case baseDigestMismatch
  case resultDigestMismatch
  case insertTargetExists(ObservationFieldKey)
  case mutationTargetMissing(ObservationFieldKey)
  case expectedValueMismatch(ObservationFieldKey)
}

public struct CanonicalObservationState: Codable, Equatable, Sendable {
  public let generation: UInt64
  public let documentID: String
  public let securityOrigin: SecurityOrigin
  public let entries: [ObservationStateEntry]

  public init(
    generation: UInt64,
    documentID: String,
    securityOrigin: SecurityOrigin,
    entries: [ObservationStateEntry]
  ) throws {
    guard !documentID.isEmpty else { throw ObservationHistoryError.emptyDocumentID }

    var keys = Set<ObservationFieldKey>()
    for entry in entries {
      guard !entry.key.frameID.isEmpty, !entry.key.elementID.isEmpty, !entry.key.field.isEmpty
      else {
        throw ObservationHistoryError.emptyKeyComponent
      }
      guard keys.insert(entry.key).inserted else {
        throw ObservationHistoryError.duplicateKey(entry.key)
      }
    }

    self.generation = generation
    self.documentID = documentID
    self.securityOrigin = securityOrigin
    self.entries = entries.sorted { $0.key < $1.key }
  }

  public func digest() throws -> String {
    try Self.sha256(canonicalJSONData())
  }

  public func canonicalJSONData() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(self)
  }

  fileprivate var entriesByKey: [ObservationFieldKey: ProvenancedText] {
    Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0.value) })
  }

  fileprivate static func digest(_ value: ProvenancedText) throws -> String {
    try sha256(value.canonicalJSONData())
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

public enum ObservationDeltaOperation: Codable, Equatable, Sendable {
  case insert(key: ObservationFieldKey, value: ProvenancedText)
  case replace(
    key: ObservationFieldKey,
    expectedValueDigest: String,
    value: ProvenancedText
  )
  case remove(key: ObservationFieldKey, expectedValueDigest: String)
}

public struct ObservationDelta: Codable, Equatable, Sendable {
  public let baseGeneration: UInt64
  public let resultGeneration: UInt64
  public let baseDigest: String
  public let resultDigest: String
  public let operations: [ObservationDeltaOperation]

  public static func between(
    _ base: CanonicalObservationState,
    and result: CanonicalObservationState
  ) throws -> Self {
    let (nextGeneration, overflow) = base.generation.addingReportingOverflow(1)
    guard !overflow else { throw ObservationHistoryError.generationOverflow }
    guard result.generation == nextGeneration else {
      throw ObservationHistoryError.generationGap(
        expected: nextGeneration,
        actual: result.generation
      )
    }
    guard base.documentID == result.documentID, base.securityOrigin == result.securityOrigin else {
      throw ObservationHistoryError.baseDigestMismatch
    }

    let old = base.entriesByKey
    let new = result.entriesByKey
    let oldKeys = Set(old.keys)
    let newKeys = Set(new.keys)
    var operations: [ObservationDeltaOperation] = []

    for key in oldKeys.subtracting(newKeys).sorted() {
      operations.append(
        .remove(key: key, expectedValueDigest: try CanonicalObservationState.digest(old[key]!))
      )
    }
    for key in oldKeys.intersection(newKeys).sorted() where old[key] != new[key] {
      operations.append(
        .replace(
          key: key,
          expectedValueDigest: try CanonicalObservationState.digest(old[key]!),
          value: new[key]!
        )
      )
    }
    for key in newKeys.subtracting(oldKeys).sorted() {
      operations.append(.insert(key: key, value: new[key]!))
    }

    return Self(
      baseGeneration: base.generation,
      resultGeneration: result.generation,
      baseDigest: try base.digest(),
      resultDigest: try result.digest(),
      operations: operations
    )
  }

  public func applying(to base: CanonicalObservationState) throws -> CanonicalObservationState {
    guard base.generation == baseGeneration else {
      throw ObservationHistoryError.baseGenerationMismatch
    }
    guard try base.digest() == baseDigest else {
      throw ObservationHistoryError.baseDigestMismatch
    }

    var values = base.entriesByKey
    for operation in operations {
      switch operation {
      case .insert(let key, let value):
        guard values[key] == nil else { throw ObservationHistoryError.insertTargetExists(key) }
        values[key] = value
      case .replace(let key, let expectedDigest, let value):
        guard let oldValue = values[key] else {
          throw ObservationHistoryError.mutationTargetMissing(key)
        }
        guard try CanonicalObservationState.digest(oldValue) == expectedDigest else {
          throw ObservationHistoryError.expectedValueMismatch(key)
        }
        values[key] = value
      case .remove(let key, let expectedDigest):
        guard let oldValue = values[key] else {
          throw ObservationHistoryError.mutationTargetMissing(key)
        }
        guard try CanonicalObservationState.digest(oldValue) == expectedDigest else {
          throw ObservationHistoryError.expectedValueMismatch(key)
        }
        values.removeValue(forKey: key)
      }
    }

    let result = try CanonicalObservationState(
      generation: resultGeneration,
      documentID: base.documentID,
      securityOrigin: base.securityOrigin,
      entries: values.map { ObservationStateEntry(key: $0.key, value: $0.value) }
    )
    guard try result.digest() == resultDigest else {
      throw ObservationHistoryError.resultDigestMismatch
    }
    return result
  }
}

public enum CheckpointBoundary: String, Codable, Equatable, Sendable {
  case navigation
  case largeMutation = "large_mutation"
  case addressingFailure = "addressing_failure"
  case manual
  case documentChanged = "document_changed"
  case periodicLimit = "periodic_limit"
}

public enum ObservationHistoryAppend: Equatable, Sendable {
  case delta(depth: Int)
  case checkpoint(CheckpointBoundary)
}

public struct ObservationHistory: Sendable {
  public private(set) var checkpoint: CanonicalObservationState
  public private(set) var deltas: [ObservationDelta]
  public let maximumDeltaDepth: Int

  public init(checkpoint: CanonicalObservationState, maximumDeltaDepth: Int) throws {
    guard maximumDeltaDepth > 0 else {
      throw ObservationHistoryError.invalidMaximumDeltaDepth(maximumDeltaDepth)
    }
    self.checkpoint = checkpoint
    self.deltas = []
    self.maximumDeltaDepth = maximumDeltaDepth
  }

  public func reconstruct() throws -> CanonicalObservationState {
    try deltas.reduce(checkpoint) { state, delta in
      try delta.applying(to: state)
    }
  }

  public mutating func append(
    _ next: CanonicalObservationState,
    boundary: CheckpointBoundary? = nil
  ) throws -> ObservationHistoryAppend {
    let current = try reconstruct()
    let (expectedGeneration, overflow) = current.generation.addingReportingOverflow(1)
    guard !overflow else { throw ObservationHistoryError.generationOverflow }
    guard next.generation == expectedGeneration else {
      throw ObservationHistoryError.generationGap(
        expected: expectedGeneration,
        actual: next.generation
      )
    }

    let forcedBoundary: CheckpointBoundary?
    if current.documentID != next.documentID || current.securityOrigin != next.securityOrigin {
      forcedBoundary = .documentChanged
    } else if let boundary {
      forcedBoundary = boundary
    } else if deltas.count >= maximumDeltaDepth {
      forcedBoundary = .periodicLimit
    } else {
      forcedBoundary = nil
    }

    if let forcedBoundary {
      checkpoint = next
      deltas.removeAll(keepingCapacity: true)
      return .checkpoint(forcedBoundary)
    }

    deltas.append(try ObservationDelta.between(current, and: next))
    return .delta(depth: deltas.count)
  }
}
