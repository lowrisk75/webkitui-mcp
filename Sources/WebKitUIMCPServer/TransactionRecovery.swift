import WebKitUIMCPCore

/// Machine-readable follow-up calls carry the original session and key. They are
/// read-only suggestions, never a new action or an authorization to replay.
enum TransactionRecovery {
  static func guidance(
    sessionID: String, key: String, verification: TransactionVerification,
    dispatchState: String
  ) throws -> JSONValue {
    let receipt: TransactionReceipt
    let state: String
    switch verification {
    case .verified(let value):
      receipt = value
      state = "verified_ui_state"
    case .pending(let value):
      receipt = value
      state = "verification_pending"
    case .indeterminate(let value):
      receipt = value
      state = "postcondition_unproved"
    }
    let followUp: JSONValue = .object([
      "tool": .string("browser_transaction"),
      "arguments": .object([
        "session_id": .string(sessionID), "idempotency_key": .string(key),
        "operation": .string("reconcile"),
      ]),
    ])
    return .object([
      "dispatch_state": .string(dispatchState),
      "verification_state": .string(state),
      "postcondition_evidence": try .encoded(receipt.postconditionEvidence),
      "automatic_replay_allowed": .bool(false),
      "verification_proves_remote_save": .bool(false),
      "next_read": state == "verified_ui_state" ? .null : followUp,
      "if_still_unproved": .string(
        "Observe the current page and inspect an independent provider receipt or status. "
          + "A missing UI postcondition does not prove failure; do not create a new key to repeat the write."
      ),
    ])
  }
}
