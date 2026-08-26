from __future__ import annotations

import unittest
from unittest.mock import patch

import mqtt_bridge


PROBE_TOPIC = "p" * 43
PAIRING_TOPIC = "q" * 43
LOCAL_FINGERPRINT = "a" * 64


class FakeMqttClient:
    def __init__(self) -> None:
        self.subscriptions: list[tuple[str, int, int]] = []
        self.unsubscriptions: list[list[str]] = []
        self._next_mid = 10

    def is_connected(self) -> bool:
        return True

    def subscribe(self, topic: str, qos: int = 0) -> tuple[int, int]:
        self._next_mid += 1
        self.subscriptions.append((topic, qos, self._next_mid))
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
        self.assertEqual(expected, {topic for topic, _qos, _mid in mqttc.subscriptions})
        for topic, _qos, message_id in mqttc.subscriptions:
            mqtt_bridge.on_subscribe(mqttc, None, message_id, [1])
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
        for _topic, _qos, message_id in list(mqttc.subscriptions):
            mqtt_bridge.on_subscribe(mqttc, None, message_id, [1])

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

        self.assertEqual(expected, {topic for topic, _qos, _mid in mqttc.subscriptions})

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
        self.assertNotIn(PROBE_TOPIC, status)


if __name__ == "__main__":
    unittest.main()
