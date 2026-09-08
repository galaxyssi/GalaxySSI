import gc
import os
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch

from agent_conversation_sessions import AgentConversationSessions
from codex_app_server import CodexAppServer, CodexRun


class MultitaskIsolationTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.environment = patch.dict(os.environ, {
            "GALAXYSSI_STATE_DIR": str(Path(self.temporary.name) / "state"),
            "GALAXYSSI_WORKSPACE_ROOT": str(Path(self.temporary.name) / "work"),
        })
        self.environment.start()

    def tearDown(self):
        self.environment.stop()
        self.temporary.cleanup()

    def server(self):
        events = []
        server = CodexAppServer("codex", {}, lambda task, event: events.append((task, event)))
        run = CodexRun(task_id="current", thread_id="thread", turn_id="turn-current")
        server._runs[run.task_id] = run
        server._turn_tasks[run.turn_id] = run.task_id
        return server, run, events

    def test_old_turn_delta_cannot_enter_current_task(self):
        server, run, events = self.server()
        server._handle_event({"method": "item/agentMessage/delta", "params": {
            "threadId": "thread", "turnId": "turn-old", "itemId": "old", "delta": "STALE"}})
        self.assertEqual({}, run.agent_message_deltas)
        self.assertEqual([], events)

    def test_valid_turn_with_wrong_thread_is_rejected(self):
        server, run, events = self.server()
        server._handle_event({"method": "item/agentMessage/delta", "params": {
            "threadId": "another-app-thread", "turnId": run.turn_id, "delta": "WRONG"}})
        self.assertEqual({}, run.agent_message_deltas)
        self.assertEqual([], events)

    def test_ambiguous_thread_without_turn_does_not_choose_latest_task(self):
        server, run, events = self.server()
        server._runs["second"] = CodexRun(task_id="second", thread_id="thread", turn_id="turn-second")
        server._handle_event({"method": "item/agentMessage/delta", "params": {
            "threadId": "thread", "delta": "AMBIGUOUS"}})
        self.assertEqual({}, run.agent_message_deltas)
        self.assertEqual({}, server._runs["second"].agent_message_deltas)
        self.assertEqual([], events)

    def test_turn_started_can_bind_unique_pending_run(self):
        server, run, events = self.server()
        server._turn_tasks.clear()
        run.turn_id = ""
        with patch.object(server, "_checkpoint_progress"):
            server._handle_event({"method": "turn/started", "params": {
                "threadId": "thread", "turnId": "new-turn"}})
        self.assertEqual("new-turn", run.turn_id)
        self.assertEqual(run.task_id, server._turn_tasks["new-turn"])
        self.assertTrue(run.turn_started_event.is_set())

    def test_delete_does_not_replace_held_conversation_lock(self):
        with tempfile.TemporaryDirectory() as directory:
            sessions = AgentConversationSessions(Path(directory) / "sessions.json")
            sessions.ensure("codex", "conversation")
            held = sessions.conversation_lock("codex", "conversation")
            with held:
                sessions.delete("codex", "conversation")
                self.assertIs(held, sessions.conversation_lock("codex", "conversation"))
                sessions.ensure("codex", "conversation")
                sessions.delete_conversation("conversation")
                self.assertIs(held, sessions.conversation_lock("codex", "conversation"))

    def test_concurrent_ensure_has_one_binding_and_idle_locks_are_reclaimed(self):
        with tempfile.TemporaryDirectory() as directory:
            sessions = AgentConversationSessions(Path(directory) / "sessions.json")
            with ThreadPoolExecutor(max_workers=10) as pool:
                bindings = list(pool.map(lambda _: sessions.ensure("codex", "conversation").session_id, range(100)))
            self.assertEqual(1, len(set(bindings)))
            for i in range(10000):
                with sessions.conversation_lock("codex", f"conversation-{i}"):
                    pass
            gc.collect()
            self.assertEqual(0, len(sessions._conversation_locks))
