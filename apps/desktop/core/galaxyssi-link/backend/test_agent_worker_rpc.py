"""Worker response isolation, bounded callers, retries and paired ingress."""
from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
import queue
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

from agent_worker_mqtt import close_worker_rpc_client, route_worker_payload, worker_rpc_client
from agent_worker_protocol import AgentWorkerProtocol
from agent_worker_rpc import AgentWorkerRpcClient, MAX_RESPONSE_BYTES, PROTOCOL, WorkerRpcError, request_digest
from test_agent_worker_queue import record
from test_agent_worker_registry import WorkerFixture, peer


def response(request, **values):
    return dict(type="agent_worker_response", protocol=PROTOCOL, request_id=request["request_id"],
                request_digest=request_digest(request), ok=True, **values)


class WorkerRpcTest(unittest.TestCase):
    def setUp(self):
        self.peers = {route: peer(route) for route in ("route-a", "route-b")}
        self.sent = queue.Queue()
        self.client = AgentWorkerRpcClient(self.peers.get, self.send)
        self.addCleanup(self.client.close)

    def send(self, paired, payload):
        self.sent.put((paired, payload))
        return True

    def deliver(self, sent, **values):
        paired, payload = sent
        return self.client.receive(paired, paired["signal_name"], response(payload, **values))

    def assert_empty(self):
        state = self.client.snapshot()
        self.assertEqual((0, 0, 0), (state["pending"], state["routes"], state["bytes"]))

    def test_two_routes_can_use_same_rpc_id_without_receiving_each_others_reply(self):
        with ThreadPoolExecutor(2) as pool:
            first = pool.submit(self.client.request, "route-a", "status", request_id="same")
            second = pool.submit(self.client.request, "route-b", "status", request_id="same")
            requests = [self.sent.get(timeout=2), self.sent.get(timeout=2)]
            for paired, request in reversed(requests):
                wrong = self.peers["route-b" if paired["client_route_id"] == "route-a" else "route-a"]
                self.assertFalse(self.client.receive(wrong, wrong["signal_name"], response(request)))
                self.assertTrue(self.deliver((paired, request), worker=paired["client_route_id"]))
            self.assertEqual("route-a", first.result(timeout=2).payload["worker"])
            self.assertEqual("route-b", second.result(timeout=2).payload["worker"])
        self.assert_empty()

    def test_old_attempt_cannot_complete_retry_or_refresh_lease_timing(self):
        with self.assertRaisesRegex(WorkerRpcError, "timeout"):
            self.client.request("route-a", "poll", {"sequence": 1}, request_id="retry", timeout=0.01)
        old = self.sent.get(timeout=2)
        with ThreadPoolExecutor(1) as pool:
            future = pool.submit(self.client.request, "route-a", "poll", {"sequence": 1}, request_id="retry")
            new = self.sent.get(timeout=2)
            self.assertEqual(old[1]["request_id"], new[1]["request_id"])
            self.assertNotEqual(old[1]["attempt_id"], new[1]["attempt_id"])
            self.assertFalse(self.deliver(old, job={"stale": True}))
            self.assertTrue(self.deliver(new, job=None))
            result = future.result(timeout=2)
            self.assertIsNone(result.payload["job"])
            self.assertGreaterEqual(result.received_at, result.sent_at)
        self.assert_empty()

    def test_reordered_responses_keep_session_task_and_generation_correlated(self):
        with ThreadPoolExecutor(10) as pool:
            futures = [pool.submit(self.client.request, "route-a", "renew",
                {"lease": {"key": ["app", "chat", f"turn-{i}", f"task-{i}", i + 1]}},
                request_id=f"request-{i}") for i in range(10)]
            requests = [self.sent.get(timeout=2) for _ in futures]
            for sent in reversed(requests):
                self.assertTrue(self.deliver(sent, lease=sent[1]["lease"]))
            for i, future in enumerate(futures):
                self.assertEqual(["app", "chat", f"turn-{i}", f"task-{i}", i + 1],
                                 future.result(timeout=2).payload["lease"]["key"])
        self.assert_empty()

    def test_duplicate_response_is_ignored_and_payload_is_detached(self):
        captured = {}
        def send(paired, request):
            value = response(request, worker={"name": "correct"})
            self.assertTrue(self.client.receive(paired, paired["signal_name"], value))
            self.assertFalse(self.client.receive(paired, paired["signal_name"], value))
            value["worker"]["name"] = "mutated"
            captured.update(request)
            return True
        self.client._send = send
        result = self.client.request("route-a", "status")
        self.assertEqual("correct", result.payload["worker"]["name"])
        self.assertFalse(self.client.receive(self.peers["route-a"], self.peers["route-a"]["signal_name"], response(captured)))
        self.assertNotIn("correct", repr(result))
        self.assert_empty()

    def test_untrusted_source_protocol_digest_and_oversized_responses_are_ignored(self):
        def send(paired, request):
            value = response(request)
            self.assertFalse(self.client.receive(paired, "forged", value))
            for changes in ({"protocol": "other"}, {"request_digest": "wrong"}, {"ok": 1},
                            {"request_id": []}, {"type": "text"}, {"job": "x" * MAX_RESPONSE_BYTES},
                            {"job": float("nan")}):
                with self.subTest(changes=list(changes)):
                    self.assertFalse(self.client.receive(paired, paired["signal_name"], value | changes))
            self.assertTrue(self.client.receive(paired, paired["signal_name"], value))
            return True
        self.client._send = send
        self.assertTrue(self.client.request("route-a", "status").payload["ok"])
        self.assert_empty()

    def test_repair_or_revocation_prevents_old_peer_response(self):
        for change in ({"link_secret": "changed"}, {"revoked": True}, {"access_granted_at": 456}):
            self.peers["route-a"] = peer()
            def send(paired, request):
                self.peers["route-a"].update(change)
                self.assertNotEqual(paired, self.peers["route-a"])
                self.assertFalse(self.client.receive(paired, paired["signal_name"], response(request)))
                self.assertFalse(self.client.receive(self.peers["route-a"], paired["signal_name"], response(request)))
                return True
            self.client._send = send
            with self.subTest(change=change), self.assertRaisesRegex(WorkerRpcError, "timeout"):
                self.client.request("route-a", "status", timeout=0.01)
            self.assert_empty()

    def test_pairing_change_after_response_is_rejected_before_returning_to_executor(self):
        def send(paired, request):
            self.assertTrue(self.client.receive(paired, paired["signal_name"], response(request)))
            self.peers["route-a"]["link_secret"] = "changed"
            return True
        self.client._send = send
        with self.assertRaisesRegex(WorkerRpcError, "pairing_changed"):
            self.client.request("route-a", "status")
        self.assert_empty()

    def test_timeouts_publish_failures_and_close_release_all_resources(self):
        for sender in (lambda *_: False, Mock(side_effect=OSError("network"))):
            self.client._send = sender
            with self.assertRaisesRegex(WorkerRpcError, "publish_failed"):
                self.client.request("route-a", "status")
            self.assert_empty()
        self.client._send = self.send
        with ThreadPoolExecutor(1) as pool:
            future = pool.submit(self.client.request, "route-a", "status", timeout=30)
            self.sent.get(timeout=2)
            self.client.close()
            with self.assertRaisesRegex(WorkerRpcError, "closed"):
                future.result(timeout=2)
        with self.assertRaisesRegex(WorkerRpcError, "closed"):
            self.client.request("route-a", "status")
        self.assert_empty()

    def test_global_route_and_byte_limits_do_not_allocate_extra_waiters(self):
        self.client = AgentWorkerRpcClient(self.peers.get, self.send, max_pending=2, per_route=1)
        with ThreadPoolExecutor(2) as pool:
            first = pool.submit(self.client.request, "route-a", "status", request_id="first")
            self.sent.get(timeout=2)
            with self.assertRaisesRegex(WorkerRpcError, "already_pending"):
                self.client.request("route-a", "status", request_id="first")
            with self.assertRaisesRegex(WorkerRpcError, "busy"):
                self.client.request("route-a", "status")
            second = pool.submit(self.client.request, "route-b", "status")
            self.sent.get(timeout=2)
            for i in range(1000):
                route = f"route-{i}"
                self.peers[route] = peer(route)
                with self.assertRaisesRegex(WorkerRpcError, "busy"):
                    self.client.request(route, "status")
            self.assertEqual(2, self.client.snapshot()["routes"])
            self.client.close()
            for future in (first, second):
                with self.assertRaisesRegex(WorkerRpcError, "closed"):
                    future.result(timeout=2)
        self.assert_empty()
        self.client = AgentWorkerRpcClient(self.peers.get, self.send, max_bytes=1)
        with self.assertRaisesRegex(WorkerRpcError, "busy"):
            self.client.request("route-a", "status")
        self.assert_empty()

    def test_responses_also_obey_shared_byte_budget(self):
        self.client = AgentWorkerRpcClient(self.peers.get, self.send, max_bytes=1024)
        def send(paired, request):
            self.assertFalse(self.client.receive(paired, paired["signal_name"], response(request, job="x" * 900)))
            self.assertTrue(self.client.receive(paired, paired["signal_name"], response(request, job=None)))
            return True
        self.client._send = send
        self.client.request("route-a", "poll")
        self.assert_empty()

    def test_full_size_job_has_room_for_response_envelope(self):
        def send(paired, request):
            self.assertTrue(self.client.receive(paired, paired["signal_name"],
                response(request, job="x" * (512 * 1024 - 2))))
            return True
        self.client._send = send
        self.assertEqual(512 * 1024 - 2, len(self.client.request("route-a", "poll").payload["job"]))
        self.assert_empty()

    def test_a_route_cannot_use_other_routes_response_budget(self):
        release = threading.Event()
        calls = queue.Queue()
        def send(paired, request):
            calls.put((paired, request))
            release.wait(timeout=3)
            return True
        self.client._send = send
        with ThreadPoolExecutor(4) as pool:
            futures = [pool.submit(self.client.request, route, "poll")
                       for route in ("route-a", "route-a", "route-a", "route-b")]
            try:
                requests = [calls.get(timeout=2) for _ in futures]
                groups = {route: [entry for entry in requests if entry[0]["client_route_id"] == route]
                          for route in ("route-a", "route-b")}
                self.assertTrue(self.deliver(groups["route-a"][0], job="x" * 400_000))
                self.assertTrue(self.deliver(groups["route-a"][1], job="x" * 400_000))
                self.assertFalse(self.deliver(groups["route-a"][2], job="x" * 400_000))
                self.assertTrue(self.deliver(groups["route-b"][0], job="x" * 400_000))
                self.assertTrue(self.deliver(groups["route-a"][2], job=None))
            finally:
                release.set()
            for future in futures:
                self.assertTrue(future.result(timeout=2).payload["ok"])
        self.assert_empty()

    def test_response_after_deadline_is_not_accepted_even_before_wait_starts(self):
        clock = [100.0]
        self.client = AgentWorkerRpcClient(self.peers.get, self.send, clock=lambda: clock[0])
        def send(paired, request):
            clock[0] = 110.0
            self.assertFalse(self.client.receive(paired, paired["signal_name"], response(request)))
            return True
        self.client._send = send
        with self.assertRaisesRegex(WorkerRpcError, "timeout"):
            self.client.request("route-a", "poll", timeout=10)
        self.assert_empty()

    def test_limits_cannot_be_disabled_or_increased_without_bound(self):
        for limits in ({"max_pending": 0}, {"max_pending": 129}, {"per_route": True},
                       {"per_route": 129}, {"max_bytes": 64 * 1024 * 1024 + 1}):
            with self.subTest(limits=limits), self.assertRaises(ValueError):
                AgentWorkerRpcClient(self.peers.get, self.send, **limits)

    def test_invalid_requests_fail_before_publish(self):
        for changes in ({"timeout": 0}, {"timeout": 31}, {"timeout": True}, {"timeout": float("nan")},
                        {"operation": []}, {"operation": "enroll"}, {"request_id": ""},
                        {"fields": {"attempt_id": "override"}}, {"fields": {"conversation_id": "override"}},
                        {"fields": {"text": "x" * (15 * 1024)}}, {"fields": {"v": float("inf")}}):
            with self.subTest(changes=list(changes)), self.assertRaises(WorkerRpcError):
                self.client.request(**({"route": "route-a", "operation": "status"} | changes))
        self.assertTrue(self.sent.empty())
        self.assert_empty()

    def test_authenticated_transport_metadata_does_not_change_digest(self):
        request = dict(type="agent_worker_poll", request_id="poll", sequence=1, attempt_id="attempt")
        self.assertEqual(request_digest(request), request_digest(dict(request,
            message_id="transport", conversation_id="chat", source_message_id="source", _client_route_id="route")))
        self.assertNotEqual(request_digest(request), request_digest(dict(request, sequence=2)))


