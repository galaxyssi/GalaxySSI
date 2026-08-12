from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from peer_chat_store import PeerChatStore


class PeerChatStoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.store = PeerChatStore(Path(self.temporary.name) / "peer-chat.db")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_text_and_file_messages_are_isolated_by_phone_route(self) -> None:
        source = Path(self.temporary.name) / "report.txt"
        source.write_text("verified peer content", encoding="utf-8")
        attachment = self.store.import_attachment(
            client_route_id="phone-a",
            message_id="message-a",
            source=source,
            name="report.txt",
            mime_type="text/plain",
            sha256="a" * 64,
        )
        stored = self.store.append(
            client_route_id="phone-a",
            direction="inbound",
            content="For this phone only",
            attachments=[attachment],
            remote_message_id="remote-a",
        )
        self.store.append(
            client_route_id="phone-b",
            direction="outbound",
            content="Separate conversation",
        )

        phone_a = self.store.list_messages("phone-a")
        phone_b = self.store.list_messages("phone-b")
        self.assertEqual([stored["message_id"]], [item["message_id"] for item in phone_a])
        self.assertEqual("Separate conversation", phone_b[0]["content"])
        self.assertTrue(phone_a[0]["attachments"][0]["available"])
        self.assertNotIn("local_path", phone_a[0]["attachments"][0])
        self.assertEqual(source.read_bytes(), self.store.attachment_path(stored["message_id"], 0).read_bytes())

    def test_remote_message_replay_is_idempotent(self) -> None:
        first = self.store.append(
            client_route_id="phone-a",
            direction="inbound",
            content="hello",
            remote_message_id="same-wire-message",
        )
        second = self.store.append(
            client_route_id="phone-a",
            direction="inbound",
            content="hello",
            remote_message_id="same-wire-message",
        )

        self.assertEqual(first["message_id"], second["message_id"])
        self.assertEqual(1, len(self.store.list_messages("phone-a")))

    def test_empty_message_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            self.store.append(client_route_id="phone-a", direction="outbound")


if __name__ == "__main__":
    unittest.main()
