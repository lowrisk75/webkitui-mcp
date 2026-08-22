import Foundation
import WebKitUIMCPCore

public struct WebKitTransactionResult: Sendable {
  public let action: WebKitActionResult
  public let verification: TransactionVerification
}

@MainActor
public final class WebKitTransactionCoordinator {
  private let runtime: WebKitRuntime
  private let ledger: TransactionalWriteLedger

  public init(runtime: WebKitRuntime, ledger: TransactionalWriteLedger = .init()) {
    self.runtime = runtime
    self.ledger = ledger
  }

  public func execute(
    plan: TransactionalWritePlan,
    operation: WebKitActionOperation,
    observation: WebKitPageObservation,
    capabilityAuthority: CapabilityAuthority,
    capabilityHandle: CapabilityHandle,
    verificationPollInterval: Duration = .milliseconds(20)
  ) async throws -> WebKitTransactionResult {
    let liveRecipe = try runtime.locatorRecipe(
      observationID: observation.observationID,
      elementID: plan.target.elementID
    )
    guard liveRecipe == plan.target else { throw WebKitRuntimeError.staleObservation }
    let transactionObservation = TransactionObservation(
      state: try observation.canonicalState(),
      completeness: .complete
    )
    _ = try await ledger.prepare(
      plan,
      observation: transactionObservation,
      capabilityAuthority: capabilityAuthority,
      capabilityHandle: capabilityHandle,
      wallClockNow: Date(),
      monotonicNowNanoseconds: DispatchTime.now().uptimeNanoseconds
    )

    let resolution = try await runtime.preflightResolution(
      observationID: observation.observationID,
      elementID: plan.target.elementID
    )
    _ = try await ledger.beginDispatch(
      idempotencyKey: plan.idempotencyKey,
      observation: transactionObservation,
      resolution: resolution,
      capabilityAuthority: capabilityAuthority,
      capabilityHandle: capabilityHandle,
      wallClockNow: Date(),
      monotonicNowNanoseconds: DispatchTime.now().uptimeNanoseconds
    )

    let action: WebKitActionResult
    let dispatchedAtNanoseconds: UInt64
    do {
      action = try await runtime.perform(
        observationID: observation.observationID,
        elementID: plan.target.elementID,
        operation: operation
      )
      dispatchedAtNanoseconds = DispatchTime.now().uptimeNanoseconds
      _ = try await ledger.recordDispatchOutcome(
        idempotencyKey: plan.idempotencyKey,
        outcome: .dispatched,
        monotonicNowNanoseconds: dispatchedAtNanoseconds
      )
    } catch let error as WebKitRuntimeError {
      let knownNotDispatched: Bool
      switch error {
      case .staleObservation, .unknownElement, .targetNotUnique, .targetNotActionable,
        .targetGeometryChanged, .sensitiveInputRequiresHuman:
        knownNotDispatched = true
      default:
        knownNotDispatched = false
      }
      _ = try await ledger.recordDispatchOutcome(
        idempotencyKey: plan.idempotencyKey,
        outcome: knownNotDispatched ? .notDispatched : .unknown,
        monotonicNowNanoseconds: DispatchTime.now().uptimeNanoseconds
      )
      throw error
    } catch {
      _ = try await ledger.recordDispatchOutcome(
        idempotencyKey: plan.idempotencyKey,
        outcome: .unknown,
        monotonicNowNanoseconds: DispatchTime.now().uptimeNanoseconds
      )
      throw error
    }

    let (verificationDeadline, overflow) = dispatchedAtNanoseconds.addingReportingOverflow(
      plan.verificationTimeoutNanoseconds
    )
    guard !overflow else { throw TransactionError.deadlineOverflow }

    while true {
      do {
        let latest = try await runtime.observe()
        let verification = try await ledger.verify(
          idempotencyKey: plan.idempotencyKey,
          observation: TransactionObservation(
            state: try latest.canonicalState(),
            completeness: .complete
          ),
          monotonicNowNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
        if case .pending = verification {
          try await Task.sleep(for: verificationPollInterval)
          continue
        }
        return WebKitTransactionResult(action: action, verification: verification)
      } catch is WebKitRuntimeError {
        let now = DispatchTime.now().uptimeNanoseconds
        if now >= verificationDeadline {
          let verification = try await ledger.verify(
            idempotencyKey: plan.idempotencyKey,
            observation: TransactionObservation(
              state: transactionObservation.state,
              completeness: .partial
            ),
            monotonicNowNanoseconds: now
          )
          return WebKitTransactionResult(action: action, verification: verification)
        }
        try await Task.sleep(for: verificationPollInterval)
      }
    }
  }

  public func receipt(idempotencyKey: String) async throws -> TransactionReceipt {
    try await ledger.receipt(idempotencyKey: idempotencyKey)
  }

  /// Re-observes an indeterminate write and may prove its postcondition later.
  /// It never dispatches or retries the action.
  public func reconcile(idempotencyKey: String) async throws -> TransactionVerification {
    let observation = try await runtime.observe()
    return try await ledger.reconcile(
      idempotencyKey: idempotencyKey,
      observation: TransactionObservation(
        state: try observation.canonicalState(), completeness: .complete),
      monotonicNowNanoseconds: DispatchTime.now().uptimeNanoseconds
    )
  }
}
