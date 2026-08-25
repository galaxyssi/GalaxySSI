import os
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from codex_app_server import CodexAppServer
from latency_feature_flags import feature_enabled
from mqtt_bridge import (
    _TaskProgressEventGate,
    _agent_task_payload,
    _codex_visible_progress_event,
    _should_publish_task_status,
    _task_event_is_coalescible,
    _trace_metrics,
)


class TaskLatencyTests(unittest.TestCase):
    def test_output_delta_feature_flag_can_be_disabled(self):
        with patch.dict(
            os.environ,
            {"SIGNALASI_FEATURE_AGENT_OUTPUT_DELTA_V1": "off"},
        ):
            self.assertFalse(feature_enabled("agent.output_delta_v1", default=True))

    def test_trace_metrics_reports_stage_and_total_milliseconds(self):
        metrics = _trace_metrics([
            {"stage": "phone_publish_started", "at": 1_000},
            {"stage": "desktop_mqtt_received", "at": 1_240},
            {"stage": "desktop_task_created", "at": 1_310},
            {"stage": "codex_running", "at": 1_900},
        ])

        self.assertEqual(900, metrics["total_ms"])
        self.assertEqual(240, metrics["stages"][1]["from_previous_ms"])
        self.assertEqual(310, metrics["stages"][2]["from_start_ms"])

    def test_transport_statuses_publish_acceptance_before_progress_is_merged(self):
        self.assertTrue(_should_publish_task_status("accepted"))
        self.assertFalse(_should_publish_task_status("queued"))
        self.assertFalse(_should_publish_task_status("starting"))
        self.assertTrue(_should_publish_task_status("running"))
        self.assertFalse(_should_publish_task_status("completed"))
        self.assertTrue(_should_publish_task_status("failed"))

    def test_acceptance_is_published_before_running_heartbeat(self):
        gate = _TaskProgressEventGate(heartbeat_interval_ms=15_000)

        self.assertTrue(gate.should_publish({
            "status": "accepted", "status_seq": 1, "current_step": "",
        }, now_ms=1_000))
        self.assertTrue(gate.should_publish({
            "status": "running", "status_seq": 2, "current_step": "Codex is working",
        }, now_ms=1_100))

    def test_running_progress_keeps_a_bounded_heartbeat(self):
        gate = _TaskProgressEventGate(heartbeat_interval_ms=15_000)

        self.assertTrue(gate.should_publish({
            "status": "running", "status_seq": 1, "current_step": "Running Codex",
        }, now_ms=1_000))
        self.assertFalse(gate.should_publish({
            "status": "running", "status_seq": 2, "current_step": "Running Codex",
        }, now_ms=6_000))
        self.assertFalse(gate.should_publish({
            "status": "running", "status_seq": 3, "current_step": "Running Codex",
        }, now_ms=15_999))
        self.assertFalse(gate.should_publish({
            "status": "running", "status_seq": 2, "current_step": "Running Codex",
        }, now_ms=16_000))
        self.assertTrue(gate.should_publish({
            "status": "running", "status_seq": 4, "current_step": "Running Codex",
        }, now_ms=16_000))

    def test_running_step_change_publishes_without_waiting_for_heartbeat(self):
        gate = _TaskProgressEventGate(heartbeat_interval_ms=15_000)

        self.assertTrue(gate.should_publish({
            "status": "running", "status_seq": 1, "current_step": "",
        }, now_ms=1_000))
        self.assertTrue(gate.should_publish({
            "status": "running", "status_seq": 2, "current_step": "Reading files",
        }, now_ms=1_100))
        self.assertFalse(gate.should_publish({
            "status": "running", "status_seq": 2, "current_step": "Reading files",
        }, now_ms=20_000))

    def test_progress_event_state_change_publishes_even_when_title_is_unchanged(self):
        gate = _TaskProgressEventGate(heartbeat_interval_ms=15_000)
        started = {
            "event_id": "codex:image_view:image-1",
            "status": "running",
            "created_at": 1_000,
            "updated_at": 1_000,
        }
        completed = {
            **started,
            "status": "completed",
            "updated_at": 1_100,
        }

        self.assertTrue(gate.should_publish({
            "status": "running",
            "status_seq": 1,
            "current_step": "Image",
            "events": [started],
        }, now_ms=1_000))
        self.assertTrue(gate.should_publish({
            "status": "running",
            "status_seq": 2,
            "current_step": "Image",
            "events": [completed],
        }, now_ms=1_100))

    def test_first_output_trace_publishes_without_changing_visible_step(self):
        gate = _TaskProgressEventGate(heartbeat_interval_ms=15_000)
        running = {
            "status": "running",
            "status_seq": 1,
            "current_step": "Codex is working",
            "delivery_trace": [
                {"stage": "codex_running", "at": 1_000},
            ],
        }
        first_output = {
            **running,
            "status_seq": 2,
            "delivery_trace": [
                *running["delivery_trace"],
                {"stage": "agent_first_output", "at": 1_250},
            ],
        }

        self.assertTrue(gate.should_publish(running, now_ms=1_000))
        self.assertTrue(gate.should_publish(first_output, now_ms=1_250))

    def test_new_output_sequence_publishes_even_when_step_is_unchanged(self):
        gate = _TaskProgressEventGate(heartbeat_interval_ms=15_000)
        first = {
            "status": "running",
            "status_seq": 1,
            "current_step": "Codex is responding",
            "output_delta_sequence": 1,
        }
        second = {
            **first,
            "status_seq": 2,
            "output_delta_sequence": 2,
        }

        self.assertTrue(gate.should_publish(first, now_ms=1_000))
        self.assertTrue(gate.should_publish(second, now_ms=1_050))
        self.assertFalse(gate.should_publish(second, now_ms=1_100))

    def test_running_partial_snapshot_is_mqtt_coalescible(self):
        self.assertTrue(_task_event_is_coalescible({
            "status": "running",
            "partial_result": {"sequence": 1, "text": "Visible reply"},
        }))
        self.assertFalse(_task_event_is_coalescible({
            "status": "waiting_approval",
            "partial_result": {"sequence": 1, "text": "Visible reply"},
        }))

    def test_completed_task_replays_readable_progress(self):
        gate = _TaskProgressEventGate(heartbeat_interval_ms=15_000)
        self.assertTrue(gate.should_publish({
            "status": "running",
            "status_seq": 1,
            "events": [{
                "event_id": "commentary-1",
                "kind": "narration",
                "title": "Inspecting",
                "detail": "Inspecting the worksheet.",
            }],
        }, now_ms=1_000))
        self.assertTrue(gate.should_publish({
            "status": "completed",
            "status_seq": 2,
            "events": [{
                "event_id": "commentary-1",
                "kind": "narration",
                "title": "Inspecting",
                "detail": "Inspecting the worksheet.",
            }],
        }, now_ms=2_000))
        self.assertFalse(_TaskProgressEventGate().should_publish({
            "status": "completed",
            "status_seq": 1,
            "events": [],
        }, now_ms=1_000))

    def test_task_payload_carries_latest_event_and_replays_only_readable_progress(self):
        first = {
            "event_id": "one",
            "kind": "command",
            "status": "completed",
            "detail": "python hidden.py",
        }
        empty_reasoning = {
            "event_id": "planning",
            "kind": "reasoning",
            "status": "completed",
            "title": "Planning",
            "detail": "",
        }
        latest = {
            "event_id": "two",
            "kind": "narration",
            "status": "completed",
            "detail": "Inspecting the worksheet.",
        }
        payload = _agent_task_payload(
            {
                "task_id": "task-1",
                "status": "running",
                "events": [first, empty_reasoning, latest],
            },
            [],
            resolved_desktop_id="desktop-1",
            resolved_desktop_name="Desktop",
            include_progress_replay=True,
        )

        self.assertEqual(latest, payload["progress_event"])
        self.assertNotIn("connector_agents", payload)
        self.assertEqual(
            [{
                "event_id": "two",
                "kind": "narration",
                "code": "narration",
                "title": "",
                "status": "completed",
                "detail": "Inspecting the worksheet.",
                "created_at": 0,
                "updated_at": 0,
            }],
            payload["events"],
        )

    def test_codex_visible_progress_prefers_public_progress_payload(self):
        event = _codex_visible_progress_event({
            "event_kind": "reasoning",
            "event_detail": "private reasoning must not be used",
            "progress_event": {
                "event_id": "summary-1",
                "kind": "narration",
                "code": "reasoning_summary",
                "title": "Planning",
                "detail": "I will inspect the phone project before editing it.",
                "status": "completed",
            },
        })

        self.assertIsNotNone(event)
        self.assertEqual("summary-1", event["event_id"])
        self.assertEqual("narration", event["kind"])
        self.assertEqual(
            "I will inspect the phone project before editing it.",
            event["detail"],
        )
        self.assertNotIn("private reasoning", str(event))

    def test_task_payload_carries_reconnect_safe_cumulative_partial(self):
        payload = _agent_task_payload(
            {
                "task_id": "task-delta",
                "status": "running",
                "status_seq": 8,
                "partial_result": {
                    "event_id": "partial-3",
                    "sequence": 3,
                    "text": "Complete text so far",
                    "mode": "cumulative",
                },
            },
            [],
            resolved_desktop_id="desktop-1",
            resolved_desktop_name="Desktop",
        )

        self.assertEqual(8, payload["status_seq"])
        self.assertEqual("partial-3", payload["partial_result"]["event_id"])
        self.assertEqual(3, payload["partial_result"]["sequence"])
        self.assertEqual("cumulative", payload["partial_result"]["mode"])
        self.assertEqual("partial_result", payload["event_type"])
        self.assertEqual(payload["partial_result"], payload["payload"])

    def test_task_payload_uses_persisted_trace_and_includes_outbound_stage(self):
        task = {
            "task_id": "task-persisted-trace",
            "trace_id": "trace-1",
            "status": "running",
            "agent_id": "codex",
            "client_route_id": "route-a",
            "client_conversation_id": "conversation-a",
            "client_turn_id": "turn-a",
            "delivery_trace": [
                {"stage": "created", "at": 1_000, "detail": "phone"},
                {"stage": "agent_first_output", "at": 1_500, "detail": "codex"},
            ],
            "execution_view": {
                "executor_id": "codex",
                "location_kind": "desktop",
                "location_id": "desktop-1",
                "location_name": "Desktop",
                "cancellable": True,
            },
        }
        with patch("mqtt_bridge.time.time", return_value=2.0):
            payload = _agent_task_payload(
                task,
                [{"stage": "stale", "at": 500, "detail": ""}],
                resolved_desktop_id="desktop-1",
                resolved_desktop_name="Desktop",
            )

        self.assertEqual("trace-1", payload["trace_id"])
        self.assertEqual("route-a", payload["client_route_id"])
        self.assertEqual("conversation-a", payload["conversation_id"])
        self.assertEqual("turn-a", payload["turn_id"])
        self.assertEqual(task["execution_view"], payload["execution_view"])
        self.assertEqual(
            ["created", "agent_first_output", "agent_running"],
            [item["stage"] for item in payload["delivery_trace"]],
        )
        self.assertEqual(1_000, payload["latency"]["total_ms"])
        self.assertEqual(500, payload["latency"]["first_output_ms"])

    def test_readable_progress_replay_is_bounded_and_keeps_latest_narration(self):
        events = [
            {
                "event_id": f"narration-{index}",
                "kind": "narration",
                "status": "completed",
                "detail": f"Visible update {index}",
            }
            for index in range(80)
        ]
        payload = _agent_task_payload(
            {"task_id": "task-1", "status": "running", "events": events},
            [],
            resolved_desktop_id="desktop-1",
            resolved_desktop_name="Desktop",
            include_progress_replay=True,
        )

        self.assertEqual(64, len(payload["events"]))
        self.assertEqual("narration-16", payload["events"][0]["event_id"])
        self.assertEqual("narration-79", payload["events"][-1]["event_id"])

    def test_readable_progress_replay_preserves_redacted_mcp_call_context(self):
        metadata = {
            "kind": "mcp_tool_call",
            "connection_id": "vault",
            "connection_name": "Vault",
            "tool_name": "search",
            "source": "desktop-mcp:vault",
            "risk": "low",
            "permissions": ["mcp.data.read", "mcp.network.connect"],
            "parameter_preview": {"query": "release notes"},
            "permission_mode": "read_only",
            "permission_decision": "allowed_read_only",
            "allowed": True,
            "status": "succeeded",
            "duration_ms": 28,
            "internal_secret": "must-not-cross-the-wire",
        }
        payload = _agent_task_payload(
            {
                "task_id": "task-mcp",
                "status": "completed",
                "events": [{
                    "event_id": "mcp-tool:1",
                    "kind": "mcp",
                    "status": "completed",
                    "title": "Vault · search",
                    "metadata": metadata,
                }],
            },
            [],
            resolved_desktop_id="desktop-1",
            resolved_desktop_name="Desktop",
            include_progress_replay=True,
        )

        self.assertEqual("mcp", payload["events"][0]["kind"])
        self.assertEqual("mcp_tool", payload["events"][0]["code"])
        self.assertEqual("desktop-mcp:vault", payload["events"][0]["metadata"]["source"])
        self.assertEqual({"query": "release notes"}, payload["events"][0]["metadata"]["parameter_preview"])
        self.assertNotIn("internal_secret", payload["events"][0]["metadata"])

    def test_terminal_failure_is_not_throttled(self):
        gate = _TaskProgressEventGate(heartbeat_interval_ms=15_000)

        self.assertTrue(gate.should_publish({
            "status": "running", "status_seq": 1, "current_step": "Running Hermes",
        }, now_ms=1_000))
        self.assertTrue(gate.should_publish({
            "status": "failed", "status_seq": 2, "current_step": "Running Hermes",
        }, now_ms=1_100))
        self.assertFalse(gate.should_publish({
            "status": "completed", "status_seq": 3, "current_step": "",
        }, now_ms=1_200))

    def test_steered_completion_is_published_even_though_normal_completion_is_hidden(self):
        gate = _TaskProgressEventGate(heartbeat_interval_ms=15_000)

        self.assertTrue(gate.should_publish({
            "status": "running", "status_seq": 1, "current_step": "Adding instruction",
        }, now_ms=1_000))
        self.assertTrue(gate.should_publish({
            "status": "completed",
            "status_seq": 2,
            "current_step": "",
            "task_disposition": "steered",
        }, now_ms=1_100))

    def test_resumed_running_and_stale_events_are_ordered(self):
        gate = _TaskProgressEventGate(heartbeat_interval_ms=15_000)

        self.assertTrue(gate.should_publish({
            "status": "running", "status_seq": 1, "current_step": "Calling tool",
        }, now_ms=1_000))
        self.assertTrue(gate.should_publish({
            "status": "waiting_input", "status_seq": 2, "current_step": "Waiting for input",
        }, now_ms=1_100))
        self.assertTrue(gate.should_publish({
            "status": "running", "status_seq": 3, "current_step": "Calling tool",
        }, now_ms=1_200))
        self.assertFalse(gate.should_publish({
            "status": "completed", "status_seq": 4, "current_step": "",
        }, now_ms=1_300))
        self.assertFalse(gate.should_publish({
            "status": "running", "status_seq": 3, "current_step": "Calling tool",
        }, now_ms=20_000))

    def test_warm_initializes_without_creating_a_task(self):
        server = CodexAppServer("codex", {}, lambda _task_id, _event: None)
        server.process = SimpleNamespace(pid=42)
        with patch.object(server, "_ensure_started") as ensure_started:
            result = server.warm()

        ensure_started.assert_called_once_with()
        self.assertTrue(result["ready"])
        self.assertEqual(42, result["pid"])


if __name__ == "__main__":
    unittest.main()
