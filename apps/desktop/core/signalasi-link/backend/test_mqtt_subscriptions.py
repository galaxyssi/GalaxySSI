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

    def test_periodic_reconcile_renews_routes_even_when_local_state_says_active(self) -> None:
        mqttc = FakeMqttClient()
        client = paired_client("phone-a")
        expected_topics = {
            f"signalasichat/v1/{SERVER_ROUTE_ID}/pair",
            f"signalasichat/v1/{SERVER_ROUTE_ID}/health",
            client["topics"]["up"],
            client["topics"]["control"],
        }
        with mqtt_bridge.mqtt_subscription_lock:
            mqtt_bridge.mqtt_subscription_active.update(
                {topic: "phone-a" for topic in expected_topics}
            )
        mqtt_bridge.mqtt_subscription_last_reconcile = 1.0

        with (
            patch.object(mqtt_bridge, "client", mqttc),
            patch.object(mqtt_bridge, "server_route_id", return_value=SERVER_ROUTE_ID),
            patch.object(mqtt_bridge, "list_clients", return_value=[client]),
            patch.object(mqtt_bridge.time, "monotonic", return_value=100.0),
            patch.object(mqtt_bridge.transport_probe_state, "stalled", return_value=(False, 0.0, 1)),
            patch.object(mqtt_bridge.transport_probe_state, "should_publish", return_value=False),
        ):
            mqtt_bridge._transport_probe_tick()

        self.assertEqual(expected_topics, {topic for topic, _qos, _mid in mqttc.subscriptions})

    def test_subscription_status_reports_missing_expected_routes(self) -> None:
        client = paired_client("phone-a")
        with (
            patch.object(mqtt_bridge, "server_route_id", return_value=SERVER_ROUTE_ID),
            patch.object(mqtt_bridge, "list_clients", return_value=[client]),
        ):
            with mqtt_bridge.mqtt_subscription_lock:
                mqtt_bridge.mqtt_subscription_active[
                    f"signalasichat/v1/{SERVER_ROUTE_ID}/pair"
                ] = ""
            status = mqtt_bridge.mqtt_subscription_status()

        self.assertEqual(4, status["expected"])
        self.assertEqual(1, status["active"])
        self.assertEqual(3, status["missing"])


if __name__ == "__main__":
    unittest.main()
