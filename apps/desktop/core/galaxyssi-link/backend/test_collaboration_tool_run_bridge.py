import dataclasses
import unittest
from unittest.mock import patch

from agent_execution_harness import AgentExecutionMode
from collaboration_tool_test_bridge import RUN_TOOL, RESPONSE, ToolTestBroker, run_tool_spec, tool_spec, validate_arguments
from codex_app_server import CodexAppServer, CodexRun
from test_collaboration_tool_test_bridge import task, args as test_args


def args(record="tool_release"):
    return {"mode": "start", "execution_id": "reuse-v1", "timeout_ms": 10000,
            record: {"object_id": "a" * 64, "revision": 1, "sha256": "b" * 64},
            "parameters": {"values": [3, 1, 2], "options": {"stable": True}}}


class SavedToolRunBridgeTest(unittest.TestCase):
    def test_run_spec_is_distinct_from_testing_without_broadening_source_authority(self):
        spec = run_tool_spec()
        self.assertEqual(RUN_TOOL, spec["name"])
        self.assertIn("not scientific or goal success", spec["description"])
        self.assertIn("Network remains disabled", spec["description"])
        fields = spec["inputSchema"]["properties"]
        self.assertEqual({"mode", "execution_id", "timeout_ms", "tool_release", "capability_channel", "parameters"}, set(fields))
        self.assertIn("tool_test_plan", tool_spec()["inputSchema"]["properties"])
        for record in ("tool_release", "capability_channel"):
            self.assertEqual(args(record), validate_arguments(args(record), tool=RUN_TOOL))
        with self.assertRaises(ValueError):
            validate_arguments(test_args(), tool=RUN_TOOL)
        with self.assertRaises(ValueError):
            validate_arguments(args())

    def test_invalid_run_input_never_reaches_transport(self):
        value = args()
        bad = [{**value, key: content} for key, content in (
            ("source", "print(1)"), ("network_enabled", True), ("group_id", "other"),
            ("expected", 42), ("parameters", []), ("parameters", None),
            ("parameters", {"x": float("nan")}), ("parameters", {"x": float("inf")}),
            ("parameters", {"x": object()}), ("timeout_ms", True), ("timeout_ms", 1.0),
            ("capability_channel", value["tool_release"]), ("tool_test_plan", value["tool_release"]))]
        bad += [{**value, "tool_release": {**value["tool_release"], "revision": version}}
                for version in (True, 1.0, 0, 2147483648)]
        bad.append({key: content for key, content in value.items() if key != "parameters"})
        for content in bad:
            with self.subTest(content=repr(content)):
                sent = []
                with self.assertRaises(ValueError):
                    ToolTestBroker().query(task, content, sent.append)
                self.assertEqual([], sent)

    def test_transport_retries_identical_parameters_without_minting_an_execution(self):
        broker = ToolTestBroker()
        sent = []
        def publish(request):
            sent.append(request)
            if len(sent) == 2:
                response = {**request, "type": RESPONSE, "result": {"success": True, "status": "running", "execution_mode": "run"}}
                self.assertFalse(broker.receive({**response, "execution_generation": 2}, "phone"))
                self.assertFalse(broker.receive(response, "other"))
                self.assertTrue(broker.receive(response, "phone"))
            return True
        from test_collaboration_recall_retry import simulated_time
        with simulated_time():
            self.assertEqual("run", broker.query(task, args(), publish)["execution_mode"])
        self.assertEqual(sent[0], sent[1])
        self.assertEqual(args(), sent[0]["arguments"])

    def server(self):
        calls, events = [], []
        def invoke(task_id, arguments, active):
            self.assertTrue(active())
            calls.append(arguments)
            return {"success": True, "status": "queued", "execution_mode": "run"}
        server = CodexAppServer("codex", {}, lambda *event: events.append(event), collaboration_test=invoke)
        server._runs["task"] = CodexRun("task", thread_id="thread", turn_id="turn", sandbox="workspace-write")
        return server, calls, events

    def test_dynamic_run_reuses_explicit_execution_callback_not_web_search(self):
        server, calls, events = self.server()
        self.assertIn(RUN_TOOL, [tool["name"] for tool in server._dynamic_tools])
        with patch.object(server, "_write_server_response") as reply:
            server._execute_dynamic_tool_call("task", {"id": 1}, {"tool": RUN_TOOL, "arguments": args()}, {})
        self.assertTrue(reply.call_args.args[1]["success"])
        self.assertEqual([args()], calls)
        self.assertFalse(server._runs["task"].finished)
        self.assertFalse(server._runs["task"].research_observed)
        self.assertEqual("collaboration_tool_run_returned", events[-1][1]["trace_stage"])

    def test_read_only_plan_only_screen_and_changed_turn_cannot_start_run(self):
        for guard in ("read-only", "plan-only", "screen", "changed-turn", "finished"):
            server, calls, _ = self.server()
            run = server._runs["task"]
            if guard == "read-only":
                run.sandbox = "read-only"
            elif guard == "plan-only":
                run.execution_policy = dataclasses.replace(run.execution_policy, execution_mode=AgentExecutionMode.PLAN_ONLY)
            elif guard == "screen":
                run.execution_policy = dataclasses.replace(run.execution_policy, task_intent_signals=("screen_analysis",))
            elif guard == "finished":
                run.finished = True
            common = {"turn_id": "other"} if guard == "changed-turn" else {}
            with patch.object(server, "_write_server_response") as reply:
                server._execute_dynamic_tool_call("task", {"id": 1}, {"tool": RUN_TOOL, "arguments": args()}, common)
            self.assertFalse(reply.call_args.args[1]["success"], guard)
            self.assertEqual([], calls)

    def test_read_only_status_does_not_supply_parameters_or_start_execution(self):
        server, calls, _ = self.server()
        server._runs["task"].sandbox = "read-only"
        request = {"mode": "status", "execution_id": "reuse-v1"}
        with patch.object(server, "_write_server_response") as reply:
            server._execute_dynamic_tool_call("task", {"id": 1}, {"tool": RUN_TOOL, "arguments": request}, {})
        self.assertTrue(reply.call_args.args[1]["success"])
        self.assertEqual([request], calls)
        for mode in ("status", "cancel"):
            with self.assertRaises(ValueError):
                validate_arguments({**args(), "mode": mode}, tool=RUN_TOOL)

    def test_missing_executor_does_not_advertise_run_tool(self):
        server = CodexAppServer("codex", {}, lambda *_: None)
        self.assertNotIn(RUN_TOOL, [tool["name"] for tool in server._dynamic_tools])


if __name__ == "__main__":
    unittest.main()
