#!/usr/bin/env python3
"""Package only public, pinned release bytes. Does not build, launch or publish."""

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import stat
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = "0.6.24"
ARCHIVE_SHA256 = "9e3457301514015a47552c2f7abe7643e796b55664c6298f089acce554cfad43"
RELEASE = f"https://github.com/lowrisk75/webkitui-mcp/releases/download/v{VERSION}"
PREFIX = "WebKitUI MCP.app/Contents/"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path, help="Published 0.6.24 notarized ZIP")
    parser.add_argument("--output", type=Path, default=ROOT / "dist/catalogue-0.6.24")
    args = parser.parse_args()
    archive_bytes = args.archive.read_bytes()
    if digest(archive_bytes) != ARCHIVE_SHA256:
        raise SystemExit("Refusing an archive that differs from the pinned public release")
    manifest_bytes = (ROOT / "Support/Catalogue/manifest.json").read_bytes()
    manifest = json.loads(manifest_bytes)
    assert manifest["version"] == VERSION
    entries = {"manifest.json": (manifest_bytes, 0o644)}
    with zipfile.ZipFile(args.archive) as source:
        info = plistlib.loads(source.read(PREFIX + "Info.plist"))
        assert info["CFBundleShortVersionString"] == VERSION
        relay = source.read(PREFIX + "MacOS/webkitui-mcp-relay")
        # Copy the signed Mach-O intact; never re-sign or modify release bytes.
        entries["server/webkitui-mcp-relay"] = (relay, 0o755)
        for name in ("LICENSE", "LICENSING.md", "THIRD_PARTY_NOTICES.md"):
            entries[name] = (source.read(PREFIX + "Resources/" + name), 0o644)
    entries["README.md"] = ((ROOT / "docs/distribution/catalogue-install.md").read_bytes(), 0o644)
    args.output.mkdir(parents=True, exist_ok=True)
    bundle = args.output / f"webkitui-mcp-{VERSION}-macos-arm64.mcpb"
    with zipfile.ZipFile(bundle, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as output:
        for name, (data, mode) in sorted(entries.items()):
            item = zipfile.ZipInfo(name, date_time=(2026, 10, 4, 20, 14, 38))
            item.create_system = 3
            item.external_attr = (stat.S_IFREG | mode) << 16
            item.compress_type = zipfile.ZIP_DEFLATED
            output.writestr(item, data)
    bundle_hash = digest(bundle.read_bytes())
    server = {
        "$schema": "https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json",
        "name": "io.github.lowrisk75/webkitui-mcp",
        "title": "WebKitUI MCP",
        "description": "Native WebKit for Mac. Human approval and persistent sign-ins. Requires the companion app.",
        "repository": {"url": "https://github.com/lowrisk75/webkitui-mcp", "source": "github"},
        "version": VERSION,
        "websiteUrl": "https://github.com/lowrisk75/webkitui-mcp",
        "packages": [{
            "registryType": "mcpb",
            "identifier": f"{RELEASE}/{bundle.name}",
            "fileSha256": bundle_hash,
            "transport": {"type": "stdio"},
        }],
    }
    (args.output / "server.json").write_text(json.dumps(server, indent=2) + "\n")
    (args.output / "SHA256SUMS").write_text(f"{bundle_hash}  {bundle.name}\n")
    provenance = {
        "release": f"https://github.com/lowrisk75/webkitui-mcp/releases/tag/v{VERSION}",
        "sourceArchiveSha256": ARCHIVE_SHA256,
        "relaySha256": digest(relay),
        "manifestSha256": digest(manifest_bytes),
        "bundleSha256": bundle_hash,
        "signing": "Original relay bytes retained; this new MCPB is not independently notarized",
        "runtimeValidation": "Not performed by this packager",
        "publication": "Local candidate only. MCPB URL becomes valid only after authorized release upload.",
    }
    (args.output / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    print(json.dumps({"bundle": str(bundle), "sha256": bundle_hash, "published": False}))


if __name__ == "__main__":
    main()
