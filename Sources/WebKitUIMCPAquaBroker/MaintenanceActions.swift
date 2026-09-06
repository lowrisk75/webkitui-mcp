import Foundation

/// Recovery an operator can trigger from the Status window. Kept as closures so the
/// window never reaches into the session registry, and so each action can be tested
/// without a running broker.
@MainActor
struct WebKitUIMaintenanceActions {
  let forceRender: () -> Void
  let clearBrowsingData: () -> Void
  let releaseHostLease: () -> Void
}
