import unittest
from unittest.mock import patch

import mqtt_bridge


class _DeadThread:
    def is_alive(self):
        return False


class _AliveThread:
    def is_alive(self):
        return True


class _DisconnectedMqtt:
    def is_connected(self):
        return False


class MqttLifecycleSupervisorTests(unittest.TestCase):
    def setUp(self):
        self.originals = {
            "client": mqtt_bridge.client,
            "running": mqtt_bridge.running,
            "worker": mqtt_bridge.mqtt_worker_thread,
            "supervisor": mqtt_bridge.mqtt_supervisor_thread,
            "worker_started_at": mqtt_bridge.mqtt_worker_started_at,
            "connected_at": mqtt_bridge.mqtt_connected_at,
            "disconnected_at": mqtt_bridge.mqtt_disconnected_at,
            "last_error": mqtt_bridge.mqtt_last_error,
            "start_count": mqtt_bridge.mqtt_worker_start_count,
        }
        mqtt_bridge.mqtt_lifecycle_stop_event.clear()
        mqtt_bridge.mqtt_connected_event.clear()
        mqtt_bridge._clear_transport_reconnect()

    def tearDown(self):
        mqtt_bridge.client = self.originals["client"]
        mqtt_bridge.running = self.originals["running"]
        mqtt_bridge.mqtt_worker_thread = self.originals["worker"]
        mqtt_bridge.mqtt_supervisor_thread = self.originals["supervisor"]
        mqtt_bridge.mqtt_worker_started_at = self.originals["worker_started_at"]
        mqtt_bridge.mqtt_connected_at = self.originals["connected_at"]
        mqtt_bridge.mqtt_disconnected_at = self.originals["disconnected_at"]
        mqtt_bridge.mqtt_last_error = self.originals["last_error"]
        mqtt_bridge.mqtt_worker_start_count = self.originals["start_count"]
        mqtt_bridge.mqtt_lifecycle_stop_event.clear()
        mqtt_bridge.mqtt_connected_event.clear()
        mqtt_bridge._clear_transport_reconnect()

    def test_dead_worker_is_restarted(self):
        mqtt_bridge.mqtt_worker_thread = _DeadThread()

        with (
            patch.object(mqtt_bridge, "_ensure_mqtt_worker", return_value=True) as ensure,
            patch.object(mqtt_bridge, "_request_transport_reconnect") as recover,
        ):
            mqtt_bridge._mqtt_supervisor_tick(now=200.0)

        ensure.assert_called_once_with()
        recover.assert_not_called()

    def test_long_disconnected_worker_forces_transport_recovery(self):
        mqttc = _DisconnectedMqtt()
        mqtt_bridge.client = mqttc
        mqtt_bridge.mqtt_worker_thread = _AliveThread()
        mqtt_bridge.mqtt_disconnected_at = 100.0

        with (
            patch.object(mqtt_bridge, "_ensure_mqtt_worker", return_value=False),
            patch.object(mqtt_bridge, "_transport_reconnect_age", return_value=None),
            patch.object(mqtt_bridge, "_request_transport_reconnect") as recover,
            patch.object(mqtt_bridge, "MQTT_DISCONNECTED_RECOVERY_SECONDS", 30.0),
        ):
            mqtt_bridge._mqtt_supervisor_tick(now=130.0)

        recover.assert_called_once_with(mqttc, "supervisor_disconnected")

    def test_recent_disconnect_uses_paho_retry_without_forced_recovery(self):
        mqtt_bridge.client = _DisconnectedMqtt()
        mqtt_bridge.mqtt_worker_thread = _AliveThread()
        mqtt_bridge.mqtt_disconnected_at = 100.0

        with (
            patch.object(mqtt_bridge, "_ensure_mqtt_worker", return_value=False),
            patch.object(mqtt_bridge, "_request_transport_reconnect") as recover,
            patch.object(mqtt_bridge, "MQTT_DISCONNECTED_RECOVERY_SECONDS", 30.0),
        ):
            mqtt_bridge._mqtt_supervisor_tick(now=129.9)

        recover.assert_not_called()

    def test_initialization_failure_clears_running_for_next_restart(self):
        mqtt_bridge.running = False
        mqtt_bridge.mqtt_worker_start_count = 0

        with patch.object(
            mqtt_bridge,
            "ensure_transport_epoch",
            side_effect=RuntimeError("setup failed"),
        ):
            mqtt_bridge.start()

        self.assertFalse(mqtt_bridge.running)
        self.assertIsNone(mqtt_bridge.client)
        self.assertEqual(1, mqtt_bridge.mqtt_worker_start_count)
        self.assertIn("setup failed", mqtt_bridge.mqtt_last_error)

    def test_health_distinguishes_process_from_broker_connection(self):
        mqtt_bridge.running = True
        mqtt_bridge.mqtt_worker_thread = _AliveThread()
        mqtt_bridge.mqtt_supervisor_thread = _AliveThread()
        mqtt_bridge.client = _DisconnectedMqtt()
        mqtt_bridge.mqtt_disconnected_at = 100.0

        with patch.object(mqtt_bridge.time, "time", return_value=105.0):
            status = mqtt_bridge.mqtt_bridge_status()

        self.assertTrue(status["running"])
        self.assertTrue(status["supervised"])
        self.assertFalse(status["connected"])
        self.assertEqual(5.0, status["disconnected_seconds"])


if __name__ == "__main__":
    unittest.main()
