#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import zipfile

repo = Path(__file__).resolve().parents[2]
c = json.loads((repo / "docs/diagnostics/2026-10-20-local-install-resources.json").read_text())
root, source, dependency = Path(c["root"]), Path(c["source"]), Path(c["dependency"])
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
(root / "allocated-package").unlink()
# Existing helper scripts allocate short-lived files. Keep those inside the
# registered root as well; the scripts' own traps remove each file.
adapter = root / "mission-bin/mktemp"
text = adapter.read_text().replace('if args == ["/private/tmp/webkitui-provenance-inputs.XXXXXX"]:', 'if len(args) == 1 and args[0].startswith("/private/tmp/webkitui-"):')
text = text.replace('args = [str(root / "provenance-inputs.XXXXXX")]', 'args = [str(root / pathlib.Path(args[0]).name)]')
adapter.write_text(text)
env = dict(os.environ, PATH=str(root / "mission-bin") + os.pathsep + os.environ["PATH"], GIT_OPTIONAL_LOCKS="0", SILICONPASS_CREDENTIAL_BROKER_MANAGER_APP=str(dependency))
output = repo / "dist/local-0.6.41-745E07FF"
with (repo / "docs/diagnostics/2026-10-20-local-install-build.log").open("a") as log:
    subprocess.run(["scripts/package-preview.sh", str(output), c["build"]], cwd=source, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    subprocess.run(["swift", "test", "-c", "release", "--arch", "arm64", "--scratch-path", c["build"], "--filter", "Handoff|handoff|privacy|humanControl|AquaLocalization|CapabilityClaims|LicenceCoherence"], cwd=source, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
print("PACKAGE_AND_RELEASE_TESTS_PASSED", output)
