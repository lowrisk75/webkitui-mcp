# WebKitUI MCP V6 — website deployment packet

Date: 2026-08-30  
Status: **validated locally — not deployed**

## Diagnosis

- `https://lorislab.fr/developers/webkitui-mcp/` still returned HTTP 404 at the
  anonymous refresh on `2026-08-30T20:56:52Z`.
- The eight WebKitUI files are present on website `origin/main` at merge commit
  `0423f13f072d7afb5c36b7d606c2c086e67e72d5`.
- The site is hosted through Hostinger rather than GitHub Pages. The current
  public bytes were therefore not changed by merging the website PR.
- The public homepage and sitemap in that commit do not link the product.
- The existing website checkout is intentionally only a preflight/contact page;
  it does not create a Stripe purchase or grant commercial rights.

## Isolated candidate

- Worktree: `/private/tmp/lorislab-webkitui-v6-site`
- Base: website `origin/main` commit
  `0423f13f072d7afb5c36b7d606c2c086e67e72d5`
- Local additions: one homepage structured-data entry, one footer link and four
  sitemap URLs.
- Dirty user changes in `/Users/kevinnadjarian/GitHub/lorislab-website` were
  not copied, modified, committed or staged.
- Deployment credential availability was checked without printing the secret.

## Exact ten-file manifest

```text
3863a1f70672c15c3f4c1af67e904fda2d1a332de0709202d617f8d13ff103f4  index.html
43c1d81d881cb57f6aab218c5d852ae2705267492356aaf82600c4678b56f9db  sitemap.xml
3b2c28e82b04d08b0cf64a860b4c82144ed581cf6b885fcddbf88564de85a588  developers/webkitui-mcp/buy/index.html
346700f9ec6e1114a160b037417931e9d9e82174c340c0340712290764f641dd  developers/webkitui-mcp/index.html
d5a12f39263fa7a3c3f9ddbdd7d056c88eca19451c834eef60324bef347085e6  developers/webkitui-mcp/og-webkitui-mcp.png
5681dadcbabe61e241d61ac05a390ce0559bb894cb9655205342569c02574952  developers/webkitui-mcp/privacy.html
7709f6183a414b0dd9e80041faa098affd367d326e42a17f18ed52f188ba96d6  developers/webkitui-mcp/product.css
27992dd8cd1fcdd7bed6508b72762110b9ac5c5a8867325dd51f54a3d367f28d  developers/webkitui-mcp/support.html
bd9a68f7d5dd8c157c83fa4ce23eca454fb5ff39030f11c03837aac954f825e6  developers/webkitui-mcp/terms.html
bbc12eac1ba71452d6c52f634562de262228065a7ba507c60f34029c716f0e11  developers/webkitui-mcp/thanks.html
```

Sorted manifest SHA-256:
`fb9847cf510898de0751c56450a4e469a53fedb746dc391edd51e24397ac2840`.

## Local verification

- `sitemap.xml`: well-formed XML.
- Six product pages: every local `href` and `src` resolves in the staged tree.
- A parse5 structural/accessibility/link audit passed 169/169 checks across the
  product, buy preflight, support, privacy, terms and post-checkout pages. It
  verifies HTML parsing, document language, one main landmark and H1, unique
  IDs, image alternatives, named controls, safe new-window links, JSON-LD,
  every local resource and fragment, complete French translation keys, and
  labelled navigation, skip links, deliberate sitemap exclusion of the buy and
  post-checkout pages, and WCAG AA contrast for the smallest faint text.
- The faint-text contrast was corrected from about 3.6:1 to a measured minimum
  of 4.899:1 across its supported dark surfaces. The buy-preflight and
  post-checkout pages now expose labelled navigation and a working skip link.
- Animated receipt and workflow content now defaults to visible and is hidden
  for animation only after runtime IntersectionObserver support is confirmed.
  The page therefore retains all core content without JavaScript.
- A fresh 1440 px macOS Quick Look/WebKit render visually confirms the complete
  desktop hero, receipt, navigation, CTAs and start of the next section with no
  clipping or missing animated content. Screenshot SHA-256:
  `ded233a04b983d345e68e616676e2aac56fdee2a23a70c239a265917934676bf`.
- A separate nonpersistent off-screen `WKWebView` run at 390 x 844 CSS pixels
  confirms `clientWidth = scrollWidth = 390`, no horizontal overflow, desktop
  navigation hidden and the hamburger displayed. The mobile screenshot is
  780 x 1688 Retina pixels and has SHA-256
  `e7472a51468f34c769b4c1f7f22bbaf55f814bdb393cf386a3dc390937b1b767`.
- In that same real WebKit run, the mobile menu changed atomically from hidden,
  `display:none`, `aria-expanded=false` to visible, `display:flex`,
  `aria-expanded=true`, then closed cleanly. EN changed the document language
  to `en`, FR restored `fr`, the skip link accepted focus, and the document
  retained exactly one H1 and one main landmark.
- Five additional 390 x 844 off-screen WebKit runs cover buy preflight,
  support, privacy, terms and post-checkout. Every page reports
  `clientWidth = scrollWidth = 390`, no horizontal overflow, one H1, one main
  landmark and a focusable skip link. Their visually reviewed contact sheet
  shows no clipped heading, card or terminal and has SHA-256
  `5a27f884409894c47cebb6be7446369c36f634d1c5547d59550fe50a534711ca`.
- The ten-file manifest was regenerated after that audit and remains exactly
  `fb9847cf510898de0751c56450a4e469a53fedb746dc391edd51e24397ac2840`.
- `git diff --check`: PASS.
- Candidate diff from website base: seven files, 31 insertions and six
  deletions.
- Terms and privacy now describe the same 90-day dormant-slot reclaim trigger
  and make clear that reclaim does not cancel the license.
- No upload, Hostinger deploy, cache purge, commit or push was performed.
- A final sequential keyboard pass and cache-busted live HTTP rendering remain
  required after deployment. No Playwright browser package was downloaded and
  no low-disk cache was expanded merely to duplicate the native WebKit evidence.

## Required order

1. Notarize and install-verify the exact V6 app.
2. Publish the exact GitHub source/tag/Release and notarized asset.
3. Rebind evaluation buttons to the published release rather than the repository
   root, then regenerate this manifest.
4. Obtain an exact Hostinger deployment GO for the final manifest.
5. Upload only the named files and independently read back their bytes.
6. Verify normal and cache-busted HTTP 200, canonical metadata, sitemap, product,
   support, privacy, terms and purchase-preflight pages.

Website deployment is publication and remains a separate authorization gate.
