# Apple's Safari MCP Server — verified factual baseline for a published comparison

Date: 2026-09-09

Question: What exactly does Apple's Safari MCP server expose, require, and promise, and which of those statements can we safely quote in a public comparison table?

---

## Summary

The Safari MCP server is a Model Context Protocol server built into Apple's `safaridriver` binary and started with `safaridriver --mcp`, introduced in Safari 27 beta and Safari Technology Preview 247 and announced on the WebKit blog on 1 July 2026 (EXTERNAL-PRIMARY, [WebKit blog](https://webkit.org/blog/18136/introducing-the-safari-mcp-server-for-web-developers/), read 2026-09-09). Apple positions it squarely at web developers who already use coding agents, to remove the "debugging dance" of hopping between browser, console and terminal: "the Safari MCP server gives your agent the ability to know how your code actually renders in the browser by connecting it to a Safari browser window." It exposes **17** tools — not fifteen — covering page-content extraction, screenshots, network requests, console logs, JavaScript evaluation, DOM interaction, viewport/media emulation and tab management, and both Apple's release notes classify it as a **WebDriver** feature, not a browsing feature. Apple's own framing is development and debugging ("Allow your agent to connect to a Safari browser for development and debugging via the Safari MCP server"), and Apple states the server "does not have access to your personal information in Safari (e.g. AutoFill or other browser activity)".

---

## Tool surface

**Count correction (material).** The task brief said the blog mentions fifteen tools. It does not. The blog's tool table contains **17 rows** (EXTERNAL-PRIMARY, [WebKit blog](https://webkit.org/blog/18136/introducing-the-safari-mcp-server-for-web-developers/), read 2026-09-09), and Apple's shipped server returns exactly the same **17** tool names from a `tools/list` JSON-RPC call (LOCAL-VERIFICATION, see method note below). Third-party write-ups variously claim 15, 16 and 17; they are unreliable on this point. **Do not publish a "15 tools" figure.**

Method note for the `tools/list` evidence (LOCAL-VERIFICATION, 2026-09-09): on this machine — macOS 27.0 (build 26A5425a), Safari 27.0, `/usr/bin/safaridriver` → `/System/Cryptexes/App/usr/bin/safaridriver`, code-signed `Identifier=com.apple.safaridriver`, `Authority=macOS Software Signing` — `safaridriver --mcp` was driven over stdio with an `initialize` + `tools/list` handshake. It answered `{"protocolVersion":"2024-11-05","serverInfo":{"name":"Safari","version":"1.0.0"},"capabilities":{"tools":{}}}`. No page was loaded and no action was taken on any page.

The blog's one-line descriptions (EXTERNAL-PRIMARY, quoted verbatim from the blog table):

| # | Tool | Apple's description |
|---|---|---|
| 1 | `browser_console_messages` | "Return buffered console logs for the current or specified tab" |
| 2 | `browser_dialogs` | "List and respond to browser dialogs (accept, dismiss, or input text for JS prompts)" |
| 3 | `close_tab` | "Close a browser tab by its handle" |
| 4 | `create_tab` | "Create a new browser tab, optionally loading a URL" |
| 5 | `evaluate_javascript` | "Execute JavaScript code within the page and return the result" |
| 6 | `get_network_request` | "Get full detail for a single recorded network request (headers, body, timing)" |
| 7 | `get_page_content` | "Extract text content of a page in various formats (markdown, HTML, JSON, etc.)" |
| 8 | `list_network_requests` | "List network request summaries (URL, method, status, timing) for the current tab" |
| 9 | `list_tabs` | "List all open browser tabs with their handles and URLs" |
| 10 | `navigate_to_url` | "Navigate to a URL and return the loaded page's content" |
| 11 | `page_info` | "Get info about the current page: URL, title, and loading state" |
| 12 | `page_interactions` | "Perform DOM interactions in sequence: click, type, scroll, hover, keyPress, etc." |
| 13 | `screenshot` | "Capture a screenshot of the current page as a PNG" |
| 14 | `set_emulated_media` | "Emulate a CSS media type (e.g. \"print\") for responsive-design testing" |
| 15 | `set_viewport_size` | "Set the browser viewport size in CSS pixels" |
| 16 | `switch_tab` | "Switch to a different browser tab by its handle" |
| 17 | `wait_for_navigation` | "Wait for the current page to finish loading; returns final URL and title" |

