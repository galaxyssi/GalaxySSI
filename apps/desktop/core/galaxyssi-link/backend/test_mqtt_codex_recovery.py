import tempfile
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

import mqtt_bridge


class _ImmediateThread:
    def __init__(self, target=None, args=(), kwargs=None, **_options):
        self.target = target
        self.args = args
        self.kwargs = kwargs or {}

    def start(self):
        if self.target is not None:
            self.target(*self.args, **self.kwargs)


class _RecoveredTaskManager:
    def __init__(self):
        now = int(time.time() * 1000)
        self.task = SimpleNamespace(
            task_id="task-recovered",
            agent_id="codex",
            contact_id="codex",
            source_message_id="message-1",
            prompt="continue",
            conversation_id="conversation-1",
            client_conversation_id="conversation-1",
            client_route_id="client-1",
            client_turn_id="phone-turn-recovered",
            thread_id="thread-original",
            turn_id="turn-original",
            created_at=now - 55_000,
            started_at=now - 45_000,
            status="recovering",
            execution_generation=2,
            pause_requested=False,
            cancel_requested=False,
            result="",
        )
        self.updates = []
        self.recovery_registration = None

    def get(self, task_id):
        if task_id != self.task.task_id:
            return None
        self.task.matches_client_identity = lambda **identity: (
            identity["client_route_id"] == self.task.client_route_id
            and identity["conversation_id"] == self.task.conversation_id
            and identity["task_id"] == self.task.task_id
            and identity["turn_id"] == self.task.client_turn_id
        )
        return self.task

    def resume_external(self, task_id, _on_event):
        if task_id != self.task.task_id:
            return None
        return self.task

    def is_current_execution(self, key):
        from agent_task_manager import AgentTaskManager
        return key == AgentTaskManager._execution_key(self.task, self.task.execution_generation)

    def execution_snapshot(self, key):
        return dict(vars(self.task)) if self.is_current_execution(key) else None

    def schedule_external(self, task_id, starter, on_event, *, interactive=False):
        self.update(task_id, "queued", on_event)
        starter()

    def update(self, task_id, status, on_event=None, **values):
        self.updates.append((task_id, status, values))
        self.task.status = status
        for name, value in values.items():
            if value is not None:
                setattr(self.task, name, value)
        return self.task

    def register_external_recovery(
        self,
        task_id,
        recover,
        *,
        on_event=None,
        on_result=None,
    ):
        self.recovery_registration = (task_id, recover, on_event, on_result)
        return task_id == self.task.task_id


class _RecoveredCodexServer:
    def __init__(self):
        self.process = SimpleNamespace(pid=123)
        self.recoveries = []
        self.started = False

    def warm(self):
        return {"ready": True, "pid": self.process.pid}

    def recover_task(self, **values):
        self.recoveries.append(values)
        return SimpleNamespace(finished=False)

    def recover_stalled_task(self, task_id, failure):
        return task_id == "task-recovered" and bool(failure)

    def start_task(self, *_args, **_kwargs):
        self.started = True
        raise AssertionError("Recovery must not start a duplicate Codex turn")


