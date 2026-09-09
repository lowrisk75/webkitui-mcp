# Plans index

Three axes decide whether this product is state of the art, and they are not
interchangeable: it must be safe, it must reach far enough to finish a task, and
both must be *proved* rather than asserted. Code closes the first two. Only a
human at the machine closes most of the third.

## 1. Safety — done 2026-09-09

[`2026-09-09-sota-delta-after-safari-mcp.md`](2026-09-09-sota-delta-after-safari-mcp.md)
— four tasks, complete.

The approval gate no longer depends on the client honouring an elicitation, the
dialog names the origin a control's data would reach, a burst of confirmations is
counted and a flood refused, and six published claims the research refuted are
gone. Driven by the six research passes in `docs/research/2026-09-09-*`.

## 2. Reach — in progress

[`2026-09-09-reach-gaps.md`](2026-09-09-reach-gaps.md) — six tasks.

The product refuses little and reaches less: a `confirm()` is answered "cancel"
without telling anyone, a country dropdown cannot be set, the keyboard has three
keys, and an invoice link opens nothing. Evidence in
`docs/research/2026-09-09-tool-surface-gap-matrix.md`.

**Not planned yet, and the largest single gap:** cross-origin iframe content is
counted and never read, which removes every hosted payment field, CAPTCHA and
embedded SSO widget — a checkout is the flagship task and the impossible one. It
is not blocked; the instrumentation already runs in every frame. It needs its own
plan because element identity, observation generations, the origin lock and
provenance all assume one document.

Also deferred: main-frame HTTP status on the navigation result, the console
journal, and the proxy's contacted-host list. The gap matrix argues the network
observation outranks everything in the reach plan, because
`browser_transaction reconcile` currently reconciles an indeterminate write
against another observation of the interface — while the product correctly says
the interface never proves a server commit.

## 3. Proof — one axis a machine can close

[`2026-09-09-adversarial-corpus.md`](2026-09-09-adversarial-corpus.md) — five tasks.

A standing adversarial fixture corpus, run on every `swift test`, measuring one
question: with a hostile page, does what the operator sees still correspond to
what the action would do. It cannot measure whether a human reads the dialog, and
the plan says so repeatedly on purpose.

**The three proof gates no code closes**, from the parent spec
[`../../2026-08-29-full-sota-product-plan.md`](../../2026-08-29-full-sota-product-plan.md):

- dated provider journeys for Stripe, Google Play Console and Cloudflare, with
  independent read-back;
- physical-Mac authentication — locked Mac, closed lid, Touch ID lockout, Apple
  Watch, password fallback, cancellation, timeout;
- one paid live canary through to cancellation, refund and entitlement
  revocation.

## Reading order for someone new

The parent spec for what the product is for. Then
`docs/research/2026-09-09-agentic-browser-security-sota.md` for the attack that
eight of eight defences permitted, because everything in plan 1 exists to answer
it. Then the gap matrix for why the product could not finish a checkout anyway.
