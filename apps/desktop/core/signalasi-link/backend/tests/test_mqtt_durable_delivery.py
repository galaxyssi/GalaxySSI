from __future__ import annotations

import unittest
from types import SimpleNamespace
from unittest.mock import patch

import mqtt_bridge


class DurableMqttClient:
    def is_connected(self) -> bool:
        return True


class MqttDurableDeliveryTest(unittest.TestCase):
    def test_existing_durable_message_does_not_advance_signal_session_again(self) -> None:
        paired_client = {
            "client_route_id": "current-route",
            "signal_name": "signalasi:phone",
            "topics": {"down": "current/down", "control": "current/control"},
        }
        with (
            patch.object(
                mqtt_bridge,
                "make_envelope",
                return_value={"message_id": "stable-message"},
            ),
            patch.object(mqtt_bridge, "outbound_status", return_value="published"),
            patch.object(mqtt_bridge, "encrypt_signal_payload") as encrypt,
            patch.object(mqtt_bridge, "flush_outbound_messages", return_value={}) as flush,
        ):
            result = mqtt_bridge._publish_to_registered_client(
                DurableMqttClient(),
                paired_client,
                {"message_id": "stable-message", "type": "text"},
            )

        encrypt.assert_not_called()
        flush.assert_called_once_with(
            unittest.mock.ANY,
            preferred_client_route_id="current-route",
        )
        self.assertTrue(result.deferred)

    def test_flush_round_robins_routes_and_prefers_current_client(self) -> None:
        clients = [
            {"client_route_id": "current", "last_seen_at": 200.0},
            {"client_route_id": "offline", "last_seen_at": 100.0},
        ]
        candidates = {
            "current": [
                {
                    "client_route_id": "current",
                    "message_id": f"current-{index}",
                    "topic": f"current/{index}",
                    "wire_payload": f"current-wire-{index}",
                }
                for index in range(4)
            ],
            "offline": [
                {
                    "client_route_id": "offline",
                    "message_id": f"offline-{index}",
                    "topic": f"offline/{index}",
                    "wire_payload": f"offline-wire-{index}",
                }
                for index in range(4)
            ],
        }
        published_topics: list[str] = []

        def pending(*, client_route_id: str, limit: int):
            return [dict(item) for item in candidates[client_route_id][:limit]]

        def publish(_mqttc, topic: str, _wire_payload: str):
            published_topics.append(topic)
            return SimpleNamespace(rc=mqtt_bridge.mqtt.MQTT_ERR_SUCCESS, mid=len(published_topics))

        with (
            patch.object(mqtt_bridge, "list_clients", return_value=clients),
            patch.object(mqtt_bridge, "outbound_inflight_count", return_value=0),
            patch.object(mqtt_bridge, "pending_outbound", side_effect=pending),
            patch.object(mqtt_bridge, "get_client", return_value={"paired": True}),
            patch.object(mqtt_bridge, "mark_outbound_sending"),
            patch.object(mqtt_bridge, "track_outbound_publish"),
            patch.object(mqtt_bridge, "_publish_mqtt_wire_payload", side_effect=publish),
        ):
            mqtt_bridge.flush_outbound_messages(
                DurableMqttClient(),
                preferred_client_route_id="current",
            )

        self.assertEqual(
            [
                "current/0", "offline/0",
                "current/1", "offline/1",
                "current/2", "offline/2",
                "current/3", "offline/3",
            ],
            published_topics,
        )


if __name__ == "__main__":
    unittest.main()
