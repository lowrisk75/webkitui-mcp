#!/usr/bin/env python3
"""Mission-local orchestration: frozen source, registered stages, existing package gates."""
import hashlib
import plistlib
import zipfile
import json
import os
from pathlib import Path
import shutil
import subprocess

repo = Path(__file__).resolve().parents[2]
c = json.loads((repo / "docs/diagnostics/2026-10-20-local-642-resources.json").read_text())
root, source, dependency = Path(c["root"]), Path(c["source"]), Path(c["dependency"])
assert source.is_dir() and not any(source.iterdir())
for relative in [".git", "Sources", "Tests", "Support/AquaApp", "Support/Packaging", "scripts", "docs/examples"]:
    shutil.copytree(repo / relative, source / relative, symlinks=True)
for relative in ["Package.swift", "package.json", "package-lock.json", "README.md", "LICENSE", "LICENSING.md", "THIRD_PARTY_NOTICES.md", "docs/network-boundary.md", "docs/release-maintenance-policy.md", "docs/scoped-interaction-workflows.md"]:
    target = source / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(repo / relative, target)
bin_dir = root / "mission-bin"
bin_dir.mkdir(exist_ok=False)
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
policy = plistlib.loads((source / "Support/Packaging/SiliconPassVaultMCP.plist").read_bytes())
archive = repo / "dist/robustness-0.6.40/final/preview/WebKitUI-MCP-0.6.40-preview.zip"
prefix = "WebKitUI MCP.app/Contents/Resources/CredentialBroker/"
with zipfile.ZipFile(archive) as z:
    connector = z.read(prefix + "siliconpass-vault-mcp")
    assert hashlib.sha256(connector).hexdigest() == policy["ConnectorInputSHA256"]
    for name in z.namelist():
        if not name.startswith(prefix) or name.endswith("/"): continue
        relative = Path(name[len(prefix):])
        assert not relative.is_absolute() and ".." not in relative.parts
        target = dependency / "Contents/Resources/CredentialBroker" / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(z.read(name))
    (dependency / "Contents/Resources/CredentialBroker/siliconpass-vault-mcp").chmod(0o755)
shutil.copy2("/Applications/SiliconPassCredentialBrokerManager.app/Contents/Info.plist", dependency / "Contents/Info.plist")
(root / "resources.json").write_text(json.dumps(c))

# Existing helper scripts allocate short-lived files. Keep those inside the
# registered root as well; the scripts' own traps remove each file.
adapter = root / "mission-bin/mktemp"
text = adapter.read_text().replace('if args == ["/private/tmp/webkitui-provenance-inputs.XXXXXX"]:', 'if len(args) == 1 and args[0].startswith("/private/tmp/webkitui-"):')
text = text.replace('args = [str(root / "provenance-inputs.XXXXXX")]', 'args = [str(root / pathlib.Path(args[0]).name)]')
adapter.write_text(text)
env = dict(os.environ, PATH=str(root / "mission-bin") + os.pathsep + os.environ["PATH"], GIT_OPTIONAL_LOCKS="0", SILICONPASS_CREDENTIAL_BROKER_MANAGER_APP=str(dependency))
output = repo / "dist/local-0.6.42-745E07FF"
with (repo / "docs/diagnostics/2026-10-20-local-642-build.log").open("a") as log:
    subprocess.run(["scripts/package-preview.sh", str(output), c["build"]], cwd=source, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    subprocess.run(["swift", "test", "-c", "release", "--arch", "arm64", "--scratch-path", c["build"], "--filter", "Handoff|handoff|privacy|humanControl|AquaLocalization|CapabilityClaims|LicenceCoherence|sessionLoadDiagnosis|safariCompatibility|loadDiagnostics"], cwd=source, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
print("PACKAGE_AND_RELEASE_TESTS_PASSED", output)
