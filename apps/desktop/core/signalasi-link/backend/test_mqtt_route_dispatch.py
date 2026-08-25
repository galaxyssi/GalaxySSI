from __future__ import annotations

import json
import tempfile
import threading
import time
import unittest
from unittest.mock import ANY, patch

import link_protocol
import mqtt_bridge
import mqtt_wire_chunking


LINK_SECRET = "A" * 43
LOCAL_FINGERPRINT = "a" * 64
REMOTE_FINGERPRINT = "b" * 64


def paired_client(route_id: str = "client", signal_name: str = "phone-signal-id") -> dict:
    return {
        "client_route_id": route_id,
        "signal_name": signal_name,
        "link_secret": LINK_SECRET,
        "local_identity_fingerprint": LOCAL_FINGERPRINT,
        "identity_fingerprint": REMOTE_FINGERPRINT,
        "last_seen_at": 1,
    }


class FakeMessage:
    def __init__(self, topic: str, payload: bytes = b"{}") -> None:
        self.topic = topic
        self.payload = payload


class AlreadyPublishedInfo:
    mid = 41

    @staticmethod
    def is_published() -> bool:
        return True


class FakePublishInfo:
    def __init__(self, mid: int, rc: int = 0) -> None:
        self.mid = mid
        self.rc = rc

    @staticmethod
    def is_published() -> bool:
        return False


class RecordingMqtt:
    def __init__(self) -> None:
        self.published: list[tuple[str, str, int, FakePublishInfo]] = []

    def publish(self, topic: str, payload: str, qos: int = 0) -> FakePublishInfo:
        info = FakePublishInfo(len(self.published) + 1)
        self.published.append((topic, payload, qos, info))
        return info

    @staticmethod
    def is_connected() -> bool:
        return True


class RacingPublishMqtt:
    """Dispatch the broker ACK while durable publish registration is in flight."""

    def __init__(self) -> None:
        self.ack_started = threading.Event()
        self.ack_finished = threading.Event()
        self.ack_thread: threading.Thread | None = None

    def publish(self, _topic: str, _payload: str, qos: int = 0) -> FakePublishInfo:
        del qos
        info = FakePublishInfo(71)

        def acknowledge() -> None:
            self.ack_started.set()
            mqtt_bridge.on_publish(self, None, info.mid)
            self.ack_finished.set()

        self.ack_thread = threading.Thread(target=acknowledge)
        self.ack_thread.start()
        self.assert_ack_started()
        return info

    def assert_ack_started(self) -> None:
        if not self.ack_started.wait(1):
            raise AssertionError("broker ACK thread did not start")

    @staticmethod
    def is_connected() -> bool:
        return True


