#!/usr/bin/env python3
"""Resumable release evidence, never an authorization or provider executor."""
import argparse
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parent.parent
GATES = {
    "source_review": ("audit_current", "blocking_findings_closed", "license_reviewed"),
    "local_validation": ("debug_complete", "release_complete", "package_verified"),
    "physical_source": ("escape_early_ignored", "escape_late_cancelled", "none_ignored", "keyboard_passed"),
    "freeze": ("clean_revision",),
    "signed_artifact": ("signatures_valid", "helper_launch_checked", "provenance_matches"),
    "notarization": ("apple_accepted", "stapled", "gatekeeper_passed"),
    "installed_validation": ("installed_bytes_match", "two_clients_passed", "keyboard_passed", "rollback_available"),
    "release_review": ("no_blocking_findings", "claims_supported"),
    "public_release": ("public_source_matches", "tag_matches", "download_verified"),
    "website_publication": ("public_manifest_verified", "links_verified", "offer_verified"),
    "final_review": ("public_release_verified", "website_verified", "no_blocking_findings"),
    "reddit_delivery": ("rules_rechecked", "affiliation_disclosed", "live_links_verified", "draft_delivered"),
}
HEX = re.compile(r"^[0-9a-f]{64}$")
SECRET_KEYS = re.compile(r"password|secret|api.?key|access.?token|refresh.?token|cookie|credential", re.I)


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], stderr=subprocess.PIPE)


def source_anchor(root):
    # Include intended untracked files too; ignored local evidence never changes it.
    names = git(root, "ls-files", "-z", "--cached", "--others", "--exclude-standard").split(b"\0")
    h = hashlib.sha256()
    for name in sorted(set(n for n in names if n)):
        path = root / os.fsdecode(name)
        if path.is_symlink():
            value = b"symlink\0" + os.fsencode(os.readlink(path))
        elif path.is_file():
            value = f"{path.stat().st_mode & 0o777:o}:{digest(path)}".encode()
        else:
            value = b"deleted"
        h.update(name + b"\0" + value + b"\0")
    return h.hexdigest()


def atomic_json(path, value):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".release-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


@contextlib.contextmanager
def writer(directory):
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(directory, 0o700)
    with (directory / ".lock").open("a") as stream:
        os.chmod(stream.name, 0o600)
        fcntl.flock(stream, fcntl.LOCK_EX)
        yield


