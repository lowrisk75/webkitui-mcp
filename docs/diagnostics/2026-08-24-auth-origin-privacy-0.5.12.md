# WebKitUI MCP 0.5.12 authentication-origin privacy remediation

Date: 2026-08-24

## Scope

This local remediation responds to a sanitized inter-session report. It uses
synthetic HTML and loopback fixtures only. No Apple page, account, credential,
OAuth flow, provider build, broker restart, commit, push, or publication is
part of the validation.

## Implemented boundaries

- Observation removes non-rendered controls before applying its element limit.
- Hidden, zero-size, CSS-hidden, transparent, `aria-hidden`, and `inert`
  controls cannot contribute a value to an observation.
- Password, OTP/autocomplete, token, state, CSRF, nonce, session, assertion,
  secret, and opaque-value fields are sensitive and value-less.
- Selects expose only the visible selected label.
- Canonical state and locator recipes independently refuse sensitive or
  non-rendered values.
- `idmsa.apple.com` is origin-restricted: agent read/capture/scroll/act/fill
  surfaces return an origin-only handoff requirement.
- Agent resume remains blocked until the human leaves the restricted origin.
- Cross-origin cancellation returns `redirect_requires_human_approval` with
  source and target origins only.
- `auth_ui_not_ready` is derived from booleans only: complete document, progress
  indicator, invisible authentication controls, and no visible authentication
  control. Environment telemetry contains configuration booleans only.

## Local validation

- Targeted Debug regression set (privacy, authentication-origin policy,
  sanitized redirect approval, environment, persistent storage, proxy routing,
  and verified fill): **10/10 passed**, terminal exit status `0`.
- Relevant serialized Debug suite:
  `swift test -c debug --no-parallel --skip hostExclusiveSession --quiet`:
  **129/129 passed** across 14 suites, terminal exit status `0`
  (server 27/27, runtime 41/41, core 61/61).
- `git diff --check`: passed, terminal exit status `0`.
- `xcrun swift-format lint --strict --recursive Sources Tests`: passed,
  terminal exit status `0` (with only the tool's temporary-directory warning).
- `hostExclusiveSession` was intentionally excluded because the active Aqua
  broker lease was not interrupted.

An initial full-suite run exposed that safe empty text fields had lost their
canonical `@value` entry. The extraction now preserves the empty string only
for rendered, non-sensitive, editable text controls. The isolated regression
and both final test runs above passed after that correction.

## Evidence boundary

The synthetic fixtures verify the fail-closed privacy behavior. They do not
establish why Apple's real client-side authentication UI remained on its
carousel. Real-site JavaScript, resource loading, anti-automation behavior,
cookie policy, and embedded-browser compatibility remain unverified by design.
