#!/usr/bin/env python3
"""Publish the reviewed catalogue metadata; credentials stay in memory only."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
BASE = "https://registry.modelcontextprotocol.io"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--publish", action="store_true", help="Perform the explicitly authorized publish")
args = parser.parse_args()
metadata = json.loads((ROOT / "dist/catalogue-0.6.24/server.json").read_text())
assert metadata["name"] == "io.github.lowrisk75/webkitui-mcp"
assert metadata["version"] == "0.6.24"
version_url = BASE + "/v0.1/servers/" + urllib.parse.quote(metadata["name"], safe="") + "/versions/0.6.24"


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


opener = urllib.request.build_opener(NoRedirect)


def request(url, payload=None, token=None):
    headers = {"Accept": "application/json", "User-Agent": "WebKitUI-Catalogue-Publisher/1.0"}
    if payload is not None:
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(url, data=json.dumps(payload).encode() if payload is not None else None, headers=headers)
    try:
        with opener.open(req, timeout=20) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        # Never print auth response bodies or request headers.
        if error.code == 404 and payload is None:
            return 404, None
        if url.endswith("/publish"):
            # Publish errors describe public metadata validation, not credentials.
            detail = error.read(4096).decode(errors="replace")
            raise SystemExit(f"Registry publish HTTP {error.code}: {detail}")
        raise SystemExit(f"Registry request HTTP {error.code}; no credential data retained")


status, existing = request(version_url)
if status == 200:
    observed = existing.get("server", existing)
    assert observed["packages"][0]["fileSha256"] == metadata["packages"][0]["fileSha256"]
    result = {"alreadyPublished": True, "response": existing}
elif not args.publish:
    print(json.dumps({"exists": False, "candidate": metadata["name"], "publish": False}))
    raise SystemExit(0)
else:
    # Independently verify the public artifact before any authenticated request.
    with urllib.request.urlopen(metadata["packages"][0]["identifier"], timeout=20) as artifact:
        artifact_bytes = artifact.read(2 * 1024 * 1024)
    assert hashlib.sha256(artifact_bytes).hexdigest() == metadata["packages"][0]["fileSha256"]
    account = subprocess.check_output(["gh", "api", "user", "--jq", ".login"], text=True).strip()
    assert account == "lowrisk75"
    github_token = subprocess.check_output(["gh", "auth", "token", "--hostname", "github.com"], text=True).strip()
    _, authentication = request(BASE + "/v0.1/auth/github-at", {"github_token": github_token})
    del github_token
    registry_token = authentication["registry_token"]
    del authentication
    _, receipt = request(BASE + "/v0.1/publish", metadata, registry_token)
    del registry_token
    result = {"alreadyPublished": False, "response": receipt}
    status, confirmed = request(version_url)
    assert status == 200
    observed = confirmed.get("server", confirmed)
    assert observed["packages"][0]["fileSha256"] == metadata["packages"][0]["fileSha256"]
    result["independentGet"] = confirmed
result.update({"verifiedAt": datetime.now(timezone.utc).isoformat(), "publicUrl": version_url})
evidence = ROOT / "docs/diagnostics/2026-10-20-catalogue-registry-receipt.json"
evidence.write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps({"published": True, "publicUrl": version_url, "evidence": str(evidence)}))