def no_secret_fields(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if SECRET_KEYS.search(key):
                raise ValueError("secret-bearing receipt field rejected")
            no_secret_fields(child)
    elif isinstance(value, list):
        for child in value:
            no_secret_fields(child)


def check_proofs(receipt):
    proofs = receipt.get("proofs")
    if not isinstance(proofs, list) or not proofs:
        raise ValueError("receipt needs file-backed proofs")
    for proof in proofs:
        if set(proof) != {"path", "sha256"} or not HEX.fullmatch(proof["sha256"]):
            raise ValueError("invalid proof descriptor")
        path = Path(proof["path"])
        if not path.is_absolute() or path.is_symlink() or not path.is_file():
            raise ValueError("proof must be an existing absolute regular file")
        if digest(path) != proof["sha256"]:
            raise ValueError("proof hash changed")


def validate_receipt(state, gate, receipt, anchor, head=None):
    if receipt.get("schema_version") != 1 or receipt.get("gate") != gate or receipt.get("result") != "PASS":
        raise ValueError("invalid receipt identity/result")
    if receipt.get("source_anchor") != anchor:
        raise ValueError("receipt source anchor is stale")
    if receipt.get("evidence_class") not in {"CURRENT-OBSERVED", "HUMAN-ATTESTED"}:
        raise ValueError("unsupported evidence class")
    if receipt["evidence_class"] == "HUMAN-ATTESTED" and gate not in {"physical_source", "installed_validation"}:
        raise ValueError("human attestation is only valid for physical gates")
    if not receipt.get("completed_at") or not receipt.get("summary"):
        raise ValueError("receipt needs timestamp and redacted summary")
    for field in GATES[gate]:
        if receipt.get(field) is not True:
            raise ValueError(f"missing completion evidence: {field}")
    check_proofs(receipt)
    no_secret_fields(receipt)
    if gate == "freeze" and head is not None and receipt.get("commit") != head:
        raise ValueError("frozen commit does not match HEAD")
    if gate in {"signed_artifact", "notarization"}:
        artifact = receipt.get("artifact_sha256", "")
        if not HEX.fullmatch(artifact) or not any(p["sha256"] == artifact for p in receipt["proofs"]):
            raise ValueError("exact artifact bytes must be included in proofs")
    if gate == "notarization":
        if receipt.get("input_sha256") != state["receipts"]["signed_artifact"]["artifact_sha256"]:
            raise ValueError("notarization input differs from signed artifact")
        if not receipt.get("request_id"):
            raise ValueError("missing Apple request identifier")
    if gate in {"installed_validation", "public_release"}:
        if receipt.get("artifact_sha256") != state["receipts"]["notarization"]["artifact_sha256"]:
            raise ValueError("artifact differs from notarized bytes")
    if gate == "public_release":
        if receipt.get("http_status") != 200 or receipt.get("download_sha256") != receipt["artifact_sha256"]:
            raise ValueError("public download is not verified")
        if not isinstance(receipt.get("download_bytes"), int) or receipt["download_bytes"] <= 0:
            raise ValueError("missing public byte length")
        download = receipt.get("download_path")
        matches = [p for p in receipt["proofs"] if p["path"] == download and p["sha256"] == receipt["download_sha256"]]
        if not matches or Path(download).stat().st_size != receipt["download_bytes"]:
            raise ValueError("public download bytes must be included in proofs with their exact length")
        if receipt.get("url") != state["release_url"]:
            raise ValueError("public release destination differs from configured scope")
        if receipt.get("commit") != state["receipts"]["freeze"]["commit"]:
            raise ValueError("public commit differs from frozen revision")
    if gate == "website_publication":
        if receipt.get("http_status") != 200 or not HEX.fullmatch(receipt.get("manifest_sha256", "")):
            raise ValueError("website needs HTTP 200 and exact deployed manifest")
        if receipt.get("url") != state["website_url"]:
            raise ValueError("website destination differs from configured scope")
        if not any(p["sha256"] == receipt["manifest_sha256"] for p in receipt["proofs"]):
            raise ValueError("website manifest must be included in file-backed proofs")


def statuses(state, anchor, head=None):
    result = {}
    stale_parent = False
    for gate in GATES:
        receipt = state["receipts"].get(gate)
        if not receipt:
            result[gate] = "PENDING"
            stale_parent = True
            continue
        valid = receipt.get("source_anchor") == anchor and not stale_parent
        if gate == "freeze" and head is not None and receipt.get("commit") != head:
            valid = False
        try:
            validate_receipt(state, gate, receipt, anchor, head)
        except (OSError, ValueError, TypeError, KeyError):
            valid = False
        result[gate] = "PASS" if valid else "STALE"
        stale_parent = not valid
    return result


def record(state, gate, receipt, root):
    no_secret_fields(receipt)
    anchor = source_anchor(root)
    current = statuses(state, anchor, git(root, "rev-parse", "HEAD").decode().strip())
    first = next((g for g in GATES if current[g] != "PASS"), None)
    if first != gate:
        raise ValueError(f"out of order; next={first or 'complete'}")
    validate_receipt(state, gate, receipt, anchor, git(root, "rev-parse", "HEAD").decode().strip())
    if gate == "freeze" and git(root, "status", "--porcelain").strip():
        raise ValueError("release source must be clean before freezing")
    # Revalidate after reading proofs, before binding the new state.
    if source_anchor(root) != anchor:
        raise ValueError("source changed during receipt validation")
    old = state["receipts"].get(gate)
    if old:
        state["history"].append(old)
    state["receipts"][gate] = receipt
    # Replacing a stale gate invalidates all dependent receipts, kept in history.
    keys = list(GATES)
    for dependent in keys[keys.index(gate) + 1:]:
        old = state["receipts"].pop(dependent, None)
        if old:
            state["history"].append(old)
    state["updated_at"] = datetime.now(timezone.utc).isoformat()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["init", "status", "next", "record"])
    parser.add_argument("gate", nargs="?", choices=list(GATES))
    parser.add_argument("receipt", nargs="?", type=Path)
    parser.add_argument("--state-dir", type=Path)
    parser.add_argument("--github-repository", help="owner/repository, only for init")
    parser.add_argument("--website-url", help="exact HTTPS product page, only for init")
    args = parser.parse_args()
    with (ROOT / "Support/AquaApp/Info.plist").open("rb") as stream:
        plist = plistlib.load(stream)
    version = plist["CFBundleShortVersionString"]
    directory = args.state_dir or ROOT / "audit-output" / f"release-{version}-loop"
    path = directory / "state.json"
    if args.command == "init":
        with writer(directory):
            if not path.exists():
                if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.github_repository or ""):
                    raise ValueError("init requires --github-repository owner/repository")
                if not (args.website_url or "").startswith("https://"):
                    raise ValueError("init requires --website-url with the exact HTTPS destination")
                atomic_json(path, {"schema_version": 2, "version": version, "receipts": {}, "history": [],
                                  "release_url": f"https://github.com/{args.github_repository}/releases/tag/v{version}",
                                  "website_url": args.website_url})
    if not path.exists():
        raise ValueError("state missing; run init")
    def read():
        state = json.loads(path.read_text())
        if state.get("schema_version") != 2 or state.get("version") != version:
            raise ValueError("incompatible state; do not reuse historical V6 receipts")
        return state
    if args.command == "record":
        if not args.gate or not args.receipt:
            raise ValueError("record requires gate and receipt path")
        if args.receipt.stat().st_size > 65536:
            raise ValueError("receipt exceeds 64 KiB")
        with writer(directory):
            state = read()
            record(state, args.gate, json.loads(args.receipt.read_text()), ROOT)
            atomic_json(path, state)
    state = read()
    anchor = source_anchor(ROOT)
    states = statuses(state, anchor, git(ROOT, "rev-parse", "HEAD").decode().strip())
    next_gate = next((g for g in GATES if states[g] != "PASS"), None)
    if args.command == "next":
        print(next_gate or "complete")
    else:
        print(json.dumps({"version": version, "source_anchor": anchor, "gates": states,
                          "next": next_gate, "complete": next_gate is None}, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        # Never dump payloads, process environments or provider output.
        message = str(error) if isinstance(error, ValueError) else type(error).__name__
        raise SystemExit(f"release loop refused: {message}")
