# WebKitUI MCP

Native WebKit automation for Apple Silicon, exposed through MCP and designed for an LLM rather than a human.

This repository is a Swift rewrite. The retained TypeScript/Playwright files are prior art only and are not the implementation being extended.

## What exists

- Native `WKWebView` runtime using the persistent system WebKit data store for real authenticated sessions.
- MCP 2026-07-28 stdio server with legacy initialization compatibility.
- Thirteen bounded tools, including authenticated native downloads, explicit page/element scrolling, and bounded text extraction for rendered virtualized logs.
- Observation-scoped element symbols backed by semantic locator recipes and fresh action-time resolution.
- Five separate addressing counters: `address_resolution_failed`, `address_now_ambiguous`, `logical_target_changed`, `node_replaced_but_semantic_locator_recovered`, and `coordinate_invalidated_by_layout_change`.
- Provenance attached to every serialized page string.
- Observation-time privacy minimization: non-rendered controls are removed
  before bounding, sensitive/token-like fields never serialize values, and a
  sensitive select publishes neither its option labels, nor how many it has, nor
  the one currently chosen in it — a selected label is that control's value. The
  control is still reported, with its role and accessible name, so it can be
  handed to a human.
- Checkpoint-plus-delta observation history and Minimal Failure Set coverage metrics.
- Optional local Ollama ranker with `think: false`, strict budgets, and deterministic fallback.
- Transaction ledger with preconditions, exact post-conditions, idempotency keys, indeterminate outcomes, receipts, and reconciliation without replay.
- Human confirmation before every exposed click and open-world navigation.
  Navigation defaults to a server-owned native macOS dialog so a client cannot
  silently decline the round trip; MCP multi-round navigation remains opt-in.
- `browser_session` can set a bounded 320×240–3840×2160 CSS viewport and can
  navigate back, forward, or reload using WebKit's own history list. History
  movement is confirmed against the destination WebKit reports; reloading a page
  produced by a form submission is refused before confirmation to prevent replay.
- Camera, microphone, and geolocation requests are always denied by the native
  `WKUIDelegate`. The observation names the requesting origin and permission, with
  repeated requests counted and distinct records bounded; there is no MCP operation
  that can grant one.
- The confirmation names the origin a submit control's data would reach, computed
  server-side from the freshly re-resolved element rather than from its accessible
  name, and says so explicitly when that origin differs from the page the operator is
  on. A submit button's `formaction` overrides its form's `action`, so a control whose
  accessible name reads harmlessly can post elsewhere.
- Confirmations are counted in a rolling 60-second window. From the fifth, the dialog
  states how many have been requested; the twentieth is refused instead of presented,
  because a dialog a human clicks twenty times in a row has stopped being a gate.
- Legacy MCP clients receive the same exact-action authority boundary through a
  server-owned native macOS confirmation dialog; the model cannot supply or
  forge the approval value.
- Local human handoff: `handoff_start` immediately returns an opaque session-bound resume token while the actual WebKit session becomes a visible window. `handoff_status` is non-blocking; `handoff_resume` consumes the token only after local confirmation and returns a fresh observation. The agent remains locked out throughout human control.
- The packaged handoff app installs a native Edit menu, so standard first-responder
  shortcuts such as Command-X/C/V/A work inside WebKit form controls.
- MCP sessions use a per-session loopback SOCKS5 boundary with failover disabled: hostnames are resolved once, public addresses are pinned, and private/reserved destinations plus non-TCP SOCKS commands fail closed.
- The production CLI enforces one browser controller across all local/remote MCP processes for the macOS account; the lease is released on close or process death.
- Private remote clients can use the app-owned broker plus a forced-command SSH relay; WebKit and authenticated profile data remain on the logged-in Mac.
- Multiple relay clients may use the same long-lived broker concurrently, but
  only one client owns the single browser surface at a time. Other clients get
  `session_in_use` with `wait_only=true`; they cannot observe, navigate, act,
  invalidate addresses, or request duplicate user control. Ownership transfers
  after the controlling client disconnects.
