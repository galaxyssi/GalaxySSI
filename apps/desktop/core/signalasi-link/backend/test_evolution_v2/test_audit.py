from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from evolution_v2.audit import AuditLedger


class AuditTests(unittest.TestCase):
    def test_hash_chain_and_secret_redaction(self):
        with tempfile.TemporaryDirectory() as root:
            ledger = AuditLedger(Path(root) / "audit.jsonl")
            ledger.append("created", task_id="t1", payload={"api_key": "secret-value", "note": "ok"})
            ledger.append("passed", task_id="t1", payload={"authorization": "Bearer abcdefghijklmnop"})
            integrity = ledger.verify()
            self.assertTrue(integrity["valid"])
            self.assertEqual(2, integrity["records"])
            text = (Path(root) / "audit.jsonl").read_text(encoding="utf-8")
            self.assertNotIn("secret-value", text)
            self.assertNotIn("abcdefghijklmnop", text)

    def test_tampering_is_detected(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "audit.jsonl"
            ledger = AuditLedger(path)
            ledger.append("created", payload={"value": 1})
            row = json.loads(path.read_text(encoding="utf-8"))
            row["payload"]["value"] = 2
            path.write_text(json.dumps(row) + "\n", encoding="utf-8")
            self.assertFalse(ledger.verify()["valid"])

    def test_invalid_trailing_record_is_detected(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "audit.jsonl"
            ledger = AuditLedger(path)
            ledger.append("created", task_id="t1")
            with path.open("a", encoding="utf-8") as stream:
                stream.write("{invalid\n")
            result = ledger.verify()
            self.assertFalse(result["valid"])
            self.assertIn("record 2: invalid JSON", result["errors"])


if __name__ == "__main__":
    unittest.main()
