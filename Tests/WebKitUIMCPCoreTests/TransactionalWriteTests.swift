import Foundation
import Testing

@testable import WebKitUIMCPCore

@Suite("Transactional writes")
struct TransactionalWriteTests {
  private let origin = SecurityOrigin(scheme: "https", host: "example.com")
  private let wallClock = Date(timeIntervalSince1970: 1_800_000_000)
  private let key = ObservationFieldKey(frameID: "main", elementID: "status", field: "@text")

  @Test("Absence is unknown in a partial observation")
  func partialAbsenceIsUnknown() throws {
    let observation = TransactionObservation(
      state: try state(generation: 1, entries: []),
      completeness: .partial
    )

    #expect(try ObservationPredicate.entryAbsent(key).evaluate(in: observation) == .unknown)
    #expect(try ObservationPredicate.entryPresent(key).evaluate(in: observation) == .unknown)
  }

  @Test("Text digests compare caller values without inventing provenance")
  func textDigestPredicate() throws {
    let value = try text("https://example.com/done")
    let observation = TransactionObservation(
      state: try state(generation: 1, entries: [(key, value)]),
      completeness: .complete
    )
    let predicate = ObservationPredicate.entryTextDigest(
      key, ObservationPredicate.textDigest(of: "https://example.com/done"))
    #expect(try predicate.evaluate(in: observation) == .satisfied)
  }