class MqttRouteDispatchTests(unittest.TestCase):
    def setUp(self) -> None:
        mqtt_bridge._stop_inbound_route_workers()
        mqtt_bridge._clear_mqtt_wire_transport_state()

    def tearDown(self) -> None:
        mqtt_bridge._stop_inbound_route_workers()
        mqtt_bridge._clear_mqtt_wire_transport_state()
        with mqtt_bridge.pending_outbound_acks_lock:
            mqtt_bridge.pending_outbound_acks.clear()

    @staticmethod
    def _route(topic: str):
        route_id = "old-route" if topic == "old" else "current-route"
        return "client", paired_client(route_id)

    def test_stalled_old_route_does_not_block_current_phone(self) -> None:
        old_started = threading.Event()
        release_old = threading.Event()
        current_processed = threading.Event()

        def process(_mqttc, _userdata, message) -> None:
            if message.topic == "old":
                old_started.set()
                release_old.wait(2)
            else:
                current_processed.set()

        with (
            patch.object(mqtt_bridge, "_resolve_inbound_topic", side_effect=self._route),
            patch.object(mqtt_bridge, "_process_message", side_effect=process),
        ):
            mqtt_bridge.on_mqtt_message(object(), None, FakeMessage("old"))
            self.assertTrue(old_started.wait(1))
            mqtt_bridge.on_mqtt_message(object(), None, FakeMessage("current"))
            self.assertTrue(current_processed.wait(1))
            release_old.set()

    def test_signal_messages_remain_ordered_within_one_route(self) -> None:
        first_started = threading.Event()
        release_first = threading.Event()
        second_processed = threading.Event()
        processed: list[bytes] = []

        def process(_mqttc, _userdata, message) -> None:
            if message.payload == b"first":
                first_started.set()
                release_first.wait(2)
            processed.append(message.payload)
            if message.payload == b"second":
                second_processed.set()

        with (
            patch.object(
                mqtt_bridge,
                "_resolve_inbound_topic",
                return_value=("client", paired_client("one-route")),
            ),
            patch.object(mqtt_bridge, "_process_message", side_effect=process),
        ):
            mqtt_bridge.on_mqtt_message(object(), None, FakeMessage("same", b"first"))
            self.assertTrue(first_started.wait(1))
            mqtt_bridge.on_mqtt_message(object(), None, FakeMessage("same", b"second"))
            time.sleep(0.05)
            self.assertFalse(second_processed.is_set())
            release_first.set()
            self.assertTrue(second_processed.wait(1))

        self.assertEqual([b"first", b"second"], processed)

    def test_route_worker_survives_one_failed_message(self) -> None:
        second_processed = threading.Event()
        processed: list[bytes] = []

        def process(_mqttc, _userdata, message) -> None:
            processed.append(message.payload)
            if message.payload == b"first":
                raise RuntimeError("transient inbound failure")
            second_processed.set()

        with (
            patch.object(
                mqtt_bridge,
                "_resolve_inbound_topic",
                return_value=("client", paired_client("one-route")),
            ),
            patch.object(mqtt_bridge, "_process_message", side_effect=process),
        ):
            mqtt_bridge.on_mqtt_message(object(), None, FakeMessage("same", b"first"))
            mqtt_bridge.on_mqtt_message(object(), None, FakeMessage("same", b"second"))
            self.assertTrue(second_processed.wait(1))

        self.assertEqual([b"first", b"second"], processed)

    def test_publish_ack_that_wins_the_tracking_race_is_persisted(self) -> None:
        with patch.object(mqtt_bridge, "mark_outbound_published") as mark_published:
            mqtt_bridge.track_outbound_publish(AlreadyPublishedInfo(), "route", "message")

        mark_published.assert_called_once_with("route", "message")
        self.assertNotIn(AlreadyPublishedInfo.mid, mqtt_bridge.pending_outbound_acks)

    def test_broker_ack_defers_delivery_ack_outside_paho_callback(self) -> None:
        ack = {"source_message_id": "source", "_client_route_id": "client"}
        with mqtt_bridge.pending_delivery_acks_lock:
            mqtt_bridge.pending_delivery_acks[91] = ack

        with (
            patch.object(mqtt_bridge, "enqueue_delivery_ack") as enqueue,
            patch.object(mqtt_bridge, "publish_delivery_ack") as publish,
        ):
            callback = threading.Thread(
                target=mqtt_bridge.on_publish,
                args=(object(), None, 91),
            )
            callback.start()
            callback.join(timeout=0.5)

        self.assertFalse(callback.is_alive())
        enqueue.assert_called_once_with(ANY, ack, None)
        publish.assert_not_called()

    def test_already_published_delivery_ack_is_queued(self) -> None:
        payload = {"source_message_id": "source", "_client_route_id": "client"}
        mqttc = object()

        with patch.object(mqtt_bridge, "enqueue_delivery_ack") as enqueue:
            mqtt_bridge.track_delivery_ack(
                mqttc,
                AlreadyPublishedInfo(),
                payload,
                "desktop_reply_broker_ack",
            )

        enqueue.assert_called_once()
        self.assertIs(enqueue.call_args.args[0], mqttc)
        self.assertEqual("source", enqueue.call_args.args[1]["source_message_id"])

    def test_flush_registers_durable_message_before_early_broker_ack(self) -> None:
        mqttc = RacingPublishMqtt()
        pending = [{
            "client_route_id": "client",
            "message_id": "second-result",
            "topic": "topic/down",
            "wire_payload": "wire-result",
        }]
        with (
            patch.object(mqtt_bridge, "outbound_inflight_count", return_value=0),
            patch.object(
                mqtt_bridge,
                "list_clients",
                return_value=[paired_client()],
            ),
            patch.object(mqtt_bridge, "pending_outbound", return_value=pending),
            patch.object(mqtt_bridge, "fail_exhausted_outbound", return_value=[]),
            patch.object(mqtt_bridge, "get_client", return_value=paired_client()),
            patch.object(mqtt_bridge, "mark_outbound_sending"),
            patch.object(mqtt_bridge, "mark_outbound_published") as mark_published,
        ):
            published = mqtt_bridge.flush_outbound_messages(mqttc)
            self.assertTrue(mqttc.ack_finished.wait(1))

        if mqttc.ack_thread is not None:
            mqttc.ack_thread.join(timeout=1)
        self.assertEqual({("client", "second-result")}, set(published))
        mark_published.assert_called_once_with("client", "second-result")
        self.assertNotIn(71, mqtt_bridge.pending_outbound_acks)

    def test_durable_flush_never_exceeds_available_application_ack_window(self) -> None:
        mqttc = RecordingMqtt()
        pending = [
            {
                "client_route_id": "client",
                "message_id": f"message-{index}",
                "topic": "topic/down",
                "wire_payload": f"wire-{index}",
            }
            for index in range(4)
        ]
        with (
            patch.object(
                mqtt_bridge,
                "outbound_inflight_count",
                side_effect=lambda client_route_id="": (
                    0
                    if client_route_id
                    else mqtt_bridge.MAX_DURABLE_OUTBOUND_INFLIGHT - 1
                ),
            ),
            patch.object(
                mqtt_bridge,
                "list_clients",
                return_value=[paired_client()],
            ),
            patch.object(mqtt_bridge, "pending_outbound", return_value=pending[:1]) as select,
            patch.object(mqtt_bridge, "fail_exhausted_outbound", return_value=[]),
            patch.object(mqtt_bridge, "get_client", return_value=paired_client()),
            patch.object(mqtt_bridge, "mark_outbound_sending") as mark_sending,
            patch.object(mqtt_bridge, "track_outbound_publish") as track,
        ):
            published = mqtt_bridge.flush_outbound_messages(mqttc)

        select.assert_called_once_with(
            limit=mqtt_bridge.MAX_DURABLE_OUTBOUND_BATCH,
            client_route_id="client",
        )
        mark_sending.assert_called_once_with("client", "message-0")
        track.assert_called_once()
        self.assertEqual({("client", "message-0")}, set(published))
        self.assertEqual(1, len(mqttc.published))

    def test_deferred_durable_publish_does_not_claim_a_broker_ack(self) -> None:
        client_record = paired_client()
        with (
            patch.object(mqtt_bridge, "_wire_client", return_value=client_record),
            patch.object(
                mqtt_bridge,
                "_publish_to_registered_client",
                return_value=mqtt_bridge._DeferredPublishInfo(),
            ),
            patch.object(mqtt_bridge, "track_delivery_ack") as track,
        ):
            published = mqtt_bridge._publish_phone_payload(
                object(),
                {"_client_route_id": "client"},
                {"type": "chat", "source_message_id": "source"},
            )

        self.assertTrue(published)
        track.assert_not_called()

    def test_running_task_progress_is_volatile_but_failure_is_durable(self) -> None:
        pending = mqtt_bridge._PendingTaskEvent(
            wire_payload={"_client_route_id": "client"},
            task={"task_id": "task", "status": "running", "events": []},
            trace=[],
        )
        with (
            patch.object(mqtt_bridge, "desktop_id", return_value="desktop"),
            patch.object(mqtt_bridge, "desktop_name", return_value="Desktop"),
            patch.object(mqtt_bridge, "mobile_connector_agents", return_value=[]),
            patch.object(mqtt_bridge, "_publish_phone_payload", return_value=True) as publish,
        ):
            self.assertTrue(mqtt_bridge._try_publish_task_event(RecordingMqtt(), pending))
            pending.task["status"] = "failed"
            self.assertTrue(mqtt_bridge._try_publish_task_event(RecordingMqtt(), pending))

        self.assertFalse(publish.call_args_list[0].kwargs["durable"])
        self.assertTrue(publish.call_args_list[1].kwargs["durable"])

    def test_large_transfer_never_occupies_reserved_small_message_slots(self) -> None:
        mqttc = RecordingMqtt()
        large = '{"scheme":"signal","from":"phone","to":"desktop","body":"' + ("x" * 300_000) + '"}'
        packet_count = len(mqtt_wire_chunking.encode_wire_payload(large))
        initial_fragment_count = min(
            packet_count,
            mqtt_bridge.MAX_FRAGMENT_INFLIGHT_PER_TRANSFER,
        )

        fragmented = mqtt_bridge._publish_mqtt_wire_payload(
            mqttc, "l" * 43, large, LINK_SECRET
        )

        self.assertLess(fragmented.mid, 0)
        self.assertEqual(initial_fragment_count, len(mqttc.published))
        self.assertEqual(initial_fragment_count, mqtt_bridge.fragment_publish_inflight)
        self.assertLess(mqtt_bridge.fragment_publish_inflight, mqtt_bridge.MQTT_MAX_INFLIGHT)

        direct = mqtt_bridge._publish_mqtt_wire_payload(
            mqttc,
            "s" * 43,
            '{"scheme":"signal","body":"hello"}',
            LINK_SECRET,
        )

        self.assertGreater(direct.mid, 0)
        self.assertEqual(initial_fragment_count + 1, len(mqttc.published))
        first_fragment_mid = mqttc.published[0][3].mid
        handled, logical_mid = mqtt_bridge._complete_fragment_publish(mqttc, first_fragment_mid)
        self.assertTrue(handled)
        self.assertIsNone(logical_mid)
        expected_after_ack = initial_fragment_count + 1
        if initial_fragment_count < packet_count:
            expected_after_ack += 1
        self.assertEqual(expected_after_ack, len(mqttc.published))

    def test_fragmented_envelope_is_decrypted_only_after_complete_integrity_check(self) -> None:
        encrypted_wire = json.dumps(
            {
                "scheme": "signal",
                "from": "phone-signal-id",
                "to": "desktop-signal-id",
                "body": "x" * 180_000,
            },
            separators=(",", ":"),
        )
        packets = mqtt_wire_chunking.encode_wire_payload(encrypted_wire)
        client_record = paired_client("client-route")
        mqttc = RecordingMqtt()
        decrypted = link_protocol.make_envelope(
            {"type": "text", "content": "hello"},
            source_id="phone-signal-id",
            target_id="desktop-signal-id",
            conversation_id="conversation-fragment",
        )

        with (
            patch.object(
                mqtt_bridge,
                "_resolve_inbound_topic",
                return_value=("client", client_record),
            ),
            patch.object(mqtt_bridge, "desktop_id", return_value="desktop-signal-id"),
            patch.object(mqtt_bridge, "get_client", return_value=client_record),
            patch.object(mqtt_bridge, "message_for_ciphertext", return_value=""),
            patch.object(mqtt_bridge, "decrypt_signal_envelope", return_value=decrypted) as decrypt,
            patch.object(mqtt_bridge, "bind_ciphertext"),
            patch.object(mqtt_bridge, "claim_message", return_value=True),
            patch.object(mqtt_bridge, "touch_client"),
            patch.object(mqtt_bridge, "complete_message"),
            patch.object(mqtt_bridge, "_publish_phone_payload", return_value=True),
            patch.object(mqtt_bridge, "_start_remote_agent_task"),
        ):
            for packet in packets[:-1]:
                mqtt_bridge._process_message(
                    mqttc,
                    None,
                    FakeMessage(
                        "t" * 43,
                        link_protocol.seal_wire_packet(packet, LINK_SECRET).encode("ascii"),
                    ),
                )
                decrypt.assert_not_called()

            mqtt_bridge._process_message(
                mqttc,
                None,
                FakeMessage(
                    "t" * 43,
                    link_protocol.seal_wire_packet(packets[-1], LINK_SECRET).encode("ascii"),
                ),
            )

        decrypt.assert_called_once()

    def test_signal_ciphertext_replay_is_acknowledged_without_decrypting_again(self) -> None:
        message_id = "11111111-1111-4111-8111-111111111111"
        encrypted_wire = {
            "scheme": "signal",
            "from": "phone-signal-id",
            "to": "desktop-signal-id",
            "message_type": 2,
            "body": "ciphertext",
        }
        client_record = paired_client("client-route")
        mqttc = RecordingMqtt()

        with (
            patch.object(
                mqtt_bridge,
                "_resolve_inbound_topic",
                return_value=("client", client_record),
            ),
            patch.object(mqtt_bridge, "desktop_id", return_value="desktop-signal-id"),
            patch.object(mqtt_bridge, "get_client", return_value=client_record),
            patch.object(mqtt_bridge, "message_for_ciphertext", return_value=message_id),
            patch.object(mqtt_bridge, "previous_acknowledgement", return_value={"status": "accepted"}),
            patch.object(mqtt_bridge, "decrypt_signal_envelope") as decrypt,
            patch.object(mqtt_bridge, "_publish_phone_payload", return_value=True) as publish,
        ):
            mqtt_bridge._process_message(
                mqttc,
                None,
                FakeMessage(
                    "t" * 43,
                    link_protocol.seal_wire_packet(
                        json.dumps(encrypted_wire), LINK_SECRET
                    ).encode("ascii"),
                ),
            )

        decrypt.assert_not_called()
        publish.assert_called_once()
        self.assertEqual("delivery_ack", publish.call_args.args[2]["type"])
        self.assertEqual(message_id, publish.call_args.args[2]["transport_message_id"])
        self.assertNotIn("message_id", publish.call_args.args[2])
        self.assertTrue(publish.call_args.args[2]["duplicate"])

    def test_returned_image_intent_is_detected_without_matching_plain_grading(self) -> None:
        self.assertTrue(mqtt_bridge._requests_returned_image("Annotate this and return the image"))
        self.assertTrue(mqtt_bridge._requests_returned_image("\u6279\u6539\u4f5c\u4e1a\u5e76\u53d1\u56de\u6765\u56fe\u7247"))
        self.assertFalse(mqtt_bridge._requests_returned_image("\u6279\u6539\u4f5c\u4e1a"))

    def test_returned_image_intent_uses_only_the_current_user_request(self) -> None:
        prompt = (
            "[SIGNALASI_CONVERSATION_CONTEXT_V1]\n"
            '{"turns":[{"role":"user","content":"Annotate this and return the image"}]}\n'
            "[/SIGNALASI_CONVERSATION_CONTEXT_V1]\n\n"
            "Current user request:\n"
            "What is the brand title in this image? Reply only with the title."
        )
        self.assertFalse(mqtt_bridge._current_request_needs_returned_image(prompt))

        prompt = (
            "[SIGNALASI_CONVERSATION_CONTEXT_V1]\n"
            '{"turns":[{"role":"assistant","content":"The brand is SignalASI"}]}\n'
            "[/SIGNALASI_CONVERSATION_CONTEXT_V1]\n\n"
            "Current user request:\n"
            "Add a blue border and return the edited image."
        )
        self.assertTrue(mqtt_bridge._current_request_needs_returned_image(prompt))

    def test_returned_image_contract_targets_output_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = mqtt_bridge.Path(temporary)
            source = root / "input.jpg"
            source.write_bytes(b"image")
            contract = mqtt_bridge._returned_image_artifact_contract(
                root / "outputs",
                [source],
            )

        self.assertIn("finished annotated image", contract)
        self.assertIn(str(source.resolve()), contract)
        self.assertIn("Never claim that the input image is missing", contract)
        self.assertIn("ASCII-only", contract)
        self.assertIn("annotated-result.jpg", contract)

    def test_verified_phone_image_is_materialized_for_codex_local_image_input(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = mqtt_bridge.Path(temporary)
            transfer = root / "verified-transfer.bin"
            transfer.write_bytes(b"verified-image")
            task_input = root / "task" / "downloads" / "input"
            task_input.mkdir(parents=True)

            materialized = mqtt_bridge._materialize_verified_task_attachment(
                transfer,
                task_input,
                0,
                "../phone-photo.jpg",
            )

            self.assertEqual(task_input / "01-phone-photo.jpg", materialized)
            self.assertEqual(b"verified-image", materialized.read_bytes())
            self.assertEqual([materialized], sorted(task_input.glob("*")))

    def test_missing_returned_image_message_keeps_current_input(self) -> None:
        chinese = mqtt_bridge._missing_returned_image_message("\u6279\u6539\u56fe\u7247")
        english = mqtt_bridge._missing_returned_image_message("Annotate this image")

        self.assertIn("\u539f\u56fe\u5df2\u6536\u5230", chinese)
        self.assertIn("\u6cbf\u7528\u5f53\u524d\u56fe\u7247", chinese)
        self.assertNotIn("\u91cd\u65b0\u53d1\u9001", chinese)
        self.assertIn("original image was received", english)
        self.assertIn("current image", english)


if __name__ == "__main__":
    unittest.main()
