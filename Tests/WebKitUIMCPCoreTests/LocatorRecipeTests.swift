import Testing

@testable import WebKitUIMCPCore

@Suite("Locator recipes")
struct LocatorRecipeTests {
  @Test("Required semantic facts select one candidate")
  func uniqueResolution() throws {
    let recipe = try makeRecipe()
    let resolution = LocatorResolver.resolve(
      recipe: recipe,
      candidates: [
        .init(candidateID: "n1", facts: [.role: "button", .accessibleName: "Cancel"]),
        .init(candidateID: "n2", facts: [.role: "button", .accessibleName: "Submit"]),
      ]
    )

    #expect(resolution.eligibleCandidateIDs == ["n2"])
    #expect(resolution.finalCandidateCount == 1)
  }

  @Test("A missing required fact excludes the candidate")
  func missingRequiredFact() throws {
    let recipe = try makeRecipe()
    let resolution = LocatorResolver.resolve(
      recipe: recipe,
      candidates: [.init(candidateID: "n1", facts: [.role: "button"])]
    )

    #expect(resolution.finalCandidateCount == 0)
    #expect(resolution.evaluations[0].requiredFailures == [.missing(.accessibleName)])
  }

  @Test("Corroboration cannot silently break an ambiguity")
  func corroborationDoesNotChoose() throws {
    let recipe = try LocatorRecipe(
      elementID: "e17",
      observationID: "observation-1",
      observationGeneration: 4,
      clauses: [
        .init(fact: .role, expectedValue: "button", strength: .required),
        .init(
          fact: .stableAttribute("data-testid"),
          expectedValue: "submit",
          strength: .corroborating
        ),
      ]
    )
    let resolution = LocatorResolver.resolve(
      recipe: recipe,
      candidates: [
        .init(
          candidateID: "n1",
          facts: [
            .role: "button",
            .stableAttribute("data-testid"): "submit",
          ]),
        .init(candidateID: "n2", facts: [.role: "button"]),
      ]
    )

    #expect(resolution.finalCandidateCount == 2)
    #expect(resolution.evaluations[0].corroboratingMatches == 1)
    #expect(resolution.evaluations[1].corroboratingAvailable == 0)
  }

  @Test("A context anchor rejects a recycled virtual row")
  func contextAnchorRejectsRecycle() throws {
    let recipe = try LocatorRecipe(
      elementID: "e17",
      observationID: "observation-1",
      observationGeneration: 4,
      clauses: [
        .init(fact: .role, expectedValue: "button", strength: .required),
        .init(
          fact: .contextAnchor("invoice_id"),
          expectedValue: "INV-0042",
          strength: .required
        ),
      ]
    )
    let resolution = LocatorResolver.resolve(
      recipe: recipe,
      candidates: [
        .init(
          candidateID: "recycled",
          facts: [
            .role: "button",
            .contextAnchor("invoice_id"): "INV-0089",
          ])
      ]
    )

    #expect(resolution.finalCandidateCount == 0)
    #expect(
      resolution.evaluations[0].requiredFailures
        == [.mismatch(.contextAnchor("invoice_id"))]
    )
  }

  @Test("Mutable state and DOM paths cannot define identity")
  func mutableFactsRejectedAsRequired() {
    #expect(throws: LocatorRecipeError.mutableFactCannotBeRequired(.value)) {
      try LocatorRecipe(
        elementID: "e1",
        observationID: "o1",
        observationGeneration: 0,
        clauses: [.init(fact: .value, expectedValue: "", strength: .required)]
      )
    }
    #expect(throws: LocatorRecipeError.mutableFactCannotBeRequired(.domPath)) {
      try LocatorRecipe(
        elementID: "e1",
        observationID: "o1",
        observationGeneration: 0,
        clauses: [.init(fact: .domPath, expectedValue: "body>button", strength: .required)]
      )
    }
  }

  @Test("Recipes require one identity clause and unique fact keys")
  func recipeInvariants() {
    #expect(throws: LocatorRecipeError.noRequiredIdentityClause) {
      try LocatorRecipe(
        elementID: "e1",
        observationID: "o1",
        observationGeneration: 0,
        clauses: [.init(fact: .value, expectedValue: "", strength: .corroborating)]
      )
    }
    #expect(throws: LocatorRecipeError.duplicateFact(.role)) {
      try LocatorRecipe(
        elementID: "e1",
        observationID: "o1",
        observationGeneration: 0,
        clauses: [
          .init(fact: .role, expectedValue: "button", strength: .required),
          .init(fact: .role, expectedValue: "button", strength: .corroborating),
        ]
      )
    }
  }

  @Test("Whitespace normalization is explicit")
  func explicitWhitespaceNormalization() throws {
    let recipe = try LocatorRecipe(
      elementID: "e17",
      observationID: "observation-1",
      observationGeneration: 4,
      clauses: [
        .init(
          fact: .accessibleName,
          expectedValue: "Save changes",
          strength: .required,
          comparison: .whitespaceCollapsed
        )
      ]
    )
    let resolution = LocatorResolver.resolve(
      recipe: recipe,
      candidates: [
        .init(candidateID: "n1", facts: [.accessibleName: "  Save\n changes  "])
      ]
    )

    #expect(resolution.eligibleCandidateIDs == ["n1"])
  }

  @Test("Semantic identity survives observation leases but changes with required facts")
  func semanticIdentity() throws {
    let first = try LocatorRecipe(
      elementID: "e1",
      observationID: "obs-1",
      observationGeneration: 1,
      clauses: [
        .init(fact: .role, expectedValue: "textbox", strength: .required),
        .init(fact: .accessibleName, expectedValue: "Name", strength: .required),
        .init(fact: .domPath, expectedValue: "body>input", strength: .corroborating),
      ])
    let nextLease = try LocatorRecipe(
      elementID: "e7",
      observationID: "obs-2",
      observationGeneration: 2,
      clauses: [
        .init(fact: .accessibleName, expectedValue: "Name", strength: .required),
        .init(fact: .role, expectedValue: "textbox", strength: .required),
      ])
    let otherTarget = try LocatorRecipe(
      elementID: "e1",
      observationID: "obs-1",
      observationGeneration: 1,
      clauses: [
        .init(fact: .role, expectedValue: "textbox", strength: .required),
        .init(fact: .accessibleName, expectedValue: "Email", strength: .required),
      ])

    #expect(first.semanticIdentity == nextLease.semanticIdentity)
    #expect(first.semanticIdentity != otherTarget.semanticIdentity)
  }

  private func makeRecipe() throws -> LocatorRecipe {
    try LocatorRecipe(
      elementID: "e17",
      observationID: "observation-1",
      observationGeneration: 4,
      clauses: [
        .init(fact: .role, expectedValue: "button", strength: .required),
        .init(fact: .accessibleName, expectedValue: "Submit", strength: .required),
      ]
    )
  }
}
