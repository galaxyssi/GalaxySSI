from __future__ import annotations

import unittest
from unittest.mock import patch

import mqtt_bridge

SERVER_ROUTE_ID = "AAAAAAAAAAAAAAAAAAAAAA"


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


def paired_client(route_id: str) -> dict:
    return {
        "client_route_id": route_id,
        "topics": {
            "up": f"signalasichat/v1/{SERVER_ROUTE_ID}/{route_id}/up",
            "control": f"signalasichat/v1/{SERVER_ROUTE_ID}/{route_id}/control",
        },
    }


class MqttSubscriptionTests(unittest.TestCase):
    def setUp(self) -> None:
        mqtt_bridge._reset_subscription_state()

    def tearDown(self) -> None:
        mqtt_bridge._reset_subscription_state()

    def test_reconcile_subscribes_each_active_client_and_tracks_suback(self) -> None:
        mqttc = FakeMqttClient()
        with (
            patch.object(mqtt_bridge, "server_route_id", return_value=SERVER_ROUTE_ID),
            patch.object(mqtt_bridge, "list_clients", return_value=[paired_client("phone-a")]),
        ):
            result = mqtt_bridge.reconcile_mqtt_subscriptions(mqttc, force=True)

        self.assertTrue(result["ok"])
        self.assertEqual(4, result["requested"])
        for topic, _qos, message_id in mqttc.subscriptions:
            mqtt_bridge.on_subscribe(mqttc, None, message_id, [1])
        with mqtt_bridge.mqtt_subscription_lock:
            active = dict(mqtt_bridge.mqtt_subscription_active)
        self.assertEqual("phone-a", active[f"signalasichat/v1/{SERVER_ROUTE_ID}/phone-a/up"])
        self.assertEqual("phone-a", active[f"signalasichat/v1/{SERVER_ROUTE_ID}/phone-a/control"])

    def test_reconcile_unsubscribes_revoked_client_without_touching_active_client(self) -> None:
        mqttc = FakeMqttClient()
        with (
            patch.object(mqtt_bridge, "server_route_id", return_value=SERVER_ROUTE_ID),
            patch.object(
                mqtt_bridge,
                "list_clients",
                return_value=[paired_client("phone-a"), paired_client("phone-b")],
            ),
        ):
            mqtt_bridge.reconcile_mqtt_subscriptions(mqttc, force=True)
        for _topic, _qos, message_id in list(mqttc.subscriptions):
            mqtt_bridge.on_subscribe(mqttc, None, message_id, [1])

        with (
            patch.object(mqtt_bridge, "server_route_id", return_value=SERVER_ROUTE_ID),
            patch.object(mqtt_bridge, "list_clients", return_value=[paired_client("phone-b")]),
        ):
            result = mqtt_bridge.reconcile_mqtt_subscriptions(mqttc)

        removed = {topic for group in mqttc.unsubscriptions for topic in group}
        self.assertEqual(2, result["removed"])
        self.assertIn(f"signalasichat/v1/{SERVER_ROUTE_ID}/phone-a/up", removed)
        self.assertIn(f"signalasichat/v1/{SERVER_ROUTE_ID}/phone-a/control", removed)
        with mqtt_bridge.mqtt_subscription_lock:
            active_topics = set(mqtt_bridge.mqtt_subscription_active)
        self.assertIn(f"signalasichat/v1/{SERVER_ROUTE_ID}/phone-b/up", active_topics)


if __name__ == "__main__":
    unittest.main()
