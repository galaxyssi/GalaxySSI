import unittest
from unittest.mock import patch

from collaboration_tool_test_bridge import CONTRACT, REQUEST, RESPONSE, ToolTestBroker, tool_spec, validate_arguments
from codex_app_server import CodexAppServer, CodexRun


def task():
    return dict(task_id="task", client_route_id="phone", client_conversation_id="group", client_turn_id="turn",
                source_message_id="42", contact_id="contact", agent_id="codex", status="running", execution_generation=1)


def args():
    return {"mode": "start", "execution_id": "candidate-v1", "timeout_ms": 10000,
            "tool_test_plan": {"object_id": "a" * 64, "revision": 1, "sha256": "b" * 64}}


class SavedToolTestBridgeTest(unittest.TestCase):
    def test_explicit_tool_uses_original_native_runtime_not_shell_claim(self):
        self.assertEqual("collaboration_test_tool", tool_spec()["name"])
        self.assertIn("not passed", tool_spec()["description"])
        self.assertIn("not a security sandbox", tool_spec()["description"])
        self.assertIn("workspace.kind=executable_tool", tool_spec()["description"])
        self.assertIn("body.tool_test_plan", tool_spec()["description"])
        self.assertIn("record_validation", tool_spec()["description"])
        self.assertEqual(args(), validate_arguments(args()))
        for mode in ("status", "cancel"):
            value = {"mode": mode, "execution_id": "candidate-v1"}
            self.assertEqual(value, validate_arguments(value))

    def test_authority_code_and_type_overrides_rejected_before_transport(self):
        bad = [None, [], {}, {**args(), "group_id": "other"}, {**args(), "source": "pass"},
               {**args(), "network_enabled": True}, {**args(), "timeout_ms": True}, {**args(), "timeout_ms": 1.0},
               {**args(), "timeout_ms": 1800001}, {**args(), "execution_id": "../other"},
               {**args(), "execution_id": "x" * 129}, {**args(), "mode": "status"}]
        bad += [{**args(), "tool_test_plan": {**args()["tool_test_plan"], "revision": value}} for value in (True, 1.0, 0, 2147483648)]
        for value in bad:
            with self.subTest(value=value):
                sent = []
                with self.assertRaises(ValueError):
                    ToolTestBroker().query(task, value, sent.append)
                self.assertEqual([], sent)

    def test_response_is_bound_to_authenticated_generation_and_phase(self):
        broker = ToolTestBroker()
        def publish(request):
            self.assertEqual(REQUEST, request["type"])
            self.assertEqual(CONTRACT, request["contract"])
            response = {**request, "type": RESPONSE, "result": {"success": True, "status": "queued"}}
            for changed in ({"phase": "status"}, {"execution_generation": 2}, {"contract": "wrong"}):
                self.assertFalse(broker.receive({**response, **changed}, "phone"))
            self.assertFalse(broker.receive(response, "another-phone"))
            self.assertTrue(broker.receive(response, "phone"))
            return True
        self.assertEqual("queued", broker.query(task, args(), publish)["status"])

    def test_transport_retries_same_execution_id_and_nonce(self):
        sent = []; broker = ToolTestBroker()
        def publish(request):
            sent.append(request)
            if len(sent) == 2:
                broker.receive({**request, "type": RESPONSE, "result": {"success": True, "status": "running"}}, "phone")
            return True
        from test_collaboration_recall_retry import simulated_time
        with simulated_time():
            self.assertEqual("running", broker.query(task, args(), publish)["status"])
        self.assertEqual(sent[0], sent[1])

    def test_failed_native_diagnostic_is_preserved_without_retry_or_relabeling(self):
        broker = ToolTestBroker()
        result = {"success": True, "status": "finished", "execution_id": "candidate-v1",
                  "result": {"native_status": "failed", "passed": None, "error": {
                      "code": "collaboration_tool_invalid", "record_validation": {
                          "code": "record_kind_mismatch", "path": "/reference/kind",
                          "expected": ["tool_test_plan"], "actual": "artifact"}}}}
        sent = []
        def publish(request):
            sent.append(request)
            self.assertTrue(broker.receive({**request, "type": RESPONSE, "result": result}, "phone"))
            return True
        self.assertEqual(result, broker.query(task, {"mode": "status", "execution_id": "candidate-v1"}, publish))
        self.assertEqual(1, len(sent))

    def test_timeout_retains_uncertain_outcome(self):
        with self.assertRaisesRegex(TimeoutError, "SAME execution_id"):
            ToolTestBroker().query(task, args(), lambda _: True, timeout=.005)

    def test_no_extra_outbox_for_expiring_rpc(self):
        from mqtt_query_delivery import needs_durable_outbox
        from signal_receive_dispatch import retry_safe
        self.assertFalse(needs_durable_outbox(REQUEST))
        self.assertTrue(retry_safe({"payload": {"type": RESPONSE}}))

    def server(self, sandbox="workspace-write"):
        calls = []; events = []
        def invoke(task_id, arguments, active):
            self.assertTrue(active())
            calls.append((task_id, arguments))
            return {"success": True, "status": "queued", "passed": None}
        server = CodexAppServer("codex", {}, lambda *event: events.append(event), collaboration_test=invoke)
        server._runs["task"] = CodexRun("task", thread_id="thread", turn_id="turn", sandbox=sandbox)
        return server, calls, events

    def test_dynamic_tool_reaches_callback_without_finishing_or_searching(self):
        server, calls, events = self.server()
        self.assertIn("collaboration_test_tool", [tool["name"] for tool in server._dynamic_tools])
        with patch.object(server, "_write_server_response") as reply:
            server._execute_dynamic_tool_call("task", {"id": 1}, {"tool": "collaboration_test_tool", "arguments": args()}, {})
        self.assertTrue(reply.call_args.args[1]["success"])
        self.assertEqual([("task", args())], calls)
        self.assertFalse(server._runs["task"].finished)
        self.assertFalse(server._runs["task"].research_observed)
        self.assertEqual("collaboration_tool_test_returned", events[-1][1]["trace_stage"])

    def test_read_only_cannot_be_used_to_escape_execution_policy(self):
        server, calls, _ = self.server("read-only")
        with patch.object(server, "_write_server_response") as reply:
            server._execute_dynamic_tool_call("task", {"id": 1}, {"tool": "collaboration_test_tool", "arguments": args()}, {})
        self.assertFalse(reply.call_args.args[1]["success"])
        self.assertEqual([], calls)

    def test_changed_turn_cannot_start_another_members_test(self):
        server, calls, _ = self.server()
        with patch.object(server, "_write_server_response") as reply:
            server._execute_dynamic_tool_call("task", {"id": 1}, {"tool": "collaboration_test_tool", "arguments": args()}, {"turn_id": "other"})
        self.assertFalse(reply.call_args.args[1]["success"])
        self.assertEqual([], calls)

    def test_read_only_can_recover_status_without_starting_code(self):
        server, calls, _ = self.server("read-only")
        values = {"mode": "status", "execution_id": "candidate-v1"}
        with patch.object(server, "_write_server_response") as reply:
            server._execute_dynamic_tool_call("task", {"id": 1}, {"tool": "collaboration_test_tool", "arguments": values}, {})
        self.assertTrue(reply.call_args.args[1]["success"])
        self.assertEqual([("task", values)], calls)


if __name__ == "__main__":
    unittest.main()
