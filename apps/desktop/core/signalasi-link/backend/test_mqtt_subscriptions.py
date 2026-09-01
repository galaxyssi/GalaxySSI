from __future__ import annotations

import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import Mock, patch

import mqtt_bridge


PROBE_TOPIC = "p" * 43
PAIRING_TOPIC = "q" * 43
LOCAL_FINGERPRINT = "a" * 64


class FakeMqttClient:
    def __init__(self) -> None:
        self.subscriptions: list[tuple[list[tuple[str, int]], int]] = []
        self.unsubscriptions: list[list[str]] = []
        self._next_mid = 10

    def is_connected(self) -> bool:
        return True

    def subscribe(self, topic, qos: int = 0) -> tuple[int, int]:
        self._next_mid += 1
        request = list(topic) if isinstance(topic, list) else [(str(topic), qos)]
        self.subscriptions.append((request, self._next_mid))
        return mqtt_bridge.mqtt.MQTT_ERR_SUCCESS, self._next_mid

    def unsubscribe(self, topics) -> tuple[int, int]:
        normalized = list(topics) if isinstance(topics, (list, tuple)) else [str(topics)]
        self.unsubscriptions.append(normalized)
        self._next_mid += 1
        return mqtt_bridge.mqtt.MQTT_ERR_SUCCESS, self._next_mid


def paired_client(route_id: str, marker: str) -> dict:
    return {
        "client_route_id": route_id,
        "link_secret": marker.upper() * 43,
        "local_identity_fingerprint": LOCAL_FINGERPRINT,
        "identity_fingerprint": marker * 64,
    }


def receive_topics(client: dict) -> set[str]:
    return set(mqtt_bridge._topics_for_client(client).receive_window)


def subscribed_topics(client: FakeMqttClient) -> set[str]:
    return {
        topic
        for request, _message_id in client.subscriptions
        for topic, _qos in request
    }


def acknowledge_subscriptions(client: FakeMqttClient) -> None:
    for request, message_id in client.subscriptions:
        mqtt_bridge.on_subscribe(client, None, message_id, [qos for _topic, qos in request])


