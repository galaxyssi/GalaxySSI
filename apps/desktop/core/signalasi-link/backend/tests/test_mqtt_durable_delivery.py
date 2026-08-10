from __future__ import annotations

import threading
import unittest
from types import SimpleNamespace
from unittest.mock import patch

import mqtt_bridge


class DurableMqttClient:
    def is_connected(self) -> bool:
        return True


class MqttDurableDeliveryTest(unittest.TestCase):
    def tearDown(self) -> None:
        mqtt_bridge.outbound_retry_stop_event.set()
        thread = mqtt_bridge.outbound_retry_thread
        if thread is not None and thread is not threading.current_thread():
            thread.join(timeout=2.0)
        mqtt_bridge.outbound_retry_thread = None

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
            patch.object(mqtt_bridge, "fail_exhausted_outbound", return_value=[]),
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
            ],
            published_topics,
        )

    def test_retry_loop_prepares_persisted_task_results_before_transport_flush(self) -> None:
        mqtt_client = DurableMqttClient()
        mqtt_bridge.outbound_retry_stop_event.clear()

        def finish_after_flush(_mqttc) -> None:
            mqtt_bridge.outbound_retry_stop_event.set()

        with (
            patch.object(mqtt_bridge, "client", mqtt_client),
            patch.object(mqtt_bridge, "OUTBOUND_RETRY_POLL_SECONDS", 0.001),
            patch.object(mqtt_bridge, "flush_pending_task_results") as task_results,
            patch.object(
                mqtt_bridge,
                "flush_outbound_messages",
                side_effect=finish_after_flush,
            ) as transport,
        ):
            mqtt_bridge._outbound_retry_loop()

        task_results.assert_called_once_with(mqtt_client)
        transport.assert_called_once_with(mqtt_client)

    def test_terminal_result_uses_reserved_slot_when_progress_fills_route(self) -> None:
        terminal = {
            "client_route_id": "current",
            "message_id": "final",
            "topic": "current/down",
            "wire_payload": "final-wire",
            "priority": mqtt_bridge.OUTBOUND_PRIORITY_TERMINAL,
        }
        published_topics: list[str] = []

        def publish(_mqttc, topic: str, _wire_payload: str):
            published_topics.append(topic)
            return SimpleNamespace(
                rc=mqtt_bridge.mqtt.MQTT_ERR_SUCCESS,
                mid=len(published_topics),
                is_published=lambda: False,
            )

        with (
            patch.object(
                mqtt_bridge,
                "list_clients",
                return_value=[{"client_route_id": "current", "last_seen_at": 1.0}],
            ),
            patch.object(
                mqtt_bridge,
                "outbound_inflight_count",
                return_value=mqtt_bridge.MAX_DURABLE_OUTBOUND_INFLIGHT_PER_CLIENT,
            ),
            patch.object(mqtt_bridge, "fail_exhausted_outbound", return_value=[]),
            patch.object(mqtt_bridge, "pending_outbound", return_value=[terminal]),
            patch.object(mqtt_bridge, "get_client", return_value={"paired": True}),
            patch.object(mqtt_bridge, "mark_outbound_sending"),
            patch.object(mqtt_bridge, "track_outbound_publish"),
            patch.object(mqtt_bridge, "_publish_mqtt_wire_payload", side_effect=publish),
        ):
            mqtt_bridge.flush_outbound_messages(DurableMqttClient())

        self.assertEqual(["current/down"], published_topics)

    def test_durable_queue_lock_is_released_before_mqtt_publish(self) -> None:
        lock_was_available = threading.Event()
        candidate = {
            "client_route_id": "current",
            "message_id": "message",
            "topic": "current/down",
            "wire_payload": "wire",
            "priority": mqtt_bridge.OUTBOUND_PRIORITY_NORMAL,
        }

        def publish(_mqttc, _topic: str, _wire_payload: str):
            def acquire_lock() -> None:
                with mqtt_bridge.durable_outbound_lock:
                    lock_was_available.set()

            worker = threading.Thread(target=acquire_lock)
            worker.start()
            worker.join(timeout=1.0)
            return SimpleNamespace(
                rc=mqtt_bridge.mqtt.MQTT_ERR_SUCCESS,
                mid=1,
                is_published=lambda: False,
            )

        with (
            patch.object(
                mqtt_bridge,
                "list_clients",
                return_value=[{"client_route_id": "current", "last_seen_at": 1.0}],
            ),
            patch.object(mqtt_bridge, "outbound_inflight_count", return_value=0),
            patch.object(mqtt_bridge, "fail_exhausted_outbound", return_value=[]),
            patch.object(mqtt_bridge, "pending_outbound", return_value=[candidate]),
            patch.object(mqtt_bridge, "get_client", return_value={"paired": True}),
            patch.object(mqtt_bridge, "mark_outbound_sending"),
            patch.object(mqtt_bridge, "track_outbound_publish"),
            patch.object(mqtt_bridge, "_publish_mqtt_wire_payload", side_effect=publish),
        ):
            mqtt_bridge.flush_outbound_messages(DurableMqttClient())

        self.assertTrue(lock_was_available.is_set())

    def test_running_progress_is_best_effort_but_terminal_event_is_durable(self) -> None:
        base_task = {
            "task_id": "task-1",
            "client_route_id": "route-1",
            "client_conversation_id": "conversation-1",
            "client_turn_id": "turn-1",
            "events": [{"event_id": "event-1", "kind": "reasoning", "title": "Working"}],
        }
        wire = {"_client_route_id": "route-1"}
        with (
            patch.object(mqtt_bridge, "_agent_task_payload", return_value={"type": "agent_task_event"}),
            patch.object(mqtt_bridge, "_publish_phone_payload", return_value=True) as publish,
        ):
            running = mqtt_bridge._PendingTaskEvent(wire, {**base_task, "status": "running"}, [])
            completed = mqtt_bridge._PendingTaskEvent(wire, {**base_task, "status": "completed"}, [])
            self.assertTrue(mqtt_bridge._try_publish_task_event(DurableMqttClient(), running))
            self.assertTrue(mqtt_bridge._try_publish_task_event(DurableMqttClient(), completed))

        self.assertFalse(publish.call_args_list[0].kwargs["durable"])
        self.assertTrue(publish.call_args_list[1].kwargs["durable"])

    def test_task_result_enqueue_restores_retry_worker(self) -> None:
        payload = {
            "task_id": "task-1",
            "client_route_id": "route-1",
            "conversation_id": "conversation-1",
            "turn_id": "turn-1",
        }
        wire_payload = {"_client_route_id": "route-1"}

        with (
            patch.object(mqtt_bridge, "queue_task_result"),
            patch.object(mqtt_bridge, "_ensure_outbound_retry_thread") as ensure_retry,
            patch.object(mqtt_bridge, "_publish_phone_payload", return_value=False),
            patch.object(mqtt_bridge, "outbound_status", return_value=None),
        ):
            published = mqtt_bridge._publish_or_queue_task_result(
                DurableMqttClient(),
                wire_payload,
                payload,
            )

        self.assertFalse(published)
        ensure_retry.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
