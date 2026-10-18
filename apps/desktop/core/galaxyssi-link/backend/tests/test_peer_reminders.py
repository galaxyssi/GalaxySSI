import concurrent.futures
import sqlite3
import tempfile
import unittest
from contextlib import closing
from pathlib import Path

from peer_reminders import PeerReminders, reply_payload


class PeerReminderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.now = 1_000_000
        self.path = Path(self.temp.name) / "reminders.db"
        self.store = PeerReminders(self.path, lambda: self.now)
        self.packet = {"type": "peer_attention", "reminder_id": "abcdef01-2345-6789-abcd-012345678901",
                       "reminder_action": "request", "created_at": self.now, "expires_at": self.now + 120_000}
        self.events = []
        self.store.subscribe(self.events.append)

    def receive(self, **changes):
        return self.store.receive("trusted-route", "Test contact", dict(self.packet, **changes))

    def test_duplicate_does_not_notify_twice(self):
        self.receive()
        self.receive()
        self.assertEqual(1, len(self.events))

    def test_simultaneous_duplicates_notify_once(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            list(pool.map(lambda _: self.receive(), range(32)))
        self.assertEqual(1, len(self.events))

    def test_cancel_before_request_never_rings(self):
        self.receive(reminder_action="cancelled")
        self.assertEqual("cancelled", self.receive()["status"])
        self.assertFalse(self.store.active())
        self.assertEqual(["cancelled"], [event["status"] for event in self.events])

    def test_restart_retains_acknowledgement(self):
        self.receive()
        self.store.act(self.packet["reminder_id"], "acknowledged")
        restarted = PeerReminders(self.path, lambda: self.now)
        self.assertEqual("acknowledged", restarted.receive("trusted-route", "Test", self.packet)["status"])
        self.assertFalse(restarted.active())

    def test_receipt_binding(self):
        value = self.receive()
        reply = reply_payload(value)
        for key in ("reminder_id", "created_at", "expires_at"):
            self.assertEqual(self.packet[key], reply[key])
        self.assertEqual("received", reply["reminder_action"])
        self.assertNotIn("sender_name", reply)

    def test_wrong_peer_cannot_cancel(self):
        self.receive()
        self.assertIsNone(self.store.receive("other-route", "Other", dict(self.packet, reminder_action="cancelled")))
        self.assertEqual("received", self.store.active()[0]["status"])

    def test_bound_lifetime_cannot_be_replaced(self):
        self.receive()
        self.assertIsNone(self.receive(created_at=self.now + 1))
        self.assertIsNone(self.receive(expires_at=self.now + 119_999))

    def test_remote_peer_cannot_acknowledge(self):
        self.receive()
        self.assertIsNone(self.receive(reminder_action="acknowledged"))
        self.assertEqual("received", self.store.active()[0]["status"])

    def test_terminal_state_is_monotonic(self):
        self.receive()
        identifier = self.packet["reminder_id"]
        self.store.act(identifier, "dismissed")
        self.assertEqual("dismissed", self.store.act(identifier, "muted")["status"])
        self.assertEqual("dismissed", self.receive(reminder_action="cancelled")["status"])

    def test_expiry(self):
        self.receive()
        self.now += 120_000
        self.assertFalse(self.store.active())
        self.assertIsNone(self.receive())
        self.assertEqual("expired", self.store.act(self.packet["reminder_id"], "acknowledged")["status"])

    def test_invalid_envelopes(self):
        for change in ({"reminder_id": "../bad"}, {"created_at": True}, {"expires_at": "later"},
                       {"created_at": 0}, {"created_at": self.now + 30_001},
                       {"expires_at": self.now + 120_001}, {"expires_at": self.now}):
            with self.subTest(change=change):
                self.assertIsNone(self.receive(**change))
        self.assertFalse(self.events)

    def test_sensitive_fields_are_encrypted(self):
        self.receive()
        with closing(sqlite3.connect(self.path)) as db:
            encrypted = db.execute("SELECT payload FROM reminders").fetchone()[0]
        self.assertTrue(encrypted.startswith("enc:v1:"))
        self.assertNotIn("trusted-route", encrypted)
        self.assertNotIn("Test contact", encrypted)

    def test_invalid_local_action(self):
        self.receive()
        with self.assertRaises(ValueError):
            self.store.act(self.packet["reminder_id"], "request")


if __name__ == "__main__":
    unittest.main()