class MqttSubscriptionTests(unittest.TestCase):
    def setUp(self) -> None:
        mqtt_bridge._reset_subscription_state()

    def tearDown(self) -> None:
        mqtt_bridge._reset_subscription_state()

    def protocol_patches(self, clients):
        return (
            patch.object(mqtt_bridge, "_transport_probe_topic", return_value=PROBE_TOPIC),
            patch.object(mqtt_bridge, "active_pairing_topics", return_value=(PAIRING_TOPIC,)),
            patch.object(mqtt_bridge, "list_clients", return_value=clients),
        )

    def test_reconcile_subscribes_opaque_pairing_probe_and_receive_window(self) -> None:
        mqttc = FakeMqttClient()
        client = paired_client("phone-a", "b")
        patches = self.protocol_patches([client])
        with patches[0], patches[1], patches[2]:
            result = mqtt_bridge.reconcile_mqtt_subscriptions(mqttc, force=True)

        expected = {PROBE_TOPIC, PAIRING_TOPIC, *receive_topics(client)}
        self.assertTrue(result["ok"])
        self.assertEqual(len(expected), result["requested"])
        self.assertEqual(expected, subscribed_topics(mqttc))
        self.assertEqual(1, len(mqttc.subscriptions))
        acknowledge_subscriptions(mqttc)
        with mqtt_bridge.mqtt_subscription_lock:
            active = dict(mqtt_bridge.mqtt_subscription_active)
        for topic in receive_topics(client):
            self.assertEqual("phone-a", active[topic])

    def test_reconcile_unsubscribes_only_the_revoked_relationship_window(self) -> None:
        mqttc = FakeMqttClient()
        first = paired_client("phone-a", "b")
        second = paired_client("phone-b", "c")
        patches = self.protocol_patches([first, second])
        with patches[0], patches[1], patches[2]:
            mqtt_bridge.reconcile_mqtt_subscriptions(mqttc, force=True)
        acknowledge_subscriptions(mqttc)

        patches = self.protocol_patches([second])
        with patches[0], patches[1], patches[2]:
            result = mqtt_bridge.reconcile_mqtt_subscriptions(mqttc)

        removed = {topic for group in mqttc.unsubscriptions for topic in group}
        self.assertEqual(receive_topics(first), removed)
        self.assertEqual(3, result["removed"])
        with mqtt_bridge.mqtt_subscription_lock:
            active_topics = set(mqtt_bridge.mqtt_subscription_active)
        self.assertTrue(receive_topics(second).issubset(active_topics))

    def test_periodic_reconcile_renews_all_opaque_mailboxes(self) -> None:
        mqttc = FakeMqttClient()
        client = paired_client("phone-a", "b")
        expected = {PROBE_TOPIC, PAIRING_TOPIC, *receive_topics(client)}
        with mqtt_bridge.mqtt_subscription_lock:
            mqtt_bridge.mqtt_subscription_active.update({topic: "phone-a" for topic in expected})
        mqtt_bridge.mqtt_subscription_last_reconcile = 1.0

        patches = self.protocol_patches([client])
        with (
            patch.object(mqtt_bridge, "client", mqttc),
            patches[0], patches[1], patches[2],
            patch.object(mqtt_bridge.time, "monotonic", return_value=100.0),
            patch.object(mqtt_bridge.transport_probe_state, "stalled", return_value=(False, 0.0, 1)),
            patch.object(mqtt_bridge.transport_probe_state, "should_publish", return_value=False),
        ):
            mqtt_bridge._transport_probe_tick()

        self.assertEqual(expected, subscribed_topics(mqttc))

    def test_subscription_status_exposes_counts_not_mailbox_values(self) -> None:
        client = paired_client("phone-a", "b")
        patches = self.protocol_patches([client])
        with patches[0], patches[1], patches[2]:
            with mqtt_bridge.mqtt_subscription_lock:
                mqtt_bridge.mqtt_subscription_active[PROBE_TOPIC] = ""
            status = mqtt_bridge.mqtt_subscription_status()

        self.assertEqual(5, status["expected"])
        self.assertEqual(1, status["active"])
        self.assertEqual(4, status["missing"])
        self.assertFalse(status["ready"])
        self.assertNotIn(PROBE_TOPIC, status)

    def test_all_expected_subscriptions_become_ready_after_one_batch_ack(self) -> None:
        mqttc = FakeMqttClient()
        client = paired_client("phone-a", "b")
        patches = self.protocol_patches([client])
        with patches[0], patches[1], patches[2]:
            mqtt_bridge.reconcile_mqtt_subscriptions(mqttc, force=True)
            self.assertFalse(mqtt_bridge.mqtt_subscription_status()["ready"])
            acknowledge_subscriptions(mqttc)
            self.assertTrue(mqtt_bridge.mqtt_subscription_status()["ready"])

    def test_persistent_client_id_is_opaque_and_reused(self) -> None:
        with TemporaryDirectory() as directory:
            path = Path(directory) / "mqtt-client-id"
            first = mqtt_bridge._persistent_mqtt_client_id(path)
            second = mqtt_bridge._persistent_mqtt_client_id(path)

        self.assertEqual(first, second)
        self.assertRegex(first, mqtt_bridge.MQTT_CLIENT_ID_PATTERN)
        self.assertNotIn("signalasi", first.lower())

    def test_mqtt_client_uses_persistent_broker_session(self) -> None:
        mqtt_client = Mock()
        callback_versions = Mock()
        callback_versions.VERSION2 = object()
        with (
            patch.object(mqtt_bridge, "_persistent_mqtt_client_id", return_value="a" * 22),
            patch.object(mqtt_bridge.mqtt, "CallbackAPIVersion", callback_versions),
            patch.object(mqtt_bridge.mqtt, "Client", return_value=mqtt_client) as constructor,
        ):
            created = mqtt_bridge._new_mqtt_client()

        self.assertIs(mqtt_client, created)
        constructor.assert_called_once_with(
            callback_api_version=callback_versions.VERSION2,
            client_id="a" * 22,
            clean_session=False,
        )


if __name__ == "__main__":
    unittest.main()