  @Test("Semantic text digests survive ephemeral element IDs and honor field filters")
  func semanticTextDigestPredicate() throws {
    let statusKey = ObservationFieldKey(
      frameID: "main", elementID: "e42", field: "@accessible_name")
    let observation = TransactionObservation(
      state: try state(generation: 2, entries: [(statusKey, try text("Saved locally"))]),
      completeness: .complete
    )
    let digest = ObservationPredicate.textDigest(of: "Saved locally")

    #expect(
      try ObservationPredicate.anyEntryTextDigest([.accessibleName], digest)
        .evaluate(in: observation) == .satisfied)
    #expect(
      try ObservationPredicate.anyEntryTextDigest([.text], digest)
        .evaluate(in: observation) == .unsatisfied)

    let partial = TransactionObservation(state: observation.state, completeness: .partial)
    #expect(
      try ObservationPredicate.anyEntryTextDigest([.text], digest)
        .evaluate(in: partial) == .unknown)
  }

  @Test("Prepare checks capability and every precondition")
  func preparationFailsClosed() async throws {
    let authority = CapabilityAuthority()
    let handle = await grant(authority: authority)
    let ledger = TransactionalWriteLedger()
    let observation = TransactionObservation(
      state: try state(generation: 1, entries: []),
      completeness: .partial
    )
    let plan = try makePlan(preconditions: [.entryPresent(key)])

    await #expect(throws: TransactionError.preconditionUnknown) {
      try await ledger.prepare(
        plan,
        observation: observation,
        capabilityAuthority: authority,
        capabilityHandle: handle,
        wallClockNow: wallClock,
        monotonicNowNanoseconds: 10
      )
    }

    let deniedHandle = await authority.issue(
      CapabilityScope(
        actions: [.readPage],
        origins: [origin],
        acceptedInputProvenance: [.userIntent],
        expiresAt: wallClock.addingTimeInterval(60)
      )
    )
    await #expect(throws: TransactionError.capabilityDenied(.actionNotGranted)) {
      try await ledger.prepare(
        try makePlan(idempotencyKey: "denied"),
        observation: TransactionObservation(
          state: try state(generation: 1, entries: []),
          completeness: .complete
        ),
        capabilityAuthority: authority,
        capabilityHandle: deniedHandle,
        wallClockNow: wallClock,
        monotonicNowNanoseconds: 10
      )
    }
  }

  @Test("Same key is idempotent only for the exact same plan")
  func keyConflict() async throws {
    let authority = CapabilityAuthority()
    let handle = await grant(authority: authority)
    let ledger = TransactionalWriteLedger()
    let observation = TransactionObservation(
      state: try state(generation: 1, entries: []),
      completeness: .complete
    )
    let plan = try makePlan()

    _ = try await prepare(
      plan,
      ledger: ledger,
      observation: observation,
      authority: authority,
      handle: handle
    )
    let repeated = try await prepare(
      plan,
      ledger: ledger,
      observation: observation,
      authority: authority,
      handle: handle
    )
    guard case .alreadyExists(let receipt) = repeated else {
      Issue.record("Expected an existing transaction")
      return
    }
    #expect(receipt.phase == .prepared)

    await #expect(throws: TransactionError.idempotencyKeyConflict) {
      try await self.prepare(
        try makePlan(postconditions: [.entryAbsent(key)]),
        ledger: ledger,
        observation: observation,
        authority: authority,
        handle: handle
      )
    }
  }

  @Test("Dispatch rechecks capability, preconditions and unique resolution")
  func dispatchRevalidates() async throws {
    let authority = CapabilityAuthority()
    let handle = await grant(authority: authority)
    let ledger = TransactionalWriteLedger()
    let observation = TransactionObservation(
      state: try state(generation: 1, entries: []),
      completeness: .complete
    )
    let plan = try makePlan()
    _ = try await prepare(
      plan,
      ledger: ledger,
      observation: observation,
      authority: authority,
      handle: handle
    )

    await #expect(throws: TransactionError.targetResolutionMismatch) {
      try await ledger.beginDispatch(
        idempotencyKey: plan.idempotencyKey,
        observation: observation,
        resolution: LocatorResolution(
          recipeElementID: "other-target",
          evaluations: resolution(count: 1).evaluations
        ),
        capabilityAuthority: authority,
        capabilityHandle: handle,
        wallClockNow: wallClock,
        monotonicNowNanoseconds: 20
      )
    }

    await #expect(throws: TransactionError.targetNotUnique(2)) {
      try await ledger.beginDispatch(
        idempotencyKey: plan.idempotencyKey,
        observation: observation,
        resolution: resolution(count: 2),
        capabilityAuthority: authority,
        capabilityHandle: handle,
        wallClockNow: wallClock,
        monotonicNowNanoseconds: 20
      )
    }

    await authority.revoke(handle)
    await #expect(throws: TransactionError.capabilityDenied(.unknownHandle)) {
      try await ledger.beginDispatch(
        idempotencyKey: plan.idempotencyKey,
        observation: observation,
        resolution: resolution(count: 1),
        capabilityAuthority: authority,
        capabilityHandle: handle,
        wallClockNow: wallClock,
        monotonicNowNanoseconds: 20
      )
    }
  }

  @Test("Known non-dispatch returns to prepared and permits a fresh attempt")
  func definitelyNotDispatchedCanRetry() async throws {
    let context = try await preparedContext()
    _ = try await context.ledger.beginDispatch(
      idempotencyKey: context.plan.idempotencyKey,
      observation: context.observation,
      resolution: resolution(count: 1),
      capabilityAuthority: context.authority,
      capabilityHandle: context.handle,
      wallClockNow: wallClock,
      monotonicNowNanoseconds: 20
    )
    let receipt = try await context.ledger.recordDispatchOutcome(
      idempotencyKey: context.plan.idempotencyKey,
      outcome: .notDispatched,
      monotonicNowNanoseconds: 21
    )
    #expect(receipt.phase == .prepared)

    let retry = try await context.ledger.beginDispatch(
      idempotencyKey: context.plan.idempotencyKey,
      observation: context.observation,
      resolution: resolution(count: 1),
      capabilityAuthority: context.authority,
      capabilityHandle: context.handle,
      wallClockNow: wallClock,
      monotonicNowNanoseconds: 22
    )
    #expect(retry.phase == .dispatching)
  }

  @Test("Unknown dispatch becomes indeterminate and cannot be replayed")
  func ambiguousDispatchCannotReplay() async throws {
    let context = try await preparedContext()
    _ = try await context.ledger.beginDispatch(
      idempotencyKey: context.plan.idempotencyKey,
      observation: context.observation,
      resolution: resolution(count: 1),
      capabilityAuthority: context.authority,
      capabilityHandle: context.handle,
      wallClockNow: wallClock,
      monotonicNowNanoseconds: 20
    )
    let receipt = try await context.ledger.recordDispatchOutcome(
      idempotencyKey: context.plan.idempotencyKey,
      outcome: .unknown,
      monotonicNowNanoseconds: 21
    )
    #expect(receipt.phase == .indeterminate)

    await #expect(
      throws: TransactionError.invalidPhase(expected: .prepared, actual: .indeterminate)
    ) {
      try await context.ledger.beginDispatch(
        idempotencyKey: context.plan.idempotencyKey,
        observation: context.observation,
        resolution: resolution(count: 1),
        capabilityAuthority: context.authority,
        capabilityHandle: context.handle,
        wallClockNow: wallClock,
        monotonicNowNanoseconds: 22
      )
    }
  }

  @Test("A postcondition is the only path from dispatched to verified")
  func verifiesWithEvidence() async throws {
    let context = try await dispatchedContext(timeout: 100)
    let succeeded = TransactionObservation(
      state: try state(generation: 2, entries: [(key, try text("saved"))]),
      completeness: .complete
    )
    let result = try await context.ledger.verify(
      idempotencyKey: context.plan.idempotencyKey,
      observation: succeeded,
      monotonicNowNanoseconds: 30
    )
    guard case .verified(let receipt) = result else {
      Issue.record("Expected verified")
      return
    }
    #expect(receipt.phase == .verified)
    #expect(receipt.postconditionEvidence.map(\.result) == [.satisfied])
    #expect(receipt.resultObservationDigest == (try succeeded.state.digest()))
  }

  @Test("Timeout without proof is indeterminate, never a safe failure")
  func timeoutIsIndeterminate() async throws {
    let context = try await dispatchedContext(timeout: 10)
    let incomplete = TransactionObservation(
      state: try state(generation: 2, entries: []),
      completeness: .partial
    )
    let pending = try await context.ledger.verify(
      idempotencyKey: context.plan.idempotencyKey,
      observation: incomplete,
      monotonicNowNanoseconds: 29
    )
    guard case .pending(let pendingReceipt) = pending else {
      Issue.record("Expected pending")
      return
    }
    #expect(pendingReceipt.postconditionEvidence.map(\.result) == [.unknown])

    let timedOut = try await context.ledger.verify(
      idempotencyKey: context.plan.idempotencyKey,
      observation: incomplete,
      monotonicNowNanoseconds: 30
    )
    guard case .indeterminate(let receipt) = timedOut else {
      Issue.record("Expected indeterminate")
      return
    }
    #expect(receipt.phase == .indeterminate)
  }

  @Test("Reconciliation may prove success but never authorizes replay")
  func reconciliation() async throws {
    let context = try await dispatchedContext(outcome: .unknown)
    let succeeded = TransactionObservation(
      state: try state(generation: 2, entries: [(key, try text("saved"))]),
      completeness: .complete
    )
    let result = try await context.ledger.reconcile(
      idempotencyKey: context.plan.idempotencyKey,
      observation: succeeded,
      monotonicNowNanoseconds: 40
    )
    guard case .verified(let receipt) = result else {
      Issue.record("Expected verified reconciliation")
      return
    }
    #expect(receipt.recoveredByReconciliation)
  }

  @Test("Plan validation and monotonic overflow fail closed")
  func validation() async throws {
    #expect(throws: TransactionError.emptyIdempotencyKey) {
      try makePlan(idempotencyKey: "")
    }
    #expect(throws: TransactionError.emptyPostconditions) {
      try makePlan(postconditions: [])
    }
    #expect(throws: TransactionError.invalidExpectedDigest) {
      try makePlan(postconditions: [.entryValueDigest(key, "NOT-A-DIGEST")])
    }
    #expect(throws: TransactionError.invalidExpectedDigest) {
      try makePlan(postconditions: [.entryTextDigest(key, "NOT-A-DIGEST")])
    }
    #expect(throws: TransactionError.invalidExpectedDigest) {
      try makePlan(postconditions: [.anyEntryTextDigest([.text], "NOT-A-DIGEST")])
    }
    #expect(throws: TransactionError.emptySemanticTextFields) {
      try makePlan(
        postconditions: [
          .anyEntryTextDigest([], ObservationPredicate.textDigest(of: "Saved"))
        ])
    }

    let context = try await preparedContext(timeout: 2)
    _ = try await context.ledger.beginDispatch(
      idempotencyKey: context.plan.idempotencyKey,
      observation: context.observation,
      resolution: resolution(count: 1),
      capabilityAuthority: context.authority,
      capabilityHandle: context.handle,
      wallClockNow: wallClock,
      monotonicNowNanoseconds: UInt64.max - 1
    )
    await #expect(throws: TransactionError.deadlineOverflow) {
      try await context.ledger.recordDispatchOutcome(
        idempotencyKey: context.plan.idempotencyKey,
        outcome: .dispatched,
        monotonicNowNanoseconds: UInt64.max - 1
      )
    }
  }

  private func text(_ value: String) throws -> ProvenancedText {
    try ProvenancedText(
      text: value,
      source: ProvenanceSource(
        classification: .firstPartySiteContent,
        documentID: "doc-1",
        frameID: "main",
        securityOrigin: origin
      )
    )
  }

  private func state(
    generation: UInt64,
    entries: [(ObservationFieldKey, ProvenancedText)]
  ) throws -> CanonicalObservationState {
    try CanonicalObservationState(
      generation: generation,
      documentID: "doc-1",
      securityOrigin: origin,
      entries: entries.map { ObservationStateEntry(key: $0.0, value: $0.1) }
    )
  }

  private func recipe() throws -> LocatorRecipe {
    try LocatorRecipe(
      elementID: "submit",
      observationID: "obs-1",
      observationGeneration: 1,
      clauses: [
        LocatorClause(fact: .role, expectedValue: "button", strength: .required),
        LocatorClause(
          fact: .accessibleName,
          expectedValue: "Save",
          strength: .required
        ),
      ]
    )
  }

  private func makePlan(
    idempotencyKey: String = "write-1",
    preconditions: [ObservationPredicate] = [],
    postconditions: [ObservationPredicate]? = nil,
    timeout: UInt64 = 100
  ) throws -> TransactionalWritePlan {
    let saved = try text("saved")
    return try TransactionalWritePlan(
      idempotencyKey: idempotencyKey,
      target: recipe(),
      requiredCapability: .submitForm,
      inputProvenance: [.userIntent],
      expectedOrigin: origin,
      preconditions: preconditions,
      postconditions: postconditions ?? [
        .entryValueDigest(key, try ObservationPredicate.digest(of: saved))
      ],
      verificationTimeoutNanoseconds: timeout
    )
  }

  private func grant(authority: CapabilityAuthority) async -> CapabilityHandle {
    await authority.issue(
      CapabilityScope(
        actions: [.submitForm],
        origins: [origin],
        acceptedInputProvenance: [.userIntent],
        expiresAt: wallClock.addingTimeInterval(60)
      )
    )
  }

  private func resolution(count: Int) -> LocatorResolution {
    LocatorResolution(
      recipeElementID: "submit",
      evaluations: (0..<count).map {
        LocatorCandidateEvaluation(
          candidateID: "candidate-\($0)",
          requiredFailures: [],
          corroboratingMatches: 0,
          corroboratingAvailable: 0
        )
      }
    )
  }

  private func prepare(
    _ plan: TransactionalWritePlan,
    ledger: TransactionalWriteLedger,
    observation: TransactionObservation,
    authority: CapabilityAuthority,
    handle: CapabilityHandle
  ) async throws -> TransactionPreparation {
    try await ledger.prepare(
      plan,
      observation: observation,
      capabilityAuthority: authority,
      capabilityHandle: handle,
      wallClockNow: wallClock,
      monotonicNowNanoseconds: 10
    )
  }

  private func preparedContext(timeout: UInt64 = 100) async throws -> (
    ledger: TransactionalWriteLedger,
    authority: CapabilityAuthority,
    handle: CapabilityHandle,
    plan: TransactionalWritePlan,
    observation: TransactionObservation
  ) {
    let authority = CapabilityAuthority()
    let handle = await grant(authority: authority)
    let ledger = TransactionalWriteLedger()
    let plan = try makePlan(timeout: timeout)
    let observation = TransactionObservation(
      state: try state(generation: 1, entries: []),
      completeness: .complete
    )
    _ = try await prepare(
      plan,
      ledger: ledger,
      observation: observation,
      authority: authority,
      handle: handle
    )
    return (ledger, authority, handle, plan, observation)
  }

  private func dispatchedContext(
    timeout: UInt64 = 100,
    outcome: DispatchOutcome = .dispatched
  ) async throws -> (
    ledger: TransactionalWriteLedger,
    plan: TransactionalWritePlan
  ) {
    let context = try await preparedContext(timeout: timeout)
    _ = try await context.ledger.beginDispatch(
      idempotencyKey: context.plan.idempotencyKey,
      observation: context.observation,
      resolution: resolution(count: 1),
      capabilityAuthority: context.authority,
      capabilityHandle: context.handle,
      wallClockNow: wallClock,
      monotonicNowNanoseconds: 20
    )
    _ = try await context.ledger.recordDispatchOutcome(
      idempotencyKey: context.plan.idempotencyKey,
      outcome: outcome,
      monotonicNowNanoseconds: 20
    )
    return (context.ledger, context.plan)
  }
}
