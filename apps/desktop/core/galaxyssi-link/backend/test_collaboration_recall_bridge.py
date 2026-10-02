import json
import unittest
from unittest.mock import Mock, patch

from collaboration_recall_bridge import CONTRACT, RESPONSE, TOOL, RecallBroker, task_scope, validate_arguments
from codex_app_server import CodexAppServer, CodexRun


def task(**changes):
    return dict(task_id="task", client_route_id="phone", client_conversation_id="group",
                client_turn_id="turn", source_message_id="42", contact_id="codex-contact", agent_id="codex",
                status="running", execution_generation=1, **changes)


class CollaborationRecallBridgeTest(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