The shipped server's own descriptions are longer than the blog's and reveal design intent worth knowing (LOCAL-VERIFICATION, `tools/list`, 2026-09-09):

- `get_page_content` — "Extract the text content of a page using WebKit's text extraction. This is the preferred way to read a page — favor it over screenshots or scripting the DOM with `evaluate_javascript`." Options include `region` (`viewport` / `entire_page`), `format` (`markdown`, `text`, `textTree`, `json`, `html`, `plainText`), `includeAccessibilityAttributes` (default true), `includeSubframes` (cross-origin subframes, default false), `maxWordsPerParagraph` (default 15), and `nodeIds` (`none` / `editable` / `interactive` / `allContainers`). Output ≥ 32 kB is written to a temp file and the path returned.
- `page_interactions` — actions are "click, type, keyPress, scroll, selectText, selectMenuItem, hover, highlightText", executed "sequentially with a 400 ms settle between each", returning a diff of page changes.
- `evaluate_javascript` — "Execute a JavaScript function body within the page", with a `$uid(N)` macro to address DOM nodes returned by `get_page_content`, and an optional `frameId` to run inside an iframe.
- `screenshot` — "Returns the file path (never inline base64)."
- `navigate_to_url` — accepts a single free-form `url` string with no host, scheme or origin restriction in the schema.

Element addressing is UID-based: `get_page_content` hands back node UIDs which `page_interactions` and `evaluate_javascript` then reference — there is no separate accessibility-snapshot tool and no separate element-inspection tool.

---

## Setup and settings required

