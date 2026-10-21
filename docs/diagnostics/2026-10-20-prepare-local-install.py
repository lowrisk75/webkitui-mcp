#!/usr/bin/env python3
"""Mission-local orchestration: frozen source, registered stages, existing package gates."""
import json
import os
from pathlib import Path
import shutil
import subprocess

repo = Path(__file__).resolve().parents[2]
c = json.loads((repo / "docs/diagnostics/2026-10-20-local-install-resources.json").read_text())
root, source = Path(c["root"]), Path(c["source"])
assert source.is_dir() and not any(source.iterdir())
for relative in [".git", "Sources", "Tests", "Support/AquaApp", "Support/Packaging", "scripts", "docs/examples"]:
    shutil.copytree(repo / relative, source / relative, symlinks=True)
for relative in ["Package.swift", "package.json", "package-lock.json", "README.md", "LICENSE", "LICENSING.md", "THIRD_PARTY_NOTICES.md", "docs/network-boundary.md", "docs/release-maintenance-policy.md", "docs/scoped-interaction-workflows.md"]:
    target = source / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(repo / relative, target)
bin_dir = root / "mission-bin"
bin_dir.mkdir()
(root / "resources.json").write_text(json.dumps(c))
adapter = bin_dir / "mktemp"
adapter.write_text('''#!/usr/bin/env python3
import json, os, pathlib, subprocess, sys
root = pathlib.Path(__file__).resolve().parents[1]
c = json.loads((root / "resources.json").read_text())
args = sys.argv[1:]
if len(args) == 2 and args[0] == "-d":
    mapping = {"/private/tmp/webkitui-package.XXXXXX": ["package"],
      "/private/tmp/webkitui-exact-sign.XXXXXX": ["sign"],
      "/private/tmp/webkitui-pre-notary-verify.XXXXXX": ["verify1", "verify2"]}
    if args[1] in mapping:
        for role in mapping[args[1]]:
            marker = root / ("allocated-" + role)
            if marker.exists(): continue
            directory = pathlib.Path(c[role])
            assert directory.is_dir() and not any(directory.iterdir())
            marker.touch(exist_ok=False)
            print(directory)
            sys.exit(0)
        sys.exit("No unused registered verification stage remains")
if args == ["/private/tmp/webkitui-provenance-inputs.XXXXXX"]:
    args = [str(root / "provenance-inputs.XXXXXX")]
os.execv("/usr/bin/mktemp", ["mktemp", *args])
''')
adapter.chmod(0o755)
output = repo / "dist/local-0.6.41-745E07FF"
output.mkdir(parents=True, exist_ok=False)
env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ["PATH"], GIT_OPTIONAL_LOCKS="0")
with (repo / "docs/diagnostics/2026-10-20-local-install-build.log").open("w") as log:
    subprocess.run(["scripts/package-preview.sh", str(output), c["build"]], cwd=source, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    subprocess.run(["swift", "test", "-c", "release", "--arch", "arm64", "--scratch-path", c["build"], "--filter", "Handoff|handoff|privacy|humanControl|AquaLocalization|CapabilityClaims|LicenceCoherence"], cwd=source, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
print("PACKAGE_AND_RELEASE_TESTS_PASSED", output)
