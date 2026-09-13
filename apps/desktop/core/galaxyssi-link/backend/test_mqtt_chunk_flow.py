import unittest

from mqtt_broker_catalog import BROKER_IDS, CATALOG
from mqtt_chunk_feedback import ChunkFeedback
from mqtt_chunk_throughput import ChunkAttempt, ChunkThroughput
from mqtt_multipath_policy import MultipathPolicy, PeerRoute, Traffic


class ChunkFlowTest(unittest.TestCase):
    def test_sparse_samples_keep_bootstrap_rate_and_batch_counts_bytes_once(self):
        flow = ChunkThroughput()
        for number in range(3):
            chunk = ChunkAttempt(f"transfer-{number}", "request", 0, True)
            start = number * 3.0
            flow.track("peer", chunk, "hivemq", 1, 524288, start)
            flow.track("peer", ChunkAttempt(chunk.transfer, "request", 1, True), "hivemq", 1, 524288, start)
            flow.confirmed("peer", chunk.transfer, "request", [0, 1], {"hivemq": 1}, start + 0.5)
            self.assertEqual(262144 if number < 2 else 2097152, flow.rate("peer", "hivemq"))
            flow.confirmed("peer", chunk.transfer, "request", [0, 1], {"hivemq": 1}, start + 0.6)
            self.assertEqual(number + 1, flow.rates["peer", "hivemq"][2])
        self.assertEqual(0, flow.pending_bytes("hivemq"))

    def test_retry_or_multiple_possible_attempts_never_become_speed_samples(self):
        for retried in (True, False):
            flow = ChunkThroughput()
            chunk = ChunkAttempt("transfer", "request", 0, not retried)
            flow.track("peer", chunk, "emqx", 1, 524288, 1)
            if not retried:
                flow.track("peer", chunk, "hivemq", 1, 524288, 1.1)
            flow.confirmed("peer", "transfer", "request", [0], {"emqx": 1, "hivemq": 1}, 2)
            self.assertFalse(flow.rates)
            self.assertFalse(flow.flights)

    def test_wrong_pair_request_and_reconnected_generation_cannot_credit_path(self):
        flow = ChunkThroughput()
        chunk = ChunkAttempt("transfer", "request", 0, True)
        flow.track("peer", chunk, "emqx", 1, 100, 1)
        flow.confirmed("other", "transfer", "request", [0], {"emqx": 1}, 2)
        flow.confirmed("peer", "transfer", "old", [0], {"emqx": 1}, 2)
        self.assertEqual(100, flow.pending_bytes("emqx"))
        flow.confirmed("peer", "transfer", "request", [0], {"emqx": 2}, 2)
        self.assertFalse(flow.rates)

    def test_new_round_and_expiry_remove_observations_not_persisted_delivery(self):
        flow = ChunkThroughput()
        flow.track("peer", ChunkAttempt("transfer", "old", 0, True), "emqx", 1, 100, 1)
        flow.track("peer", ChunkAttempt("transfer", "new", 1, False), "hivemq", 1, 200, 2)
        self.assertEqual(0, flow.pending_bytes("emqx"))
        self.assertEqual(200, flow.pending_bytes("hivemq"))
        flow.expire(33)
        self.assertFalse(flow.flights)

    def policy(self):
        policy = MultipathPolicy(tie_seed=b"test")
        for broker in BROKER_IDS:
            policy.connected(broker, 1)
            policy.subscribed(broker, 1, {"inbox"})
        policy.accept_verified_resume("peer", PeerRoute(1, BROKER_IDS, 1048576, True, 300), now=0)
        return policy

    def test_fast_verified_delivery_path_wins_and_network_change_forgets_rates(self):
        policy = self.policy()
        for number in range(3):
            paths = (("hivemq", 0.25), ("mosquitto", 1), ("emqx", 2))
            start = number * 4
            for broker, _ in paths:
                chunk = ChunkAttempt(f"{broker}-{number}", "request", 0, True)
                policy.track_chunk("peer", chunk, broker, 1, 524288, start)
            for broker, elapsed in paths:
                chunk = ChunkAttempt(f"{broker}-{number}", "request", 0, True)
                policy.confirm_chunk_state("peer", chunk.transfer, "request", [0], start + elapsed)
        plan = policy.plan("peer", "next", Traffic.CHUNK, 524288, {"inbox"}, now=12)
        self.assertEqual("hivemq", plan[0].broker_id)
        policy.set_network("new-wifi")
        self.assertFalse(policy.chunks.rates)

    def test_broker_only_ack_does_not_make_path_look_empty(self):
        policy = self.policy()
        first = policy.plan("peer", "first", Traffic.CHUNK, 524288, {"inbox"}, now=1)[0].broker_id
        policy.track_chunk("peer", ChunkAttempt("transfer", "request", 0, True), first, 1, 524288, 1)
        following = policy.plan("peer", "second", Traffic.CHUNK, 524288, {"inbox"}, now=1)[0].broker_id
        self.assertNotEqual(first, following)
        self.assertEqual(0, policy.diagnostics()["inflight_packets"])
        self.assertEqual(524288, policy.chunks.pending_bytes(first))

    def test_metric_retention_and_pair_revocation(self):
        flow = ChunkThroughput()
        for peer in ("a", "b"):
            flow.track(peer, ChunkAttempt("transfer", "request", 0, True), "emqx", 1, 100, 0)
        for peer in ("a", "b"):
            flow.confirmed(peer, "transfer", "request", [0], {"emqx": 1}, 1)
        self.assertEqual({("a", "emqx"), ("b", "emqx")}, set(flow.rates))
        flow.forget("a")
        self.assertEqual({("b", "emqx")}, set(flow.rates))
        flow.expire(302)
        self.assertFalse(flow.rates)

    def test_observation_memory_remains_bounded_without_peer_ack(self):
        flow = ChunkThroughput()
        bound = CATALOG["limits"]["max_tracked_attempts"]
        for index in range(bound + 3):
            flow.track("peer", ChunkAttempt(str(index), "request", 0, True), "emqx", 1, 100, 0)
        self.assertEqual(bound * 100, flow.pending_bytes("emqx"))
        flow.forget("peer")
        self.assertEqual(0, flow.pending_bytes("emqx"))

    def test_burst_feedback_uses_latest_revision_without_extending_first_deadline(self):
        feedback, sent = ChunkFeedback(), []
        feedback.offer("peer", "transfer", "request", 1, lambda: sent.append(1), 0)
        feedback.offer("peer", "transfer", "request", 3, lambda: sent.append(3), 0.15)
        feedback.offer("peer", "transfer", "request", 2, lambda: sent.append(2), 0.16)
        self.assertFalse(feedback.drain(0.19))
        for send in feedback.drain(0.201):
            send()
        self.assertEqual([3], sent)

    def test_terminal_or_probe_is_immediate_and_cancels_queued_state(self):
        feedback, sent = ChunkFeedback(), []
        feedback.offer("peer", "transfer", "request", 1, lambda: sent.append(1), 0)
        immediate = feedback.offer("peer", "transfer", "request", 2, lambda: sent.append(2), 0.1, urgent=True)
        immediate()
        self.assertEqual([2], sent)
        self.assertFalse(feedback.drain(1))

    def test_feedback_per_peer_bound_leaves_capacity_for_other_pairs(self):
        feedback, sent = ChunkFeedback(), []
        for index in range(CATALOG["limits"]["per_peer_chunk_feedback"] + 1):
            feedback.offer("peer", str(index), "request", 1, lambda: sent.append("peer"), 0)
        feedback.offer("other", "transfer", "request", 1, lambda: sent.append("other"), 0)
        feedback.forget("peer")
        for send in feedback.drain(1):
            send()
        self.assertEqual(["other"], sent)

    def test_feedback_drain_is_bounded(self):
        feedback = ChunkFeedback()
        for index in range(30):
            feedback.offer("peer", str(index), "request", 1, lambda: None, 0)
        self.assertEqual(16, len(feedback.drain(1)))
        self.assertEqual(14, len(feedback.drain(1)))


if __name__ == "__main__":
    unittest.main()
