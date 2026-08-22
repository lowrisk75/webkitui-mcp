# 2026-08-21 — Transactional writes counter-audit

## Questions asked

- `WebKITUI MPC`: measured evidence for preconditions, postconditions,
  idempotency, receipts, premature success, and crash recovery.
- `WebKITUI MPC`: failure analysis of the proposed state machine.
- `WebKITUI MPC`: missed measurable opportunities.
- `LLM`: missed opportunities. The answer was settled but returned **no
  citations**, so it is not evidence.

## Measured or source-verified

- Web Bench's published pool is 5,750 tasks on 452 sites; 2,454 tasks were open
  sourced. The released dataset has 1,580 READ, 512 CREATE, 173 UPDATE, 149
  DELETE and 40 FILE_MANIPULATION tasks. The authors identify incomplete
  execution and wrong-element selection as recurring write failures.
  Sources: [Skyvern methodology](https://www.skyvern.com/blog/web-bench-a-new-way-to-compare-ai-browser-agents/),
  [Halluminate dataset card](https://huggingface.co/datasets/Halluminate/WebBench).
- The released action tasks are side-effectful and cannot be verified merely
  from an agent's final text snapshot. This limits claims based on text-only
  judging. Source: [Lightpanda WebBench harness](https://github.com/lightpanda-io/agent-benchmarks/blob/main/src/agent_benchmarks/webbench/README.md).
- HTTP defines PUT, DELETE, and safe methods as idempotent. A client should not
  automatically retry a non-idempotent request unless it knows the operation is
  idempotent or can detect that the original request was never applied.
  Source: [RFC 9110 section 9.2.2](https://www.rfc-editor.org/rfc/rfc9110.html#section-9.2.2).
- macOS 27 exposes the beta
  `webView(_:willSubmitForm:submissionHandler:)` delegate. The API is real; its
  effectiveness as an agent safety mechanism is not measured.
  Source: [Apple documentation](https://developer.apple.com/documentation/webkit/wknavigationdelegate/webview(_:willsubmitform:submissionhandler:)).
- The primary notebook returned settled, cited answers. It found no published
  ablation that quantifies the independent benefit of browser-agent
  preconditions, postconditions, local idempotency ledgers, receipts, or forced
  WebContent-process recovery.

## Conjectural or unverified

- A local idempotency key prevents duplicate *local dispatch attempts*, but
  cannot make an arbitrary web `POST` exactly-once. Server cooperation or an
  authoritative reconciliation query is required.
- A browser event accepted by WebKit is not proof of a server-side commit.
- A host crash between “begin dispatch” and the adapter's outcome creates an
  unavoidable ambiguity. Fail-closed reconciliation is safer than replay.
- The primary notebook proposed form interception, stale-address survival,
  background write latency, provenance escape, and crash recovery as new
  metrics. These are research hypotheses, not measured gains.
- The second notebook suggested cross-tab state merging, cache-aligned rollback,
  checkpoint I/O, and cooperative context garbage collection. With zero
  citations returned, none is used to justify this implementation.

## Implementation decisions after counter-audit

- State machine: `prepared → dispatching → dispatched → verified`; any unknown
  dispatch or expired verification becomes `indeterminate`.
- Only an adapter-certified `not_dispatched` outcome permits another attempt.
- Capability, live origin, preconditions, recipe identity, and locator
  uniqueness are rechecked immediately before dispatch.
- Missing data in a partial observation is `unknown`, never proof of absence.
- Receipts contain canonical hashes and predicate results, not page strings or
  secrets.
- No rollback or exactly-once claim is made.
