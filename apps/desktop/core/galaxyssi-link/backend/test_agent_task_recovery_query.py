import copy
from types import SimpleNamespace
import unittest
from unittest.mock import Mock

from agent_task_recovery_query import IDENTITY_FIELDS, STATUSES, TASK_FIELDS, recovery_query


class RecoveryQueryTest(unittest.TestCase):
    def setUp(self):
        self.item = dict(zip(IDENTITY_FIELDS, (
            "route-a", "conversation-a", "task-a", "turn-a", "codex-contact", "42", "codex",
        )))
        self.payload = {"request_id": "query-a", "client_route_id": "route-a", "items": [self.item]}
        self.task = SimpleNamespace(**dict(zip(TASK_FIELDS, self.item.values())),
                                    status="running", status_seq=7, run_id="remote-run-a")
        self.manager = Mock(spec=["get_scoped"])
        self.manager.get_scoped.return_value = self.task

    def query(self, payload=None):
        return recovery_query(self.payload if payload is None else payload,
                              client_route_id="route-a", manager=self.manager)

    def test_exact_scope_reads_current_status_without_execution(self):
        result = self.query()
        self.assertEqual("agent_task_recovery_result", result["type"])
        self.assertEqual("running", result["items"][0]["status"])
        self.assertEqual(7, result["items"][0]["status_sequence"])
        self.manager.get_scoped.assert_called_once_with("task-a", client_route_id="route-a",
                                                      conversation_id="conversation-a", turn_id="turn-a")

    def test_every_identity_component_must_match_the_saved_task(self):
        for field in TASK_FIELDS:
            with self.subTest(field=field):
                original = getattr(self.task, field)
                setattr(self.task, field, "wrong")
                result = self.query()["items"][0]
                self.assertEqual("unavailable", result["status"])
                self.assertNotIn("remote_run_id", result)
                setattr(self.task, field, original)

    def test_stale_route_is_rejected_before_database_lookup(self):
        self.payload["client_route_id"] = "old-route"
        self.assertIsNone(self.query())
        self.manager.get_scoped.assert_not_called()

    def test_nested_route_cannot_escape_authenticated_route(self):
        self.item["client_route_id"] = "other-phone"
        self.assertIsNone(self.query())
        self.manager.get_scoped.assert_not_called()

    def test_missing_task_is_not_replayed_or_fabricated(self):
        self.manager.get_scoped.return_value = None
        self.assertEqual("unavailable", self.query()["items"][0]["status"])

    def test_all_terminal_and_waiting_states_are_preserved(self):
        for status in STATUSES:
            with self.subTest(status=status):
                self.task.status = status
                self.assertEqual(status, self.query()["items"][0]["status"])

    def test_unknown_status_is_not_claimed_running(self):
        self.task.status = "unknown"
        self.assertEqual("unavailable", self.query()["items"][0]["status"])

    def test_result_has_no_prompt_result_or_tool_payload(self):
        self.task.result = "private answer"
        self.task.prompt = "private prompt"
        self.task.events = [{"arguments": "private command"}]
        result = self.query()["items"][0]
        self.assertEqual(set(IDENTITY_FIELDS) | {"status", "remote_run_id", "status_sequence"}, set(result))

    def test_malformed_identity_rejects_whole_batch(self):
        for field in IDENTITY_FIELDS:
            for value in (None, "", 42, "x" * 201):
                with self.subTest(field=field, value=value):
                    payload = copy.deepcopy(self.payload)
                    payload["items"][0][field] = value
                    self.assertIsNone(self.query(payload))
        self.manager.get_scoped.assert_not_called()

    def test_batch_bound_and_bad_shapes(self):
        for items in ([], [self.item] * 33, {}, "tasks", [None]):
            with self.subTest(items=type(items)):
                self.assertIsNone(self.query({**self.payload, "items": items}))
        self.manager.get_scoped.assert_not_called()
        self.assertEqual(32, len(self.query({**self.payload, "items": [self.item] * 32})["items"]))

    def test_request_nonce_is_required(self):
        for nonce in (None, "", "x" * 129):
            self.assertIsNone(self.query({**self.payload, "request_id": nonce}))

    def test_repeated_queries_are_read_only_and_observe_newer_state(self):
        first = self.query()
        self.task.status = "completed"
        self.task.status_seq += 1
        second = self.query()
        self.assertEqual("running", first["items"][0]["status"])
        self.assertEqual("completed", second["items"][0]["status"])
        self.assertEqual(2, self.manager.get_scoped.call_count)


if __name__ == "__main__":
    unittest.main()
