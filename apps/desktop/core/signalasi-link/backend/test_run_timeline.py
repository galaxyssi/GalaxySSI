import unittest
from types import SimpleNamespace

from agent_task_manager import AgentTask
from run_timeline import CONTRACT_VERSION, project_run_timeline


def task(**overrides):
    values = {
        "task_id": "task-1",
        "agent_id": "codex",
        "delegate_agent_id": "",
        "client_route_id": "route-1",
        "client_conversation_id": "conversation-1",
        "conversation_id": "backend-conversation-1",
        "client_turn_id": "turn-1",
        "status": "running",
        "created_at": 1_000,
        "started_at": 1_100,
        "updated_at": 1_200,
        "completed_at": 0,
        "result": "",
        "error": "",
        "exit_code": None,
        "events": [],
        "output_files": [],
        "retry_of": "",
        "attempt": 1,
        "execution_policy": {
            "task_kind": "code_build",
            "reasoning_effort": "medium",
        },
    }
    values.update(overrides)
    return SimpleNamespace(**values)


class RunTimelineTests(unittest.TestCase):
    def test_running_task_always_has_a_plan(self):
        timeline = project_run_timeline(task())

        self.assertEqual(CONTRACT_VERSION, timeline["contract"])
        self.assertEqual(["plan"], [event["kind"] for event in timeline["events"]])
        self.assertTrue(timeline["has_plan"])
        self.assertFalse(timeline["terminal"])
        self.assertFalse(timeline["complete"])

    def test_completed_task_has_a_result_without_repeating_result_text(self):
        timeline = project_run_timeline(task(
            status="completed",
            completed_at=2_000,
            result="private result body",
            output_files=[{"name": "result.zip"}],
        ))

        self.assertEqual(["plan", "result"], [event["kind"] for event in timeline["events"]])
        self.assertEqual(19, timeline["events"][-1]["metadata"]["result_chars"])
        self.assertEqual(1, timeline["events"][-1]["metadata"]["artifact_count"])
        self.assertNotIn("private result body", str(timeline))
        self.assertTrue(timeline["complete"])

    def test_failure_and_retry_are_explicit(self):
        timeline = project_run_timeline(task(
            status="failed",
            completed_at=2_500,
            error="compiler exited 1",
            retry_of="task-0",
            attempt=2,
        ))

        self.assertEqual(
            ["retry", "plan", "failure"],
            [event["kind"] for event in timeline["events"]],
        )
        self.assertTrue(timeline["has_retry"])
        self.assertTrue(timeline["complete"])

    def test_tool_events_preserve_identity_and_update_state(self):
        timeline = project_run_timeline(task(events=[{
            "event_id": "codex:command:1",
            "kind": "command",
            "title": "Run tests",
            "status": "completed",
            "detail": "pytest -q",
            "created_at": 1_300,
            "updated_at": 1_400,
            "metadata": {
                "tool_id": "shell.exec",
                "client_route_id": "spoofed-route",
                "task_id": "spoofed-task",
            },
        }]))

        tool = next(event for event in timeline["events"] if event["kind"] == "tool")
        self.assertEqual("route-1", tool["metadata"]["client_route_id"])
        self.assertEqual("conversation-1", tool["metadata"]["conversation_id"])
        self.assertEqual("task-1", tool["metadata"]["task_id"])
        self.assertEqual("turn-1", tool["metadata"]["turn_id"])
        self.assertTrue(timeline["has_tool_activity"])

    def test_durable_record_does_not_store_a_duplicate_projection(self):
        managed = AgentTask(
            task_id="task-1",
            agent_id="codex",
            contact_id="codex",
            source_message_id="source-1",
            prompt="Run tests",
        )

        self.assertIn("run_timeline", managed.public())
        self.assertNotIn("run_timeline", managed.record())

    def test_intervention_relationship_is_part_of_the_durable_identity(self):
        managed = AgentTask(
            task_id="task-new",
            agent_id="hermes",
            contact_id="hermes",
            source_message_id="source-new",
            prompt="Use Android instead",
            task_disposition="superseded",
            supersedes_task_id="task-old",
            intervention_kind="goal_change",
        )

        public = managed.public()
        record = managed.record()
        plan = public["run_timeline"]["events"][0]
        self.assertEqual("superseded", public["task_disposition"])
        self.assertEqual("task-old", record["supersedes_task_id"])
        self.assertEqual("goal_change", plan["metadata"]["intervention_kind"])


if __name__ == "__main__":
    unittest.main()
