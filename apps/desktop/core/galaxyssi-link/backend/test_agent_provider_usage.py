from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
import base64
import json
import os
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch

from agent_provider_usage import AgentProviderUsage
from agent_task_recovery_query import IDENTITY_FIELDS
from agent_task_store import AgentTaskStore, AgentTaskWriteConflict
from agent_tool_evidence import task_identity
from codex_provider_usage import normalize
from test_codex_provider_usage import observation, payload


class AgentProviderUsageTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.path = Path(temporary.name) / "run.db"
        self.store = AgentTaskStore(self.path)
        self.task = dict(task_id="task", client_route_id="phone", client_conversation_id="conversation",
                         client_turn_id="turn", source_message_id="1234", contact_id="paired-codex", agent_id="codex",
                         conversation_id="backend", status="running", execution_generation=1, status_seq=1)
        self.store.upsert(self.task)
        self.archive = AgentProviderUsage(self.path)

    def request(self, **values):
        return {**task_identity(self.task), "execution_generation": 1, **values}

    def query(self, **values):
        return self.archive.query(self.request(**values), client_route_id="phone")

    def test_deduplicates_exact_snapshots_without_summing_cumulative_counters(self):
        first = self.archive.record(self.task, observation())
        self.assertEqual(first, self.archive.record(self.task, observation()))
        second = self.archive.record(self.task, observation(200))
        result = self.query()
        self.assertEqual([first, second], result["entries"])
        self.assertFalse(result["provider_history_complete"])
        for field in ("task_token_total", "request_count", "billed_cost"):
            self.assertIsNone(result[field])
        self.assertEqual([100, 200], [row["observation"]["total"]["input_tokens"] for row in result["entries"]])

    def test_reopening_reads_same_immutable_entries(self):
        first = self.archive.record(self.task, observation())
        self.archive = AgentProviderUsage(self.path)
        self.assertEqual([first], self.query()["entries"])
        self.assertEqual(first, self.archive.record(self.task, observation()))

    def test_more_than_100_observations_use_stable_pagination(self):
        for i in range(103):
            self.archive.record(self.task, observation(100 + i))
        first = self.query()
        self.assertEqual(100, len(first["entries"]))
        self.assertTrue(first["has_more"])
        second = self.query(after_sequence=first["next_sequence"])
        self.assertEqual([101, 102, 103], [row["sequence"] for row in second["entries"]])
        self.assertFalse(second["has_more"])

    def test_each_identity_field_is_isolated(self):
        self.archive.record(self.task, observation())
        for key in IDENTITY_FIELDS:
            with self.subTest(key=key):
                result = self.query(**{key: "other"})
                if key in {"client_route_id", "agent_id"}:
                    self.assertIsNone(result)
                else:
                    self.assertEqual("unavailable", result["status"])

    def test_old_generation_cannot_write_but_can_be_read(self):
        first = self.archive.record(self.task, observation())
        current = self.store.get("task")
        current["execution_generation"] = 2
        self.store.upsert(current)
        with self.assertRaises(AgentTaskWriteConflict):
            self.archive.record(self.task, observation(200))
        second = self.archive.record(current, observation(300))
        self.assertEqual([first], self.query()["entries"])
        self.assertEqual([second], self.query(execution_generation=2)["entries"])
        self.assertEqual("unavailable", self.query(execution_generation=3)["status"])

    def test_worker_reservation_prevents_unfenced_local_write(self):
        with closing(sqlite3.connect(self.path)) as db, db:
            db.execute("CREATE TABLE agent_worker_queue(task_id TEXT PRIMARY KEY)")
            db.execute("INSERT INTO agent_worker_queue VALUES('task')")
        with self.assertRaises(AgentTaskWriteConflict):
            self.archive.record(self.task, observation())
        self.assertEqual([], self.query()["entries"])

    def test_finished_execution_accepts_late_usage_without_touching_task_state(self):
        current = self.store.get("task")
        current["status"] = "completed"
        self.store.upsert(current)
        before = self.store.get("task")
        self.archive.record(before, observation())
        self.assertEqual(before, self.store.get("task"))

    def test_same_provider_thread_can_have_distinct_turn_snapshots(self):
        first = self.archive.record(self.task, observation())
        params = payload()
        params["turnId"] = "repair-turn"
        second = self.archive.record(self.task, normalize(params, model="fixture-model", effort="high"))
        self.assertNotEqual(first["event_id"], second["event_id"])
        self.assertEqual(2, len(self.query()["entries"]))

    def test_allowlist_rejects_wrong_contract_and_discards_extra_content(self):
        for change in ({"contract": "fake"}, {"provider": "other"}, {"kind": {}}, {"issues": ["secret"]}):
            self.assertIsNone(self.archive.record(self.task, {**observation(), **change}))
        value = {**observation(), "prompt": "DO-NOT-PERSIST", "api_key": "DO-NOT-PERSIST"}
        value["total"]["unknown"] = "DO-NOT-PERSIST"
        entry = self.archive.record(self.task, value)
        self.assertNotIn("DO-NOT-PERSIST", json.dumps(entry))
        self.assertEqual([], entry["observation"]["issues"])

    def test_invalid_numbers_remain_null_with_original_diagnostics(self):
        params = payload()
        params["tokenUsage"]["last"]["outputTokens"] = True
        value = normalize(params, model="m", effort="high")
        entry = self.archive.record(self.task, value)
        self.assertIsNone(entry["observation"]["last"]["output_tokens"])
        self.assertIn("last.outputTokens:invalid_or_missing_counter", entry["observation"]["issues"])

    def test_encrypted_body_and_tamper_detection(self):
        self.archive.record(self.task, observation())
        with closing(sqlite3.connect(self.path)) as db, db:
            body = db.execute("SELECT body FROM agent_provider_usage").fetchone()[0]
            self.assertTrue(body.startswith("enc:v1:"))
            self.assertNotIn("fixture-model", body)
            db.execute("UPDATE agent_provider_usage SET body='forged'")
        with self.assertRaises(Exception):
            self.query()

    def test_digest_tampering_is_not_returned_as_valid_audit(self):
        self.archive.record(self.task, observation())
        with closing(sqlite3.connect(self.path)) as db, db:
            db.execute("UPDATE agent_provider_usage SET digest=?", ("0" * 64,))
        with self.assertRaisesRegex(ValueError, "integrity"):
            self.query()

    def test_failed_write_is_atomic_and_manual_audit_retry_does_not_repeat_execution(self):
        before = self.store.get("task")
        with patch("agent_provider_usage.encrypt_text", side_effect=OSError("disk full")):
            with self.assertRaises(OSError):
                self.archive.record(self.task, observation())
        self.assertEqual([], self.query()["entries"])
        self.assertEqual(before, self.store.get("task"))
        entry = self.archive.record(self.task, observation())
        self.assertEqual(1, entry["sequence"])

    def test_concurrent_duplicate_delivery_records_once(self):
        with ThreadPoolExecutor(max_workers=6) as pool:
            entries = list(pool.map(lambda _: self.archive.record(self.task, observation()), range(12)))
        self.assertTrue(all(entry == entries[0] for entry in entries))
        self.assertEqual(1, len(self.query()["entries"]))

    def test_read_before_first_observation_does_not_create_schema_or_key(self):
        self.assertEqual("unavailable", self.query()["status"])
        self.assertFalse((self.path.parent / ".galaxyssi-state-key").exists())
        with closing(sqlite3.connect(self.path)) as db:
            self.assertIsNone(db.execute("SELECT 1 FROM sqlite_master WHERE name='agent_provider_usage'").fetchone())

    def test_invalid_query_does_not_open_database(self):
        for change in ({"task_id": 1}, {"execution_generation": True}, {"execution_generation": 0},
                       {"after_sequence": -1}, {"after_sequence": True}, {"through_sequence": -1},
                       {"through_sequence": True}):
            with patch("agent_provider_usage.sqlite3.connect") as connect:
                self.assertIsNone(self.query(**change))
                connect.assert_not_called()

    def test_lifecycle_and_usage_are_distinct_events(self):
        for kind in ("turn_started", "usage_snapshot", "turn_terminal"):
            value = normalize(payload(), model="m", effort="high", kind=kind, status="completed")
            self.archive.record(self.task, value)
        self.assertEqual(["turn_started", "usage_snapshot", "turn_terminal"],
                         [entry["observation"]["kind"] for entry in self.query()["entries"]])

    def test_bounded_read_does_not_include_later_appends(self):
        self.archive.record(self.task, observation())
        first = self.query()
        self.archive.record(self.task, observation(200))
        second = self.query(after_sequence=first["next_sequence"],
                            through_sequence=first["observed_through_sequence"])
        self.assertEqual([], second["entries"])
        self.assertEqual(1, second["observed_through_sequence"])
        self.assertEqual(2, len(self.query()["entries"]))

    def test_separate_writers_deduplicate_transactionally(self):
        def record(_):
            return AgentProviderUsage(self.path).record(self.task, observation())
        with ThreadPoolExecutor(max_workers=4) as pool:
            entries = list(pool.map(record, range(8)))
        self.assertTrue(all(entry == entries[0] for entry in entries))
        self.assertEqual(1, len(self.query()["entries"]))

    def test_missing_key_cannot_turn_existing_usage_into_an_empty_report(self):
        from secure_state import MASTER_KEY_ENV, MASTER_KEY_NAME, SecureStateError
        with patch.dict(os.environ, {MASTER_KEY_ENV: ""}):
            self.archive.record(self.task, observation())
            key = self.path.parent / MASTER_KEY_NAME
            key.unlink()
            key.with_suffix(".bak").unlink(missing_ok=True)
            with self.assertRaises(SecureStateError):
                self.query()
            with self.assertRaises(SecureStateError):
                self.archive.record(self.task, observation(200))
            self.assertFalse(key.exists())
            with closing(sqlite3.connect(self.path)) as db:
                self.assertEqual(1, db.execute("SELECT COUNT(*) FROM agent_provider_usage").fetchone()[0])

    def test_wrong_key_override_cannot_present_an_empty_scope_or_fork_the_journal(self):
        from secure_state import MASTER_KEY_ENV, SecureStateError
        self.archive.record(self.task, observation())
        with patch.dict(os.environ, {MASTER_KEY_ENV: base64.b64encode(b"x" * 32).decode()}):
            with self.assertRaises(SecureStateError):
                self.query()
            with self.assertRaises(SecureStateError):
                self.archive.record(self.task, observation(200))
        self.assertEqual(1, len(self.query()["entries"]))


if __name__ == "__main__":
    unittest.main()
