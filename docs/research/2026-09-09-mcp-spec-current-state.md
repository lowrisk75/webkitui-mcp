# MCP Specification: Current State vs. webkitui-mcp (revision 2026-07-28)

Date: 2026-09-09

Question: Is protocol revision 2026-07-28 still current, and would any newer protocol feature serve a human-approval-gated macOS MCP server better than a server-owned native confirmation dialog?

All URLs below were read on 2026-09-09. Findings are labelled EXTERNAL-PRIMARY (specification, official docs, SDK docs, official blog), COMMUNITY-SIGNAL (issue tracker, third-party blog), or UNAVAILABLE.

---

## Verdict

Revision `2026-07-28` is the current published revision and there is nothing after it — the versioning page names it as **Current**, the schema directory contains no dated revision beyond it, and the `draft` changelog is empty ("Changes since the most recent release will accumulate here"), so this server is exactly current and no revision upgrade is available or pending. Nothing newer in the protocol replaces a server-owned native confirmation dialog: elicitation is the only user-interaction primitive in core MCP, and it carries no guarantee that a human ever saw the request — clients are documented and observed to answer it programmatically, so it must stay an optional convenience rather than the gate. Two things are genuinely worth adopting, neither of which is a new revision: the vendor `_meta` flag `anthropic/requiresUserInteraction`, which is the only mechanism found anywhere that forces a per-call human prompt even under `bypassPermissions`; and a fix for the `content`/`structuredContent` split, which is broken in opposite directions by different shipping clients.

---

## Revisions after 2026-07-28

**None.** (EXTERNAL-PRIMARY)

| Evidence | Source |
| --- | --- |
| "The **current** protocol version is [**2026-07-28**]" — no draft revision is listed on the versioning page | https://modelcontextprotocol.io/specification/versioning |
| `/specification/latest` resolves to the 2026-07-28 content (all in-page links point at `/specification/2026-07-28/…`) | https://modelcontextprotocol.io/specification/latest |
| Schema directories: `2024-11-05`, `2025-03-26`, `2025-06-18`, `2025-11-25`, `2026-07-28`, `draft`. No dated directory after 2026-07-28. | https://github.com/modelcontextprotocol/modelcontextprotocol/tree/main/schema |
| Draft changelog is empty: "Changes since the most recent release will accumulate here." | https://modelcontextprotocol.io/specification/draft/changelog |
| `/specification/draft` is textually identical to `/specification/latest` in Key Details, Features, Extensions and Security sections | https://modelcontextprotocol.io/specification/draft |

Consequence for this server: **no migration work exists.** `MCPServer.protocolVersion = "2026-07-28"` (`Sources/WebKitUIMCPServer/MCPServer.swift:22`) is the newest value the specification defines. Re-check the draft changelog rather than the versioning page when watching for the next revision; the draft accumulates first.

### What 2026-07-28 itself changed (for reference, since it is the revision in force)

Reproduced from the specification's own changelog (EXTERNAL-PRIMARY, https://modelcontextprotocol.io/specification/2026-07-28/changelog), which compares against `2025-11-25`. Marked for relevance to a human-approval server.

