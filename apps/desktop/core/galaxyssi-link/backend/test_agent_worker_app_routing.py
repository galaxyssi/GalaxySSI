"""Ordinary App admission, durable original recipient and local fallback."""
import base64
from contextlib import ExitStack
from copy import deepcopy
import json
import os
import time
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch

from agent_execution_harness import execution_policy_for
from agent_request_snapshot import build_request_snapshot
from agent_task_manager import AgentTaskManager
from agent_worker_app_admission import dispatch_app_request
from agent_worker_mqtt import flush_worker_notifications
from agent_worker_protocol import AgentWorkerProtocol
from agent_worker_registry import WorkerAccessError
from agent_worker_routing import WorkerAppRouting, routing_for
from test_agent_worker_registry import WorkerFixture, peer
from test_agent_worker_local import png_attachment


class AppRoutingFixture(WorkerFixture):
    def setUp(self):
        super().setUp()
        self.enroll()
        self.protocol = AgentWorkerProtocol(self.registry)
        self.manager = AgentTaskManager(state_path=self.ledger.path)
        self.addCleanup(self.manager.model_work_pool.close)
        self.peers = {"route-a": self.peer, "app-a": peer("app-a"), "app-b": peer("app-b")}
        self.bridge = SimpleNamespace(agent_task_manager=self.manager, get_client=self.peers.get,
            _worker_enrollment_registry=self.registry, _worker_execution_protocol=self.protocol,
            _ensure_outbound_retry_thread=Mock())
        self.routing = routing_for(self.bridge, create=True)

    def enable(self, app="app-a"):
        self.routing.configure(app, ["route-a"])

    def args(self, task="task-one", app="app-a", attachments=None):
        prompt = "Reply exactly ROUTED_" + task + "."
        policy = execution_policy_for(prompt).public()
        snapshot = build_request_snapshot({"attachments": attachments or []}, model_id="gpt-5.6-sol", reasoning_effort="", policy=policy)
        return dict(task_id=task, app=app, conversation="same-chat", backend_conversation=app + ":same-chat",
            turn="turn-" + task, source_message="message-" + task, contact="codex", prompt=prompt,
            snapshot=snapshot, policy=policy, trace=[], trace_id="trace-" + task)

    def dispatch(self, **kwargs):
        return dispatch_app_request(self.bridge, **self.args(**kwargs))

    def poll(self, sequence=1):
        return self.protocol.poll(self.peer, self.source, dict(incarnation="boot-a", session_epoch=1,
            sequence=sequence, request_id="poll-" + str(sequence)))["job"]


