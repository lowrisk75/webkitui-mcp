#!/usr/bin/env python3
"""Exercise the embedded connector without reading or changing a vault."""
import argparse
import json
import selectors
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("connector")
parser.add_argument("--expected-version", choices=["0.1.0", "0.3.0"], default="0.3.0")
args = parser.parse_args()
process = subprocess.Popen(
    [args.connector], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
    stderr=subprocess.PIPE, bufsize=0)
print(f"RESOURCE_CREATED=connector-verifier-process:{process.pid}", file=sys.stderr)
selector = selectors.DefaultSelector()
selector.register(process.stdout, selectors.EVENT_READ)
buffer = bytearray()


def send(method, params, request_id=None):
    message = {"jsonrpc": "2.0", "method": method, "params": params}
    if request_id is not None:
        message["id"] = request_id
    process.stdin.write(json.dumps(message).encode() + b"\n")
    process.stdin.flush()
    if request_id is None:
        return None
    while b"\n" not in buffer:
        assert selector.select(10), "Timed out waiting for MCP response"
        data = process.stdout.read(4096)
        assert data, "Connector closed stdout"
        buffer.extend(data)
        assert len(buffer) <= 32768, "Response exceeds bound"
    line, _, rest = buffer.partition(b"\n")
    buffer[:] = rest
    response = json.loads(line)
    assert response["jsonrpc"] == "2.0" and response["id"] == request_id
    return response


try:
    initialized = send("initialize", {
        "protocolVersion": "2025-11-25", "capabilities": {},
        "clientInfo": {"name": "webkitui-package-verifier", "version": "1"}}, 1)
    assert initialized["result"]["protocolVersion"] == "2025-11-25"
    assert initialized["result"]["serverInfo"] == {
        "name": "siliconpass-vault", "version": args.expected_version}
    send("notifications/initialized", {})
    tools = send("tools/list", {}, 2)["result"]["tools"]
    expected_tools = {
        "mission_start", "vault_read", "vault_create_note",
        "vault_create_login", "mission_revoke"}
    if args.expected_version == "0.3.0":
        expected_tools.update({"vault_operation_status", "vault_recover_operation",
                               "vault_prepare_local_secret_import", "vault_commit_local_secret_import",
                               "vault_recover_independent_recovery"})
    actual_tools = {tool["name"] for tool in tools}
    assert actual_tools == expected_tools, {
        "unexpected_tools": sorted(actual_tools - expected_tools),
        "missing_tools": sorted(expected_tools - actual_tools)}
    assert all(tool["inputSchema"]["additionalProperties"] is False for tool in tools)
    if args.expected_version == "0.3.0":
        recovery = next(tool for tool in tools if tool["name"] == "vault_recover_independent_recovery")
        schema = recovery["inputSchema"]
        assert set(schema["properties"]) == {"operationID", "versionID"}
        assert set(schema["required"]) == {"operationID", "versionID"}
        assert all(value == {"type": "string", "format": "uuid"}
                   for value in schema["properties"].values())
        rejected_recovery = send("tools/call", {
            "name": "vault_recover_independent_recovery", "arguments": {
                "operationID": "00000000-0000-0000-0000-000000000001",
                "versionID": "00000000-0000-0000-0000-000000000002",
                "password": "RECOVERY-PROCESS-CANARY"}}, 5)
        assert rejected_recovery["result"]["isError"]
        assert json.loads(rejected_recovery["result"]["content"][0]["text"]) == {
            "status": "failed", "error": "invalid_request"}
        assert "RECOVERY-PROCESS-CANARY" not in json.dumps(rejected_recovery)
    rejected = send("tools/call", {"name": "mission_start", "arguments": {
        "durationSeconds": 15, "maximumOperations": 1, "requestRead": False,
        "allowCreateNote": True, "allowCreateLogin": False,
        "password": "PROCESS-CANARY"}}, 3)
    reply = json.loads(rejected["result"]["content"][0]["text"])
    assert rejected["result"]["isError"]
    assert reply == {"status": "failed", "error": "invalid_request"}
    assert "PROCESS-CANARY" not in json.dumps(rejected)
    assert send("ping", {}, 4)["result"] == {}
    print(json.dumps({"result": "PASS", "tools": len(tools),
                      "secret_argument_rejected": True,
                      "vault_read_or_changed": False}))
finally:
    process.stdin.close()
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
    selector.close()
    print(f"RESOURCE_STOPPED=connector-verifier-process:{process.pid}", file=sys.stderr)
