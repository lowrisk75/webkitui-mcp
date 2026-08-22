public enum MFSInformation: Hashable, Codable, Sendable {
  case tag
  case text
  case attribute(String)

  fileprivate var canonicalKey: String {
    switch self {
    case .tag: "@tag"
    case .text: "@text"
    case .attribute(let name): "attribute:\(name)"
    }
  }
}

public struct MFSUnit: Hashable, Codable, Comparable, Sendable {
  public let observationElementID: String
  public let information: MFSInformation

  public init(observationElementID: String, information: MFSInformation) {
    self.observationElementID = observationElementID
    self.information = information
  }

  fileprivate var canonicalKey: String {
    "\(observationElementID)\u{1F}\(information.canonicalKey)"
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.canonicalKey < rhs.canonicalKey
  }
}

public enum MFSError: Error, Equatable, Sendable {
  case emptyDataset
  case emptyInstanceID
  case emptyObservation
  case emptyApproximateMFS
  case invalidAttributeName(String)
  case approximateMFSOutsideObservation([MFSUnit])
  case nonPositiveOriginalCharacterCount(Int)
  case nonPositiveOriginalTokenCount(Int)
  case duplicateInstanceID(String)
  case duplicateReductionID(String)
  case missingReduction(String)
  case unknownInstance(String)
  case retainedUnitOutsideObservation(instanceID: String, units: [MFSUnit])
  case invalidReducedCharacterCount(instanceID: String, count: Int)
  case incompleteTokenCounts(instanceID: String)
  case invalidReducedTokenCount(instanceID: String, count: Int)
}

/// One immutable observation and its preconstructed approximate, 1-minimal MFS.
public struct MFSInstance: Codable, Equatable, Sendable {
  public let id: String
  public let observationUnits: [MFSUnit]
  public let approximateMFS: [MFSUnit]
  public let originalCharacterCount: Int
  public let originalTokenCount: Int?

  public init(
    id: String,
    observationUnits: Set<MFSUnit>,
    approximateMFS: Set<MFSUnit>,
    originalCharacterCount: Int,
    originalTokenCount: Int? = nil
  ) throws {
    guard !id.isEmpty else { throw MFSError.emptyInstanceID }
    guard !observationUnits.isEmpty else { throw MFSError.emptyObservation }
    guard !approximateMFS.isEmpty else { throw MFSError.emptyApproximateMFS }

    for unit in observationUnits {
      if case .attribute(let name) = unit.information,
        name.isEmpty || name.hasPrefix("@")
      {
        throw MFSError.invalidAttributeName(name)
      }
    }

    let foreignMFSUnits = approximateMFS.subtracting(observationUnits).sorted()
    guard foreignMFSUnits.isEmpty else {
      throw MFSError.approximateMFSOutsideObservation(foreignMFSUnits)
    }
    guard originalCharacterCount > 0 else {
      throw MFSError.nonPositiveOriginalCharacterCount(originalCharacterCount)
    }
    if let originalTokenCount, originalTokenCount <= 0 {
      throw MFSError.nonPositiveOriginalTokenCount(originalTokenCount)
    }

    self.id = id
    self.observationUnits = observationUnits.sorted()
    self.approximateMFS = approximateMFS.sorted()
    self.originalCharacterCount = originalCharacterCount
    self.originalTokenCount = originalTokenCount
  }
}

public struct MFSReduction: Codable, Equatable, Sendable {
  public let instanceID: String
  public let retainedUnits: [MFSUnit]
  public let serializedCharacterCount: Int
  public let serializedTokenCount: Int?

  public init(
    instanceID: String,
    retainedUnits: Set<MFSUnit>,
    serializedCharacterCount: Int,
    serializedTokenCount: Int? = nil
  ) {
    self.instanceID = instanceID
    self.retainedUnits = retainedUnits.sorted()
    self.serializedCharacterCount = serializedCharacterCount
    self.serializedTokenCount = serializedTokenCount
  }
}

public struct MFSInstanceResult: Codable, Equatable, Sendable {
  public let instanceID: String
  public let covered: Bool
  public let missingMFSUnits: [MFSUnit]
  public let mfsUnitRecall: Double
  public let characterRetentionRatio: Double
  public let tokenRetentionRatio: Double?
}

