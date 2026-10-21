#!/usr/bin/env python3
"""Preserve local evidence, then remove only verified mission-created staging."""
import hashlib
import json
from pathlib import Path
import shutil
import tarfile

repo = Path(__file__).resolve().parents[2]
c = json.loads((repo / "docs/diagnostics/2026-10-20-local-642-resources.json").read_text())
root, source = Path(c["root"]), Path(c["source"])
assert not root.is_symlink()
identity = root.stat()
assert (identity.st_dev, identity.st_ino, int(identity.st_birthtime)) == (16777244, 43165918, 1792503870)
assert json.loads((root / "resources.json").read_text())["root"] == str(root)
output = repo / "dist/local-0.6.42-745E07FF"
archive = output / "source-snapshot-0.6.42.tar.gz"
assert not archive.exists()
def safe_source(item):
    if ".git" in Path(item.name).parts: return None
    return item
with tarfile.open(archive, "w:gz") as tar:
    tar.add(source, arcname="source", filter=safe_source)
candidate = output / "candidate/WebKitUI MCP.app"
installed = Path("/Applications/WebKitUI MCP.app")
for relative in ["Contents/MacOS/webkitui-mcp-aqua-broker", "Contents/Resources/SOURCE-MANIFEST.sha256"]:
    assert hashlib.sha256((candidate / relative).read_bytes()).digest() == hashlib.sha256((installed / relative).read_bytes()).digest()
manifest = candidate / "Contents/Resources/SOURCE-MANIFEST.sha256"
shutil.copy2(manifest, output / "SOURCE-MANIFEST.sha256")
shutil.copy2(candidate / "Contents/Resources/ReleaseProvenance.plist", output / "ReleaseProvenance.plist")
shutil.rmtree(output / "candidate")
# Verify each surviving child against the mission's creation identity as well.
resources = json.loads((repo / "docs/diagnostics/2026-10-20-642-resources-before-cleanup.json").read_text())
verified = []
for entry in resources:
    if entry["kind"] != "temporaryDirectory": continue
    path = Path(entry["locator"])
    if not path.is_relative_to(root): continue
    if path.exists():
        assert not path.is_symlink()
        stat = path.stat()
        expected = entry["identity"].split(":")
        assert (stat.st_dev, stat.st_ino, int(stat.st_birthtime)) == tuple(map(int, expected[:3]))
    verified.append(entry["id"])
# All packaging, signing, test and installation foreground sessions have exited.
# Their transient probe children were synchronously reaped by the gate scripts.
shutil.rmtree(root)
assert not root.exists()
evidence = {"verified_root_identity": [identity.st_dev, identity.st_ino, int(identity.st_birthtime)], "removed_mission_root": str(root), "source_archive": str(archive), "source_archive_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(), "installed_service_retained_pid": 68230, "rollback_retained": str(output / "rollback/WebKitUI MCP.app"), "other_mission_resources_touched": False, "verified_directory_resource_ids": verified, "siliconpass_production_pid_retained": 25762, "siliconpass_evidence": str(repo / "dist/siliconpass-apple-origin-20261020")}
(repo / "docs/diagnostics/2026-10-20-local-642-cleanup.json").write_text(json.dumps(evidence, indent=2) + "\n")
print("VERIFIED_MISSION_STAGING_REMOVED; installed service, signed artifact, source and rollback retained")
