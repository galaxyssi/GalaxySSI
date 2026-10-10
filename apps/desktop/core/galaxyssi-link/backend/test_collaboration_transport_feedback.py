import json
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch

from collaboration_recall_bridge import RESPONSE, RecallBroker
from collaboration_transport_feedback import PublishObservation
from test_collaboration_recall_bridge import task
from test_collaboration_recall_retry import simulated_time


class CollaborationTransportFeedbackTest(unittest.TestCase):
    def test_admission_reasons_reach_structured_feedback_without_raw_content(self):
        for reason in ("invalid_attempt", "path_unavailable", "path_packet_limit", "duplicate_attempt",
                       "tracking_limit", "message_content_conflict", "inflight_packet_limit",
                       "inflight_byte_limit", "peer_byte_limit"):
            code = "attempt_" + reason
            self.assertEqual(code, PublishObservation(False, code).public()["reason_code"])
        self.assertEqual("unknown", PublishObservation(False, "attempt_private-payload").public()["reason_code"])

    def details(self, error):
        return json.loads("{" + str(error).split("{", 1)[1])

    def test_rejected_route_reports_local_facts_without_claiming_phone_failure(self):
        with simulated_time():
            publish = Mock(return_value=PublishObservation(False, "publication_unclassified", "unconfirmed_local_epoch", True))
            with self.assertRaises(ConnectionError) as error:
                RecallBroker().query(task, {"mode": "workspace"}, publish)
        details = self.details(error.exception)
        self.assertEqual(4, details["publish_attempts"])
        self.assertEqual(0, details["accepted_publish_attempts"])
        self.assertEqual({"publication_unclassified": 4}, details["reason_counts"])
        self.assertEqual("unconfirmed_local_epoch", details["latest_transport_observation"]["route_state_after_attempt"])
        self.assertTrue(details["latest_transport_observation"]["mqtt_connected_after_attempt"])
        self.assertEqual("unknown", details["remote_execution_state"])
        self.assertFalse(details["authenticated_response_received"])

    def test_one_accepted_publish_is_timeout_even_if_later_admission_fails(self):
        with simulated_time():
            publish = Mock(side_effect=[PublishObservation(True, "accepted", "ready", True)] +
                           [PublishObservation(False, "no_admitted_path", "no_verified_common_route", True)] * 3)
            with self.assertRaises(TimeoutError) as error:
                RecallBroker().query(task, {"mode": "workspace"}, publish)
        details = self.details(error.exception)
        self.assertEqual(1, details["accepted_publish_attempts"])
        self.assertEqual({"accepted": 1, "no_admitted_path": 3}, details["reason_counts"])
        self.assertNotIn("all publish attempts", str(error.exception))

    def test_observed_recovery_still_requires_authenticated_phone_response(self):
        with simulated_time():
            broker, calls = RecallBroker(), []
            def publish(request):
                calls.append(request)
                if len(calls) == 1:
                    return PublishObservation(False, "publication_unclassified", "unconfirmed_local_epoch", True)
                response = {**request, "type": RESPONSE, "result": {"success": True, "content": "original"}}
                self.assertFalse(broker.receive(response, "wrong-phone"))
                self.assertTrue(broker.receive(response, "phone"))
                return PublishObservation(True, "accepted", "ready", True)
            self.assertEqual("original", broker.query(task, {"mode": "workspace"}, publish)["content"])
            self.assertEqual(calls[0], calls[1])

    def test_confirmation_failure_is_labelled_confirm_not_missing_evidence(self):
        import hashlib
        with simulated_time():
            broker = RecallBroker()
            def publish(request):
                if request["phase"] == "read":
                    result = {"success": True, "content": "original", "delivery": {
                        "receipt_id": "receipt", "content_sha256": hashlib.sha256(b"original").hexdigest()}}
                    broker.receive({**request, "type": RESPONSE, "result": result}, "phone")
                    return PublishObservation(True, "accepted")
                return PublishObservation(False, "physical_publish_rejected")
            with self.assertRaises(ConnectionError) as error:
                broker.query(task, {"mode": "evidence", "evidence_id": "a" * 64, "sha256": "b" * 64}, publish)
        self.assertEqual("confirm", self.details(error.exception)["phase"])
        self.assertEqual({}, broker._pending)

    def test_feedback_cannot_copy_selectors_secret_fields_or_arbitrary_messages(self):
        for value in ("secret-topic", ["private"], {"token": "private"}, None):
            with self.subTest(value=value), simulated_time():
                with self.assertLogs("collaboration_recall_bridge", level="INFO") as logs:
                    with self.assertRaises(ConnectionError) as error:
                        RecallBroker().query(task, {"mode": "capabilities", "query": "private-question"},
                            lambda _: PublishObservation(False, value, value, "private-value"))
            combined = str(error.exception) + "\n".join(logs.output)
            self.assertNotIn("private", combined)
            self.assertNotIn("secret-topic", combined)
            self.assertEqual("unknown", self.details(error.exception)["latest_transport_observation"]["reason_code"])

    def test_bridge_returns_observation_from_same_publication_attempt(self):
        import mqtt_bridge
        broker = SimpleNamespace(query=lambda snapshot, arguments, publish, **_: publish({"client_route_id": "phone"}))
        expected = PublishObservation(False, "missing_recipient")
        def publish(_client, wire, request, *, durable, observe):
            self.assertFalse(durable)
            self.assertEqual("phone", wire["_client_route_id"])
            observe(expected)
            return False
        with patch.object(mqtt_bridge, "_publish_phone_payload", side_effect=publish):
            self.assertIs(expected, mqtt_bridge._codex_collaboration_exchange(broker, "task", {}, lambda: True))

    def test_phone_publisher_preserves_boolean_contract_and_recipient_check(self):
        import mqtt_bridge
        observed = []
        with patch.object(mqtt_bridge, "_wire_client", return_value=None):
            self.assertIs(False, mqtt_bridge._publish_phone_payload(None, {}, {"type": "collaboration_recall_request"},
                                                                   durable=False, observe=observed.append))
        self.assertEqual("missing_recipient", observed[-1].reason_code)
        with patch.object(mqtt_bridge, "_wire_client", return_value={"client_route_id": "phone"}), \
                patch("agent_worker_routing.recipient_allowed", return_value=False), \
                patch.object(mqtt_bridge, "_publish_to_registered_client") as send:
            self.assertIs(False, mqtt_bridge._publish_phone_payload(None, {}, {"type": "collaboration_recall_request"},
                                                                   durable=False, observe=observed.append))
        send.assert_not_called()
        self.assertEqual("recipient_not_authorized", observed[-1].reason_code)

    def test_phone_publisher_connectivity_is_only_a_post_attempt_observation(self):
        import mqtt_bridge
        from mqtt_pool_client import MqttPoolClient, PublishInfo
        from tests.mqtt_pool_fixture import ManualPool
        client = MqttPoolClient(classify_publication=lambda *_: None, pool_factory=ManualPool)
        self.addCleanup(client.disconnect)
        client.peer_routes = SimpleNamespace(admission_state=lambda _: "ready")
        client._pool.connect("hivemq")
        observed = []
        with patch.object(mqtt_bridge, "_wire_client", return_value={"client_route_id": "phone"}), \
                patch("agent_worker_routing.recipient_allowed", return_value=True), \
                patch.object(mqtt_bridge, "_topics_for_client", return_value=SimpleNamespace(send="private-topic")), \
                patch.object(mqtt_bridge, "_publish_to_registered_client", return_value=PublishInfo(1, rc=4,
                    reason_code="publication_unclassified")):
            self.assertIs(False, mqtt_bridge._publish_phone_payload(client, {"_client_route_id": "phone"},
                {"type": "collaboration_recall_request"}, durable=False, observe=observed.append))
        self.assertEqual("ready", observed[-1].route_state_after_attempt)
        self.assertEqual("publication_unclassified", observed[-1].reason_code)
        self.assertTrue(observed[-1].mqtt_connected_after_attempt)

    def test_codex_receives_complete_structured_failure_instead_of_truncated_json(self):
        from codex_app_server import CodexAppServer, CodexRun
        for tool in ("collaboration_recall",):
            with self.subTest(tool=tool), simulated_time():
                def fail(*_args):
                    return RecallBroker().query(task, {"mode": "workspace"},
                        lambda _: PublishObservation(False, "publication_unclassified", "unconfirmed_local_epoch", True))
                server = CodexAppServer("codex", {}, lambda *_: None,
                    collaboration_recall=fail, collaboration_publish=fail)
                server._runs["task"] = CodexRun("task", thread_id="thread", turn_id="turn")
                with patch.object(server, "_write_server_response") as write, self.assertLogs(level="ERROR"):
                    server._execute_dynamic_tool_call("task", {"id": 3}, {"tool": tool,
                        "arguments": {"mode": "workspace"}}, {})
                result = write.call_args.args[1]
                self.assertFalse(result["success"])
                payload = json.loads(result["contentItems"][0]["text"])
                self.assertGreater(len(result["contentItems"][0]["text"]), 500)
                self.assertEqual("transport_unconfirmed", payload["status"])
                observation = payload["transport_observation"]
                self.assertEqual("unconfirmed_local_epoch", observation["latest_transport_observation"]["route_state_after_attempt"])
                self.assertEqual("unknown", observation["remote_execution_state"])

    def test_actual_milestone_wrapper_preserves_structured_observation_and_mode_guidance_to_codex(self):
        from codex_app_server import CodexAppServer, CodexRun
        from collaboration_milestone_bridge import MilestoneBroker
        for mode in ("publish", "list", "status"):
            for accepted in (False, True):
                with self.subTest(mode=mode, accepted=accepted), simulated_time():
                    broker = MilestoneBroker()
                    args = {"mode": mode}
                    if mode == "publish":
                        args.update(milestone_id="private-candidate", artifact="private-artifact")
                    reason, route = ("accepted", "ready") if accepted else ("no_admitted_path", "no_verified_common_route")
                    def invoke(_task_id, arguments, active):
                        return broker.query(task, arguments,
                            lambda _: PublishObservation(accepted, reason, route, True), active=active)
                    server = CodexAppServer("codex", {}, lambda *_: None, collaboration_publish=invoke)
                    server._runs["task"] = CodexRun("task", thread_id="thread", turn_id="turn")
                    with patch.object(server, "_write_server_response") as write, self.assertLogs(level="ERROR"):
                        server._execute_dynamic_tool_call("task", {"id": 4},
                            {"tool": "collaboration_publish", "arguments": args}, {})
                    result = write.call_args.args[1]
                    self.assertFalse(result["success"])
                    payload = json.loads(result["contentItems"][0]["text"])
                    observation = payload["transport_observation"]
                    self.assertIsInstance(observation, dict)
                    self.assertEqual(mode, observation["phase"])
                    self.assertEqual(4, observation["publish_attempts"])
                    self.assertEqual(4 if accepted else 0, observation["accepted_publish_attempts"])
                    self.assertEqual({reason: 4}, observation["reason_counts"])
                    self.assertEqual(route, observation["latest_transport_observation"]["route_state_after_attempt"])
                    self.assertTrue(observation["latest_transport_observation"]["mqtt_connected_after_attempt"])
                    self.assertEqual("unknown", observation["remote_execution_state"])
                    self.assertFalse(observation["authenticated_response_received"])
                    self.assertEqual("transport_unconfirmed", payload["status"])
                    expected = {"publish": "SAME milestone_id", "list": "this read submitted no artifact",
                                "status": "no artifact was submitted"}[mode]
                    self.assertIn(expected, payload["error"])
                    if mode != "publish":
                        self.assertNotIn("outcome is uncertain", payload["error"])
                        self.assertNotIn("SAME milestone_id", payload["error"])
                    self.assertNotIn("private-", result["contentItems"][0]["text"])
                    self.assertFalse(server._runs["task"].finished)
                    self.assertEqual({}, broker._pending)

    def test_typed_transport_failures_cannot_silently_replace_observations_with_text(self):
        from collaboration_transport_feedback import PublicationRejected, ResponseUnconfirmed
        for error_type in (PublicationRejected, ResponseUnconfirmed):
            with self.assertRaises(TypeError):
                error_type("incorrect positional guidance")

    def test_untyped_errors_keep_existing_bounded_error_handling(self):
        from collaboration_transport_feedback import model_failure_result
        self.assertIsNone(model_failure_result(ValueError("private arbitrary error")))


if __name__ == "__main__":
    unittest.main()
