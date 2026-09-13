"""Notification APIs with real durable storage; Signal encryption is a fixture."""
from concurrent.futures import ThreadPoolExecutor
from contextlib import ExitStack
from pathlib import Path
import sqlite3
import tempfile
import threading
import unittest
from unittest.mock import Mock, patch
import uuid

import link_delivery as delivery
import mqtt_bridge as bridge
from link_protocol import new_link_secret


class NotificationQueueTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="galaxyssi-notification-")
        self.addCleanup(temporary.cleanup)
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(delivery, "DB_PATH", Path(temporary.name) / "delivery.db"))
        self.peers = [{"client_route_id": "phone-a", "signal_name": "phone-a", "link_secret": new_link_secret(),
                       "local_identity_fingerprint": "a" * 64, "identity_fingerprint": "b" * 64}]
        self.mock("client", None)
        self.mock("desktop_id", Mock(return_value="desktop"))
        self.mock("desktop_name", Mock(return_value="Desktop"))
        self.mock("is_paired", Mock(return_value=True))
        self.mock("list_clients", Mock(side_effect=lambda: self.peers))
        self.mock("get_client", Mock(side_effect=lambda route: next((p for p in self.peers if p["client_route_id"] == route), None)))
        self.encrypt = self.mock("encrypt_signal_payload", Mock(side_effect=lambda envelope, **kwargs: {
            "scheme": "signal", "from": "desktop", "to": kwargs["remote_name"], "signal_type": "signal", "body": "Y2lwaGVy"}))
        self.flush = self.mock("flush_outbound_messages", Mock(side_effect=AssertionError("Synchronous socket flush")))
        self.worker = self.mock("_ensure_outbound_retry_thread", Mock())
        self.stack.enter_context(patch.object(bridge.transport_timing, "queued"))

    def mock(self, name, value):
        return self.stack.enter_context(patch.object(bridge, name, value))

    def send(self, kind="agent", **kwargs):
        if kind == "agent":
            return bridge.publish_agent_push_message("codex", "completed", client_route_id="phone-a", **kwargs)
        return bridge.publish_mobile_test_message("codex", "diagnostic", client_route_id="phone-a", **kwargs)

    def test_offline_and_uninitialized_entries_commit_before_success(self):
        for mqttc in (None, Mock(is_connected=Mock(return_value=False))):
            for kind in ("agent", "diagnostic"):
                with self.subTest(kind=kind, initialized=mqttc is not None), patch.object(bridge, "client", mqttc):
                    result = self.send(kind)
                self.assertTrue(result["ok"], result)
                self.assertTrue(result["queued"])
                self.assertFalse(result["delivered"])
                self.assertEqual(1, result["accepted_count"])
                self.assertEqual("queued", result["delivery_state"])
                mid = result["deliveries"][0]["message_id"]
                self.assertEqual(mid, str(uuid.UUID(mid)))
                self.assertEqual("queued", delivery.outbound_status("phone-a", mid))
        self.assertEqual(4, len(delivery.pending_outbound()))
        self.flush.assert_not_called()

    def test_online_acceptance_is_still_queued_not_broker_or_peer_delivery(self):
        with patch.object(bridge, "client", Mock(is_connected=Mock(return_value=True))):
            result = self.send()
        self.assertTrue(result["queued"])
        self.assertFalse(result["delivered"])
        self.flush.assert_not_called()
        envelope = self.encrypt.call_args.args[0]
        self.assertEqual("phone-a", envelope["target_id"])
        self.assertEqual(result["deliveries"][0]["message_id"], envelope["message_id"])
        self.assertEqual("completed", envelope["payload"]["content"])

    def test_storage_or_signal_failure_never_claims_acceptance(self):
        for method in ("queue_outbound", "encrypt_signal_payload"):
            with self.subTest(method=method), patch.object(bridge, method, side_effect=sqlite3.OperationalError("unavailable")):
                result = self.send()
            self.assertFalse(result["ok"])
            self.assertFalse(result["queued"])
            self.assertFalse(result["delivered"])
            self.assertEqual(1, result["failed_count"])
        self.worker.assert_not_called()

    def test_timing_and_worker_failure_do_not_invalidate_committed_ciphertext(self):
        self.worker.side_effect = RuntimeError("temporarily unavailable")
        with patch.object(bridge.transport_timing, "queued", side_effect=RuntimeError("telemetry unavailable")):
            result = self.send()
        self.assertTrue(result["ok"])
        self.assertEqual("queued", delivery.outbound_status("phone-a", result["deliveries"][0]["message_id"]))

    def test_multi_peer_requires_explicit_selection_and_reports_partial_queue(self):
        self.peers.extend({**self.peers[0], "client_route_id": route, "signal_name": route}
                          for route in ("phone-b", "phone-c"))
        result = bridge.publish_agent_push_message("codex", "test")
        self.assertFalse(result["ok"])
        self.assertEqual("client_route_required", result["code"])
        original = bridge.queue_outbound
        def queue(route, *args, **kwargs):
            if route == "phone-b":
                raise sqlite3.OperationalError("busy")
            return original(route, *args, **kwargs)
        with patch.object(bridge, "queue_outbound", side_effect=queue):
            result = bridge.publish_agent_push_message("codex", "test", broadcast=True)
        self.assertFalse(result["ok"])
        self.assertEqual("partially_queued", result["delivery_state"])
        self.assertEqual(2, result["accepted_count"])
        self.assertEqual(1, result["failed_count"])
        self.assertEqual(["queued", "failed", "queued"], [d["state"] for d in result["deliveries"]])
        self.assertEqual({"phone-a", "phone-c"}, {d["client_route_id"] for d in delivery.pending_outbound()})

    def test_unpaired_unknown_and_incomplete_task_identity_never_encrypt(self):
        with patch.object(bridge, "is_paired", return_value=False):
            self.assertFalse(self.send()["ok"])
        self.assertFalse(bridge.publish_agent_push_message("codex", "test", client_route_id="unknown")["ok"])
        self.assertEqual("agent_task_identity_required", self.send(task_id="task")["code"])
        for entry in (bridge.publish_agent_push_message, bridge.publish_mobile_test_message):
            self.assertFalse(entry("", "text")["ok"])
            self.assertFalse(entry("codex", " ")["ok"])
        self.encrypt.assert_not_called()

    def test_task_identity_and_priority_survive_offline_queue(self):
        result = self.send(task_id="task", conversation_id="conversation", turn_id="turn", source_message_id="source")
        self.assertTrue(result["ok"])
        envelope = self.encrypt.call_args.args[0]
        self.assertEqual("conversation", envelope["conversation_id"])
        self.assertEqual("source", envelope["reply_to"])
        self.assertEqual("turn", envelope["payload"]["turn_id"])
        pending = delivery.pending_outbound()[0]
        self.assertEqual(bridge.OUTBOUND_PRIORITY_TERMINAL, pending["priority"])
        self.assertEqual("final", pending["transport_traffic"])

    def test_queue_only_preserves_pending_ciphertext_and_rejects_non_durable(self):
        result = self.send()
        mid = result["deliveries"][0]["message_id"]
        before = delivery.pending_outbound()[0]["wire_payload"]
        self.encrypt.reset_mock()
        bridge._publish_to_registered_client(None, self.peers[0], {"message_id": mid, "type": "text"}, queue_only=True)
        self.encrypt.assert_not_called()
        self.assertEqual(before, delivery.pending_outbound()[0]["wire_payload"])
        with self.assertRaises(ValueError):
            bridge._publish_to_registered_client(None, self.peers[0], {}, durable=False, queue_only=True)


class NotificationRetryOwnerTest(unittest.TestCase):
    def test_concurrent_ensure_calls_share_one_retry_worker(self):
        entered = []
        finish = threading.Event()
        def run():
            entered.append(threading.current_thread())
            finish.wait(5)
        with patch.object(bridge, "outbound_retry_thread", None), \
             patch.object(bridge, "outbound_retry_stop_event", threading.Event()), \
             patch.object(bridge, "_outbound_retry_loop", side_effect=run):
            try:
                with ThreadPoolExecutor(max_workers=10) as workers:
                    list(workers.map(lambda _: bridge._ensure_outbound_retry_thread(), range(50)))
                self.assertEqual(1, len(entered))
                self.assertIs(entered[0], bridge.outbound_retry_thread)
            finally:
                finish.set()
                for worker in entered:
                    worker.join(5)


if __name__ == "__main__":
    unittest.main()