class MqttCodexRecoveryTests(unittest.TestCase):
    def test_recovered_codex_task_reconnects_to_original_turn(self):
        manager = _RecoveredTaskManager()
        manager.tool_evidence = Mock()
        manager.provider_usage = Mock()
        server = _RecoveredCodexServer()
        with tempfile.TemporaryDirectory() as temporary, patch.object(
            mqtt_bridge,
            "agent_task_manager",
            manager,
        ), patch.object(
            mqtt_bridge,
            "_codex_server",
            return_value=server,
        ), patch.object(
            mqtt_bridge.threading,
            "Thread",
            _ImmediateThread,
        ), patch(
            "agent_gateway._find_codex_desktop_cli",
            return_value="codex",
        ), patch(
            "task_workspace.task_workspace",
            return_value=Path(temporary),
        ):
            mqtt_bridge._start_remote_agent_task(
                mqttc=SimpleNamespace(),
                wire_payload={"scheme": "signal", "_client_route_id": "client-1"},
                payload={
                    "type": "text",
                    "content": "continue",
                    "contact_id": "codex",
                    "agent_id": "codex",
                    "client_message_id": "message-1",
                    "client_route_id": "client-1",
                    "task_id": "task-recovered",
                    "conversation_id": "conversation-1",
                    "turn_id": "phone-turn-recovered",
                    "attachments": [],
                    "_recovered_task": True,
                },
                trace=[],
                content="continue",
                msg_type="text",
            )

            from agent_tool_evidence import completed_tool_observation
            observation = completed_tool_observation(
                {"id": "command", "type": "commandExecution", "exitCode": 0, "aggregatedOutput": "fixture"},
                thread_id="thread-original", turn_id="turn-original",
            )
            updates_before = len(manager.updates)
            mqtt_bridge._dispatch_codex_event("task-recovered", {"evidence_only": True, "tool_observation": observation})
            manager.tool_evidence.record.assert_called_once()
            recorded_task, recorded_observation = manager.tool_evidence.record.call_args.args
            self.assertEqual(2, recorded_task["execution_generation"])
            self.assertEqual("phone-turn-recovered", recorded_task["client_turn_id"])
            self.assertEqual(observation, recorded_observation)
            self.assertEqual(updates_before, len(manager.updates))
            manager.task.execution_generation = 3
            mqtt_bridge._dispatch_codex_event("task-recovered", {"evidence_only": True, "tool_observation": observation})
            self.assertEqual(1, manager.tool_evidence.record.call_count)
            manager.task.execution_generation = 2

            from codex_provider_usage import normalize
            usage = normalize({"threadId": "thread-original", "turnId": "turn-original"},
                              model="fixture-model", effort="high")
            with patch.object(mqtt_bridge, "_publish_phone_payload") as publish:
                mqtt_bridge._dispatch_codex_event("task-recovered", {"provider_usage_only": True, "provider_usage": usage})
                manager.provider_usage.record.assert_called_once()
                recorded_task, recorded_usage = manager.provider_usage.record.call_args.args
                self.assertEqual(2, recorded_task["execution_generation"])
                self.assertEqual("phone-turn-recovered", recorded_task["client_turn_id"])
                self.assertEqual(usage, recorded_usage)
                self.assertEqual(updates_before, len(manager.updates))
                publish.assert_not_called()
                manager.task.execution_generation = 3
                mqtt_bridge._dispatch_codex_event("task-recovered", {"provider_usage_only": True, "provider_usage": usage})
                self.assertEqual(1, manager.provider_usage.record.call_count)
                manager.task.execution_generation = 2
                manager.provider_usage.record.side_effect = OSError("fixture audit failure")
                with self.assertLogs("codex_provider_usage", level="WARNING"):
                    mqtt_bridge._dispatch_codex_event("task-recovered", {
                        "provider_usage_only": True, "provider_usage": usage})
                self.assertEqual(updates_before, len(manager.updates))
                publish.assert_not_called()

        self.assertFalse(server.started)
        self.assertEqual(1, len(server.recoveries))
        recovery = server.recoveries[0]
        self.assertEqual("task-recovered", recovery["task_id"])
        self.assertEqual("thread-original", recovery["thread_id"])
        self.assertEqual("turn-original", recovery["turn_id"])
        self.assertTrue(recovery["cwd"])
        self.assertEqual("gpt-5.6-sol", recovery["model"])
        self.assertGreaterEqual(recovery["elapsed_seconds"], 44)
        self.assertEqual("task-recovered", manager.recovery_registration[0])
        self.assertTrue(
            manager.recovery_registration[1](
                {"task_id": "task-recovered"},
                "No progress",
            )
        )
        with mqtt_bridge.codex_task_callbacks_lock:
            mqtt_bridge.codex_task_callbacks.pop("task-recovered", None)


if __name__ == "__main__":
    unittest.main()
