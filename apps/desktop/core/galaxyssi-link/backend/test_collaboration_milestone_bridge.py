import json
import unittest
from unittest.mock import patch

from collaboration_milestone_bridge import CONTRACT, REQUEST, RESPONSE, MilestoneBroker, tool_spec, validate_arguments
from collaboration_recall_bridge import RESPONSE as READ_RESPONSE
from codex_app_server import CodexAppServer, CodexRun


def task():
    return dict(task_id="task", client_route_id="phone", client_conversation_id="group", client_turn_id="turn",
                source_message_id="42", contact_id="contact", agent_id="codex", status="running", execution_generation=1)


def args():
    return {"mode": "publish", "milestone_id": "candidate-v1", "artifact": '{"format":"galaxyssi.research-artifact.v1"}'}


class CollaborationMilestoneBridgeTest(unittest.TestCase):
    def test_transport_uses_caller_retry_without_a_second_outbox(self):
        from mqtt_query_delivery import needs_durable_outbox
        from signal_receive_dispatch import retry_safe
        self.assertFalse(needs_durable_outbox(REQUEST))
        self.assertTrue(retry_safe({"payload": {"type": RESPONSE}}))
        self.assertTrue(needs_durable_outbox("agent_task_event"))

    def test_tool_is_explicitly_separate_from_read_only_recall(self):
        spec = tool_spec()
        self.assertEqual("collaboration_publish", spec["name"])
        self.assertIn("not verification", spec["description"])
        self.assertIn("milestones:[saved IDs]", spec["description"])
        self.assertEqual(args(), validate_arguments(args()))
        unicode_id = {**args(), "milestone_id": "\U0001f4d6" * 80}
        self.assertEqual(unicode_id, validate_arguments(unicode_id))
        self.assertEqual({"mode": "list", "cursor": "opaque"}, validate_arguments({"mode": "list", "cursor": "opaque"}))
        self.assertEqual({"mode": "status"}, validate_arguments({"mode": "status"}))
        self.assertIn("not invalid artifact JSON", spec["description"])
        self.assertIn("may be omitted and decode as []", spec["description"])

    def test_minimal_envelope_reaches_phone_without_rewriting_retry_identity(self):
        artifact = json.dumps({"format": "galaxyssi.research-artifact.v1", "summary": "Measurements",
                              "workspace": [{"id": "data", "kind": "artifact", "title": "Observations",
                                             "body": {"content": "Original synthetic observations"}}]}, indent=2)
        arguments = {"mode": "publish", "milestone_id": "observations-v1", "artifact": artifact}
        broker = MilestoneBroker()
        def publish(request):
            self.assertEqual(arguments, request["arguments"])
            self.assertEqual(artifact, request["arguments"]["artifact"])
            return broker.receive({**request, "type": RESPONSE,
                                   "result": {"success": True, "status": "recorded", "assignment_completed": False}}, "phone")
        result = broker.query(task, arguments, publish)
        self.assertTrue(result["success"])
        self.assertFalse(result["assignment_completed"])

    def test_invalid_and_authority_fields_never_reach_transport(self):
        bad = [None, [], {}, {"mode": "read"}, {"mode": "list", "artifact": "x"},
               {"mode": "status", "member_id": "other"}, {"mode": "status", "artifact": "x"},
               {"mode": "list", "cursor": "x" * 513}, {"mode": "list", "cursor": None}]
        bad += [{**args(), key: value} for key, value in (
            ("milestone_id", ""), ("milestone_id", " x"), ("milestone_id", "x\n"),
            ("milestone_id", "x" * 161), ("milestone_id", "\U0001f4d6" * 81), ("artifact", {}), ("artifact", ""),
            ("artifact", "x" * 131072), ("artifact", "\u4e2d" * 50000),
            ("group_id", "other"), ("member_id", "other"), ("execute", True), ("cursor", ""))]
        for values in bad:
            with self.subTest(values=str(values)[:100]):
                sent = []
                with self.assertRaises(ValueError):
                    MilestoneBroker().query(task, values, sent.append)
                self.assertEqual([], sent)

    def test_scope_generation_phase_and_protocol_are_authenticated(self):
        broker = MilestoneBroker()
        result = {"success": True, "status": "recorded", "assignment_completed": False,
                  "revisions": [{"object_id": "a" * 64, "revision": 1, "sha256": "b" * 64}]}
        def publish(request):
            self.assertEqual(REQUEST, request["type"])
            self.assertEqual(CONTRACT, request["contract"])
            self.assertEqual(args(), request["arguments"])
            reply = {**request, "type": RESPONSE, "result": result}
            for changed in ({"type": READ_RESPONSE}, {"phase": "read"}, {"execution_generation": 2},
                            {"turn_id": "other"}, {"contract": "wrong"}):
                self.assertFalse(broker.receive({**reply, **changed}, "phone"))
            self.assertFalse(broker.receive(reply, "other-phone"))
            self.assertTrue(broker.receive(reply, "phone"))
            return True
        self.assertEqual(result, broker.query(task, args(), publish))
        self.assertEqual({}, broker._pending)

    def test_uncertain_delivery_requires_same_id_not_new_effect(self):
        broker = MilestoneBroker()
        sent = []
        with self.assertRaisesRegex(TimeoutError, "SAME milestone_id"):
            broker.query(task, args(), lambda request: sent.append(request) or True, timeout=.005)
        self.assertEqual(args(), sent[0]["arguments"])
        self.assertEqual({}, broker._pending)

    def test_status_reports_unavailability_without_inviting_artifact_repair(self):
        broker = MilestoneBroker()
        result = {"success": True, "status": "returned", "capability": {
            "publish_allowed": False, "reason_code": "assignment_not_enrolled", "grants_authority": False}}
        def publish(request):
            self.assertEqual("status", request["phase"])
            self.assertEqual({"mode": "status"}, request["arguments"])
            return broker.receive({**request, "type": RESPONSE, "result": result}, "phone")
        self.assertEqual(result, broker.query(task, {"mode": "status"}, publish))
        with self.assertRaisesRegex(TimeoutError, "no artifact was submitted"):
            broker.query(task, {"mode": "status"}, lambda request: True, timeout=.005)
        self.assertEqual({}, broker._pending)

    def test_status_read_is_not_reported_as_an_artifact_publication(self):
        events = []
        server = CodexAppServer("codex", {}, lambda *event: events.append(event),
            collaboration_publish=lambda *values: {"success": True, "status": "returned", "capability": {"publish_allowed": False}})
        run = CodexRun("task", thread_id="thread", turn_id="turn")
        server._runs["task"] = run
        with patch.object(server, "_write_server_response") as reply:
            server._execute_dynamic_tool_call("task", {"id": 1}, {"tool": "collaboration_publish", "arguments": {"mode": "status"}}, {})
        self.assertTrue(reply.call_args.args[1]["success"])
        self.assertEqual("Read assignment publication capability", events[-1][1]["current_step"])
        self.assertFalse(run.finished)

    def test_retries_keep_publication_identity_and_nonce(self):
        broker = MilestoneBroker(); sent = []
        def publish(request):
            sent.append(request)
            if len(sent) == 2:
                broker.receive({**request, "type": RESPONSE, "result": {"success": True, "status": "recorded"}}, "phone")
            return True
        from test_collaboration_recall_retry import simulated_time
        with simulated_time():
            self.assertTrue(broker.query(task, args(), publish)["success"])
        self.assertEqual(sent[0], sent[1])

    def test_pause_stops_delivery_and_phone_rejection_is_preserved(self):
        state = task(); broker = MilestoneBroker()
        def pause(request):
            state["pause_requested"] = True
            return True
        with self.assertRaises(ValueError):
            broker.query(lambda: state, args(), pause, timeout=.01)
        error = {"success": False, "status": "rejected", "reason": "Version conflict for exact object"}
        def reject(request):
            return broker.receive({**request, "type": RESPONSE, "result": error}, "phone")
        self.assertEqual(error, broker.query(task, args(), reject))

    def test_codex_publication_does_not_finish_worker_or_claim_search(self):
        events = []; calls = []
        def publish(task_id, arguments, active):
            self.assertTrue(active()); calls.append((task_id, arguments))
            return {"success": True, "status": "recorded", "assignment_completed": False}
        server = CodexAppServer("codex", {}, lambda *event: events.append(event), collaboration_publish=publish)
        run = CodexRun("task", thread_id="thread", turn_id="turn")
        server._runs["task"] = run
        with patch.object(server, "_write_server_response") as reply:
            server._execute_dynamic_tool_call("task", {"id": 1}, {"tool": "collaboration_publish", "arguments": args()}, {})
        self.assertTrue(reply.call_args.args[1]["success"])
        self.assertEqual([("task", args())], calls)
        self.assertFalse(run.finished); self.assertFalse(run.research_observed)
        self.assertEqual("running", events[-1][1]["status"])
        self.assertEqual("collaboration_publication_returned", events[-1][1]["trace_stage"])

    def test_changed_codex_turn_cannot_publish(self):
        calls = []
        server = CodexAppServer("codex", {}, lambda *_: None, collaboration_publish=lambda *values: calls.append(values))
        server._runs["task"] = CodexRun("task", thread_id="thread", turn_id="turn")
        with patch.object(server, "_write_server_response") as reply:
            server._execute_dynamic_tool_call("task", {"id": 1}, {"tool": "collaboration_publish", "arguments": args()}, {"turn_id": "other"})
        self.assertFalse(reply.call_args.args[1]["success"]); self.assertEqual([], calls)

    def test_assessment_preflight_preserves_exact_draft_and_phone_diagnostics(self):
        draft = '{\n "format": "galaxyssi.goal-assessment.v1", "criteria": []\n}'
        arguments = {"mode": "validate_assessment", "artifact": draft}
        self.assertIn("validate_assessment", tool_spec()["inputSchema"]["properties"]["mode"]["enum"])
        broker = MilestoneBroker()
        result = {"success": True, "status": "returned", "schema_valid": False, "json_syntax": "valid",
                  "failure": {"path": "$.criteria", "code": "invalid_type"}, "committed": False,
                  "goal_accepted": False, "assignment_completed": False}
        def publish(request):
            self.assertEqual("validate_assessment", request["phase"])
            self.assertEqual(arguments, request["arguments"])
            reply = {**request, "type": RESPONSE, "result": result}
            for changed in ({"phase": "publish"}, {"turn_id": "other"}, {"execution_generation": 2}):
                self.assertFalse(broker.receive({**reply, **changed}, "phone"))
            self.assertFalse(broker.receive(reply, "other-phone"))
            return broker.receive(reply, "phone")
        self.assertEqual(result, broker.query(task, arguments, publish))
        with self.assertRaisesRegex(TimeoutError, "no plan or artifact was submitted"):
            broker.query(task, arguments, lambda request: True, timeout=.005)
        self.assertEqual({}, broker._pending)

    def test_assessment_preflight_rejects_authority_and_malformed_arguments(self):
        arguments = {"mode": "validate_assessment", "artifact": "{}"}
        bad = [{**arguments, key: value} for key, value in (
            ("member_id", "other"), ("milestone_id", "new"), ("execute", True),
            ("artifact", {}), ("artifact", " "), ("artifact", "x" * 131072))]
        for values in bad:
            with self.subTest(values=str(values)[:100]):
                sent = []
                with self.assertRaises(ValueError):
                    MilestoneBroker().query(task, values, sent.append)
                self.assertEqual([], sent)

    def test_assessment_preflight_never_marks_publication_or_assignment_complete(self):
        for valid in (False, True, None):
            events = []
            server = CodexAppServer("codex", {}, lambda *event: events.append(event),
                collaboration_publish=lambda *values: {"success": valid is not None, "schema_valid": valid})
            run = CodexRun("task", thread_id="thread", turn_id="turn")
            server._runs["task"] = run
            with patch.object(server, "_write_server_response") as reply:
                server._execute_dynamic_tool_call("task", {"id": 1}, {"tool": "collaboration_publish",
                    "arguments": {"mode": "validate_assessment", "artifact": "{}"}}, {})
            self.assertEqual(valid is not None, reply.call_args.args[1]["success"])
            self.assertEqual("collaboration_assessment_preflight_returned", events[-1][1]["trace_stage"])
            self.assertIn("not submitted", events[-1][1]["current_step"])
            if valid is None:
                self.assertIn("unavailable", events[-1][1]["current_step"])
                self.assertNotIn("correction", events[-1][1]["current_step"])
            self.assertFalse(run.finished)
            self.assertFalse(run.research_observed)


if __name__ == "__main__":
    unittest.main()
