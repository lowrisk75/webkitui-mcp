# Agentic browser approval landscape

Date: 2026-09-09

Question: Is per-action human approval before dispatch actually rare or unique among agentic browser tools, or do competitors already do it?

Method note: every URL below was read on 2026-09-09. Findings are labelled
EXTERNAL-PRIMARY (vendor's own docs, repo or source), COMMUNITY-SIGNAL (third-party
blog, forum, press, security research) or UNAVAILABLE. Direct `WebFetch` of
`openai.com`, `help.openai.com` and `perplexity.ai` returned HTTP 403; wording from
those vendor pages was recovered through search-engine extraction of the same pages
and is labelled EXTERNAL-PRIMARY (unverified by direct fetch). Nothing in this
document is inferred from a marketing adjective.

## Verdict

Per-action human approval before dispatch is rare but **not unique**: Anthropic's own
Claude in Chrome ships a "Manually approve" mode that pauses before each action, and
Claude Code gives any MCP server a per-call, unbypassable prompt via
`_meta["anthropic/requiresUserInteraction"]`, so the *mechanism* is available to every
competitor and simply unused — across fourteen browser MCP servers read today, not one
implements its own pre-dispatch gate, and every shipped consumer agentic browser
(OpenAI, Perplexity, Google) gates only on a model-classified *category* such as
purchase or login, letting ordinary clicks, navigations and fills reach the page with
no human in the loop. What is genuinely distinctive is narrower than "per-action
approval": an **OS-owned** dialog whose text is computed by the server from a freshly
re-resolved target rather than supplied by the agent, which no browser MCP server and
no shipped agentic browser was found to do. The closest competitors are Claude in
Chrome (per-action, but client-owned, mode-switchable and suppressible per site) and
`brainfuel/mcp-browser` (native WKWebView, but confirms only downloads, uploads and
page dialogs).

## Per product

### Apple — Safari MCP server (`safaridriver --mcp`)

EXTERNAL-PRIMARY: <https://webkit.org/blog/18136/introducing-the-safari-mcp-server-for-web-developers/>,
<https://webkit.org/blog/6900/webdriver-support-in-safari-10/>. Ships in Safari 27 beta
and Safari Technology Preview 247.

1. **Confirmation before dispatch: none documented.** The only human step is a one-time
   opt-in: "Safari > Settings > Developer > check 'Allow remote automation and external
   agents.'" That is a session/installation grant, not per action, and it is an
   application setting rather than a dialog. No per-action approval appears anywhere in
   the post. `page_interactions` performs "click, type, scroll, hover, keyPress, etc."
   in sequence — a *batched* action tool, which is structurally the opposite of a
   per-action gate.
2. **Arbitrary JavaScript: yes — `evaluate_javascript`**, "Execute JavaScript code
   within the page and return the result". The 17 tools read from the post:
   `browser_console_messages`, `browser_dialogs`, `close_tab`, `create_tab`,
   `evaluate_javascript`, `get_network_request`, `get_page_content`,
   `list_network_requests`, `list_tabs`, `navigate_to_url`, `page_info`,
   `page_interactions`, `screenshot`, `set_emulated_media`, `set_viewport_size`,
   `switch_tab`, `wait_for_navigation`. No raw CDP (WebKit, not Chromium).
3. **Profile: an isolated automation window, not the user's logged-in Safari.** Apple's
   WebDriver design, EXTERNAL-PRIMARY: "Test execution is confined to special Automation
   windows that are isolated from normal browsing windows, user settings, and
   preferences", and restrictions prevent access to "Safari's normal browsing history,
   AutoFill data, or other sensitive information". Also "only one WebDriver session can
   be attached to the browser instance at a time".
4. **Authenticated sessions and credentials:** the MCP post states the server "does not
   have access to your personal information in Safari (e.g. AutoFill or other browser
   activity)". Community reporting (COMMUNITY-SIGNAL,
   <https://mcp.directory/blog/safari-mcp-complete-guide-2026>,
   <https://ai.rud.is/posts/2026-07-02-safari-now-has-a-built-in-mcp-server-and-its-actually-good>)
   states every session starts with no existing cookies or logins. Apple's MCP post
   itself does not state the session model, so treat "no logins" as third-party.
   **Consequence: Apple's server cannot do authenticated work at all** — it is a
   web-developer debugging tool, not a competitor for logged-in tasks.
5. **Licence and price:** bundled with Safari, no separate licence stated. Free.
   Licence terms for the server specifically: UNAVAILABLE.

### achiya-automation/safari-mcp — community macOS-native, real Safari

EXTERNAL-PRIMARY: <https://raw.githubusercontent.com/achiya-automation/safari-mcp/main/README.md>.
This is the closest thing in the field to WebKitUI's positioning on authenticated
sessions, and it is the sharpest contrast on safety.

1. **Confirmation: none.** No approval dialog, prompt or human-in-the-loop step. The
   only gate is macOS TCC (System Settings > Privacy & Security > Automation > Safari),
   granted **once to the parent process** (the IDE or terminal), i.e. session-level OS
   consent not implemented by the server. Worse for the comparison: the repo ships a
   `dialog-interceptor.js` that patches `window.alert/confirm/prompt` before page
   scripts run — it *removes* page-level confirmation rather than adding one.
