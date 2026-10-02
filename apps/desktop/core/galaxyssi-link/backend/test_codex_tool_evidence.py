from contextlib import ExitStack
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from agent_tool_evidence import completed_tool_observation
from codex_app_server import CodexAppServer, CodexRun


class CodexToolEvidenceTest(unittest.TestCase):
    def test_completed_operation_precedes_visible_progress_without_reasoning(self):
        events = []
        server = CodexAppServer("codex", {}, lambda task, event: events.append(event))
        run = CodexRun(task_id="task", thread_id="thread", turn_id="turn")
        server._runs["task"], server._turn_tasks["turn"] = run, "task"
        item = {"id": "command", "type": "commandExecution", "command": "echo fixture",
                "aggregatedOutput": "full" * 6000, "exitCode": 0}
        server._handle_event({"method": "item/started", "params": {"turnId": "turn", "item": item}})
        self.assertFalse(any(event.get("evidence_only") for event in events))
        events.clear()
        server._handle_event({"method": "item/completed", "params": {"turnId": "turn", "item": item}})
        self.assertTrue(events[0]["evidence_only"])
        self.assertEqual(item, events[0]["tool_observation"]["item"])
        self.assertNotIn("aggregatedOutput", events[-1])
        for kind in ("reasoning", "agentMessage", "plan", "imageGeneration", "unknown"):
            self.assertIsNone(completed_tool_observation({"id": "id", "type": kind, "text": "private"},
                                                         thread_id="thread", turn_id="turn"))

    def test_wrong_provider_turn_does_not_create_observation(self):
        events = []
        server = CodexAppServer("codex", {}, lambda task, event: events.append(event))
        server._runs["task"] = CodexRun(task_id="task", thread_id="thread", turn_id="new-turn")
        server._turn_tasks["old-turn"] = "task"
        server._handle_event({"method": "item/completed", "params": {"turnId": "old-turn", "item": {
            "id": "command", "type": "commandExecution", "aggregatedOutput": "stale"}}})
        self.assertEqual([], events)

    def test_supported_tool_items_are_detached_and_malformed_events_are_ignored(self):
        for kind in ("commandExecution", "fileChange", "mcpToolCall", "dynamicToolCall", "webSearch"):
            item = {"id": "item", "type": kind, "result": {"text": "original"}}
            observation = completed_tool_observation(item, thread_id="thread", turn_id="turn")
            item["result"]["text"] = "changed"
            self.assertEqual("original", observation["item"]["result"]["text"])
        for item in ({"type": "webSearch"}, {"id": 1, "type": "webSearch"},
                     {"id": "item", "type": "webSearch", "duration": float("nan")}, {"type": {}}, []):
            self.assertIsNone(completed_tool_observation(item, thread_id="thread", turn_id="turn"))

    def test_mqtt_evidence_query_is_read_only_and_uses_authenticated_route(self):
        import mqtt_bridge
        from agent_task_store import AgentTaskStore
        from agent_tool_evidence import AgentToolEvidence, task_identity
        from signal_receive_dispatch import retry_safe
        with tempfile.TemporaryDirectory() as directory, ExitStack() as stack:
            path = Path(directory) / "run.db"
            store = AgentTaskStore(path)
            task = dict(task_id="task", client_route_id="phone", client_conversation_id="conversation",
                        client_turn_id="turn", source_message_id="42", contact_id="codex", agent_id="codex",
                        status="running", execution_generation=1)
            store.upsert(task)
            evidence = AgentToolEvidence(path)
            receipt = evidence.record(task, completed_tool_observation(
                {"id": "command", "type": "commandExecution", "exitCode": 0}, thread_id="thread", turn_id="turn"))
            stack.enter_context(patch.object(mqtt_bridge, "agent_task_manager", SimpleNamespace(tool_evidence=evidence)))
            publish = stack.enter_context(patch.object(mqtt_bridge, "_publish_phone_payload"))
            # Earlier unrelated payload routers must not launch any provider for this read-only request.
            for name in ("_route_phone_tool_payload", "_route_desktop_tool_payload", "_route_desktop_control_payload",
                         "_route_peer_message_payload", "_route_evolution_payload", "_route_remote_whisper_payload",
                         "_route_unified_command_payload"):
                stack.enter_context(patch.object(mqtt_bridge, name, return_value=False))
            start = stack.enter_context(patch.object(mqtt_bridge, "_start_remote_agent_task"))
            request = {**task_identity(task), "type": "agent_task_evidence_request", "execution_generation": 1,
                       "request_id": "nonce"}
            self.assertTrue(retry_safe({"payload": request}))
            mqtt_bridge._dispatch_application_payload(None, {"client_route_id": "phone"},
                {"_client_route_id": "phone"}, {"source_id": "phone"}, request, [])
            self.assertEqual([receipt], publish.call_args.args[2]["entries"])
            publish.reset_mock()
            mqtt_bridge._dispatch_application_payload(None, {"client_route_id": "other-phone"},
                {"_client_route_id": "other-phone"}, {"source_id": "other-phone"}, request, [])
            publish.assert_not_called()
            start.assert_not_called()


if __name__ == "__main__":
    unittest.main()