public struct MFSCoverageReport: Codable, Equatable, Sendable {
  public let instanceCount: Int
  public let coveredInstanceCount: Int
  public let coverage: Double
  public let meanCharacterRetentionRatio: Double
  public let meanTokenRetentionRatio: Double?
  public let results: [MFSInstanceResult]
}

public enum MFSBenchmark {
  /// Implements the paper's binary full-MFS retention metric. Unit recall and
  /// token retention are emitted only as separately named diagnostics.
  public static func evaluate(
    instances: [MFSInstance],
    reductions: [MFSReduction]
  ) throws -> MFSCoverageReport {
    guard !instances.isEmpty else { throw MFSError.emptyDataset }

    var instancesByID: [String: MFSInstance] = [:]
    for instance in instances {
      guard instancesByID.updateValue(instance, forKey: instance.id) == nil else {
        throw MFSError.duplicateInstanceID(instance.id)
      }
    }

    var reductionsByID: [String: MFSReduction] = [:]
    for reduction in reductions {
      guard instancesByID[reduction.instanceID] != nil else {
        throw MFSError.unknownInstance(reduction.instanceID)
      }
      guard reductionsByID.updateValue(reduction, forKey: reduction.instanceID) == nil else {
        throw MFSError.duplicateReductionID(reduction.instanceID)
      }
    }

    let results = try instances.sorted { $0.id < $1.id }.map { instance in
      guard let reduction = reductionsByID[instance.id] else {
        throw MFSError.missingReduction(instance.id)
      }
      return try evaluate(instance: instance, reduction: reduction)
    }

    let coveredCount = results.lazy.filter(\.covered).count
    let coverage = Double(coveredCount) / Double(results.count)
    let meanCharacterRatio = mean(results.map(\.characterRetentionRatio))
    let tokenRatios = results.compactMap(\.tokenRetentionRatio)
    let meanTokenRatio = tokenRatios.count == results.count ? mean(tokenRatios) : nil

    return MFSCoverageReport(
      instanceCount: results.count,
      coveredInstanceCount: coveredCount,
      coverage: coverage,
      meanCharacterRetentionRatio: meanCharacterRatio,
      meanTokenRetentionRatio: meanTokenRatio,
      results: results
    )
  }

  private static func evaluate(
    instance: MFSInstance,
    reduction: MFSReduction
  ) throws -> MFSInstanceResult {
    let observationUnits = Set(instance.observationUnits)
    let retainedUnits = Set(reduction.retainedUnits)
    let foreignUnits = retainedUnits.subtracting(observationUnits).sorted()
    guard foreignUnits.isEmpty else {
      throw MFSError.retainedUnitOutsideObservation(instanceID: instance.id, units: foreignUnits)
    }
    guard (0...instance.originalCharacterCount).contains(reduction.serializedCharacterCount) else {
      throw MFSError.invalidReducedCharacterCount(
        instanceID: instance.id,
        count: reduction.serializedCharacterCount
      )
    }

    let tokenRatio: Double?
    switch (instance.originalTokenCount, reduction.serializedTokenCount) {
    case (nil, nil):
      tokenRatio = nil
    case (.some(let original), .some(let reduced)):
      guard (0...original).contains(reduced) else {
        throw MFSError.invalidReducedTokenCount(instanceID: instance.id, count: reduced)
      }
      tokenRatio = Double(reduced) / Double(original)
    case (.some, nil), (nil, .some):
      throw MFSError.incompleteTokenCounts(instanceID: instance.id)
    }

    let mfs = Set(instance.approximateMFS)
    let missing = mfs.subtracting(retainedUnits).sorted()
    let retainedMFSCount = mfs.count - missing.count

    return MFSInstanceResult(
      instanceID: instance.id,
      covered: missing.isEmpty,
      missingMFSUnits: missing,
      mfsUnitRecall: Double(retainedMFSCount) / Double(mfs.count),
      characterRetentionRatio: Double(reduction.serializedCharacterCount)
        / Double(instance.originalCharacterCount),
      tokenRetentionRatio: tokenRatio
    )
  }

  private static func mean(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    return values.reduce(0, +) / Double(values.count)
  }
}
