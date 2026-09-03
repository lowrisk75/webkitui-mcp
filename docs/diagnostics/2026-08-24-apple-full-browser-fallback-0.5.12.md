# Apple authentication full-browser fallback

Date: 2026-08-24

## Result

The App Store Connect login shell completes its top-level load in an embedded
`WKWebView`, but its `idmsa.apple.com` authentication subframe does not render
interactive controls. The same public route renders the Apple Account form in
a clean full-browser profile. A protected pinned-proxy run and a direct
ephemeral `WKWebView` run produced the same stalled authentication UI, so the
proxy is not the differentiator.

This is a browser-capability boundary, not evidence that Apple credentials,
cookies, or passkeys are invalid. No authenticated content or credential value
was captured during the comparison.

## Runtime behavior

The runtime now recognizes only the exact sanitized embedding pair:

- top level: `https://appstoreconnect.apple.com`
- restricted child: `https://idmsa.apple.com`

Agent read, capture, scroll, actuation, and credential-fill surfaces remain
fail-closed. Instead of presenting a known-stalled human-control `WKWebView`,
the MCP result returns:

- `status: full_browser_required`
- `recommended_backend: safari_mcp`
- `session_transfer_supported: false`
- `credential_transfer_supported: false`

The match is exact-host only. Suffix lookalikes and unrelated Apple origins do
not activate this route. Other restricted authentication pages continue to use
the local native handoff.

## Safari compatibility lane

Safari 27 includes an Apple-maintained MCP server at
`/usr/bin/safaridriver --mcp`. It is the compatibility lane for sites that need
a complete browser rather than an app-embedded `WKWebView`. It must be enabled
by the local user in Safari settings before a client can start it.

The Safari MCP lane is a separate browser authority. WebKitUI does not copy or
serialize its persistent website data, cookies, passkeys, AutoFill records, or
credentials into Safari. The user completes sensitive authentication in the
browser surface; the agent must treat credential fields and authentication
origins as restricted there as well.

## Evidence and limits

- Focused server tests: 27 passed.
- Focused runtime tests: the new exact-pair regression passed.
- The runtime suite's unrelated production-lock test was blocked by the
  already-running Aqua broker (`hostControllerBusy`); the broker was not
  interrupted.
- A live end-to-end Safari MCP login rendering check remains pending until the
  user enables “Allow remote automation and external agents” in Safari.
- This fallback does not claim passkey automation. Passkeys, MFA, CAPTCHA, and
  sensitive input remain human-only operations.
