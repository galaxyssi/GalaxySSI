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
            "progress_at": mqtt_bridge.mqtt_last_connection_progress_at,
            "start_count": mqtt_bridge.mqtt_worker_start_count,
        }
        mqtt_bridge.mqtt_lifecycle_stop_event.clear()
        mqtt_bridge.mqtt_connected_event.clear()
        mqtt_bridge._clear_transport_reconnect()
        mqtt_bridge.mqtt_last_connection_progress_at = 0.0

    def tearDown(self):
        mqtt_bridge.client = self.originals["client"]
        mqtt_bridge.running = self.originals["running"]
        mqtt_bridge.mqtt_worker_thread = self.originals["worker"]
        mqtt_bridge.mqtt_supervisor_thread = self.originals["supervisor"]
        mqtt_bridge.mqtt_worker_started_at = self.originals["worker_started_at"]
        mqtt_bridge.mqtt_connected_at = self.originals["connected_at"]
        mqtt_bridge.mqtt_disconnected_at = self.originals["disconnected_at"]
        mqtt_bridge.mqtt_last_error = self.originals["last_error"]
        mqtt_bridge.mqtt_last_connection_progress_at = self.originals["progress_at"]
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

    def test_server_rejections_do_not_interrupt_paho_backoff(self):
        mqttc = _DisconnectedMqtt()
        mqtt_bridge.client = mqttc
        mqtt_bridge.mqtt_disconnected_at = 100.0
        with (
            patch.object(mqtt_bridge, "_ensure_mqtt_worker", return_value=False),
            patch.object(mqtt_bridge, "_request_transport_reconnect") as recover,
            patch.object(mqtt_bridge, "_advance_mqtt_connection_generation"),
            patch.object(mqtt_bridge, "_clear_mqtt_wire_transport_state"),
        ):
            for attempt_at in (7000.0, 7030.0, 7060.0):
                with patch.object(mqtt_bridge.time, "time", return_value=attempt_at):
                    mqtt_bridge.on_pre_connect(mqttc, None)
                    mqtt_bridge.on_connect(mqttc, None, {}, "Server unavailable")
                    mqtt_bridge.on_disconnect(mqttc, None, {}, "Unspecified error", None)
                mqtt_bridge._mqtt_supervisor_tick(now=attempt_at + 29.0)
        recover.assert_not_called()
        self.assertEqual("connect_rc=Server unavailable", mqtt_bridge.mqtt_last_error)

    def test_stalled_retry_recovers_once_then_observes_cooldown(self):
        mqttc = _DisconnectedMqtt()
        mqtt_bridge.client = mqttc
        mqtt_bridge.mqtt_disconnected_at = 100.0
        mqtt_bridge.mqtt_last_connection_progress_at = 7000.0
        with (
            patch.object(mqtt_bridge, "_ensure_mqtt_worker", return_value=False),
            patch.object(mqtt_bridge, "_transport_reconnect_age", return_value=None),
            patch.object(mqtt_bridge, "_request_transport_reconnect") as recover,
        ):
            mqtt_bridge._mqtt_supervisor_tick(now=7065.0)
            mqtt_bridge._mqtt_supervisor_tick(now=7070.0)
        recover.assert_called_once_with(mqttc, "supervisor_disconnected")

    def test_connection_attempt_failure_is_progress_not_worker_stall(self):
        mqtt_bridge.client = _DisconnectedMqtt()
        mqtt_bridge.mqtt_disconnected_at = 100.0
        with patch.object(mqtt_bridge.time, "time", return_value=7000.0):
            mqtt_bridge.on_connect_fail(mqtt_bridge.client, None)
        with (
            patch.object(mqtt_bridge, "_ensure_mqtt_worker", return_value=False),
            patch.object(mqtt_bridge, "_request_transport_reconnect") as recover,
        ):
            mqtt_bridge._mqtt_supervisor_tick(now=7029.0)
        recover.assert_not_called()
        self.assertEqual("connect_attempt_failed", mqtt_bridge.mqtt_last_error)

    def test_successful_connection_clears_previous_rejection(self):
        mqtt_bridge.mqtt_last_error = "connect_rc=Server busy"
        mqtt_bridge._record_mqtt_connected()
        self.assertEqual("", mqtt_bridge.mqtt_last_error)
        self.assertTrue(mqtt_bridge.mqtt_connected_event.is_set())
        self.assertEqual(0.0, mqtt_bridge.mqtt_disconnected_at)

    def test_watchdog_rechecks_progress_before_forcing_disconnect(self):
        mqtt_bridge.client = _DisconnectedMqtt()
        mqtt_bridge.mqtt_disconnected_at = 100.0
        mqtt_bridge.mqtt_last_connection_progress_at = 100.0

        def connection_progressed():
            mqtt_bridge.mqtt_last_connection_progress_at = 7000.0
            return None

        with (
            patch.object(mqtt_bridge, "_ensure_mqtt_worker", return_value=False),
            patch.object(mqtt_bridge, "_transport_reconnect_age", side_effect=connection_progressed),
            patch.object(mqtt_bridge, "_request_transport_reconnect") as recover,
        ):
            mqtt_bridge._mqtt_supervisor_tick(now=7000.0)
        recover.assert_not_called()

    def test_offline_peer_send_returns_cause_without_publishing(self):
        mqtt_bridge.client = _DisconnectedMqtt()
        cases = [
            ("connect_rc=Server unavailable", "busy or unavailable"),
            ("connect_rc=Server busy", "busy or unavailable"),
            ("disconnect_rc=Unspecified error", "disconnected"),
        ]
        with (
            patch.object(mqtt_bridge, "get_client", return_value={"client_route_id": "test-phone"}),
            patch.object(mqtt_bridge, "_publish_phone_payload") as publish,
            patch("peer_chat_store.peer_chat_store") as store,
        ):
            for cause, expected in cases:
                with self.subTest(cause=cause):
                    mqtt_bridge.mqtt_last_error = cause
                    result = mqtt_bridge.publish_peer_message("test-phone", "test message")
                    self.assertFalse(result["ok"])
                    self.assertEqual("mqtt_not_connected", result["code"])
                    self.assertIn(expected, result["message"])
            publish.assert_not_called()
            store.assert_not_called()

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
