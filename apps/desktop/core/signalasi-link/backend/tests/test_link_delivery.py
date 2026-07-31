from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import link_delivery


class LinkDeliveryTest(unittest.TestCase):
    def test_broker_accepted_messages_wait_for_application_ack_before_retry(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            database = Path(temporary) / "delivery.db"
            with (
                patch.object(link_delivery, "DB_PATH", database),
                patch.object(link_delivery.time, "time", return_value=100.0),
            ):
                link_delivery.queue_outbound("client", "message", "topic", "wire")
                self.assertEqual(1, len(link_delivery.pending_outbound()))

                link_delivery.mark_outbound_sending("client", "message")
                link_delivery.mark_outbound_published("client", "message")

                self.assertEqual([], link_delivery.pending_outbound())
                self.assertEqual([], link_delivery.pending_outbound(now=104.999))
                self.assertEqual("message", link_delivery.pending_outbound(now=105.0)[0]["message_id"])
                self.assertEqual("published", link_delivery.outbound_status("client", "message"))
                self.assertTrue(link_delivery.acknowledge_outbound("client", "message"))
                self.assertIsNone(link_delivery.outbound_status("client", "message"))

    def test_retry_budget_never_discards_unacknowledged_message(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            database = Path(temporary) / "delivery.db"
            with (
                patch.object(link_delivery, "DB_PATH", database),
                patch.object(link_delivery.time, "time", return_value=100.0),
            ):
                link_delivery.queue_outbound("client", "persistent", "topic", "wire")
                for _ in range(12):
                    link_delivery.mark_outbound_sending("client", "persistent")
                    link_delivery.mark_outbound_retryable("client", "persistent")

                pending = link_delivery.pending_outbound(max_attempts=8, now=10_000.0)
                self.assertEqual("persistent", pending[0]["message_id"])
                self.assertEqual(12, pending[0]["attempts"])

    def test_inflight_count_and_batch_limit_apply_backpressure(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            database = Path(temporary) / "delivery.db"
            with (
                patch.object(link_delivery, "DB_PATH", database),
                patch.object(link_delivery.time, "time", return_value=100.0),
            ):
                for index in range(6):
                    link_delivery.queue_outbound("client", f"message-{index}", "topic", "wire")
                link_delivery.mark_outbound_sending("client", "message-0")
                link_delivery.mark_outbound_sending("client", "message-1")

                self.assertEqual(2, link_delivery.outbound_inflight_count(now=101.0))
                due = link_delivery.pending_outbound(limit=2, now=101.0)
                self.assertEqual(["message-2", "message-3"], [item["message_id"] for item in due])

    def test_transport_epoch_clears_obsolete_outbox_only_once(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            database = Path(temporary) / "delivery.db"
            with patch.object(link_delivery, "DB_PATH", database):
                link_delivery.queue_outbound("client", "old", "topic", "wire")
                link_delivery.queue_task_result(
                    "old-task",
                    "client",
                    {"_client_route_id": "client"},
                    {"task_id": "old-task", "content": "old"},
                )
                self.assertTrue(link_delivery.ensure_transport_epoch("v2"))
                self.assertEqual([], link_delivery.pending_outbound())
                self.assertEqual([], link_delivery.pending_task_results())

                link_delivery.queue_outbound("client", "current", "topic", "wire")
                self.assertFalse(link_delivery.ensure_transport_epoch("v2"))
                self.assertEqual("current", link_delivery.pending_outbound()[0]["message_id"])

    def test_task_result_outbox_survives_restart_until_transport_preparation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            database = Path(temporary) / "delivery.db"
            with patch.object(link_delivery, "DB_PATH", database):
                link_delivery.queue_task_result(
                    "task-1",
                    "client-1",
                    {"scheme": "signal", "_client_route_id": "client-1"},
                    {
                        "task_id": "task-1",
                        "message_id": "5a22fe7b-8ef9-54c2-9c90-3120f17d277e",
                        "content": "completed",
                    },
                )
                link_delivery.queue_task_result(
                    "task-1",
                    "client-1",
                    {"scheme": "signal", "_client_route_id": "client-1"},
                    {
                        "task_id": "task-1",
                        "message_id": "5a22fe7b-8ef9-54c2-9c90-3120f17d277e",
                        "content": "completed",
                    },
                )

                pending = link_delivery.pending_task_results()
                self.assertEqual(1, len(pending))
                self.assertEqual("task-1", pending[0]["task_id"])
                self.assertEqual("completed", pending[0]["payload"]["content"])

                link_delivery.remove_task_result("task-1")
                self.assertEqual([], link_delivery.pending_task_results())

    def test_route_topic_and_payload_are_not_plaintext_at_rest(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            database = Path(temporary) / "delivery.db"
            with patch.object(link_delivery, "DB_PATH", database):
                link_delivery.queue_outbound(
                    "client-route-secret",
                    "message-secret",
                    "signalasichat/v1/server-secret/client-route-secret/down",
                    '{"content":"payload-secret"}',
                )
                link_delivery.queue_task_result(
                    "task-secret",
                    "client-route-secret",
                    {"body": "wire-secret"},
                    {"content": "result-secret"},
                )

                self.assertEqual(
                    "client-route-secret",
                    link_delivery.pending_outbound()[0]["client_route_id"],
                )
                self.assertEqual(
                    "result-secret",
                    link_delivery.pending_task_results()[0]["payload"]["content"],
                )
                persisted = database.read_bytes()
                for secret in (
                    b"client-route-secret",
                    b"server-secret",
                    b"payload-secret",
                    b"wire-secret",
                    b"result-secret",
                ):
                    self.assertNotIn(secret, persisted)


if __name__ == "__main__":
    unittest.main()