- The app broker owns one live browser across MCP client reconnects. Every
  reconnect invalidates observations, pending approvals, capabilities, and
  transaction coordinators before returning the preserved session handle.
- The native host starts the AppKit event loop before MCP work and keeps the live
  `WKWebView` attached to one opaque window. Agent control orders that window
  out; human handoff presents the same view without reparenting it. A packaged
  visual smoke mode checks the actual WindowServer pixels.
- The stdio relay stays alive across broker restarts. It reconnects before the
  next undispatched request and never silently replays a request whose outcome
  became unknown during a restart.
- Durable multi-client status works without a session ID and reports only
  privacy-safe holder metadata (client name/version, PID, age, inactivity and
  policy). `open(wait_timeout_ms: ...)` can wait up to 60 seconds for the local
  host lease without stealing it; dead transports release their session owner.
  `browser_session(operation: "client_handoff")` can transfer an idle session
  only after local human confirmation and a final no-active-call check.
- A secretless SiliconPass fill can return `credential_not_found`; WebkitUIMCP
  then offers a native human handoff for manual sign-in and addition/update in
  SiliconPass. No credential value crosses MCP, JSON, logs, or the clipboard.
- Web-content termination invalidates every observation immediately; recovery reloads the host-owned last URL without replaying an action. A forced-crash fixture verifies that an `HttpOnly` authenticated cookie plus `localStorage` and `sessionStorage` survive in the same view/data-store lifetime.
- The macOS companion is a regular Dock app with a local activity window. It
  records only allowlisted MCP tool names, outcome, timestamp, duration and a
  bounded error type. Parameters, URLs, page content, credentials, cookies,
  keystrokes and response bodies are structurally absent. Owner-only JSONL
  files rotate automatically and can be exported or cleared from the app.

## Deliberate limits

- `browser_act` exposes click, native submit-control click, bounded non-sensitive input/textarea fill, Enter/Tab/Escape, blur, explicit input commit, and answering the one JavaScript `alert`/`confirm`/`prompt` dialog a page is suspended on (`dialog_accept`, `dialog_dismiss`, `dialog_accept_value`). A pending dialog is reported in the observation as untrusted site content, blocks every other operation until it is answered, is never answered automatically, and resolves to an explicit indeterminate outcome if nobody answers it. `beforeunload` is out of scope: the public macOS SDK exposes no before-unload panel to an embedder. Native approval also routes public text fills through AppKit insertion with a measured trusted `input` receipt. Fill verifies both the freshly re-resolved semantic target's exact value and that its live validation state is not invalid. Other actions support exact URL or URL prefix, title, heading, exact/contains semantic text, checked, selected, enabled, value, validation state, character count, bounded state attributes, dialog, named panel, or selected-option postconditions. A same-URL SPA mutation returns `same_url_page_state_changed` guidance instead of implying success. UI state never proves backend commit.
- `browser_download` converts authenticated attachment responses to `WKDownload` from either a fresh observed control or a protected same-origin URL fallback. It requires exact native confirmation plus a save-panel destination, never overwrites an existing file, and succeeds only after an on-disk receipt reports the HTTP status, suggested/final filename, MIME type, byte count, SHA-256, and decoded provisioning-profile UUID when available. Cookies, headers, and the absolute local destination path stay outside MCP.
- macOS file inputs use WebKit's native open-panel delegate. Selected regular files are bounded to 10 files and 50 MiB each; receipts may expose filenames, byte counts and SHA-256 values, but never local paths or file contents. A file-selection receipt is not provider acceptance: the action's independent postcondition must still verify the uploaded preview or saved state.
- Fill dispatches normal `input`/`change` events, so site handlers may autosave or cause server effects. It is destructive and human-confirmed; password controls require local human handoff.
- `approval_mode: "native"` sends confirmed click/submit and Enter/Tab/Escape through public AppKit `NSEvent` handling on the freshly re-resolved `WKWebView` target. An isolated message handler must observe the matching DOM event with `event.isTrusted == true` before the receipt reports trust. Missing/mismatched receipts fail indeterminate; no flag is synthesized. `approval_mode: "mcp"`, blur, and commit remain JavaScript-dispatched and report untrusted. Native public-text fill reports trust only when its matching AppKit insertion receipt is observed.
- Action results separately expose `confirmation_mode`, `dispatch_mode`, and `trusted_gesture_state`. Native confirmation alone never establishes event trust.
- Navigation readiness and rendered-content availability are separate. A document can
  reach `readyState=complete` and mutation quiescence while remaining blank;
  navigation, observation, and text reads report `empty_or_unusable` in that case and
  explicitly forbid treating the absence as page truth. A rendered textless canvas or
  media document remains `usable`.
