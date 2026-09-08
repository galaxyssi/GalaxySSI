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
