import json
import socket
import unittest
from types import SimpleNamespace
from unittest.mock import patch

import mqtt_bridge


class _PublishInfo:
    def __init__(self, rc=0):
        self.rc = rc
        self.mid = 1


class _ProbeMqtt:
    def __init__(self, rc=0):
        self.rc = rc
        self.publishes = []

    def publish(self, topic, payload, **kwargs):
        self.publishes.append((topic, json.loads(payload), kwargs))
        return _PublishInfo(self.rc)

    def is_connected(self):
        return True


class _StaleSocket:
    def __init__(self):
        self.shutdown_calls = []
        self.closed = False

    def shutdown(self, how):
        self.shutdown_calls.append(how)

    def close(self):
        self.closed = True


class _DisconnectingMqtt:
    def __init__(self):
        self.active_socket = _StaleSocket()

    def is_connected(self):
        return False

    def socket(self):
        return self.active_socket


class MqttTransportProbeStateTests(unittest.TestCase):
    def test_probe_is_inactive_until_connect_completes(self):
        state = mqtt_bridge.MqttTransportProbeState(15.0, 10.0)

        self.assertFalse(state.should_publish(100.0))
        generation = state.connected(100.0, initial_delay_seconds=2.0)

        self.assertEqual(1, generation)
        self.assertFalse(state.should_publish(101.9))
        self.assertTrue(state.should_publish(102.0))

    def test_matching_loopback_acknowledges_probe(self):
        state = mqtt_bridge.MqttTransportProbeState(15.0, 10.0)
        state.connected(100.0)
        self.assertTrue(state.begin("expected", 100.0))

        self.assertIsNone(state.acknowledge("other", 100.2))
        self.assertEqual(0.5, state.acknowledge("expected", 100.5))
        self.assertFalse(state.should_publish(115.4))
        self.assertTrue(state.should_publish(115.5))

    def test_missing_loopback_becomes_stalled(self):
        state = mqtt_bridge.MqttTransportProbeState(15.0, 10.0)
        generation = state.connected(100.0)
        self.assertTrue(state.begin("pending", 100.0))

        stalled, elapsed, observed_generation = state.stalled(109.9)
        self.assertFalse(stalled)
        self.assertAlmostEqual(9.9, elapsed)
        self.assertEqual(generation, observed_generation)
        self.assertEqual((True, 10.0, generation), state.stalled(110.0))
        state.disconnected()
        self.assertEqual((False, 0.0, generation), state.stalled(120.0))

    def test_real_transport_activity_cancels_stale_probe(self):
        state = mqtt_bridge.MqttTransportProbeState(15.0, 10.0)
        state.connected(100.0)
        self.assertTrue(state.begin("pending", 100.0))

        self.assertTrue(state.observe_transport_activity(109.5))
        self.assertEqual((False, 0.0, 1), state.stalled(120.0))
        self.assertFalse(state.should_publish(124.4))
        self.assertTrue(state.should_publish(124.5))