class AppRoutingTest(AppRoutingFixture):
    def test_pairing_alone_does_not_route_or_create_a_task(self):
        self.assertIsNone(self.dispatch())
        self.assertIsNone(self.manager.get("task-one"))
        self.assertEqual([], self.protocol.notifications())

    def test_real_admission_preserves_two_apps_turns_and_results_without_local_execution(self):
        self.enable()
        self.enable("app-b")
        for task, app in (("one", "app-a"), ("two", "app-b")):
            admitted = self.dispatch(task=task, app=app)
            self.assertEqual("queued", admitted.status)
            self.assertTrue(admitted.storage_fenced)
        self.assertEqual(0, self.manager.model_work_pool.snapshot()["active"])
        self.assertEqual(0, self.manager.model_work_pool.snapshot()["pending"])
        self.connect()
        self.heartbeat()
        results = []
        for sequence, task, app in ((1, "one", "app-a"), (2, "two", "app-b")):
            job = self.poll(sequence)
            self.assertEqual([app, "same-chat", "turn-" + task, task, 1], job["lease"]["key"])
            self.assertIn("ROUTED_" + task, job["prompt"])
            self.assertEqual("worker-a", self.manager.get(task).public()["execution_view"]["location_id"])
            self.assertEqual("worker-a", self.protocol.queue.tasks.get(task)["execution_view"]["location_id"])
            self.assertNotIn("worker_execution_location", self.manager.get(task).public())
            self.protocol.report(self.peer, self.source, dict(incarnation="boot-a", session_epoch=1,
                lease=job["lease"], sequence=1, report=dict(status="completed", text="result-" + task, error="", current_step="")))
        self.bridge._build_republished_task_result = lambda value, route: dict(value, client_route_id=route)
        self.bridge._publish_or_queue_task_result = lambda mqtt, wire, value: results.append((wire["_client_route_id"], value)) or True
        self.bridge._publish_or_queue_task_event = Mock(return_value=True)
        flush_worker_notifications(self.bridge, None)
        self.assertEqual({("app-a", "one", "result-one"), ("app-b", "two", "result-two")},
            {(route, value["task_id"], value["result"]) for route, value in results})
        self.assertEqual([], self.protocol.notifications())

    def test_restart_observes_queued_task_and_preserves_recipient_identity(self):
        self.enable()
        self.dispatch()
        manager = AgentTaskManager(state_path=self.ledger.path)
        self.addCleanup(manager.model_work_pool.close)
        routing = WorkerAppRouting(self.protocol, self.peers.get)
        observed = manager.get("task-one")
        self.assertEqual(("queued", 1, False), (observed.status, observed.execution_generation,
            observed.execution_checkpoint["dispatch_started"]))
        self.assertTrue(routing.can_receive("task-one", self.peers["app-a"]))
        self.peers["app-a"] = dict(self.peers["app-a"], identity_fingerprint="d" * 64)
        self.assertFalse(routing.can_receive("task-one", self.peers["app-a"]))
        self.assertFalse(routing.can_receive("task-one", self.peers["app-b"]))
        self.assertIsNone(self.dispatch(task="next"))

    def test_repaired_worker_requires_a_new_explicit_route_policy(self):
        self.enable()
        self.peers["route-a"] = dict(self.peer, link_secret="d" * 64)
        self.registry.enroll(self.peers["route-a"], "worker-a", max_parallel=2, providers=["codex"])
        self.assertIsNone(self.dispatch())
        self.assertIsNone(self.manager.get("task-one"))
        self.enable()
        self.assertIsNotNone(self.dispatch())

    def test_full_executor_and_enrolled_target_are_required(self):
        self.peers["app-a"] = dict(self.peers["app-a"], access_profile="agent_only", access_scopes=[])
        with self.assertRaises(WorkerAccessError):
            self.enable()
        for routes in ([], ["missing"], ["route-a", "route-a"], ["app-b"]):
            with self.subTest(routes=routes), self.assertRaises(WorkerAccessError):
                self.routing.configure("app-b", routes)

    def test_disabled_policy_stops_new_admission_without_cancelling_old_task(self):
        self.enable()
        self.dispatch()
        self.routing.disable("app-a")
        self.assertIsNone(self.dispatch(task="next"))
        self.assertEqual("queued", self.manager.get("task-one").status)
        self.assertTrue(self.routing.can_receive("task-one", self.peers["app-a"]))

    def test_attachment_capability_failure_stays_local_before_admission(self):
        self.enable()
        for attachment in ({"mime_type": "application/pdf"}, dict(png_attachment(), sha256="wrong")):
            with self.subTest(mime=attachment["mime_type"]):
                self.assertIsNone(self.dispatch(attachments=[attachment]))
        self.assertIsNone(self.manager.get("task-one"))

    def test_verified_transferred_native_image_is_scoped_and_portable(self):
        self.enable()
        attachment = png_attachment()
        raw = base64.b64decode(attachment.pop("data_b64"))
        attachment["transfer_id"] = "input-transfer"
        path = self.ledger.path.parent / "input.png"
        path.write_bytes(raw)
        with patch("input_attachment_transfer.resolved_attachment_path", return_value=path) as resolve:
            self.assertIsNotNone(self.dispatch(attachments=[attachment]))
        self.assertEqual(dict(client_route_id="app-a", conversation_id="same-chat", task_id="task-one", turn_id="turn-task-one"), resolve.call_args.kwargs)
        self.connect()
        self.heartbeat()
        value = self.poll()["options"]["attachments"][0]
        self.assertEqual(raw, base64.b64decode(value["data_b64"]))
        self.assertEqual(attachment["sha256"], value["sha256"])

    def test_origin_and_queue_commit_together(self):
        self.enable()
        with patch.object(self.protocol, "_notify", side_effect=RuntimeError("disk failure")):
            with self.assertRaises(RuntimeError):
                self.dispatch()
        self.assertIsNone(self.manager.get("task-one"))
        with self.ledger.transaction(write=False) as connection:
            self.assertEqual(0, connection.execute("SELECT count(*) FROM agent_worker_origins").fetchone()[0])

    def test_oversized_prompt_never_poison_heads_the_worker_queue(self):
        self.enable()
        args = self.args()
        args["prompt"] = "x" * (256 * 1024 + 1)
        self.assertIsNone(dispatch_app_request(self.bridge, **args))
        self.assertIsNone(self.manager.get("task-one"))

    def test_cloud_budget_denial_cannot_be_bypassed_by_routing(self):
        self.enable()
        args = self.args()
        args["snapshot"]["options"]["task_budget"]["allow_cloud"] = False
        self.assertIsNone(dispatch_app_request(self.bridge, **args))
        self.assertIsNone(self.manager.get("task-one"))