- `browser_read_text` reads only currently rendered virtualized lines. Use bounded scroll plus another read for additional ranges.
- No arbitrary JavaScript, raw CDP escape hatch, coordinate retry, proxy fleet, anti-bot bypass, or headless claim. A gate an agent can step around is not a gate: one JavaScript-evaluation call would do anything the confirmation exists to authorize one action at a time. Browserbase's MCP server also refuses JavaScript, so refusing it is not distinctive on its own; the combination surveyed for and not found elsewhere on 2026-09-09 is no JavaScript tool *and* a per-action gate *and* a real authenticated session.
- Viewport resizing changes desktop CSS layout only. It does not emulate a mobile
  device—the public macOS SDK exposes no `WKWebView` `ContentMode` API—and
  `set_emulated_media` is deliberately absent because it does not help operate a
  person's site.
- Camera, microphone, and geolocation access cannot be granted through WebKitUI MCP.
  Requests are denied and reported in the next observation instead of leaving a page
  failure silent; use human control in a complete browser when the workflow requires
  one of those permissions.
- No multiple tabs and no new-window handling. One session holds one exclusive host lease, which is what lets an approval refer to an unambiguous page.
- No subresource or XHR request inspection. It is possible and it is not offered. `WKWebsiteDataStore.proxyConfigurations` is public from macOS 14 and is Apple DTS's own recommendation for reading a `WKWebView`'s request contents, and a bundled `WKWebExtension` with the `webRequest` permission is public from macOS 15.4. Neither is free: the proxy route needs a trusted root certificate to see inside HTTPS, and the extension route reports no headers and cannot block. What is reported instead is narrow — the download receipt's HTTP status, and the egress proxy's accepted, blocked, pinned and timed-out connection counts. A main-frame navigation result carries no HTTP status today, and the proxy does not name the hosts it allowed or refused.
- Native AppKit dispatch is not a distinguishing feature and is not claimed as one. `safaridriver` dispatches `NSEvent` through `[window sendEvent:]` exactly as this does, and the WebDriver specification requires every conformant driver to produce trusted events. What differs is the measurement: an action whose trusted DOM receipt is missing or mismatched fails indeterminate here, where Playwright's hit-target interceptor treats an absent event as success.
- The `WKFormInfo` submission gate is implemented, unit-tested, and does not fire. WebKit did not call `webView(_:willSubmitForm:submissionHandler:)` on either macOS 27.0 build measured here, `26A5416b` and `26A5419a` — not for `submit()`, not for `requestSubmit()`, and not for a native trusted-gesture click. It is therefore not a second live gate and must not be read as one; it will decide if WebKit begins delivering the callback. The live defence against a submit control that posts to another site is the destination line in the confirmation.
- Registered cross-origin frames expose bounded rendered semantics with
  `THIRD_PARTY_EMBED` provenance and a sanitized origin. Their geometry is explicitly
  frame-local; `frameActionModes` (or compact `frame_action_modes`) names eligible
  attempts even when `actionable=false` means no native pointer geometry. A confirmed
  `hover` or `select_option` runs only as untrusted JavaScript in the exact child
  frame; non-sensitive `press_key` and `fill` can use AppKit only
  when that frame returns a matching trusted DOM receipt. A native pointer click has
  no public frame-to-window coordinate transform, refuses before confirmation with
  `cross_origin_native_geometry_unavailable`, and points to live human handoff.
  This is bounded control reach, not proof of hosted checkout completion. Sensitive
  and authentication controls still require a human. Frames that cannot be
  evaluated, and frames beyond the bounded native registry, remain explicitly
  unreadable rather than being treated as empty page content.
