# WKWebView process-memory attribution — 2026-08-22

## Measured locally

- `ps` shows many `com.apple.WebKit.{WebContent,Networking,GPU}` XPC helpers from concurrent applications, all reparented to PID 1.
- The available `ps` fields expose PID/PPID/RSS but no coalition identifier.
- `launchctl procinfo`, which could expose richer process ownership, requires root on this machine.
- `footprint` can target explicit PIDs but does not discover which launchd-owned WebKit helpers belong to the benchmark host.

## NotebookLM

- Both notebooks were queried for published methods, blind spots, and missed opportunities. They returned no settled evidence-bearing answer for this narrow attribution problem.

## Conclusion

Summing every process named `com.apple.WebKit.*`, or selecting helpers by creation time, would mix unrelated sessions and is not a valid WKWebView measurement. No memory number is published from this pass.

## Next valid designs

1. Run on a dedicated macOS user/host with no other WebKit clients and record baseline deltas plus PID birth/death.
2. Obtain a public WebKit process-identifier/coalition API if macOS 27 exposes one later.
3. Use an explicitly authorized privileged measurement harness that reads coalition ownership.
4. Report host-only and Chromium-tree memory separately, never as an engine comparison.
