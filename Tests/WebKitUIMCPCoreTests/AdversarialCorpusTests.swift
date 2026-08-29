import Foundation
import Testing

@testable import WebKitUIMCPCore

@Suite("Deterministic adversarial corpus")
struct AdversarialCorpusTests {
  private let origin = SecurityOrigin(scheme: "https", host: "example.com")
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  @Test("Capability mutations never widen an exact grant")
  func capabilityBindingCorpus() async {
    let authority = CapabilityAuthority()
    let handle = await authority.issue(
      CapabilityScope(
        actions: [.fillForm],
        origins: [origin],
        acceptedInputProvenance: [.userIntent],
        expiresAt: now.addingTimeInterval(60)))
    let origins = [
      origin,
      SecurityOrigin(scheme: "http", host: "example.com"),
      SecurityOrigin(scheme: "https", host: "evil-example.com"),
      SecurityOrigin(scheme: "https", host: "example.com", port: 444),
    ]
    let provenanceCorpus: [Set<ProvenanceClass>] = [
      [], [.userIntent], [.thirdPartyEmbed], [.passwordOrSecret],
      [.userIntent, .thirdPartyEmbed],
    ]

    for action in BrowserCapability.allCases {
      for liveOrigin in origins {
        for provenance in provenanceCorpus {
          let decision = await authority.evaluate(
            CapabilityRequest(
              action: action, liveOrigin: liveOrigin, inputProvenance: provenance),
            using: handle,
            now: now)
          let expectedAllowed =
            action == .fillForm && liveOrigin == origin
            && provenance.isSubset(of: Set([.userIntent]))
          #expect((decision == .allowed) == expectedAllowed)
        }
      }
    }
  }

  @Test("Canonical digest is invariant across a seeded permutation corpus")
  func canonicalDigestCorpus() throws {
    let entries = try (0..<12).map { index in
      ObservationStateEntry(
        key: ObservationFieldKey(
          frameID: "frame-\(index % 3)", elementID: "element-\(index)", field: "@text"),
        value: try provenanced("value-\(index)"))
    }
    let baseline = try canonicalState(entries: entries)
    let digest = try baseline.digest()
    var generator = SeededGenerator(state: 0x574B_5549_4D43_5031)

    for _ in 0..<256 {
      let candidate = try canonicalState(entries: entries.shuffled(using: &generator))
      #expect(try candidate.digest() == digest)
      #expect(try candidate.canonicalJSONData() == baseline.canonicalJSONData())
    }
  }

  @Test("Receipt exports disclose no adversarial raw key or expected value")
  func receiptRedactionCorpus() throws {
    let key = ObservationFieldKey(frameID: "main", elementID: "status", field: "@value")
    let corpus = [
      "person@example.test",
      "token=abc123&next=/billing",
      "line-one\nline-two",
      "\"quoted\":true",
      "emoji-🔐-秘密",
      String(repeating: "sensitive-", count: 64),
    ]

    for (index, raw) in corpus.enumerated() {
      let receipt = TransactionReceipt(
        idempotencyKey: "raw-key-\(index)-\(raw)",
        planDigest: String(repeating: "a", count: 64),
        phase: .verified,
        baseObservationDigest: String(repeating: "b", count: 64),
        resultObservationDigest: String(repeating: "c", count: 64),
        preparedAtNanoseconds: 1,
        dispatchedAtNanoseconds: 2,
        observedAtNanoseconds: 3,
        deadlineNanoseconds: 4,
        postconditionEvidence: [
          PredicateEvidence(
            predicate: .entryTextDigest(key, ObservationPredicate.textDigest(of: raw)),
            result: .satisfied)
        ],
        recoveredByReconciliation: false)
      let export = TransactionReceiptExportV1(
        receipt: receipt, exportedAt: "2026-08-29T12:00:00Z")
      let json = try #require(String(data: export.canonicalJSONData(), encoding: .utf8))

      #expect(!json.contains(raw))
      #expect(!export.markdown().contains(raw))
      #expect(!json.contains(receipt.idempotencyKey))
    }
  }

