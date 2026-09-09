"""Authenticated worker wire operations, ordered reports and durable delivery."""
from copy import deepcopy
import json
from types import SimpleNamespace
from unittest.mock import Mock, patch

from agent_worker_leases import WorkerLeaseConflict
from agent_worker_mqtt import PROTOCOL, flush_worker_notifications, route_worker_payload
from agent_worker_protocol import AgentWorkerProtocol
from agent_worker_registry import WorkerAccessError
from test_agent_worker_queue import record
from test_agent_worker_registry import WorkerFixture, peer


class WorkerProtocolTest(WorkerFixture):
    def setUp(self):
        super().setUp()
        self.enroll()
        self.connect()
        self.heartbeat()
        self.protocol = AgentWorkerProtocol(self.registry)
        self.snapshot = record()
        self.protocol.queue.enqueue(self.snapshot, provider="codex", allowed_workers=["worker-a"])

    def payload(self, **changes):
        return dict(type="agent_worker_poll", protocol=PROTOCOL, incarnation="boot-a", session_epoch=1,
                    request_id="rpc-1", sequence=1) | changes

    def poll(self):
        return self.protocol.poll(self.peer, self.source, self.payload())

    def report(self, lease, *, sequence=1, status="running", text="Progress", **changes):
        payload = self.payload(type="agent_worker_report", lease=lease, sequence=sequence,
            report=dict(status=status, text=text, error="failure" if status == "failed" else "", current_step="step"))
        payload.update(changes)
        return self.protocol.report(self.peer, self.source, payload)

    def bridge(self):
        manager = SimpleNamespace(_run_events=SimpleNamespace(ledger=self.ledger),
            get=lambda task: SimpleNamespace(public=lambda: self.protocol.queue.tasks.get(task)))
        return SimpleNamespace(agent_task_manager=manager, get_client=lambda route: self.peer if route == "route-a" else {"client_route_id": route},
            _worker_enrollment_registry=self.registry, _worker_execution_protocol=self.protocol,
            _ensure_outbound_retry_thread=Mock(), _publish_phone_payload=Mock(),
            _publish_or_queue_task_event=Mock(return_value=True), _publish_or_queue_task_result=Mock(return_value=True),
            _build_republished_task_result=lambda task, route: {"type": "text", "content": task["result"],
                "task_id": task["task_id"], "client_route_id": route, "conversation_id": task["client_conversation_id"],
                "turn_id": task["client_turn_id"], "source_message_id": task["source_message_id"]})

    def test_poll_transmits_only_request_fields_and_private_capability_to_authorized_worker(self):
        result = self.poll()
        job = result["job"]
        self.assertEqual({"lease", "provider", "prompt", "options"}, set(job))
        self.assertEqual("codex", job["provider"])
        self.assertEqual(self.snapshot["prompt"], job["prompt"])
        self.assertEqual(["app-a", "chat-a", "turn-task-1", "task-1", 1], job["lease"]["key"])
        self.assertNotIn("_storage_revision", json.dumps(result))
        self.assertNotIn("link_secret", json.dumps(result))
        self.assertEqual(job, self.poll()["job"])

    def test_oversized_dispatch_rolls_back_grant_and_can_be_retried(self):
        with patch("agent_worker_protocol.restore_request_options", return_value={"extra": "x" * (512 * 1024)}):
            with self.assertRaises(WorkerAccessError):
                self.poll()
        self.assertEqual("queued", self.protocol.queue.tasks.get("task-1")["status"])
        self.assertEqual([], self.protocol.notifications())
        self.assertEqual(1, self.poll()["job"]["lease"]["epoch"])

    def test_poll_preserves_image_snapshot_without_copying_coordinator_credentials(self):
        image = record("image", attachments=[{"id": "fixture"}], request_snapshot={"version": 1, "options": {
            "attachments": [{"id": "fixture", "mime_type": "image/png", "data_b64": "fixture-data"}],
            "agent_invocation": {"model_id": "test-model", "reasoning_effort": "low"}, "api_key": "must-not-leak"}})
        self.protocol.queue.enqueue(image, provider="codex", allowed_workers=["worker-a"])
        self.poll()
        result = self.protocol.poll(self.peer, self.source, self.payload(sequence=2, request_id="rpc-2"))
        self.assertEqual("fixture-data", result["job"]["options"]["attachments"][0]["data_b64"])
        self.assertNotIn("api_key", json.dumps(result))

    def test_report_sequence_and_exact_retry_do_not_duplicate_events_or_change_revision(self):
        lease = self.poll()["job"]["lease"]
        self.assertFalse(self.report(lease)["replayed"])
        state = self.protocol.queue.tasks.get("task-1")
        event_count = self.ledger.event_count()
        self.assertTrue(self.report(lease, request_id="retry-new-transport")["replayed"])
        self.assertEqual(state, self.protocol.queue.tasks.get("task-1"))
        self.assertEqual(event_count, self.ledger.event_count())
        with self.assertRaises(WorkerLeaseConflict):
            self.report(lease, text="different")
        with self.assertRaises(WorkerLeaseConflict):
            self.report(lease, sequence=3)
        self.assertFalse(self.report(lease, sequence=2, status="completed", text="Final result")["replayed"])
        self.assertTrue(self.report(lease, sequence=2, status="completed", text="Final result")["replayed"])
        with self.assertRaises(WorkerLeaseConflict):
            self.report(lease, sequence=3)

    def test_report_cannot_replace_request_identity_policy_or_add_arbitrary_files(self):
        lease = self.poll()["job"]["lease"]
        report = dict(status="completed", text="done", error="", current_step="")
        for name in ("task_id", "client_route_id", "contact_id", "source_message_id", "execution_policy", "output_files"):
            with self.subTest(name=name), self.assertRaises(WorkerAccessError):
                self.report(lease, report={**report, name: "untrusted"})
        for index in range(5):
            changed = deepcopy(lease)
            changed["key"][index] = 2 if index == 4 else "other"
            with self.subTest(index=index), self.assertRaises(WorkerLeaseConflict):
                self.report(changed)
        self.assertEqual(self.snapshot["source_message_id"], self.protocol.queue.tasks.get("task-1")["source_message_id"])

    def test_report_requires_meaningful_terminal_output_and_rejects_oversized_text(self):
        lease = self.poll()["job"]["lease"]
        for status, text, error in (("completed", "", ""), ("completed", "ok", "failure"),
                                    ("failed", "", ""), ("running", "x" * 8193, "")):
            with self.subTest(status=status, text_length=len(text)), self.assertRaises(WorkerAccessError):
                self.report(lease, report=dict(status=status, text=text, error=error, current_step=""))

    def test_renew_and_report_reject_stale_incarnation_revocation_and_expired_lease(self):
        lease = self.poll()["job"]["lease"]
        renewed = self.protocol.renew(self.peer, self.source, self.payload(lease=lease))["lease"]
        self.assertEqual(lease["token"], renewed["token"])
        self.assertGreaterEqual(renewed["expires_at_ms"], lease["expires_at_ms"])
        with patch("agent_worker_leases._clock_ms", return_value=renewed["expires_at_ms"] + 1):
            with self.assertRaises(WorkerLeaseConflict):
                self.report(lease)
        self.connect(request_id="new-boot", expected_session_epoch=1, incarnation="boot-b")
        with self.assertRaises(WorkerAccessError):
            self.report(lease)
        self.heartbeat(incarnation="boot-b", session_epoch=2)
        with self.assertRaises(WorkerLeaseConflict):
            self.report(lease, incarnation="boot-b", session_epoch=2)

    def test_result_and_notification_checkpoint_rollback_together_on_storage_failure(self):
        lease = self.poll()["job"]["lease"]
        self.protocol.acknowledge_notification("task-1", 1, 1)
        before = self.protocol.queue.tasks.get("task-1")
        with patch.object(self.protocol, "_notify", side_effect=RuntimeError("disk failure")):
            with self.assertRaises(RuntimeError):
                self.report(lease, status="completed")
        self.assertEqual(before, self.protocol.queue.tasks.get("task-1"))
        self.assertEqual([], self.protocol.notifications())
        self.assertFalse(self.report(lease, status="completed")["replayed"])

    def test_another_enrolled_worker_cannot_use_a_copied_lease(self):
        lease = self.poll()["job"]["lease"]
        other = peer("other-worker-route")
        self.registry.enroll(other, "worker-b", max_parallel=1, providers=["codex"])
        self.registry.connect(other, other["signal_name"], dict(incarnation="boot-a", request_id="other-connect",
            expected_session_epoch=0, providers=["codex"]))
        self.registry.heartbeat(other, other["signal_name"], dict(incarnation="boot-a", session_epoch=1,
            sequence=1, available_slots=1))
        with self.assertRaises(WorkerLeaseConflict):
            self.protocol.renew(other, other["signal_name"], self.payload(lease=lease))
        with self.assertRaises(WorkerLeaseConflict):
            self.protocol.report(other, other["signal_name"], self.payload(lease=lease,
                report=dict(status="completed", text="forged", error="", current_step="")))
        self.assertEqual("running", self.protocol.queue.tasks.get("task-1")["status"])

    def test_notifications_survive_restart_and_route_to_original_app_not_worker(self):
        lease = self.poll()["job"]["lease"]
        self.report(lease, status="completed", text="Result for App A")
        self.protocol = AgentWorkerProtocol(self.registry)
        bridge = self.bridge()
        bridge._publish_or_queue_task_result.return_value = False
        flush_worker_notifications(bridge, None)
        self.assertEqual(1, len(self.protocol.notifications()))
        bridge._publish_or_queue_task_result.return_value = True
        flush_worker_notifications(bridge, None)
        self.assertEqual([], self.protocol.notifications())
        wire, message = bridge._publish_or_queue_task_result.call_args.args[1:]
        self.assertEqual("app-a", wire["_client_route_id"])
        self.assertEqual(self.snapshot["source_message_id"], message["source_message_id"])
        self.assertNotIn(lease["token"], json.dumps(message))
        bridge._publish_phone_payload.assert_not_called()

    def test_old_notification_ack_cannot_remove_newer_progress(self):
        lease = self.poll()["job"]["lease"]
        self.report(lease)
        self.protocol.acknowledge_notification("task-1", 1, 1)
        self.assertEqual([("task-1", 1, 2)], self.protocol.notifications())

    def test_notification_send_ack_does_not_delete_a_result_committed_during_send(self):
        lease = self.poll()["job"]["lease"]
        bridge = self.bridge()
        def finish_during_send(*_):
            self.report(lease, status="completed")
            return True
        bridge._publish_or_queue_task_event.side_effect = finish_during_send
        flush_worker_notifications(bridge, None)
        self.assertEqual([("task-1", 1, 2)], self.protocol.notifications())
        flush_worker_notifications(bridge, None)
        self.assertEqual([], self.protocol.notifications())

    def test_failure_reports_follow_original_app_status_delivery_path(self):
        lease = self.poll()["job"]["lease"]
        self.report(lease, status="failed", text="")
        bridge = self.bridge()
        flush_worker_notifications(bridge, None)
        public = bridge._publish_or_queue_task_event.call_args.args[2]
        self.assertEqual("failed", public["status"])
        self.assertEqual("failure", public["error"])
        self.assertEqual("app-a", public["client_route_id"])
        self.assertNotIn(lease["token"], json.dumps(public))
        self.assertEqual([], self.protocol.notifications())

    def test_unreachable_notification_does_not_starve_other_apps(self):
        lease = self.poll()["job"]["lease"]
        self.report(lease, status="completed")
        for index in range(10):
            with self.ledger.transaction() as connection:
                self.protocol._notify(connection, {"task_id": "other-" + str(index), "execution_generation": 1, "status_seq": 1})
        first = self.protocol.notifications()
        for row in first:
            self.protocol.attempted_notification(*row)
        self.assertNotEqual(first, self.protocol.notifications())

    def test_mqtt_replies_are_correlated_and_reserved_operations_never_start_a_model(self):
        bridge = self.bridge()
        route_worker_payload(bridge, None, {}, self.payload(), client_route_id="route-a", source_id=self.source)
        reply = bridge._publish_phone_payload.call_args.args[2]
        self.assertTrue(reply["ok"])
        self.assertEqual("rpc-1", reply["request_id"])
        self.assertIn("job", reply)
        bad = self.payload(type="agent_worker_report", lease=reply["job"]["lease"], report={"status": ["bad"]})
        route_worker_payload(bridge, None, {}, bad, client_route_id="route-a", source_id=self.source)
        self.assertFalse(bridge._publish_phone_payload.call_args.args[2]["ok"])

    def test_reply_transport_failure_is_not_mislabeled_as_request_validation_failure(self):
        bridge = self.bridge()
        bridge._publish_phone_payload.side_effect = ValueError("transport encoding failure")
        with self.assertRaisesRegex(ValueError, "transport encoding failure"):
            route_worker_payload(bridge, None, {}, self.payload(), client_route_id="route-a", source_id=self.source)
        bridge._publish_phone_payload.assert_called_once()
        response = bridge._publish_phone_payload.call_args.args[2]
        self.assertTrue(response["ok"])
        self.assertNotIn("error", response)
        self.assertEqual(response["job"], self.poll()["job"])


