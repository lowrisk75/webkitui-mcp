# Cross-origin frame boundary — local measurement

Measured on 2026-09-16 against branch `main`, base `0979da7`, plus the preserved
uncommitted worktree. This is a local loopback/WebKit contract test, not a hosted
checkout, installed-app, or provider journey.

## What passed

- A registered child supplies bounded semantics with `THIRD_PARTY_EMBED` provenance,
  a sanitized origin, and frame-local geometry. A nested grandchild appears once with
  its own origin; two byte-identical child URLs retain distinct native identities.
- Child-page prompt text remains attributed to third-party content. Page-world attempts
  to set the frame capability/origin and post registration or gesture messages do not
  yield forged identity or trust. Query, fragment, payment-card, state, and OTP canaries
  occur in no encoded observation or canonical state. The server removes locator
  recipes from its wire payload; the internal public recipe exposes only a tag and a
  keyed, document-scoped opaque identity, not third-party semantic clauses.
- Runtime and MCP tests drive frame-local hover/select as untrusted JavaScript, and
  native key/fill only after an exact child-frame `isTrusted` receipt. A missing receipt
  is indeterminate. A native pointer operation returns
  `cross_origin_native_geometry_unavailable`, `dispatched=false` and a live handoff
  route before confirmation. The handoff/resume test preserves the embedded document.
- A restricted-authentication child frame (`idmsa.apple.com` embedded by an
  unrelated parent) turns every agent surface into an explicit
  `authenticationOriginRequiresHuman` refusal naming the child origin, with
  `humanHandoffRequired` as classification. Human handoff and step completion proceed;
  resume is refused while the frame is present and accepted once the human's sign-in
  leaves the document behind through a top-level navigation. The resumed observation
  is main-frame only and no query-state canary appears in the result, status, or
  observation.
- Transaction verification distinguishes two same-tag controls in one child; it does
  not claim a trusted gesture without the receipt or a successful fill merely because
  the native event was sent. `frameActionModes` names eligible attempts separately
  from the pointer-specific `actionable=false` state. Sensitive controls list no modes.

The dedicated cross-origin adversarial suite contains **3 new deterministic tests**:
hostile child strings and byte canaries, nested origins, and duplicate child URLs.
The previously existing frame tests cover registry overflow, global pagination,
same-URL navigation staleness, origin changes, replacement recovery and same-URL
duplicate-frame resolution. The relevant MCP tests cover refusal before confirmation,
child-origin confirmation, trust state, and verified writes.

The first MCP native-text test caught a real attribution defect: the tag-only public
recipe gave two child `<input>` controls the same verification identity. The gesture
had a trusted receipt but the postcondition stayed indeterminate; a blank input also
had no `@value` entry for the old precondition. The keyed opaque identity and a
presence precondition for an untouched embedded input fixed those two cases. The test
now verifies both key and fill against the exact semantic target.

## Limits and remaining gates

- The restricted-authentication child contract is now measured offline: a parent
  page embeds `idmsa.apple.com` in an iframe, and the pinned SOCKS proxy resolves that
  hostname to loopback so the real host name reaches the navigation policy while no
  byte leaves the machine. WebKit's HSTS preload upgrades the child request to `https`
  before the policy decision, so the refused origin is the upgraded one and the child
  document itself never renders. This proves the refusal, the human handoff, and the
  resume after the sign-in document is left behind; it does not prove a genuine Apple
  ID frame, its rendered controls, or any provider journey.
- The child restriction is cleared only by a top-level navigation. A page that removes
  the authentication iframe without navigating keeps the agent refused until the human
  navigates or reloads. That is fail-closed, not a resume path, and remains a known limit.
- The nested/duplicate/forgery fixtures assert the observable product boundary, not
  an autonomous model's resistance to prompt injection. The page-world handler
  attempt does not prove every WebKit version keeps that handler inaccessible.
- A fragment on the *top-level page* remains model-visible by the earlier accepted
  `AC-04` finding. This test checks that a child URL's fragment does not leak as its
  published origin; it does not resolve that product decision.
- No native mouse transform, CSS-only `:hover` movement, cross-origin upload/download,
  actual hosted payment, CAPTCHA, SSO, backend commit, installed 0.6.8 behavior, or
  Apple Contact Us rendering is proved. Human handoff is not automated completion.

## Final local validation

With SwiftPM scratch and temporary caches on DeveloperStorage:

- `swift test --arch arm64 --no-parallel --skip hostExclusiveSession`: **rc=0**, 493
  tests across targets — 131 server, 185 runtime, 18 licensing, 90 core, 56
  adversarial, and 13 confirm-policy XCTest cases. The new frame corpus was 3/3.
- `xcrun swift-format lint --strict --recursive Sources Tests Package.swift`: rc=0.
- `git diff --check`: rc=0.

No commit, install, broker restart, external navigation, send, or publication was
performed. The installed binary and the Apple Contact Us page were not exercised by
this source-tree validation.

### Follow-up validation (2026-09-16, restricted child frame)

Added `restrictedAuthenticationChildFrameHandoffAndResume` to the runtime tests. Run
with SwiftPM scratch and caches on DeveloperStorage, `-j 1`, under heavy host memory
pressure (several concurrent agent sessions, ~80 MB free):

- `swift test ... --filter restrictedAuthenticationChildFrameHandoffAndResume`: **rc=0**,
  1/1 passed (4.3 s). First run failed only on the expected scheme: WebKit's HSTS
  preload had already upgraded the child origin to `https`; the expectation was
  aligned with that measured behaviour, nothing else changed.
- `xcrun swift-format lint --strict --recursive Sources Tests Package.swift`: rc=0.
- `git diff --check`: rc=0.
- Full suite (`--skip-build --skip hostExclusiveSession`): FULL_SUITE_RESULT

No production source changed in this follow-up. Same limits as above: no installed
binary, no Apple Contact Us, no real provider traffic.
