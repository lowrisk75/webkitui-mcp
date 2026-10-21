#!/usr/bin/env python3
"""Verify catalogue archive and original relay using an isolated mock Unix broker."""
import hashlib
import json
from pathlib import Path
import socket
import stat
import subprocess
import threading
import zipfile

out = Path(__file__).resolve().parents[1] / "dist/catalogue-0.6.24"
bundle = out / "webkitui-mcp-0.6.24-macos-arm64.mcpb"
relay = out / "relay-verification"
endpoint = out / "probe.sock"
assert not endpoint.exists(), "Never replace an existing socket"
with zipfile.ZipFile(bundle) as archive:
    assert sorted(archive.namelist()) == sorted([
        "manifest.json", "server/webkitui-mcp-relay", "LICENSE",
        "LICENSING.md", "THIRD_PARTY_NOTICES.md", "README.md"])
    entry = archive.getinfo("server/webkitui-mcp-relay")
    assert (entry.external_attr >> 16) & stat.S_IXUSR
    relay.write_bytes(archive.read(entry))
    relay.chmod(0o755)
subprocess.run(["codesign", "--verify", "--strict", str(relay)], check=True, capture_output=True)
server = json.loads((out / "server.json").read_text())
assert server["packages"][0]["fileSha256"] == hashlib.sha256(bundle.read_bytes()).hexdigest()
listener = socket.socket(socket.AF_UNIX)
listener.settimeout(5)
identity = None
errors = []


def fixture():
    try:
        connection, _ = listener.accept()
        with connection:
            connection.settimeout(5)
            stream = connection.makefile("rwb", buffering=0)
            request = json.loads(stream.readline())
            assert request["method"] == "initialize"
            reply = {"jsonrpc": "2.0", "id": request["id"], "result": {
                "protocolVersion": "2025-11-25", "capabilities": {},
                "serverInfo": {"name": "transport-fixture", "version": "1.0.0"}}}
            stream.write((json.dumps(reply) + "\n").encode())
    except Exception as error:
        errors.append(type(error).__name__ + ": " + str(error))


try:
    listener.bind(str(endpoint))
    identity = endpoint.stat()
    listener.listen(1)
    worker = threading.Thread(target=fixture, daemon=True)
    worker.start()
    request = {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2025-11-25", "capabilities": {},
        "clientInfo": {"name": "catalogue-transport-fixture", "version": "1.0.0"}}}
    result = subprocess.run([str(relay), str(endpoint)], input=json.dumps(request) + "\n",
                            text=True, capture_output=True, timeout=8, check=True)
    assert json.loads(result.stdout)["result"]["serverInfo"]["name"] == "transport-fixture"
    worker.join(6)
    assert not worker.is_alive()
    assert not errors, errors
finally:
    listener.close()
    if identity and endpoint.exists() and endpoint.stat().st_ino == identity.st_ino:
        endpoint.unlink()
    relay.unlink(missing_ok=True)
evidence = {
    "bundleSha256": hashlib.sha256(bundle.read_bytes()).hexdigest(),
    "entryAllowlist": True, "relayExecutableBit": True,
    "relayOriginalSignature": True, "registryHashMatches": True,
    "relayStdioUnixSocketRoundTrip": "passed with dedicated mock broker",
    "realCompanionActivation": "not tested; existing shared app left untouched",
    "cleanMacMCPBClientInstall": "not tested", "fixtureResourcesReleased": True}
(out / "validation.json").write_text(json.dumps(evidence, indent=2) + "\n")
print(json.dumps(evidence))
