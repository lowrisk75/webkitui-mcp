#!/usr/bin/env python3
"""Hermetic custody/recovery tests. No provider, signing, or installed runtime."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import release_loop as loop


class ReleaseLoopTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="webkitui-loop-test-", dir="/private/tmp")
        self.base = Path(self.tmp.name)
        self.root = self.base / "repo"
        self.root.mkdir()
        self.command("init", "-q")
        (self.root / "source").write_text("fixture source\n")
        self.command("add", "source")
        self.command("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                     "commit", "-qm", "fixture")
        self.proof = self.base / "proof.txt"
        self.proof.write_text("synthetic evidence; no real provider action\n")
        self.signed = self.base / "signed.zip"
        self.signed.write_bytes(b"synthetic signed bytes")
        self.notarized = self.base / "notarized.zip"
        self.notarized.write_bytes(b"synthetic notarized bytes")
        self.state = {"schema_version": 2, "version": "0.6.6", "receipts": {}, "history": [],
                      "release_url": "https://github.com/fixture/product/releases/tag/v0.6.6",
                      "website_url": "https://example.invalid/product/"}

    def tearDown(self):
        self.tmp.cleanup()

    def command(self, *args):
        return subprocess.check_output(["git", "-C", str(self.root), *args], stderr=subprocess.PIPE)

    def receipt(self, gate):
        r = {"schema_version": 1, "gate": gate, "result": "PASS",
             "source_anchor": loop.source_anchor(self.root), "evidence_class": "CURRENT-OBSERVED",
             "completed_at": "2026-09-07T00:00:00Z", "summary": "synthetic test only",
             "proofs": [{"path": str(self.proof), "sha256": loop.digest(self.proof)}]}
        r.update({field: True for field in loop.GATES[gate]})
        if gate == "freeze":
            r["commit"] = self.command("rev-parse", "HEAD").decode().strip()
        if gate in {"signed_artifact", "notarization"}:
            artifact = self.signed if gate == "signed_artifact" else self.notarized
            r["artifact_sha256"] = loop.digest(artifact)
            r["proofs"].append({"path": str(artifact), "sha256": loop.digest(artifact)})
        if gate == "notarization":
            r.update(input_sha256=loop.digest(self.signed), request_id="synthetic-request")
        if gate in {"installed_validation", "public_release"}:
            r["artifact_sha256"] = loop.digest(self.notarized)
        if gate == "public_release":
            r.update(http_status=200, download_sha256=loop.digest(self.notarized), download_bytes=self.notarized.stat().st_size, download_path=str(self.notarized),
                     url=self.state["release_url"], commit=self.command("rev-parse", "HEAD").decode().strip())
            r["proofs"].append({"path": str(self.notarized), "sha256": loop.digest(self.notarized)})
        if gate == "website_publication":
            r.update(http_status=200, manifest_sha256=loop.digest(self.proof), url=self.state["website_url"])
        return r

    def through(self, last):
        for gate in loop.GATES:
            loop.record(self.state, gate, self.receipt(gate), self.root)
            if gate == last:
                break

    def test_full_chain_and_atomic_resume(self):
        self.through("reddit_delivery")
        path = self.base / "private" / "state.json"
        with loop.writer(path.parent):
            loop.atomic_json(path, self.state)
        reopened = json.loads(path.read_text())
        self.assertTrue(all(v == "PASS" for v in loop.statuses(reopened, loop.source_anchor(self.root)).values()))
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(path.parent.stat().st_mode & 0o777, 0o700)

    def test_source_drift_invalidates_dependents_and_preserves_history(self):
        self.through("local_validation")
        (self.root / "new-source").write_text("new release input")
        status = loop.statuses(self.state, loop.source_anchor(self.root))
        self.assertEqual(status["source_review"], "STALE")
        self.assertEqual(status["local_validation"], "STALE")
        loop.record(self.state, "source_review", self.receipt("source_review"), self.root)
        self.assertNotIn("local_validation", self.state["receipts"])
        self.assertEqual(len(self.state["history"]), 2)

    def test_changed_or_missing_proof_is_stale(self):
        self.through("source_review")
        self.proof.write_text("changed evidence")
        self.assertEqual(loop.statuses(self.state, loop.source_anchor(self.root))["source_review"], "STALE")
        self.proof.unlink()
        self.assertEqual(loop.statuses(self.state, loop.source_anchor(self.root))["source_review"], "STALE")

    def test_out_of_order_and_wrong_anchor(self):
        with self.assertRaisesRegex(ValueError, "out of order"):
            loop.record(self.state, "public_release", self.receipt("public_release"), self.root)
        r = self.receipt("source_review")
        r["source_anchor"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "stale"):
            loop.record(self.state, "source_review", r, self.root)

    def test_missing_semantics_secret_field_and_wrong_attestation(self):
        for update in [{"audit_current": False}, {"nested": {"api_key": "fictional"}},
                       {"evidence_class": "HUMAN-ATTESTED"}, {"proofs": []}]:
            r = self.receipt("source_review")
            r.update(update)
            with self.assertRaises(ValueError):
                loop.record(self.state, "source_review", r, self.root)

    def test_dirty_source_cannot_freeze(self):
        (self.root / "source").write_text("changed")
        self.through("physical_source")
        with self.assertRaisesRegex(ValueError, "clean"):
            loop.record(self.state, "freeze", self.receipt("freeze"), self.root)

    def test_commit_drift_invalidates_frozen_gate(self):
        self.through("freeze")
        states = loop.statuses(self.state, loop.source_anchor(self.root), "different-commit")
        self.assertEqual(states["physical_source"], "PASS")
        self.assertEqual(states["freeze"], "STALE")

    def test_notarization_binds_signed_input(self):
        self.through("signed_artifact")
        r = self.receipt("notarization")
        r["input_sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "input differs"):
            loop.record(self.state, "notarization", r, self.root)

    def test_public_hash_http_and_destination_must_match(self):
        self.through("release_review")
        for change in [{"http_status": 404}, {"download_sha256": "0" * 64},
                       {"artifact_sha256": "0" * 64}, {"download_bytes": 0},
                       {"url": "https://github.com/wrong/repo"}, {"commit": "wrong"}]:
            r = self.receipt("public_release")
            r.update(change)
            with self.assertRaises(ValueError):
                loop.record(self.state, "public_release", r, self.root)

    def test_public_download_requires_actual_bytes(self):
        self.through("release_review")
        for change in [{"download_bytes": 999}, {"download_path": str(self.proof)},
                       {"proofs": [{"path": str(self.proof), "sha256": loop.digest(self.proof)}]}]:
            r = self.receipt("public_release")
            r.update(change)
            with self.assertRaises(ValueError):
                loop.record(self.state, "public_release", r, self.root)

    def test_reloaded_receipt_semantics_are_rechecked(self):
        self.through("reddit_delivery")
        self.state["receipts"]["notarization"]["input_sha256"] = "0" * 64
        status = loop.statuses(self.state, loop.source_anchor(self.root))
        self.assertEqual(status["signed_artifact"], "PASS")
        self.assertEqual(status["notarization"], "STALE")
        self.assertEqual(status["reddit_delivery"], "STALE")
        self.state["receipts"]["source_review"]["audit_current"] = False
        self.assertEqual(loop.statuses(self.state, loop.source_anchor(self.root))["source_review"], "STALE")

    def test_website_manifest_must_be_proved(self):
        self.through("public_release")
        r = self.receipt("website_publication")
        r["manifest_sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "manifest must"):
            loop.record(self.state, "website_publication", r, self.root)


if __name__ == "__main__":
    unittest.main()
