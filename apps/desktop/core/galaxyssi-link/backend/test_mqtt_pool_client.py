from itertools import permutations
import time
import unittest
from unittest.mock import Mock

from mqtt_broker_catalog import BROKER_IDS
from mqtt_broker_pool import Ingress
from mqtt_multipath_policy import PeerRoute, Traffic
from mqtt_pool_client import MqttPoolClient, Publication
from tests.mqtt_pool_fixture import ManualPool


class MqttPoolClientTest(unittest.TestCase):
    def setUp(self):
        self.publication = Publication("pair", "message", "a" * 64, Traffic.MESSAGE, frozenset({"inbox"}))
        self.client = MqttPoolClient(classify_publication=lambda *_: self.publication, pool_factory=ManualPool)
        self.addCleanup(self.client.disconnect)
        self.pool = self.client._pool
        self.connected, self.disconnected, self.subscribed, self.published, self.messages = (Mock() for _ in range(5))
        self.client.on_connect, self.client.on_disconnect = self.connected, self.disconnected
        self.client.on_subscribe, self.client.on_publish = self.subscribed, self.published
        self.client.on_message = self.messages
        self.client.subscribe([("inbox", 1)])

    def ready(self):
        for broker in BROKER_IDS:
            self.pool.connect(broker)
        self.client.policy.accept_verified_resume("pair", PeerRoute(
            1, frozenset(BROKER_IDS), 1048576, True, time.monotonic() + 200), now=time.monotonic())

    def test_no_fixed_broker_order_or_wait_all_connection(self):
        for order in permutations(BROKER_IDS):
            with self.subTest(order=order):
                client = MqttPoolClient(classify_publication=lambda *_: None, pool_factory=ManualPool)
                client.on_connect = Mock()
                client.subscribe({"inbox": 1})
                client._pool.connect(order[0])
                self.assertTrue(client.is_connected())
                self.assertEqual({"inbox"}, client.active_topics())
                for broker in order[1:]:
                    client._pool.connect(broker)
                client.on_connect.assert_called_once()
                client.disconnect()

    def test_repeated_start_shares_one_pool(self):
        self.client.start()
        self.client.start()
        self.assertEqual(1, self.pool.start_count)

    def test_connected_without_authenticated_route_cannot_publish_business(self):
        self.pool.connect("hivemq")
        self.assertNotEqual(0, self.client.publish("outbox", b"ciphertext").rc)
        self.assertEqual([], self.pool.sent)

    def test_missing_suback_cannot_be_used_for_business(self):
        self.pool.auto_suback = False
        self.ready()
        self.assertEqual(set(), self.client.active_topics())
        self.assertNotEqual(0, self.client.publish("outbox", b"ciphertext").rc)

    def test_split_subacks_cannot_complete_one_receive_window(self):
        self.pool.auto_suback = False
        self.client.subscribe({"inbox": 1, "previous-inbox": 1})
        self.ready()
        self.pool.confirm("emqx", {"inbox"})
        self.subscribed.reset_mock()
        self.pool.confirm("hivemq", {"previous-inbox"})
        self.subscribed.assert_not_called()
        self.assertEqual({}, self.client.ready_path_generations({"inbox", "previous-inbox"}))
        self.pool.confirm("hivemq", {"inbox"})
        self.subscribed.assert_called_once()

    def test_delayed_suback_after_unsubscribe_cannot_restore_policy_readiness(self):
        self.ready()
        self.client.unsubscribe("inbox")
        self.client._subscribed(Ingress("hivemq", 1, time.monotonic()), {"inbox"}, True)
        self.assertEqual(frozenset(), self.client.policy.ready_brokers({"inbox"}))
        self.assertNotEqual(0, self.client.publish("outbox", b"ciphertext").rc)

    def test_empty_receive_window_is_never_ready(self):
        self.ready()
        self.assertEqual({}, self.client.ready_path_generations(set()))

    def test_one_disconnect_does_not_reset_other_paths_or_global_generation(self):
        self.ready()
        self.pool.lose("emqx")
        self.disconnected.assert_not_called()
        self.assertTrue(self.client.is_connected())
        self.assertEqual(0, self.client.publish("outbox", b"ciphertext").rc)
        self.assertNotEqual("emqx", self.pool.sent[-1][0])
        self.pool.lose("hivemq")
        self.pool.lose("mosquitto")
        self.disconnected.assert_called_once()

    def test_last_path_recovery_has_one_aggregate_connect_callback(self):
        self.ready()
        for broker in BROKER_IDS:
            self.pool.lose(broker)
        self.pool.connect("mosquitto", 2)
        self.assertEqual(2, self.connected.call_count)
        self.assertTrue(self.client.is_connected())

    def test_delayed_old_connect_and_suback_cannot_resurrect_dead_path(self):
        self.ready()
        self.pool.lose("emqx")
        self.client._state(Ingress("emqx", 1, time.monotonic()), "connected", "")
        self.client._subscribed(Ingress("emqx", 1, time.monotonic()), {"inbox"}, True)
        self.assertNotIn("emqx", self.client.policy.ready_brokers({"inbox"}))

    def test_disconnect_before_delayed_connack_keeps_the_generation_retired(self):
        self.client._state(Ingress("hivemq", 1, time.monotonic()), "disconnected", "closed")
        self.client._state(Ingress("hivemq", 1, time.monotonic()), "connected", "")
        self.client._subscribed(Ingress("hivemq", 1, time.monotonic()), {"inbox"}, True)
        self.assertFalse(self.client.is_connected())
        self.assertEqual({}, self.client.ready_path_generations({"inbox"}))
        self.connected.assert_not_called()

    def test_colliding_native_ids_have_independent_logical_callbacks(self):
        self.ready()
        self.pool.auto_ack = False
        logical = []
        for broker in BROKER_IDS:
            descriptor = Publication("pair", "message", "a" * 64, Traffic.CONTROL,
                                     frozenset({"inbox"}), True, broker)
            logical.append(self.client.publish("outbox", b"ciphertext", publication=descriptor).mid)
        self.assertEqual(3, len(set(logical)))
        for native in list(self.pool.pending):
            self.pool.ack(native)
        self.assertEqual(set(logical), {call.args[2] for call in self.published.call_args_list})

    def test_synchronous_puback_is_not_lost(self):
        self.ready()
        info = self.client.publish("outbox", b"ciphertext")
        self.assertTrue(info.is_published())
        self.published.assert_called_once()
        self.assertEqual(0, self.client.policy.diagnostics()["inflight_packets"])

    def test_aggregate_budget_retains_two_control_slots(self):
        self.ready()
        self.pool.auto_ack = False
        for _ in range(10):
            self.assertEqual(0, self.client.publish("outbox", b"ciphertext").rc)
        self.assertNotEqual(0, self.client.publish("outbox", b"ciphertext").rc)
        control = Publication("pair", "control", "b" * 64, Traffic.CONTROL, frozenset({"inbox"}))
        for _ in range(2):
            self.assertEqual(0, self.client.publish("outbox", b"stop", publication=control).rc)
        self.assertNotEqual(0, self.client.publish("outbox", b"stop", publication=control).rc)
        self.assertEqual(12, self.client.policy.diagnostics()["inflight_packets"])

    def test_failed_path_only_fails_its_pending_physical_tokens(self):
        self.ready()
        self.pool.auto_ack = False
        first = self.client.publish("outbox", b"one", publication=Publication(
            "pair", "one", "a" * 64, Traffic.CONTROL, frozenset({"inbox"}), True, "emqx"))
        second = self.client.publish("outbox", b"two", publication=Publication(
            "pair", "two", "b" * 64, Traffic.CONTROL, frozenset({"inbox"}), True, "hivemq"))
        self.pool.lose("emqx")
        self.assertNotEqual(0, first.rc)
        self.assertFalse(second._done.is_set())
        self.assertEqual(1, self.client.policy.diagnostics()["inflight_packets"])

    def test_repeated_subscribe_coalesces_pending_request(self):
        first = self.client.subscribe({"inbox": 1})
        second = self.client.subscribe({"inbox": 1})
        self.assertEqual(first, second)
        self.pool.connect("hivemq")
        self.subscribed.assert_called_once()

    def test_unsubscribe_removes_receive_path_before_wire_ack(self):
        self.ready()
        self.client.unsubscribe("inbox")
        self.assertEqual(set(), self.client.active_topics())
        self.assertEqual(frozenset(), self.client.policy.ready_brokers({"inbox"}))

    def test_ingress_carries_broker_and_generation_to_existing_callback(self):
        self.ready()
        self.client._packet(Ingress("hivemq", 1, time.monotonic()), "inbox", b"ciphertext")
        message = self.messages.call_args.args[2]
        self.assertEqual(("hivemq", 1, b"ciphertext"), (message.broker_id, message.broker_generation, message.payload))
        self.assertGreater(message.received_at_ns, 0)

    def test_wildcards_retain_and_oversized_packets_are_rejected(self):
        self.ready()
        with self.assertRaises(ValueError):
            self.client.subscribe({"galaxyssi/#": 1})
        with self.assertRaises(ValueError):
            self.client.publish("outbox", b"x", retain=True)
        self.assertNotEqual(0, self.client.publish("outbox", b"x" * 1048576).rc)

    def test_failed_maintenance_is_rate_limited_and_does_not_disconnect_paths(self):
        self.ready()
        self.client.on_tick = Mock(side_effect=[OSError("private detail"), OSError("private detail"), None])
        with self.assertLogs("mqtt_pool_client", level="WARNING") as logs:
            for _ in range(3):
                self.client._tick()
        self.assertEqual(1, len(logs.output))
        self.assertNotIn("private detail", logs.output[0])
        self.assertTrue(self.client.is_connected())
        self.disconnected.assert_not_called()


if __name__ == "__main__":
    unittest.main()
