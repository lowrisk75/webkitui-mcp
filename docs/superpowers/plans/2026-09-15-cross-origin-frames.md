# Cross-origin frames — Implementation Plan

**Goal:** Observe and operate the parts of an embedded cross-origin document that
public WebKit can reach without weakening same-origin isolation, inventing frame
identity, or claiming a trusted pointer gesture WebKit cannot prove.

**Status:** Tasks 1–4 implemented locally; Task 5 has partial local adversarial
measurement. The restricted-authentication child contract (refusal, handoff, resume) is
measured offline against a loopback-resolved `idmsa.apple.com` frame; genuine provider
frames and hosted journeys remain open. No
commit, installation, or runtime deployment is implied by this document.

## Verified public boundary

- A document-start `WKUserScript` already runs in every frame inside the named
  isolated `WKContentWorld`.
- A message sent from that world arrives with the exact `WKFrameInfo`. The public
  frame object exposes its current request, security origin, main-frame flag, and
  owning web view.
- `evaluateJavaScript(_:in:in:)` and `callAsyncJavaScript(_:arguments:in:in:)`
  can execute in that exact `WKFrameInfo` without asking the top-level document to
  cross the same-origin boundary.
- `WKFrameInfo` exposes no frame rectangle or public transform to top-level WebKit
  coordinates. A cross-origin child also cannot read its parent `frameElement`.
  Therefore no implementation may derive a native mouse target from frame order,
  URL matching, or guessed offsets and report it as trusted.

## Global invariants

- The page world never supplies a frame handle, origin, observation record, locator,
  or trust receipt. Registration and evaluation stay in the isolated world and
  native process.
- Every frame-derived string carries `THIRD_PARTY_EMBED` provenance plus its
  sanitized security origin. Paths, queries, fragments, cookies, storage, headers,
  and credentials never become frame identity or diagnostics.
- Frame identity is an opaque, document-scoped native capability. DOM index,
  `iframe.src`, URL, and frame name are corroboration only and never break a tie.
- Retained native frame registrations never outlive main-frame navigation or WebContent
  termination and cannot be used while human control is active. Any element or frame
  reference exported by an observation is separately session- and observation-scoped;
  it expires on reconnect, handoff, or the next observation. A subframe navigation
  forces a fresh observation. Because public WebKit exposes no stable subframe ID with
  which to expire one exported subset safely, the current observation lease is
  invalidated as a whole.
- The current global element, field-character, payload, time, and pagination bounds
  apply after main-frame and subframe results are combined. Failure to read one frame
  is explicit; it never turns into an absent-control claim.
- Password, token-like, authentication, payment-card, OTP, and other sensitive values
  remain withheld. A restricted authentication frame produces a human/full-browser
  requirement, not semantics.
- There is no silent dispatch downgrade. If native pointer geometry is unavailable,
  native pointer mode refuses with a named reason. Any supported JavaScript dispatch
  remains explicitly untrusted in the confirmation, result, and receipt.
- This work does not solve cross-origin dataflow through model-generated values. That
  is the separate origin-taint gap described in the security research.

## Task 1: Register real frame capabilities

**Implemented locally (2026-09-15).** The registry is capped at 32 retained frame
handles, reports dropped registrations, and revokes them on a new main document or
WebContent termination. Tests use two byte-identical child URLs to prove native
identity, evaluate a fixed probe through each retained frame while the parent remains
blocked by same-origin policy, remove the frames to prove stale handles become
unavailable, and flood the registry to prove its bound.

Add a second isolated-world message handler whose document-start script announces
each frame. Retain a bounded registry of `WKFrameInfo` objects on `MainActor`, keyed by
an opaque document-scoped identifier minted by native code. Never accept a page-provided
identifier as authority.

Required tests:

- A real loopback page embedding a different loopback origin yields a non-main
  `WKFrameInfo` whose security origin is the child origin.
- Code evaluated through that retained frame sees the child document, while a
  top-level `contentDocument` read remains blocked.
- Two frames with the same URL remain distinct capabilities.
- Main-frame navigation and WebContent termination revoke every retained frame.
- Registry overflow and a frame that disappears are explicit and bounded.

## Task 2: Publish cross-origin semantics without duplication

**Implemented locally (2026-09-15).** The reusable collector now runs once from the
main document and separately in registered frames the main walk could not read. Native
code applies one filter-aware global page slice, gives all frame-derived strings
`THIRD_PARTY_EMBED` provenance, publishes only a sanitized origin plus the frame-local
coordinate space, and retains the opaque frame capability outside every payload.
Individual frame evaluation is bounded to two seconds; failure and registry overflow
make the observation explicitly incomplete. At this stage cross-origin controls
refused every action before confirmation or dispatch; Task 4 added bounded modes.
Tests cover
same-origin deduplication, global pagination and filters, hostile page-world identity
forgery, sensitive payment/OTP/state byte canaries, bounded overflow, and the MCP
refusal contract.

Split the observation script into a reusable frame-local collector. The main-frame
collector continues walking same-origin descendants. Native code evaluates the same
collector separately only for registered cross-origin frames, then applies one global
filter, element bound, and wire budget.

Each element gains an internal frame capability reference and publishes only a
sanitized `frameOrigin` plus `frameIsMain`. Cross-origin strings use
`THIRD_PARTY_EMBED`; same-origin strings retain their existing provenance. A frame
evaluation timeout, navigation race, process loss, or decode error increments an
explicit unreadable-frame result and makes the observation incomplete.

