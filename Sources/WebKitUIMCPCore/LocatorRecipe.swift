import CryptoKit
import Foundation

public enum LocatorFact: Hashable, Codable, Sendable {
  case role
  case accessibleName
  case label
  case contextAnchor(String)
  case stableAttribute(String)
  case framePath
  case value
  case domPath

  var mayDefineIdentity: Bool {
    switch self {
    case .role, .accessibleName, .label, .contextAnchor, .stableAttribute, .framePath:
      true
    case .value, .domPath:
      false
    }
  }
}

public enum LocatorClauseStrength: String, Codable, Sendable {
  case required
  case corroborating
}

public enum LocatorStringComparison: String, Codable, Sendable {
  case exact
  case whitespaceCollapsed

  func matches(expected: String, actual: String) -> Bool {
    switch self {
    case .exact:
      actual == expected
    case .whitespaceCollapsed:
      Self.collapseWhitespace(actual) == Self.collapseWhitespace(expected)
    }
  }

  private static func collapseWhitespace(_ value: String) -> String {
    value.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
  }
}

public struct LocatorClause: Hashable, Codable, Sendable {
  public let fact: LocatorFact
  public let expectedValue: String
  public let strength: LocatorClauseStrength
  public let comparison: LocatorStringComparison

  public init(
    fact: LocatorFact,
    expectedValue: String,
    strength: LocatorClauseStrength,
    comparison: LocatorStringComparison = .exact
  ) {
    self.fact = fact
    self.expectedValue = expectedValue
    self.strength = strength
    self.comparison = comparison
  }
}

public enum LocatorRecipeError: Error, Equatable, Sendable {
  case emptyElementID
  case emptyObservationID
  case noRequiredIdentityClause
  case duplicateFact(LocatorFact)
  case mutableFactCannotBeRequired(LocatorFact)
}

/// An observation-scoped recipe. It is data for re-resolution, not a node handle.
public struct LocatorRecipe: Codable, Equatable, Sendable {
  public let elementID: String
  public let observationID: String
  public let observationGeneration: UInt64
  public let clauses: [LocatorClause]

  public init(
    elementID: String,
    observationID: String,
    observationGeneration: UInt64,
    clauses: [LocatorClause]
  ) throws {
    guard !elementID.isEmpty else { throw LocatorRecipeError.emptyElementID }
    guard !observationID.isEmpty else { throw LocatorRecipeError.emptyObservationID }

    var seenFacts = Set<LocatorFact>()
    for clause in clauses {
      guard seenFacts.insert(clause.fact).inserted else {
        throw LocatorRecipeError.duplicateFact(clause.fact)
      }
      if clause.strength == .required, !clause.fact.mayDefineIdentity {
        throw LocatorRecipeError.mutableFactCannotBeRequired(clause.fact)
      }
    }

    guard clauses.contains(where: { $0.strength == .required && $0.fact.mayDefineIdentity }) else {
      throw LocatorRecipeError.noRequiredIdentityClause
    }

    self.elementID = elementID
    self.observationID = observationID
    self.observationGeneration = observationGeneration
    self.clauses = clauses
  }

  /// Stable across observations while the required semantic identity remains
  /// unchanged. It is evidence for predicates, never an authority handle.
  public var semanticIdentity: String {
    let components = clauses.compactMap { clause -> String? in
      guard clause.strength == .required else { return nil }
      return [
        Self.identityName(for: clause.fact),
        clause.comparison.rawValue,
        clause.expectedValue,
      ].joined(separator: "\u{1F}")
    }.sorted()
    let digest = SHA256.hash(data: Data(components.joined(separator: "\u{1E}").utf8))
      .map { String(format: "%02x", $0) }
      .joined()
    return "locator:\(digest)"
  }

  private static func identityName(for fact: LocatorFact) -> String {
    switch fact {
    case .role: "role"
    case .accessibleName: "accessible_name"
    case .label: "label"
    case .contextAnchor(let selector): "context_anchor:\(selector)"
    case .stableAttribute(let name): "stable_attribute:\(name)"
    case .framePath: "frame_path"
    case .value: "value"
    case .domPath: "dom_path"
    }
  }
}

public struct LocatorCandidate: Codable, Equatable, Sendable {
  public let candidateID: String
  public let facts: [LocatorFact: String]

  public init(candidateID: String, facts: [LocatorFact: String]) {
    self.candidateID = candidateID
    self.facts = facts
  }
}

public enum RequiredClauseFailure: Codable, Equatable, Sendable {
  case missing(LocatorFact)
  case mismatch(LocatorFact)
}

public struct LocatorCandidateEvaluation: Codable, Equatable, Sendable {
  public let candidateID: String
  public let requiredFailures: [RequiredClauseFailure]
  public let corroboratingMatches: Int
  public let corroboratingAvailable: Int

  public init(
    candidateID: String,
    requiredFailures: [RequiredClauseFailure],
    corroboratingMatches: Int,
    corroboratingAvailable: Int
  ) {
    self.candidateID = candidateID
    self.requiredFailures = requiredFailures
    self.corroboratingMatches = corroboratingMatches
    self.corroboratingAvailable = corroboratingAvailable
  }

  public var isEligible: Bool { requiredFailures.isEmpty }
}

public struct LocatorResolution: Codable, Equatable, Sendable {
  public let recipeElementID: String
  public let evaluations: [LocatorCandidateEvaluation]

  public init(recipeElementID: String, evaluations: [LocatorCandidateEvaluation]) {
    self.recipeElementID = recipeElementID
    self.evaluations = evaluations
  }

  public var eligibleCandidateIDs: [String] {
    evaluations.lazy.filter(\.isEligible).map(\.candidateID)
  }

  public var finalCandidateCount: Int { eligibleCandidateIDs.count }
}

public enum LocatorResolver {
  /// Applies every required clause. Corroborating clauses are measured but can
  /// never silently choose one of several otherwise eligible candidates.
  public static func resolve(
    recipe: LocatorRecipe,
    candidates: [LocatorCandidate]
  ) -> LocatorResolution {
    let evaluations = candidates.map { candidate in
      var failures: [RequiredClauseFailure] = []
      var corroboratingMatches = 0
      var corroboratingAvailable = 0

      for clause in recipe.clauses {
        guard let actualValue = candidate.facts[clause.fact] else {
          if clause.strength == .required {
            failures.append(.missing(clause.fact))
          }
          continue
        }

        let matches = clause.comparison.matches(
          expected: clause.expectedValue,
          actual: actualValue
        )
        switch clause.strength {
        case .required:
          if !matches { failures.append(.mismatch(clause.fact)) }
        case .corroborating:
          corroboratingAvailable += 1
          if matches { corroboratingMatches += 1 }
        }
      }

      return LocatorCandidateEvaluation(
        candidateID: candidate.candidateID,
        requiredFailures: failures,
        corroboratingMatches: corroboratingMatches,
        corroboratingAvailable: corroboratingAvailable
      )
    }

    return LocatorResolution(recipeElementID: recipe.elementID, evaluations: evaluations)
  }
}
