import unittest

from mqtt_pool_client import PublishInfo
from mqtt_receipt_publication import ReceiptPublication


class ReceiptPublicationTest(unittest.TestCase):
    def setUp(self):
        self.now = 0
        self.sent = []
        self.available = ["emqx", "hivemq", "mosquitto"]
        self.publication = ReceiptPublication(self.publish, lambda: self.now)

    def publish(self, attempted):
        paths = [path for path in self.available if path not in attempted]
        if not paths:
            return None
        info = PublishInfo(len(self.sent) + 1, broker_id=paths[0])
        self.sent.append(info)
        return info

    def test_admission_is_not_success_and_fallback_waits_for_grace(self):
        self.assertFalse(self.publication.send())
        self.now = 0.999
        self.assertFalse(self.publication.send())
        self.assertEqual(1, len(self.sent))
        self.now = 1
        self.assertFalse(self.publication.send())
        self.assertEqual(["emqx", "hivemq"], [info.broker_id for info in self.sent])
        self.sent[1]._done.set()
        self.now = 2
        self.assertTrue(self.publication.send())
        self.assertEqual(2, len(self.sent))

    def test_late_first_path_success_stops_additional_copies(self):
        self.publication.send()
        self.now = 1
        self.publication.send()
        self.sent[0]._done.set()
        self.now = 2
        self.assertTrue(self.publication.send())
        self.assertEqual(2, len(self.sent))

    def test_async_failure_tries_other_path_without_waiting(self):
        self.publication.send()
        self.sent[0].rc = 7
        self.sent[0]._done.set()
        self.assertFalse(self.publication.send())
        self.assertEqual(["emqx", "hivemq"], [info.broker_id for info in self.sent])

    def test_pending_paths_remain_bounded_even_with_repeated_maintenance(self):
        for instant in range(30):
            self.now = instant
            self.assertFalse(self.publication.send())
        self.assertEqual(3, len(self.sent))

    def test_all_failed_paths_can_be_retried_on_a_later_tick(self):
        for _ in range(3):
            self.assertFalse(self.publication.send())
            self.sent[-1].rc = 7
            self.sent[-1]._done.set()
        self.assertFalse(self.publication.send())
        self.assertEqual(3, len(self.sent))
        self.assertFalse(self.publication.send())
        self.assertEqual(4, len(self.sent))

    def test_no_authorized_path_does_not_complete_receipt(self):
        self.available.clear()
        self.assertFalse(self.publication.send())
        self.assertFalse(self.sent)
        self.available.append("hivemq")
        self.assertFalse(self.publication.send())
        self.sent[0]._done.set()
        self.assertTrue(self.publication.send())
