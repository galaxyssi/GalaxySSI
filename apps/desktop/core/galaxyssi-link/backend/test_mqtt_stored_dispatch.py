"""Exercise the real bridge receive/replay entrypoints with real durable storage."""
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing, ExitStack
import copy
import json
from pathlib import Path
import sqlite3
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import link_delivery as delivery
import link_protocol
import mqtt_bridge as bridge
import signal_receive_dispatch as dispatch
from tests.receive_test_support import store_received_envelope


class MqttStoredDispatchTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="galaxyssi-stored-bridge-")
        self.addCleanup(self.temp.cleanup)
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.path = Path(self.temp.name) / "delivery.db"
        self.stack.enter_context(patch.object(delivery, "DB_PATH", self.path))
        self.paired = {"client_route_id": "pair", "signal_name": "phone", "link_secret": link_protocol.new_link_secret()}
        self.envelope = link_protocol.make_envelope(
            {"type": "text", "content": "hello", "contact_id": "codex", "client_route_id": "pair",
             "task_id": "task", "turn_id": "turn", "conversation_id": "conversation"},
            source_id="phone", target_id="desktop", conversation_id="conversation")
        self.mid = self.envelope["message_id"]
        self.wire = {"scheme": "signal", "from": "phone", "to": "desktop", "signal_type": "signal",
                     "message_type": 2, "body": "Y2lwaGVy"}
        self.mock("desktop_id", return_value="desktop")
        self.mock("desktop_name", return_value="Test Desktop")
        self.get_client = self.mock("get_client", return_value=self.paired)
        self.mock("_resolve_inbound_topic", return_value=("client", self.paired))
        self.mock("touch_client")
        self.publish = self.mock("_publish_phone_payload", return_value=True)
        self.handle = self.mock("_dispatch_application_payload")
        self.decrypt = self.mock("decrypt_signal_envelope", side_effect=self.receive)
        self.log = self.mock("log")

    def mock(self, name, **kwargs):
        return self.stack.enter_context(patch.object(bridge, name, **kwargs))

    def receive(self, *_args, **_kwargs):
        return store_received_envelope("pair", copy.deepcopy(self.envelope))

    def packet(self, **wire):
        value = {**self.wire, **wire}
        sealed = link_protocol.seal_wire_packet(json.dumps(value), self.paired["link_secret"])
        return SimpleNamespace(topic="test-topic", payload=sealed.encode(), received_at_ms=int(time.time() * 1000))

    def send(self, **wire):
        bridge.on_message(object(), None, self.packet(**wire))

    def replay(self, *, now=None):
        records = dispatch.pending(now=now)
        for route, mid, size, token in records:
            bridge.on_message(object(), None, bridge._StoredInboxMessage(route, mid, size, token))
        return records

    def state(self):
        with closing(sqlite3.connect(self.path)) as db:
            return db.execute("SELECT dispatch_state,dispatch_attempts FROM inbound_messages").fetchone()

    def test_ack_means_durable_receive_before_business_not_task_completion(self):
        def publish(_mqtt, _wire, receipt):
            self.assertEqual(self.envelope, dispatch.load_envelope("pair", self.mid))
            self.assertEqual("RX_STORED", receipt["delivery_status"])
            self.assertEqual(64, len(receipt["content_hash"]))
            self.handle.assert_not_called()
            return True
        self.publish.side_effect = publish
        self.send()
        self.log.error.assert_not_called()
        self.handle.assert_called_once()
        self.assertEqual(("dispatched", 1), self.state())

    def test_three_concurrent_copies_only_dispatch_once(self):
        with ThreadPoolExecutor(max_workers=3) as workers:
            list(workers.map(lambda _: self.send(), range(3)))
        self.log.error.assert_not_called()
        self.handle.assert_called_once()
        self.assertEqual(("dispatched", 1), self.state())

    def test_busy_handler_does_not_emit_unverified_duplicate_receipt(self):
        self.receive()
        with dispatch.DispatchGuard("pair", self.mid):
            self.send()
        self.publish.assert_not_called()
        self.handle.assert_not_called()
        self.assertEqual(1, len(self.replay()))
        self.handle.assert_called_once()

    def test_cipher_replay_loads_body_instead_of_just_skipping_task(self):
        self.receive()
        delivery.bind_ciphertext("pair", bridge._signal_ciphertext_digest(self.wire), self.mid)
        self.send()
        self.decrypt.assert_not_called()
        self.handle.assert_called_once()
        self.assertEqual(("dispatched", 1), self.state())

    def test_completed_cipher_replay_acknowledges_without_new_task(self):
        self.send()
        self.send()
        self.handle.assert_called_once()
        self.decrypt.assert_called_once()
        self.assertTrue(self.publish.call_args.args[2]["duplicate"])

    def test_business_payload_enrichment_does_not_mutate_stored_envelope(self):
        original = copy.deepcopy(self.envelope)
        self.send()
        self.assertEqual(original, dispatch.load_envelope("pair", self.mid))
        self.assertEqual(original, self.handle.call_args.args[3])
        self.assertEqual(self.mid, self.handle.call_args.args[4]["source_message_id"])
        self.assertNotIn("source_message_id", original["payload"])

    def test_persisted_body_resumes_without_another_network_packet(self):
        self.receive()
        self.assertEqual(1, len(self.replay()))
        self.handle.assert_called_once()
        self.decrypt.assert_not_called()
        self.assertEqual([], self.replay())

    def test_interrupted_safe_task_preserves_all_task_identity(self):
        self.receive()
        with dispatch.DispatchGuard("pair", self.mid) as guard:
            dispatch.begin(guard, self.envelope)
        self.replay()
        sent = self.handle.call_args.args[4]
        for key in ("client_route_id", "conversation_id", "task_id", "turn_id"):
            self.assertEqual(self.envelope["payload"][key], sent[key])
        self.assertNotIn("_recovered_task", sent)
        self.assertEqual(("dispatched", 2), self.state())

    def test_interrupted_unknown_tool_does_not_repeat_external_effect(self):
        self.envelope["payload"]["type"] = "unknown_external_tool"
        self.receive()
        with dispatch.DispatchGuard("pair", self.mid) as guard:
            dispatch.begin(guard, self.envelope)
        self.replay()
        self.handle.assert_not_called()
        self.assertEqual("uncertain", self.state()[0])

    def test_failure_after_receive_retries_with_existing_body(self):
        self.handle.side_effect = OSError("business persistence unavailable")
        self.send()
        self.assertEqual("retry", self.state()[0])
        self.handle.side_effect = None
        self.replay(now=time.time() + 100)
        self.assertEqual(2, self.handle.call_count)
        self.decrypt.assert_called_once()
        self.assertEqual("dispatched", self.state()[0])

    def test_lost_receipt_publish_does_not_block_task_dispatch(self):
        self.publish.side_effect = OSError("network unavailable")
        self.send()
        self.handle.assert_called_once()
        self.assertEqual("dispatched", self.state()[0])
        self.log.error.assert_not_called()

    def test_unpersisted_decrypt_result_is_never_acknowledged(self):
        self.decrypt.side_effect = None
        self.decrypt.return_value = self.envelope
        self.send()
        self.publish.assert_not_called()
        self.handle.assert_not_called()

    def test_receipt_replay_never_creates_ack_of_ack(self):
        self.envelope["payload"] = {"type": "delivery_ack", "transport_message_id": "old-outbound"}
        ack = self.mock("acknowledge_outbound", return_value=False)
        self.send()
        self.send()
        ack.assert_called_once_with("pair", "old-outbound")
        self.publish.assert_not_called()
        self.handle.assert_not_called()

    def test_revocation_or_changed_identity_rejects_pending_body(self):
        for paired in (None, {**self.paired, "revoked_at": 1}, {**self.paired, "signal_name": "different"}):
            with self.subTest(paired=paired):
                delivery.discard_route("pair")
                self.receive()
                self.get_client.return_value = paired
                self.replay()
                self.handle.assert_not_called()
                self.publish.assert_not_called()
                self.assertEqual("rejected", self.state()[0])

    def test_expired_body_cannot_start_a_new_task(self):
        self.envelope["sent_at"] = 1
        self.envelope["expires_at"] = 2
        self.receive()
        self.replay()
        self.handle.assert_not_called()
        self.publish.assert_not_called()
        self.assertEqual("rejected", self.state()[0])

    def test_authenticated_wrong_wire_recipient_never_decrypts(self):
        self.send(to="another-desktop")
        self.decrypt.assert_not_called()
        self.publish.assert_not_called()

    def test_background_replay_uses_existing_identity_lane_and_byte_budget(self):
        self.receive()
        queued = self.mock("_queue_inbound_message", return_value=True)
        self.assertEqual(1, bridge.flush_pending_inbound_messages(object()))
        self.assertEqual("signal:phone", queued.call_args.args[1])
        message = queued.call_args.args[2]
        self.assertIsInstance(message, bridge._StoredInboxMessage)
        self.assertGreater(message.byte_count, 0)
        self.assertEqual(0, bridge.flush_pending_inbound_messages(object()))

    def test_saved_business_handoff_recovers_even_while_network_is_offline(self):
        self.mock("client", new=SimpleNamespace(is_connected=lambda: False))
        inbound = self.mock("flush_pending_inbound_messages")
        outbound = self.mock("flush_outbound_messages")
        with patch.object(bridge.outbound_retry_stop_event, "wait", side_effect=[False, True]):
            bridge._outbound_retry_loop()
        inbound.assert_called_once()
        outbound.assert_not_called()


if __name__ == "__main__":
    unittest.main()
