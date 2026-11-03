import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from agent_provider_usage import AgentProviderUsage
from agent_task_store import AgentTaskStore
from agent_tool_evidence import canonical, task_identity
from codex_usage_export import export
from test_codex_provider_usage import observation


class CodexUsageExportTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.path = self.root / "run.db"
        store = AgentTaskStore(self.path)
        self.task = dict(task_id="task", client_route_id="phone", client_conversation_id="conversation",
                         client_turn_id="turn", source_message_id="1234", contact_id="paired-codex", agent_id="codex",
                         conversation_id="backend", status="running", execution_generation=1, status_seq=1)
        store.upsert(self.task)
        self.archive = AgentProviderUsage(self.path)
        self.scope = {**task_identity(self.task), "execution_generation": 1}
        self.output = self.root / "private" / "usage.json"

    def test_exports_paginated_metadata_with_unknown_accounting_not_fake_zero(self):
        for i in range(102):
            self.archive.record(self.task, observation(100 + i))
        report = export(self.path, {**self.scope, "prompt": "DO-NOT-EXPORT"}, self.output)
        self.assertEqual(102, report["journal_entry_count"])
        self.assertEqual(102, report["usage_snapshot_count"])
        self.assertEqual(report, json.loads(self.output.read_text(encoding="utf-8")))
        self.assertEqual(hashlib.sha256(canonical(report["entries"])).hexdigest(), report["entries_sha256"])
        self.assertIsNone(report["request_count"])
        self.assertIsNone(report["billed_cost"])
        self.assertFalse(report["provider_history_complete"])
        self.assertNotIn("DO-NOT-EXPORT", self.output.read_text())

    def test_never_overwrites_existing_audit(self):
        self.archive.record(self.task, observation())
        export(self.path, self.scope, self.output)
        original = self.output.read_bytes()
        with self.assertRaises(FileExistsError):
            export(self.path, self.scope, self.output)
        self.assertEqual(original, self.output.read_bytes())

    def test_no_export_of_unknown_or_mismatched_scope(self):
        for change in ({"client_turn_id": "wrong", "turn_id": "wrong"}, {"execution_generation": 2}):
            with self.assertRaises(ValueError):
                export(self.path, {**self.scope, **change}, self.output)
        self.assertFalse(self.output.exists())

    def test_refuses_git_worktree_and_repository_destinations(self):
        self.archive.record(self.task, observation())
        (self.root / ".git").mkdir()
        with self.assertRaisesRegex(ValueError, "outside Git"):
            export(self.path, self.scope, self.output)
        self.assertFalse(self.output.exists())

    def test_invalid_generation_cannot_open_journal(self):
        with self.assertRaises(ValueError):
            export(self.path, {**self.scope, "execution_generation": True}, self.output)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
