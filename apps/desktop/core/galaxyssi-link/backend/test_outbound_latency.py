"""Isolated scheduling/durability regressions, not live latency acceptance."""

from contextlib import ExitStack
from pathlib import Path
from types import SimpleNamespace
import sqlite3
import tempfile
import threading
import unittest
from unittest.mock import Mock, patch

import link_delivery as delivery
import mqtt_bridge as bridge
from tests.test_mqtt_durable_delivery import DurableMqttClient, paired_client


class OutboundLatencyTests(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        root = self.stack.enter_context(tempfile.TemporaryDirectory())
        self.stack.enter_context(patch.object(delivery, "DB_PATH", Path(root) / "delivery.db"))
        self.wake = threading.Event()
        self.stack.enter_context(patch.object(bridge, "outbound_retry_wake_event", self.wake))
        self.stack.enter_context(patch.object(bridge, "pending_outbound_acks", {}))
        self.stack.enter_context(patch.object(bridge, "pending_delivery_acks", {}))
        self.stack.enter_context(patch.object(bridge, "pending_outbound_priorities", {}))
        self.stack.enter_context(patch.object(bridge, "outbound_publish_reservations", {}))
        self.stack.enter_context(patch.object(bridge, "early_outbound_acks", {}))

    def queue(self, message):
        delivery.queue_outbound("phone", message, "topic", "immutable-ciphertext")

    def test_batch_uses_one_full_sync_commit_and_deduplicates_keys(self):
        for message in ("a", "b"):
            self.queue(message)
        sql = []
        original = delivery._connect

        def connect():
            db = original()
            self.assertEqual(2, db.execute("PRAGMA synchronous").fetchone()[0])
            db.set_trace_callback(sql.append)
            return db

        with patch.object(delivery, "_connect", side_effect=connect) as opened:
            delivery.mark_outbound_batch_sending([("phone", "a"), ("phone", "b"), ("phone", "a")])
        self.assertEqual(1, opened.call_count)
        self.assertEqual(1, sql.count("COMMIT"))
        rows = delivery.pending_outbound(now=10**12)
        self.assertEqual([("a", 1, "sending"), ("b", 1, "sending")],
                         [(row["message_id"], row["attempts"], row["status"]) for row in rows])
        self.assertEqual({"immutable-ciphertext"}, {row["wire_payload"] for row in rows})

    def test_batch_failure_rolls_back_every_attempt(self):
        for message in ("a", "b"):
            self.queue(message)
        db = delivery._connect()
        try:
            db.execute("""CREATE TRIGGER reject_b BEFORE UPDATE ON outbound_messages
                          WHEN NEW.message_id='b' BEGIN SELECT RAISE(ABORT, 'injected'); END""")
            db.commit()
        finally:
            db.close()
        with self.assertRaises(sqlite3.IntegrityError):
            delivery.mark_outbound_batch_sending([("phone", "a"), ("phone", "b")])
        rows = delivery.pending_outbound()
        self.assertEqual([(0, "queued"), (0, "queued")], [(row["attempts"], row["status"]) for row in rows])

    def test_all_attempts_commit_before_wire_and_failed_commit_sends_nothing(self):
        peer = paired_client("phone")
        for message in ("a", "b"):
            self.queue(message)
        self.stack.enter_context(patch.object(bridge, "list_clients", return_value=[peer]))
        self.stack.enter_context(patch.object(bridge, "get_client", return_value=peer))
        sent = []

        def publish(*args, **kwargs):
            self.assertEqual({("phone", "a"): "sending", ("phone", "b"): "sending"},
                             delivery.outbound_statuses([("phone", "a"), ("phone", "b")]))
            self.assertEqual("immutable-ciphertext", args[2])
            sent.append(kwargs["timing_scope"])
            return SimpleNamespace(rc=0, mid=len(sent), is_published=lambda: False)

        with patch.object(bridge, "_publish_mqtt_wire_payload", side_effect=publish) as wire:
            with patch.object(bridge, "mark_outbound_batch_sending", side_effect=OSError("disk unavailable")):
                with self.assertRaises(OSError):
                    bridge.flush_outbound_messages(DurableMqttClient())
            wire.assert_not_called()
            self.assertEqual({}, bridge.outbound_publish_reservations)
            bridge.flush_outbound_messages(DurableMqttClient())
        self.assertEqual([("phone", "a"), ("phone", "b")], sent)

    def test_puback_wakes_sender_only_after_durable_state_update(self):
        self.queue("a")
        delivery.mark_outbound_sending("phone", "a")
        bridge.pending_outbound_acks[7] = ("phone", "a")
        bridge.pending_outbound_priorities[("phone", "a")] = 50
        bridge._record_publish_completion(object(), 7, False)
        self.assertTrue(self.wake.is_set())
        self.assertEqual("published", delivery.outbound_status("phone", "a"))
        self.assertEqual({}, bridge.pending_outbound_acks)
        self.assertEqual({}, bridge.pending_outbound_priorities)

    def test_early_puback_and_failed_puback_wake_after_tracking(self):
        for failed in (False, True):
            with self.subTest(failed=failed):
                self.wake.clear()
                client = object()
                bridge._record_publish_completion(client, 8, failed)
                self.assertFalse(self.wake.is_set())
                with patch.object(bridge, "mark_outbound_published") as published, \
                        patch.object(bridge, "mark_outbound_retryable") as retry:
                    bridge.track_outbound_publish(SimpleNamespace(mid=8), "phone", "a", mqttc=client)
                self.assertTrue(self.wake.is_set())
                self.assertEqual(not failed, published.called)
                self.assertEqual(failed, retry.called)

    def test_packet_wakeups_drain_without_repeated_recovery_or_starving_timer(self):
        stop = threading.Event()
        wake = Mock()
        clock = SimpleNamespace(now=0.0)
        order = []
        waits = []

        def wait(timeout):
            waits.append(timeout)
            clock.now += 0.4
            return True

        def recover(_):
            order.append("inbox")
            stop.set()

        wake.wait.side_effect = wait
        with patch.object(bridge, "client", DurableMqttClient()), \
                patch.object(bridge, "outbound_retry_wake_event", wake), \
                patch.object(bridge, "outbound_retry_stop_event", stop), \
                patch.object(bridge.time, "monotonic", side_effect=lambda: clock.now), \
                patch.object(bridge, "OUTBOUND_RETRY_POLL_SECONDS", 1.0), \
                patch.object(bridge, "flush_outbound_messages", side_effect=lambda _: order.append("wire")), \
                patch.object(bridge, "flush_pending_inbound_messages", side_effect=recover), \
                patch.object(bridge, "flush_pending_task_results", side_effect=lambda _: order.append("results")), \
                patch.object(bridge, "flush_pending_task_events"), \
                patch("agent_worker_mqtt.flush_worker_notifications"):
            bridge._outbound_retry_loop()
        self.assertEqual(["wire", "wire", "wire", "inbox", "results", "wire"], order)
        self.assertEqual([1.0, 0.6, 0.2], [round(value, 3) for value in waits])

    def test_ack_drains_queued_reply_without_waiting_for_poll(self):
        stop, entered, drained = threading.Event(), threading.Event(), threading.Event()
        self.queue("a")
        delivery.mark_outbound_sending("phone", "a")
        bridge.pending_outbound_acks[7] = ("phone", "a")

        def flush(_):
            drained.set()
            stop.set()

        class ObservedEvent(threading.Event):
            def wait(self, timeout=None):
                entered.set()
                return super().wait(timeout)

        wake = ObservedEvent()
        with patch.object(bridge, "client", DurableMqttClient()), \
                patch.object(bridge, "outbound_retry_stop_event", stop), \
                patch.object(bridge, "outbound_retry_wake_event", wake), \
                patch.object(bridge, "OUTBOUND_RETRY_POLL_SECONDS", 60.0), \
                patch.object(bridge, "flush_outbound_messages", side_effect=flush), \
                patch.object(bridge, "flush_pending_inbound_messages") as maintenance:
            worker = threading.Thread(target=bridge._outbound_retry_loop)
            worker.start()
            try:
                self.assertTrue(entered.wait(2))
                bridge._record_publish_completion(object(), 7, False)
                self.assertTrue(drained.wait(2), "PUBACK must wake the sender, not wait for its 60s timer")
                maintenance.assert_not_called()
            finally:
                stop.set()
                wake.set()
                worker.join(2)
        self.assertFalse(worker.is_alive())

    def test_slow_recovery_keeps_the_maintenance_interval(self):
        stop = threading.Event()
        clock = SimpleNamespace(now=0.0)
        wake = Mock()
        waits = []

        def wait(timeout):
            waits.append(timeout)
            clock.now += timeout
            if len(waits) == 2:
                stop.set()
            return False

        def slow_recovery(_):
            clock.now += 5.0

        wake.wait.side_effect = wait
        with patch.object(bridge, "client", DurableMqttClient()), \
                patch.object(bridge, "outbound_retry_stop_event", stop), \
                patch.object(bridge, "outbound_retry_wake_event", wake), \
                patch.object(bridge.time, "monotonic", side_effect=lambda: clock.now), \
                patch.object(bridge, "OUTBOUND_RETRY_POLL_SECONDS", 1.0), \
                patch.object(bridge, "flush_outbound_messages"), \
                patch.object(bridge, "flush_pending_inbound_messages", side_effect=slow_recovery), \
                patch.object(bridge, "flush_pending_task_results"), \
                patch.object(bridge, "flush_pending_task_events"), \
                patch("agent_worker_mqtt.flush_worker_notifications"):
            bridge._outbound_retry_loop()
        self.assertEqual([1.0, 1.0], waits)