2. **Arbitrary JavaScript: yes — `safari_evaluate`** ("Execute arbitrary JavaScript,
   return result") and **`safari_eval_file`** (executes JS read from a file path,
   bypassing inline size limits), plus `safari_run_script` for batched actions.
3. **Profile: the user's real logged-in Safari.** Verbatim: "Your AI drives the
   **Safari you're already logged into** — Gmail, GitHub, Ahrefs, Slack, banking", and
   "keeps all logins, cookies, sessions". It contrasts itself with Apple's server, which
   "drives an isolated WebDriver automation session".
4. **Credentials:** no credential-handling story. Security section claims only local
   communication, no telemetry, and open source. Arbitrary JS against a logged-in
   banking session with no gate is the entire risk surface, and the README does not
   acknowledge it.
5. **Licence and price:** MIT, free; optional paid support from Achiya Automation.

### brainfuel/mcp-browser — native SwiftUI + WKWebView MCP browser

EXTERNAL-PRIMARY: <https://raw.githubusercontent.com/brainfuel/mcp-browser/main/README.md>,
<https://glama.ai/mcp/servers/brainfuel/mcp-browser>. **The closest architectural twin
to WebKitUI MCP** — native macOS app, WKWebView, in-process MCP server on 127.0.0.1
with a per-launch bearer token and Host-header validation against DNS rebinding.

1. **Confirmation: partial, and narrow.** Verbatim: "User confirmation for downloads,
   uploads, and any `dialog` interactions"; `upload_file` is "(gated by user
   permission)". **No confirmation on `click`, `fill`, `submit`, `type_text`,
   `press_key`, `eval_js`, `set_cookie`.** It ships an action log in Settings so "you can
   see exactly what an agent has done" — after-the-fact audit, not a pre-dispatch gate.
   This is the only browser MCP server found with any pre-dispatch confirmation of its
   own, and it does not cover clicks.
2. **Arbitrary JavaScript: yes — `eval_js`.** No raw CDP.
3. **Profile: its own WKWebView window** — "a real browser window on your Mac that you
   log into, navigate, and use yourself", with local persistent cookies/history
   separate from Safari's cookie jar.
4. **Credentials:** the user logs in manually in the app's own window; cookies persist
   locally. No credential-injection or secret-handling primitive documented.
5. **Licence and price:** MIT, free. Runs un-sandboxed.

### Epistates/MCPSafari — Swift MCP server + Safari Web Extension

EXTERNAL-PRIMARY: <https://raw.githubusercontent.com/Epistates/MCPSafari/main/README.md>.

1. **Confirmation: none.** Input validation only (URL-scheme allowlist, regex caps,
   file-size limits); actions dispatch immediately.
2. **Arbitrary JavaScript: yes — `javascript_tool`** (falls back to the extension's
   isolated world where page CSP forbids `unsafe-eval`).
3. **Profile: the user's active real Safari**, via a Manifest V3 Safari Web Extension
   bridged over WebSocket (ports 8089–8098).
4. **Credentials:** UNAVAILABLE — no credential or authenticated-session policy stated.
5. **Licence and price:** MIT, free.

### Microsoft — Playwright MCP

EXTERNAL-PRIMARY: <https://raw.githubusercontent.com/microsoft/playwright-mcp/main/README.md>,
<https://raw.githubusercontent.com/microsoft/playwright-mcp/main/LICENSE>.

1. **Confirmation: none of its own, by explicit design.** The README says in full:
   "Playwright MCP is **not** a security boundary." It delegates the gate to the client
   in as many words: "always rely on client-level permissions for true security."
   The interesting detail is the shape of that delegation — action tools take an
   **optional** `element` string described as "Human-readable element description used
   to obtain permission to interact with the element". That is a *model-supplied* label
   the client may render in its own prompt: the agent writes the text the human reads,
   and may omit it entirely. This is precisely the failure mode an OS-owned,
   server-computed dialog is meant to close.
   COMMUNITY-SIGNAL claims that Playwright MCP "automatically triggers elicitation
   requests" for login walls and MFA (testdino.com, qaskills.sh) **do not check out**:
   the README and <https://playwright.dev/mcp/introduction> contain no occurrence of
   elicitation, human-in-the-loop, MFA, confirmation or approval. Treat that claim as
   unverified.
