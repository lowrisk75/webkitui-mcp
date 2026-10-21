#!/usr/bin/env python3
"""Native relay integration checks; gates let Codex register each owned child first."""
import json
from pathlib import Path
import socket
import subprocess
import threading
import time

repo = Path(__file__).resolve().parents[2]
binary_dir = Path(subprocess.check_output(["swift", "build", "--show-bin-path"], cwd=repo, text=True).strip())
relay = binary_dir / "webkitui-mcp-relay"
path = repo / ".relay-lifecycle-745E07FF.sock"
assert not path.exists()
results = []
for mode in ["pending-disconnect", "stdin-eof-valid-reply", "initialize-timeout"]:
    server = socket.socket(socket.AF_UNIX)
    server.bind(str(path))
    server.listen(1)
    received = []
    release = threading.Event()
    def backend():
        connection, _ = server.accept()
        with connection:
            request = connection.makefile("rb").readline()
            received.append(request)
            if mode == "stdin-eof-valid-reply":
                time.sleep(0.3)
                connection.sendall(b'{"jsonrpc":"2.0","id":1,"result":{"fixture":true}}\n')
            release.wait(20)
    thread = threading.Thread(target=backend, daemon=True)
    thread.start()
    child = subprocess.Popen([str(relay), str(path)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    print("REGISTER_RELAY_PID=" + str(child.pid) + " MODE=" + mode, flush=True)
    input("Continue after resource registration: ")
    try:
        method = "tools/call" if mode == "pending-disconnect" else "initialize"
        child.stdin.write((json.dumps({"jsonrpc":"2.0","id":1,"method":method,"params":{}})+"\n").encode())
        child.stdin.flush()
        deadline = time.monotonic() + 3
        while not received and time.monotonic() < deadline: time.sleep(0.01)
        assert len(received) == 1
        child.stdin.close()
        start = time.monotonic()
        if mode == "pending-disconnect":
            child.stdout.close()
        else:
            response = json.loads(child.stdout.readline())
            if mode == "initialize-timeout":
                assert response["error"]["code"] == -32098
                assert 9 <= time.monotonic() - start <= 12
            else:
                assert response["result"] == {"fixture": True}
        code = child.wait(timeout=2)
        assert code == 0 and len(received) == 1
        results.append({"mode":mode,"exit_code":code,"requests":len(received),"completion_ms":round((time.monotonic()-start)*1000),"replayed":False})
        print("RELAY_RELEASED_PID=" + str(child.pid), flush=True)
    finally:
        if child.poll() is None: child.kill(); child.wait()
        release.set()
        server.close()
        thread.join(timeout=2)
        path.unlink()
        for stream in [child.stdout, child.stderr]:
            if not stream.closed: stream.close()
(repo / "docs/diagnostics/2026-10-20-relay-lifecycle-result.json").write_text(json.dumps(results,indent=2)+"\n")
print("PASS relay client disconnect, piped EOF reply and no replay; owned socket removed", flush=True)
