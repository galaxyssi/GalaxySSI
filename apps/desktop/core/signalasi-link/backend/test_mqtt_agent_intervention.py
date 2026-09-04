from __future__ import annotations

import time
import unittest
from types import SimpleNamespace
from unittest.mock import patch

import mqtt_bridge


class _Task:
    def __init__(self, task_id: str, prompt: str, status: str = "running"):
        now = int(time.time() * 1_000)
        self.task_id = task_id
        self.agent_id = "hermes"
        self.contact_id = "hermes"
        self.source_message_id = f"message-{task_id}"
        self.prompt = prompt
        self.conversation_id = mqtt_bridge._scoped_agent_conversation_id(
            "client-1",
            "conversation-1",
        )
        self.client_conversation_id = "conversation-1"
        self.client_route_id = "client-1"
        self.client_turn_id = f"turn-{task_id}"
        self.status = status
        self.status_seq = 1
        self.created_at = now
        self.started_at = now
        self.updated_at = now
        self.completed_at = 0
        self.current_step = ""
        self.pending_approval = {"approval_id": "old-approval"}
        self.task_disposition = ""
        self.merged_into_task_id = ""
        self.supersedes_task_id = ""
        self.intervention_kind = ""

    def public(self):
        return {
            "task_id": self.task_id,
            "agent_id": self.agent_id,
            "contact_id": self.contact_id,
            "source_message_id": self.source_message_id,
            "conversation_id": self.conversation_id,
            "client_conversation_id": self.client_conversation_id,
            "client_route_id": self.client_route_id,
            "client_turn_id": self.client_turn_id,
            "status": self.status,
            "status_seq": self.status_seq,
            "created_at": self.created_at,
            "started_at": self.started_at,
            "updated_at": self.updated_at,
            "completed_at": self.completed_at,
            "current_step": self.current_step,
            "pending_approval": dict(self.pending_approval),
            "task_disposition": self.task_disposition,
            "merged_into_task_id": self.merged_into_task_id,
            "supersedes_task_id": self.supersedes_task_id,
            "intervention_kind": self.intervention_kind,
            "events": [],
            "output_files": [],
        }


class _TaskManager:
    def __init__(self):
        self.active = _Task("active", "Build a web dashboard")
        self.created = None
        self.created_execution_policy = {}
        self.cancelled = []
        self.events = []

    def get(self, task_id):
        if self.created is not None and self.created.task_id == task_id:
            return self.created
        return self.active if task_id == self.active.task_id else None

    def active_for_conversation(self, conversation_id, **_options):
        return self.active if conversation_id == self.active.conversation_id else None

    def add_event(self, task_id, kind, title, **values):
        self.events.append((task_id, kind, title, values))
        return self.get(task_id)

    def cancel(self, task_id, on_event=None):
        task = self.get(task_id)
        if task is None:
            return None
        self.cancelled.append(task_id)
        task.status = "cancelled"
        task.pending_approval = {}
        task.status_seq += 1
        if on_event is not None:
            on_event(task.public())
        return task

    def create(self, **values):
        self.created = _Task(values["task_id"], values["prompt"], status="queued")
        self.created_execution_policy = dict(values.get("execution_policy") or {})
        for field in (
            "task_disposition",
            "merged_into_task_id",
            "supersedes_task_id",
            "intervention_kind",
        ):
            setattr(self.created, field, values.get(field, ""))
        return self.created

    def create_external(self, **values):
        self.created = _Task(values["task_id"], values["prompt"], status="accepted")
        self.created_execution_policy = dict(values.get("execution_policy") or {})
        for field in (
            "task_disposition",
            "merged_into_task_id",
            "supersedes_task_id",
            "intervention_kind",
        ):
            setattr(self.created, field, values.get(field, ""))
        return self.created

    def update(self, task_id, status, on_event=None, **values):
        task = self.get(task_id)
        if task is None:
            return None
        task.status = status
        task.status_seq += 1
        for name, value in values.items():
            if value is not None:
                setattr(task, name, value)
        if status in {"completed", "failed", "cancelled", "timed_out"}:
            task.completed_at = int(time.time() * 1_000)
            task.pending_approval = {}
        if on_event is not None:
            on_event(task.public())
        return task


class _Provider:
    def __init__(self):
        self.cancelled = []

    def cancel(self, agent_id, task_id):
        self.cancelled.append((agent_id, task_id))
        return SimpleNamespace(state="cancelled")


