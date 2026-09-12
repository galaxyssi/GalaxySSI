import threading
import time
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from mqtt_broker_catalog import BROKERS
from mqtt_broker_pool import BrokerPool, publish_packet_bytes


class FakeClient:
    def __init__(self, broker, generation, owner):
        self.broker, self.generation, self.owner = broker, generation, owner
        self.closed = threading.Event()
        self.subscriptions = []
        self.sent = []
        self.subscribe_id = 100
        self.publish_id = 1
        self.reject = broker in owner.reject
        self.early = owner.early
        self.auto_suback = owner.auto_suback

    def connect(self, host, port, keepalive):
        self.owner.connections.append((self.broker, host, port, keepalive))
        if self.broker in self.owner.blocked:
            self.closed.wait(2)
        if self.reject:
            self.on_connect(self, None, {}, 137, None)
            raise OSError("simulated refusal")
        self.on_connect(self, None, {}, 0, None)

    def loop_forever(self, **kwargs):
        self.closed.wait(5)

    def subscribe(self, topics):
        mid = self.subscribe_id
        self.subscribe_id += 1
        self.subscriptions.append((mid, topics))
        if self.auto_suback:
            self.on_subscribe(self, None, mid, [1] * len(topics), None)
        return 0, mid

    def unsubscribe(self, topics):
        return 0, 900

    def publish(self, topic, payload, qos, retain):
        mid = self.publish_id
        self.publish_id += 1
        self.sent.append((mid, topic, payload, qos, retain))
        if self.early:
            self.on_publish(self, None, mid, 0, None)
        return SimpleNamespace(rc=0, mid=mid)

    def ack(self, mid, reason=0):
        self.on_publish(self, None, mid, reason, None)

    def disconnect(self):
        self.closed.set()

    def lose(self):
        self.on_disconnect(self, None, {}, 128, None)
        self.closed.set()