class MqttTransportProbeIntegrationTests(unittest.TestCase):
    def setUp(self):
        mqtt_bridge._clear_transport_reconnect()
        self.state = mqtt_bridge.MqttTransportProbeState(15.0, 10.0)
        self.state_patch = patch.object(mqtt_bridge, "transport_probe_state", self.state)
        self.topic_patch = patch.object(
            mqtt_bridge,
            "_transport_probe_topic",
            return_value="signalasichat/v1/server/health",
        )
        self.state_patch.start()
        self.topic_patch.start()

    def tearDown(self):
        mqtt_bridge._clear_transport_reconnect()
        self.topic_patch.stop()
        self.state_patch.stop()

    def test_published_probe_is_consumed_without_route_dispatch(self):
        mqttc = _ProbeMqtt()
        self.state.connected(100.0)

        self.assertTrue(mqtt_bridge._publish_transport_probe(mqttc, now=100.0))
        topic, payload, kwargs = mqttc.publishes[0]
        self.assertEqual("signalasichat/v1/server/health", topic)
        self.assertEqual("signalasi_transport_probe", payload["type"])
        self.assertEqual(mqtt_bridge.MQTT_QOS, kwargs["qos"])

        message = SimpleNamespace(
            topic=topic,
            payload=json.dumps(payload).encode("utf-8"),
        )
        with patch.object(mqtt_bridge.time, "monotonic", return_value=100.25):
            self.assertTrue(mqtt_bridge._handle_transport_probe_message(message))

        self.assertEqual((False, 0.0, 1), self.state.stalled(120.0))

    def test_invalid_probe_payload_is_consumed_but_not_acknowledged(self):
        self.state.connected(100.0)
        self.assertTrue(self.state.begin("pending", 100.0))
        message = SimpleNamespace(
            topic="signalasichat/v1/server/health",
            payload=b"not-json",
        )

        self.assertTrue(mqtt_bridge._handle_transport_probe_message(message))
        self.assertEqual((True, 10.0, 1), self.state.stalled(110.0))

    def test_authenticated_route_traffic_prevents_probe_reconnect(self):
        self.state.connected(100.0)
        self.assertTrue(self.state.begin("pending", 100.0))
        server_route = "a" * 22
        client_route = "b" * 22
        message = SimpleNamespace(
            topic=f"signalasichat/v1/{server_route}/{client_route}/up",
            payload=b"{}",
        )

        with (
            patch.object(mqtt_bridge.time, "monotonic", return_value=109.5),
            patch.object(mqtt_bridge, "server_route_id", return_value=server_route),
            patch.object(mqtt_bridge, "_queue_inbound_message") as queued,
        ):
            mqtt_bridge.on_mqtt_message(_ProbeMqtt(), None, message)

        queued.assert_called_once()
        self.assertEqual((False, 0.0, 1), self.state.stalled(120.0))

    def test_broker_publish_ack_does_not_mask_dead_inbound_transport(self):
        mqttc = _ProbeMqtt()
        generation = self.state.connected(100.0)
        self.assertTrue(self.state.begin("pending", 100.0))

        with patch.object(mqtt_bridge.time, "monotonic", return_value=109.5):
            mqtt_bridge.on_publish(mqttc, None, 42)

        self.assertEqual((True, 10.0, generation), self.state.stalled(110.0))

    def test_rejected_probe_requests_transport_recovery(self):
        mqttc = _ProbeMqtt(rc=4)
        self.state.connected(100.0)

        with patch.object(mqtt_bridge, "_request_transport_reconnect") as recover:
            self.assertFalse(mqtt_bridge._publish_transport_probe(mqttc, now=100.0))

        recover.assert_called_once_with(mqttc, "probe_publish_rc_4")

    def test_disconnect_releases_reconnect_guard(self):
        self.assertTrue(mqtt_bridge._begin_transport_reconnect(now=100.0))

        with patch.object(mqtt_bridge, "_clear_mqtt_wire_transport_state"):
            mqtt_bridge.on_disconnect(_ProbeMqtt(), None, 0)

        self.assertIsNone(mqtt_bridge._transport_reconnect_age(now=101.0))
        self.assertTrue(mqtt_bridge._begin_transport_reconnect(now=101.0))

    def test_expired_reconnect_guard_retries_recovery(self):
        mqttc = _ProbeMqtt()
        self.assertTrue(mqtt_bridge._begin_transport_reconnect(now=100.0))

        with (
            patch.object(mqtt_bridge, "client", mqttc),
            patch.object(mqtt_bridge.time, "monotonic", return_value=116.0),
            patch.object(mqtt_bridge, "_request_transport_reconnect") as recover,
        ):
            mqtt_bridge._transport_probe_tick()

        recover.assert_called_once_with(mqttc, "reconnect_guard_timeout")

    def test_force_close_releases_socket_after_paho_marks_it_disconnected(self):
        mqttc = _DisconnectingMqtt()
        generation = self.state.connected(100.0)
        self.assertTrue(self.state.begin("pending", 100.0))

        with (
            patch.object(mqtt_bridge, "client", mqttc),
            patch.object(mqtt_bridge.transport_probe_stop_event, "wait", return_value=False),
            patch.object(mqtt_bridge.time, "monotonic", return_value=110.0),
        ):
            mqtt_bridge._force_close_transport_if_still_stale(mqttc, generation)

        self.assertEqual([socket.SHUT_RDWR], mqttc.active_socket.shutdown_calls)
        self.assertTrue(mqttc.active_socket.closed)

    def test_probe_loop_survives_iteration_failure(self):
        class _StopAfterTwoIterations:
            def __init__(self):
                self.calls = 0

            def wait(self, _timeout):
                self.calls += 1
                return self.calls > 2

        stop_event = _StopAfterTwoIterations()
        with (
            patch.object(mqtt_bridge, "transport_probe_stop_event", stop_event),
            patch.object(
                mqtt_bridge,
                "_transport_probe_tick",
                side_effect=[RuntimeError("probe failure"), None],
            ) as tick,
        ):
            mqtt_bridge._transport_probe_loop()

        self.assertEqual(2, tick.call_count)


if __name__ == "__main__":
    unittest.main()
