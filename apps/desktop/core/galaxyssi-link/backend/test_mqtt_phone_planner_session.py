import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import mqtt_bridge
import agent_conversation_sessions
from phone_planner_session import phone_planner_session
from test_mqtt_codex_steering import _ImmediateThread, _SteeringTaskManager, _SteeringCodexServer


class MqttPhonePlannerSessionTests(unittest.TestCase):
    def test_phone_planner_uses_goal_scoped_history_without_steering_active_chat(self):
        temporary = self.enterContext(tempfile.TemporaryDirectory())
        manager, server = _SteeringTaskManager(), _SteeringCodexServer()
        self.enterContext(patch("agent_latency_hooks.trace_stage"))
        self.enterContext(patch.object(mqtt_bridge, "agent_task_manager", manager))
        sessions = agent_conversation_sessions.AgentConversationSessions(Path(temporary) / "sessions.json")
        self.enterContext(patch.object(agent_conversation_sessions, "_sessions", sessions))
        self.enterContext(patch.object(mqtt_bridge, "_codex_server", return_value=server))
        self.enterContext(patch.object(mqtt_bridge, "_enqueue_task_event"))
        self.enterContext(patch.object(mqtt_bridge, "_publish_or_queue_task_result"))
        self.enterContext(patch.object(mqtt_bridge.threading, "Thread", _ImmediateThread))
        self.enterContext(patch("agent_gateway._find_codex_desktop_cli", return_value="codex"))
        self.enterContext(patch("task_workspace.task_workspace", return_value=Path(temporary)))
        for number in (1, 2):
            task = f"phone-step-{number}"
            mqtt_bridge._start_remote_agent_task(
                mqttc=SimpleNamespace(),
                wire_payload={"scheme": "signal", "_client_route_id": "client-1"},
                payload={"type": "text", "content": "Return the next phone ActionPlan",
                    "contact_id": "codex", "agent_id": "codex", "client_message_id": f"message-{number}",
                    "client_route_id": "client-1", "task_id": task, "conversation_id": "conversation-1",
                    "turn_id": "phone-goal", "connector_task_mode": "phone_supervised_project_plan_v1",
                    "attachments": []}, trace=[], content="Return the next phone ActionPlan", msg_type="text")
            with mqtt_bridge.codex_task_callbacks_lock:
                mqtt_bridge.codex_task_callbacks.pop(task, None)
        self.assertEqual([], server.steers)
        self.assertEqual(2, len(server.start_calls))
        expected = phone_planner_session(mode="phone_supervised_project_plan_v1", client_route="client-1",
            conversation=manager.prior.conversation_id, turn="phone-goal", model="gpt-5.6-sol")
        for _, call in server.start_calls:
            self.assertEqual(expected, call["conversation_id"])
            self.assertEqual("read-only", call["sandbox"])
        self.assertEqual("running", manager.prior.status)


if __name__ == "__main__":
    unittest.main()
