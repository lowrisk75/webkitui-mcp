# WebKitUI MCP V6 release loop

This controller resumes the V6 launch without collapsing local, physical,
provider, publication and promotion evidence into one claim.

## Commands

```sh
scripts/v6-release-loop.sh status
scripts/v6-release-loop.sh verify-local
scripts/v6-release-loop.sh prepare
WEBKITUI_V6_GATE_APPROVAL='exact token from the packet' \
  scripts/v6-release-loop.sh resume credential_rotation
scripts/v6-release-loop.sh record credential_rotation /path/to/redacted-receipt.json
```

State, approval packets and imported receipts are owner-only files under the
ignored `audit-output/v6-release-loop/` directory. Set
`WEBKITUI_V6_STATE_DIR` only for isolated tests.

## Gate order

1. Exact local app, notarized ZIP, installation and broker.
2. Credential rotation and rejection of the previous credentials.
3. Isolated Cloudflare Worker, Stripe sandbox zero-total checkout and synthetic
   Brevo delivery.
4. Guided VoiceOver, keyboard, receipt reset and logout/login evidence.
5. Exact source/tag/GitHub Release and independent public-byte read-back.
6. Exact LorisLabs website publication with access-on-request and no live
   Checkout.
7. Fresh independent G9 audit.
8. Owned GitHub and LorisLabs-site promotion only.

The controller never calls a provider. `resume` verifies and records the exact
authorization boundary; the matching connector or release workflow performs
the separately approved external action. A gate becomes `PASS` only after a
redacted JSON receipt matches its exact anchor.

## Receipt contract

```json
{
  "schema_version": 1,
  "gate": "credential_rotation",
  "result": "PASS",
  "anchor_sha256": "exact anchor from state.json",
  "evidence_class": "CURRENT-OBSERVED",
  "summary": "Redacted result without credentials or customer data.",
  "completed_at": "2026-08-31T00:00:00Z",
  "old_credentials_rejected": true,
  "new_credentials_working": true,
  "global_inheritance_removed": true,
  "rotated_targets": [
    "apple_portal_app_store_connect",
    "cloudflare",
    "cloudkit_management",
    "github",
    "hostinger",
    "mailcow",
    "local_mcp",
    "postgresql_jwt",
    "proxmox",
    "tailscale",
    "tavily",
    "x_twitter",
    "bmc",
    "opnsense",
    "zyxel"
  ]
}
```

Secret-bearing field names are rejected. `HUMAN-ATTESTED` is accepted for
guided physical evidence but remains visibly distinct from current observed
provider proof. Each gate also has mandatory semantic fields: the commerce
receipt, for example, cannot pass unless it proves Stripe sandbox mode, EUR 0
total and amount due, no payment method, synthetic delivery, the complete
license lifecycle, and explicitly labelled Stripe-test refund/dispute
simulations.

## Commercial invariants

- Public price: EUR 299 per organization per year, excluding tax.
- Public sales mode: access on request; no live Stripe Price or Payment Link.
- Canary: Stripe sandbox only and exact zero total. It must stop if `livemode`
  is true, the final total or amount due is nonzero, or a payment method is
  required.
- A zero-cost Checkout has no refundable charge. Refund and dispute behavior
  must therefore be recorded as Stripe-test simulation, not as a real refund
  of the zero-cost canary.
- Promotion excludes Reddit, email, ads and outreach.
