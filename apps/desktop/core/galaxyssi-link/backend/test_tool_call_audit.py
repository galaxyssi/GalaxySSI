from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from tool_call_audit import ToolCallAuditStore


class ToolCallAuditStoreTests(unittest.TestCase):
    def test_persists_filterable_metadata_without_raw_arguments_or_results(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "audit.json"
            store = ToolCallAuditStore(path)
            record = store.append(
                tool_id="galaxyssi.desktop.file.read_text",
                tool_version="1.0.0",
                location="desktop",
                risk="low",
                confirmation="none",
                status="succeeded",
                started_at=100,
                finished_at=125,
                input_sha256="a" * 64,
                output_sha256="b" * 64,
                invocation_id="call-1",
                context={
                    "client_route_id": "private-phone-route",
                    "conversation_id": "private-conversation",
                    "caller_id": "codex",
                    "arguments": {"api_key": "secret"},
                },
            )
            restored = ToolCallAuditStore(path).list(
                tool_id="galaxyssi.desktop.file.read_text",
                status="succeeded",
            )

        self.assertEqual("not_required", record["confirmation"])
        self.assertEqual(25, record["duration_ms"])
        self.assertEqual([record], restored)
        encoded = str(restored)
        self.assertNotIn("private-phone-route", encoded)
        self.assertNotIn("private-conversation", encoded)
        self.assertNotIn("secret", encoded)

    def test_records_approval_state_and_error_code(self) -> None:
        store = ToolCallAuditStore(None)
        record = store.append(
            tool_id="galaxyssi.desktop.terminal.run",
            tool_version="1.0.0",
            location="desktop",
            risk="high",
            confirmation="execute",
            status="failed",
            started_at=100,
            finished_at=110,
            input_sha256="a" * 64,
            output_sha256="b" * 64,
            error_code="command_failed",
            context={"confirmation": {"decision": "approved"}},
        )

        self.assertEqual("approved", record["confirmation"])
        self.assertEqual("command_failed", record["error_code"])


if __name__ == "__main__":
    unittest.main()
