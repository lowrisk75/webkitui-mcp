# WebKitUI MCP performance budgets

Date: 2026-08-29  
Status: Developer Preview; local budgets are not release proof

These budgets keep large browser sessions predictable without turning one fast
development machine into a marketing claim. A limit is **enforced** only when
the implementation rejects or truncates work and an automated test covers the
boundary. A **release target** remains open until it is measured on a clean,
signed installation using the published fixture and method.

## Enforced budgets

| Surface | Default | Hard accepted range | Evidence |
| --- | ---: | ---: | --- |
| Semantic elements per observation page | 150 | 1–2,000 | Server argument validation and pagination test |
| Characters per semantic field | 512 | 64–4,096 | Server truncation and field-budget test |
| Element page offset | 0 | 0–100,000 | Server argument validation |
| Role filters | none | at most 16 values, 64 characters each | Server argument validation |
| Name filter | none | at most 128 characters | Server argument validation |
| Default observation MCP response | — | at most 1 MiB for the 300-control long-name fixture | Automated wire-size regression test |
| Navigation and observation load | 30 s | fixed runtime default | Runtime deadline |
| Local ranker | 10 s | positive explicit deadline | Deterministic fallback after deadline |

The one-mebibyte observation budget is a regression fixture, not a universal
maximum for caller-selected values. Callers that request up to 2,000 elements
and 4,096 characters accept a larger response explicitly. Production clients
should keep the defaults and follow `nextElementOffset`.

## Release targets still requiring clean-machine evidence

| Journey | Target | Required measurement |
| --- | ---: | --- |
| Cold launch to MCP discovery | p95 ≤ 2 s | 30 signed-app launches after reboot |
| Open persistent profile to first read-only observation | p95 ≤ 5 s on local fixture | 30 clean-profile runs; report warm and cold separately |
| Confirmed native action to direct postcondition | p95 ≤ 2 s excluding human decision time | 30 fixture actions with receipt timestamps |
| Nested virtualized-list target discovery | p95 ≤ 3 observation pages and ≤ 5 s | Google Play-like local fixture plus one dated provider canary |
| Idle resident memory | ≤ 250 MiB | full process-tree footprint after five idle minutes |
| 150-element observation peak memory | ≤ 400 MiB | full process-tree peak, ten consecutive observations |

## Measurement rules

1. Record product version, Git commit, macOS version, Mac model, memory, display
   state, signing state and whether the profile was warm or cold.
2. Use monotonic clocks for latency. Exclude human approval dwell time but keep
   native confirmation presentation and dispatch time as separate fields.
3. Measure the full process tree, including WebContent processes.
4. Publish median, p95, maximum and sample count; preserve raw redacted results.
5. A provider canary supplements the deterministic fixture. It never replaces
   it, and one successful canary is not a compatibility claim.
6. Any regression above a hard enforced budget fails CI. Missing signed or
   physical evidence keeps the corresponding release target open.