  @Test("Reconciliation mutation corpus never turns a mismatch into success")
  func reconciliationCorpus() async throws {
    for index in 0..<32 {
      let expected = "provider-success-\(index)"
      let mutation = index == 31 ? expected : "provider-mismatch-\(index)"
      let verification = try await reconcile(expected: expected, observed: mutation, index: index)
      switch verification {
      case .verified:
        #expect(index == 31)
      case .indeterminate:
        #expect(index != 31)
      case .pending:
        Issue.record("Reconciliation must never return pending")
      }
    }
  }

  private func reconcile(expected: String, observed: String, index: Int) async throws
    -> TransactionVerification
  {
    let field = ObservationFieldKey(frameID: "main", elementID: "status", field: "@text")
    let authority = CapabilityAuthority()
    let handle = await authority.issue(
      CapabilityScope(
        actions: [.submitForm],
        origins: [origin],
        acceptedInputProvenance: [.userIntent],
        expiresAt: now.addingTimeInterval(60)))
    let ledger = TransactionalWriteLedger()
    let recipe = try LocatorRecipe(
      elementID: "submit",
      observationID: "observation-\(index)",
      observationGeneration: 1,
      clauses: [
        LocatorClause(fact: .role, expectedValue: "button", strength: .required),
        LocatorClause(
          fact: .accessibleName, expectedValue: "Submit", strength: .required),
      ])
    let plan = try TransactionalWritePlan(
      idempotencyKey: "reconciliation-corpus-\(index)",
      target: recipe,
      requiredCapability: .submitForm,
      inputProvenance: [.userIntent],
      expectedOrigin: origin,
      preconditions: [],
      postconditions: [
        .entryTextDigest(field, ObservationPredicate.textDigest(of: expected))
      ],
      verificationTimeoutNanoseconds: 100)
    let empty = TransactionObservation(
      state: try canonicalState(entries: []), completeness: .complete)
    _ = try await ledger.prepare(
      plan,
      observation: empty,
      capabilityAuthority: authority,
      capabilityHandle: handle,
      wallClockNow: now,
      monotonicNowNanoseconds: 10)
    _ = try await ledger.beginDispatch(
      idempotencyKey: plan.idempotencyKey,
      observation: empty,
      resolution: LocatorResolution(
        recipeElementID: "submit",
        evaluations: [
          LocatorCandidateEvaluation(
            candidateID: "candidate", requiredFailures: [], corroboratingMatches: 0,
            corroboratingAvailable: 0)
        ]),
      capabilityAuthority: authority,
      capabilityHandle: handle,
      wallClockNow: now,
      monotonicNowNanoseconds: 20)
    _ = try await ledger.recordDispatchOutcome(
      idempotencyKey: plan.idempotencyKey, outcome: .unknown, monotonicNowNanoseconds: 21)
    let fresh = TransactionObservation(
      state: try canonicalState(
        generation: 2,
        entries: [ObservationStateEntry(key: field, value: try provenanced(observed))]),
      completeness: .complete)
    return try await ledger.reconcile(
      idempotencyKey: plan.idempotencyKey,
      observation: fresh,
      monotonicNowNanoseconds: 30)
  }

  private func canonicalState(
    generation: UInt64 = 1,
    entries: [ObservationStateEntry]
  ) throws -> CanonicalObservationState {
    try CanonicalObservationState(
      generation: generation,
      documentID: "document-1",
      securityOrigin: origin,
      entries: entries)
  }

  private func provenanced(_ value: String) throws -> ProvenancedText {
    try ProvenancedText(
      text: value,
      source: ProvenanceSource(
        classification: .firstPartySiteContent,
        documentID: "document-1",
        frameID: "main",
        securityOrigin: origin))
  }
}

private struct SeededGenerator: RandomNumberGenerator {
  var state: UInt64

  mutating func next() -> UInt64 {
    state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return state
  }
}
