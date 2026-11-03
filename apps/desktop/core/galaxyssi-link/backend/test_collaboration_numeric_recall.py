"""Remote numeric counterexamples must remain exact, scoped, and read-only."""
import json
import unittest
from unittest.mock import patch

from collaboration_recall_bridge import RESPONSE, RecallBroker, task_scope, tool_spec, validate_arguments
from codex_app_server import CodexAppServer, CodexRun


FILTERS = ("failed", "all", "domain_error", "improved", "regressed", "error_reduced",
           "error_increased", "domain_recovered", "domain_failed")


def task():
    return dict(task_id="numeric-task", client_route_id="phone", client_conversation_id="group",
                client_turn_id="turn", source_message_id="42", contact_id="codex-contact",
                agent_id="codex", status="running", execution_generation=1)


def selectors(**changes):
    return dict(mode="numeric_cases", object_id="a" * 64, revision=2, sha256="b" * 64, **changes)


class CollaborationNumericRecallTest(unittest.TestCase):
    def test_tool_advertises_counterexample_paging_and_every_phone_filter(self):
        spec = tool_spec()
        properties = spec["inputSchema"]["properties"]
        self.assertIn("numeric_cases", properties["mode"]["enum"])
        self.assertEqual(list(FILTERS), properties["case_filter"]["enum"])
        for hint in ("mode=numeric_cases", "case_filter", "same trial", "next_cursor"):
            self.assertIn(hint, spec["description"])

    def test_exact_reference_and_opaque_cursor_are_preserved(self):
        self.assertEqual(selectors(), validate_arguments(selectors()))
        for case_filter in FILTERS:
            cursor = json.dumps({"sha256": "b" * 64, "case_filter": case_filter, "offset": 8000})
            arguments = selectors(case_filter=case_filter, cursor=cursor)
            self.assertEqual(arguments, validate_arguments(arguments))

    def test_missing_malformed_or_cross_mode_selectors_are_rejected_before_transport(self):
        good = selectors(case_filter="failed", cursor="")
        invalid = [{k: v for k, v in good.items() if k != required}
                   for required in ("object_id", "revision", "sha256")]
        invalid += [{**good, key: value} for key in ("object_id", "sha256")
                    for value in (None, True, 1, [], {}, "", "a" * 63, "A" * 64, "../private", "z" * 64)]
        invalid += [{**good, "revision": value} for value in (None, True, 0, -1, 2.0, "2", 2**31)]
        invalid += [{**good, "case_filter": value} for value in (None, True, [], {}, "", "unknown", "FAILED")]
        invalid += [{**good, "cursor": value} for value in (None, True, [], "x" * 513)]
        invalid += [{**good, key: value} for key, value in (("offset", 0), ("record_id", "c" * 64),
                    ("evidence_id", "c" * 64), ("topic", "tools"), ("query", "x"),
                    ("group_id", "other"), ("member_id", "other"), ("execute", True))]
        invalid += [{"mode": mode, "case_filter": "failed"}
                    for mode in tool_spec()["inputSchema"]["properties"]["mode"]["enum"] if mode != "numeric_cases"]
        for arguments in invalid:
            with self.subTest(arguments=arguments):
                published = []
                with self.assertRaises(ValueError):
                    RecallBroker().query(task, arguments, lambda request: published.append(request), timeout=.005)
                self.assertEqual([], published)

    def test_numeric_pages_round_trip_without_recomputation_or_completion_claim(self):
        broker = RecallBroker()
        cursor = json.dumps({"sha256": "b" * 64, "case_filter": "regressed", "offset": 8000})
        for page_cursor, next_cursor in (("", cursor), (cursor, None)):
            arguments = selectors(case_filter="regressed", cursor=page_cursor)
            result = dict(success=True, status="returned", content='{"cases":[', next_cursor=next_cursor,
                          matched_case_count=17, case_count=200,
                          source_reference={"object_id": "a" * 64, "revision": 2, "sha256": "b" * 64},
                          trust="host_numeric_replay_projection_not_independent_reference_truth_or_generalization")
            def publish(request):
                self.assertEqual(arguments, request["arguments"])
                self.assertEqual("read", request["phase"])
                for key, value in task_scope(task()).items():
                    self.assertEqual(value, request[key])
                response = {**request, "type": RESPONSE, "result": result}
                self.assertFalse(broker.receive(response, "other-phone"))
                self.assertFalse(broker.receive({**response, "execution_generation": 2}, "phone"))
                self.assertTrue(broker.receive(response, "phone"))
                return True
            self.assertEqual(result, broker.query(task, arguments, publish))
            self.assertEqual({}, broker._pending)

    def test_phone_rejection_is_not_changed_into_empty_or_passing_feedback(self):
        broker = RecallBroker()
        result = {"success": False, "status": "failed", "error": {"code": "object_unavailable",
                  "message": "Numeric trial is missing or isolated."}}
        def publish(request):
            broker.receive({**request, "type": RESPONSE, "result": result}, "phone")
            return True
        self.assertEqual(result, broker.query(task, selectors(), publish))
        self.assertEqual({}, broker._pending)

    def test_pause_cancels_pending_feedback_without_restarting_model_or_measurements(self):
        broker, state = RecallBroker(), task()
        requests = []
        def publish(request):
            requests.append(request)
            state["pause_requested"] = True
            return True
        with self.assertRaises(ValueError):
            broker.query(lambda: state, selectors(), publish, timeout=.005)
        self.assertEqual(1, len(requests))
        self.assertEqual({}, broker._pending)

    def test_codex_dynamic_tool_exposes_phone_counterexample_unchanged(self):
        broker, calls = RecallBroker(), []
        arguments = selectors(case_filter="domain_error", cursor="")
        result = dict(success=True, status="returned", content='{"cases":[{"id":"edge","observed":{"error":"division_by_zero"}}]}',
                      next_cursor=None, case_filter="domain_error")
        def recall(task_id, values, active):
            calls.append((task_id, values))
            def publish(request):
                broker.receive({**request, "type": RESPONSE, "result": result}, "phone")
                return True
            return broker.query(task, values, publish, active=active)
        server = CodexAppServer("codex", {}, lambda *_: None, collaboration_recall=recall)
        server._runs["numeric-task"] = CodexRun("numeric-task", thread_id="thread", turn_id="turn")
        with patch.object(server, "_write_server_response") as reply:
            server._execute_dynamic_tool_call("numeric-task", {"id": 3},
                                             {"tool": "collaboration_recall", "arguments": arguments}, {})
        self.assertTrue(reply.call_args.args[1]["success"])
        self.assertEqual(result, json.loads(reply.call_args.args[1]["contentItems"][0]["text"]))
        self.assertEqual([("numeric-task", arguments)], calls)
        self.assertFalse(server._runs["numeric-task"].research_observed)


if __name__ == "__main__":
    unittest.main()
