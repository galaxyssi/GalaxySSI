import os
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import Mock, patch

import codex_app_server as codex


class CodexProxyRefreshTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        state = patch.dict(os.environ, {"GALAXYSSI_STATE_DIR": self.directory.name,
                                       "GALAXYSSI_WORKSPACE_ROOT": self.directory.name})
        state.start()
        self.addCleanup(state.stop)
        paths = patch.object(codex, "CONVERSATION_THREADS_PATH", Path(self.directory.name) / "threads.json")
        paths.start()
        self.addCleanup(paths.stop)
        self.proxy = {"HTTPS_PROXY": "http://user:secret@127.0.0.1:7897",
                      "NO_PROXY": "localhost", "GALAXYSSI_CODEX_PROXY_SOURCE": "system"}
        self.direct = {"GALAXYSSI_CODEX_PROXY_SOURCE": "direct"}
        self.server = codex.CodexAppServer("codex", {**self.proxy, "KEEP": "value"}, lambda *_: None)

    def apply(self):
        with self.server._process_start_lock:
            self.server._refresh_idle_proxy()

    def test_idle_change_clears_stale_proxy_and_preserves_conversations(self):
        server = self.server
        server._conversation_threads[server._conversation_key("conversation")] = "thread"
        server._loaded_thread_ids.add("thread")
        process = Mock()
        process.poll.return_value = None
        server.process = process
        server.refresh_proxy_environment(self.direct)
        with self.assertLogs(codex.log, level="INFO") as logs:
            self.apply()
        process.terminate.assert_called_once()
        self.assertIsNone(server.process)
        self.assertNotIn("HTTPS_PROXY", server.env)
        self.assertNotIn("NO_PROXY", server.env)
        self.assertEqual("value", server.env["KEEP"])
        self.assertEqual("thread", server._conversation_threads[server._conversation_key("conversation")])
        self.assertFalse(server._loaded_thread_ids)
        self.assertNotIn("secret", str(logs.output))
        self.assertNotIn("7897", str(logs.output))

    def test_active_turn_defers_rotation_until_finished(self):
        run = codex.CodexRun("active")
        self.server._runs[run.task_id] = run
        self.server.refresh_proxy_environment(self.direct)
        with patch.object(self.server, "_close_process") as close:
            self.apply()
            close.assert_not_called()
            self.assertIn("HTTPS_PROXY", self.server.env)
            run.finished = True
            self.apply()
            close.assert_called_once()
        self.assertNotIn("HTTPS_PROXY", self.server.env)

    def test_pending_rpc_defers_rotation(self):
        self.server._pending[1] = Mock()
        self.server.refresh_proxy_environment(self.direct)
        with patch.object(self.server, "_close_process") as close:
            self.apply()
            close.assert_not_called()
            self.server._pending.clear()
            self.apply()
            close.assert_called_once()

    def test_prewarm_defers_refresh_without_blocking_loaded_turns(self):
        server = self.server
        server._conversation_threads[server._conversation_key("cold")] = "cold-thread"
        entered, release = threading.Event(), threading.Event()

        def resume(*args, **kwargs):
            entered.set()
            release.wait(3)

        with patch.object(server, "_ensure_started"), patch.object(server, "_resume_thread", side_effect=resume), \
                patch.object(server, "_close_process") as close:
            with ThreadPoolExecutor(max_workers=1) as pool:
                future = pool.submit(server.prewarm_recent_threads)
                try:
                    self.assertTrue(entered.wait(2))
                    self.assertTrue(server._process_start_lock.acquire(timeout=0.2))
                    server._process_start_lock.release()
                    server.refresh_proxy_environment(self.direct)
                    self.apply()
                    close.assert_not_called()
                finally:
                    release.set()
                future.result(timeout=3)
            self.apply()
            close.assert_called_once()

    def test_latest_settings_win_and_unchanged_proxy_does_not_restart(self):
        self.server.refresh_proxy_environment(self.direct)
        self.server.refresh_proxy_environment(self.proxy)
        with patch.object(self.server, "_close_process") as close:
            self.apply()
            close.assert_not_called()
        self.assertIsNone(self.server._desired_proxy_env)

    def test_enabling_proxy_and_changing_bypass_refreshes(self):
        for settings in (self.direct, self.proxy, {**self.proxy, "NO_PROXY": "other.example"}):
            self.server.refresh_proxy_environment(settings)
            with patch.object(self.server, "_close_process") as close:
                self.apply()
                close.assert_called_once()
            for key, value in settings.items():
                self.assertEqual(value, self.server.env[key])

    def test_experiment_environment_cannot_be_changed(self):
        self.server._experiment_boundary = Mock()
        self.server.refresh_proxy_environment(self.direct)
        self.assertIsNone(self.server._desired_proxy_env)
        self.assertIn("HTTPS_PROXY", self.server.env)

    def test_ready_process_still_checks_pending_refresh(self):
        process = Mock(pid=123)
        process.poll.return_value = None
        self.server.process = process
        self.server._initialized_process_pid = 123
        with patch.object(self.server, "_refresh_idle_proxy") as refresh:
            self.server._ensure_started()
        refresh.assert_called_once()

    def test_factory_refreshes_existing_server_without_replacing_callbacks(self):
        import mqtt_bridge
        with patch.object(mqtt_bridge, "codex_app_server", self.server):
            self.assertIs(self.server, mqtt_bridge._codex_server("codex", self.direct))
        self.assertEqual(self.direct, self.server._desired_proxy_env)

    def test_startup_and_active_reservation_are_atomic_with_refresh(self):
        entered, release = threading.Event(), threading.Event()
        server = self.server

        def started():
            self.assertTrue(server._process_start_lock._is_owned())
            entered.set()
            release.wait(3)

        def refresh():
            server.refresh_proxy_environment(self.direct)
            self.apply()

        with patch.object(server, "_ensure_started", side_effect=started), \
                patch.object(server, "_start_thread_with_retry", return_value="thread"), \
                patch.object(server, "_start_turn_confirmed", return_value={"turn": {"id": "turn"}}), \
                patch.object(server, "_watch_run"), patch.object(server, "_close_process") as close:
            with ThreadPoolExecutor(max_workers=2) as pool:
                future = pool.submit(server.start_task, "task", "hello", self.directory.name)
                self.assertTrue(entered.wait(2))
                change = pool.submit(refresh)
                release.set()
                run = future.result(timeout=3)
                change.result(timeout=3)
            self.assertFalse(run.finished)
            close.assert_not_called()
        self.assertIn("HTTPS_PROXY", server.env)


if __name__ == "__main__":
    unittest.main()
