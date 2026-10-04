import json
import hashlib
import unittest
from unittest.mock import Mock, patch

from collaboration_recall_bridge import CONTRACT, RESPONSE, TOOL, RecallBroker, task_scope, validate_arguments
from codex_app_server import CodexAppServer, CodexRun


def task(**changes):
    return dict(task_id="task", client_route_id="phone", client_conversation_id="group",
                client_turn_id="turn", source_message_id="42", contact_id="codex-contact", agent_id="codex",
                status="running", execution_generation=1, **changes)


class CollaborationRecallBridgeTest(unittest.TestCase):
    def test_evolution_selectors_are_read_only_and_scoped(self):
        for arguments in ({"mode": "evolution", "cursor": ""}, {"mode": "evolution_rules", "offset": 8000},
                          {"mode": "problems", "cursor": ""}):
            self.assertEqual(arguments, validate_arguments(arguments))
        for invalid in ({"mode": "evolution", "group_id": "other"},
                        {"mode": "evolution", "object_id": "a" * 64},
                        {"mode": "evolution_rules", "cursor": ""},
                        {"mode": "problems", "group_id": "other"},
                        {"mode": "problems", "offset": 0},
                        {"mode": "evolution_rules", "offset": -1}):
            with self.assertRaises(ValueError):
                validate_arguments(invalid)

    def test_evolution_recall_keeps_phone_task_binding(self):
        broker = RecallBroker()
        requests = []
        def publish(request):
            requests.append(request)
            broker.receive({**request, "type": RESPONSE, "result": {"success": True, "revisions": []}}, "phone")
            return True
        self.assertEqual([], broker.query(task, {"mode": "evolution"}, publish)["revisions"])
        self.assertEqual("group", requests[0]["conversation_id"])
        self.assertEqual({}, broker._pending)

    def test_publish_rejection_does_not_claim_phone_is_offline(self):
        broker = RecallBroker()
        with self.assertRaises(ConnectionError) as error:
            broker.query(task, {"mode": "workspace"}, lambda _: False)
        self.assertIn("connectivity is unconfirmed", str(error.exception))
        self.assertNotIn("phone is offline", str(error.exception))
        self.assertEqual({}, broker._pending)

    def test_problem_directory_round_trip_preserves_bound_phone_and_task(self):
        broker = RecallBroker()
        requests = []
        def publish(request):
            requests.append(request)
            result = {"success": True, "observations": [{"evidence_id": "a" * 64}],
                      "trust": "observed_symptoms_not_diagnosed_causes"}
            self.assertFalse(broker.receive({**request, "type": RESPONSE, "result": result}, "wrong-phone"))
            self.assertTrue(broker.receive({**request, "type": RESPONSE, "result": result}, "phone"))
            return True
        result = broker.query(task, {"mode": "problems", "cursor": ""}, publish)
        self.assertEqual("a" * 64, result["observations"][0]["evidence_id"])
        self.assertEqual("group", requests[0]["conversation_id"])
        self.assertEqual("turn", requests[0]["turn_id"])
        self.assertEqual({}, broker._pending)

    def test_archive_handoff_uses_exact_record_without_additional_authority(self):
        arguments = {"mode": "archive", "record_id": "a" * 64, "offset": 8000}
        self.assertEqual(arguments, validate_arguments(arguments))
        for invalid in ({"mode": "archive"}, {**arguments, "record_id": "../private"},
                        {**arguments, "object_id": "b" * 64}, {**arguments, "group_id": "other"}):
            with self.assertRaises(ValueError):
                validate_arguments(invalid)

    def test_round_trip_and_cleanup(self):
        broker = RecallBroker()
        requests = []
        def publish(request):
            requests.append(request)
            self.assertTrue(broker.receive({**request, "type": RESPONSE, "result": {"success": True, "content": "original"}}, "phone"))
            return True
        self.assertEqual({"success": True, "content": "original"}, broker.query(task, {"mode": "workspace"}, publish))
        self.assertEqual({}, broker._pending)
        self.assertEqual(CONTRACT, requests[0]["contract"])

    def test_wrong_peer_generation_scope_and_late_results_rejected(self):
        broker = RecallBroker()
        for malformed in (None, [], {}, {"request_id": {}}, {"request_id": []}):
            self.assertFalse(broker.receive(malformed, "phone"))
        results = []
        def publish(request):
            response = {**request, "type": RESPONSE, "result": {"success": True}}
            results.append(response)
            self.assertFalse(broker.receive(response, "other-phone"))
            for key in (*task_scope(task()).keys(), "request_id", "contract", "type"):
                changed = {**response, key: "wrong"}
                self.assertFalse(broker.receive(changed, "phone"), key)
            self.assertFalse(broker.receive({**response, "result": {"success": "true"}}, "phone"))
            self.assertFalse(broker.receive({**response, "result": {"success": True, "value": float("nan")}}, "phone"))
            self.assertFalse(broker.receive({**response, "result": {"success": True, "content": "x" * 262144}}, "phone"))
            self.assertTrue(broker.receive(response, "phone"))
            self.assertFalse(broker.receive(response, "phone"))
            return True
        broker.query(task, {"mode": "goal_contract"}, publish)
        self.assertFalse(broker.receive(results[0], "phone"))

    def test_no_model_supplied_authority_or_invalid_selectors(self):
        for args in ({"mode": "workspace", "group_id": "other"}, {"mode": "execute"},
                     {"mode": "goal_contract", "object_id": "x"}, {"mode": "workspace", "offset": -1},
                     {"mode": "workspace", "revision": True}, {"mode": "workspace", "cursor": "x" * 513}):
            with self.assertRaises(ValueError):
                validate_arguments(args)

    def test_timeout_offline_cancel_and_generation_change_release_waiter(self):
        for mode in ("timeout", "offline", "cancel", "generation", "paused", "completed"):
            broker = RecallBroker()
            state = task()
            live = [True]
            def publish(request):
                if mode == "generation": state["execution_generation"] = 2
                if mode in {"paused", "completed"}: state["status"] = mode
                if mode == "cancel": live[0] = False
                return mode != "offline"
            with self.assertRaises((TimeoutError, ConnectionError, ValueError), msg=mode):
                broker.query(lambda: state, {"mode": "workspace"}, publish, active=lambda: live[0], timeout=.005)
            self.assertEqual({}, broker._pending)

    def test_inactive_or_unscoped_task_never_publishes(self):
        broker = RecallBroker()
        for key, value in (("status", "completed"), ("client_route_id", ""), ("client_turn_id", ""),
                           ("execution_generation", True), ("agent_id", "claude"), ("pause_requested", True)):
            state = {**task(), key: value}
            with self.assertRaises(ValueError), patch("builtins.print") as publish:
                broker.query(lambda: state, {"mode": "workspace"}, publish)
            publish.assert_not_called()

    def test_codex_exposes_tool_and_does_not_label_recall_as_search(self):
        events, calls = [], []
        def recall(task_id, arguments, active):
            calls.append((task_id, arguments, active()))
            return {"success": True, "content": "original"}
        server = CodexAppServer("codex", {}, lambda task, event: events.append(event), collaboration_recall=recall)
        self.assertIn(TOOL, [tool["name"] for tool in server._dynamic_tools])
        self.assertEqual({"function"}, {tool.get("type") for tool in server._dynamic_tools})
        server._runs["task"] = CodexRun("task", thread_id="thread", turn_id="turn")
        with patch.object(server, "_write_server_response") as reply:
            server._execute_dynamic_tool_call("task", {"id": 3}, {"tool": TOOL, "arguments": {"mode": "workspace"}}, {})
        self.assertEqual([("task", {"mode": "workspace"}, True)], calls)
        self.assertTrue(reply.call_args.args[1]["success"])
        self.assertEqual("original", json.loads(reply.call_args.args[1]["contentItems"][0]["text"])["content"])
        self.assertEqual("collaboration_recall_completed", events[0]["trace_stage"])
        self.assertFalse(server._runs["task"].research_observed)

    def test_finished_codex_run_cannot_read(self):
        for common in ({}, {"turn_id": "old-turn"}, {"thread_id": "old-thread"}):
            recall = Mock()
            server = CodexAppServer("codex", {}, lambda *_: None, collaboration_recall=recall)
            server._runs["task"] = CodexRun("task", thread_id="thread", turn_id="turn", finished=not common)
            with patch.object(server, "_write_server_response") as reply:
                server._execute_dynamic_tool_call("task", {"id": 3}, {"tool": TOOL, "arguments": {"mode": "workspace"}}, common)
            self.assertFalse(reply.call_args.args[1]["success"])
            recall.assert_not_called()

    def test_original_is_returned_only_after_phone_confirms_delivery(self):
        broker, phases = RecallBroker(), []
        content = "\u8bc1\u636e\n\"quoted\"\U0001f600"
        delivery = {"receipt_id": "phone-nonce", "content_sha256": "d04a7261a11ea301be4dffc134a83f7bace52437f78289152f19f49d1f452db5"}
        args = {"mode": "evidence", "evidence_id": "a" * 64, "sha256": "b" * 64}
        def publish(request):
            phases.append(request["phase"])
            if request["phase"] == "read":
                result = {"success": True, "content": content, "delivery": delivery,
                          "host_read_coverage": {"complete": False}}
            else:
                self.assertEqual(delivery, request["delivery"])
                result = {"success": True, "status": "confirmed", "delivery": delivery,
                          "host_read_coverage": {"complete": True}}
            self.assertTrue(broker.receive({**request, "type": RESPONSE, "result": result}, "phone"))
            return True
        result = broker.query(task, args, publish)
        self.assertEqual(["read", "confirm"], phases)
        self.assertEqual(content, result["content"])
        self.assertTrue(result["host_read_coverage"]["complete"])
        self.assertNotIn("delivery", result)
        self.assertEqual({}, broker._pending)

    def test_missing_corrupt_lost_or_revoked_confirmation_never_returns_an_original(self):
        args = {"mode": "evidence", "evidence_id": "a" * 64, "sha256": "b" * 64}
        for fault in ("read_lost", "no_receipt", "corrupt_content", "confirm_lost", "wrong_phase", "revoked", "generation", "cancel"):
            broker, phases, state, live = RecallBroker(), [], task(), [True]
            delivery = {"receipt_id": "phone-nonce", "content_sha256": hashlib.sha256(b"original").hexdigest()}
            def publish(request):
                phase = request["phase"]
                phases.append(phase)
                if fault == "read_lost" or phase == "confirm" and fault == "confirm_lost": return True
                if phase == "read":
                    result = {"success": True, "content": "changed" if fault == "corrupt_content" else "original", "delivery": delivery}
                    if fault == "no_receipt": result.pop("delivery")
                    if fault == "generation": state["execution_generation"] = 2
                    if fault == "cancel": live[0] = False
                else:
                    result = {"success": fault != "revoked", "status": "confirmed", "delivery": delivery,
                              "host_read_coverage": {"complete": True}}
                response = {**request, "type": RESPONSE, "result": result}
                if phase == "confirm" and fault == "wrong_phase": response["phase"] = "read"
                accepted = broker.receive(response, "phone")
                self.assertEqual(not (phase == "confirm" and fault == "wrong_phase"), accepted)
                return True
            with self.assertRaises((ValueError, TimeoutError), msg=fault):
                broker.query(lambda: state, args, publish, active=lambda: live[0], timeout=.005)
            self.assertEqual({}, broker._pending)
            if fault in {"read_lost", "no_receipt", "corrupt_content", "generation", "cancel"}:
                self.assertEqual(["read"], phases)

    def test_evidence_reads_require_exact_browse_references(self):
        for args in ({"mode": "evidence", "evidence_id": "a" * 64},
                     {"mode": "evidence", "evidence_id": "a" * 64, "sha256": "x" * 64}):
            with self.assertRaises(ValueError): validate_arguments(args)


if __name__ == "__main__":
    unittest.main()
