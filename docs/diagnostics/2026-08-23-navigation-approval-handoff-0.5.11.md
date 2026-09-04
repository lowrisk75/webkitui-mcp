# WebKitUI MCP 0.5.11 navigation approval and empty handoff

## Reproduction

Terra opened the persistent `default` profile through the Aqua relay. The MCP
client declined the `browser_navigate` multi-round request before Codemagic was
loaded. A later handoff presented the live but never-navigated `WKWebView`, so
the native window was correctly owned and visible yet appeared entirely white.

Evidence supplied by the human session:

- installed version `0.5.10` / bundle `510`;
- Aqua PID `13546`, launchd parent;
- Terra relay PID `7525`, Codex parent `7483`;
- exact error `The user did not approve this navigation`;
- no `WKErrorDomain`, OAuth, Codemagic build, or ASC upload;
- redacted screenshot `/private/tmp/webkitui-0.5.10-blank-human-control.png`.

## Remediation

- `browser_navigate` now defaults to a server-owned native macOS confirmation
  containing the exact current page and destination. This preserves explicit
  human authority without relying on a client elicitation round trip.
- `approval_mode: "mcp"` retains the bound, single-use multi-round protocol as
  an explicit option.
- The Aqua application now packages the fail-closed `webkitui-mcp-confirm`
  helper beside its broker; the installed verifier requires both Aqua and CLI
  helper copies to be executable and covered by the application signature.
- Handoff with no loaded document renders a local status page saying that no
  approved page is loaded. It performs no network request and cannot be
  mistaken for a compositor failure.

## Verification gates

- Server test: native confirmation is the default and denial fails closed.
- Server test: explicit MCP mode remains exact-argument-bound and single-use.
- Runtime test: an empty handoff renders the local status document.
- The installed verifier explicitly uses `--no-parallel`; concurrent WebKit
  fixture suites reproduced `noDocument`, while serialized execution exercises
  the same assertions deterministically without retry-based masking.
- Full Debug and Release suites, signed installation, live Aqua socket, and a
  physical Codemagic approval/handoff were required; their results follow.

## Installed verification result

`scripts/verify-native-installed.sh` completed with exit status 0 after the
0.5.11 installation:

- Debug: 24 server + 37 runtime + 61 core = 122 passing tests;
- Release: 24 server + 37 runtime + 61 core = 122 passing tests;
- strict Swift formatting and `git diff --check`: pass;
- deep application signature, including the packaged confirmation helper:
  pass;
- live socket: version `0.5.11`, 10 tools, `default` profile, two clients, one
  shared durable session;
- Aqua broker SHA-256:
  `0bd7f821e9cd4216a7ebbd69b60c966b4fdd984f6be19f59e34bc827a068cddb`;
- Aqua confirmation helper SHA-256:
  `569394a062d519a65496560aa08f54f1775ce20d43ece74ad3d5a78c6b36bdae`;
- direct CLI SHA-256:
  `f6551af1a6b51dc9a4a0f3fbbb3ebaa00f6c57586ee7b7830a2ea06561c3cc81`;
- direct confirmation helper SHA-256:
  `78645111660c637f65371182589cf01114dc7d8a3833cb08a4d8696bfb20b3dd`;
- relay SHA-256:
  `34406be0932e00f23c187f8f9ffd21868ce453d1027ee31096c01738dad61840`.

## Physical Codemagic gate

Final verdict: **PASS**.

- server `0.5.11`, bundle `511`;
- native navigation confirmation displayed and approved by Kevin;
- Codemagic rendered in the live human-control handoff with no white surface;
- handoff window PID `31026`;
- no OAuth action, secret entry, Codemagic build, or App Store Connect upload.

This closes the 0.5.11 navigation-approval and visible-handoff gate. It does
not claim authentication completion, a successful Codemagic workflow, or an
App Store Connect delivery.
