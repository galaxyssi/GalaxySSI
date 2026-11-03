import json
import os
import queue
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import codex_app_server as codex


class CodexStartupConcurrencyTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.env = patch.dict(os.environ, {
            "GALAXYSSI_STATE_DIR": self.directory.name,
            "GALAXYSSI_WORKSPACE_ROOT": self.directory.name,
        })
        self.env.start()
        self.path = patch.object(codex, "CONVERSATION_THREADS_PATH", Path(self.directory.name) / "threads.json")
        self.path.start()

    def tearDown(self):
        self.path.stop()
        self.env.stop()
        self.directory.cleanup()

    def test_slow_notification_does_not_block_ten_rpc_replies(self):
        server = codex.CodexAppServer("codex", {}, lambda *_: None)
        lines = queue.Queue()
        entered, release, handled = threading.Event(), threading.Event(), threading.Event()
        observed = []
        written = []
        write_lock = threading.Lock()
        server.process = SimpleNamespace(stdout=iter(lines.get, None))

        def event(message):
            entered.set()
            release.wait(5)
            observed.append(message["params"]["sequence"])
            if len(observed) == 10:
                handled.set()

        def write(message):
            with write_lock:
                written.append(message["id"])
                lines.put(json.dumps({"method": "progress", "params": {"sequence": message["id"]}}))
                lines.put(json.dumps({"id": message["id"], "result": {"request": message["id"]}}))

        server._handle_event = event
        server._write = write
        reader = threading.Thread(target=server._read_stdout)
        reader.start()
        try:
            with ThreadPoolExecutor(max_workers=10) as pool:
                futures = [pool.submit(server._request, "turn/start", {}, 2) for _ in range(10)]
                self.assertTrue(entered.wait(1))
                replies = [future.result(timeout=3) for future in futures]
            self.assertEqual(10, len({reply["request"] for reply in replies}))
            self.assertFalse(release.is_set())
            release.set()
            self.assertTrue(handled.wait(2))
            self.assertEqual(written, observed)
            self.assertEqual({}, server._pending)
        finally:
            release.set()
            lines.put(None)
            reader.join(3)
            server.process = None
        self.assertFalse(reader.is_alive())

    def test_startup_reserves_conversation_without_holding_global_lock(self):
        server = codex.CodexAppServer("codex", {}, lambda *_: None)
        entered, release = threading.Event(), threading.Event()

        def start(*args, **kwargs):
            self.assertTrue(server._thread_lifecycle_lock._is_owned())
            entered.set()
            release.wait(3)
            return "thread"

        with patch.object(server, "_ensure_started"), patch.object(server, "_start_thread_with_retry", side_effect=start), \
                patch.object(server, "_start_turn_confirmed", return_value={"turn": {"id": "turn"}}), \
                patch.object(server, "_watch_run"), patch.object(server, "_begin_host_config_guard", return_value=None):
            with ThreadPoolExecutor(max_workers=1) as pool:
                future = pool.submit(server.start_task, "task", "hello", self.directory.name, conversation_id="same")
                try:
                    self.assertTrue(entered.wait(1))
                    acquired = server._lock.acquire(timeout=0.3)
                    self.assertTrue(acquired, "RPC wait must not hold the shared state lock")
                    if acquired:
                        server._lock.release()
                    with self.assertRaises(codex.CodexConversationBusyError):
                        server.start_task("duplicate", "hello", self.directory.name, conversation_id="same")
                finally:
                    release.set()
                self.assertEqual("thread", future.result(timeout=2).thread_id)

    def test_slow_callback_batches_queued_text_before_terminal_notification(self):
        server = codex.CodexAppServer("codex", {}, lambda *_: None)
        lines = queue.Queue()
        entered, release, terminal = threading.Event(), threading.Event(), threading.Event()
        observed = []
        server.process = SimpleNamespace(stdout=iter(lines.get, None))
        reply = queue.Queue()
        server._pending[123] = reply

        def handle(message):
            if message["method"] == "turn/started":
                entered.set()
                release.wait(5)
            observed.append(message)
            if message["method"] == "turn/completed":
                terminal.set()

        server._handle_event = handle
        reader = threading.Thread(target=server._read_stdout)
        reader.start()
        try:
            lines.put(json.dumps({"method": "turn/started", "params": {}}))
            self.assertTrue(entered.wait(2))
            for _ in range(1024):
                lines.put(json.dumps({"method": "item/agentMessage/delta", "params": {
                    "threadId": "thread", "turnId": "turn", "itemId": "item", "delta": "text"}}))
            lines.put(json.dumps({"method": "turn/completed", "params": {"turn": {"id": "turn"}}}))
            lines.put(json.dumps({"id": 123, "result": {"ready": True}}))
            self.assertEqual({"id": 123, "result": {"ready": True}}, reply.get(timeout=3))
            self.assertFalse(release.is_set(), "RPC reader must not wait for the event callback")
            release.set()
            self.assertTrue(terminal.wait(2))
            self.assertEqual(["turn/started", "item/agentMessage/delta", "turn/completed"],
                             [message["method"] for message in observed])
            self.assertEqual("text" * 1024, observed[1]["params"]["delta"])
        finally:
            release.set()
            lines.put(None)
            reader.join(3)
            server.process = None
        self.assertFalse(reader.is_alive())

    def test_resume_does_not_hold_global_lock(self):
        server = codex.CodexAppServer("codex", {}, lambda *_: None)
        server._conversation_threads[server._conversation_key("same")] = "existing"

        def resume(*args, **kwargs):
            with ThreadPoolExecutor(max_workers=1) as pool:
                def acquire():
                    acquired = server._lock.acquire(timeout=0.3)
                    if acquired:
                        server._lock.release()
                    return acquired
                self.assertTrue(pool.submit(acquire).result(timeout=1))

        with patch.object(server, "_ensure_started"), patch.object(server, "_resume_thread", side_effect=resume), \
                patch.object(server, "_start_turn_confirmed", return_value={"turn": {"id": "turn"}}), \
                patch.object(server, "_watch_run"), patch.object(server, "_begin_host_config_guard", return_value=None):
            self.assertEqual("existing", server.start_task("task", "hello", self.directory.name, conversation_id="same").thread_id)

    def test_loaded_turn_does_not_wait_for_unrelated_lifecycle_rpc(self):
        server = codex.CodexAppServer("codex", {}, lambda *_: None)
        server._conversation_threads[server._conversation_key("same")] = "existing"
        server._mark_thread_loaded_locked("existing")
        entered, release = threading.Event(), threading.Event()

        def unrelated_lifecycle():
            with server._thread_lifecycle_lock:
                entered.set()
                release.wait(5)

        worker = threading.Thread(target=unrelated_lifecycle)
        worker.start()
        try:
            self.assertTrue(entered.wait(2))
            with patch.object(server, "_ensure_started"), \
                    patch.object(server, "_request", return_value={"turn": {"id": "turn"}}) as rpc, \
                    patch.object(server, "_watch_run"), \
                    patch.object(server, "_begin_host_config_guard", return_value=None):
                with ThreadPoolExecutor(max_workers=1) as pool:
                    future = pool.submit(server.start_task, "task", "unchanged prompt", self.directory.name,
                                         model="selected-model", conversation_id="same")
                    try:
                        run = future.result(timeout=2)
                        self.assertFalse(release.is_set())
                        self.assertEqual("existing", run.thread_id)
                        self.assertEqual(["turn/start"], [call.args[0] for call in rpc.call_args_list])
                        self.assertEqual("selected-model", rpc.call_args.args[1]["model"])
                        self.assertEqual(run.execution_policy.reasoning_effort.value, rpc.call_args.args[1]["effort"])
                        self.assertIn("unchanged prompt", rpc.call_args.args[1]["input"][0]["text"])
                    finally:
                        release.set()
        finally:
            release.set()
            worker.join(2)
        self.assertFalse(worker.is_alive())

    def test_eviction_fences_loaded_marker_before_unsubscribe_rpc(self):
        server = codex.CodexAppServer("codex", {}, lambda *_: None)
        server._mark_thread_loaded_locked("old")

        def unsubscribe(method, params, timeout):
            self.assertEqual("thread/unsubscribe", method)
            self.assertEqual("old", params["threadId"])
            self.assertNotIn("old", server._loaded_thread_ids)
            self.assertNotIn("old", server._loaded_thread_recency)

        with patch.object(codex, "MAX_LOADED_CODEX_THREADS", 1), \
                patch.object(server, "_request", side_effect=unsubscribe):
            with server._thread_lifecycle_lock:
                server._make_loaded_thread_room()

    def test_active_warm_reservation_is_not_evicted(self):
        server = codex.CodexAppServer("codex", {}, lambda *_: None)
        server._conversation_threads[server._conversation_key("same")] = "existing"
        server._mark_thread_loaded_locked("existing")

        def submit(*args, **kwargs):
            with patch.object(codex, "MAX_LOADED_CODEX_THREADS", 1), \
                    patch.object(server, "_request") as rpc:
                with server._thread_lifecycle_lock:
                    server._make_loaded_thread_room()
                rpc.assert_not_called()
                self.assertIn("existing", server._loaded_thread_ids)
            return {"turn": {"id": "turn"}}

        with patch.object(server, "_ensure_started"), \
                patch.object(server, "_start_turn_confirmed", side_effect=submit), \
                patch.object(server, "_watch_run"), \
                patch.object(server, "_begin_host_config_guard", return_value=None):
            server.start_task("task", "hello", self.directory.name, conversation_id="same")

    def test_rpc_timing_separates_write_from_ack_wait_without_content(self):
        server = codex.CodexAppServer("codex", {}, lambda *_: None)

        def write(message):
            server._pending[message["id"]].put({"result": {"private-output": "not logged"}})

        with patch.object(server, "_write", side_effect=write), \
                patch.object(codex.time, "perf_counter", side_effect=[1.0, 1.25, 3.0]), \
                patch.object(codex.log, "info") as log:
            server._request("turn/start", {"private-prompt": "not logged"}, 1)
        self.assertEqual(("turn/start", "completed", 250.0, 1750.0), log.call_args.args[1:])
        self.assertNotIn("private", str(log.call_args))

    def test_dispatcher_continues_after_handler_error(self):
        server = codex.CodexAppServer("codex", {}, lambda *_: None)
        done = threading.Event()
        server.process = SimpleNamespace(stdout=iter([
            json.dumps({"method": "bad"}), json.dumps({"method": "good"}),
        ]))

        def event(message):
            if message["method"] == "bad":
                raise ValueError("injected")
            done.set()

        server._handle_event = event
        server._read_stdout()
        self.assertTrue(done.wait(2))
        server.process = None

    def test_write_failure_cleans_pending_request(self):
        server = codex.CodexAppServer("codex", {}, lambda *_: None)
        with patch.object(server, "_write", side_effect=BrokenPipeError("injected")):
            with self.assertRaises(BrokenPipeError):
                server._request("turn/start", {}, 1)
        self.assertEqual({}, server._pending)

    def test_dispatch_timing_logs_identity_not_message_content(self):
        server = codex.CodexAppServer("codex", {}, lambda *_: None)
        logged = threading.Event()
        calls = []
        server.process = SimpleNamespace(stdout=iter([json.dumps({
            "method": "turn/completed", "params": {"threadId": "thread", "turn": {
                "id": "turn", "status": "completed", "items": [{"text": "PRIVATE_CONTENT"}]}}})]))
        server._handle_event = lambda _: None

        def record(*args):
            calls.append(args)
            logged.set()

        with patch.object(codex.log, "info", side_effect=record):
            server._read_stdout()
            self.assertTrue(logged.wait(2))
        server.process = None
        self.assertEqual(1, len(calls))
        self.assertNotIn("PRIVATE_CONTENT", str(calls))
        self.assertEqual(("turn/completed", "thread", "turn"), calls[0][1:4])
        self.assertGreaterEqual(calls[0][4], 0)
        self.assertGreaterEqual(calls[0][5], 0)