| # | Change | Affects this server? |
| --- | --- | --- |
| Major 1 | Protocol-level sessions and `Mcp-Session-Id` removed; list endpoints must not vary per-connection; cross-call state uses server-minted handles passed as ordinary tool arguments (SEP-2567) | Yes — this server hands out explicit browser session handles; that is now the sanctioned pattern, and per-connection variation of `tools/list` is forbidden |
| Major 2 | MCP is stateless: `initialize`/`notifications/initialized` removed; every request carries `io.modelcontextprotocol/protocolVersion` and `io.modelcontextprotocol/clientCapabilities` in `_meta`; mismatches return `UnsupportedProtocolVersionError` (SEP-2575) | Yes — already implemented (`MCPServer.swift:3531` enforces the `_meta` protocol key) |
| Major 3 | `server/discover` is a mandatory RPC advertising supported versions, capabilities, identity (SEP-2575) | Yes — already implemented (`MCPServer.swift:3192`) |
| Major 4 | HTTP GET endpoint and `resources/subscribe`/`unsubscribe` replaced by `subscriptions/listen` (single long-lived POST-response stream, opt-in notification types) (SEP-2575) | Only if a Streamable HTTP transport is added; not for stdio |
| Major 5 | `ping`, `logging/setLevel`, `notifications/roots/list_changed` removed; log level is per-request via `io.modelcontextprotocol/logLevel`; servers **MUST NOT** emit `notifications/message` for requests that did not set it | Yes — a server that logs unconditionally over MCP now violates a MUST NOT |
| Major 6 | Tasks moved out of core into the official extension `io.modelcontextprotocol/tasks`; `tasks/result` replaced by polling `tasks/get` plus `tasks/update` for client-to-server input; `tasks/list` removed (SEP-2663) | Yes, as an option — see Recommended adoptions |
| Major 7 | **Multi Round-Trip Requests (MRTR)** replaces server-initiated requests. Servers return `InputRequiredResult` (`resultType: "input_required"`) carrying `inputRequests`; the client answers on a **retry of the original request** via `inputResponses`. Server-initiated `roots/list`, `sampling/createMessage`, `elicitation/create` are "no longer supported. This is a breaking change." (SEP-2322) | Yes — this is how the server's multi-round elicitation must work, and it does (`MCPServer.swift:1671`, `:1978`, `:2360`) |
| Major 8 | All results carry a required `resultType`: `"complete"` or `"input_required"` (SEP-2322) | Yes — every tool result envelope must set it |
| Major 9 | SSE stream resumability and `Last-Event-ID` redelivery removed; a broken stream loses the in-flight request and the client **MUST** re-issue with a new request ID | Relevant to any future HTTP transport: a native dialog awaiting approval must tolerate the client abandoning the call |
| Minor 5 | `ttlMs` and `cacheScope` now **required** on results of `tools/list`, `prompts/list`, `resources/list`, `resources/read`, `resources/templates/list` (`CacheableResult`) (SEP-2549) | Yes — a compliance item worth verifying on `tools/list` |
| Minor 10 | `inputSchema`/`outputSchema` loosened to any JSON Schema 2020-12; `structuredContent` may be **any JSON value**, not just an object (SEP-2106) | Yes — the compact-form encoder may return arrays/scalars if useful |
| Minor 11 | `notifications/elicitation/complete` and the URL-mode `elicitationId` field (both new in 2025-11-25) **removed**; correlation across retries is now done by the server encoding its own identifier in `requestState` | Yes — no server-initiated completion signal exists; a native dialog cannot notify the client that it finished |
| Minor 12 | Error-code allocation policy: `-32000`–`-32019` implementation-defined, `-32020`–`-32099` reserved for the spec; `HeaderMismatch` → `-32020`, `MissingRequiredClientCapability` → `-32021`, `UnsupportedProtocolVersion` → `-32022` | Yes — if the server mints custom codes, keep them inside `-32000`–`-32019` |
| Minor 3 | Servers **SHOULD** return `tools/list` in deterministic order | Yes — cheap compliance item |
| Deprecated 1 | **Roots, Sampling and Logging are Deprecated** (SEP-2577). Earliest removal: first revision released on or after 2027-07-28. Migrations: tool parameters/resource URIs instead of Roots; direct LLM provider APIs instead of Sampling; `stderr` or OpenTelemetry instead of Logging | Yes, decisively — see Q3 below: "sampling with user review" is a dead end |
| Deprecated 2–4 | HTTP+SSE transport reclassified Deprecated; `includeContext: "thisServer"`/`"allServers"` Deprecated; OAuth 2.0 DCR (RFC 7591) deprecated in favour of Client ID Metadata Documents | Only DCR matters, and only if a remote transport is ever added |