- Some identity providers require a complete browser surface and do not render
  inside an app-embedded `WKWebView` (for example a WebAuthn-only step without the
  browser passkey entitlement). Those return `full_browser_required` with an internal
  `safari_compatibility` requirement. `compatibility_start` opens Safari after confirmation, but provides no Safari
  observation/control and no automatic return to this MCP after login. Complete
  the entire blocked workflow manually in the external browser. WebKitUI never copies cookies,
  passkeys, AutoFill data, or credentials between backends.
- `takeSnapshot` may omit GPU-composited effects.
- No exactly-once or rollback claim for an uncooperative website.
- Low concurrency is intentional because WKWebView has no per-view hard memory quota.
- The protected network path is the MCP session registry or `WebKitRuntime(protectedWebsiteDataStore:)`; the lower-level `WebKitRuntime(websiteDataStore:)` initializer is intentionally unprotected for fixtures and embedding.
- This is a bounded website-traffic control, not a complete process egress
  sandbox. The exact tested transports, exclusions and safe-use rule are in
  [`docs/network-boundary.md`](docs/network-boundary.md).

## Compared with the Safari MCP server

Apple's Safari MCP server ships inside `safaridriver` and is started with
`safaridriver --mcp`; Apple's own help text for the flag reads "Run as an MCP (Model
Context Protocol) server using stdio transport." It exposes seventeen tools — page
content, screenshots, network requests, console logs, JavaScript evaluation, DOM
interaction, viewport and media emulation, tab management. It needs two settings in two
different panes: "Show features for web developers" in Safari > Settings > Advanced, and
"Allow remote automation and external agents" in Safari > Settings > Developer. Apple's
floor is Safari 27 beta or Safari Technology Preview 247 or later, and Apple documents
Safari 27 beta on macOS 26 and macOS Sequoia as well as macOS 27, so it is not a macOS 27
requirement.

Apple aims it at web developers: it "gives your agent the ability to know how your code
actually renders in the browser", and both sets of release notes file it under
WebDriver > New Features. Apple also states it "runs entirely on your local machine and
makes no network calls of its own" and that it "does not have access to your personal
information in Safari (e.g. AutoFill or other browser activity)". For developing a site
it is the better tool, it is included with Safari and Apple lists no separate price, and
this project does not compete with it.

The difference is what happens when the site is not yours and you are signed in to it:

| | Safari MCP server | WebKitUI MCP |
| --- | --- | --- |
| Purpose | inspect and debug a site you are developing | act on a site you are signed in to |
| Approval | no confirmation step is documented, and none of the seventeen tools requests one | native macOS confirmation before every exposed click and open-world navigation |
| Tool annotations | none: every tool carries only `name`, `description` and `inputSchema`, so a client gets no signal separating page reading from JavaScript evaluation | `readOnlyHint`, `destructiveHint`, `idempotentHint` and `openWorldHint` on every tool |
| JavaScript evaluation | exposed as a tool | absent, with no CDP or coordinate fallback |
| Session | Apple's WebDriver documentation states automation windows are "isolated from normal browsing windows, user settings, and preferences" and that a session "always starts from a clean slate" | its own `WKWebView` and its own persistent profile, which is what authenticated work requires |
| Protocol | reports `2024-11-05` | `2026-07-28`, the current revision |
| Network detail | full request inspection, including headers, body and timing | no per-request inspection: the download receipt's HTTP status, and the egress proxy's connection counts without host names |
| Verification | inspection tools | an explicit postcondition per action, plus separate `confirmation_mode`, `dispatch_mode` and `trusted_gesture_state` |

The isolation wording above is Apple's WebDriver documentation, about automation sessions
generally. Apple has published no equivalent statement about the MCP server itself.

Both can be installed at once, and for most developers both should be.

