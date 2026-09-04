import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from agent_reputation_ledger import AgentReputationLedger


class _TestIdentity:
    signer_id = "desktop_0123456789abcdef"
    signature_key_id = hashlib.sha256(b"test-public-key").hexdigest()
    secret = b"test-signing-secret"

    def identity(self) -> dict[str, str]:
        return {
            "signer_id": self.signer_id,
            "signature_key_id": self.signature_key_id,
        }

    def sign(self, payload: bytes) -> dict[str, str]:
        return {
            **self.identity(),
            "signature": hashlib.sha256(self.secret + payload).hexdigest(),
        }

    def verify(self, payload: bytes, signature: str) -> bool:
        return signature == self.sign(payload)["signature"]


class AgentReputationLedgerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.identity = _TestIdentity()
        self.now = 20_000_000

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def ledger(self) -> AgentReputationLedger:
        return AgentReputationLedger(
            self.root / "ledger.jsonl",
            self.root / "head.json",
            identity_provider=self.identity.identity,
            signer=self.identity.sign,
            verifier=self.identity.verify,
            clock=lambda: self.now,
        )

    def task(
        self,
        task_id: str,
        status: str = "completed",
        *,
        agent_id: str = "codex",
        result: str = "done",
    ) -> dict:
        return {
            "task_id": task_id,
            "agent_id": agent_id,
            "contact_id": f"{self.identity.signer_id}:{agent_id}",
            "status": status,
            "created_at": self.now - 2_000,
            "started_at": self.now - 1_500,
            "completed_at": self.now,
            "result": result,
            "error": "failed" if status == "failed" else "",
            "exit_code": 1 if status == "failed" else 0,
            "output_files": [],
            "attempt": 1,
        }

    def test_records_signed_android_compatible_host_receipt(self) -> None:
        ledger = self.ledger()

        receipt = ledger.record_task(self.task("task-1"))

        self.assertIsNotNone(receipt)
        self.assertEqual("HOST_OBSERVED", receipt["provenance"])
        self.assertEqual("SUCCEEDED", receipt["outcome"])
        self.assertEqual(
            f"{self.identity.signer_id}:codex",
            receipt["agent_id"],
        )
        self.assertIn("CODE", receipt["capabilities"])
        self.assertIn("TASK_EXECUTION", receipt["capabilities"])
        self.assertEqual(self.identity.signer_id, receipt["signer_id"])
        self.assertEqual(64, len(receipt["task_id_hash"]))
        self.assertTrue(receipt["signature"])
        self.assertEqual("verified", ledger.integrity()["reason"])

    def test_duplicate_terminal_event_is_idempotent(self) -> None:
        ledger = self.ledger()
        first = ledger.record_task(self.task("task-1"))
        second = ledger.record_task(self.task("task-1", result="changed"))

        self.assertEqual(first, second)
        self.assertEqual(1, ledger.integrity()["records"])

    def test_persists_and_reloads_verified_chain(self) -> None:
        ledger = self.ledger()
        expected = ledger.record_task(self.task("task-1"))

        reloaded = self.ledger()

        self.assertTrue(reloaded.integrity()["ok"])
        self.assertEqual(expected, reloaded.receipt_for_task("task-1"))

    def test_record_tampering_is_detected_and_blocks_append(self) -> None:
        ledger = self.ledger()
        ledger.record_task(self.task("task-1"))
        ledger_path = self.root / "ledger.jsonl"
        document = json.loads(ledger_path.read_text(encoding="utf-8"))
        document["receipt"]["outcome"] = "FAILED"
        ledger_path.write_text(
            json.dumps(document, separators=(",", ":")) + "\n",
            encoding="utf-8",
        )

        tampered = self.ledger()

        self.assertFalse(tampered.integrity()["ok"])
        with self.assertRaisesRegex(RuntimeError, "integrity failure"):
            tampered.record_task(self.task("task-2"))

    def test_signed_head_detects_tail_truncation(self) -> None:
        ledger = self.ledger()
        ledger.record_task(self.task("task-1"))
        self.now += 1_000
        ledger.record_task(self.task("task-2"))
        ledger_path = self.root / "ledger.jsonl"
        first_line = ledger_path.read_text(encoding="utf-8").splitlines()[0]
        ledger_path.write_text(first_line + "\n", encoding="utf-8")

        truncated = self.ledger()

        self.assertFalse(truncated.integrity()["ok"])
        self.assertIn("ledger_truncated", truncated.integrity()["reason"])

    def test_task_index_cannot_be_rebound_to_a_signed_receipt(self) -> None:
        ledger = self.ledger()
        ledger.record_task(self.task("task-1"))
        ledger_path = self.root / "ledger.jsonl"
        document = json.loads(ledger_path.read_text(encoding="utf-8"))
        document["task_id"] = "forged-task"
        unsigned = dict(document)
        unsigned.pop("record_hash")
        document["record_hash"] = hashlib.sha256(
            json.dumps(
                unsigned,
                ensure_ascii=False,
                separators=(",", ":"),
                sort_keys=True,
            ).encode("utf-8")
        ).hexdigest()
        ledger_path.write_text(
            json.dumps(document, separators=(",", ":"), sort_keys=True) + "\n",
            encoding="utf-8",
        )

        rebound = self.ledger()

        self.assertFalse(rebound.integrity()["ok"])
        self.assertIn("task_binding_mismatch", rebound.integrity()["reason"])

    def test_snapshot_tracks_success_timeout_and_capability_scope(self) -> None:
        ledger = self.ledger()
        ledger.record_task(self.task("code-success"))
        self.now += 1_000
        ledger.record_task(self.task(
            "research-timeout",
            status="timed_out",
            agent_id="hermes",
            result="",
        ))

        code = ledger.snapshot(
            f"{self.identity.signer_id}:codex",
            ["code"],
            self.now,
        )
        research = ledger.snapshot(
            f"{self.identity.signer_id}:hermes",
            ["research"],
            self.now,
        )

        self.assertEqual(1, code["evaluated_runs"])
        self.assertGreater(code["score"], research["score"])
        self.assertEqual(1, research["timeout_runs"])
        self.assertEqual(1, research["failed_runs"])


if __name__ == "__main__":
    unittest.main()