class AppRoutingMqttTest(AppRoutingFixture):
    def module_context(self):
        import mqtt_bridge
        context = ExitStack()
        for name, value in dict(agent_task_manager=self.manager, get_client=lambda route, **_: self.peers.get(route),
                _worker_app_routing_cache=(str(self.ledger.path.resolve()), self.routing),
                _ensure_outbound_retry_thread=Mock()).items():
            context.enter_context(patch.object(mqtt_bridge, name, value, create=True))
        return context

    def test_normal_mqtt_entry_uses_queue_and_never_starts_local_codex(self):
        import mqtt_bridge
        self.enable()
        args = self.args()
        payload = dict(type="text", content=args["prompt"], agent_id="codex", contact_id="codex",
            client_route_id="app-a", conversation_id="same-chat", task_id="task-one",
            turn_id="turn-task-one", client_message_id="message-task-one", attachments=[])
        with self.module_context(), patch.object(self.manager, "create_external", side_effect=AssertionError("local execution")), \
                patch.object(mqtt_bridge, "_enqueue_task_event"):
            mqtt_bridge._start_remote_agent_task(None, {"scheme": "signal", "_client_route_id": "app-a"}, payload, [], args["prompt"], "text")
        self.assertEqual("queued", self.manager.get("task-one").status)
        self.connect()
        self.heartbeat()
        self.assertEqual(["app-a", "same-chat", "turn-task-one", "task-one", 1], self.poll()["lease"]["key"])

    def test_actual_phone_publish_blocks_old_result_after_app_repair(self):
        import mqtt_bridge
        self.enable()
        self.dispatch()
        changed = dict(self.peers["app-a"], identity_fingerprint="d" * 64)
        self.peers["app-a"] = changed
        with self.module_context(), patch.object(mqtt_bridge, "_wire_client", return_value=changed), \
                patch.object(mqtt_bridge, "_topics_for_client", return_value=SimpleNamespace(send="fixture")), \
                patch.object(mqtt_bridge, "_publish_to_registered_client") as publish:
            self.assertFalse(mqtt_bridge._publish_phone_payload(None, {"_client_route_id": "app-a"},
                {"type": "text", "task_id": "task-one", "content": "private old result"}))
        publish.assert_not_called()

    def test_api_authorization_precedes_policy_creation(self):
        from fastapi import FastAPI, HTTPException
        from fastapi.testclient import TestClient
        from agent_worker_routing_api import router
        app = FastAPI()
        app.include_router(router)
        with patch("main.require_desktop_api_token", side_effect=HTTPException(status_code=401)), \
                patch("agent_worker_routing_api.routing_for") as factory:
            response = TestClient(app).put("/api/agent/worker-routes/app-a", json={"worker_routes": ["route-a"]})
        self.assertEqual(401, response.status_code)
        factory.assert_not_called()

    def test_operator_api_configure_inspect_disable(self):
        from fastapi import FastAPI
        from fastapi.testclient import TestClient
        from agent_worker_routing_api import router
        app = FastAPI()
        app.include_router(router)
        with patch("agent_worker_routing_api.context", return_value=self.routing):
            client = TestClient(app)
            path = "/api/agent/worker-routes/app-a"
            self.assertEqual(200, client.put(path, json={"worker_routes": ["route-a"]}).status_code)
            self.assertTrue(client.get(path).json()["enabled"])
            self.assertNotIn("binding", json.dumps(client.get(path).json()))
            self.assertFalse(client.delete(path).json()["enabled"])
            self.assertEqual(422, client.put(path, json={"worker_routes": ["route-a"], "app_identity": "forged"}).status_code)


