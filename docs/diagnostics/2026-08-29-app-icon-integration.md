# WebKitUI MCP macOS app icon integration

Date: 2026-08-30
Repository HEAD: `4ccca1cd988c52856056edd911087705b8244c2c` (dirty remediation tree)
Status: `PASS LOCAL V3 — Icon Composer source, catalog and unsigned preview verified`

## Selected design

The user-selected V3 uses a blue globe and bounded directional orbit to express
Web navigation and controlled MCP flow. It replaces the generic target-like V2
symbol and removes the old silver frame. The artwork has no cursor or text and
remains recognizable at 32 pixels.

The exact user-provided Apple Icon Composer source is retained at
`Support/AquaApp/WebKitUIMCP.icon`. Its rendered 1024-pixel PNG is the canonical
master; no generative edit or visual reinterpretation was applied.

## Source assets

- Master: `Support/AquaApp/AppIcon-master.png`
- Master properties: PNG, 1024 x 1024, alpha channel present
- Master SHA-256:
  `d55abaa062d585aa7d2bd14372a3263a6b1224dd4e1a90c78853d7c2acc8bf75`
- Icon Composer source: `Support/AquaApp/WebKitUIMCP.icon`
- Icon Composer layer SHA-256:
  `419ee16edacf60ca518a6afa30a161c11939cffc1b3ad344860ae5270948b6f0`
- Asset catalog:
  `Support/AquaApp/Assets.xcassets/AppIcon.appiconset/`
- Representations: 16, 32, 64, 128, 256, 512 and 1024 physical pixels
- Packaged icon: `Support/AquaApp/AppIcon.icns`
- ICNS SHA-256:
  `652b1bd14edeb7a56a22f8dc6e5ca8589555e0673d680de333a6b30281f69466`

`scripts/generate-app-icon.sh` deterministically resizes the exact master and
uses Apple `actool` to compile the checked-in ICNS. Two consecutive generations
produced the same ICNS hash. All ten PNG representations retain genuine corner
alpha and have their exact catalog dimensions.

## Packaging integration

- `CFBundleIconFile` is `AppIcon`.
- Signed-local and unsigned-preview builders copy `AppIcon.icns` into
  `Contents/Resources`.
- Both preview and pre-notarization verifiers fail closed if the plist key,
  resource or ICNS file type is missing.

## Fresh validation

- Plist, JSON asset catalog, shell syntax, strict Swift format and
  `git diff --check`: PASS
- All ten asset PNGs retain alpha: PASS
- Visual review at 32, 128 and 1024 pixels: PASS V3
- Latest full installed-source gate: Debug and Release 189/189 each; one
  live-host test intentionally skipped so the installed broker remained active
- Fresh V5 arm64 Release build and preview round trip: PASS
- Unsigned preview archive verifier and embedded provenance: PASS
- Preview app ZIP SHA-256:
  `1622a39aa3959fb5607b7bb929e31ddcdc6cca1e6536d6f459ba48446bf7501d`
- Local evidence directory:
  `/private/tmp/webkitui-globe-icon-preview-v5`

The currently installed V4 remains unchanged with the prior icon. No V5 signing,
notarization, broker stop, installation, publication, commit or push occurred.
