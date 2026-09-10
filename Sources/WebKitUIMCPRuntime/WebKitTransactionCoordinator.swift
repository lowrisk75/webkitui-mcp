import Foundation
import WebKitUIMCPCore

public struct WebKitTransactionResult: Sendable {
  public let action: WebKitActionResult
  public let verification: TransactionVerification
}

public enum WebKitTransactionExecutionError: Error, Sendable {
  case uncertainDispatch(
    verification: TransactionVerification,
    underlyingDescription: String
  )
}

@MainActor
public final class WebKitTransactionCoordinator {
  private let runtime: WebKitRuntime
  private let ledger: TransactionalWriteLedger

  /// How long a settled state is still accepted after the verification deadline. The
  /// deadline decides when to stop waiting; it must not decide whether the write
  /// happened. Reconciliation can prove a late postcondition, never authorise a replay.
  private let reconciliationGrace: Duration

  public init(
    runtime: WebKitRuntime,
    ledger: TransactionalWriteLedger = .init(),
    reconciliationGrace: Duration = .seconds(3)
  ) {
    self.runtime = runtime
    self.ledger = ledger
    self.reconciliationGrace = reconciliationGrace
  }

  public func execute(
    plan: TransactionalWritePlan,
    operation: WebKitActionOperation,
    dispatchMode: WebKitActionDispatchMode = .javascript,
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
        operation: operation,
        dispatchMode: dispatchMode
      )
      dispatchedAtNanoseconds = DispatchTime.now().uptimeNanoseconds
      _ = try await ledger.recordDispatchOutcome(
        idempotencyKey: plan.idempotencyKey,
        outcome: .dispatched,
        monotonicNowNanoseconds: dispatchedAtNanoseconds
      )
    } catch let error as WebKitRuntimeError {
      let outcome = Self.dispatchOutcome(for: error)
      _ = try await ledger.recordDispatchOutcome(
        idempotencyKey: plan.idempotencyKey,
        outcome: outcome,
        monotonicNowNanoseconds: DispatchTime.now().uptimeNanoseconds
      )
      if outcome.rawValue == DispatchOutcome.unknown.rawValue {
        let verification = try await reconcileUncertainDispatch(
          idempotencyKey: plan.idempotencyKey,
          fallbackObservation: transactionObservation)
        throw WebKitTransactionExecutionError.uncertainDispatch(
          verification: verification,
          underlyingDescription: String(describing: error))
      }
      throw error
    } catch {
      _ = try await ledger.recordDispatchOutcome(
        idempotencyKey: plan.idempotencyKey,
        outcome: .unknown,
        monotonicNowNanoseconds: DispatchTime.now().uptimeNanoseconds
      )
      let verification = try await reconcileUncertainDispatch(
        idempotencyKey: plan.idempotencyKey,
        fallbackObservation: transactionObservation)
      throw WebKitTransactionExecutionError.uncertainDispatch(
        verification: verification,
        underlyingDescription: String(describing: type(of: error)))
    }

    let (verificationDeadline, overflow) = dispatchedAtNanoseconds.addingReportingOverflow(
      plan.verificationTimeoutNanoseconds
    )
    guard !overflow else { throw TransactionError.deadlineOverflow }

    while true {
      do {
        let latest = try await runtime.observe(hydrationTimeout: .zero)
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
        // The deadline decides when to stop waiting, not whether the write happened.
        // A page that settles a moment late was being reported unsatisfied while the
        // very next observation showed the change — and a client that believes it
        // failed retries, which on a menu closes what the first click opened. Read the
        // page once more before concluding. Reconciliation can prove a late
        // postcondition; it never authorises a replay.
        if case .indeterminate = verification {
          return WebKitTransactionResult(
            action: action,
            verification: try await reconcileUntilSettled(
              idempotencyKey: plan.idempotencyKey,
              fallbackObservation: transactionObservation,
              pollInterval: verificationPollInterval))
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

  static func dispatchOutcome(for error: WebKitRuntimeError) -> DispatchOutcome {
    switch error {
    case .staleObservation, .unknownElement, .targetNotUnique, .targetNotFound,
      .operationUnsupportedForControl,
      .targetGeometryChanged, .sensitiveInputRequiresHuman, .handoffSurfaceUnavailable,
      // A panel was already open, so the gesture was refused before anything reached
      // the page. The four answer-side refusals never dispatch either.
      .javaScriptDialogPending, .noPendingJavaScriptDialog, .staleJavaScriptDialog,
      .javaScriptDialogValueRequired, .javaScriptDialogValueUnsupported,
      // A key that cannot be mapped, or a chord this app's own menu claims, is refused
      // while the keyboard is still idle. Nothing reached the page.
      .keyCodeUnavailable, .keyChordReservedByApplicationMenu, .keyModifierChangesCharacter,
      // An option label that names two options or none is refused while the control is
      // still untouched, so nothing reached the page.
      .optionLabelNotUnique:
      .notDispatched
    case .targetNotActionable, .nativeGestureReceiptUnavailable,
      .webContentProcessTerminated, .malformedInstrumentationResult, .noDocument,
      .navigationFailed, .navigationTimedOut, .networkBoundaryDenied,
      .unsupportedURLScheme, .crossOriginRedirectRequiresHuman,
      .invalidQuietWindow, .invalidCredentialOrigin, .invalidCredentialBinding,
      .invalidCredentialSecret, .humanControlActive, .authenticationOriginRequiresHuman,
      .noPendingCrossOriginNavigation, .invalidControlTransition,
      .downloadInProgress, .downloadCancelled, .downloadReceiptTimedOut,
      .unsupportedDownload, .downloadHTTPFailure, .downloadFailed,
      // The gesture landed — it is what opened the panel — and then the page stopped
      // running, so its effect is exactly as unknown as a dispatch that never verified.
      .javaScriptDialogOpenedByAction,
      // The selection was dispatched and the re-resolved control does not agree. The
      // gesture landed; what it did is unknown, which is not the same as refused.
      .selectedOptionMismatch:
      .unknown
    }
  }

  /// Nine consecutive App Store Connect actions were reported unsatisfied while the
  /// next observation showed every one had taken effect: a heavy single-page app can
  /// settle just after a five second budget. A client that believes it failed retries,
  /// and on a menu the second click undoes the first, so a false negative here is the
  /// one failure in this system that can corrupt a remote page.
  private func reconcileUntilSettled(
    idempotencyKey: String,
    fallbackObservation: TransactionObservation,
    pollInterval: Duration
  ) async throws -> TransactionVerification {
    let deadline = ContinuousClock.now + reconciliationGrace
    var verification = try await reconcileUncertainDispatch(
      idempotencyKey: idempotencyKey, fallbackObservation: fallbackObservation)
    while case .indeterminate = verification, ContinuousClock.now < deadline {
      try await Task.sleep(for: pollInterval)
      verification = try await reconcileUncertainDispatch(
        idempotencyKey: idempotencyKey, fallbackObservation: fallbackObservation)
    }
    return verification
  }

  private func reconcileUncertainDispatch(
    idempotencyKey: String,
    fallbackObservation: TransactionObservation
  ) async throws -> TransactionVerification {
    do {
      let current = try await runtime.observe(hydrationTimeout: .zero)
      return try await ledger.reconcile(
        idempotencyKey: idempotencyKey,
        observation: TransactionObservation(
          state: try current.canonicalState(), completeness: .complete),
        monotonicNowNanoseconds: DispatchTime.now().uptimeNanoseconds)
    } catch {
      return try await ledger.reconcile(
        idempotencyKey: idempotencyKey,
        observation: TransactionObservation(
          state: fallbackObservation.state, completeness: .partial),
        monotonicNowNanoseconds: DispatchTime.now().uptimeNanoseconds)
    }
  }

  /// Re-observes an indeterminate write and may prove its postcondition later.
  /// It never dispatches or retries the action.
  public func reconcile(idempotencyKey: String) async throws -> TransactionVerification {
    let observation = try await runtime.observe(hydrationTimeout: .zero)
    return try await ledger.reconcile(
      idempotencyKey: idempotencyKey,
      observation: TransactionObservation(
        state: try observation.canonicalState(), completeness: .complete),
      monotonicNowNanoseconds: DispatchTime.now().uptimeNanoseconds
    )
  }
}