2. **Arbitrary JavaScript: yes, twice.** `browser_evaluate` ("Evaluate JavaScript
   expression on page or element") and `browser_run_code_unsafe`, whose own description
   reads "Unsafe: executes arbitrary JavaScript in the Playwright server process and is
   RCE-equivalent". No raw CDP endpoint. Tools are grouped behind opt-in capability
   flags (`--caps=vision,pdf,devtools,network,storage,testing`), which gates *surface*,
   not *authority*.
3. **Profile: persistent by default, and it keeps your logins.** "All the logged in
   information will be stored in the persistent profile." `--user-data-dir` points it
   anywhere, including a real profile; `--isolated` is opt-in and discards state on
   close; `--storage-state` loads cookies and localStorage into an isolated context.
4. **Credentials:** `--secrets <path>` in dotenv format, used defensively rather than
   for injection: "Secrets are used to replace matching plain text in the tool responses
   to prevent the LLM from accidentally getting sensitive data." Full cookie and
   localStorage read/write tools are exposed under `--caps=storage`.
   `--allowed-origins`/`--blocked-origins` both carry the note that each "*does not*
   serve as a security boundary".
5. **Licence and price:** Apache-2.0, free.

### Google — Chrome DevTools MCP

EXTERNAL-PRIMARY: <https://raw.githubusercontent.com/ChromeDevTools/chrome-devtools-mcp/main/README.md>,
<https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/tool-reference.md>,
<https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/configuration.md>,
LICENSE.

1. **Confirmation: none.** No approval mechanism anywhere in README, tool reference or
   configuration guide. Chrome 144 shows a permission dialog when the server *attaches*
   to a running instance — but that is Chrome's dialog, **per connection, then
   unlimited**, and `--autoConnect` targets the default profile (COMMUNITY-SIGNAL:
   <https://agenticcontrolplane.com/mcp-controls/chrome-devtools>, which puts the gap
   bluntly: "No approval mechanism — nothing can hold `fill_form` on a checkout page or
   `evaluate_script` in an attached session for a human", and "The newest class of MCP
   servers — those that drive a browser — ship with the least native control").
2. **Arbitrary JavaScript: yes — `evaluate_script`**, "Runs a JavaScript function within
   the target webpage, returning JSON-serializable outputs". Input automation tools:
   `click`, `click_at`, `drag`, `fill`, `fill_form`, `handle_dialog`, `hover`,
   `press_key`, `type_text`, `upload_file`. It is built on Puppeteer, so CDP is the
   substrate rather than an exposed tool.
3. **Profile: a persistent dedicated profile by default, with attach-to-real-Chrome
   available.** Default user data dir is
   `$HOME/.cache/chrome-devtools-mcp/chrome-profile$CHANNEL_SUFFIX_IF_NON_STABLE` —
   reused across sessions. `--isolated` "creates a temporary user-data-dir that is
   automatically cleaned up". `--browserUrl` connects "to a running, debuggable Chrome
   instance", as does `--wsEndpoint`.
4. **Credentials:** no credential primitive. The disclaimer is the whole policy:
   "`chrome-devtools-mcp` exposes content of the browser instance to the MCP clients
   allowing them to inspect, debug, and modify any data in the browser or DevTools.
   Avoid sharing sensitive or personal information that you don't want to share with MCP
   clients." The configuration guide contains **no** warning about pointing it at a
   personal logged-in profile.
5. **Licence and price:** Apache-2.0, free.

### Browser MCP (browsermcp.io)

EXTERNAL-PRIMARY: <https://raw.githubusercontent.com/BrowserMCP/mcp/main/README.md>,
GitHub API licence field.

1. **Confirmation: none documented.**
2. **Arbitrary JavaScript: UNAVAILABLE** — not stated either way in the README. It is a
   Playwright MCP fork, "adapted… in order to automate the user's browser rather than
   creating new browser instances".
3. **Profile: the user's real logged-in browser via a Chrome extension.** "Uses your
   existing browser profile, keeping you logged into all your services." Also "Avoids
   basic bot detection and CAPTCHAs by using your real browser fingerprint."
4. **Credentials:** none beyond inheriting the live session. "Since automation happens
   locally, your browser activity stays on your device."
5. **Licence and price:** Apache-2.0, free.

### Browserbase / Stagehand

EXTERNAL-PRIMARY: repo sources under
<https://github.com/browserbase/mcp-server-browserbase> (`src/tools/act.ts`,
`src/tools/index.ts`, `src/tools/__tests__/tools.test.ts`, `src/mcp/resources.ts`,
LICENSE), <https://raw.githubusercontent.com/browserbase/stagehand/main/README.md>,
<https://docs.stagehand.dev/v4/reference/page.md>,
<https://docs.browserbase.com/features/contexts>,
<https://docs.browserbase.com/features/session-live-view>,
<https://docs.browserbase.com/platform/identity/overview>,
<https://www.browserbase.com/pricing>.

1. **Confirmation: none.** The MCP `act` tool ("Perform an action on the page", schema
   `{action: string}`) delegates straight to `stagehand.act()` with no gate; the README
   and MCP docs contain no occurrence of confirmation, approval, human-in-the-loop or
   `requires_approval`. The nearest feature is **Session Live View**, an embeddable
   iframe where a human can "watch, click, type, and scroll in real-time" — it runs
   *alongside* the agent and does not pause it, and it is read/write unless the
   developer adds `pointer-events: none`. That is concurrent takeover, not approval.
2. **Arbitrary JavaScript: not over MCP — notable.** The MCP server exposes exactly six
   tools, asserted by its own test file: `start`, `end`, `navigate`, `act`, `observe`,
   `extract`. No `evaluate`, no CDP; `screenshot` is explicitly asserted *absent*.
   **This means WebKitUI is not the only MCP browser server without a JS-eval tool.**
   The Stagehand SDK underneath does expose arbitrary JS: `page.evaluate()` ("Evaluate
   JavaScript in the page and return its result") and `addInitScript()`. Discrepancy:
   <https://www.browserbase.com/mcp> still markets screenshots for the hosted
   `mcp.browserbase.com` endpoint; whether the hosted tool set differs from the repo is
   UNAVAILABLE without an API key.
3. **Profile: remote cloud browsers are the product path.** "Fleets of headless browsers
   at scale with isolated sessions and global infrastructure." Stagehand local mode
   supports `executablePath`, `userDataDir`, `preserveUserDataDir`, and
   `localBrowser.connect({cdpUrl})`, so it *can* drive a real profile, but the docs frame
   local mode as "development, debugging, and custom browser setups".
4. **Credentials — the most explicit policy in the field.** Contexts persist the
   Chromium user data directory (cookies, localStorage, IndexedDB, sessionStorage,
   service workers, form autofill), and verbatim: "Context data can include stored
   credentials and other sensitive browsing data. Because of this, Contexts are uniquely
   encrypted at rest to ensure security." Stagehand's own guidance: "A persisted profile
   carries cookies, tokens, and site data across runs. **Treat the directory or context
   ID as a credential**." Agent Identity adds 1Password retrieval, 2FA/OAuth handling,
   CAPTCHA solving and Web Bot Auth signed-agent attestation — none of which is an
   action gate.
5. **Licence and price:** MCP server Apache-2.0; Stagehand MIT. Free $0/mo (3 concurrent,
   1 browser hour); Developer $20/mo; Startup $99/mo; Scale custom.

### Browser Use

EXTERNAL-PRIMARY: <https://raw.githubusercontent.com/browser-use/browser-use/main/browser_use/tools/service.py>,
`browser_use/mcp/server.py`, LICENSE,
<https://docs.browser-use.com/customize/hooks>,
<https://docs.browser-use.com/cloud/agent/human-in-the-loop>,
<https://docs.browser-use.com/open-source/customize/browser/all-parameters>,
<https://docs.browser-use.com/cloud/guides/secrets>,
<https://docs.browser-use.com/cloud/guides/1password>,
<https://browser-use.com/pricing.md>.

1. **Confirmation: none.** The full action registry was read: no confirmation gate on
   any action. The only guards are an `allowed_domains` check, upload-path-traversal
   validation, and a 180 s per-action wall clock. Two adjacent features, neither a
   pre-dispatch gate: (a) developer-written hooks `on_step_start`/`on_step_end` — and
   `on_step_end` fires "after the agent has executed **all the actions** for the current
   step", so this is per *step*, not per action, and it is code you write rather than
   shipped UI; (b) cloud takeover *after* a run stops, which you must ask for in the
   prompt ("Open the login page and stop for human review"). Community demand confirms
   absence: issues #221, #333, #1704, discussion #1024 (COMMUNITY-SIGNAL). Cloud MCP is
   worse for the client-gate argument: `run_session` means one client approval covers an
   entire autonomous session.
2. **Arbitrary JavaScript: yes — `evaluate`**, "Execute browser JavaScript",
   implemented via CDP `Runtime.evaluate`. The registry also includes local-filesystem
   actions `write_file`, `replace_file`, `read_file`, `upload_file`. The OSS MCP server
   does not surface `browser_evaluate`, but `retry_with_browser_use_agent` hands the full
   registry — including `evaluate` — to an autonomous loop under a single tool call.
3. **Profile: first-class support for the user's real Chrome.** `cdp_url`,
   `executable_path`, `user_data_dir`, `profile_directory` (default `'Default'`), and a
   `Browser.from_system_chrome()` helper whose own docs warn "You may need to fully close
   Chrome before using this". README: "Reuse your existing Chrome profile with saved
   logins." Cloud mode runs a forked Chromium.
4. **Credentials:** `sensitive_data` masks logging; cloud Secrets are domain-scoped
   (`{"github.com": "username:password123"}`); auth profiles persist "cookies, local
   storage, and login state"; 1Password integration auto-fills including TOTP, with the
   claim "The actual username, password, and 2FA codes are filled in programmatically —
   keeping your secrets hidden from the AI model." No per-fill human approval. No
   encryption-at-rest statement for cloud auth profiles: UNAVAILABLE.
5. **Licence and price:** MIT. Free tier $0 with a one-time $15 credit; pay-as-you-go
   credits; $0.02/browser-hour; proxies $5/GB residential.

### Anthropic — Claude in Chrome

EXTERNAL-PRIMARY: <https://support.claude.com/en/articles/12902446-claude-in-chrome-permissions-guide>.
COMMUNITY-SIGNAL for GA and pricing: <https://ccleaks.com/news/claude-in-chrome-generally-available-aug-2026>,
<https://claude.com/pricing>. **This is the strongest counter-example in the field.**

1. **Confirmation: yes, and genuinely per-action in one mode.** Three modes:
   - **"Manually approve (Manual)"** (formerly "Ask before acting") — "Claude pauses and
     requests approval before each action"; the human chooses Allow or Deny.
   - **"Automatically approve (Auto)"** — Claude continues working, a classifier reviews
     actions for safety, and it pauses only when needed.
   - **"Skip all approvals (Skip)"** (formerly "Act without asking") — no pausing,
     nothing checks actions automatically.
   Approval scope is selectable per prompt: "Allow this action" versus **"Always allow
   actions on this site"**, which grants ongoing permission for multiple actions. A
   fixed set always requires approval regardless of mode: modifying permissions
   settings, granting authorizations, and inputting potentially sensitive information
   into websites. **Where it appears: the extension side panel, Claude Cowork or Claude
   Code — not browser chrome, and not an OS dialog.**
   Two limits matter for the comparison: the per-action gate is one *mode among three*
   that the user can switch off, and "Always allow actions on this site" collapses it to
   a site grant. Whether the dialog names the specific target element, destination URL
   or exact value to be typed is **UNAVAILABLE** — the permissions guide describes a
   plan-approval view listing which websites Claude may access, and does not quote the
   per-action dialog's wording. Field reports indicate the site-permission plumbing has
   been unreliable in practice (COMMUNITY-SIGNAL: anthropics/claude-code issues #74715,
   #85999, #66125, #26779 — including one titled "site permissions can be bypassed via
   direct LevelDB write").
2. **Arbitrary JavaScript: yes.** The extension's MCP surface includes a
   `javascript_tool` alongside `computer`, `navigate`, `read_page`, `form_input`,
   `read_console_messages`, `read_network_requests`, `browser_batch` and others
   (EXTERNAL-PRIMARY: the tool namespace `mcp__claude-in-chrome__*` as exposed to Claude
   Code, observed 2026-09-09).
3. **Profile: the user's real Chrome.** It is a Chrome extension operating in the
   user's existing session, opening pages in new tabs. Whether it can be pointed at a
   separate profile: UNAVAILABLE from the permissions guide.
4. **Credentials:** the permissions guide does not address passwords, autofill or
   credential handling — UNAVAILABLE. The only related commitment is that "inputting
   potentially sensitive information into websites" always requires approval.
5. **Licence and price:** proprietary, paid plans only (not on Free). Pro $17–20/mo, Max
   from $100/mo, Team $25–30/user/mo (COMMUNITY-SIGNAL for the figures).

### OpenAI — ChatGPT Work, cloud browser, built-in browser (Operator / agent / Atlas all retired)

**The comparators named in most competitive decks no longer exist.** EXTERNAL-PRIMARY
by direct fetch: <https://en.wikipedia.org/wiki/OpenAI_Operator> — Operator "shut down on
August 31, 2025"; ChatGPT agent was "removed from ChatGPT in early August 2026 without
an advance deprecation notice"; OpenAI "directed remaining users to ChatGPT Work and to a
separate cloud browser feature". EXTERNAL-PRIMARY by direct fetch:
<https://9to5mac.com/2026/07/09/openai-is-discontinuing-chatgpt-atlas-its-standalone-desktop-browser/>
— Atlas's "current targeted date for deprecation is 8/9", replaced by browser
capabilities inside the ChatGPT desktop app plus ChatGPT Work and Codex.

1. **Confirmation: category-gated, not per action.** EXTERNAL-PRIMARY (unverified by
   direct fetch, 403):
   <https://help.openai.com/en/articles/20001277-using-the-built-in-browser-in-the-chatgpt-desktop-app>
   — "ChatGPT asks for confirmation before sensitive activities, including sharing
   personal information, making purchases, deleting data, changing account permissions,
   or sending messages on your behalf", and, notably stronger than Perplexity, "It asks
   for your confirmation immediately before sending it, **even if you previously approved
   the website or task**." Release notes: "ChatGPT Work will always ask for confirmation
   before consequential actions, such as completing a reservation or payment." Atlas-era
   wording was softer still: "trained to ask before taking many important actions" and
   "will pause to ensure you're watching it take actions on specific sensitive sites".
   Ordinary clicks, navigations and form fills are dispatched with no human step, and
   the trigger is a **model judgment** ("trained to ask", "when needed"), not a
   mechanical interception. Where it appears: in-chat / in-app. OS-level confirmation:
   UNAVAILABLE (none found).
   Asymmetry worth recording: OpenAI **does** implement a per-call gate for MCP tools —
   <https://help.openai.com/en/articles/12584461-developer-mode-and-mcp-apps-in-chatgpt>:
   "Write actions by default require confirmation", with an optional per-conversation
   remembered choice. Its own browser-action path is gated more weakly than its tool path.
2. **Arbitrary JavaScript: no, in agent mode.**
   <https://help.openai.com/en/articles/12628199-using-ask-chatgpt-sidebar-and-chatgpt-agent-on-atlas>
   — in agent mode it "cannot run code in the browser, download files, or install
   extensions". Whether that still holds for the current built-in browser: UNAVAILABLE
   (the current doc lists downloads and extensions as browser features).
3. **Profile: separate, never the user's Chrome.** Cloud browser "gives ChatGPT Work its
   own browser on a separate computer in the cloud". The desktop built-in browser "uses
   its own browser state": "If you are already signed in to the same website in Chrome,
   you may need to sign in again in the built-in browser."
4. **Credentials:** a "logged out mode, where it won't use any pre-existing cookies and
   won't be logged into any of your online accounts without your specific approval"; the
   agent "cannot access… saved passwords, or use autofill data"; for cloud sign-in,
   "Credentials entered through the secure form go directly to the remote browser. The
   username and password entered there are not visible to the model." Login handoff is
   explicit: the agent "will pause and prompt you to take control of the virtual
   browser", and "While you control the browser, screenshots are not captured."
5. **Licence and price:** proprietary, not self-hostable. Cloud browser is "available in
   ChatGPT Work on paid ChatGPT plans in supported regions, excluding Free and Go".
   Exact 2026 tier prices: UNAVAILABLE.

### Perplexity — Comet

EXTERNAL-PRIMARY (unverified by direct fetch, 403):
<https://comet-help.perplexity.ai/en/articles/12658082-control-what-comet-assistant-can-use>,
<https://www.perplexity.ai/help-center/en/articles/13531023-managing-comet-assistant-permissions>,
<https://www.perplexity.ai/help-center/comet/en/articles/12867356-browsing-privacy-safety>.
COMMUNITY-SIGNAL by direct fetch: <https://brave.com/blog/comet-prompt-injection/>,
<https://brave.com/blog/unseeable-prompt-injections/>.

1. **Confirmation: category-gated, model-classified, and defeasible.** Verbatim: "When
   Comet Assistant recognizes that a task is important, such as logging in to a certain
   site or completing a purchase from your shopping cart, it will pause and ask for
   permission before proceeding." An **"Always Allow"** option "allows Comet to perform
   actions on behalf of the user without having to confirm"; enterprise admins can
   disable it, "which would result in a prompt every time you ask Comet to take action"
   — per *task request*, not per dispatched action. Admins can mark domains Read Only.
   Where it appears: in-browser assistant UI. This is weaker than OpenAI's, which
   re-asks even after prior approval. Third-party corroboration (COMMUNITY-SIGNAL,
   <https://arxiv.org/pdf/2511.19477>): "unlike ChatGPT Agent's approval gates for
   sensitive operations, Comet proceeds autonomously once initiated."
   Brave's disclosures are the best external argument *for* a pre-dispatch gate: "The AI
   operates with the user's full privileges across authenticated sessions, providing
   potential access to banking accounts, corporate systems, private emails, cloud
   storage", and Brave's recommended mitigation is exactly the missing control — "No
   matter the prior agent plan and tasks, the model should require explicit user
   interaction" for security-critical operations. Perplexity's answer, BrowseSafe, is a
   classifier and trust-boundary defence, not a confirmation gate.
2. **Arbitrary JavaScript / CDP exposed to the model: UNAVAILABLE.** Comet does expose
   local and remote MCP connectors
   (<https://www.perplexity.ai/help-center/en/articles/11502712-local-and-remote-mcps-for-perplexity>),
   with local MCP able to "interact with files, databases, applications, and services on
   your computer"; no documented per-tool-call confirmation for those write actions.
   Third-party MCP servers drive Comet as an automation target with no gate
   (COMMUNITY-SIGNAL: <https://github.com/hanzili/comet-mcp>).
3. **Profile: the user's real signed-in browser, with no isolated mode.** The assistant
   acts inside the user's own Chromium profile with "access to the user's cookies,
   logins, extensions, and stored credentials"; "The agent operates under the user's real
   identity." Corroborated by Brave. This is the sharpest architectural difference from
   OpenAI, which offers cloud, separate-profile and logged-out options.
4. **Credentials:** "By default, Comet Assistant does not access or upload passwords and
   autofill data"; credentials sit in a local vault decrypted only after OS biometric
   verification; "Comet cannot read or export passwords unless you explicitly choose to
   do so." Critical caveat: not reading passwords is not the same as not using the
   session those passwords created — the agent inherits live authenticated cookies,
   which is precisely the Brave attack path.
5. **Licence and price:** proprietary. Comet browser free worldwide since 2025-10-02
   (COMMUNITY-SIGNAL: <https://www.cnbc.com/2025/10/02/perplexity-ai-comet-browser-free-.html>).
   Perplexity Pro $20/mo, Max $200/mo, Comet Plus $5/mo. Background Assistant is
   Max-tier (COMMUNITY-SIGNAL).

### Google — Gemini in Chrome "auto browse" (Project Mariner folded in)

EXTERNAL-PRIMARY for existence and tiering:
<https://blog.google/products-and-platforms/products/chrome/gemini-3-auto-browse/> —
agentic "auto browse" in Chrome for AI Pro and Ultra subscribers, powered by Gemini 3;
it can fill in forms, for example from a PDF. COMMUNITY-SIGNAL for Mariner's shutdown
(2026-05-04) and its absorption into Gemini and Chrome:
<https://www.androidheadlines.com/2026/05/google-shuts-down-project-mariner-ai-agent.html>.

1. **Confirmation: category-gated per third-party reporting; primary wording
   UNAVAILABLE.** COMMUNITY-SIGNAL (low-quality secondary sources:
   <https://aithinkerlab.com/chrome-ai-auto-browse-complete-guide/>,
   <https://nerova.ai/news/google-shuts-down-project-mariner-gemini-agent-browser-2026>)
   describes "mandatory user confirmation before any sensitive action like a purchase or
   form submission". I could not confirm that wording on a Google-owned page, so treat
   the scope as unestablished. No evidence of per-action or OS-level confirmation.
2. **Arbitrary JavaScript exposed to the agent: UNAVAILABLE.**
3. **Profile: the user's real Chrome**, as an in-browser feature. Isolation options:
   UNAVAILABLE.
4. **Credentials:** UNAVAILABLE.
5. **Licence and price:** proprietary; requires Google AI Pro or Ultra.

### Baseline that matters most: the MCP client, not the browser server

This is where the distinctiveness question is actually decided, because it is what a
competitor gets **for free** without writing any gate.

- **Claude Code prompts per tool call by default** and offers "Yes, and don't ask again"
  which saves a rule to `.claude/settings.local.json` (EXTERNAL-PRIMARY:
  <https://code.claude.com/docs/en/permissions>). MCP tools are permissioned by
  `mcp__server__tool` patterns; `bypassPermissions` mode "skips permission prompts".
- **Any MCP server can force an unbypassable per-call prompt in Claude Code.**
  EXTERNAL-PRIMARY: <https://code.claude.com/docs/en/mcp> — setting
  `_meta["anthropic/requiresUserInteraction"]` to `true` in a tool's `tools/list` entry
  means "Claude Code shows that tool's permission prompt on every call, even in
  `acceptEdits`, `auto`, and `bypassPermissions` permission modes, and doesn't offer a
  'don't ask again' option for it. Allow rules that match the tool don't skip the prompt
  either." This is Claude Code-specific, not in the MCP spec. **A competitor could adopt
  it in one line of JSON.** No browser MCP server was found using it (searched
  2026-09-09; the only documented users are internal servers such as `scheduled-tasks`).
- **MCP elicitation exists and is the natural primitive for a per-action gate, but is
  advisory.** EXTERNAL-PRIMARY:
  <https://modelcontextprotocol.io/specification/2025-06-18/client/elicitation> —
  `elicitation/create` with `accept`/`decline`/`cancel`; clients supporting it MUST
  declare the capability, but the surrounding obligations are **SHOULD** ("Clients
  SHOULD implement user approval controls", "SHOULD allow users to decline"), the
  protocol "does not mandate any specific user interaction model", schemas are limited
  to flat primitives, and servers "MUST NOT use elicitation to request sensitive
  information". Current spec revision is 2026-07-28; elicitation landed in 2025-06-18
  and still carries the "design may evolve" note. **No browser MCP server was found
  using elicitation for action approval** in fourteen months.
- **OS-native dialogs from an MCP server have exactly one precedent, and it is not a
  browser.** EXTERNAL-PRIMARY:
  <https://raw.githubusercontent.com/portel-dev/ncp/main/docs/guides/native-dialog-cross-platform.md>
  — `portel-dev/ncp`, a generic tool orchestrator, uses AppleScript `display dialog` via
  System Events for per-tool-call confirmation, explicitly as a fallback when the client
  does not support elicitation.

## What this means for WebKitUI MCP's claims

### Safe to publish

1. **"No other MCP browser server confirms a click with the human before dispatching
   it."** Evidenced across fourteen servers read on 2026-09-09. The single exception is
   `brainfuel/mcp-browser`, which confirms downloads, uploads and page dialogs **only**
   — so the precise safe form is "no other MCP browser server gates clicks, fills or
   JavaScript", with `brainfuel/mcp-browser` named as the partial exception. Name it;
   don't pretend it isn't there.
2. **"Every shipped consumer agentic browser gates on a model-classified category, not
   on the action."** Directly quotable for OpenAI ("sharing personal information, making
   purchases, deleting data, changing account permissions, or sending messages on your
   behalf") and Perplexity ("recognizes that a task is important, such as logging in to a
   certain site or completing a purchase"). The corollary — that ordinary clicks and
   fills reach the page with no human step — is sound.
3. **"The gate is a model behaviour in competing products, not a mechanism."** Their own
   verbs carry it: "trained to ask", "when needed", "recognizes". A prompt-injected model
   can simply fail to recognise. Brave's disclosures are the external authority for why
   that matters.
4. **"Approval text computed by the server from a freshly re-resolved target, rather
   than a string the agent supplied."** Playwright MCP is the clean contrast: its
   `element` parameter is *optional* and is documented as a "Human-readable element
   description used to obtain permission" — the agent writes what the human reads. No
   competitor was found computing the approval text server-side.
5. **"We expose no arbitrary-JavaScript and no raw-CDP tool."** True and unusual —
   Apple's own server ships `evaluate_javascript`, and every macOS/WebKit MCP browser
   found exposes JS eval. But see the correction below: it is not unique.
6. **"Apple's Safari MCP cannot do authenticated work."** Well evidenced from Apple's own
   WebDriver isolation guarantees. This is a real, defensible positioning line and does
   not depend on the approval claim at all.

### Needs softening

1. **Drop "unique" and any implication of a first.** Claude in Chrome's Manual mode
   already "pauses and requests approval before each action". Per-action human approval
   before dispatch exists in the market, shipped by Anthropic, generally available since
   August 2026.
2. **Drop "cannot be bypassed" as an absolute.** Two reasons. (a) Claude Code's
   `_meta["anthropic/requiresUserInteraction"]` already gives *any* MCP server a
   per-call prompt that survives `bypassPermissions` — so unbypassability is not a moat,
   it is an unclaimed one-line feature. (b) More importantly, WebKitUI's own default
   contradicts the claim; see the next point.
3. **The "native macOS dialog before every exposed click" claim is false as shipped.**
   Read on 2026-09-09 in this repo: `Sources/WebKitUIMCPServer/MCPServer.swift:2201`,
   inside `actTool`, reads
   `let approvalMode = arguments["approval_mode"]?.stringValue ?? (modern ? "mcp" : "native")`.
   For a modern client — the normal case — **click and fill confirmation defaults to MCP
   elicitation in the client's own chat, not to an OS dialog**, and `approval_mode` is an
   argument the *agent* supplies. Navigation is different: `MCPServer.swift:1590` defaults
   to `native`, matching the README. So the accurate claim today is: "Navigation blocks on
   a native macOS dialog by default. Click and fill block on a confirmation that is
   native for legacy clients and, for modern clients, an in-client elicitation by
   default." Either publish that, or change the `actTool` default to `native` and then
   publish the stronger sentence.
4. **"The agent cannot supply or bypass that dialog" needs to be split.** The dialog's
   *content* is server-computed — that part holds and is the real differentiator. But the
   agent selects the approval *channel* via `approval_mode`, and the MCP channel is only
   as strong as the client: the spec's obligations on clients are SHOULD, not MUST, and
   the protocol "does not mandate any specific user interaction model". Say "cannot
   author the approval text and cannot synthesise the approval value", not "cannot
   bypass".
5. **"The only MCP browser without a JavaScript-evaluation tool" is false.** Browserbase's
   MCP server exposes exactly six tools — `start`, `end`, `navigate`, `act`, `observe`,
   `extract` — with no `evaluate` and no CDP, asserted by its own test file. Reframe as
   "no arbitrary-JS tool *and* a per-action gate *and* a real authenticated session", which
   is the combination nobody else was found to have.
6. **Qualify "OS-owned" as the differentiator, not "per-action".** The defensible sentence
   is about *who owns the dialog*: every competitor's confirmation is rendered by the
   agent's own client or by the browser it is driving; only WebKitUI's navigation path
   puts it in an OS dialog owned by a separate signed helper. That is narrower and it
   survives scrutiny.

### Exact wording I would refuse to publish

- "The only agentic browser that asks for human approval before every action."
- "The first tool to put a human in the loop before every click."
- "Unbypassable" / "impossible to bypass" / "the agent cannot bypass the confirmation",
  unqualified.
- "No competitor requires human approval before acting."
- "A native macOS confirmation dialog appears before every exposed click", while
  `actTool` defaults to `mcp` for modern clients.
- "The only MCP browser that refuses arbitrary JavaScript."
- "Unlike Apple, we gate every action" as a comparison implying Apple's server is a
  competitor for authenticated work — it runs an isolated session and cannot do that
  work at all. The honest comparison is a different one.

## Unavailable

- Whether Claude in Chrome's per-action dialog names the specific target element,
  destination URL, or exact value to be typed. The permissions guide does not quote the
  dialog. This is the single most important open question, because it decides whether
  "shows the exact bound action" is a differentiator against Anthropic's own product.
- Whether Claude in Chrome can be pointed at a profile other than the user's real Chrome;
  and its credential/autofill policy.
- Google's primary wording for what triggers an auto-browse confirmation, and whether
  Gemini in Chrome exposes JS eval to the agent. Only weak secondary sources found.
- Whether Comet exposes JS-eval or CDP to its model, and whether Perplexity MCP write
  actions carry any confirmation.
- Whether "cannot run code in the browser" still holds for OpenAI's current built-in
  browser (that wording was Atlas-era agent mode).
- Exact 2026 ChatGPT per-tier prices.
- The hosted `mcp.browserbase.com` tool list (marketing still advertises a screenshot
  tool the repo removed); requires an API key to enumerate.
- Encryption-at-rest posture for Browser Use cloud authentication profiles.
- Licence files for Playwright MCP were confirmed (Apache-2.0), but not for
  `andesco/safari-web-inspector-bridge`, `Sunalamye/MCPWebKit`, or
  `rodneyrdx/safari-ios-webinspector-mcp`.
- Whether Browser MCP (browsermcp.io) exposes JavaScript evaluation.
- An exhaustive sweep of MCP directories (glama.ai, mcp.so, smithery.ai, mcpservers.org,
  awesome-mcp-servers) was not performed programmatically, and WebSearch is US-region, so
  a low-visibility Swift/WebKit MCP server could have been missed. Recall reached a
  2-star repo (`vintik100/bunbrowser`), which is reassuring but not proof.
- Verbatim tool counts for a few servers came through a summarizer rather than raw
  source, so counts may be off by one or two. `achiya-automation/safari-mcp` claims 97
  tools in its README while its GitHub description and third-party posts say 80; the
  discrepancy is unresolved.
