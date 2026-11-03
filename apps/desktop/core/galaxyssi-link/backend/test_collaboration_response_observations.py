import hashlib
import json
import time
import unittest
from unittest.mock import patch

from collaboration_recall_bridge import CONTRACT, RESPONSE, Pending, RecallBroker
from collaboration_transport_feedback import ResponseUnconfirmed
from test_collaboration_recall_bridge import task


class CollaborationResponseObservationsTest(unittest.TestCase):
    def exchange(self, mutate=None, *, route="phone", logging_error=False):
        broker = RecallBroker()
        seen = []
        with patch("collaboration_recall_bridge.log.info") as log:
            if logging_error:
                log.side_effect = OSError("private-path")
            def publish(request):
                response = {**request, "type": RESPONSE, "result": {"success": True, "content": "private-body"}}
                if mutate:
                    mutate(response)
                seen.append(broker.receive(response, route))
                return True
            try:
                value = broker.query(task, {"mode": "workspace"}, publish, timeout=.01)
            except ResponseUnconfirmed as error:
                value = error.observation
            return value, seen, log.call_args_list, broker

    def test_valid_response_and_private_content_free_token(self):
        value, accepted, logs, broker = self.exchange()
        self.assertEqual({"success": True, "content": "private-body"}, value)
        self.assertEqual([True], accepted)
        response_log = next(call for call in logs if "Collaboration response" in call.args[0])
        self.assertEqual("accepted", response_log.args[2])
        self.assertRegex(response_log.args[1], r"^[a-f0-9]{16}$")
        for private in ("private-body", "phone", "group", "codex-contact"):
            self.assertNotIn(private, str(response_log))
        self.assertEqual({}, broker._pending)

    def test_precise_scope_fields_do_not_leak_values(self):
        for field in ("type", "contract", "phase", "client_route_id", "conversation_id",
                      "task_id", "turn_id", "contact_id", "source_message_id", "agent_id", "execution_generation"):
            with self.subTest(field=field):
                value, accepted, _, broker = self.exchange(lambda response: response.update({field: "private-wrong-value"}))
                self.assertEqual({f"mismatch_{field}": 1}, value["response_validation_counts"])
                self.assertFalse(value["authenticated_response_received"])
                self.assertNotIn("private-wrong-value", json.dumps(value))
                self.assertEqual([False], accepted)
                self.assertEqual({}, broker._pending)

    def test_result_shape_is_not_misreported_as_json_syntax(self):
        for changes, reason in (({"result": []}, "result_not_object"),
                                ({"result": {"success": "true"}}, "success_not_boolean"),
                                ({"result": {"success": True, "value": float("nan")}}, "result_not_json"),
                                ({"result": {"success": True, "value": "x" * (256 * 1024)}}, "response_too_large")):
            with self.subTest(reason=reason):
                value, accepted, _, _ = self.exchange(lambda response: response.update(changes))
                self.assertEqual({reason: 1}, value["response_validation_counts"])
                self.assertEqual([False], accepted)

    def test_wrong_peer_cannot_pollute_task_failure_feedback(self):
        value, accepted, logs, _ = self.exchange(route="another-private-peer")
        self.assertEqual({}, value["response_validation_counts"])
        self.assertEqual([False], accepted)
        response_log = next(call for call in logs if "Collaboration response" in call.args[0])
        self.assertEqual("route_mismatch", response_log.args[2])
        self.assertNotIn("another-private-peer", str(logs))

    def test_diagnostic_failure_does_not_drop_valid_reply(self):
        broker = RecallBroker()
        def publish(request):
            with patch("collaboration_recall_bridge.log.info", side_effect=OSError("private-path")):
                self.assertTrue(broker.receive({**request, "type": RESPONSE, "result": {"success": True}}, "phone"))
            return True
        self.assertTrue(broker.query(task, {"mode": "workspace"}, publish)["success"])
        value, accepted, _, broker = self.exchange(logging_error=True)
        self.assertTrue(value["success"])
        self.assertEqual([True], accepted)
        self.assertEqual({}, broker._pending)

    def test_rejected_then_corrected_response_preserves_pending_exchange(self):
        broker = RecallBroker()
        def publish(request):
            self.assertFalse(broker.receive({**request, "type": RESPONSE, "result": {"success": "true"}}, "phone"))
            self.assertTrue(broker.receive({**request, "type": RESPONSE, "result": {"success": True}}, "phone"))
            self.assertFalse(broker.receive({**request, "type": RESPONSE, "result": {"success": True}}, "phone"))
            return True
        self.assertEqual({"success": True}, broker.query(task, {"mode": "workspace"}, publish))

    def test_late_response_does_not_revive_or_extend_request(self):
        broker = RecallBroker()
        request = {"request_id": "private-request", "client_route_id": "phone"}
        pending = Pending(request, time.monotonic() - 1)
        broker._pending[request["request_id"]] = pending
        with patch("collaboration_recall_bridge.log.info") as log:
            self.assertFalse(broker.receive(request, "phone"))
            self.assertEqual("deadline_elapsed", log.call_args.args[2])
            del broker._pending[request["request_id"]]
            self.assertFalse(broker.receive(request, "phone"))
            self.assertEqual("no_pending_request", log.call_args.args[2])
            self.assertEqual(hashlib.sha256(b"private-request").hexdigest()[:16], log.call_args.args[1])
        self.assertIsNone(pending.response)
        self.assertFalse(pending.event.is_set())

    def test_malformed_request_ids_cannot_allocate_diagnostics(self):
        broker = RecallBroker()
        with patch("collaboration_recall_bridge.log.info") as log:
            for payload in (None, [], {}, {"request_id": []}, {"request_id": ""}, {"request_id": "x" * 129}):
                self.assertFalse(broker.receive(payload, "phone"))
            log.assert_not_called()
        self.assertEqual({}, broker._pending)


if __name__ == "__main__":
    unittest.main()
