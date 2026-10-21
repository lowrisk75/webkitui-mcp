#!/usr/bin/env python3
"""Authorized local replacement; retain the prior app and verify the live socket."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import socket
import subprocess
import time

repo = Path(__file__).resolve().parents[2]
output = repo / "dist/local-0.6.42-745E07FF"
candidate_dir = output / "candidate"
assert not candidate_dir.exists()
subprocess.run(["ditto", "-x", "-k", str(output / "signed/WebKitUI-MCP-0.6.42-signed-local.zip"), str(candidate_dir)], check=True)
candidate = candidate_dir / "WebKitUI MCP.app"
subprocess.run(["codesign", "--verify", "--strict", "--all-architectures", str(candidate)], check=True)
installed = Path("/Applications/WebKitUI MCP.app")
backup = output / "rollback/WebKitUI MCP.app"
assert installed.is_dir() and not backup.exists()
backup.parent.mkdir()
assert installed.stat().st_dev == backup.parent.stat().st_dev
pattern = r"^/Applications/WebKitUI MCP\.app/Contents/MacOS/webkitui-mcp-aqua-broker( |$)"
def broker_pids():
    value = subprocess.run(["pgrep", "-f", pattern], text=True, capture_output=True)
    assert value.returncode in (0, 1)
    return [int(x) for x in value.stdout.split()]
old_pids = broker_pids()
subprocess.run(["osascript", "-e", 'tell application id "com.lorislab.webkitui-mcp.aqua" to quit'], check=True)
deadline = time.monotonic() + 15
while broker_pids() and time.monotonic() < deadline:
    time.sleep(0.1)
assert not broker_pids(), "Broker did not quit; original app was not replaced"
os.rename(installed, backup)
try:
    subprocess.run(["ditto", str(candidate), str(installed)], check=True)
    subprocess.run(["codesign", "--verify", "--strict", "--all-architectures", str(installed)], check=True)
except BaseException:
    if installed.exists(): shutil.rmtree(installed)
    os.rename(backup, installed)
    subprocess.run(["open", str(installed)], check=True)
    raise
info = plistlib.loads((installed / "Contents/Info.plist").read_bytes())
assert (info["CFBundleShortVersionString"], info["CFBundleVersion"]) == ("0.6.42", "642")
for relative in ["Contents/MacOS/webkitui-mcp-aqua-broker", "Contents/MacOS/webkitui-mcp-confirm", "Contents/MacOS/webkitui-mcp-relay", "Contents/Resources/SOURCE-MANIFEST.sha256"]:
    assert hashlib.sha256((candidate / relative).read_bytes()).digest() == hashlib.sha256((installed / relative).read_bytes()).digest()
subprocess.run(["open", str(installed)], check=True)
deadline = time.monotonic() + 10
while not broker_pids() and time.monotonic() < deadline: time.sleep(0.1)
new_pids = broker_pids()
assert len(new_pids) == 1
# Emit immediately so the orchestrator can retain the production process in
# Throttle before running the remaining read-only health checks.
print("INSTALLED_BROKER_PID=" + str(new_pids[0]), flush=True)
socket_path = str(Path.home() / "Library/Application Support/WebkitUIMCP/mcp.sock")
metadata = {"io.modelcontextprotocol/protocolVersion": "2026-07-28", "io.modelcontextprotocol/clientInfo": {"name": "webkitui-local-install-health", "version": "1"}, "io.modelcontextprotocol/clientCapabilities": {"elicitation": {}}}
deadline = time.monotonic() + 15
while True:
    try:
        connection = socket.socket(socket.AF_UNIX)
        connection.settimeout(5)
        connection.connect(socket_path)
        break
    except OSError:
        connection.close()
        if time.monotonic() >= deadline: raise
        time.sleep(0.1)
stream = connection.makefile("rwb")
def call(identifier, method, params):
    stream.write((json.dumps({"jsonrpc": "2.0", "id": identifier, "method": method, "params": {**params, "_meta": metadata}}) + "\n").encode())
    stream.flush()
    response = json.loads(stream.readline())
    assert "error" not in response, response.get("error", {}).get("code")
    return response["result"]
discovery = call(1, "server/discover", {})
assert discovery["_meta"]["io.modelcontextprotocol/serverInfo"]["version"] == "0.6.42"
tools = call(2, "tools/list", {})["tools"]
session_tool = next(x for x in tools if x["name"] == "browser_session")
assert "observation_available=false" in session_tool["description"]
assert "diagnose" in session_tool["description"]
stream.close()
connection.close()
evidence = {"version": "0.6.42", "build": "642", "live_discovery_version_verified": True, "new_resume_contract_advertised": True, "installed_bytes_match_verified_archive": True, "old_broker_pids_exited": old_pids, "retained_broker_pid": new_pids[0], "rollback": str(backup), "foreign_session_opened_or_changed": False, "notarization_or_publication_performed": False}
(repo / "docs/diagnostics/2026-10-20-local-642-result.json").write_text(json.dumps(evidence, indent=2) + "\n")
print("LOCAL_INSTALL_AND_LIVE_DISCOVERY_PASSED", flush=True)