class MqttAgentInterventionTests(unittest.TestCase):
    def _dispatch(
        self,
        content: str,
        execution_mode: str = "auto_complete",
        task_budget: dict | None = None,
        connector_task_mode: str = "",
        execution_policy_prompt: str = "",
    ):
        manager = _TaskManager()
        provider = _Provider()
        published = []
        with (
            patch.object(mqtt_bridge, "agent_task_manager", manager),
            patch("agent_gateway.desktop_agent_provider", return_value=provider),
            patch.object(
                mqtt_bridge,
                "_enqueue_task_event",
                side_effect=lambda _mqtt, _wire, event, _trace: published.append(event),
            ),
        ):
            mqtt_bridge._start_remote_agent_task(
                mqttc=SimpleNamespace(),
                wire_payload={"scheme": "signal", "_client_route_id": "client-1"},
                payload={
                    "type": "text",
                    "content": content,
                    "contact_id": "hermes",
                    "agent_id": "hermes",
                    "client_message_id": "message-new",
                    "client_route_id": "client-1",
                    "task_id": "task-new",
                    "conversation_id": "conversation-1",
                    "turn_id": "turn-new",
                    "attachments": [],
                    "execution_mode": execution_mode,
                    "task_budget": task_budget or {},
                    "connector_task_mode": connector_task_mode,
                    "execution_policy_prompt": execution_policy_prompt,
                },
                trace=[],
                content=content,
                msg_type="text",
            )
        return manager, provider, published

    def test_non_steerable_provider_is_superseded_with_both_prompts(self):
        manager, provider, _published = self._dispatch(
            "Change the goal to a native Android dashboard"
        )

        self.assertEqual(["active"], manager.cancelled)
        self.assertEqual([("hermes", "active")], provider.cancelled)
        self.assertEqual("superseded", manager.created.task_disposition)
        self.assertEqual("active", manager.created.supersedes_task_id)
        self.assertEqual("goal_change", manager.created.intervention_kind)
        self.assertIn("Build a web dashboard", manager.created.prompt)
        self.assertIn("native Android dashboard", manager.created.prompt)
        self.assertEqual({}, manager.active.pending_approval)

    def test_standalone_stop_interrupts_without_starting_a_replacement(self):
        manager, provider, published = self._dispatch("Cancel the current task")

        self.assertEqual(["active"], manager.cancelled)
        self.assertEqual([("hermes", "active")], provider.cancelled)
        self.assertEqual("completed", manager.created.status)
        self.assertEqual("interrupted", manager.created.task_disposition)
        self.assertEqual("active", manager.created.merged_into_task_id)
        self.assertFalse(any(event.get("result") for event in published))

    def test_plan_only_starts_an_independent_read_only_task(self):
        manager, provider, _published = self._dispatch(
            "Change the goal to a native Android dashboard",
            execution_mode="plan_only",
        )

        self.assertEqual([], manager.cancelled)
        self.assertEqual([], provider.cancelled)
        self.assertEqual("", manager.created.task_disposition)
        self.assertEqual("", manager.created.supersedes_task_id)
        self.assertEqual(
            "Change the goal to a native Android dashboard",
            manager.created.prompt,
        )
        self.assertEqual(
            "plan_only",
            manager.created_execution_policy["execution_mode"],
        )
        self.assertFalse(
            manager.created_execution_policy["requires_artifact"],
        )

    def test_phone_task_budget_is_preserved_for_the_selected_agent(self):
        manager, _provider, _published = self._dispatch(
            "Summarize the report",
            task_budget={
                "profile": "private",
                "max_network_bytes": 1_048_576,
                "allow_cloud": False,
            },
        )

        budget = manager.created_execution_policy["task_budget"]
        self.assertEqual("private", budget["profile"])
        self.assertEqual(1_048_576, budget["max_network_bytes"])
        self.assertFalse(budget["allow_cloud"])
        self.assertFalse(budget["allow_paid_providers"])

    def test_execution_policy_uses_original_request_instead_of_tool_evidence(self):
        manager, _provider, _published = self._dispatch(
            "Current user request:\nResearch and compare two primary sources.\n\n"
            "Immutable tool receipt:\nThe Android workflow was triggered and installed successfully.",
            execution_policy_prompt="Research and compare two primary sources.",
        )

        policy = manager.created_execution_policy
        self.assertEqual("research", policy["task_kind"])
        self.assertEqual("research", policy["task_intent"])
        self.assertFalse(policy["requires_artifact"])
        self.assertFalse(policy["verify_installation"])

    def test_supervised_phone_planner_forces_an_independent_plan_only_task(self):
        manager, provider, _published = self._dispatch(
            "Return exactly one JSON ActionPlan",
            execution_mode="auto_complete",
            connector_task_mode="phone_supervised_project_plan_v1",
        )

        self.assertEqual([], manager.cancelled)
        self.assertEqual([], provider.cancelled)
        self.assertEqual("plan_only", manager.created_execution_policy["execution_mode"])


if __name__ == "__main__":
    unittest.main()
