from __future__ import annotations

import re
import unittest
from pathlib import Path

import link_protocol


REPOSITORY_ROOT = Path(__file__).resolve().parents[5]
DESKTOP_TRANSPORT_FILES = (
    "apps/desktop/core/galaxyssi-link/backend/link_protocol.py",
    "apps/desktop/core/galaxyssi-link/backend/main.py",
    "apps/desktop/core/galaxyssi-link/backend/mqtt_bridge.py",
    "apps/desktop/core/galaxyssi-link/backend/mqtt_wire_chunking.py",
    "apps/desktop/core/galaxyssi-link/backend/pairing_state.py",
)
ANDROID_TRANSPORT_FILES = (
    "apps/android/app/src/main/java/com/galaxyssi/chat/PhoneContactCard.kt",
    "apps/android/app/src/main/java/com/galaxyssi/chat/GalaxySSILinkProtocol.kt",
    "apps/android/app/src/main/java/com/galaxyssi/chat/GalaxySSILinkSubscriptionCoordinator.kt",
    "apps/android/app/src/main/java/com/galaxyssi/chat/GalaxySSIMqttClient.kt",
    "apps/android/app/src/main/java/com/galaxyssi/chat/GalaxySSIMqttClientIdentity.kt",
    "apps/android/app/src/main/java/com/galaxyssi/chat/GalaxySSIMqttMessagePublisher.kt",
    "apps/android/app/src/main/java/com/galaxyssi/chat/GalaxySSIMqttWireChunking.kt",
)


class ProtocolPrivacyGuardTests(unittest.TestCase):
    def source(self, relative_path: str) -> str:
        return (REPOSITORY_ROOT / relative_path).read_text(encoding="utf-8")

    def test_transport_sources_do_not_restore_semantic_public_topics(self) -> None:
        forbidden = (
            "galaxyssichat/",
            "galaxyssichat/android",
            "server_route_id",
            "mqtt_inbox_topic",
            "reply_topic",
        )
        for relative_path in DESKTOP_TRANSPORT_FILES + ANDROID_TRANSPORT_FILES:
            source = self.source(relative_path)
            for marker in forbidden:
                self.assertNotIn(marker, source, f"{marker!r} leaked in {relative_path}")

    def test_public_transport_never_uses_retained_messages(self) -> None:
        desktop = self.source(DESKTOP_TRANSPORT_FILES[2])
        android = self.source(ANDROID_TRANSPORT_FILES[3])
        self.assertNotRegex(desktop, re.compile(r"retain\s*=\s*True"))
        self.assertNotRegex(android, re.compile(r"isRetained\s*=\s*true"))

    def test_generated_topics_have_no_structure_or_product_name(self) -> None:
        secret = link_protocol.new_link_secret()
        topics = link_protocol.LinkTopics(secret, "a" * 64, "b" * 64, epoch=123)
        for topic in (topics.send, topics.receive, *topics.receive_window):
            self.assertRegex(topic, r"^[A-Za-z0-9_-]{43}$")
            self.assertNotIn("/", topic)
            self.assertNotIn("galaxyssi", topic.lower())


if __name__ == "__main__":
    unittest.main()