Two things this project will not say about Apple's server, because Apple does not: that
it cannot reach your cookies or your logged-in sessions — Apple's MCP post names AutoFill
and "other browser activity" only — and that Apple states there is no confirmation step.
The absence is documented; a denial is not.

## Build and test

The product targets macOS 15+ on Apple silicon. Building the optional
`WKJSHandle` probe requires the macOS 27 SDK; those APIs stay feature-gated.

```bash
swift build -c release --arch arm64
xcrun swift-format lint --strict --recursive Sources Tests Package.swift
swift test --arch arm64
swift test -c release --arch arm64
```

For a reproducible verification of the current checkout plus the signed local
installation and its two-client transport:

```bash
scripts/verify-native-installed.sh
```

Run the server:

```bash
swift run -c release --arch arm64 webkitui-mcp
```

Before registration, run the secret-free local readiness check:

```bash
webkitui-mcp doctor
```

It checks the native confirmation helper, local owner-authentication policy,
architecture, macOS version, and locally stored license state. It does not open
a website, read browser data or credentials, authenticate the user, or contact
the license service.

`webkitui-mcp --help` prints the stdio contract without starting the server.
The sibling `webkitui-mcp-confirm` helper owns legacy native dialogs so closing
an AppKit alert cannot terminate or corrupt the long-lived stdio server.

The process reads newline-delimited JSON-RPC from stdin, writes protocol responses only to stdout, and reserves stderr for diagnostics.

For a disposable direct process, install the CLI and register it normally:

```bash
release_bin="$(swift build --show-bin-path -c release --arch arm64)/webkitui-mcp"
release_dir="$(dirname "$release_bin")"
install -m 0755 "$release_bin" "$HOME/.local/bin/webkitui-mcp"
install -m 0755 "$release_dir/webkitui-mcp-confirm" "$HOME/.local/bin/webkitui-mcp-confirm"
codex mcp add webkitui-mcp -- "$HOME/.local/bin/webkitui-mcp"
claude mcp add --scope user webkitui-mcp -- "$HOME/.local/bin/webkitui-mcp"
```

Install the two together and leave them side by side. Before showing a
confirmation the server checks the helper next to it, and what it can demand
depends on how the server itself is signed:

- a **notarized** server pins its Developer ID team and the exact identifier the
  release script stamps, so nobody can drop a helper of their own beside it;
- a server **built from source** is ad-hoc signed and has neither, so the check
  can only require that the helper sits next to it under its own name. That
  gives nothing away: whoever can write a helper beside an unsigned server can
  replace that server too.

Mixing the two is refused in both directions. If you re-sign one binary, re-sign
the other with the same identity, or the confirmation will not appear and every
navigation will fail closed.

### Keyboard behaviour of the confirmation

The confirmation uses a nonactivating panel: it can receive keyboard input while
the caller remains the active application, without adding a separate helper icon
to the Dock. Two preferences, shared by a source build and the notarized app,
decide what the keyboard may do:

```bash
# Return cancels and Escape closes after 1 s of initial keyboard focus (default).
defaults write com.lorislab.webkitui-mcp ConfirmationKeyboardDefault cancel
# Return/Escape have no default action; click, or Tab to a button then Space.
defaults write com.lorislab.webkitui-mcp ConfirmationKeyboardDefault none
# Arming delay for Return/Escape, 0 to 5 seconds (default 1).
defaults write com.lorislab.webkitui-mcp ConfirmationArmingDelaySeconds -float 2
```

The arming delay starts after the initial display and key-window acquisition.
Queued Return/Escape input is checked against its original event timestamp. Initially no button has focus:
stray Return/Space press nothing, and Escape
is ignored until armed. Deliberately selecting a button with Tab and Space or
clicking still works. In `none` mode Escape stays disabled.
Approve is never a keyboard default and cannot be made one. No per-project or
per-session auto-approval exists; the design constraints for one are recorded
in `docs/research/2026-09-01-goal-delegation-and-browser-addressing-sota.md`.

For authenticated sessions that must survive Codex conversation reconnects,
build the self-contained app instead:

