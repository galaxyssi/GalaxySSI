import base64
from contextlib import closing
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

from agent_task_store import AgentTaskStore, AgentTaskWriteConflict
from agent_tool_evidence import (AgentToolEvidence, EvidenceConflict, IDENTITY_FIELDS, INDEX_PAGE_SIZE,
                                 PAGE_BYTES, canonical, completed_tool_observation, observation_outcome, task_identity)
from codex_tool_evidence_bridge import capture


class AgentToolEvidenceTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.path = Path(temporary.name) / "run.db"
        self.store = AgentTaskStore(self.path)
        self.task = dict(task_id="task", client_route_id="phone", client_conversation_id="conversation",
                         client_turn_id="turn", source_message_id="1234", contact_id="paired-codex", agent_id="codex",
                         conversation_id="backend", status="running", execution_generation=1, status_seq=1)
        self.store.upsert(self.task)
        self.archive = AgentToolEvidence(self.path)

    def observation(self, item_id="item", **values):
        item = {"id": item_id, "type": "commandExecution", "command": "fixture-command",
                "aggregatedOutput": "original-output", "exitCode": 0, **values}
        return completed_tool_observation(item, thread_id="provider-thread", turn_id="provider-turn")

    def request(self, **values):
        return {**task_identity(self.task), "request_id": "nonce", "execution_generation": 1, **values}

    def query(self, **values):
        return self.archive.query(self.request(**values), client_route_id="phone")

    def read(self, descriptor):
        pages = [self.query(mode="page", evidence_id=descriptor["evidence_id"], sha256=descriptor["sha256"],
                            page_index=i) for i in range(descriptor["page_count"])]
        for page in pages:
            self.assertEqual("ready", page["status"])
            self.assertEqual(hashlib.sha256(base64.b64decode(page["data_b64"])).hexdigest(), page["page_sha256"])
        raw = b"".join(base64.b64decode(page["data_b64"]) for page in pages)
        self.assertEqual(descriptor["sha256"], hashlib.sha256(raw).hexdigest())
        return json.loads(raw)

    def test_large_original_survives_paging_without_ui_truncation(self):
        original = self.observation(aggregatedOutput="\u8bc1\u636e" * 24000)
        receipt = self.archive.record(self.task, original)
        self.assertGreater(receipt["total_bytes"], 128 * 1024)
        self.assertEqual(original, self.read(receipt)["observation"])
        self.assertEqual("execution_observed_not_claim_verified", receipt["trust"])
        self.assertEqual("provider_payload_as_received", receipt["coverage"])

    def test_small_original_can_share_index_with_exact_page_and_sealed_boundary(self):
        entry = self.archive.record(self.task, self.observation())
        self.assertEqual([], self.query()["inline_pages"])
        running = self.query(inline_page_bytes=PAGE_BYTES)
        self.assertFalse(running["archive_final"])
        self.assertEqual([entry], running["entries"])
        inline = running["inline_pages"][0]
        ordinary = self.query(mode="page", evidence_id=entry["evidence_id"], sha256=entry["sha256"], page_index=0)
        self.assertTrue(all(ordinary[key] == value for key, value in inline.items()))
        self.store.upsert({**self.store.get("task"), "status": "completed", "status_seq": 2})
        terminal = self.query(inline_page_bytes=PAGE_BYTES)
        self.assertTrue(terminal["archive_final"])
        self.assertFalse(terminal["has_more"])
        self.assertEqual(entry["sha256"], hashlib.sha256(base64.b64decode(inline["data_b64"])).hexdigest())

    def test_inline_byte_budget_is_total_and_large_originals_still_page(self):
        for i in range(5):
            self.archive.record(self.task, self.observation(str(i), aggregatedOutput="x" * 7000))
        self.archive.record(self.task, self.observation("large", aggregatedOutput="x" * 40000))
        response = self.query(inline_page_bytes=PAGE_BYTES)
        self.assertEqual(6, len(response["entries"]))
        self.assertEqual(2, len(response["inline_pages"]))
        self.assertLessEqual(sum(len(base64.b64decode(p["data_b64"])) for p in response["inline_pages"]), PAGE_BYTES)
        for entry in response["entries"]:
            self.assertIsNotNone(self.read(entry))

    def test_invalid_inline_budget_never_opens_database(self):
        for value in (True, -1, PAGE_BYTES + 1, "16384", 1.5, None):
            with patch.object(self.archive, "_connect") as connect:
                self.assertIsNone(self.query(inline_page_bytes=value))
                connect.assert_not_called()

    def test_inline_projection_cannot_return_phone_owned_recall_bodies(self):
        self.archive.record(self.task, self.observation("recall", type="dynamicToolCall", tool="collaboration_recall"))
        external = self.archive.record(self.task, self.observation("external"))
        result = self.archive.query(self.request(inline_page_bytes=PAGE_BYTES), client_route_id="phone", phone_import=True)
        self.assertEqual([external["evidence_id"]], [p["evidence_id"] for p in result["inline_pages"]])

    def test_phone_import_omits_recall_echo_but_full_audit_and_original_are_retained(self):
        original = self.observation("recall", type="dynamicToolCall", tool="collaboration_recall",
                                    result={"contentItems": [{"type": "inputText", "text": "phone-original" * 5000}]})
        recall = self.archive.record(self.task, original)
        external = self.archive.record(self.task, self.observation("actual-command"))
        projected = self.archive.query(self.request(), client_route_id="phone", phone_import=True)
        self.assertEqual([external], projected["entries"])
        self.assertEqual("external_execution_observations", projected["projection"])
        self.assertFalse(projected["provider_history_complete"])
        self.assertEqual(2, len(self.query()["entries"]))
        self.assertEqual(original, self.read(recall)["observation"])
        from codex_tool_evidence_bridge import query
        manager = SimpleNamespace(tool_evidence=self.archive)
        self.assertEqual([external], query(manager, self.request(), client_route_id="phone")["entries"])
        self.assertIsNone(query(manager, self.request(), client_route_id="other-phone"))

    def test_projection_cursor_skips_internal_reads_without_losing_external_observations(self):
        external = []
        for i in range(45):
            self.archive.record(self.task, self.observation(f"read-{i}", type="dynamicToolCall", tool="collaboration_recall"))
            external.append(self.archive.record(self.task, self.observation(f"command-{i}")))
        cursor, found = 0, []
        while True:
            page = self.archive.query(self.request(after_sequence=cursor), client_route_id="phone", phone_import=True)
            found.extend(page["entries"])
            cursor = page["next_sequence"]
            if not page["has_more"]: break
        self.assertEqual(external, found)
        self.assertEqual(90, cursor)

    def test_only_host_registered_internal_recall_type_is_excluded(self):
        receipts = []
        for i, (kind, tool) in enumerate((("mcpToolCall", "collaboration_recall"), ("commandExecution", "collaboration_recall"),
                                         ("dynamicToolCall", "web_fetch"), ("dynamicToolCall", "other"))):
            receipts.append(self.archive.record(self.task, self.observation(str(i), type=kind, tool=tool)))
        self.assertEqual(receipts, self.archive.query(self.request(), client_route_id="phone", phone_import=True)["entries"])

    def test_legacy_evidence_schema_adds_projection_without_dropping_observations(self):
        from secure_state import encrypt_text
        receipt = self.archive.record(self.task, self.observation(aggregatedOutput="legacy-output" * PAGE_BYTES))
        receipt.pop("phone_import")
        with closing(sqlite3.connect(self.path)) as db, db:
            scope = db.execute("SELECT scope FROM agent_tool_evidence").fetchone()[0]
            encrypted = encrypt_text(self.path, canonical(receipt).decode(),
                                     purpose=self.archive._purpose(scope, receipt["evidence_id"], "meta"))
            db.execute("UPDATE agent_tool_evidence SET descriptor=?", (encrypted,))
            db.execute("DROP INDEX tool_evidence_phone_import")
            db.execute("ALTER TABLE agent_tool_evidence DROP COLUMN phone_import")
        self.archive = AgentToolEvidence(self.path)
        self.assertEqual([receipt], self.archive.query(self.request(), client_route_id="phone", phone_import=True)["entries"])
        self.assertEqual("legacy-output" * PAGE_BYTES, self.read(receipt)["observation"]["item"]["aggregatedOutput"])

    def test_duplicate_is_exact_replay_and_conflict_cannot_overwrite(self):
        original = self.archive.record(self.task, self.observation())
        self.assertEqual(original, self.archive.record(self.task, self.observation()))
        with self.assertRaises(EvidenceConflict):
            self.archive.record(self.task, self.observation(aggregatedOutput="replacement"))
        self.assertEqual("original-output", self.read(original)["observation"]["item"]["aggregatedOutput"])
        self.assertEqual(1, len(self.query()["entries"]))

    def test_more_than_100_observations_are_retained_and_cursor_is_stable(self):
        for i in range(121):
            self.archive.record(self.task, self.observation(str(i)))
        cursor, entries = 0, []
        while True:
            result = self.query(after_sequence=cursor)
            self.assertLessEqual(len(result["entries"]), INDEX_PAGE_SIZE)
            entries.extend(result["entries"])
            cursor = result["next_sequence"]
            if not result["has_more"]:
                break
        self.assertEqual(list(range(1, 122)), [entry["sequence"] for entry in entries])
        self.assertEqual("0", self.read(entries[0])["observation"]["item"]["id"])

    def test_each_identity_field_and_generation_isolated(self):
        self.archive.record(self.task, self.observation())
        for key in IDENTITY_FIELDS:
            with self.subTest(key=key):
                result = self.query(**{key: "other"})
                if key == "client_route_id":
                    self.assertIsNone(result)
                else:
                    self.assertEqual("unavailable", result["status"])
        self.assertEqual("unavailable", self.query(execution_generation=2)["status"])

    def test_provider_turn_and_thread_cannot_reuse_observation_identity(self):
        first = self.archive.record(self.task, self.observation())
        for key in ("thread_id", "turn_id"):
            other = self.observation()
            other[key] = "other"
            receipt = self.archive.record(self.task, other)
            self.assertNotEqual(first["evidence_id"], receipt["evidence_id"])
        self.assertEqual(3, len(self.query()["entries"]))

    def test_invalid_queries_do_not_open_database(self):
        for values in ({"task_id": 123}, {"execution_generation": True}, {"execution_generation": 0},
                       {"request_id": ""}, {"after_sequence": -1}, {"after_sequence": True},
                       {"mode": "page", "page_index": 0, "evidence_id": "forged", "sha256": "0" * 64},
                       {"mode": "execute"}, {"mode": {}}):
            with self.subTest(values=values), patch.object(self.archive, "_connect") as connect:
                self.assertIsNone(self.query(**values))
                connect.assert_not_called()

    def test_failed_tool_is_not_successful_evidence(self):
        for values in ({"exitCode": 1}, {"status": "failed"}, {"error": {"message": "bad"}},
                       {"result": {"isError": True}}, {"isError": True}, {"status": "declined"}):
            with self.subTest(values=values):
                self.assertEqual("failed", observation_outcome({**self.observation()["item"], **values}))
        receipt = self.archive.record(self.task, self.observation(exitCode=2))
        self.assertEqual("failed", receipt["outcome"])

    def test_old_callback_cannot_write_after_generation_changes(self):
        current = self.store.get("task")
        current["execution_generation"] = 2
        self.store.upsert(current)
        with self.assertRaises(AgentTaskWriteConflict):
            self.archive.record(self.task, self.observation())
        self.assertEqual([], self.query(execution_generation=2)["entries"])

    def test_worker_reservation_fences_capture_in_same_transaction(self):
        with closing(sqlite3.connect(self.path)) as db, db:
            db.execute("CREATE TABLE agent_worker_queue(task_id TEXT PRIMARY KEY)")
            db.execute("INSERT INTO agent_worker_queue VALUES('task')")
        with self.assertRaises(AgentTaskWriteConflict):
            self.archive.record(self.task, self.observation())

    def test_terminal_task_keeps_exact_replay_but_rejects_new_observations(self):
        original = self.archive.record(self.task, self.observation())
        current = self.store.get("task")
        current["status"] = "completed"
        self.store.upsert(current)
        self.assertEqual(original, self.archive.record(current, self.observation()))
        with self.assertRaises(AgentTaskWriteConflict):
            self.archive.record(current, self.observation("late"))

    def test_plaintext_is_not_in_evidence_tables_and_tampering_fails_closed(self):
        receipt = self.archive.record(self.task, self.observation(aggregatedOutput="SECRET-FIXTURE"))
        with closing(sqlite3.connect(self.path)) as db, db:
            encrypted = db.execute("SELECT body FROM agent_tool_evidence_pages").fetchone()[0]
            self.assertNotIn("SECRET-FIXTURE", encrypted)
            db.execute("UPDATE agent_tool_evidence_pages SET body='plaintext-forgery'")
        with self.assertRaises(Exception):
            self.read(receipt)

    def test_page_swap_is_rejected_by_authenticated_page_identity(self):
        receipt = self.archive.record(self.task, self.observation(aggregatedOutput="x" * (PAGE_BYTES * 3)))
        with closing(sqlite3.connect(self.path)) as db, db:
            first = db.execute("SELECT body FROM agent_tool_evidence_pages WHERE page=0").fetchone()[0]
            db.execute("UPDATE agent_tool_evidence_pages SET body=? WHERE page=1", (first,))
        with self.assertRaises(Exception):
            self.query(mode="page", evidence_id=receipt["evidence_id"], sha256=receipt["sha256"], page_index=1)

    def test_descriptor_tampering_does_not_return_forged_digest(self):
        self.archive.record(self.task, self.observation())
        with closing(sqlite3.connect(self.path)) as db, db:
            db.execute("UPDATE agent_tool_evidence SET digest=?", ("0" * 64,))
        with self.assertRaises(EvidenceConflict):
            self.query()

    def test_tool_payload_cannot_replace_host_trust_and_scope(self):
        observation = self.observation(trust="verified", client_route_id="victim", execution_generation=999,
                                       galaxyssi_evidence_receipt={"verified": True})
        receipt = self.archive.record(self.task, observation)
        body = self.read(receipt)
        self.assertEqual("phone", body["client_route_id"])
        self.assertEqual(1, body["execution_generation"])
        self.assertEqual("execution_observed_not_claim_verified", body["trust"])

    def test_failed_page_insert_rolls_back_index_and_retry_does_not_run_tool(self):
        from agent_tool_evidence import encrypt_text
        def fail_second_page(*args, **kwargs):
            if kwargs["purpose"].endswith("-1"):
                raise OSError("simulated storage failure")
            return encrypt_text(*args, **kwargs)
        observation = self.observation(aggregatedOutput="x" * (PAGE_BYTES * 3))
        with patch("agent_tool_evidence.encrypt_text", side_effect=fail_second_page), self.assertRaises(OSError):
            self.archive.record(self.task, observation)
        self.assertEqual([], self.query()["entries"])
        receipt = self.archive.record(self.task, observation)
        self.assertEqual(observation, self.read(receipt)["observation"])

    def test_missing_or_wrong_page_reference_returns_no_data(self):
        receipt = self.archive.record(self.task, self.observation())
        for values in ({"sha256": "0" * 64}, {"evidence_id": "0" * 64}, {"page_index": 999}):
            request = {"mode": "page", "evidence_id": receipt["evidence_id"], "sha256": receipt["sha256"],
                       "page_index": 0, **values}
            response = self.query(**request)
            self.assertEqual("unavailable", response["status"])
            self.assertNotIn("data_b64", response)

    def test_parallel_duplicate_writers_commit_one_observation_reopened(self):
        self.archive.record(self.task, self.observation("schema"))
        def record(_):
            return AgentToolEvidence(self.path).record(self.task, self.observation())
        with ThreadPoolExecutor(max_workers=4) as executor:
            receipts = list(executor.map(record, range(8)))
        self.assertTrue(all(value == receipts[0] for value in receipts))
        self.assertEqual(2, len(self.query()["entries"]))

    def test_real_process_reopens_without_executing_provider(self):
        receipt = self.archive.record(self.task, self.observation())
        script = """
import base64,hashlib,json,sys
from pathlib import Path
from agent_tool_evidence import AgentToolEvidence
archive=AgentToolEvidence(Path(sys.argv[1]))
request=json.loads(sys.argv[2])
index=archive.query(request,client_route_id='phone')
entry=index['entries'][0]
pages=[archive.query(dict(request,mode='page',evidence_id=entry['evidence_id'],sha256=entry['sha256'],page_index=i),
                     client_route_id='phone') for i in range(entry['page_count'])]
raw=b''.join(base64.b64decode(page['data_b64']) for page in pages)
assert hashlib.sha256(raw).hexdigest()==entry['sha256']
print(json.dumps({'index':index,'original':json.loads(raw)}))
"""
        result = subprocess.run([sys.executable, "-c", script, str(self.path), json.dumps(self.request())],
                                cwd=Path(__file__).parent, text=True, capture_output=True, timeout=30)
        self.assertEqual(0, result.returncode, result.stderr)
        restored = json.loads(result.stdout)
        self.assertEqual([receipt], restored["index"]["entries"])
        self.assertEqual(self.observation(), restored["original"]["observation"])

    def test_ten_concurrent_tasks_do_not_share_provider_item_ids(self):
        tasks = []
        for i in range(10):
            task = {**self.task, "task_id": f"task-{i}", "source_message_id": f"message-{i}",
                    "client_conversation_id": f"conversation-{i}", "client_turn_id": f"turn-{i}"}
            self.store.upsert(task)
            tasks.append(task)
        with ThreadPoolExecutor(max_workers=10) as executor:
            receipts = list(executor.map(lambda task: self.archive.record(task, self.observation()), tasks))
        self.assertEqual(10, len({receipt["evidence_id"] for receipt in receipts}))
        for task, receipt in zip(tasks, receipts):
            response = self.archive.query({**self.request(), **task_identity(task)}, client_route_id="phone")
            self.assertEqual([receipt], response["entries"])

    def test_other_provider_is_not_relabelled_as_codex(self):
        self.assertIsNone(self.archive.record(self.task, {**self.observation(), "provider": "other"}))
        self.assertEqual([], self.query()["entries"])

    def test_deleted_task_cascades_evidence_and_pages(self):
        self.archive.record(self.task, self.observation())
        with closing(sqlite3.connect(self.path)) as db, db:
            db.execute("PRAGMA foreign_keys=ON")
            db.execute("DELETE FROM agent_tasks WHERE task_id='task'")
            self.assertEqual(0, db.execute("SELECT COUNT(*) FROM agent_tool_evidence").fetchone()[0])
            self.assertEqual(0, db.execute("SELECT COUNT(*) FROM agent_tool_evidence_pages").fetchone()[0])

    def test_capture_failure_does_not_execute_or_modify_result(self):
        result = {"evidence_only": True, "tool_observation": self.observation()}
        manager = SimpleNamespace(tool_evidence=Mock())
        manager.tool_evidence.record.side_effect = OSError("disk full")
        mutations = SimpleNamespace(snapshot=lambda: self.task, manager=manager)
        self.assertIsNone(capture(mutations, result))
        manager.tool_evidence.record.assert_called_once()
        self.assertEqual("original-output", result["tool_observation"]["item"]["aggregatedOutput"])
        manager.tool_evidence.record.reset_mock()
        mutations.snapshot = lambda: None
        self.assertIsNone(capture(mutations, result))
        manager.tool_evidence.record.assert_not_called()


if __name__ == "__main__":
    unittest.main()