class BrokerPoolTests(unittest.TestCase):
    def setUp(self):
        self.reject, self.blocked = set(), set()
        self.early, self.auto_suback = False, True
        self.clients, self.connections = {}, []
        self.states, self.subacks, self.packets, self.receipts = [], [], [], []
        self.pool = BrokerPool(on_state=lambda *args: self.states.append(args),
                               on_subscribed=lambda *args: self.subacks.append(args),
                               on_packet=lambda *args: self.packets.append(args),
                               on_publish=self.receipts.append, client_factory=self.factory)

    def tearDown(self):
        self.pool.close()

    def factory(self, broker, generation):
        client = FakeClient(broker, generation, self)
        self.clients[(broker, generation)] = client
        return client

    def wait_for(self, predicate, timeout=2):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.005)
        self.fail("timed out waiting for isolated broker worker")

    def start(self):
        self.pool.subscribe({"inbox": 1})
        self.pool.start()
        self.wait_for(lambda: len(self.connections) >= 3)

    def client(self, broker, generation=1):
        return self.clients[(broker, generation)]

    def test_three_workers_start_once_and_use_verified_tls_catalog_ports(self):
        self.start()
        self.pool.start()
        self.wait_for(lambda: len(self.subacks) == 3)
        self.assertEqual(3, len(self.connections))
        for broker, host, port, keepalive in self.connections:
            self.assertEqual((BROKERS[broker]["host"], BROKERS[broker]["tls_port"], 30), (host, port, keepalive))
        self.assertEqual("automatic", self.pool.snapshot()["selection"])

    def test_emqx_refusal_does_not_block_other_connections_or_subscriptions(self):
        self.reject.add("emqx")
        self.start()
        self.wait_for(lambda: len(self.subacks) >= 2)
        paths = self.pool.snapshot()["paths"]
        self.assertFalse(paths["emqx"]["connected"])
        self.assertTrue(paths["hivemq"]["connected"])
        self.assertTrue(paths["mosquitto"]["connected"])
        self.assertEqual("connack_137", paths["emqx"]["last_error"])

    def test_missing_suback_is_retried_without_global_disconnect(self):
        self.auto_suback = False
        self.start()
        self.wait_for(lambda: len(self.client("emqx").subscriptions) == 1)
        for path in self.pool._paths.values():
            with path.lock:
                for mid in path.subscription_started:
                    path.subscription_started[mid] -= 11
        self.pool.refresh_subscriptions()
        self.assertEqual(2, len(self.client("emqx").subscriptions))
        self.assertTrue(all(value["connected"] for value in self.pool.snapshot()["paths"].values()))

    def test_slow_dns_or_handshake_does_not_serialize_other_connections(self):
        self.blocked.add("emqx")
        self.start()
        self.wait_for(lambda: len(self.subacks) >= 2, timeout=0.5)
        self.assertFalse(self.pool.snapshot()["paths"]["emqx"]["connected"])

    def test_equal_packet_ids_from_different_brokers_map_to_different_logical_ids(self):
        self.start()
        self.wait_for(lambda: len(self.subacks) == 3)
        ids = [self.pool.publish(broker, 1, "outbox", b"ciphertext", attempt_id=broker) for broker in BROKERS]
        self.assertEqual(3, len(set(ids)))
        for broker in BROKERS:
            self.client(broker).ack(1)
        self.assertEqual(set(BROKERS), {receipt.physical.broker_id for receipt in self.receipts})
        self.assertEqual({1}, {receipt.physical.packet_id for receipt in self.receipts})

    def test_ack_before_publish_returns_is_not_lost_or_duplicated(self):
        self.early = True
        self.start()
        self.wait_for(lambda: len(self.subacks) == 3)
        logical_id = self.pool.publish("hivemq", 1, "outbox", b"ciphertext", attempt_id="attempt")
        self.assertEqual(1, len(self.receipts))
        self.assertEqual(logical_id, self.receipts[0].logical_id)
        self.assertTrue(self.receipts[0].broker_acked)
        self.client("hivemq").ack(1)
        self.assertEqual(1, len(self.receipts))

    def test_suback_before_subscribe_returns_is_processed(self):
        self.start()
        self.wait_for(lambda: len(self.subacks) == 3)
        self.assertTrue(all(path["active_subscriptions"] == 1 for path in self.pool.snapshot()["paths"].values()))

    def test_partial_suback_activates_only_accepted_topics(self):
        self.auto_suback = False
        self.pool.subscribe({"one": 1, "two": 1})
        self.pool.start()
        self.wait_for(lambda: len(self.connections) == 3)
        self.wait_for(lambda: len(self.client("emqx").subscriptions) == 1)
        self.client("emqx").on_subscribe(None, None, 100, [1, 128], None)
        self.assertEqual(frozenset({"one"}), self.subacks[-1][1])
        self.assertFalse(self.subacks[-1][2])
        self.assertEqual(1, self.pool.snapshot()["paths"]["emqx"]["active_subscriptions"])

    def test_removed_topic_is_not_reactivated_by_late_suback(self):
        self.auto_suback = False
        self.start()
        self.wait_for(lambda: len(self.client("emqx").subscriptions) == 1)
        self.pool.unsubscribe({"inbox"})
        self.client("emqx").on_subscribe(None, None, 100, [1], None)
        self.assertEqual(0, self.pool.snapshot()["paths"]["emqx"]["active_subscriptions"])

    def test_generation_change_replays_subscriptions_and_rejects_old_callbacks(self):
        self.start()
        self.wait_for(lambda: len(self.subacks) == 3)
        old = self.client("emqx")
        self.pool.publish("emqx", 1, "outbox", b"ciphertext", attempt_id="old")
        old.lose()
        self.wait_for(lambda: ("emqx", 2) in self.clients)
        self.wait_for(lambda: self.pool.snapshot()["paths"]["emqx"]["active_subscriptions"] == 1)
        self.pool.publish("emqx", 2, "outbox", b"ciphertext", attempt_id="new")
        count = len(self.receipts)
        old.ack(1)
        old.on_disconnect(None, None, {}, 128, None)
        self.assertEqual(count, len(self.receipts))
        self.assertTrue(self.pool.snapshot()["paths"]["emqx"]["connected"])
        self.client("emqx", 2).ack(1)
        self.assertEqual("new", self.receipts[-1].attempt_id)
        self.assertEqual(2, self.receipts[-1].physical.generation)

    def test_one_disconnect_only_fails_that_paths_pending_publishes(self):
        self.start()
        self.wait_for(lambda: len(self.subacks) == 3)
        for broker in BROKERS:
            self.pool.publish(broker, 1, "outbox", b"ciphertext", attempt_id=broker)
        self.client("emqx").lose()
        self.assertEqual(["emqx"], [item.attempt_id for item in self.receipts])
        self.assertFalse(self.receipts[0].broker_acked)
        self.assertEqual(1, self.pool.snapshot()["paths"]["hivemq"]["pending_publishes"])

    def test_ingress_is_tagged_and_requires_active_exact_subscription(self):
        self.start()
        self.wait_for(lambda: len(self.subacks) == 3)
        client = self.client("mosquitto")
        for topic, payload in [("unsubscribed", b"x"), ("inbox", b""), ("inbox", b"x" * 1_048_577),
                               ("inbox", b"encrypted")]:
            client.on_message(client, None, SimpleNamespace(topic=topic, payload=payload))
        self.assertEqual(1, len(self.packets))
        self.assertEqual("mosquitto", self.packets[0][0].broker_id)
        self.assertEqual(b"encrypted", self.packets[0][2])

    def test_forbids_broad_subscriptions_and_retained_business_packets(self):
        for topic in ("#", "namespace/+", "", "n\0x"):
            with self.assertRaises(ValueError):
                self.pool.subscribe({topic: 1})
        self.start()
        self.wait_for(lambda: len(self.subacks) == 3)
        self.pool.publish("emqx", 1, "outbox", b"encrypted", attempt_id="a")
        self.assertEqual((1, False), self.client("emqx").sent[-1][3:])

    def test_publish_after_disconnect_or_wrong_generation_is_rejected(self):
        self.start()
        self.wait_for(lambda: len(self.subacks) == 3)
        self.assertIsNone(self.pool.publish("emqx", 2, "outbox", b"encrypted", attempt_id="a"))
        self.client("emqx").lose()
        self.assertIsNone(self.pool.publish("emqx", 1, "outbox", b"encrypted", attempt_id="a"))

    def test_transport_pending_queue_is_bounded_even_if_caller_misbehaves(self):
        self.start()
        self.wait_for(lambda: len(self.subacks) == 3)
        results = [self.pool.publish("emqx", 1, "outbox", b"encrypted", attempt_id=str(i)) for i in range(100)]
        self.assertEqual(12, sum(item is not None for item in results))

    def test_shutdown_closes_all_workers_and_ignores_late_ingress(self):
        self.start()
        self.wait_for(lambda: len(self.subacks) == 3)
        self.pool.close()
        for client in self.clients.values():
            client.on_message(client, None, SimpleNamespace(topic="inbox", payload=b"encrypted"))
        self.assertEqual([], self.packets)
        self.assertTrue(all(not worker.is_alive() for worker in self.pool._workers))
        with self.assertRaises(RuntimeError):
            self.pool.start()

    def test_slow_shutdown_retains_worker_ownership_until_the_connect_call_exits(self):
        entered, release = threading.Event(), threading.Event()
        factory = self.pool._factory
        def delayed_factory(broker, generation):
            client = factory(broker, generation)
            if broker == "emqx":
                def connect(*_args, **_kwargs):
                    entered.set()
                    release.wait(3)
                client.connect = connect
            return client
        self.pool._factory = delayed_factory
        self.pool.start()
        try:
            self.assertTrue(entered.wait(1))
            self.assertFalse(self.pool.close(timeout=0.01))
            self.assertFalse(self.pool.wait_closed(timeout=0))
            with self.assertRaises(RuntimeError):
                self.pool.start()
        finally:
            release.set()
        self.assertTrue(self.pool.wait_closed(timeout=1))

    def test_real_client_factory_enforces_tls_hostname_checks(self):
        with patch("mqtt_broker_pool.mqtt.Client") as factory:
            BrokerPool._new_client("mosquitto", 1)
            factory.return_value.tls_set.assert_called_once_with()
            factory.return_value.tls_insecure_set.assert_called_once_with(False)
            self.assertFalse(factory.call_args.kwargs["reconnect_on_failure"])

    def test_packet_limit_includes_utf8_topic_and_mqtt_headers(self):
        self.assertEqual(10, publish_packet_bytes("abc", 1))
        self.assertGreater(publish_packet_bytes("abc", 1_048_576), 1_048_576)
        self.start()
        self.wait_for(lambda: len(self.subacks) == 3)
        self.assertIsNone(self.pool.publish("emqx", 1, "outbox", b"x" * 1_048_576, attempt_id="too-large"))


if __name__ == "__main__":
    unittest.main()
