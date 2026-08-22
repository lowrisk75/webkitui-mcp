import Foundation
import Testing
import WebKitUIMCPCore

@testable import WebKitUIMCPRuntime

@Suite("WebKit transactional coordinator", .serialized)
@MainActor
struct WebKitTransactionCoordinatorTests {
  @Test("A dispatched click is successful only after its postcondition")
  func verifiedClick() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <button aria-label="Save profile" onclick="this.setAttribute('aria-label', 'Saved')">
        Save
      </button>
      """,
      baseURL: URL(string: "https://fixture.invalid/"),
      timeout: .seconds(2),
      quietWindow: .milliseconds(40)
    )
    let observation = try await runtime.observe()
    let origin = SecurityOrigin(scheme: "https", host: "fixture.invalid")
    let before = try ProvenancedText(
      text: "Save profile",
      source: ProvenanceSource(
        classification: .firstPartySiteContent,
        documentID: observation.documentID,
        frameID: "main",
        securityOrigin: origin
      )
    )
    let after = try ProvenancedText(
      text: "Saved",
      source: ProvenanceSource(
        classification: .firstPartySiteContent,
        documentID: observation.documentID,
        frameID: "main",
        securityOrigin: origin
      )
    )
    let nameKey = ObservationFieldKey(
      frameID: "main",
      elementID: "e1",
      field: "@accessible_name"
    )
    let plan = try TransactionalWritePlan(
      idempotencyKey: "save-profile-1",
      target: observation.elements[0].locatorRecipe,
      requiredCapability: .activateElement,
      inputProvenance: [.userIntent],
      expectedOrigin: origin,
      preconditions: [
        .entryValueDigest(nameKey, try ObservationPredicate.digest(of: before))
      ],
      postconditions: [
        .entryValueDigest(nameKey, try ObservationPredicate.digest(of: after))
      ],
      verificationTimeoutNanoseconds: 1_000_000_000
    )
    let authority = CapabilityAuthority()
    let handle = await authority.issue(
      CapabilityScope(
        actions: [.activateElement],
        origins: [origin],
        acceptedInputProvenance: [.userIntent],
        expiresAt: Date().addingTimeInterval(60)
      )
    )
    let coordinator = WebKitTransactionCoordinator(runtime: runtime)

    let result = try await coordinator.execute(
      plan: plan,
      operation: .click,
      observation: observation,
      capabilityAuthority: authority,
      capabilityHandle: handle
    )
    #expect(!result.action.trustedUserGesture)
    guard case .verified(let receipt) = result.verification else {
      Issue.record("Expected a verified receipt")
      return
    }
    #expect(receipt.phase == .verified)
    #expect(receipt.postconditionEvidence.map(\.result) == [.satisfied])
  }

  @Test("A postcondition already true cannot be misattributed to a new click")
  func preexistingPostconditionRejected() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      "<button aria-label='Saved'>Save</button>",
      baseURL: URL(string: "https://fixture.invalid/"),
      timeout: .seconds(2),
      quietWindow: .milliseconds(40)
    )
    let observation = try await runtime.observe()
    let origin = SecurityOrigin(scheme: "https", host: "fixture.invalid")
    let saved = try ProvenancedText(
      text: "Saved",
      source: ProvenanceSource(
        classification: .firstPartySiteContent,
        documentID: observation.documentID,
        frameID: "main",
        securityOrigin: origin
      )
    )
    let key = ObservationFieldKey(
      frameID: "main",
      elementID: "e1",
      field: "@accessible_name"
    )
    let plan = try TransactionalWritePlan(
      idempotencyKey: "already-saved",
      target: observation.elements[0].locatorRecipe,
      requiredCapability: .activateElement,
      inputProvenance: [.userIntent],
      expectedOrigin: origin,
      preconditions: [],
      postconditions: [
        .entryValueDigest(key, try ObservationPredicate.digest(of: saved))
      ],
      verificationTimeoutNanoseconds: 1_000_000_000
    )
    let authority = CapabilityAuthority()
    let handle = await authority.issue(
      CapabilityScope(
        actions: [.activateElement],
        origins: [origin],
        acceptedInputProvenance: [.userIntent],
        expiresAt: Date().addingTimeInterval(60)
      )
    )

    await #expect(throws: TransactionError.postconditionAlreadySatisfied) {
      try await WebKitTransactionCoordinator(runtime: runtime).execute(
        plan: plan,
        operation: .click,
        observation: observation,
        capabilityAuthority: authority,
        capabilityHandle: handle
      )
    }
  }

  @Test("A same-page SPA click can prove newly appearing semantic status text")
  func samePageSemanticPostcondition() async throws {
    let runtime = WebKitRuntime()
    _ = try await runtime.loadHTML(
      """
      <button aria-label="Save profile" onclick="
        const status = document.createElement('div');
        status.setAttribute('role', 'status');
        status.textContent = 'Saved locally';
        document.body.appendChild(status);
      ">Save</button>
      """,
      baseURL: URL(string: "https://fixture.invalid/settings"),
      timeout: .seconds(2),
      quietWindow: .milliseconds(40)
    )
    let observation = try await runtime.observe()
    let origin = SecurityOrigin(scheme: "https", host: "fixture.invalid")
    let plan = try TransactionalWritePlan(
      idempotencyKey: "same-page-save-1",
      target: observation.elements[0].locatorRecipe,
      requiredCapability: .activateElement,
      inputProvenance: [],
      expectedOrigin: origin,
      preconditions: [],
      postconditions: [
        .anyEntryTextDigest(
          [.accessibleName, .label, .text, .value],
          ObservationPredicate.textDigest(of: "Saved locally")
        )
      ],
      verificationTimeoutNanoseconds: 1_000_000_000
    )
    let authority = CapabilityAuthority()
    let handle = await authority.issue(
      CapabilityScope(
        actions: [.activateElement], origins: [origin], acceptedInputProvenance: [],
        expiresAt: Date().addingTimeInterval(60)))

    let result = try await WebKitTransactionCoordinator(runtime: runtime).execute(
      plan: plan,
      operation: .click,
      observation: observation,
      capabilityAuthority: authority,
      capabilityHandle: handle
    )

    guard case .verified(let receipt) = result.verification else {
      Issue.record("Expected a verified same-page write")
      return
    }
    #expect(receipt.postconditionEvidence.map(\.result) == [.satisfied])
  }
}
