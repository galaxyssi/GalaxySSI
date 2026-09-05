import json
import tempfile
import unittest
from pathlib import Path

from agent_run_kernel import (
    AgentRunEvent,
    AgentRunEventLedger,
    AgentRunIdentityConflict,
    AgentRunTerminalConflict,
    RUN_EVENT_PROTOCOL,
    RUN_EVENT_SCHEMA_VERSION,
    RUN_EVENT_TYPES,
    runtime_projection_event,
    reduce_run_state,
)


class AgentRunEventLedgerTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.path = Path(self.temporary.name) / "agent-run-events.sqlite3"
        self.ledger = AgentRunEventLedger(self.path, now=lambda: 1_700_000_000.0)

    def tearDown(self):
        self.temporary.cleanup()

    @staticmethod
    def event(event_type: str, *, event_id: str, **overrides) -> dict:
        payload = {
            "event_id": event_id,
            "idempotency_key": f"idempotency:{event_id}",
            "client_route_id": "phone-s26u",
            "conversation_id": "conversation-1",
            "goal_id": "goal-1",
            "task_id": "task-1",
            "run_id": "run-1",
            "turn_id": "turn-1",
            "action_id": f"action:{event_id}",
            "message_id": "message-1",
            "step_id": "step-1",
            "tool_call_id": "",
            "agent_id": "codex",
            "device_id": "desktop-t14",
            "type": event_type,
            "sequence": 0,
            "timestamp_millis": 0,
            "payload": {"detail": event_type.lower()},
        }
        payload.update(overrides)
        return payload

    def test_checkpoint_and_late_events_preserve_control_state(self):
        for state in ("created", "queued", "running", "paused", "waiting_for_user",
                      "waiting_for_device", "interrupted", "completed", "failed", "cancelled"):
            self.assertEqual(state, reduce_run_state(state, "CHECKPOINT_SAVED"))
        for state in ("completed", "failed", "cancelled"):
            self.assertEqual(state, reduce_run_state(state, "TOOL_PROGRESS"))
            self.assertEqual("running", reduce_run_state(state, "RUN_RECOVERED"))

    def test_invalid_checkpoint_rolls_back_event_and_root_together(self):
        with self.assertRaises(ValueError):
            self.ledger.append(self.event("RUN_CREATED", event_id="invalid", payload={
                "projection_checkpoint": {"kind": "runtime", "data": "not an object"},
            }))
        self.assertEqual(0, self.ledger.event_count())
        self.assertIsNone(self.ledger.snapshot("run-1"))
        self.assertEqual([], self.ledger.checkpoints("runtime"))

    def test_checkpoint_pages_have_no_duplicates_when_timestamps_tie(self):
        for index in range(7):
            self.ledger.append(self.event(
                "RUN_CREATED", event_id=f"event-{index}", run_id=f"run-{index}",
                payload={"projection_checkpoint": {"kind": "runtime", "data": {"index": index}}},
            ))
        seen = []
        before = None
        while page := self.ledger.checkpoints("runtime", limit=3, before=before):
            seen.extend(row["run_id"] for row in page)
            before = (page[-1]["updated_at_millis"], page[-1]["run_id"])
        self.assertEqual([f"run-{index}" for index in reversed(range(7))], seen)

    def test_assigns_monotonic_sequence_and_replays_same_idempotency_key(self):
        first, created = self.ledger.append(self.event("RUN_CREATED", event_id="created"))
        started, started_created = self.ledger.append(
            self.event("RUN_STARTED", event_id="started")
        )
        replay, replay_created = self.ledger.append({
            **self.event("RUN_STARTED", event_id="different-event-id"),
            "idempotency_key": "idempotency:started",
            "action_id": "action:started",
        })

        self.assertTrue(created)
        self.assertTrue(started_created)
        self.assertFalse(replay_created)
        self.assertEqual([1, 2], [first.sequence, started.sequence])
        self.assertEqual(started, replay)
        self.assertEqual(2, self.ledger.event_count("run-1"))

    def test_rejects_idempotency_key_reuse_with_different_content(self):
        self.ledger.append(self.event("RUN_CREATED", event_id="created"))

        with self.assertRaises(AgentRunIdentityConflict):
            self.ledger.append({
                **self.event("RUN_STARTED", event_id="different"),
                "idempotency_key": "idempotency:created",
            })

    def test_rejects_cross_route_run_identity_change(self):
        self.ledger.append(self.event("RUN_CREATED", event_id="created"))

        with self.assertRaises(AgentRunIdentityConflict):
            self.ledger.append(
                self.event(
                    "RUN_STARTED",
                    event_id="wrong-route",
                    client_route_id="phone-s20u",
                )
            )

        self.assertEqual(1, self.ledger.event_count("run-1"))

    def test_terminal_run_requires_explicit_recovery_before_more_events(self):
        self.ledger.append(self.event("RUN_CREATED", event_id="created"))
        self.ledger.append(self.event("RUN_COMPLETED", event_id="completed"))

        with self.assertRaises(AgentRunTerminalConflict):
            self.ledger.append(self.event("TOOL_PROGRESS", event_id="late-progress"))

        recovered, created = self.ledger.append(
            self.event("RUN_RECOVERED", event_id="recovered")
        )
        self.assertTrue(created)
        self.assertEqual(3, recovered.sequence)
        self.assertEqual("running", self.ledger.snapshot("run-1")["state"])

    def test_events_survive_reopen_without_fixed_history_truncation(self):
        self.ledger.append(self.event("RUN_CREATED", event_id="created"))
        for index in range(1, 2_052):
            self.ledger.append(
                self.event(
                    "TOOL_PROGRESS",
                    event_id=f"progress-{index}",
                    action_id=f"tool-{index}",
                )
            )

        reopened = AgentRunEventLedger(self.path)
        self.assertEqual(2_052, reopened.event_count("run-1"))
        self.assertEqual(2_052, len(reopened.events("run-1")))
        self.assertEqual(
            list(range(2_001, 2_053)),
            [
                event.sequence
                for event in reopened.events(
                    "run-1",
                    after_sequence=2_000,
                    limit=100,
                )
            ],
        )
        self.assertEqual(2_052, reopened.snapshot("run-1")["last_sequence"])

    def test_idempotency_key_is_scoped_to_run(self):
        first, first_created = self.ledger.append(
            self.event(
                "RUN_CREATED",
                event_id="first-run",
                idempotency_key="shared-idempotency",
            )
        )
        second, second_created = self.ledger.append(
            self.event(
                "RUN_CREATED",
                event_id="second-run",
                idempotency_key="shared-idempotency",
                run_id="run-2",
                task_id="task-2",
                goal_id="goal-2",
            )
        )

        self.assertTrue(first_created)
        self.assertTrue(second_created)
        self.assertEqual("run-1", first.run_id)
        self.assertEqual("run-2", second.run_id)

    def test_runtime_projection_populates_complete_portable_identity(self):
        event = runtime_projection_event(
            {
                "run_id": "runtime-run",
                "idempotency_key": "request-key",
                "client_route_id": "phone-s26u",
                "conversation_id": "conversation-7",
                "goal_id": "goal-7",
                "task_id": "task-7",
                "turn_id": "turn-7",
                "source_message_id": "message-7",
                "agent_id": "codex",
                "device_id": "desktop-t14",
            },
            "run_started",
            2,
            1234,
        )

        self.assertEqual(RUN_EVENT_PROTOCOL, event.protocol)
        self.assertEqual(RUN_EVENT_SCHEMA_VERSION, event.schema_version)
        self.assertEqual("RUN_STARTED", event.type)
        self.assertEqual("phone-s26u", event.client_route_id)
        self.assertEqual("turn-7", event.turn_id)
        self.assertTrue(event.action_id)

    def test_schema_and_desktop_event_catalog_remain_aligned(self):
        root = Path(__file__).resolve().parents[5]
        schema = json.loads(
            (root / "core" / "protocol" / "agent-run-event-v1.schema.json")
            .read_text(encoding="utf-8")
        )
        required = set(schema["required"])

        self.assertEqual(RUN_EVENT_PROTOCOL, schema["properties"]["protocol"]["const"])
        self.assertEqual(RUN_EVENT_SCHEMA_VERSION, schema["properties"]["schema_version"]["const"])
        self.assertEqual(RUN_EVENT_TYPES, frozenset(schema["properties"]["type"]["enum"]))
        self.assertTrue({
            "client_route_id",
            "conversation_id",
            "goal_id",
            "task_id",
            "run_id",
            "turn_id",
            "action_id",
        }.issubset(required))
        event = AgentRunEvent.from_mapping(self.event("RUN_CREATED", event_id="shape"))
        self.assertTrue(required.issubset(event.public()))


if __name__ == "__main__":
    unittest.main()