```bash
scripts/package-preview.sh dist
scripts/verify-package-preview.sh dist
```

Unzip `WebKitUI-MCP-0.6.11-preview.zip`, move `WebKitUI MCP.app` to the
Applications folder, and open it. In the status window:

1. Enable **Launch at Login**. macOS may require approval in System Settings.
2. Copy and run the Codex setup command. It points to the relay embedded in the
   app bundle and the owner-only local Unix socket.
3. Keep the app in Applications after registration so the saved relay path
   remains valid.

The **Activity journal** button opens the local privacy-safe event history.
Its files live under `~/Library/Application Support/WebkitUIMCP/Activity` with
owner-only permissions. Rotation retains at most seven 5 MiB archives plus the
active file. **Clear** removes activity files but preserves transaction
receipts; **Export** writes only the same redacted event schema.

The app uses Apple's Service Management API and does not install a mutable
plist in `~/Library/LaunchAgents`. **Prepare to uninstall** disables Launch at
Login while preserving receipts and license data; then quit the app and move it
to the Trash. The preview archive is unsigned. Signing, notarization, clean-Mac
installation and publication are separate release gates.

Each MCP client receives isolated observations, confirmations, transactions,
and capability grants over the same durable browser. A logical
`browser_session close` detaches that client authority but deliberately keeps
the live browser; quitting the app destroys that in-memory page session.

Restart conversations opened before registration: MCP tool catalogs are fixed
for a running conversation and are not retroactively replaced.

## MCP flow

1. List the secretless persistent profile with `browser_session { operation: "profiles" }`, then `browser_session { operation: "open", profile_id: "default" }`.
2. `browser_navigate` opens a native exact-destination approval dialog by
   default. Use `approval_mode: "mcp"` only when the client reliably supports
   multi-round elicitation.
3. `browser_observe`; use `element_scroll_into_view`, `browser_scroll`, or
   `browser_session { operation: "set_viewport", ... }`, then observe again when
   needed. `back`, `forward`, and `reload` are native-confirmed session operations.
4. Use the fresh `observationID` and `elementID` once.
5. For a login form, call `browser_fill_siliconpass`. If it returns
   `credential_not_found`, accept the native handoff and add or update the
   credential directly in SiliconPass.
6. `browser_act` returns `input_required`; approve the exact bound action.
7. Read, export as canonical `ReceiptV1`, or reconcile the receipt with
   `browser_transaction`. One redacted canonical object produces both JSON and
   Markdown; only the SHA-256 of the idempotency key is exported. Exported
   evidence never authorizes replay.

Large semantic pages can be read without oversized MCP results: `browser_observe`
supports role/name filters, `maximum_elements`, `maximum_field_characters`, and
`element_offset`; follow `nextElementOffset` until it is absent.
The enforced limits and the remaining release measurements are documented in
[`docs/performance-budgets.md`](docs/performance-budgets.md).
The authority boundaries, attack paths, current controls and residual release
gates are maintained in
[`docs/security-threat-model.md`](docs/security-threat-model.md).
Local data lifetimes and explicit-export boundaries are documented in
[`docs/privacy-retention.md`](docs/privacy-retention.md).
The stable diagnostic allowlist and forbidden support data are documented in
[`docs/support-diagnostics.md`](docs/support-diagnostics.md).
The manual signed-update, rollback, support and incident rules are documented
in [`docs/release-maintenance-policy.md`](docs/release-maintenance-policy.md).

While a person holds the human control window, its bar offers **Fill with
SiliconPass** when the SiliconPass broker is installed. The person asks, not the
agent: WebKitUI binds the one visible password form in the frame being used,
including a restricted sign-in frame such as `idmsa.apple.com`, and SiliconPass
matches the saved sign-in by that frame's exact host. The values are typed into the
two fields through AppKit, so the page sees real input events; nothing is
submitted and nothing reaches MCP, logs or the agent.

