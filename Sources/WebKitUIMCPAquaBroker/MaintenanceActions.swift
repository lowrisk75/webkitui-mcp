import Foundation
import WebKitUIMCPRuntime

/// Recovery an operator can trigger from the Status window. Kept as closures so the
/// window never reaches into the session registry, and so each action can be tested
/// without a running broker.
@MainActor
struct WebKitUIMaintenanceActions {
  let forceRender: () -> Void
  let clearBrowsingData: () -> Void
  /// Reports what actually happened. The previous signature could not say that it had
  /// done nothing, which is exactly what it did whenever another process held the lease.
  /// Asynchronous because eviction waits out a grace period the main thread must not.
  let releaseHostLease: (@escaping @MainActor @Sendable (HostLeaseEviction.Outcome) -> Void) -> Void
}
