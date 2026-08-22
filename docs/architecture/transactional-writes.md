# Transactional writes

`TransactionalWriteLedger` is a fail-closed state machine around a browser
write. It provides local transition integrity; it does not turn an arbitrary
website into a transactional database.

## Contract

1. `prepare` verifies the current origin, capability, and deterministic
   preconditions.
2. `beginDispatch` repeats those checks and additionally requires a fresh,
   unique resolution for the exact locator recipe.
3. The adapter reports one of `not_dispatched`, `dispatched`, or `unknown`.
4. A dispatched action is successful only after every deterministic
   postcondition is satisfied.
5. Timeout, process interruption, partial evidence, or unknown dispatch yields
   `indeterminate`. That state can be reconciled, never silently replayed.

## Evidence rules

- Predicates address canonical observation fields and compare provenance-aware
  value digests.
- A semantic-text predicate can match exact digests across bounded observable
  fields without depending on an ephemeral element ID. `prepare` rejects it if
  the same text was already present, preventing reuse of stale success UI.
- Absence is provable only in an observation marked `complete`.
- Deadlines use caller-supplied monotonic nanoseconds. Wall time is used only by
  the existing capability authority.
- Receipts store observation and plan digests, transition times, and tri-state
  predicate evidence. They contain no observed page text.

## Known boundary

The current ledger is in-memory. It survives a WebContent-process replacement
only while the native host remains alive. Durable atomic persistence and the
server-side application proof remain required before claiming host-crash
recovery or backend commit. Semantic UI text proves browser-visible state only.
