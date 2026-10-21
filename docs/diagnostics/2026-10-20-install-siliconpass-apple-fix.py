#!/usr/bin/env python3
"""Install the validated native candidate; preserve the old app and data entitlements."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import time

repo = Path(__file__).resolve().parents[2]
stage = Path(os.environ["SILICONPASS_APPLE_STAGE"])
assert stage.is_dir() and set(p.name for p in stage.iterdir()) <= {"SiliconPass.app"}
output = repo / "dist/siliconpass-apple-origin-20261020"
output.mkdir(parents=True, exist_ok=True)
assert not any(output.iterdir()), "Installation output must still be empty"
built = Path("/Volumes/DeveloperStorage/BuildScratch/Auto/SiliconPass-098a075cdc7f/xcodebuild/Build/Products/Release/SiliconPass.app")
candidate = stage / "SiliconPass.app"
evidence = json.loads((repo / "docs/diagnostics/2026-10-20-siliconpass-candidate-signature.json").read_text())
assert all(evidence["sensitive_entitlements_equal"].values()) and evidence["candidate_signature_valid"]
assert hashlib.sha256((built / "Contents/MacOS/SiliconPass").read_bytes()).hexdigest() == evidence["candidate_binary_sha256"]
if not candidate.exists():
    subprocess.run(["ditto", str(built), str(candidate)], check=True)
assert hashlib.sha256((candidate / "Contents/MacOS/SiliconPass").read_bytes()).hexdigest() == evidence["candidate_binary_sha256"]
installed = Path("/Applications/SiliconPass.app")
requirement = 'anchor apple generic and certificate leaf[subject.OU] = "TDV6D5L785" and identifier "com.lorislab.siliconpass" and entitlement["com.apple.security.get-task-allow"] absent'
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(candidate)], check=True)
subprocess.run(["codesign", "--verify", "-R=" + requirement, str(candidate)], check=True)
def entitlements(app):
    return plistlib.loads(subprocess.check_output(["codesign", "-d", "--entitlements", ":-", str(app)], stderr=subprocess.DEVNULL))
old_entitlements, new_entitlements = entitlements(installed), entitlements(candidate)
keys = ["keychain-access-groups", "com.apple.security.application-groups", "com.apple.application-identifier", "com.apple.developer.team-identifier", "com.apple.developer.icloud-container-identifiers"]
assert all(old_entitlements.get(key) == new_entitlements.get(key) for key in keys)
subprocess.run(["ditto", "-c", "-k", "--norsrc", "--noextattr", "--keepParent", str(candidate), str(output / "SiliconPass-apple-origin-local.zip")], check=True)
backup = output / "rollback/SiliconPass.app"
backup.parent.mkdir()
assert installed.stat().st_dev == backup.parent.stat().st_dev
pattern = r"^/Applications/SiliconPass\.app/Contents/MacOS/SiliconPass( |$)"
def pids():
    result = subprocess.run(["pgrep", "-f", pattern], text=True, capture_output=True)
    assert result.returncode in (0, 1)
    return [int(x) for x in result.stdout.split()]
old_pids = pids()
if old_pids:
    subprocess.run(["osascript", "-e", 'tell application id "com.lorislab.siliconpass" to quit'], check=True)
deadline = time.monotonic() + 15
while pids() and time.monotonic() < deadline: time.sleep(0.1)
assert not pids(), "SiliconPass did not quit; original app not replaced"
os.rename(installed, backup)
try:
    subprocess.run(["ditto", str(candidate), str(installed)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(installed)], check=True)
    assert hashlib.sha256((installed / "Contents/MacOS/SiliconPass").read_bytes()).hexdigest() == evidence["candidate_binary_sha256"]
except BaseException:
    if installed.exists(): shutil.rmtree(installed)
    os.rename(backup, installed)
    subprocess.run(["open", str(installed)], check=True)
    raise
subprocess.run(["open", str(installed)], check=True)
deadline = time.monotonic() + 10
while not pids() and time.monotonic() < deadline: time.sleep(0.1)
new_pids = pids()
assert len(new_pids) == 1
print("SILICONPASS_RETAINED_PID=" + str(new_pids[0]), flush=True)
evidence.update({"installed": True, "retained_pid": new_pids[0], "rollback": str(backup), "old_processes_exited": old_pids, "vault_read_or_changed_by_installer": False, "live_fill_not_automatically_retried": True})
(repo / "docs/diagnostics/2026-10-20-siliconpass-install-result.json").write_text(json.dumps(evidence, indent=2) + "\n")
print("SILICONPASS_APPLE_FIX_INSTALLED; unlock in native app before retrying Fill", flush=True)