@unittest.skipUnless(os.name == "nt" and os.environ.get("GALAXYSSI_LIVE_WORKER_CODEX") == "1", "Real model opt-in required")
class AppRoutingLiveTest(AppRoutingFixture):
    def test_original_app_mqtt_entry_to_real_codex_text_image_and_original_results(self):
        import mqtt_bridge
        from agent_worker_controller import WorkerController
        from agent_worker_execution import WorkerProcessExecutor
        from agent_worker_local import WorkerExecutionJournal
        from agent_worker_mqtt import route_worker_payload
        from agent_worker_rpc import AgentWorkerRpcClient
        self.enable()
        self.enable("app-b")
        rpc = AgentWorkerRpcClient(self.peers.get, lambda peer, payload: route_worker_payload(
            self.bridge, None, {}, payload, client_route_id="route-a", source_id=self.source))
        self.addCleanup(rpc.close)
        self.bridge._publish_phone_payload = lambda mqtt, wire, payload: rpc.receive(self.peer, self.source, payload)
        executor = WorkerProcessExecutor(WorkerExecutionJournal(self.ledger), self.ledger.path.parent / "workers",
            max_workers=2, work_pool=self.manager.model_work_pool)
        self.addCleanup(executor.close)
        controller = WorkerController(rpc, self.peers.get, "route-a", self.ledger, executor, max_parallel=2)
        self.addCleanup(lambda: self.assertTrue(controller.stop()))
        marker = str(time.time_ns())
        tasks = [("text", "app-a", "Reply exactly ROUTED_TEXT_" + marker + ".", []),
            ("image", "app-b", "Read the image using native vision. Reply ROUTED_IMAGE_" + marker + " and its equation. No tools or search.", [png_attachment()])]
        with AppRoutingMqttTest.module_context(self), patch.object(self.manager, "create_external", side_effect=AssertionError("local model must not start")), \
                patch.object(mqtt_bridge, "_enqueue_task_event"):
            for task, app, prompt, attachments in tasks:
                payload = dict(type="text", content=prompt, agent_id="codex", contact_id="codex", client_route_id=app,
                    conversation_id="same-chat", task_id=task, turn_id="turn-" + task, client_message_id="message-" + task,
                    agent_invocation={"model_id": "gpt-5.6-sol"}, attachments=attachments)
                mqtt_bridge._start_remote_agent_task(None, {"scheme": "signal", "_client_route_id": app}, payload, [], prompt, "text")
        controller.start()
        deadline = time.monotonic() + 120
        while controller.snapshot()["completed_tasks"] < 2 and time.monotonic() < deadline:
            self.assertTrue(controller.is_alive(), controller.snapshot())
            time.sleep(0.05)
        self.assertEqual(2, controller.snapshot()["completed_tasks"], controller.snapshot())
        results = []
        self.bridge._build_republished_task_result = lambda value, route: dict(value, client_route_id=route)
        self.bridge._publish_or_queue_task_result = lambda mqtt, wire, value: results.append((wire["_client_route_id"], value)) or True
        self.bridge._publish_or_queue_task_event = Mock(return_value=True)
        flush_worker_notifications(self.bridge, None)
        self.assertEqual({("app-a", "text", "turn-text", 1), ("app-b", "image", "turn-image", 1)},
            {(route, value["task_id"], value["client_turn_id"], value["execution_generation"]) for route, value in results})
        self.assertIn("ROUTED_TEXT_" + marker, self.manager.get("text").result)
        self.assertIn("ROUTED_IMAGE_" + marker, self.manager.get("image").result)
        self.assertRegex(self.manager.get("image").result, r"2\s*[+\uff0b]\s*2\s*[=\uff1d]\s*4")
