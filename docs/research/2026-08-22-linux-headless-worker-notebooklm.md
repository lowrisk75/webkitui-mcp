# Linux headless worker — NotebookLM counter-audit — 2026-08-22

## Scope

Assess a separate Playwright worker for Linux/Proxmox. It must preserve the six
bounded MCP tools, provenance, fresh semantic resolution, addressing counters,
and transactional receipts. It must not extend the old raw-CDP implementation.

## Measured or source-verifiable

- The target Proxmox host reported `amd64`, 32 logical CPUs, 62 GiB RAM with
  14 GiB available, and 2.3 TiB free on its root pool at measurement time.
- Playwright 1.62.1 and MCP SDK 1.30.0 were the current npm registry versions
  observed before implementation.
- Playwright officially supports Chromium and its patched WebKit on Linux in
  headless mode. Its documentation says macOS WebKit remains closer to Safari.
- WebKit source contains a WPE headless platform and automation session, but no
  comparative agent-correctness benchmark was found for it.
- The first required notebook query returned only progress UI. The blind-spot
  query returned a cited answer. The opportunity notebook was blocked because
  the gateway could not verify its Companion window as hidden.
- Deployment inspection found Playwright Chromium initially included
  `--no-sandbox` despite running as a non-root user. This was measured from the
  VM process command line, then treated as a release blocker rather than an
  acceptable default.
- After explicitly enabling `chromiumSandbox`, the deployed command line no
  longer contained `--no-sandbox`; the measured renderer reported Linux
  seccomp mode 2 and `NoNewPrivs` 1. Chromium documents that an unsandboxed
  zygote may still fork processes which install their specialized sandboxes.
- The final suite passed 18/18 inside the Debian 13 VM for both engines. A final
  forced-command SSH probe reached Example Domain, observed and captured it,
  and denied a confirmed loopback navigation with both Chromium and WebKit.
- One open Chromium controller used 551,380 KiB RSS across the worker/browser
  process tree in a single idle inspection. This is one sample, not a benchmark.
- The same inspection proved the runtime UID was non-root, the SSH PTY was
  denied, a second controller was rejected, and only SSH plus loopback DNS were
  listening after host firewall hardening.

## Conjectural NotebookLM leads requiring implementation checks

- A raw remote-debugging port can become a complete authority bypass. The worker
  therefore exposes no CDP port or raw JavaScript tool.
- Fill must reject carriage returns and newlines because Enter can implicitly
  submit a form outside a separate click confirmation.
- Provenance labels are evidence, not authority. A separate runtime capability
  must constrain exact top-level and subresource origins.
- Receipts do not stop passive exfiltration. Cross-origin page requests need a
  fail-closed egress boundary, and the worker must start without user secrets or
  a persistent authenticated profile.

## Explicitly not accepted as measured

The notebook's attack percentages, datacenter anti-bot rates, and generalized
claims about container escape were not reverified against primary sources in
this slice. They are not product measurements.

## Primary references used for the deployment decision

- [Playwright browser support](https://playwright.dev/docs/browsers)
- [Playwright Chromium sandbox option](https://github.com/microsoft/playwright/blob/main/docs/src/api/params.md)
- [Chromium sandbox switches](https://chromium.googlesource.com/chromium/src/+/HEAD/sandbox/policy/switches.cc)
- [Proxmox container and VM tooling](https://pve.proxmox.com/pve-docs-9-beta/pct.1.html)