class WorkerProtocolIngressTest(WorkerFixture):
    def test_real_signal_ingress_connect_poll_report_and_forged_source(self):
        import agent_worker_mqtt
        import mqtt_bridge
        from tests.test_mqtt_phone_tool_routing import MqttPhoneToolRoutingTests, FakeMessage
        fixture = MqttPhoneToolRoutingTests(methodName="runTest")
        fixture.setUp()
        self.addCleanup(fixture.tearDown)
        self.registry.enroll(fixture.first, "worker-a", max_parallel=2, providers=["codex"])
        protocol = AgentWorkerProtocol(self.registry)
        with patch.object(agent_worker_mqtt, "worker_registry", return_value=self.registry), \
                patch.object(agent_worker_mqtt, "worker_protocol", return_value=protocol), \
                patch.object(mqtt_bridge, "_ensure_outbound_retry_thread"):
            def deliver(kind, **fields):
                fixture._deliver(fixture.first, dict(type=kind, protocol=PROTOCOL, request_id=kind,
                    incarnation="boot-a", session_epoch=1, **fields))
                return fixture.publish_phone_payload.call_args.args[2]
            self.assertTrue(deliver("agent_worker_connect", expected_session_epoch=0, providers=["codex"])["ok"])
            self.assertTrue(deliver("agent_worker_heartbeat", sequence=1, available_slots=2)["ok"])
            protocol.queue.enqueue(record(), provider="codex", allowed_workers=["worker-a"])
            polled = deliver("agent_worker_poll", sequence=1)
            self.assertTrue(polled["ok"])
            result = deliver("agent_worker_report", sequence=1, lease=polled["job"]["lease"],
                report=dict(status="completed", text="done", error="", current_step=""))
            self.assertTrue(result["ok"])
            self.assertEqual("completed", protocol.queue.tasks.get("task-1")["status"])
            self.assertEqual([], fixture.agent_starts)
            fixture.publish_phone_payload.reset_mock()
            fixture.decrypted["source_id"] = "forged"
            mqtt_bridge.on_message(fixture.mqtt, None, FakeMessage(fixture.first))
            fixture.publish_phone_payload.assert_not_called()
