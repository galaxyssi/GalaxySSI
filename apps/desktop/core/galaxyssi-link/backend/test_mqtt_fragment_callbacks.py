"""Adversarial fragment callbacks without a broker or private delivery state."""
import json
import threading
import time
import unittest
from contextlib import ExitStack
from types import SimpleNamespace
from unittest.mock import patch

import mqtt_bridge as bridge


class FragmentCallbacksTest(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        bridge._clear_mqtt_wire_transport_state()
        self.addCleanup(bridge._clear_mqtt_wire_transport_state)
        self.stack.enter_context(patch.object(bridge, "encode_wire_payload", return_value=["a", "b", "c"]))
        self.stack.enter_context(patch.object(bridge, "seal_wire_packet", side_effect=lambda packet, secret: packet))
        self.stack.enter_context(patch.object(bridge, "transport_timing"))
        self.published = self.stack.enter_context(patch.object(bridge, "mark_outbound_published"))
        self.retryable = self.stack.enter_context(patch.object(bridge, "mark_outbound_retryable"))
        self.mqtt = SimpleNamespace(publish=self.publish)
        self.calls = []

    def publish(self, topic, packet, qos):
        info = SimpleNamespace(mid=len(self.calls) + 1, rc=0, is_published=lambda: False)
        self.calls.append((topic, packet, info))
        return info

    def send(self, mqttc=None, topic="test/topic"):
        return bridge._publish_mqtt_wire_payload(mqttc or self.mqtt, topic, "wire", "secret")

    def test_publish_allows_disconnect_callback_to_acquire_state_lock(self):
        finished = threading.Event()
        observations = []
        threads = []

        def publish(*args, **kwargs):
            info = self.publish(*args, **kwargs)
            thread = threading.Thread(target=lambda: (bridge._clear_mqtt_wire_transport_state(), finished.set()),
                                      daemon=True)
            threads.append(thread)
            thread.start()
            observations.append(finished.wait(.3))
            return info

        self.mqtt.publish = publish
        info = self.send()
        for thread in threads:
            thread.join(1)
            self.assertFalse(thread.is_alive())
        self.assertTrue(all(observations), "MQTT publish blocked its disconnect callback")
        self.assertFalse(info.is_published())
        self.assertEqual(0, bridge.fragment_publish_inflight)
        self.assertEqual({}, bridge.fragment_publish_transfers)

    def test_inline_early_ack_completes_every_fragment(self):
        def publish(*args, **kwargs):
            info = self.publish(*args, **kwargs)
            bridge.on_publish(self.mqtt, None, info.mid)
            return info

        self.mqtt.publish = publish
        info = self.send()
        self.assertEqual(3, len(self.calls))
        self.assertTrue(info.is_published())
        self.assertEqual(0, bridge.fragment_publish_inflight)

    def test_failed_fragment_never_reports_logical_success(self):
        info = self.send()
        bridge.track_outbound_publish(info, "app-a", "message-a", mqttc=self.mqtt,
                                      generation=bridge.mqtt_connection_generation)
        bridge.on_publish(self.mqtt, None, self.calls[0][2].mid, 128)
        for _, _, physical in self.calls[1:]:
            bridge.on_publish(self.mqtt, None, physical.mid)
        self.assertFalse(info.is_published())
        self.published.assert_not_called()
        self.retryable.assert_called_once_with("app-a", "message-a")
        self.assertEqual(0, bridge.fragment_publish_inflight)

    def test_other_client_cannot_ack_same_mid(self):
        info = self.send()
        before = bridge.fragment_publish_inflight
        handled, _ = bridge._complete_fragment_publish(object(), self.calls[0][2].mid)
        self.assertFalse(handled)
        self.assertEqual(before, bridge.fragment_publish_inflight)
        self.assertFalse(info.is_published())

    def test_same_ciphertext_for_other_topic_is_not_deduplicated(self):
        first = self.send(topic="test/one")
        second = self.send(topic="test/two")
        self.assertNotEqual(first.mid, second.mid)

    def test_pending_fragment_slots_stay_bounded(self):
        for index in range(12):
            self.send(topic=f"test/{index}")
        self.assertLessEqual(bridge.fragment_publish_inflight, bridge.MAX_FRAGMENT_INFLIGHT)
        for transfer in bridge.fragment_publish_transfers.values():
            self.assertLessEqual(len(transfer.pending_mids), bridge.MAX_FRAGMENT_INFLIGHT_PER_TRANSFER)

    def test_early_failed_ack_releases_slot_and_stops_remaining_fragments(self):
        def publish(*args, **kwargs):
            info = self.publish(*args, **kwargs)
            bridge.on_publish(self.mqtt, None, info.mid, 128)
            return info

        self.mqtt.publish = publish
        info = self.send()
        self.assertEqual(1, len(self.calls))
        self.assertFalse(info.is_published())
        self.assertNotEqual(0, info.rc)
        self.assertEqual(0, bridge.fragment_publish_inflight)

    def test_generation_change_during_publish_does_not_leak_reserved_capacity(self):
        def publish(*args, **kwargs):
            info = self.publish(*args, **kwargs)
            bridge._advance_mqtt_connection_generation()
            return info

        self.mqtt.publish = publish
        info = self.send()
        self.assertNotEqual(0, info.rc)
        self.assertEqual(0, bridge.fragment_publish_inflight)
        self.assertEqual({}, bridge.fragment_publish_transfers)

    def test_old_client_ack_cannot_consume_new_client_reused_mid_after_disconnect(self):
        self.send()
        bridge._clear_mqtt_wire_transport_state()
        bridge._advance_mqtt_connection_generation()
        self.calls.clear()
        new_client = SimpleNamespace(publish=self.publish)
        current = self.send(mqttc=new_client)
        bridge.on_publish(self.mqtt, None, 1)
        self.assertEqual(3, bridge.fragment_publish_inflight)
        for _, _, physical in self.calls:
            bridge.on_publish(new_client, None, physical.mid)
        self.assertTrue(current.is_published())
        self.assertEqual(0, bridge.fragment_publish_inflight)

    def test_buffered_transfer_count_is_bounded(self):
        with patch.object(bridge, "MAX_FRAGMENT_PENDING_TRANSFERS", 2):
            self.assertEqual(0, self.send(topic="test/one").rc)
            self.assertEqual(0, self.send(topic="test/two").rc)
            self.assertEqual(bridge.mqtt.MQTT_ERR_QUEUE_SIZE, self.send(topic="test/three").rc)
        self.assertEqual(2, len(bridge.fragment_publish_transfers))

    def test_buffered_bytes_are_bounded(self):
        with patch.object(bridge, "MAX_FRAGMENT_BUFFER_BYTES", 5):
            self.assertEqual(0, self.send(topic="test/one").rc)
            self.assertEqual(bridge.mqtt.MQTT_ERR_QUEUE_SIZE, self.send(topic="test/two").rc)
        self.assertEqual(1, len(bridge.fragment_publish_transfers))

    def test_synchronous_publish_failure_releases_reserved_slot(self):
        def publish(*args, **kwargs):
            raise OSError("test disconnect")

        self.mqtt.publish = publish
        self.assertNotEqual(0, self.send().rc)
        self.assertEqual(0, bridge.fragment_publish_inflight)
        self.assertEqual({}, bridge.fragment_publish_transfers)

    def test_concurrent_publishers_use_one_pump_and_complete_all_transfers(self):
        barrier = threading.Barrier(20)
        infos = []
        failures = []
        active = 0
        maximum = 0

        def publish(*args, **kwargs):
            nonlocal active, maximum
            active += 1
            maximum = max(maximum, active)
            info = self.publish(*args, **kwargs)
            time.sleep(.001)
            bridge.on_publish(self.mqtt, None, info.mid)
            active -= 1
            return info

        def send(index):
            try:
                barrier.wait(2)
                infos.append(self.send(topic=f"test/{index}"))
            except BaseException as error:
                failures.append(error)

        self.mqtt.publish = publish
        threads = [threading.Thread(target=send, args=(index,), daemon=True) for index in range(20)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(3)
            self.assertFalse(thread.is_alive())
        self.assertEqual([], failures)
        self.assertEqual(20, len(infos))
        self.assertTrue(all(info.is_published() for info in infos))
        self.assertEqual(60, len(self.calls))
        self.assertEqual(1, maximum)
        self.assertEqual(0, bridge.fragment_publish_inflight)

    def test_clear_during_publish_preserves_new_generation_work(self):
        fresh = []

        def publish(*args, **kwargs):
            info = self.publish(*args, **kwargs)
            if len(self.calls) == 1:
                bridge._clear_mqtt_wire_transport_state()
                bridge._advance_mqtt_connection_generation()
                fresh.append(self.send(topic="test/new-generation"))
            else:
                bridge.on_publish(self.mqtt, None, info.mid)
            return info

        self.mqtt.publish = publish
        old = self.send()
        self.assertFalse(old.is_published())
        self.assertTrue(fresh[0].is_published())
        self.assertEqual(0, bridge.fragment_publish_inflight)

    def test_real_wire_encoding_reassembles_after_early_fragment_acks(self):
        from link_protocol import open_wire_packet, seal_wire_packet
        from mqtt_wire_chunking import MqttWireChunkAssembler, encode_wire_payload
        secret = "A" * 43
        wire = json.dumps({"scheme": "signal", "from": "test-a", "to": "test-b", "body": "x" * 800_000})
        assembler = MqttWireChunkAssembler()
        received = []

        def publish(*args, **kwargs):
            info = self.publish(*args, **kwargs)
            packet = json.loads(open_wire_packet(args[1], secret))
            output = assembler.accept("test-app/test-task/generation-1", packet)
            if output is not None:
                received.append(output)
            bridge.on_publish(self.mqtt, None, info.mid)
            return info

        self.mqtt.publish = publish
        with patch.object(bridge, "encode_wire_payload", encode_wire_payload), \
                patch.object(bridge, "seal_wire_packet", seal_wire_packet):
            info = bridge._publish_mqtt_wire_payload(self.mqtt, "test/topic", wire, secret)
        self.assertGreater(len(self.calls), 1)
        self.assertEqual([wire], received)
        self.assertTrue(info.is_published())
        self.assertEqual(0, bridge.fragment_publish_inflight)


if __name__ == "__main__":
    unittest.main()
