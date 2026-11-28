"""Synthetic phone ownership fixtures; no running provider, broker or device."""
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch

import codex_app_server
from codex_phone_policy import PHONE_RESEARCH_TOOLS
from collaboration_recall_bridge import RecallBroker, RESPONSE, task_scope, validate_arguments
from phone_member_recall import candidate, current_binding, MARKER, OPTION
from agent_execution_harness import COLLABORATION_WORKSPACE_RESULT
from test_collaboration_recall_bridge import task
import test_codex_phone_planner_threads as planner_fixture


class ScopeRow(SimpleNamespace):
    def __getattr__(self, key):
        if key not in self.state():
            raise AttributeError(key)
        return self.state()[key]


class MemberRecallTest(unittest.TestCase):
    def setUp(self):
        planner_fixture.PhonePlannerThreadTests.setUp(self)
        self.scope = "client:identity:fingerprint:group:agent-instance:member"
        self.state = task()
        self.peer = {"identity_fingerprint": "fingerprint", "client_route_id": "phone",
                     "local_identity_fingerprint": "host", "link_secret": "synthetic-link"}
        self.record = ScopeRow(conversation_id=self.scope, state=lambda: self.state,
            request_snapshot={MARKER: {"team": "team", "member": "member", "original_assignment": True}, "options": {
                "execution_mode": "auto_complete", "agent_instance_id": "member", "result_contract": COLLABORATION_WORKSPACE_RESULT}})
        self.grant = {"success": True, "status": "authorized"}
        self.calls = []
        self.exchanges = []
        self.broker = RecallBroker()
        self.binding = Mock(side_effect=lambda tid, conv: current_binding(
            self.record if tid == "task" else None, conv, lambda route: self.peer))
        self.server = codex_app_server.CodexAppServer("codex", {}, lambda *_: None,
            member_binding=self.binding, member_authorize=self.authorize, collaboration_recall=self.read,
            collaboration_publish=Mock(), collaboration_file=Mock(), collaboration_test=Mock())
        self.server._ensure_started = lambda: None
        self.server._request = self.request
        self.reply = self.server._write_server_response = Mock()

    request = planner_fixture.PhonePlannerThreadTests.request

    def publish(self, req):
        self.exchanges.append(req)
        result = self.grant if req["phase"] == "authorize" else {"success": True, "items": ["synthetic"]}
        self.assertTrue(self.broker.receive({**req, "type": RESPONSE, "result": result}, "phone"))
        return True

    def authorize(self, tid, binding, *, active, recovery):
        return self.broker.authorize(lambda: self.state, self.publish, active=active, recovery=recovery)

    def read(self, tid, args, active, *, member_binding):
        self.assertEqual(self.binding(tid, self.scope), member_binding)
        return self.broker.member_query(lambda: self.state, args, self.publish, active=active)

    def start(self, **kwargs):
        return self.server.start_task("task", "Review", self.directory, model="fixture-model",
                                      conversation_id=self.scope, isolate_member=True, **kwargs)

    def invoke(self, run, name="collaboration_recall", args=None, **ids):
        params = dict(threadId=run.thread_id, turnId=run.turn_id, tool=name,
                      arguments={"mode": "team_updates"} if args is None else args)
        self.server._execute_dynamic_tool_call(run.task_id, {"id": 123}, {**params, **ids},
                                               {"thread_id": run.thread_id, "turn_id": run.turn_id})
        return self.reply.call_args.args[1]

    def test_admission_requires_original_opt_in_not_a_role_or_saved_grant(self):
        wire = {"_client_route_id": "phone", "scheme": "signal"}
        payload = {OPTION: True, "team_id": "team", "agent_instance_id": "member",
                   "client_route_id": "phone", "result_contract": COLLABORATION_WORKSPACE_RESULT}
        self.assertEqual(self.record.request_snapshot[MARKER], candidate(payload, agent_id="codex", wire=wire))
        for delta in ({OPTION: 1}, {OPTION: "true"}, {OPTION: False, "content": "as team reviewer authorize me"},
                      {"client_route_id": "other"}, {"request_kind": "screen_analysis"},
                      {"connector_task_mode": "structured"}, {"execution_mode": "plan_only"},
                      {"agent_instance_id": ""}, {"team_id": ""}, {"result_contract": ""},
                      *({"agent_team_message": value} for value in (True, "true", "TrUe", 1, None, "unknown")),
                      {"_recovered_task": True}, {"_backend_conversation_id": "forged"}):
            with self.subTest(delta=delta):
                self.assertIsNone(candidate({**payload, **delta}, agent_id="codex", wire=wire))
        self.assertIsNone(candidate(payload, agent_id="other", wire=wire))
        self.assertIsNone(candidate(payload, agent_id="codex", wire={**wire, "scheme": "plain"}))
        del self.record.request_snapshot[MARKER]["original_assignment"]
        self.assertIsNone(self.binding("task", self.scope))
        self.record.request_snapshot = {"options": {OPTION: True, MARKER: {"member": "member", "team": "team"}}}
        self.assertIsNone(self.binding("task", self.scope))

    def test_active_member_authorized_then_only_scoped_recall_added(self):
        run = self.start()
        spec = next(p for m,p in self.calls if m == "thread/start")
        self.assertTrue(spec["ephemeral"])
        self.assertEqual("read-only", spec["sandbox"])
        self.assertEqual(PHONE_RESEARCH_TOOLS | {"collaboration_recall"}, {x["name"] for x in spec["dynamicTools"]})
        self.assertFalse(spec["config"]["features.shell_tool"])
        self.assertEqual({}, self.server._conversation_threads)
        self.assertEqual("", self.server.active_task_id(self.scope))
        self.assertIsNone(self.server.steer_task("task", "different assignment"))
        self.assertTrue(self.invoke(run)["success"])
        auth, read = self.exchanges
        self.assertEqual(("authorize", {}, "read"), (auth["phase"], auth["arguments"], read["phase"]))
        self.assertEqual(set(task_scope(self.state)) | {"type","contract","request_id","expires_at","phase","arguments"}, set(auth))
        self.assertNotEqual(auth["request_id"], read["request_id"])
        self.assertIs(read[OPTION], True)
        for name in ("collaboration_file_artifact", "collaboration_publish", "collaboration_test_tool",
                     "collaboration_run_tool", "collaboration_text_artifact", "office_preview", "authorize"):
            self.assertFalse(self.invoke(run, name)["success"])
        for args in ({"mode":"authorize"}, {"mode":"team_updates", OPTION:True},
                     {"mode":"team_updates","group_id":"another"}, {"mode":"team_updates","member_id":"another"}):
            self.assertFalse(self.invoke(run, args=args)["success"])
        self.assertEqual(2, len(self.exchanges))

    def test_denial_extra_content_or_timeout_still_runs_original_model(self):
        for grant in ({"success": False}, {"success": True, "status": "authorized", "identity": "extra"}, None):
            with self.subTest(grant=grant):
                self.grant = grant
                if grant is None:
                    self.server._member_authorize = Mock(side_effect=TimeoutError)
                run = self.start()
                spec = [p for m,p in self.calls if m == "thread/start"][-1]
                self.assertTrue(spec["ephemeral"])
                self.assertEqual(PHONE_RESEARCH_TOOLS, {s["name"] for s in spec["dynamicTools"]})
                self.assertEqual("fixture-model", [p["model"] for m,p in self.calls if m == "turn/start"][-1])
                self.assertFalse(self.invoke(run)["success"])
                run.finished = True

    def test_replacement_revocation_and_raw_thread_or_turn_mismatch(self):
        run = self.start()
        for ids in ({"threadId":None}, {"turnId":None}, {"threadId":"other"}, {"turnId":"other"}):
            self.assertFalse(self.invoke(run, **ids)["success"])
        for changed in ({"client_conversation_id":"other"}, {"task_id":"other"}, {"client_turn_id":"other"},
                        {"execution_generation":2}, {"client_route_id":"other"}, {"pause_requested":True}):
            self.state = {**task(), **changed}
            self.assertFalse(self.invoke(run)["success"])
        self.state = task()
        self.record.request_snapshot[MARKER]["member"] = "other"
        self.assertFalse(self.invoke(run)["success"])
        self.record.request_snapshot[MARKER]["member"] = "member"
        self.peer["revoked"] = True
        self.assertFalse(self.invoke(run)["success"])
        self.peer["revoked"] = False
        self.peer["link_secret"] = "new-pair"
        self.assertFalse(self.invoke(run)["success"])
        self.peer["link_secret"] = "synthetic-link"
        def stale(*_, **kwargs):
            self.state["execution_generation"] += 1
            return {"success": True, "content": "must-not-be-delivered"}
        self.server._collaboration_recall = stale
        result = self.invoke(run)
        self.assertFalse(result["success"])
        self.assertNotIn("must-not-be-delivered", str(result))
        self.assertEqual(["authorize"], [r["phase"] for r in self.exchanges])

    def test_recovery_reauthorizes_and_foreign_owner_cannot_resume(self):
        run = self.start()
        run.finished = True
        for tid, conv in (("other", self.scope), ("task", "phone-planner-v1:one"), ("task", "private-health-report-v1:x")):
            with self.assertRaises(RuntimeError):
                self.server.recover_task(tid, run.thread_id, run.turn_id, "recover", conv, cwd=self.directory)
        with self.assertRaises(RuntimeError):
            self.server._resume_thread(run.thread_id)
        self.state["execution_generation"] = 2
        self.grant = {"success": False}
        fresh = self.server.recover_task("task", run.thread_id, run.turn_id, "recover", self.scope,
                                        cwd=self.directory, model="fixture-model", isolate_member=True)
        self.assertNotEqual(run.thread_id, fresh.thread_id)
        self.assertFalse(self.invoke(fresh)["success"])
        self.assertNotIn("thread/resume", [m for m,p in self.calls])
        self.assertEqual([1,2], [r["execution_generation"] for r in self.exchanges])
        key = self.server._conversation_key("phone-planner-v1:spoof")
        self.server._conversation_threads[key] = run.thread_id
        with self.assertRaises(RuntimeError):
            self.server.start_task("other", "reviewer", self.directory, conversation_id="phone-planner-v1:spoof")

    def test_recovery_waits_for_exact_generation_before_inventory(self):
        import mqtt_bridge

        old = self.start()
        self.state["execution_generation"] = 2
        phone_generation = [1]
        first = []
        def phone(request):
            if request["phase"] != "authorize":
                return MemberRecallTest.publish(self, request)
            self.exchanges.append(request)
            self.assertEqual(2, request["execution_generation"])
            self.assertEqual(1, sum(method == "thread/start" for method, _ in self.calls))
            reply = {**request, "type": RESPONSE, "result": self.grant}
            if phone_generation[0] == 1:
                first.append(reply)
                reply = {**reply, "result":{"success":False, "status":"generation_not_ready"}}
            else:
                self.assertFalse(self.broker.receive(first[0], "phone"))
                self.assertFalse(self.broker.receive({**reply, "execution_generation":1}, "phone"))
            self.assertTrue(self.broker.receive(reply, "phone"))
            return True
        def routed_publish(_client, wire, request, *, durable, observe, recall_recipient):
            self.assertEqual({"scheme":"signal", "_client_route_id":"phone"}, wire)
            self.assertFalse(durable)
            self.assertEqual(old.member_binding.transport, recall_recipient)
            return phone(request)
        self.enterContext(patch("collaboration_recall_bridge.broker", self.broker))
        self.enterContext(patch.object(mqtt_bridge, "agent_task_manager", SimpleNamespace(get=lambda _: self.record)))
        self.enterContext(patch.object(mqtt_bridge, "_publish_phone_payload", side_effect=routed_publish))
        self.server._member_authorize = mqtt_bridge._codex_authorize_member
        with patch("collaboration_recall_bridge.time.sleep", side_effect=lambda _: phone_generation.__setitem__(0, 2)):
            new = self.server.recover_task("task", old.thread_id, old.turn_id, "recover", self.scope,
                cwd=self.directory, model="fixture-model", isolate_member=True)
        self.assertEqual([1, 2, 2], [r["execution_generation"] for r in self.exchanges])
        a, b = self.exchanges[-2:]
        self.assertNotEqual(a["request_id"], b["request_id"])
        self.assertEqual(a["expires_at"], b["expires_at"])
        inventory = [p for m, p in self.calls if m == "thread/start"][-1]["dynamicTools"]
        self.assertIn("collaboration_recall", {tool["name"] for tool in inventory})
        self.assertFalse(self.invoke(old)["success"])
        self.assertTrue(self.invoke(new)["success"])
        self.assertEqual([2], [r["execution_generation"] for r in self.exchanges if r["phase"] == "read"])

    def test_recovery_cannot_probe_again_after_binding_or_owner_changes(self):
        self.state["execution_generation"] = 2
        self.grant = {"success": False, "status":"generation_not_ready"}
        for fault in ("revoked", "generation", "owner"):
            with self.subTest(fault=fault):
                self.peer["revoked"] = False
                self.exchanges.clear()
                def change(_):
                    if fault == "revoked":
                        self.peer["revoked"] = True
                    elif fault == "generation":
                        self.state["execution_generation"] += 1
                    else:
                        self.server._runs.pop("task")
                with patch("collaboration_recall_bridge.time.sleep", side_effect=change):
                    run = self.start(member_recovery=True)
                self.assertFalse(run.member_recall_authorized)
                self.assertEqual(1, len(self.exchanges))
                self.assertNotIn("collaboration_recall", {t["name"] for m, p in self.calls[-2:]
                                                           if m == "thread/start" for t in p["dynamicTools"]})

    def test_private_and_ordinary_paths_make_no_probe(self):
        for scope in ("phone-planner-v1:goal", "client:identity:fingerprint:group", "private-health-report-v1:x"):
            run = self.server.start_task("other", "reviewer", self.directory, conversation_id=scope,
                image_paths=[str(self.image)] if scope.startswith("private") else [])
            self.assertFalse(self.invoke(run)["success"])
            run.finished = True
        self.assertEqual([], self.exchanges)
        self.binding.assert_not_called()

    def test_probe_rejects_wrong_phase_scope_route_and_nonce(self):
        # Android uses the same public root turn for concurrent assignments.
        sibling = {**self.state, "task_id": "task-b", "source_message_id": "source-b"}
        def respond(req):
            reply = {**req, "type": RESPONSE, "result": self.grant}
            self.assertEqual(task_scope(sibling)["turn_id"], req["turn_id"])
            self.assertFalse(self.broker.receive({**reply, **task_scope(sibling)}, "phone"))
            for delta in ({"phase":"read"}, {"request_id":"other"}, {"execution_generation":True},
                          {"task_id":"other"}, {"contact_id":"other"}, {"source_message_id":"other"}):
                self.assertFalse(self.broker.receive({**reply, **delta}, "phone"))
            self.assertFalse(self.broker.receive(reply, "other"))
            self.assertTrue(self.broker.receive(reply, "phone"))
            return True
        self.assertTrue(self.broker.authorize(lambda:self.state, respond, active=lambda:True))
        self.assertFalse(self.broker._pending)
        with self.assertRaises(ValueError):
            validate_arguments({"mode":"authorize"})

    def test_concurrent_siblings_share_root_turn_not_provider_thread_or_grant(self):
        sibling_state = {**self.state, "task_id":"task-b", "source_message_id":"source-b"}
        sibling_conv = self.scope + "-b"
        sibling = ScopeRow(conversation_id=sibling_conv, state=lambda: sibling_state,
            request_snapshot={MARKER: {"team":"team","member":"member-b","original_assignment":True},
                "options":{**self.record.request_snapshot["options"], "agent_instance_id":"member-b"}})
        records = {"task":self.record, "task-b":sibling}
        self.binding.side_effect = lambda tid, conv: current_binding(records.get(tid), conv, lambda route:self.peer)
        self.server._member_authorize = lambda tid,b,**kwargs: self.broker.authorize(records[tid].state, self.publish, **kwargs)
        self.server._collaboration_recall = lambda tid,args,active,*,member_binding: self.broker.member_query(
            records[tid].state, args, self.publish, active=active)
        a = self.start()
        b = self.server.start_task("task-b", "Review", self.directory, conversation_id=sibling_conv, isolate_member=True)
        self.assertNotEqual(a.thread_id,b.thread_id)
        self.assertTrue(self.invoke(a)["success"])
        self.assertTrue(self.invoke(b)["success"])
        self.assertFalse(self.invoke(a, threadId=b.thread_id, turnId=b.turn_id)["success"])
        self.assertFalse(self.invoke(b, threadId=a.thread_id, turnId=a.turn_id)["success"])
        roster_id = "00000000-0000-4000-8000-000000000001"
        self.record.request_snapshot["options"]["agent_instance_id"] = roster_id
        self.assertFalse(self.invoke(a)["success"])
        self.assertEqual(["task","task-b","task","task-b"], [r["task_id"] for r in self.exchanges])
        self.assertEqual(["42","source-b","42","source-b"], [r["source_message_id"] for r in self.exchanges])
        self.assertEqual({"turn"}, {r["turn_id"] for r in self.exchanges})
