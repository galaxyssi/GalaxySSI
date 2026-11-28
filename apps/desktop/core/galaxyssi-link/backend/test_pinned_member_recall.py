"""Combined MQTT admission, native pin and scoped recall with synthetic endpoints."""
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

import codex_app_server as native
import collaboration_recall_bridge as recall
import mqtt_bridge as bridge
from agent_request_snapshot import restore_request_options
from agent_task_manager import AgentTask
from codex_phone_policy import PHONE_RESEARCH_TOOLS
from phone_member_recall import MARKER, OPTION
from test_mqtt_codex_steering import _SteeringTaskManager
from test_pinned_team_codex import MEMBER, MODEL


class MemberManager(_SteeringTaskManager):
    def create_external(self, **values):
        task = super().create_external(**values)
        task.request_snapshot = values["request_snapshot"]
        task.execution_policy = values["execution_policy"]
        task.matches_client_identity = AgentTask.matches_client_identity.__get__(task)
        return task

    def recovery_request(self, task_id):
        return self.get(task_id).request_snapshot

    def resume_external(self, task_id, on_event):
        return self.get(task_id)


class PinnedMemberRecallTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(self.enterContext(tempfile.TemporaryDirectory()))
        self.enterContext(patch.dict(os.environ, {"GALAXYSSI_WORKSPACE_ROOT": str(self.root),
                                                   "GALAXYSSI_STATE_DIR": str(self.root / "state")}))
        self.enterContext(patch.object(native, "CONVERSATION_THREADS_PATH", self.root / "threads.json"))
        peer = dict(client_route_id="client-1", identity_fingerprint="fixture-phone",
                    local_identity_fingerprint="fixture-host", link_secret="fixture-link")
        self.enterContext(patch.object(bridge, "get_client", return_value=peer))
        self.manager = MemberManager(instance_id=MEMBER["agent_instance_id"])
        self.enterContext(patch.object(bridge, "agent_task_manager", self.manager))
        self.enterContext(patch.object(bridge, "has_full_executor", return_value=True))
        self.worker = self.enterContext(patch("agent_worker_app_admission.dispatch_app_request"))
        self.handoff = self.enterContext(patch.object(bridge, "deliver_agent_sync"))
        self.enterContext(patch.object(bridge, "_enqueue_task_event"))
        self.enterContext(patch.object(bridge, "_publish_or_queue_task_result"))
        self.enterContext(patch.object(bridge, "codex_task_callbacks", {}))
        self.enterContext(patch("agent_gateway._agent_env", return_value={}))
        self.enterContext(patch("agent_gateway._find_codex_desktop_cli", return_value="unused"))
        self.enterContext(patch("agent_latency_hooks.trace_stage"))
        self.sessions = self.enterContext(patch("agent_conversation_sessions.agent_conversation_sessions")).return_value
        self.enterContext(patch("task_workspace.task_workspace", return_value=self.root))
        self.server = native.CodexAppServer("unused", {}, Mock(), member_binding=bridge._codex_member_binding,
            member_authorize=bridge._codex_authorize_member, collaboration_recall=bridge._codex_collaboration_recall)
        self.server._ensure_started = self.server.warm = Mock()
        self.server._watch_run = self.server._begin_host_config_guard = Mock()
        self.server._request = Mock(side_effect=self.provider)
        self.enterContext(patch.object(bridge, "_codex_server", return_value=self.server))
        self.broker = recall.RecallBroker()
        self.enterContext(patch.object(recall, "broker", self.broker))
        self.enterContext(patch.object(bridge, "_publish_phone_payload", side_effect=self.phone))
        self.exchanges, self.threads, self.turns = [], [], []
        self.authorized, self.provider_model = True, MODEL

    def provider(self, method, params, timeout):
        if method == "thread/start":
            self.threads.append(params)
            return {"thread": {"id": f"thread-{len(self.threads)}"}, "model": self.provider_model}
        if method == "turn/start":
            self.turns.append(params)
            return {"turn": {"id": f"turn-{len(self.turns)}"}}
        self.fail(f"Unexpected provider call: {method}")

    def phone(self, client, wire, request, *, durable, observe, recall_recipient):
        self.exchanges.append(request)
        self.assertFalse(durable)
        self.assertTrue(recall_recipient)
        self.assertEqual("client-1", wire["_client_route_id"])
        self.assertNotIn("team_id", request)
        self.assertNotIn("model_id", request)
        if request["phase"] == "authorize":
            self.assertNotIn(OPTION, request)
            result = {"success": self.authorized, "status": "authorized" if self.authorized else "unavailable"}
        else:
            self.assertEqual("read", request["phase"])
            self.assertIs(request[OPTION], True)
            result = {"success": True, "items": []}
        return self.broker.receive({**request, "type": recall.RESPONSE, "result": result}, "client-1")

    def dispatch(self):
        payload = {**MEMBER, OPTION: True, "type":"text", "contact_id":"codex", "agent_id":"codex",
            "client_message_id":"message-follow-up", "client_route_id":"client-1", "task_id":"task-follow-up",
            "conversation_id":"conversation-1", "turn_id":"phone-turn-follow-up", "execution_mode":"auto_complete"}
        bridge._start_remote_agent_task(None, {"scheme":"signal", "_client_route_id":"client-1"},
                                       payload, [], "Hello", "text")
        return self.manager.current

    def read(self, run):
        reply = self.server._write_server_response = Mock()
        self.server._execute_dynamic_tool_call(run.task_id, {"id":1},
            {"tool":"collaboration_recall", "arguments":{"mode":"team_updates"},
             "threadId":run.thread_id, "turnId":run.turn_id}, {"thread_id":run.thread_id, "turn_id":run.turn_id})
        return reply.call_args.args[1]["success"]

    def check_inventory(self, authorized):
        p = self.threads[-1]
        self.assertEqual(MODEL, p["model"])
        self.assertIs(p["allowProviderModelFallback"], False)
        self.assertIs(p["ephemeral"], True)
        self.assertEqual("read-only", p["sandbox"])
        for flag in ("features.multi_agent", "features.multi_agent_v2"):
            self.assertIs(p["config"][flag], False)
        self.assertEqual(PHONE_RESEARCH_TOOLS | ({"collaboration_recall"} if authorized else set()),
                         {x["name"] for x in p["dynamicTools"]})
        self.assertFalse(self.server._conversation_threads)

    def tearDown(self):
        self.worker.assert_not_called()
        self.handoff.assert_not_called()
        self.sessions.get.assert_not_called()
        self.sessions.put.assert_not_called()

    def test_authorized_original_then_denied_recovery_stays_on_exact_native_route(self):
        task = self.dispatch()
        first = self.server._runs[task.task_id]
        self.assertEqual(MODEL, task.execution_policy["pinned_codex_model"])
        options = restore_request_options(task.request_snapshot)
        self.assertEqual(MODEL, options["agent_invocation"]["model_id"])
        self.assertEqual(MEMBER["team_id"], options["team_id"])
        self.assertNotIn(OPTION, options)
        self.assertNotIn(MARKER, options)
        self.check_inventory(True)
        self.assertTrue(self.read(first))

        task.thread_id, task.turn_id = first.thread_id, first.turn_id
        task.status, task.execution_generation = "recovering", 2
        self.authorized = False
        bridge._resume_recovered_remote_task(None, vars(task))
        second = self.server._runs[task.task_id]
        self.assertNotEqual(first.thread_id, second.thread_id)
        self.check_inventory(False)
        self.assertFalse(self.read(first))
        self.assertFalse(self.read(second))
        self.assertEqual([MODEL, MODEL], [p["model"] for p in self.turns])
        self.assertEqual([("authorize",1), ("read",1), ("authorize",2)],
                         [(r["phase"],r["execution_generation"]) for r in self.exchanges])

        bridge._dispatch_codex_event(task.task_id, {"status":"completed", "result":
            '[GALAXYSSI_RECOVERY_ACTION_V1]\n{"version":1,"action":"switch_agent","target_agent_id":"claude"}'
            '\n[/GALAXYSSI_RECOVERY_ACTION_V1]'})
        self.assertEqual("failed", task.status)
        self.assertIn("handoff refused", task.error)

    def test_denied_original_runs_pinned_model(self):
        self.authorized = False
        task = self.dispatch()
        self.check_inventory(False)
        self.assertEqual([MODEL], [p["model"] for p in self.turns])
        self.assertFalse(self.read(self.server._runs[task.task_id]))
        self.assertEqual(["authorize"], [r["phase"] for r in self.exchanges])

    def test_grant_cannot_override_missing_or_substituted_provider_model(self):
        for acknowledgement in (None, "different-model"):
            with self.subTest(acknowledgement=acknowledgement):
                self.provider_model = acknowledgement
                self.manager.current = None
                task = self.dispatch()
                self.assertEqual("failed", task.status)
                self.assertIn(MODEL, task.error)
                self.assertIn("did not confirm", task.error)
                self.check_inventory(True)
                self.assertNotIn(task.task_id, self.server._runs)
        self.assertFalse(self.turns)
        self.assertEqual(["authorize", "authorize"], [r["phase"] for r in self.exchanges])