SiliconPass credential release is deliberately stronger than ordinary browser
confirmation. After the exact native fill summary is approved, macOS evaluates
`deviceOwnerAuthentication` uses zero Touch ID reuse and delegates the
available authentication method to macOS. WebKitUI does not infer that Touch ID,
Apple Watch, password fallback, or closed-lid authentication will be available
on a particular Mac. If the Mac is locked or authentication UI cannot be
presented, WebKitUI receives only
`user_presence_unavailable`: no secret is released and no automatic retry is
performed.

Restricted authentication origins such as `idmsa.apple.com` return only their
canonical origin and a local handoff requirement. Observe, text, capture,
scroll, credential fill, and actuation remain blocked until the human leaves
that origin. A cross-origin redirect is not reported as an ambiguous WebKit
failure: it returns `redirect_requires_human_approval` with source and target
origins only.

When App Store Connect embeds that restricted Apple Account origin, the sign-in
takes the native human handoff like any other restricted origin. It used to return
`full_browser_required`: the frame measured as stalled was a hidden-page defect of
the parked window (fixed 2026-09-23), not an engine limit.

Navigation blocks on an exact native macOS confirmation by default and returns
a normal terminal tool result. Human handoff is
two calls: the first transfers control to the visible window; after completing
the sensitive step, call `browser_session { operation: "handoff", ... }` again
and approve the native resume dialog. MCP 2026-07-28 clients continue to use
multi-round `input_required` results.

Use `browser_session { operation: "handoff" }` when a human must control the same local WebKit session. Declining resume leaves human control active.
The handoff window becomes a regular foreground Mac app with a Dock icon and
uses the same rendered view as semantic observation and capture.

## Linux headless lane

`linux/` is a separate, ephemeral Playwright worker for disposable workloads on
a dedicated Linux VM. It does not inherit Mac cookies or passwords and it does
not replace native WebKit. Route authenticated sessions and human handoff to the
Mac; route public, unauthenticated headless work to Linux. See
[`linux/README.md`](linux/README.md) and
[`docs/architecture/linux-headless-worker.md`](docs/architecture/linux-headless-worker.md).

## Evidence

- Architecture: [`docs/architecture/`](docs/architecture/)
- Private remote transport and deployment gates: [`docs/architecture/private-remote-transport.md`](docs/architecture/private-remote-transport.md)
- Dated research and NotebookLM audits: [`docs/research/`](docs/research/)
- Same-Mac runtime benchmark: [`Benchmarks/README.md`](Benchmarks/README.md)
- Public/private publication boundary: [`docs/architecture/public-private-boundary.md`](docs/architecture/public-private-boundary.md)
- Vulnerability reporting and release invariants: [`SECURITY.md`](SECURITY.md)

The [dated adversarial corpus measurement](docs/research/2026-09-09-adversarial-corpus-measurement.md)
records 53 deterministic tests across 57 concrete fixture executions for provenance,
dialog truth, destinations, and export leakage. It measures those product boundaries,
not human or model attack success.

The first measured local lane uses 30 runs of the same deterministic fixture at 2560×1600. It compares WKWebView with Playwright 1.61.1 driving installed Chrome 151. It does **not** yet measure full process-tree memory, visible-window behavior, authenticated task success, or Playwright's pinned Chromium binary; no broader superiority claim is made.

## Licensing

WebKitUI MCP 0.6.11 Developer Preview is available under the
[Business Source License 1.1](LICENSE). The source is readable, auditable and
modifiable; production use is granted for personal noncommercial, qualifying
noncommercial organization and evaluation use, and commercial production use
requires an agreement with the Licensor. This version converts to Apache 2.0 on
2030-08-28. See [`LICENSING.md`](LICENSING.md) for the exact scope, third-party
boundary and treatment of earlier revisions.

## Safety

The model cannot mint capability handles. Page content never becomes trusted policy. Password values are omitted from observations. Unknown dispatch is indeterminate and is never automatically retried. No commit, push, deployment, or external account mutation is performed by the project itself.

Navigation actor attribution uses the first main-frame navigation within two
seconds of an action. It is diagnostic evidence, not proof of causality or
authorization: autonomous or more delayed navigation can be misattributed.
