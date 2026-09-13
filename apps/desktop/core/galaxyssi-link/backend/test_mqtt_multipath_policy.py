import itertools
import unittest
from concurrent.futures import ThreadPoolExecutor

from mqtt_multipath_policy import (
    Attempt, BROKER_IDS, Limits, MultipathPolicy, PeerRoute, PhysicalKey, Traffic,
)


HASH = "a" * 64


class MultipathPolicyTests(unittest.TestCase):
    def setUp(self):
        self.policy = MultipathPolicy(tie_seed=b"deterministic-test")
        for broker in BROKER_IDS:
            self.policy.connected(broker, 1)
            self.policy.subscribed(broker, 1, {"inbox"})
        self.resume()

    def resume(self, *, peer="peer", epoch=1, brokers=BROKER_IDS, expiry=300.0, limit=1_048_576):
        return self.policy.accept_verified_resume(
            peer, PeerRoute(epoch, frozenset(brokers), limit, True, expiry), now=0.0,
        )

    def plan(self, traffic=Traffic.MESSAGE, *, peer="peer", message="m", size=100, now=1.0, **kwargs):
        return self.policy.plan(peer, message, traffic, size, {"inbox"}, now=now, **kwargs)

    def reserve(self, key, *, peer="peer", message="m", path="emqx", size=100,
                traffic=Traffic.MESSAGE, content_hash=HASH, started=0.0):
        return self.policy.reserve(key, Attempt(peer, message, content_hash, path, 1, size, traffic, started))

    def test_all_three_connection_orders_use_first_subscribed_common_path(self):
        for order in itertools.permutations(BROKER_IDS):
            with self.subTest(order=order):
                policy = MultipathPolicy()
                policy.accept_verified_resume("peer", PeerRoute(1, BROKER_IDS, 1_048_576, True, 300), now=0)
                for index, broker in enumerate(order):
                    policy.connected(broker, 1)
                    before = policy.plan("peer", "m", Traffic.CONTROL, 100, {"inbox"}, now=1)
                    self.assertEqual(index, len(before))
                    policy.subscribed(broker, 1, {"inbox"})
                    result = policy.plan("peer", "m", Traffic.CONTROL, 100, {"inbox"}, now=1)
                    self.assertEqual(set(order[:index + 1]), {item.broker_id for item in result})

    def test_no_business_send_before_verified_peer_resume(self):
        self.assertEqual((), self.plan(peer="unverified"))

    def test_control_races_all_brokers_without_default(self):
        plan = self.plan(Traffic.CONTROL)
        self.assertEqual(BROKER_IDS, frozenset(item.broker_id for item in plan))
        self.assertTrue(all(item.delay == 0 for item in plan))
        winners = {self.plan(message=str(index))[0].broker_id for index in range(100)}
        self.assertEqual(BROKER_IDS, winners)

    def test_normal_messages_hedge_without_waiting_for_all_paths(self):
        plan = self.plan()
        self.assertEqual([0, 2.0, 4.0], [item.delay for item in plan])

    def test_large_packets_progress_and_chunks_do_not_triple_copy(self):
        for traffic, size in [(Traffic.MESSAGE, 65_537), (Traffic.FINAL, 65_537),
                              (Traffic.CONTROL, 65_537), (Traffic.CHUNK, 100), (Traffic.PROGRESS, 100)]:
            with self.subTest(traffic=traffic, size=size):
                self.assertEqual(1, len(self.plan(traffic, size=size)))

    def test_receipt_prefers_ingress_without_ack_storm(self):
        for broker in BROKER_IDS:
            plan = self.plan(Traffic.RECEIPT, ingress=broker)
            self.assertEqual([broker], [item.broker_id for item in plan])

    def test_down_path_does_not_clear_other_subscriptions(self):
        self.policy.disconnected("emqx", 1)
        self.assertEqual({"hivemq", "mosquitto"}, {item.broker_id for item in self.plan()})

    def test_packet_id_and_connection_generations_are_isolated(self):
        self.assertNotEqual(PhysicalKey("emqx", 1, 7), PhysicalKey("hivemq", 1, 7))
        self.assertNotEqual(PhysicalKey("emqx", 1, 7), PhysicalKey("emqx", 2, 7))
        self.policy.connected("emqx", 2)
        self.assertFalse(self.policy.subscribed("emqx", 1, {"inbox"}))
        self.assertFalse(self.policy.disconnected("emqx", 1))
        self.assertTrue(self.policy.paths["emqx"].connected)
        self.assertNotIn("emqx", {item.broker_id for item in self.plan()})

    def test_reconnect_requires_new_suback(self):
        self.policy.disconnected("emqx", 1)
        self.assertFalse(self.policy.connected("emqx", 1))
        self.assertTrue(self.policy.connected("emqx", 2))
        self.assertNotIn("emqx", {item.broker_id for item in self.plan()})
        self.policy.subscribed("emqx", 2, {"inbox"})
        self.assertIn("emqx", {item.broker_id for item in self.plan()})

    def test_all_offline_queues_and_any_one_recovery_can_work(self):
        for broker in BROKER_IDS:
            self.policy.disconnected(broker, 1)
        self.assertEqual((), self.plan())
        self.policy.connected("mosquitto", 2)
        self.policy.subscribed("mosquitto", 2, {"inbox"})
        self.assertEqual(["mosquitto"], [item.broker_id for item in self.plan()])

    def test_different_receive_collections_only_use_intersection(self):
        self.resume(epoch=2, brokers={"hivemq"})
        self.assertEqual(["hivemq"], [item.broker_id for item in self.plan()])
        self.policy.disconnected("hivemq", 1)
        self.assertEqual((), self.plan())

    def test_resume_replay_cannot_revert_routes_or_extend_expiry(self):
        self.assertTrue(self.resume(epoch=2, brokers={"hivemq"}, expiry=200))
        self.assertFalse(self.resume(epoch=1))
        self.assertFalse(self.resume(epoch=2, brokers={"hivemq"}, expiry=250))
        self.assertTrue(self.resume(epoch=2, brokers={"hivemq"}, expiry=200))
        self.assertEqual((), self.plan(now=201))

    def test_invalid_capabilities_are_rejected(self):
        for route in [PeerRoute(0, BROKER_IDS, 1, True, 200),
                      PeerRoute(2, frozenset({"attacker"}), 100, True, 200),
                      PeerRoute(2, BROKER_IDS, 0, True, 200),
                      PeerRoute(2, BROKER_IDS, 1_048_577, True, 200),
                      PeerRoute(2, BROKER_IDS, 100, True, float("inf")),
                      PeerRoute(2, BROKER_IDS, 100, True, 301)]:
            with self.subTest(route=route):
                self.assertFalse(self.policy.accept_verified_resume("peer", route, now=0))

    def test_encoded_packet_limit_is_intersection_of_path_and_peer(self):
        self.resume(epoch=2, limit=1024)
        self.assertEqual((), self.plan(size=1025))
        self.assertTrue(self.plan(size=1024))
        self.policy.connected("emqx", 2, packet_bytes=512)
        self.policy.subscribed("emqx", 2, {"inbox"})
        self.assertNotIn("emqx", {item.broker_id for item in self.plan(size=1024)})

    def test_broker_ack_is_not_peer_acceptance(self):
        self.assertTrue(self.reserve("attempt"))
        self.assertFalse(self.policy.broker_ack("attempt", "hivemq", 1))
        self.assertTrue(self.policy.broker_ack("attempt", "emqx", 1))
        self.assertTrue(self.policy.pending("peer", "m"))
        self.assertEqual(0, self.policy.diagnostics()["inflight_packets"])
        self.assertEqual(3, len(self.plan()))

    def test_receipt_must_bind_peer_message_hash_and_attempt(self):
        self.reserve("attempt")
        for peer, message, content_hash, attempt in [("other", "m", HASH, "attempt"),
                                                    ("peer", "other", HASH, "attempt"),
                                                    ("peer", "m", "b" * 64, "attempt"),
                                                    ("peer", "m", HASH, "unknown")]:
            self.assertEqual((), self.policy.accept_verified_receipt(
                peer, message, content_hash, attempt, now=1))
        self.assertTrue(self.policy.pending("peer", "m"))

    def test_verified_receipt_retires_all_copies_of_one_message_only(self):
        for broker in BROKER_IDS:
            self.reserve(broker, path=broker)
        self.reserve("another", message="m2")
        completed = self.policy.accept_verified_receipt("peer", "m", HASH, "hivemq", now=0.2)
        self.assertEqual(BROKER_IDS, set(completed))
        self.assertFalse(self.policy.pending("peer", "m"))
        self.assertTrue(self.policy.pending("peer", "m2"))

    def test_duplicate_message_id_with_changed_content_is_rejected(self):
        self.assertTrue(self.reserve("one"))
        self.assertFalse(self.reserve("two", content_hash="b" * 64))

    def test_path_ranking_uses_peer_receipt_latency_and_expires(self):
        self.reserve("fast", path="mosquitto")
        self.policy.accept_verified_receipt("peer", "m", HASH, "fast", now=0.02)
        plan = self.plan()
        self.assertEqual("mosquitto", plan[0].broker_id)
        self.assertEqual(2.0, plan[1].delay)
        self.assertTrue(self.resume(epoch=2, expiry=300))
        self.assertFalse(self.policy._samples("peer", "mosquitto", 301))

    def test_percentile_hedge_requires_twenty_distinct_verified_receipts(self):
        for index in range(20):
            key = f"sample-{index}"
            self.assertTrue(self.reserve(key, path="mosquitto", message=key))
            self.policy.broker_ack(key, "mosquitto", 1)
            self.policy.accept_verified_receipt("peer", key, HASH, key, now=0.02)
            self.assertEqual(2.0 if index < 19 else 0.1, self.plan()[1].delay)

    def test_network_change_discards_previous_network_speed_assumptions(self):
        self.policy.set_network("wifi")
        self.reserve("fast", path="hivemq")
        self.policy.accept_verified_receipt("peer", "m", HASH, "fast", now=0.02)
        self.assertTrue(self.policy._samples("peer", "hivemq", 1))
        self.policy.set_network("cellular")
        self.assertFalse(self.policy._samples("peer", "hivemq", 1))

    def test_cold_path_hedge_uses_twenty_peer_samples_across_healthy_paths(self):
        for index in range(20):
            key = f"spread-{index}"
            path = sorted(BROKER_IDS)[index % 3]
            self.assertTrue(self.reserve(key, path=path, message=key))
            self.policy.broker_ack(key, path, 1)
            self.policy.accept_verified_receipt("peer", key, HASH, key, now=0.8)
            self.assertAlmostEqual(2.0 if index < 19 else 1.2, self.plan()[1].delay)
        self.assertTrue(all(item.delay == 0 for item in self.plan(Traffic.CONTROL)))
        self.policy.disconnected("emqx", 1)
        self.assertEqual(2.0, self.plan()[1].delay)

    def test_peer_aggregate_does_not_use_another_peer_or_network(self):
        self.resume(peer="other")
        for index in range(20):
            key = f"other-{index}"
            path = sorted(BROKER_IDS)[index % 3]
            self.assertTrue(self.reserve(key, peer="other", path=path, message=key))
            self.policy.broker_ack(key, path, 1)
            self.policy.accept_verified_receipt("other", key, HASH, key, now=0.8)
        self.assertEqual(2.0, self.plan()[1].delay)
        self.assertAlmostEqual(1.2, self.plan(peer="other")[1].delay)
        self.policy.set_network("new-network")
        self.assertEqual(2.0, self.plan(peer="other")[1].delay)

    def test_cold_hedge_budget_does_not_redefine_unknown_path_ranking(self):
        self.reserve("slow", path="hivemq")
        self.policy.accept_verified_receipt("peer", "m", HASH, "slow", now=0.8)
        self.assertNotEqual("hivemq", self.plan()[0].broker_id)
        self.assertEqual(2.0, self.plan()[1].delay)
        for value in (0, -1, float("inf"), float("nan")):
            with self.assertRaises(ValueError):
                Limits(unmeasured_path_rtt=value)

    def test_mature_primary_samples_take_precedence_over_slower_peer_aggregate(self):
        for path, elapsed in (("mosquitto", 0.2), ("hivemq", 0.8)):
            for index in range(20):
                key = f"mature-{path}-{index}"
                self.assertTrue(self.reserve(key, path=path, message=key))
                self.policy.broker_ack(key, path, 1)
                self.policy.accept_verified_receipt("peer", key, HASH, key, now=elapsed)
        plan = self.plan()
        self.assertEqual("mosquitto", plan[0].broker_id)
        self.assertAlmostEqual(0.3, plan[1].delay)

    def test_chunk_retry_prefers_an_unused_healthy_path(self):
        first = self.plan(Traffic.CHUNK)[0].broker_id
        second = self.plan(Traffic.CHUNK, attempted=frozenset({first}))[0].broker_id
        self.assertNotEqual(first, second)

    def test_global_capacity_reserves_control_slots_across_brokers(self):
        for index in range(10):
            self.assertTrue(self.reserve(str(index), peer=str(index), message=str(index), traffic=Traffic.CHUNK))
        self.assertFalse(self.reserve("ordinary", peer="ordinary"))
        self.assertTrue(self.reserve("control", traffic=Traffic.CONTROL))
        self.assertTrue(self.reserve("final", traffic=Traffic.FINAL))
        self.assertFalse(self.reserve("excess", traffic=Traffic.CONTROL))
        self.assertEqual(12, self.policy.diagnostics()["inflight_packets"])

    def test_concurrent_reservations_never_exceed_global_limit(self):
        with ThreadPoolExecutor(max_workers=20) as executor:
            results = list(executor.map(lambda index: self.reserve(
                str(index), peer=str(index), traffic=Traffic.CHUNK), range(200)))
        self.assertEqual(10, sum(results))

    def test_peer_quota_and_attempt_expiry_are_bounded(self):
        self.assertTrue(self.reserve("one", size=1_048_576, traffic=Traffic.CHUNK))
        self.assertTrue(self.reserve("two", size=917_504, traffic=Traffic.CHUNK))
        self.assertFalse(self.reserve("three", traffic=Traffic.CHUNK))
        self.assertTrue(self.reserve("control", traffic=Traffic.CONTROL, started=2))
        self.assertEqual({"one", "two"}, set(self.policy.expire_attempts(1)))
        self.assertEqual(100, self.policy.diagnostics()["inflight_bytes"])

    def test_peer_acceptance_does_not_release_already_sent_copies(self):
        for broker in BROKER_IDS:
            self.reserve(broker, path=broker)
        self.policy.accept_verified_receipt("peer", "m", HASH, "hivemq", now=0.2)
        self.assertFalse(self.policy.pending("peer", "m"))
        self.assertEqual(3, self.policy.diagnostics()["inflight_packets"])
        self.policy.broker_ack("hivemq", "hivemq", 1)
        self.assertEqual(2, self.policy.diagnostics()["inflight_packets"])
        self.policy.disconnected("emqx", 1)
        self.assertEqual(1, self.policy.diagnostics()["inflight_packets"])
        self.policy.broker_ack("mosquitto", "mosquitto", 1)
        self.assertEqual(0, self.policy.diagnostics()["pending_attempts"])

    def test_inflight_load_distributes_chunks_instead_of_static_round_robin(self):
        selected = set()
        for index in range(3):
            plan = self.plan(Traffic.CHUNK, message="same", size=1_048_576)
            path = plan[0].broker_id
            selected.add(path)
            self.reserve(str(index), path=path, peer=str(index), message=str(index), size=1_048_576,
                         traffic=Traffic.CHUNK)
        self.assertEqual(BROKER_IDS, selected)

    def test_unsubscribe_removes_receive_readiness_on_every_path(self):
        self.policy.unsubscribe({"inbox"})
        self.assertEqual((), self.plan())

    def test_forget_peer_removes_path_state_and_observations(self):
        self.reserve("attempt")
        self.policy.forget_peer("peer")
        self.assertEqual((), self.plan())
        self.assertFalse(self.policy.pending("peer", "m"))

    def test_limits_reject_impossible_reservations(self):
        for params in [{"control_reserve": 12}, {"packet_bytes": 1},
                       {"hedge_min": 3}, {"peer_inflight_bytes": 10}, {"route_ttl": 0}]:
            with self.subTest(params=params), self.assertRaises(ValueError):
                Limits(**params)

    def test_unanswered_messages_cannot_consume_control_tracking_reservation(self):
        self.policy = MultipathPolicy(Limits(max_attempts=12))
        self.policy.connected("emqx", 1)
        for index in range(10):
            self.assertTrue(self.reserve(str(index), message=str(index)))
            self.policy.broker_ack(str(index), "emqx", 1)
        self.assertFalse(self.reserve("ordinary"))
        self.assertTrue(self.reserve("stop", traffic=Traffic.CONTROL))
        self.assertTrue(self.reserve("receipt", traffic=Traffic.RECEIPT))


if __name__ == "__main__":
    unittest.main()