Deprecation registry (EXTERNAL-PRIMARY, https://modelcontextprotocol.io/specification/2026-07-28/deprecated) confirms nothing has been **Removed** yet.

---

## Elicitation as a security primitive

### What the specification currently says (EXTERNAL-PRIMARY, https://modelcontextprotocol.io/specification/2026-07-28/client/elicitation)

- Two modes. **Form mode**: in-band structured data, flat objects of primitives only (string/number/integer/boolean/enum, formats `email`/`uri`/`date`/`date-time`); data is exposed to the client. **URL mode**: out-of-band navigation; nothing but the URL is exposed to the client.
- Delivered only inside `InputRequiredResult.inputRequests` under MRTR; the client answers by **retrying the original request**.
- Capability is per-request: `_meta.io.modelcontextprotocol/clientCapabilities.elicitation` with `{"form":{}}` and/or `{"url":{}}`; an empty object means form-only. Servers **MUST NOT** send a mode the client did not declare.
- Three actions: `accept` (with `content` for form mode), `decline` (explicit refusal), `cancel` (dismissal — closed dialog, Escape, browser failed to load).
- Servers **MUST NOT** use form mode for passwords, API keys, access tokens or payment credentials; those **MUST** use URL mode.
- Clients **MUST** identify the requesting server, provide decline and cancel options, allow review and modification of form responses before sending, and for URL mode display the target host and gather consent before navigating.
- URL mode is explicitly **not** a way to authorize the client to the server; servers **MUST NOT** rely on it to authorize users for themselves, **MUST NOT** put credentials or pre-authenticated URLs in the elicitation URL, and **MUST** verify that the user who opens the URL is the user the elicitation was minted for (the documented phishing/account-takeover attack).
- `requestState` is the only correlation mechanism. It passes through the client, so servers **MUST** treat it as attacker-controlled, **MUST** integrity-protect it (HMAC/AEAD) whenever it influences authorization or business logic, and **SHOULD** bind principal, TTL and an originating-request identifier inside it (EXTERNAL-PRIMARY, https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/mrtr).
- Servers **MUST NOT** assume clients will fulfil `inputRequests` or retry at all (MRTR server requirement 8).

### What it guarantees

- A **shape** for asking, and a **vocabulary** for the three outcomes.
- That a conforming client will not silently pass secrets through itself in form mode.
- That the server can distinguish "user refused" (`decline`) from "nothing happened" (`cancel`).
- That the request cannot be answered by the *model* in-band: elicitation bypasses the LLM and is surfaced by the client application.

### What it does not guarantee

1. **That a human answered.** Nothing in the elicitation or MRTR text requires the client to involve a person. The strongest words are "Clients **SHOULD** implement user approval controls" and "**SHOULD** allow users to decline … at any time" — SHOULD, not MUST, and about *offering* controls, not about consulting a human before responding.
2. **That the request will be answered at all.** MRTR requirement 8 tells servers not to assume a retry ever comes. Fail-closed is mandatory, not optional.
3. **That an `accept` means the work happened.** For URL mode the specification says outright: "The response with `action: "accept"` indicates that the user has consented to the interaction. It does not mean that the interaction is complete."
4. **That the server learns the outcome asynchronously.** `notifications/elicitation/complete` and `elicitationId` were **removed** in 2026-07-28; the server only finds out on the next retry.
5. **That the client is a UI at all.** Capability declaration is the only signal; a headless agent, a CI runner, or a test harness may declare `elicitation` and answer from code.

### Can a client answer automatically or programmatically? Yes — demonstrably.

- **EXTERNAL-PRIMARY** (https://ts.sdk.modelcontextprotocol.io/v2/migration/support-2026-07-28): in the TypeScript SDK v2 the client fulfils embedded requests "through the same handlers registered with `setRequestHandler('elicitation/create' | 'sampling/createMessage' | 'roots/list', …)`". These are ordinary application callbacks that return a value; auto-fulfilment is controlled by `ClientOptions.inputRequired`, with `allowInputRequired: true` for per-call manual control. There is no human in that path unless the application puts one there. The SDK also warns that accepted content is **not** re-checked against `requestedSchema`, so a handler can return a shape the server did not ask for.
- **COMMUNITY-SIGNAL** (https://github.com/openai/codex/issues/23383, open as read): Codex Desktop auto-accepts elicitation. "When a tool is configured with `approval_mode = "approve"` (e.g. after the user picks 'always allow' in the desktop UI), Codex auto-accepts any `elicitation/create` request that tool issues", sending `{action: "accept", content: {}}`. The issue's own framing: "When users do the normal thing ('always allow this tool'), the gate silently breaks." This is precisely the failure mode a security-critical server must assume.
- **COMMUNITY-SIGNAL** (https://www.systemshardening.com/articles/ai-landscape/mcp-elicitation-security/): elicitation "bypasses the model entirely: the server sends the request to the client, and the client surfaces it to the user as if it were a legitimate application request" — the same property that makes it useful makes it a social-engineering channel, and the defence "must be at the client and protocol layer", i.e. not somewhere the server controls.

**Conclusion: a server MUST NOT treat an elicitation `accept` as proof that a human approved anything.** It is evidence that *some* client-side policy accepted, which may be a person, a stored "always allow", or a line of code. For a server whose defining property is that dangerous operations stop for a human, elicitation is a UX affordance and a portability path — not the gate. The server-owned native macOS dialog remains the only approval channel this server can actually reason about, because it is the only one the server itself renders and reads.

### Client support table

Core MCP has no published per-feature client matrix on modelcontextprotocol.io as of this date — `/clients` redirects to the "What is MCP" page and `/clients/feature-support-matrix` returns 404; the only official matrix covers **extensions**, not elicitation (EXTERNAL-PRIMARY, https://modelcontextprotocol.io/extensions/client-matrix). Elicitation support therefore has to be read off each vendor's own docs.

| Client | Elicitation | 2026-07-28 / MRTR | Can it answer without a human? | Source (read 2026-09-09) |
| --- | --- | --- | --- | --- |
| Claude Code | Yes. Form mode and URL mode; "No configuration is required — elicitation dialogs appear automatically", and they "appear regardless of permission mode", including `bypassPermissions` | Yes, on the v2 runtime (v2.1.232+, TS SDK 2.0). Negotiates: asks HTTP and claude.ai connector servers; asks stdio servers only if `MCP_PROTOCOL_NEGOTIATION=auto` | Not documented as auto-answering elicitation; but tool *permission* prompts are auto-approved in `acceptEdits`/`auto`/`bypassPermissions` unless the tool sets `_meta["anthropic/requiresUserInteraction"]` | EXTERNAL-PRIMARY https://code.claude.com/docs/en/mcp |
| Claude / Claude Desktop | Not stated on the pages read (MCP Apps yes) | Not stated | UNAVAILABLE | EXTERNAL-PRIMARY (extensions only) https://modelcontextprotocol.io/extensions/client-matrix |
| VS Code (GitHub Copilot) | Elicitation support reported; MCP Apps and Enterprise Managed Auth confirmed officially | Reported as supporting the stateless revision, probing with `server/discover` and falling back to `initialize` | UNAVAILABLE | EXTERNAL-PRIMARY for MCP Apps (client-matrix); COMMUNITY-SIGNAL for elicitation/stateless (search summary of https://github.blog/changelog/2026-07-23-github-mcp-server-supports-the-next-mcp-specification/ and third-party write-ups) |
| Cursor | Lists Tools, Prompts, Resources, Roots, **Elicitation**, and Apps among its MCP capabilities | MCP Apps confirmed officially | Concerning: from Cursor 3.6, in Auto-review mode "allowlisted MCP tools run immediately and everything else is routed through the safety classifier" — an allowlist path with no human | COMMUNITY-SIGNAL (search summary of https://cursor.com/docs/context/mcp); EXTERNAL-PRIMARY for Apps (client-matrix) |
| Codex (OpenAI) | Yes | Not established | **Yes — confirmed auto-accept** under `approval_mode = "approve"` | COMMUNITY-SIGNAL https://github.com/openai/codex/issues/23383 |
| Zed | UNAVAILABLE — no elicitation statement found; absent from the official extension matrix | UNAVAILABLE | UNAVAILABLE | — |
| ChatGPT, Microsoft 365 Copilot, Goose, Postman, MCPJam, Archestra.AI, PostHog Code | Elicitation not stated | — | UNAVAILABLE | EXTERNAL-PRIMARY (MCP Apps only) https://modelcontextprotocol.io/extensions/client-matrix |
| Any SDK-built client / harness / CI | Whatever it declares | Whatever it declares | **Yes by construction** — `setRequestHandler('elicitation/create', …)` is a function | EXTERNAL-PRIMARY https://ts.sdk.modelcontextprotocol.io/v2/migration/support-2026-07-28 |

Read the table as: elicitation exists in the specification and is implemented by several major clients (both facts), and separately, no client is documented as *guaranteeing* a human answers it, while at least one (Codex) is documented as not doing so.

---

## Specification security guidance versus this server

Sources: https://modelcontextprotocol.io/docs/2026-07-28/tutorials/security/security_best_practices, https://modelcontextprotocol.io/specification/2026-07-28/server/tools, https://modelcontextprotocol.io/specification/2026-07-28/client/elicitation, https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/mrtr, https://modelcontextprotocol.io/specification/latest (all EXTERNAL-PRIMARY).

Note on scope: the Security Best Practices document is overwhelmingly about **authorization** (confused deputy, token passthrough, SSRF, mix-up attacks, CIMD, scope minimization). A local stdio macOS server with no OAuth surface is out of scope for most of it. The clauses that do bind are below.

| Requirement | Normative source | This server | Verdict |
| --- | --- | --- | --- |
| Servers **MUST** validate all tool inputs | tools § Security Considerations | Assumed; verify per tool | Pass (verify) |
| Servers **MUST** implement proper access controls | tools § Security Considerations | Native dialog gate on dangerous operations | Pass |
| Servers **MUST** rate-limit tool invocations | tools § Security Considerations | Not observed in the source read | **Likely fail — verify.** No rate limiting was found; a runaway agent can re-drive the dialog indefinitely (dialog fatigue is the attack) |
| Servers **MUST** sanitize tool outputs | tools § Security Considerations | Page text/DOM flows back to the model; sanitization not audited here | **Unverified** — treat as an open item, since browser output is untrusted attacker-controlled content |
| There **SHOULD** always be a human in the loop able to deny tool invocations | tools § User Interaction Model (Warning) | This is the server's defining behaviour, and it is enforced server-side rather than delegated | **Pass, and stronger than required** |
| Clients **MUST** consider tool annotations untrusted unless from a trusted server | tools § Tool (Warning) | Server publishes hints but does not depend on them | Pass |
| Servers **MUST** securely associate elicitation state with individual users, protected against unauthorized access | elicitation § Statefulness | Local single-user stdio server; no multi-user state | Pass (not applicable) |
| Servers **MUST** treat `requestState` as attacker-controlled, **MUST** integrity-protect it (HMAC/AEAD) where it influences authorization or business logic, and **MUST** reject state that fails verification | MRTR server requirement 4 | Not observed in the source read | **Verify. Fail if `requestState` is unsigned and carries anything but inert data.** Integrity protection may be omitted only "when tampering can cause nothing worse than request failure" — for an approval server, tampering that fabricates an approval is far worse |
| Servers **SHOULD** bind principal, TTL and an originating-request digest inside `requestState`; single-use invariants **MUST** be enforced server-side | MRTR server requirement 5 | Not observed | **Verify.** An approval token that can be replayed is an approval bypass |
| Servers **MUST NOT** send `inputRequests` the client did not declare support for | MRTR server requirement 7 | Server declares `requiredCapabilities: {elicitation: {}}` and gates on it (`MCPServer.swift:363`, `:401`) | Pass |
| Servers **MUST NOT** assume clients fulfil `inputRequests` or retry | MRTR server requirement 8 | Native dialog is the default and does not depend on a retry | **Pass — and this is the architectural reason the design is sound** |
| Servers **MUST NOT** use form mode for passwords, API keys, tokens, payment credentials; **MUST** use URL mode | elicitation § Warning | Repo contains a credential-broker path with an `elicitation` capability in `_meta` (`Sources/CredentialBrokerPhysicalValidation/main.swift:214`) | **Verify explicitly.** If any credential is ever requested through form-mode elicitation, that is a MUST violation. Native dialog or URL mode only |
| Servers **MUST NOT** put sensitive info or pre-authenticated URLs in a URL-mode elicitation URL; **SHOULD** use HTTPS outside development | elicitation § Safe URL Handling | Verify if URL mode is used at all | Verify |
| Servers **MUST NOT** rely on client-provided user identification without server verification | elicitation § Identifying the User | Local server; identity is the logged-in macOS user, established by the server's own dialog | Pass |
| Servers **MUST NOT** emit `notifications/message` for requests that did not set `io.modelcontextprotocol/logLevel` | changelog Major 5 | Verify the logging path | Verify |
| Servers intending to run locally **SHOULD** use `stdio` to limit access to just the client, or restrict HTTP (auth token, unix domain socket) | best practices § Local MCP Server Compromise | stdio | Pass |
| Servers **MUST NOT** treat possession of a state handle as authentication; handles **SHOULD** be non-deterministic, bound server-side, expiring | best practices § State Handle Hijacking | Browser session handles are minted by the server; binding/entropy/expiry not audited here | **Verify** — the specification's own guidance for unauthenticated servers is UUIDv4-grade entropy plus a bounded lifetime |
| Servers **MUST NOT** accept tokens not issued for them (token passthrough) | best practices § Token Passthrough | No OAuth surface | Not applicable |
| Tools **MUST** provide structured results conforming to `outputSchema` when one is declared | tools § Output Schema | Compact-vs-full negotiation means the returned shape varies | **Verify.** If an `outputSchema` is declared, *both* the compact and full forms must validate against it, or the schema must be omitted |
| `tools/list`, `resources/list`, etc. results **MUST** carry `ttlMs` and `cacheScope` | changelog Minor 5 (`CacheableResult`) | Not observed | **Likely fail — verify** |
| `tools/list` **MUST NOT** vary per-connection | tools § Capabilities | The compact-form negotiation must not change the *tool list* per client — only results | **Verify.** Varying results by declared client capability is fine; varying the advertised tool set by client identity is now forbidden |
| Servers **SHOULD** return tools in deterministic order | tools § Capabilities | Not observed | Verify (cheap) |

Summary: the human-approval architecture **passes the parts of the specification that matter most**, and passes them by not trusting the client. The plausible failures are housekeeping and hardening, not design: `ttlMs`/`cacheScope` on list results, rate limiting, `requestState` integrity and replay protection, `outputSchema` conformance across both result forms, and an explicit audit that no credential is ever requested via form-mode elicitation.

---

## Tool annotations and `structuredContent`

### Annotations (EXTERNAL-PRIMARY)

The four hints — `readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`, plus `title` — are unchanged in 2026-07-28; the changelog lists no ToolAnnotations change. The tools page describes `annotations` only as "Optional properties describing tool behavior" and attaches a Warning: "clients **MUST** consider tool annotations to be untrusted unless they come from trusted servers" (https://modelcontextprotocol.io/specification/2026-07-28/server/tools). The official MCP blog is blunter still (https://blog.modelcontextprotocol.io/posts/2026-03-16-tool-annotations/): annotations "are not guaranteed to faithfully describe tool behavior", "they aren't enforcement — if you need a guarantee that a tool can't exfiltrate data, that's a job for network controls or sandboxing, not a boolean hint", and implementors should "keep your actual safety guarantees in deterministic controls". They *can* legitimately "drive confirmation prompts" in a client that trusts the server.

This server already emits all four (`MCPServer.swift:4162`–`:4166`). Keep them: they are a correct courtesy to clients, and they are not, and must not become, part of the gate.

### Is there anything newer for declaring "this tool requires human approval"?

- **In the specification: no.** There is no `requiresApproval`, `requiresUserInteraction`, `confirmationRequired` or equivalent field in core MCP 2026-07-28 or in the empty draft. The closest thing is `destructiveHint` — a hint, explicitly untrusted, and defaulting conservatively.
- **In a vendor `_meta` key: yes, for Claude Code.** `_meta["anthropic/requiresUserInteraction"]: true` on a tool definition makes Claude Code "show that tool's permission prompt on every call, even in `acceptEdits`, `auto`, and `bypassPermissions` permission modes", with no "don't ask again" option, and denial rather than prompting in `dontAsk`. Allow rules that match the tool do not skip the prompt (EXTERNAL-PRIMARY, https://code.claude.com/docs/en/mcp). It is not in this server's source today (no `requiresUserInteraction` match under `Sources/`).

### `structuredContent` (EXTERNAL-PRIMARY)

Current guidance, verbatim: structured content "can be any JSON value (object, array, string, number, boolean, or null) that conforms to the tool's `outputSchema` if one is defined", and — critically — "For backwards compatibility, a tool that returns structured content SHOULD also return **the serialized JSON** in a TextContent block." Every example in the specification shows either the serialized JSON in `content` or a human summary alongside a full `structuredContent`. If an `outputSchema` is declared, servers **MUST** conform to it and clients **SHOULD** validate against it.

This server returns a concise sentence — `"Compact structured result available in structuredContent."` (`MCPServer.swift:3378`) — rather than the serialized JSON. That is a deliberate deviation from a SHOULD, and it is exactly the case the next section shows breaking.

---

## Practical client compatibility: concise `content` + complete `structuredContent`

**Yes. This is broken by shipping clients, in both directions.** All COMMUNITY-SIGNAL (issue trackers), read 2026-09-09.

| Client | Documented behaviour | Effect on this server |
| --- | --- | --- |
| VS Code | "When `structuredContent` is present: Text items in `content` are skipped (`if (!callResult.structuredContent)`); Only `JSON.stringify(structuredContent)` is sent to the model." Open, filed 2026-01-24. https://github.com/microsoft/vscode/issues/290063 | The compact-form negotiation is **defeated**: the concise text is dropped and the full payload is stringified into the model context — the opposite of the intent |
| Claude Code | "When an MCP server returns a tool response containing both `content` … and `structuredContent` …, Claude Code only displays `structuredContent` and ignores `content`." Closed/confirmed, filed 2025-12-26 against 2.0.67. https://github.com/anthropics/claude-code/issues/15412 | Same defeat, plus the human-readable summary never reaches the user |
| Claude Desktop | Ignores `structuredContent`; only processes `content`. https://github.com/blockscout/mcp-server/issues/324 | **Worst case for this server**: the model receives only the sentence "Compact structured result available in structuredContent." and no data at all |
| Cursor | "When an MCP `tools/call` result carries data only in `structuredContent` and its `content` array is empty, Cursor delivers an empty result to the model." https://forum.cursor.com/t/mcp-tool-results-containing-only-structuredcontent-are-silently-dropped/167346 | Safe only because `content` is non-empty; the data still does not arrive |
| langchain-mcp-adapters | Ignores `structuredContent` from tool responses. https://github.com/langchain-ai/langchain-mcp-adapters/issues/283 | Data loss |
| Microsoft Agent Framework (Python) | `CallToolResult.structuredContent` not parsed; results return `None`. https://github.com/microsoft/agent-framework/issues/3313 | Data loss |
| n8n | Drops `structuredContent`, causing agent tool loops. https://github.com/n8n-io/n8n/issues/26963 | Data loss and retry storms |

The two populations are irreconcilable by any single payload **unless** `content` carries everything the model needs on its own. The specification's SHOULD — serialize the JSON into a TextContent block — is exactly the hedge that survives both camps, at the cost of the context saving the compact form was built to achieve. The honest resolution is to make the *compact* form the thing that goes in both places: put the compact JSON serialization in `content` and the compact object in `structuredContent`, keeping the full payload behind an explicit follow-up tool or a `resource_link`. That keeps context small without depending on which field a given client reads.

---

## Recommended adoptions

Ranked. Nothing here is recommended for being new.

**1. Add `_meta["anthropic/requiresUserInteraction"]: true` to every dangerous tool. (Highest value, near-zero cost.)**
Problem solved: today a Claude Code user in `bypassPermissions` / `auto` mode gets no client-side prompt for a destructive browser action; the server's native dialog is the only barrier, and any future decision to make the dialog skippable would silently remove the gate. This flag makes the *client* also prompt, on every call, un-suppressible, defence in depth from the other side of the boundary. Cost: a vendor-specific `_meta` key that other clients ignore (harmless — `_meta` is designed for exactly this), plus one prompt per dangerous call for Claude Code users who had opted out of prompts. Confirm the key against https://code.claude.com/docs/en/mcp before shipping, since it is vendor documentation and can change.

**2. Fix the `content` / `structuredContent` split so a client that reads only one field still works. (High value, moderate cost.)**
Problem solved: as shown above, Claude Desktop / Cursor / langchain / n8n users of this server can receive an empty or useless result for every compact response, and VS Code / Claude Code users silently get the full payload instead of the compact one, so the negotiation buys nothing. Approach: keep the compact form as the single source of truth for the round trip, serialize it into `content` as the specification's SHOULD directs, and expose the full payload only on explicit request. Cost: the concise-sentence optimization goes away; context savings must come from the compact *shape*, not from splitting fields. Also verify that both forms validate against any declared `outputSchema` (a MUST).

**3. Close the compliance gaps found above. (Medium value, low cost.)**
`ttlMs` + `cacheScope` on `tools/list` (now required); deterministic tool ordering; per-request `logLevel` gating of `notifications/message`; rate limiting of tool invocations (a MUST that also blunts dialog fatigue, the realistic attack on an approval server); `requestState` integrity protection with principal + TTL + originating-request binding, and single-use enforcement wherever an approval could otherwise be replayed; entropy/binding/expiry on browser session handles. Problem solved: MUST-level conformance and replay resistance. Cost: a day of unglamorous work.

**4. Consider the Tasks extension (`io.modelcontextprotocol/tasks`) only if the native dialog's blocking time is causing client timeouts. (Conditional.)**
Problem solved: the extension's stated use cases include "human approvals" and "Approval gates, review steps, or any operation that pauses for user confirmation" — the task moves to `input_required`, the client polls `tasks/get`, answers via `tasks/update`, and the task ID survives disconnects, whereas a blocking call dies with the stream (2026-07-28 removed SSE resumability, so a broken stream loses the in-flight request outright). Cost: real, and probably not worth paying yet — it is an opt-in extension requiring both sides to declare support, it does not appear in the official extension client matrix (only MCP Apps and the two auth extensions do, so **the extension is specified but its client support is undocumented — two separate facts**), it adds a polling state machine and durable task storage to a currently stateless server, and it changes nothing about who actually approves: `input_required` is answered by the same client-side machinery that can auto-accept elicitation. Adopt only on evidence of timeouts, and keep the native dialog authoritative regardless. Source: https://modelcontextprotocol.io/extensions/tasks/overview.

**5. Adopt nothing else. Explicitly reject:**
- **Making elicitation the primary or fallback gate.** It cannot be relied on for a security decision (see above). Keep it as the optional, secondary path it already is.
- **Sampling with user review.** Sampling is **Deprecated** as of 2026-07-28, earliest removal the first revision on or after 2027-07-28, migration path "integrate directly with LLM provider APIs" (https://modelcontextprotocol.io/specification/2026-07-28/deprecated). "New implementations shouldn't adopt them." There is no user-review guarantee attached to it either. Dead end — do not build on it.
- **MCP Apps (`io.modelcontextprotocol/ui`) as a consent surface.** It is a real, officially supported extension with the broadest client matrix of any extension, and it does render forms and approval-style workflows in a sandboxed iframe with host-enforced policy. But it is a *presentation* extension: the approval it produces is still the host's, mediated by the host's own consent path, in a browser-grade sandbox — strictly weaker for this purpose than a dialog the server itself owns on the local machine, and unavailable in the stdio/no-UI clients this server must still be safe under. Cost of adopting it for approval: an HTML/JS surface, a CSP, and a new trust boundary, in exchange for no new guarantee. It would be a reasonable future addition for *displaying* a page or diff to a human — not for being the gate.
- **A protocol-revision migration.** There is none to make.
- **Removing or weakening the native dialog.** It is the only channel in this architecture whose answer the server can attribute to a human, and MRTR requirement 8 ("Servers **MUST NOT** assume that clients will fulfil the `inputRequests` or retry") is the specification agreeing.

---

## Unavailable

- **No official per-feature client support matrix for core MCP.** `https://modelcontextprotocol.io/clients` redirects to the "What is MCP?" page; `https://modelcontextprotocol.io/clients/feature-support-matrix` returns HTTP 404. The only official matrix (https://modelcontextprotocol.io/extensions/client-matrix) covers extensions — MCP Apps, OAuth Client Credentials, Enterprise-Managed Authorization — and does not mention elicitation, sampling or roots. Elicitation support per client therefore rests on vendor docs and community reports, and is marked accordingly above.
- **Zed**: no statement found about elicitation support, MRTR, or 2026-07-28. Absent from the official extension matrix. Not established either way.
- **Claude Desktop**: elicitation support not stated in any official page read. The only primary datum is the `structuredContent`-ignoring behaviour reported against it in a third-party server's issue tracker (COMMUNITY-SIGNAL).
- **Cursor / VS Code elicitation**: reported by search summaries of vendor documentation rather than read directly from `https://cursor.com/docs/context/mcp` and the VS Code MCP docs. Treat as COMMUNITY-SIGNAL until those pages are read directly.
- **Whether any client guarantees a human answers an elicitation.** No client documentation making that guarantee was found. The one client whose behaviour is documented in detail (Codex) does the opposite.
- **Rate limiting, output sanitization, `requestState` integrity, session-handle entropy in this server.** Marked "verify" above rather than pass/fail: this research was read-only over the web plus a shallow grep, not a source audit. Each needs a code review before being claimed as compliant.
- **`server/discover` in the wild**: no measurement of how many clients actually call it versus falling back to `initialize`. GitHub's MCP server changelog and third-party write-ups describe the probe-then-fallback pattern, but adoption breadth is not established.
