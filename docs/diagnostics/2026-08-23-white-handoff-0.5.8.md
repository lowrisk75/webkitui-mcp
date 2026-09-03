# WebKitUI MCP 0.5.8 white handoff remediation

Date: 2026-08-23

## Decision

GO for the local native handoff rendering defect. The installed Aqua broker
rendered a real `https://example.com/` document in the `Human control` window.
No OAuth, Codemagic mutation, credential submission, or App Store Connect
operation was performed.

## Confirmed cause

The broker accepted WebKit work before running the native AppKit event loop.
DOM observation and `WKWebView.takeSnapshot` could therefore succeed while the
WindowServer-backed handoff surface remained white. The broker now starts
`NSApplication.run()` before MCP requests can drive the runtime.

The live `WKWebView` also retains one opaque window owner. Agent control orders
that window out; handoff presents the same window without alpha transitions or
view reparenting.

## Evidence

- Packaged LaunchServices smoke test: dark blue page and the white heading
  `WebkitUIMCP visual smoke test` were visible in a Computer Use capture.
- Installed production broker advertised version `0.5.8` over its real relay.
- Production navigation to `https://example.com/` completed, then the native
  handoff showed `Example Domain` in both WindowServer pixels and the macOS
  accessibility tree.
- Resume returned `control_state=freshly_reobserved` and a new observation.
- Debug and Release suites passed with `hostExclusiveSession` skipped because
  the installed production broker intentionally held the exclusive host lock.
- `swift-format lint --strict` and `git diff --check` passed.
- Installed app signature passed `codesign --verify --deep --strict`.

Installed broker SHA-256:
`b304d846e2361b37d01c8cf1eded9f2c2540f9c1272698e5e08f9aca418ebbce`.

## Remaining operational caveat

The data volume had only about 116 MiB free during validation. WebKit emitted a
cache-directory `ENOSPC` warning, although the relevant tests and production
render proof succeeded. Disk capacity is an infrastructure risk, not evidence
of a remaining handoff rendering defect.
