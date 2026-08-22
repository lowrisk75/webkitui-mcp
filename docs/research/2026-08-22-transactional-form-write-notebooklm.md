# Transactional form writes — 2026-08-22

## Measured or source-backed

- The existing research packet reports Web Bench write success of 11.4–65.6%, versus 63–88% for reads. This is benchmark evidence, not a local measurement.
- The existing runtime already measures a negative result: macOS 27 `willSubmitForm` is present but does not fire for programmatic `requestSubmit()` in the tested WKWebView path.
- The existing transaction ledger records intent before dispatch, rejects already-satisfied postconditions, binds origin/target/capability/idempotency key, and never replays an indeterminate dispatch.
- NotebookLM returned no usable citations for its form-specific numeric claims. They are not adopted as evidence here.

## Conjectural or rejected

- NotebookLM recommended two `requestAnimationFrame` stability checks. Rejected: off-screen/inactive WebKit can suspend rAF, so host monotonic mutation quiescence remains the primitive.
- Network 200/201 is insufficient proof of the intended backend mutation and is not treated as a verified write by itself.
- Direct database/API verification is useful only when a site-specific trusted verifier exists; it cannot be a generic browser claim.
- The opportunity notebook found no documented novel safe form-write primitive. Its useful patterns—MCP elicitation, human credential handoff, and authority separate from tool visibility—are already represented in this architecture.

## Implementation target

- Add a bounded `fill` operation that re-resolves a fresh semantic locator, accepts only editable form controls, dispatches input/change events, and verifies the exact resulting field value before returning.
- Keep secrets out of the model path: password controls remain human-handoff only.
- Treat submit as a separate, human-confirmed transactional click with an explicit postcondition and existing no-replay receipt semantics; filling alone must never imply server commit.
- Counter-audit after implementation for framework-controlled inputs, autofill, validation, disabled/read-only fields, value leakage, stale references, and partial multi-field writes.

## Post-implementation counter-audit

- The first detailed NotebookLM request timed out after 60 seconds. A shorter retry returned three hypotheses with citations.
- **Locally mitigated:** semantic mimicry produces multiple candidates and fails closed; the action path also requires visibility and hit-testing. Same-document hostile replacement remains a general page-authority problem, not proof of target provenance.
- **Rejected for this implementation:** setting a value plus dispatching `input/change` does not synthesize an Enter keypress. Newlines are nevertheless rejected for `<input>` controls and tested; `<textarea>` remains multiline.
- **Measured locally:** a fill remains verified after its input handler replaces the physical node and inserts another interactive element, shifting the target from `e1` to `e2`. The semantic target-value key survives while the observation lease changes.
- **Open and explicit:** arbitrary site `input/change` handlers may autosave or submit. The generic runtime cannot prove that fill has no server side effect, so fill remains destructive, exact-value human-confirmed, and does not claim backend commit.

## Local measurements

- Confirmed fill with physical-node replacement and target shift `e1` → `e2`: verified in 0.505 s in the focused run.
- Confirmed native submit with a newly appearing exact semantic postcondition: passed in the focused test.
- Password fill, submit-as-click, and newline-in-input are rejected before confirmation/dispatch.
- Full arm64 debug gate: 12 server + 29 runtime + 61 core tests = 102 passed.
- Full arm64 release gate: 12 server + 29 runtime + 61 core tests = 102 passed.
- These are deterministic local fixtures, not end-to-end success measurements on third-party sites.
