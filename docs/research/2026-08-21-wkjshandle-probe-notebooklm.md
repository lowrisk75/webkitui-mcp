# WKJSHandle probe — NotebookLM review (2026-08-21)

Notebook: **WebKITUI MPC** (private notebook ID redacted).

Questions were sent with explicit consent and `sensitivity: internal` about
documented behavior, probe blind spots, and unmeasured opportunities.

## Notebook result

- The first detailed query settled without a usable answer or citations; a
  shorter reformulation was required.
- The notebook correctly highlighted world/frame/navigation boundaries and the
  absence of published WKJSHandle performance or stability baselines.
- It suggested measuring lifetime/memory, dereference latency, background
  throttling, process termination, and cross-world/frame behavior.

## Primary-source correction

The notebook claimed that replacing or detaching a DOM node invalidates its
`WKJSHandle`. The macOS 27 SDK header says instead that the referenced JavaScript
object is protected from garbage collection for the handle's lifetime. A
detached handle may therefore remain valid while becoming semantically stale.
That claim remains unverified because handle creation currently fails on the
local beta runtime.

The SDK explicitly documents two safe invalidation boundaries:

- using the handle in another content world yields JavaScript `undefined`;
- using it in another frame or after that frame navigates yields `undefined`.

Notebook statements about process-termination behavior and hard invalidation
remain conjectural until directly measured or documented by Apple.
