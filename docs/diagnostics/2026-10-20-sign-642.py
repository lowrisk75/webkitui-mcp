#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path
import subprocess

repo = Path(__file__).resolve().parents[2]
c = json.loads((repo / "docs/diagnostics/2026-10-20-local-642-resources.json").read_text())
output = repo / "dist/local-0.6.42-745E07FF"
preview = output / "WebKitUI-MCP-0.6.42-preview.zip"
env = dict(os.environ, PATH=str(Path(c["root"]) / "mission-bin") + os.pathsep + os.environ["PATH"], GIT_OPTIONAL_LOCKS="0")
with (repo / "docs/diagnostics/2026-10-20-local-642-sign.log").open("w") as log:
    subprocess.run(["scripts/sign-exact-preview-local.sh", str(preview), hashlib.sha256(preview.read_bytes()).hexdigest(), str(output / "signed"), "8333AB7CD909731530AC62DD28CCA47C8D288225", "TDV6D5L785"], cwd=c["source"], env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
print("SIGNATURE_AND_ROUNDTRIP_GATES_PASSED")
