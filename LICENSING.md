# WebKitUI MCP licensing

## Current licensing model

Future versions distributed from this checkout are intended to use the Business
Source License 1.1 in [`LICENSE`](LICENSE). BSL 1.1 is source-available, not an
Open Source Initiative approved open-source license before its Change Date.

The included Additional Use Grant permits:

- personal, noncommercial production use;
- qualifying charitable, educational, and public-research use;
- internal evaluation for up to 30 consecutive days;
- all non-production copying, modification, development, testing, and
  redistribution already permitted by BSL 1.1.

Commercial production use requires a separate written commercial license. This
includes internal business automation, embedding WebKitUI MCP in a proprietary
product, distributing it to customers, or offering a paid or revenue-generating
service substantially based on it.

## Commercial launch policy

The intended launch offer is:

- **Team:** EUR 299 per organization per year, for up to five authorized
  developers, up to ten activated Macs, and internal commercial production use.
- **Business, Enterprise, OEM, redistribution, and hosted services:** negotiated
  terms.
- **Evaluation:** 30 consecutive days under the Additional Use Grant.

Pricing is a launch policy, not a license grant or binding offer. Commercial
rights exist only after both parties accept a separate written commercial
agreement. Contact `partenariats@lorislab.fr`.

Purchased Team entitlements are intended to be activated with
`webkitui-mcp license activate`. Activation exchanges the commercial key for a
short-lived, product-bound signed entitlement and stores both in the local
macOS Keychain. This mechanism is operational evidence of a purchase; the
written license remains the source of commercial rights.

Unless a signed agreement states otherwise, expiry of a paid term is intended
to leave the customer licensed for the last version covered during the paid
term, while access to later commercial versions and support ends. This policy
must be reflected in the final commercial agreement before sales begin.

## Previously published MIT versions

The license change is not retroactive. Any version or source revision already
distributed under the MIT License remains licensed under MIT permanently. The
BSL file governs only versions first distributed with that file. In particular,
publishing a later BSL revision does not withdraw, narrow, or reacquire exclusive
rights over an earlier MIT revision or over downstream copies lawfully made
from it.

The local entitlement verifier reports evidence about a signed commercial
lease. Developer Preview capabilities are not currently conditioned on that
status, so activation alone must not be described as technical enforcement of
commercial-use rights.

## Delayed open-source conversion

On 2030-08-28, or the fourth anniversary of a version's first public BSL
distribution if earlier, that version converts to the Apache License 2.0 under
the BSL terms.

## Third-party software

This repository's license does not replace third-party licenses. Apple SDKs,
system frameworks, package dependencies, and incorporated third-party material
remain governed by their own terms. A complete third-party notice and dependency
license audit are release gates for any binary commercial distribution.

## Publication gates

Before publishing or selling a BSL version, LorisLabs must:

1. reuse and independently read back the exact individual-business seller
   identity already used for direct Throttle sales; no new company is required;
2. obtain French legal review of the Additional Use Grant and commercial terms;
3. publish a complete commercial agreement, invoicing terms, privacy terms, and
   legally required business disclosures;
4. verify copyright ownership and contribution permissions for every included
   source file;
5. complete the third-party dependency and notice audit;
6. align the website, repository metadata, package metadata, release artifacts,
   and product page on the same license version and Change Date.

No document in this repository is legal advice.
