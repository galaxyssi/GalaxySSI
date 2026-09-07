import base64
import copy
import hashlib
import json
from contextlib import ExitStack
from pathlib import Path
from types import SimpleNamespace
import tempfile
import threading
import unittest
from unittest.mock import Mock, patch

from agent_task_recovery_query import IDENTITY_FIELDS, INLINE_RESPONSE_BYTES, TASK_FIELDS, recovery_query
from agent_task_result_archive import PAGE_BYTES, TaskResultArchive


def size(value):
    return len(json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))


class InlineRecoveryPageTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.archive = TaskResultArchive(Path(directory.name) / "results.db")
        self.fields = dict(zip(IDENTITY_FIELDS, ("route", "conversation", "task", "turn", "contact", "42", "codex")))
        self.payload = {"request_id": "nonce", "client_route_id": "route", "items": [self.fields],
                        "include_result_page": True}
        self.manager = Mock(spec=["recovery_snapshot"])
        self.task = dict(zip(TASK_FIELDS, self.fields.values())) | {
            "status": "completed", "status_seq": 7, "execution_generation": 2, "run_id": "run"}
        self.manager.recovery_snapshot.return_value = self.task
        self.body = self.fields | {"type": "text", "task_status": "completed", "execution_generation": 2,
                                   "content": "\u6062\u590d\u6d4b\u8bd5\u5b8c\u6210", "status_sequence": 7}
        self.archive.put(self.body)

    def query(self, payload=None, archive=None):
        return recovery_query(self.payload if payload is None else payload, client_route_id="route",
                              manager=self.manager, result_archive=self.archive if archive is None else archive)

    def test_small_reply_recovers_from_exact_archived_page(self):
        result = self.query()
        page = result["items"][0]["result_page"]
        self.assertEqual("nonce", page["request_id"])
        self.assertEqual(0, page["page_index"])
        self.assertEqual(2, page["execution_generation"])
        raw = base64.b64decode(page["data_b64"], validate=True)
        self.assertEqual(self.body, json.loads(raw))
        self.assertEqual(hashlib.sha256(raw).hexdigest(), page["sha256"])
        self.assertEqual(page["sha256"], page["page_sha256"])
        self.assertLessEqual(size(result), INLINE_RESPONSE_BYTES)

    def test_only_explicit_boolean_opt_in_reads_archive(self):
        archive = Mock(spec=["try_page"])
        for value in (None, False, 1, "true", "false", {}, []):
            with self.subTest(value=value):
                result = self.query(self.payload | {"include_result_page": value}, archive)
                self.assertNotIn("result_page", result["items"][0])
        payload = dict(self.payload)
        payload.pop("include_result_page")
        self.query(payload, archive)
        archive.try_page.assert_not_called()

    def test_observation_only_caller_without_reader_still_works(self):
        result = recovery_query(self.payload, client_route_id="route", manager=self.manager)
        self.assertNotIn("result_page", result["items"][0])

    def test_nonterminal_tasks_never_read_bodies(self):
        archive = Mock(spec=["try_page"])
        for status in ("running", "paused", "waiting_input", "interrupted", "recovering", "queued"):
            self.task["status"] = status
            self.assertNotIn("result_page", self.query(archive=archive)["items"][0])
        archive.try_page.assert_not_called()

    def test_terminal_failures_keep_their_canonical_outcomes(self):
        for generation, status in enumerate(("failed", "timed_out", "cancelled"), 3):
            with self.subTest(status=status):
                body = self.body | {"execution_generation": generation, "task_status": status,
                                    "content": "", "terminal_reason": status}
                self.archive.put(body)
                self.task.update(status=status, execution_generation=generation)
                result = self.query()["items"][0]
                self.assertEqual(status, result["status"])
                self.assertEqual(body, json.loads(base64.b64decode(result["result_page"]["data_b64"])))

    def test_new_generation_never_receives_old_archived_body(self):
        self.task["execution_generation"] = 3
        self.assertNotIn("result_page", self.query()["items"][0])

    def test_every_task_scope_mismatch_prevents_archive_access(self):
        archive = Mock(spec=["try_page"])
        for field in TASK_FIELDS:
            original = self.task[field]
            self.task[field] = "other"
            with self.subTest(field=field):
                self.assertEqual("unavailable", self.query(archive=archive)["items"][0]["status"])
            self.task[field] = original
        archive.try_page.assert_not_called()

    def test_invalid_batch_is_rejected_before_any_read(self):
        archive = Mock(spec=["try_page"])
        for payload in (self.payload | {"client_route_id": "other"},
                        self.payload | {"items": [self.fields | {"client_route_id": "other"}]},
                        self.payload | {"items": [self.fields, {}]}):
            self.assertIsNone(self.query(payload, archive))
        archive.try_page.assert_not_called()
        self.manager.recovery_snapshot.assert_not_called()

    def test_missing_or_acknowledged_archive_keeps_status_available(self):
        self.task["task_id"] = "missing"
        result = self.query(self.payload | {"items": [self.fields | {"task_id": "missing"}]})
        self.assertEqual("completed", result["items"][0]["status"])
        self.assertNotIn("result_page", result["items"][0])
        self.task["task_id"] = "task"
        digest = self.query()["items"][0]["result_page"]["sha256"]
        self.assertTrue(self.archive.acknowledge(self.fields | {"sha256": digest, "execution_generation": 2},
                                               client_route_id="route"))
        self.assertNotIn("result_page", self.query()["items"][0])

    def test_large_body_returns_first_page_and_keeps_normal_remaining_pages(self):
        body = self.body | {"execution_generation": 3, "content": "\u4e2d\u6587" * 20000}
        self.archive.put(body)
        self.task["execution_generation"] = 3
        first = self.query()["items"][0]["result_page"]
        chunks = [base64.b64decode(first["data_b64"])]
        self.assertEqual(PAGE_BYTES, len(chunks[0]))
        self.assertGreater(first["page_count"], 1)
        for index in range(1, first["page_count"]):
            page = self.archive.page(self.fields | {"request_id": "page-nonce", "execution_generation": 3,
                "page_index": index, "sha256": first["sha256"]}, client_route_id="route")
            chunks.append(base64.b64decode(page["data_b64"]))
        self.assertEqual(body, json.loads(b"".join(chunks)))

    def test_batch_budget_is_aggregate_and_preserves_all_observations(self):
        items, tasks = [], {}
        for index in range(10):
            fields = self.fields | {"task_id": f"task-{index}"}
            items.append(fields)
            tasks[fields["task_id"]] = self.task | {"task_id": fields["task_id"]}
            self.archive.put(self.body | fields | {"content": "x" * 30000})
        self.manager.recovery_snapshot.side_effect = lambda task_id, **_: tasks[task_id]
        response = self.query(self.payload | {"items": items})
        self.assertEqual(10, len(response["items"]))
        self.assertEqual(1, sum("result_page" in item for item in response["items"]))
        self.assertTrue(all(item["status"] == "completed" for item in response["items"]))
        self.assertLessEqual(size(response), INLINE_RESPONSE_BYTES)

    def test_exact_utf8_budget_boundary(self):
        self.task["run_id"] = "\u4e2d" * 200
        with_page = self.query()
        exact = size(with_page)
        with patch("agent_task_recovery_query.INLINE_RESPONSE_BYTES", exact):
            self.assertEqual(with_page, self.query())
        with patch("agent_task_recovery_query.INLINE_RESPONSE_BYTES", exact - 1):
            self.assertNotIn("result_page", self.query()["items"][0])

    def test_large_metadata_does_not_trigger_archive_reads(self):
        self.task["run_id"] = "\u4e2d" * 1000
        archive = Mock(spec=["try_page"])
        response = self.query(self.payload | {"items": [self.fields] * 32}, archive)
        self.assertGreater(size(response), INLINE_RESPONSE_BYTES)
        self.assertEqual(32, len(response["items"]))
        archive.try_page.assert_not_called()

    def test_reader_failure_does_not_hide_status_or_log_private_exception(self):
        archive = Mock(spec=["try_page"])
        archive.try_page.side_effect = RuntimeError("private filesystem and answer")
        with self.assertLogs("agent_task_recovery_query", "WARNING") as logs:
            result = self.query(archive=archive)
        self.assertEqual("completed", result["items"][0]["status"])
        self.assertNotIn("result_page", result["items"][0])
        self.assertNotIn("private", "".join(logs.output))

    def test_reader_cannot_attach_a_page_with_other_identity_nonce_or_generation(self):
        page = self.query()["items"][0]["result_page"]
        archive = Mock(spec=["try_page"])
        for field, value in [(field, "other") for field in IDENTITY_FIELDS + ("request_id", "type")] + [
                ("execution_generation", 1), ("execution_generation", True), ("page_index", 1),
                ("page_index", False), ("status", "unavailable")]:
            with self.subTest(field=field, value=value):
                archive.try_page.return_value = page | {field: value}
                self.assertNotIn("result_page", self.query(archive=archive)["items"][0])

    def test_oversized_page_keeps_metadata_and_does_not_modify_request(self):
        original = copy.deepcopy(self.payload)
        archive = Mock(spec=["try_page"])
        archive.try_page.return_value = self.query()["items"][0]["result_page"] | {"data_b64": "a" * 100000}
        self.assertNotIn("result_page", self.query(archive=archive)["items"][0])
        self.assertEqual(original, self.payload)

    def test_archive_stays_encrypted_and_read_does_not_acknowledge_it(self):
        first = self.query()["items"][0]["result_page"]
        second = self.query()["items"][0]["result_page"]
        self.assertEqual(first, second)
        self.assertNotIn(self.body["content"].encode("utf-8"), self.archive.path.read_bytes())

    def test_invalid_utf8_metadata_does_not_invoke_optional_reader(self):
        self.task["run_id"] = "\ud800"
        archive = Mock(spec=["try_page"])
        self.assertEqual("completed", self.query(archive=archive)["items"][0]["status"])
        archive.try_page.assert_not_called()

    def test_optional_read_does_not_initialize_missing_archive(self):
        archive = TaskResultArchive(self.archive.path.parent / "missing.db")
        self.assertNotIn("result_page", self.query(archive=archive)["items"][0])
        self.assertFalse(archive.path.exists())

    def test_busy_archive_does_not_block_query_and_later_reads_still_work(self):
        from agent_task_result_archive import _lock

        locked, release = threading.Event(), threading.Event()
        def writer():
            with _lock:
                locked.set()
                release.wait(5)
        owner = threading.Thread(target=writer)
        owner.start()
        try:
            self.assertTrue(locked.wait(2))
            result = self.query()
            self.assertFalse(release.is_set())
            self.assertNotIn("result_page", result["items"][0])
            self.assertEqual("completed", result["items"][0]["status"])
        finally:
            release.set()
            owner.join(2)
        self.assertFalse(owner.is_alive())
        self.assertIn("result_page", self.query()["items"][0])

    def test_try_page_releases_lock_after_archive_failure(self):
        from agent_task_result_archive import _lock

        with patch.object(self.archive, "page", side_effect=OSError("disk unavailable")):
            with self.assertRaises(OSError):
                self.archive.try_page({}, client_route_id="route")
        acquired = threading.Event()
        def reader():
            if _lock.acquire(blocking=False):
                acquired.set()
                _lock.release()
        worker = threading.Thread(target=reader)
        worker.start(); worker.join(2)
        self.assertTrue(acquired.is_set())

    def test_mqtt_dispatch_uses_archive_and_never_reexecutes(self):
        import agent_task_result_archive
        import link_protocol
        import mqtt_bridge

        client = {"client_route_id": "route", "signal_name": "phone", "link_secret": "A" * 43}
        wire = json.dumps({"scheme": "signal", "from": "phone", "to": "desktop", "body": "ciphertext"}).encode()
        envelope = link_protocol.make_envelope(self.payload | {"type": "agent_task_recovery_request"},
            source_id="phone", target_id="desktop", conversation_id="conversation")
        with ExitStack() as stack:
            for name, value in {"_resolve_inbound_topic": ("client", client), "desktop_id": "desktop",
                    "get_client": client, "message_for_ciphertext": "", "open_wire_packet": wire,
                    "decrypt_signal_envelope": envelope, "bind_ciphertext": None, "claim_message": True,
                    "touch_client": None, "complete_message": None}.items():
                stack.enter_context(patch.object(mqtt_bridge, name, return_value=value))
            stack.enter_context(patch.object(mqtt_bridge, "agent_task_manager", self.manager))
            stack.enter_context(patch.object(agent_task_result_archive, "archive", self.archive))
            publish = stack.enter_context(patch.object(mqtt_bridge, "_publish_phone_payload", return_value=True))
            execute = stack.enter_context(patch.object(mqtt_bridge, "_start_remote_agent_task"))
            mqtt_bridge._process_message(SimpleNamespace(), None, SimpleNamespace(topic="mailbox", payload=b"wire"))
            replies = [call.args[2] for call in publish.call_args_list
                       if call.args[2].get("type") == "agent_task_recovery_result"]
        execute.assert_not_called()
        self.assertEqual(1, len(replies))
        self.assertIn("result_page", replies[0]["items"][0])


if __name__ == "__main__":
    unittest.main()