Required tests:

- A visible cross-origin button is present, names its child origin, and every string
  encoded from it has third-party provenance.
- The same-origin fixture remains present exactly once.
- Role/name filters run before the global bound across frame groups.
- Pagination never duplicates or loses an unchanged target.
- A hostile child cannot forge another origin, main-frame provenance, frame ID, or
  native trust receipt through the page world.
- Password and opaque token canaries from a child occur in no encoded observation,
  canonical state, or locator recipe.

## Task 3: Re-resolve inside the exact frame

**Implemented locally (2026-09-16).** A provenance-private locator recipe now stays in
the native target record beside the opaque frame capability; the public recipe remains
free of unlabelled third-party strings. Post-confirmation runtime entry re-evaluates the
private recipe in that exact `WKFrameInfo`, with an atomic isolated-world guard over the
capability and sanitized origin, and rechecks document generation, semantics,
cardinality, observed control state, and frame-local geometry. A new child document,
missing frame, guard mismatch, semantic mismatch, ambiguity, or geometry change
dispatches nothing. Task 3 authorizes no action mode: the checked target still returns
the existing named cross-origin refusal until Task 4. Tests prove semantic recovery
after a node replacement, staleness across a byte-identical child navigation, isolation
between two same-URL frames, and no dispatch after a child-origin change.

Extend the private target record—not the public element ID—with its frame capability.
After confirmation, re-evaluate the locator recipe in that same live `WKFrameInfo` and
recheck frame origin, document generation, semantics, uniqueness, state, and geometry.
If the frame navigated, vanished, changed origin, or now resolves differently, dispatch
nothing and require a fresh observation.

Required tests:

- Replacing a child node with the same semantics follows the existing semantic
  recovery rules.
- Replacing or navigating the frame after observation is stale, not a positional hit.
- Duplicate controls in two same-URL frames never cross-resolve.
- A child-origin change during confirmation is refused before dispatch.

## Task 4: Honest action modes and human recovery

**Implemented locally (2026-09-16).** The exact retained frame executes confirmed
hover and select-option as untrusted JavaScript. Non-sensitive native key/fill run only
with server-owned confirmation naming the child origin and an isolated-world receipt
bound to that frame capability, native origin, physical control, event type, and
`isTrusted`. A missing receipt is indeterminate. Native pointer refuses with
`cross_origin_native_geometry_unavailable` before confirmation, and the same live
embedded document survives handoff and confirmed resume. The public tag-only recipe
now carries a keyed, document-scoped opaque semantic identity, allowing transaction
verification to distinguish multiple controls of the same tag without publishing
third-party labels or a guessable digest of them. The observation lists eligible
frame modes explicitly while retaining the native-pointer `actionable=false` reason.
Targeted runtime and MCP tests and the final 493-test local suite passed; the
remaining Task 5 external proof is a separate gate.

First support the operations that can remain truthful in a frame-local execution:
hover and select-option as explicitly untrusted JavaScript dispatches, with their
existing postconditions evaluated in the exact frame. Prototype focus plus AppKit key
delivery for keyboard activation and public text insertion; expose it only if the
isolated child frame measures the matching trusted DOM receipt.

Native mouse click remains unavailable until a public, measured coordinate transform
exists. It returns `cross_origin_native_geometry_unavailable`, `dispatched=false`, and
remediation to use the live human handoff. Sensitive/payment/authentication controls
always take the human/full-browser route.

Required tests:

- Untrusted frame hover/select say untrusted before and after dispatch.
- A native key/fill path is enabled only when the child records the exact trusted
  receipt; absent or mismatched receipts are indeterminate.
- Native pointer click never calls the current top-level coordinate path.
- Following the reported handoff route presents the same live embedded document and
  returns only through the existing confirmed resume flow.

## Task 5: Adversarial proof and product truth

**Partially measured (2026-09-16).** Three new loopback corpus fixtures cover hostile
third-party text, attempted page-world registration/gesture forgery, encoded URL and
sensitive-value canaries, nested origins, and duplicate child URLs. Runtime tests cover
navigation races and registry flooding. The dated
[measurement](../../research/2026-09-16-cross-origin-frame-boundary-measurement.md)
records the offline restricted-authentication child test added on 2026-09-16
(`restrictedAuthenticationChildFrameHandoffAndResume`: explicit refusal naming the
child origin, human handoff, resume only after the sign-in document is left behind, no
query canary) and keeps genuine provider frames and hosted workflows explicitly open;
offline authentication tests are not substituted for a provider journey.

Add frame fixtures for prompt injection, forged handler messages, duplicate origins,
navigation races, restricted authentication, payment-like sensitive fields, payload
flooding, query/fragment canaries, and nested cross-origin frames. Search encoded bytes
for every secret canary.

Update the README, tool descriptions, architecture document, capability matrix, and
dated measurement with exactly what passed. Do not claim hosted checkout support from
observation alone, do not call an untrusted dispatch native, and do not call a human
handoff automated completion.

Final gate:

```sh
swift test --arch arm64 --no-parallel --skip hostExclusiveSession
xcrun swift-format lint --strict --recursive Sources Tests Package.swift
git diff --check
```

No commit, install, signing, broker restart, provider mutation, or publication is part
of this plan without separate explicit authorization.