class WorkerRpcProtocolTest(WorkerFixture):
    def test_client_connects_polls_renews_and_reports_through_production_rpc_router(self):
        self.enroll()
        protocol = AgentWorkerProtocol(self.registry)
        server = SimpleNamespace(get_client=lambda route: self.peer, _worker_enrollment_registry=self.registry,
            _worker_execution_protocol=protocol, agent_task_manager=SimpleNamespace(_run_events=SimpleNamespace(ledger=self.ledger)),
            _ensure_outbound_retry_thread=Mock())
        client = None
        responses = []
        def receive(_mqtt, _wire, value):
            responses.append(deepcopy(value))
            return client.receive(self.peer, self.source, value)
        server._publish_phone_payload = receive
        def send(paired, request):
            return route_worker_payload(server, None, {}, request,
                client_route_id=paired["client_route_id"], source_id=self.source)
        client = AgentWorkerRpcClient(lambda route: self.peer, send)
        self.addCleanup(client.close)
        connected = client.request("route-a", "connect", dict(incarnation="node", expected_session_epoch=0,
            providers=["codex"]), request_id="connect")
        self.assertTrue(connected.payload["ok"])
        session = dict(incarnation="node", session_epoch=connected.payload["worker"]["session_epoch"])
        self.assertTrue(client.request("route-a", "heartbeat", dict(session, sequence=1, available_slots=2)).payload["ok"])
        protocol.queue.enqueue(record(), provider="codex", allowed_workers=["worker-a"])
        job = client.request("route-a", "poll", dict(session, sequence=1), request_id="poll").payload["job"]
        repeated = client.request("route-a", "poll", dict(session, sequence=1), request_id="poll").payload["job"]
        self.assertEqual(job, repeated)
        self.assertNotEqual(responses[-1]["request_digest"], responses[-2]["request_digest"])
        renewed = client.request("route-a", "renew", dict(session, lease=job["lease"]))
        self.assertTrue(renewed.payload["ok"])
        fields = dict(session, lease=renewed.payload["lease"], sequence=1,
                      report=dict(status="completed", text="fixture result", error="", current_step="done"))
        result = client.request("route-a", "report", fields, request_id="report")
        replay = client.request("route-a", "report", fields, request_id="report")
        self.assertFalse(result.payload["replayed"])
        self.assertTrue(replay.payload["replayed"])
        self.assertEqual("fixture result", protocol.queue.tasks.get("task-1")["result"])
        self.assertEqual(0, client.snapshot()["pending"])

    def test_bridge_uses_signal_transport_without_durable_expired_request_replay(self):
        bridge = SimpleNamespace(get_client=lambda route: self.peer, client=Mock(),
            mqtt_lifecycle_stop_event=threading.Event())
        client = worker_rpc_client(bridge)
        self.addCleanup(client.close)
        def publish(mqtt, paired, payload, *, durable):
            self.assertIs(mqtt, bridge.client)
            self.assertEqual(self.peer, paired)
            self.assertFalse(durable)
            self.assertTrue(route_worker_payload(bridge, mqtt, {}, response(payload, worker={}),
                client_route_id="route-a", source_id=self.source))
            return SimpleNamespace(rc=0)
        bridge._publish_to_registered_client = publish
        self.assertTrue(client.request("route-a", "status").payload["ok"])
        close_worker_rpc_client(bridge)
        self.assertTrue(client.snapshot()["closed"])
        bridge.mqtt_lifecycle_stop_event.set()
        with self.assertRaisesRegex(WorkerRpcError, "closed"):
            worker_rpc_client(bridge)
        bridge.mqtt_lifecycle_stop_event.clear()
        self.assertIsNot(client, worker_rpc_client(bridge))
        close_worker_rpc_client(bridge)

    def test_unsolicited_response_never_enrolls_or_creates_a_client(self):
        bridge = SimpleNamespace(get_client=Mock())
        self.assertTrue(route_worker_payload(bridge, None, {}, response({"request_id": "unknown"}),
            client_route_id="route-a", source_id=self.source))
        self.assertFalse(hasattr(bridge, "_worker_rpc_client"))
        bridge.get_client.assert_not_called()

    def test_response_passes_real_envelope_ingress_but_forged_source_cannot_complete_rpc(self):
        import mqtt_bridge
        from tests.test_mqtt_phone_tool_routing import MqttPhoneToolRoutingTests, FakeMessage
        fixture = MqttPhoneToolRoutingTests(methodName="runTest")
        fixture.setUp()
        self.addCleanup(fixture.tearDown)
        client = AgentWorkerRpcClient(mqtt_bridge.get_client, lambda *_: True)
        self.addCleanup(client.close)
        def send(paired, request):
            value = response(request, worker={"fixture": True})
            fixture._deliver(fixture.second, value)
            self.assertEqual(1, client.snapshot()["pending"])
            fixture.decrypted["source_id"] = "forged"
            mqtt_bridge.on_message(fixture.mqtt, None, FakeMessage(paired))
            self.assertEqual(1, client.snapshot()["pending"])
            fixture._deliver(paired, value)
            return True
        client._send = send
        with patch.object(mqtt_bridge, "_worker_rpc_client", client, create=True):
            result = client.request(fixture.first["client_route_id"], "status")
        self.assertTrue(result.payload["worker"]["fixture"])
        self.assertEqual([], fixture.agent_starts)
