"""Enrollment and worker sessions do not inherit ordinary contact permissions."""
from copy import deepcopy
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import Mock, patch

from agent_run_kernel import AgentRunEventLedger
from agent_worker_mqtt import route_worker_payload
from agent_worker_registry import AgentWorkerRegistry, WorkerAccessError
from agent_worker_leases import WorkerLeaseConflict
from agent_work_pool import ExecutionKey
from pairing_access import grant_for_executor


def peer(route="route-a"):
    access = grant_for_executor(True, issued_at_millis=123)
    return dict(client_route_id=route, signal_name="signal:" + route, identity_fingerprint="a" * 64,
        local_identity_fingerprint="b" * 64, link_secret="c" * 64, revoked=False,
        access_profile=access["profile"], access_scopes=access["scopes"], access_granted_at=123)


class WorkerFixture(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.ledger = AgentRunEventLedger(Path(temporary.name) / "runs.db")
        self.registry = AgentWorkerRegistry(self.ledger)
        self.peer = peer()
        self.source = self.peer["signal_name"]

    def enroll(self):
        return self.registry.enroll(self.peer, "worker-a", max_parallel=10, providers=["codex", "deepseek"])

    def connect(self, **changes):
        payload = dict(request_id="connect-a", incarnation="boot-a", expected_session_epoch=0, providers=["codex"])
        payload.update(changes)
        return self.registry.connect(self.peer, self.source, payload)

    def heartbeat(self, **changes):
        payload = dict(request_id="heartbeat", incarnation="boot-a", session_epoch=1, sequence=1, available_slots=4)
        payload.update(changes)
        return self.registry.heartbeat(self.peer, self.source, payload)


class WorkerRegistryTest(WorkerFixture):
    def test_pairing_even_with_full_executor_does_not_enroll_worker(self):
        with self.assertRaises(WorkerAccessError):
            self.registry.status(self.peer, self.source)
        with self.assertRaises(WorkerAccessError):
            self.connect()

    def test_enrollment_requires_exact_pair_and_grant_binding(self):
        self.enroll()
        for field, value in (("client_route_id", "route-b"), ("signal_name", "other"),
                ("identity_fingerprint", "d" * 64), ("local_identity_fingerprint", "e" * 64),
                ("link_secret", "f" * 64), ("access_granted_at", 124), ("revoked", True)):
            changed = deepcopy(self.peer)
            changed[field] = value
            with self.subTest(field=field), self.assertRaises(WorkerAccessError):
                self.registry.status(changed, changed["signal_name"])
        with self.assertRaises(WorkerAccessError):
            self.registry.status(self.peer, "forged-source")

    def test_capacity_and_provider_permission_are_bounded(self):
        self.enroll()
        with self.assertRaises(WorkerAccessError):
            self.connect(providers=["unauthorized-provider"])
        self.connect()
        for slots in (11, -1, True):
            with self.subTest(slots=slots), self.assertRaises(WorkerAccessError):
                self.heartbeat(available_slots=slots)
        self.assertEqual(4, self.heartbeat()["available_slots"])

    def test_connect_replay_and_old_process_messages(self):
        self.enroll()
        self.connect()
        self.assertEqual(1, self.connect()["session_epoch"])
        self.heartbeat()
        new = self.connect(request_id="connect-b", incarnation="boot-b", expected_session_epoch=1)
        self.assertEqual(2, new["session_epoch"])
        with self.assertRaises(WorkerAccessError):
            self.connect()
        with self.assertRaises(WorkerAccessError):
            self.heartbeat(sequence=2)

    def test_revocation_and_process_replacement_revoke_execution_leases(self):
        self.enroll()
        self.connect()
        grant = self.registry.leases.claim(ExecutionKey("app", "chat", "turn", "task", 1),
            "worker-a", "boot-a", expected_epoch=0, claim_id="lease")
        self.connect(request_id="connect-b", incarnation="boot-b", expected_session_epoch=1)
        with self.assertRaises(WorkerLeaseConflict):
            self.registry.leases.renew(grant)
        self.registry.revoke(self.peer["client_route_id"])
        with self.assertRaises(WorkerAccessError):
            self.registry.status(self.peer, self.source)

    def test_heartbeat_replay_does_not_refresh_liveness_or_change_capacity(self):
        self.enroll()
        self.connect()
        first = self.heartbeat(sequence=4)
        self.assertEqual(first["last_seen_ms"], self.heartbeat(sequence=4)["last_seen_ms"])
        with self.assertRaises(WorkerAccessError):
            self.heartbeat(sequence=4, available_slots=3)
        with self.assertRaises(WorkerAccessError):
            self.heartbeat(sequence=3)
        with patch("agent_worker_registry.time.time_ns", return_value=(first["last_seen_ms"] + 30001) * 1_000_000):
            status = self.registry.status(self.peer, self.source)
        self.assertFalse(status["connected"])
        self.assertEqual(0, status["available_slots"])

    def test_worker_identity_cannot_move_between_routes(self):
        self.enroll()
        with self.assertRaises(WorkerAccessError):
            self.registry.enroll(peer("route-b"), "worker-a", max_parallel=10, providers=["codex"])

    def test_registry_reconstruction_keeps_permission_and_epoch(self):
        self.enroll()
        self.connect()
        restarted = AgentWorkerRegistry(AgentRunEventLedger(self.ledger.path))
        self.assertEqual(1, restarted.status(self.peer, self.source)["session_epoch"])
        self.assertEqual("worker-a", restarted.status(self.peer, self.source)["worker_id"])


class WorkerMqttRoutingTest(WorkerFixture):
    def route(self, payload, *, source=None):
        payload.setdefault("protocol", "galaxyssi.worker-control.v1")
        bridge = SimpleNamespace(agent_task_manager=SimpleNamespace(_run_events=SimpleNamespace(ledger=self.ledger)),
            _worker_enrollment_registry=self.registry, get_client=Mock(return_value=self.peer),
            _publish_phone_payload=Mock())
        handled = route_worker_payload(bridge, None, {"_client_route_id": self.peer["client_route_id"]}, payload,
            client_route_id=self.peer["client_route_id"], source_id=source or self.source)
        return handled, bridge._publish_phone_payload

    def test_mqtt_cannot_self_enroll_and_reserved_controls_do_not_become_chat(self):
        handled, publish = self.route(dict(type="agent_worker_enroll", request_id="request"))
        self.assertTrue(handled)
        self.assertEqual("worker_operation_unsupported", publish.call_args.args[2]["error"])
        handled, publish = self.route(dict(type="agent_worker_connect", request_id="request",
            incarnation="boot", providers=["codex"], expected_session_epoch=0))
        self.assertTrue(handled)
        self.assertFalse(publish.call_args.args[2]["ok"])


    def test_worker_response_does_not_create_response_loop(self):
        handled, publish = self.route(dict(type="agent_worker_response", request_id="response"))
        self.assertTrue(handled)
        publish.assert_not_called()

    def test_unknown_worker_operations_and_oversized_payloads_fail_closed(self):
        for payload in (dict(type="AGENT_WORKER_EXECUTE", request_id="bad", content="do something"),
                        dict(type="agent_worker_status", request_id="version", protocol="future-version"),
                        dict(type="agent_worker_status", request_id="big", content="x" * 17000)):
            handled, publish = self.route(payload)
            self.assertTrue(handled)
            self.assertFalse(publish.call_args.args[2]["ok"])

    def test_authenticated_worker_status_ignores_forged_worker_selector(self):
        self.enroll()
        _, publish = self.route(dict(type="agent_worker_status", request_id="status", worker_id="worker-b"))
        response = publish.call_args.args[2]
        self.assertTrue(response["ok"])
        self.assertEqual("worker-a", response["worker"]["worker_id"])
        self.assertNotIn("binding", response["worker"])
        _, publish = self.route(dict(type="agent_worker_status", request_id="status"), source="forged-source")
        self.assertFalse(publish.call_args.args[2]["ok"])


class WorkerApiTest(WorkerFixture):
    def request(self, host="127.0.0.1", token="test-token"):
        from fastapi import Request
        return Request({"type": "http", "client": (host, 1234),
                        "headers": [(b"x-galaxyssi-token", token.encode())]})

    def test_admin_api_requires_both_loopback_and_existing_desktop_token(self):
        from fastapi import HTTPException
        import agent_worker_api as api
        import main
        with patch.object(main, "_desktop_task_stream_token", return_value="test-token"):
            for host, token, expected in (("198.51.100.2", "test-token", 403), ("127.0.0.1", "", 401)):
                with self.subTest(host=host), self.assertRaises(HTTPException) as error:
                    api.worker_status("route-a", self.request(host, token))
                self.assertEqual(expected, error.exception.status_code)

    def test_admin_enrollment_and_revocation_are_local_and_explicit(self):
        import agent_worker_api as api
        import main
        import mqtt_bridge
        with patch.object(main, "_desktop_task_stream_token", return_value="test-token"), \
                patch.object(api, "worker_registry", return_value=self.registry), \
                patch.object(mqtt_bridge, "get_client", return_value=self.peer) as get_client:
            result = api.enroll_worker("route-a", api.WorkerEnrollment(worker_id="worker-a",
                max_parallel=10, providers=["codex"]), self.request())
            self.assertTrue(result["enabled"])
            get_client.return_value = None
            self.assertFalse(api.revoke_worker("route-a", self.request())["enabled"])


class WorkerIngressTest(WorkerFixture):
    def test_signal_ingress_does_not_treat_worker_controls_as_chat(self):
        import agent_worker_mqtt
        from tests.test_mqtt_phone_tool_routing import MqttPhoneToolRoutingTests
        fixture = MqttPhoneToolRoutingTests(methodName="runTest")
        fixture.setUp()
        self.addCleanup(fixture.tearDown)
        with patch.object(agent_worker_mqtt, "worker_registry", return_value=self.registry):
            fixture._deliver(fixture.first, dict(type="agent_worker_status", request_id="not-enrolled",
                                               protocol="galaxyssi.worker-control.v1"))
            response = fixture.publish_phone_payload.call_args.args[2]
            self.assertEqual("agent_worker_response", response["type"])
            self.assertFalse(response["ok"])
            self.registry.enroll(fixture.first, "worker-a", max_parallel=10, providers=["codex"])
            fixture._deliver(fixture.first, dict(type="agent_worker_status", request_id="enrolled",
                                               protocol="galaxyssi.worker-control.v1"))
            response = fixture.publish_phone_payload.call_args.args[2]
            self.assertTrue(response["ok"])
            self.assertEqual([], fixture.agent_starts)

            import mqtt_bridge
            from tests.test_mqtt_phone_tool_routing import FakeMessage
            fixture.publish_phone_payload.reset_mock()
            fixture.decrypted["source_id"] = "forged-signal-source"
            mqtt_bridge.on_message(fixture.mqtt, None, FakeMessage(fixture.first))
            fixture.publish_phone_payload.assert_not_called()
            self.assertEqual([], fixture.agent_starts)
