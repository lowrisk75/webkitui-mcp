# Navigation capability boundary — NotebookLM review (2026-08-21)

Notebooks: `WebKITUI MPC` and the private opportunity notebook `LLM`.

## Source-supported

- CVE-2025-47241 showed that Browser Use's domain restriction could be bypassed with URL user-info parsing; string-splitting is not an origin parser.
- Published browser-agent attacks have chained untrusted page content into cross-origin navigation and later privileged actions.
- CaMeL's out-of-model capability enforcement measured 77% task success with security guarantees versus 84% without; model-only filtering is not the security boundary.

## Locally measured

- Current WebkitUIMCP clicks bind confirmation to exact arguments, observation, document, origin, and fresh locator resolution.
- Before this slice, `browser_navigate` had no equivalent confirmation or private capability check.
- After implementation, an adversarial MCP test rejects changed post-approval arguments, URL user-info, localhost, `.local`, IPv4/IPv6 literals, decimal/hex IPv4 forms, and legacy invocation.
- A native WKWebView test confirms that a later JavaScript top-level redirect outside the approved origin is cancelled.

## Conjectural / open

- A GET can change server state despite HTTP semantics; URL shape cannot prove safety.
- Blocking literal local addresses and `.local` names closes direct host access but does not solve DNS rebinding because WKWebView resolves independently.
- No public benchmark isolates the utility cost and attack reduction of exact navigation approval.

## Implementation consequence

- Require MCP multi-round human approval for every exposed navigation and bind it to the exact canonical URL and arguments.
- Reject URL credentials, localhost/`.local`, and IP-literal targets by default.
- Mint a short-lived private `navigate` capability only after approval; never treat model-generated URL text as `USER_INTENT`.
- Mark navigation destructive/open-world and add adversarial tests for argument mutation, user-info URLs, and legacy bypass.
- Persist the approved-origin lock across the agent-controlled session; clear it during local human handoff and rebind it on resume.