All EXTERNAL-PRIMARY from the [WebKit blog](https://webkit.org/blog/18136/introducing-the-safari-mcp-server-for-web-developers/) (read 2026-09-09) unless labelled otherwise.

**What you install.** Nothing. There is no package, no npm module and no download. The server is the `safaridriver` binary that ships with Safari; you install a Safari build that has it. Apple gives two routes:

- **Safari 27 beta** — "First, you'll need to install Safari 27 beta."
- **Safari Technology Preview** (247 or later) — "First, you'll need to install Safari Technology Preview."

**Settings, exact names and locations.** Apple words these slightly differently per route, and the wording differs again in the binary's own error string. All three are worth knowing:

- Safari 27 beta route, verbatim: "To enable features for web developers choose Safari > Settings > Advanced > check the **Show features for web developers** checkbox. Then go to Safari > Settings > Developer > check **"Allow remote automation and external agents."**"
- Safari Technology Preview route: "enable **Safari Settings > Advanced > Show features for web developers**. Then go to **Safari Settings > Developer > Enable remote automation and external agents**."
- The shipped binary's error text uses a third, shorter form: "You must enable 'Allow remote automation' in the Developer section of Safari Settings to control Safari via WebDriver." (LOCAL-VERIFICATION, `list_tabs` tool error on this machine, 2026-09-09.)

So: two settings, in two different panes — **Advanced** for the developer-features toggle, **Developer** for the automation toggle. The Developer pane only appears once the Advanced toggle is on.

**Is `safaridriver` required?** Yes, unavoidably — it *is* the server. The registration command is literally the binary plus a flag:

```
claude mcp add safari-mcp -- "/usr/bin/safaridriver" --mcp
codex mcp add safari-mcp -- "/usr/bin/safaridriver" --mcp
```

```json
{
  "mcpServers": {
    "safari-mcp": {
      "command": "/usr/bin/safaridriver",
      "args": ["--mcp"]
    }
  }
}
```

For Safari Technology Preview the command path is `/Applications/Safari Technology Preview.app/Contents/MacOS/safaridriver`. The binary's own help confirms the transport: "--mcp   Run as an MCP (Model Context Protocol) server using stdio transport. Reads JSON-RPC from stdin, writes to stdout." (LOCAL-VERIFICATION, `safaridriver --help`, macOS 27.0, 2026-09-09.)

**Per-window, per-tab or global?** Not per-tab. Apple's blog says the agent connects "to a Safari browser window" (singular), and the tool set is window-scoped-with-tabs: `list_tabs`, `create_tab`, `switch_tab`, `close_tab` all operate on handles within one session. INFERRED (strong): because the MCP server is `safaridriver` and creates a WebDriver session — the failure mode on this machine was `WebDriverErrorDomain Code=6 "Could not create a session: ... to control Safari via WebDriver"` — the scope is one WebDriver automation session, i.e. one isolated automation window plus the tabs it owns, and Apple's WebDriver documentation states "only one WebDriver session at a time can be attached to the browser instance" ([About WebDriver for Safari](https://developer.apple.com/documentation/webkit/about-webdriver-for-safari), read 2026-09-09). It is therefore **neither global to your running Safari nor per-tab**: it is one automation session at a time.

---

## Security and privacy model

**Apple's own words** (EXTERNAL-PRIMARY, [WebKit blog](https://webkit.org/blog/18136/introducing-the-safari-mcp-server-for-web-developers/), read 2026-09-09) — the complete privacy paragraph, quoted in full because it is the only one Apple wrote:

> "The Safari MCP server runs entirely on your local machine and makes no network calls of its own. It also does not have access to your personal information in Safari (e.g. AutoFill or other browser activity). When it captures page content, screenshots, or console logs, that data goes directly to the agent you're running — not to Apple. What happens to that data from there depends on the agent and model you're using. As with any agent you give access to your browser, only use ones you trust."

Four things Apple asserts there, and one it disclaims:

1. Runs entirely locally; "makes no network calls of its own".
2. "does not have access to your personal information in Safari (e.g. AutoFill or other browser activity)" — AutoFill is named explicitly.
3. Captured page content, screenshots and console logs go "directly to the agent you're running — not to Apple".
4. Disclaimer: "What happens to that data from there depends on the agent and model you're using."
5. Trust is pushed to the user: "only use ones you trust."

**Cookies, logged-in sessions and browsing history — Apple's blog is silent.** It names AutoFill and "other browser activity"; it never uses the words cookies, session, login or history. Anyone quoting Apple on cookies is quoting something Apple did not write in that post.

**Ordinary profile or isolated?** Apple has not published this statement about the MCP server specifically. It has published it about `safaridriver` WebDriver sessions, which is what the MCP server creates. From [About WebDriver for Safari](https://developer.apple.com/documentation/webkit/about-webdriver-for-safari) (EXTERNAL-PRIMARY, read 2026-09-09):

> "To support WebDriver without sacrificing a user's privacy or security, Safari's driver provides extra safeguards to ensure that test execution is isolated from normal browsing data and from other test runs."

> "**Isolated Automation Windows.** Test execution is confined to special automation windows that are isolated from normal browsing windows, user settings, and preferences. You can recognize these windows by their orange Smart Search field. Like a private browsing session, an automation session always starts from a clean slate. It can't access Safari's browsing history, AutoFill data, or other sensitive information available in a normal browsing session. These isolated sessions also help to ensure that tests are unaffected by a previous test session's persistent state."

> "**Glass Panes.** To prevent any attempts to interact with the window or web content during a test, Safari installs a transparent "glass pane" over the automation windows while the browser is being used for WebDriver testing. This pane catches any stray interactions (mouse, keyboard, resizing, and so on) that could affect the automation window."

INFERRED (strong, three-link chain, each link primary): (a) the MCP server is `safaridriver --mcp`; (b) both release notes file it under **WebDriver → New Features** — "Allow your agent to connect to a Safari browser for development and debugging via the Safari MCP server. (176038457)" ([Safari 27 beta release notes](https://developer.apple.com/documentation/safari-release-notes/safari-27-release-notes) and [STP 247 release notes](https://developer.apple.com/documentation/safari-technology-preview-release-notes/stp-release-247), read 2026-09-09); (c) on this machine the server failed with `WebDriverErrorDomain` "Could not create a session ... to control Safari via WebDriver". Therefore the MCP server operates in an isolated WebDriver automation window with a clean-slate data store, not the user's ordinary Safari profile — which is also the only reading consistent with Apple's "does not have access to your personal information in Safari".

This inference could not be closed empirically because "Allow remote automation" is off on this machine and enabling it is a configuration change requiring the user's own authorisation. It was **not** enabled. Publish this as our inference, or as "Apple's WebDriver documentation states", never as "Apple says about the MCP server".

---

## Approval and consent

**There is no human confirmation, consent prompt or approval step in the product.** This is a cited absence, established four ways:

1. **The 17 tools include no confirmation tool.** No `confirm`, `approve`, `request_permission` or equivalent appears in the blog's table or in the server's `tools/list` (EXTERNAL-PRIMARY + LOCAL-VERIFICATION, 2026-09-09). `browser_dialogs` is the opposite of a consent step: its purpose is to let the agent dispatch a page's own JavaScript dialogs — "List and respond to browser dialogs. Actions: "list" to query, "respond" to accept, "dismiss" to cancel." The agent answers dialogs; it is not questioned by one.
2. **The server ships no MCP tool annotations at all.** Every one of the 17 tool definitions returned by `tools/list` carries exactly three keys — `name`, `description`, `inputSchema` — and nothing else (LOCAL-VERIFICATION, 2026-09-09). There is no `readOnlyHint`, no `destructiveHint`, no `openWorldHint`. A client therefore receives no signal from Apple distinguishing `get_page_content` from `page_interactions` or `evaluate_javascript`, and cannot gate the destructive ones on that basis. Whatever approval a user gets is entirely the MCP client's own doing.
3. **Apple's text describes autonomy, not approval.** The blog's worked dialogue has the agent report findings and *ask the user in chat* — "I found two distinct bugs on the flight page in Safari. Want me to fix them both?" — which is the agent's conversational habit, not a browser-level gate. Apple's framing is explicitly toward less human involvement: "The Safari MCP server enables your agent to do more debugging and troubleshooting on its own", "All you need is an initial request to get started, and with the help of the Safari MCP server, your agent can take it from there", and "it shouldn't need to be told to use the Safari MCP server explicitly — it'll figure it out on its own."
4. **Apple substitutes user trust for a technical control.** The only safeguard Apple names is choosing your agent: "As with any agent you give access to your browser, only use ones you trust." A one-time global setting ("Allow remote automation and external agents") is the sole consent event; after that, no per-action gate exists.

The single caveat worth stating honestly: Apple's WebDriver documentation notes the glass pane "catches any stray interactions" and that a stuck session can be interrupted by "breaking" the glass pane ([About WebDriver for Safari](https://developer.apple.com/documentation/webkit/about-webdriver-for-safari), read 2026-09-09). That is an interrupt and a visible orange-field window — a stop button and a signal, not a pre-action approval. Describe it that way.

---

## Limitations and requirements

- **macOS only, in practice.** Registration uses `/usr/bin/safaridriver` or the Safari Technology Preview app bundle — both macOS paths (EXTERNAL-PRIMARY, WebKit blog). The Safari 27 beta release notes state "Safari 27 beta is available for iOS 27 beta, iPadOS 27 beta, visionOS 27 beta, macOS 27 beta, macOS 26, and macOS Sequoia", but the MCP server is invoked from a macOS command line (EXTERNAL-PRIMARY, [Safari 27 beta release notes](https://developer.apple.com/documentation/safari-release-notes/safari-27-release-notes), read 2026-09-09).
- **Version floor.** Safari 27 beta or Safari Technology Preview 247 or later. Safari 27 beta is recorded as "Released July 20, 2026 — 27.0 beta (20625.1.24)". LOCAL-VERIFICATION (2026-09-09): `--mcp` is present in **shipping** Safari 27.0 on macOS 27.0 (build 26A5425a), so the "beta only" framing in the July blog post is now out of date on current systems.
- **Two settings must be on**, in two different Settings panes (see Setup above). Off by default.
- **One session at a time.** "Only one Safari browser instance can be active at any given time, and only one WebDriver session at a time can be attached to the browser instance" (EXTERNAL-PRIMARY, [About WebDriver for Safari](https://developer.apple.com/documentation/webkit/about-webdriver-for-safari), read 2026-09-09).
- **The user cannot interact with the automated window while a session runs** — the glass pane exists precisely to prevent that (EXTERNAL-PRIMARY, same page).
- **Apple has published no dedicated documentation page for it.** Apple's WebKit documentation index contains **zero** occurrences of "MCP" or "Model Context Protocol" (verified against `https://developer.apple.com/tutorials/data/documentation/webkit.json`, 2026-09-09). Apple's total documentation coverage is one sentence, repeated in two sets of release notes, plus the WebKit blog post. There is no reference page listing the tools, their parameters or their error semantics.
- **The `safaridriver` man page is stale.** `man safaridriver` on macOS 27.0 is dated 4/19/17, its SYNOPSIS omits `--mcp` entirely, and it still refers to the old "Enable Remote Automation" menu item (LOCAL-VERIFICATION, 2026-09-09).
- **No WWDC coverage.** The WWDC26 "Safari and Web Technologies Group Lab" session contains no mention of MCP, the Safari MCP server, AI agents or `safaridriver` (COMMUNITY-SIGNAL / EXTERNAL-PRIMARY-page-read, [developer.apple.com/videos/play/wwdc2026/8015/](https://developer.apple.com/videos/play/wwdc2026/8015/), read 2026-09-09). Chronologically consistent: WWDC26 preceded the July 2026 announcement.
- **Known issues:** Apple publishes none for the MCP server. The only self-declared rough edge is inside a tool description: `screenshot`'s `node` parameter is "(Currently no-op pending dispatcher support; falls back to viewport.)" (LOCAL-VERIFICATION, `tools/list`, 2026-09-09).
- **Server protocol version** is `2024-11-05`, an older MCP revision (LOCAL-VERIFICATION, `initialize` response, 2026-09-09).

---

## Licence and price

- **Price: Apple states none.** UNAVAILABLE as an Apple statement. INFERRED: it is included at no additional charge, because it is a flag on a binary that ships with Safari and macOS and no purchase, account or entitlement is mentioned anywhere. Safest published wording: "included with Safari; Apple lists no separate price."
- **Licence: UNAVAILABLE.** Neither the blog post nor the release notes state a licence for the MCP server. `safaridriver` is part of macOS and is governed by the macOS software licence agreement, not by an open-source licence grant published for this feature.
- **Not open source.** EXTERNAL-PRIMARY + verification: the binary at `/System/Cryptexes/App/usr/bin/safaridriver` is Apple-signed (`Identifier=com.apple.safaridriver`, `Authority=macOS Software Signing`) and closed; the implementation is not in the public WebKit tree. A code search of `WebKit/WebKit` returns **0** hits for `page_interactions`, **0** for `"--mcp"` and **0** for `modelcontextprotocol`; the single hit for `navigate_to_url` is an unrelated imported Selenium BiDi test file (`WebDriverTests/imported/selenium/py/test/selenium/webdriver/common/bidi_browsing_context_tests.py`) (LOCAL-VERIFICATION via GitHub code search, 2026-09-09). The tool names do not appear in `safaridriver`'s own strings either, so the implementation lives in Safari's WebDriver service, not in the driver binary.
- **No repository and no package.** Apple ships no repo, no npm package and no download for it. Beware: several GitHub projects named `safari-mcp` exist and are **not** Apple's — notably `achiya-automation/safari-mcp`, an unrelated third-party AppleScript-based server advertising 97 tools. Do not conflate them in a comparison (COMMUNITY-SIGNAL, [github.com/achiya-automation/safari-mcp](https://github.com/achiya-automation/safari-mcp), read 2026-09-09).

---

## Arbitrary public sites vs local development

- **Apple's stated intent is development and debugging.** The release-notes sentence is explicit: "Allow your agent to connect to a Safari browser for development and debugging via the Safari MCP server" (EXTERNAL-PRIMARY, both release notes, read 2026-09-09). Every use case in the blog is a developer testing their own site — "Web development in Safari", "Improve compatibility with Safari", "Analyze performance", "Check for accessibility", "Verify any user state" — and every suggested prompt says *my site*: "Find bugs on my site in Safari", "How accessible is my site in Safari?", "See how my website performs in Safari".
- **But Apple states no technical restriction, and there is none in the schema.** `navigate_to_url` takes a free-form `url` string with no host, scheme or origin constraint, and `create_tab` likewise (LOCAL-VERIFICATION, `tools/list`, 2026-09-09). Apple nowhere says it is limited to localhost or to sites you own.
- Correct published wording: Apple frames it for development and debugging of your own site and states no restriction preventing navigation to any URL. Do **not** write that Apple restricts it to local development, and do **not** write that Apple endorses it for general web automation.

---

## Facts safe to publish in a comparison table

Each is quotable verbatim as written.

1. "Apple's Safari MCP server exposes 17 tools." — [WebKit blog](https://webkit.org/blog/18136/introducing-the-safari-mcp-server-for-web-developers/) (tool table, 17 rows), corroborated by the server's own `tools/list` response. Read 2026-09-09.
2. "It is started as `safaridriver --mcp` and communicates over stdio: Apple's binary describes the flag as 'Run as an MCP (Model Context Protocol) server using stdio transport. Reads JSON-RPC from stdin, writes to stdout.'" — `safaridriver --help`, macOS 27.0, 2026-09-09.
3. "It requires Safari 27 beta or Safari Technology Preview 247 or later." — [WebKit blog](https://webkit.org/blog/18136/introducing-the-safari-mcp-server-for-web-developers/), read 2026-09-09.
4. "Two Safari settings must be enabled: 'Show features for web developers' under Safari > Settings > Advanced, and 'Allow remote automation and external agents' under Safari > Settings > Developer." — [WebKit blog](https://webkit.org/blog/18136/introducing-the-safari-mcp-server-for-web-developers/), read 2026-09-09.
5. "Apple states the server 'runs entirely on your local machine and makes no network calls of its own.'" — [WebKit blog](https://webkit.org/blog/18136/introducing-the-safari-mcp-server-for-web-developers/), read 2026-09-09.
6. "Apple states it 'does not have access to your personal information in Safari (e.g. AutoFill or other browser activity).'" — [WebKit blog](https://webkit.org/blog/18136/introducing-the-safari-mcp-server-for-web-developers/), read 2026-09-09.
7. "Apple states captured page content, screenshots and console logs go 'directly to the agent you're running — not to Apple', and that 'What happens to that data from there depends on the agent and model you're using.'" — [WebKit blog](https://webkit.org/blog/18136/introducing-the-safari-mcp-server-for-web-developers/), read 2026-09-09.
8. "The only safeguard Apple names is choice of agent: 'As with any agent you give access to your browser, only use ones you trust.'" — [WebKit blog](https://webkit.org/blog/18136/introducing-the-safari-mcp-server-for-web-developers/), read 2026-09-09.
9. "Apple documents no per-action confirmation or approval step: none of the 17 tools requests user confirmation, and the server returns no MCP tool annotations — each tool definition carries only `name`, `description` and `inputSchema`, with no `readOnlyHint` or `destructiveHint`." — WebKit blog tool table + `tools/list` response, 2026-09-09.
10. "Apple's framing is agent autonomy: the server 'enables your agent to do more debugging and troubleshooting on its own', and 'All you need is an initial request to get started ... your agent can take it from there.'" — [WebKit blog](https://webkit.org/blog/18136/introducing-the-safari-mcp-server-for-web-developers/), read 2026-09-09.
11. "Apple's release notes list it under WebDriver > New Features: 'Allow your agent to connect to a Safari browser for development and debugging via the Safari MCP server.'" — [Safari 27 beta release notes](https://developer.apple.com/documentation/safari-release-notes/safari-27-release-notes) and [Safari Technology Preview 247 release notes](https://developer.apple.com/documentation/safari-technology-preview-release-notes/stp-release-247), read 2026-09-09.
12. "Apple's WebDriver documentation states that automation windows are 'isolated from normal browsing windows, user settings, and preferences', that 'an automation session always starts from a clean slate', and that it 'can't access Safari's browsing history, AutoFill data, or other sensitive information available in a normal browsing session.'" — [About WebDriver for Safari](https://developer.apple.com/documentation/webkit/about-webdriver-for-safari), read 2026-09-09. (Attribute to Apple's WebDriver documentation, not to the MCP announcement.)
13. "Apple's WebDriver documentation states that 'only one WebDriver session at a time can be attached to the browser instance.'" — [About WebDriver for Safari](https://developer.apple.com/documentation/webkit/about-webdriver-for-safari), read 2026-09-09.
14. "While a session runs, Safari 'installs a transparent "glass pane" over the automation windows', which 'catches any stray interactions (mouse, keyboard, resizing, and so on)' — so the user cannot interact with the automated window." — [About WebDriver for Safari](https://developer.apple.com/documentation/webkit/about-webdriver-for-safari), read 2026-09-09.
15. "Apple has published no dedicated developer documentation page for the Safari MCP server; its WebKit documentation index contains no occurrence of 'MCP' or 'Model Context Protocol'." — verified against `https://developer.apple.com/tutorials/data/documentation/webkit.json`, 2026-09-09.
16. "It is not open source: the implementation ships in Apple's signed `safaridriver` binary and is absent from the public WebKit repository (0 hits for `page_interactions`, `--mcp` or `modelcontextprotocol` in `WebKit/WebKit`)." — GitHub code search + local `codesign` inspection, 2026-09-09.
17. "Apple publishes no price and no licence terms for it; it ships as part of Safari." — absence across [WebKit blog](https://webkit.org/blog/18136/introducing-the-safari-mcp-server-for-web-developers/) and both release-notes pages, read 2026-09-09.
18. "Apple frames every documented use case around the developer's own site — 'Find bugs on my site in Safari', 'How accessible is my site in Safari?' — while stating no restriction on which URLs may be navigated." — [WebKit blog](https://webkit.org/blog/18136/introducing-the-safari-mcp-server-for-web-developers/) + `navigate_to_url` schema, read 2026-09-09.
19. "The server reports MCP protocol version 2024-11-05 and identifies itself as `Safari` version `1.0.0`." — `initialize` response, macOS 27.0, 2026-09-09.

---

## Do not publish

Tempting, and each is wrong, unsourced, or attributed to the wrong Apple document.

1. **"The blog lists fifteen tools" / "15 tools".** Wrong. 17, verified twice. Third-party posts saying 15, 16 or 17 are inconsistent; do not cite them for the count.
2. **"Apple says it cannot access your cookies / saved logins / open tabs / browsing history."** Apple's MCP announcement says none of that. It names AutoFill and "other browser activity" only. The history/AutoFill wording exists in Apple's *WebDriver* documentation, about automation sessions generally — cite it there or not at all.
3. **"Apple says it runs in an isolated WebDriver session."** Apple has not written this sentence about the MCP server. It is our well-supported inference from three primary links. Publish it as an inference, or quote the WebDriver documentation with correct attribution.
4. **"It cannot touch your logged-in sessions."** Same problem, and additionally untested here: remote automation was off on the test machine, so we never observed session behaviour. Do not assert it as verified.
5. **"It drives your real, already-open Safari window."** Unverified and probably false; the WebDriver isolation documentation points the other way. Also do not assert the opposite as fact.
6. **"Apple restricts it to localhost / local development only."** Apple states no such restriction, and the `navigate_to_url` schema imposes none.
7. **"There is a confirmation prompt before actions."** There is not, on the evidence. Equally, do not write "Apple explicitly states there is no confirmation step" — Apple states nothing either way; the finding is a documented absence, and must be worded as an absence.
8. **"macOS 27 / Safari 27 required."** Overstated. Apple's floor is Safari 27 beta *or* Safari Technology Preview 247+, and Safari 27 beta is documented as available on macOS 26 and macOS Sequoia too. Our `--mcp` observation on macOS 27.0 is one data point, not a requirement.
9. **"Available on iPhone / iPad / Vision Pro."** Safari 27 beta spans those platforms, but the MCP server is launched from a macOS binary path. Do not imply mobile support.
10. **"Announced at WWDC26."** It was not; no WWDC26 session mentions it. It was announced on the WebKit blog on 1 July 2026.
11. **Anything from `achiya-automation/safari-mcp`** (97 tools, AppleScript, drives real Safari, keeps logins, open source). That is a third-party project, not Apple's. Attributing any of it to Apple would be the worst error available here.
12. **"Free" as an Apple claim.** Apple says nothing about price. Write "included with Safari; Apple lists no separate price."
13. **Performance, CPU or speed comparisons.** Apple publishes no numbers, and we measured none.

---

## Unavailable

- **A dedicated Apple documentation page for the Safari MCP server.** Does not exist as of 2026-09-09; the WebKit documentation index has zero MCP references. Total Apple documentation: one release-notes sentence (repeated in two release-note sets) plus the WebKit blog post.
- **Apple's stated licence terms** for the MCP server. None published.
- **Apple's stated price.** None published.
- **Any Apple statement about cookies, logged-in sessions or browsing history in the context of the MCP server.** Only "AutoFill or other browser activity".
- **Any Apple statement about profile isolation in the context of the MCP server.** Only inferable from the WebDriver documentation.
- **Any Apple-published known-issues list** for the MCP server.
- **A public repository or package.** None; implementation absent from the open-source WebKit tree.
- **WWDC material.** None found.
- **Empirical confirmation of session isolation, cookie access, and per-window vs per-tab behaviour.** Not obtained: "Allow remote automation" is disabled on the test machine and enabling it is a configuration change requiring the user's own authorisation. It was not enabled, and no page was ever loaded or acted upon. Closing this gap needs an explicit go-ahead to enable the setting and run one observation session.
- **An updated `safaridriver` man page** covering `--mcp`. The shipped page is dated 4/19/17 and omits the flag.

---

## Sources

| Source | Label | Read |
|---|---|---|
| [webkit.org/blog/18136 — Introducing the Safari MCP server for web developers](https://webkit.org/blog/18136/introducing-the-safari-mcp-server-for-web-developers/) (Jul 1, 2026, Saron Yitbarek; carries an "Update:" covering Safari 27 beta + STP 247) | EXTERNAL-PRIMARY | 2026-09-09 |
| [Safari 27 Beta Release Notes](https://developer.apple.com/documentation/safari-release-notes/safari-27-release-notes) — "Released July 20, 2026 — 27.0 beta (20625.1.24)"; WebDriver > New Features (radar 176038457) | EXTERNAL-PRIMARY | 2026-09-09 |
| [Safari Technology Preview 247 Release Notes](https://developer.apple.com/documentation/safari-technology-preview-release-notes/stp-release-247) — same WebDriver > New Features line | EXTERNAL-PRIMARY | 2026-09-09 |
| [About WebDriver for Safari](https://developer.apple.com/documentation/webkit/about-webdriver-for-safari) — isolated automation windows, glass panes, one session at a time | EXTERNAL-PRIMARY | 2026-09-09 |
| [Testing with WebDriver in Safari](https://developer.apple.com/documentation/webkit/testing-with-webdriver-in-safari) — `safaridriver` locations, enabling WebDriver | EXTERNAL-PRIMARY | 2026-09-09 |
| [WWDC26 — Safari and Web Technologies Group Lab](https://developer.apple.com/videos/play/wwdc2026/8015/) — no MCP mention | EXTERNAL-PRIMARY (absence) | 2026-09-09 |
| Apple's shipped binary: `safaridriver --help`; `safaridriver --mcp` `initialize` + `tools/list`; `codesign` on `/System/Cryptexes/App/usr/bin/safaridriver`; `man safaridriver`; macOS 27.0 build 26A5425a, Safari 27.0 | LOCAL-VERIFICATION | 2026-09-09 |
| `https://developer.apple.com/tutorials/data/documentation/webkit.json` — WebKit doc index, 0 MCP references | EXTERNAL-PRIMARY (absence) | 2026-09-09 |
| GitHub code search over `WebKit/WebKit` for `page_interactions`, `--mcp`, `modelcontextprotocol`, `navigate_to_url` | LOCAL-VERIFICATION | 2026-09-09 |
| [github.com/achiya-automation/safari-mcp](https://github.com/achiya-automation/safari-mcp) — unrelated third-party project, do not conflate | COMMUNITY-SIGNAL | 2026-09-09 |
| Third-party write-ups ([9to5Mac](https://9to5mac.com/2026/07/01/safaris-new-mcp-server-lets-coding-agents-inspect-and-debug-websites/), [MacRumors](https://www.macrumors.com/2026/07/01/apple-releases-safari-technology-preview-247/), [ai.rud.is](https://ai.rud.is/posts/2026-07-02-safari-now-has-a-built-in-mcp-server-and-its-actually-good), [Daring Fireball](https://daringfireball.net/linked/2026/07/02/safari-mcp)) — inconsistent tool counts (15/16/17); not used for any published fact | COMMUNITY-SIGNAL | 2026-09-09 |
