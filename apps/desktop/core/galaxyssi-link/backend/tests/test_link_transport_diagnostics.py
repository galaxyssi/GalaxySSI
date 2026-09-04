from __future__ import annotations

import tempfile
import threading
import unittest
from pathlib import Path

from link_transport_diagnostics import (
    LinkTransportDiagnostics,
    anonymized_reference,
    classify_decryption_error,
    classify_fragment_error,
)


class DuplicateMessageExceptionForTest(RuntimeError):
    pass


class LinkTransportDiagnosticsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "link-diagnostics.json"

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_records_bounded_events_and_lifetime_counts(self) -> None:
        ticks = iter((1_000, 2_000, 3_000))
        diagnostics = LinkTransportDiagnostics(
            self.path,
            clock=lambda: next(ticks),
            maximum_events=2,
        )

        diagnostics.record(
            "encrypted_replay",
            route_id="private-route",
            message_id="message-1",
            detail_code="pre decrypt",
        )
        diagnostics.record("duplicate_message", message_id="message-2")
        snapshot = diagnostics.record("old_counter", message_id="message-3")

        self.assertEqual(3, snapshot["total_events"])
        self.assertEqual(
            {"replay": 1, "duplicate": 1, "old_counter": 1, "failure": 0},
            snapshot["summary"],
        )
        self.assertEqual(2, len(snapshot["recent_events"]))
        self.assertEqual("old_counter", snapshot["recent_events"][0]["kind"])

    def test_persistence_never_contains_raw_route_or_message_identity(self) -> None:
        diagnostics = LinkTransportDiagnostics(self.path)
        diagnostics.record(
            "decrypt_failure",
            route_id="galaxyssi:private-phone-id",
            message_id="secret-message-id",
            detail_code="Runtime Exception: private value",
        )

        persisted = self.path.read_text(encoding="utf-8")
        restored = LinkTransportDiagnostics(self.path).snapshot()
        event = restored["recent_events"][0]

        self.assertNotIn("private-phone-id", persisted)
        self.assertNotIn("secret-message-id", persisted)
        self.assertEqual(12, len(event["endpoint_ref"]))
        self.assertEqual(12, len(event["message_ref"]))
        self.assertEqual("runtime_exception_private_value", event["detail_code"])
        self.assertNotEqual(event["endpoint_ref"], event["message_ref"])

    def test_classifiers_distinguish_old_counter_duplicate_and_fragment_errors(self) -> None:
        self.assertEqual(
            "old_counter",
            classify_decryption_error(RuntimeError("Received message with old counter: 7")),
        )
        self.assertEqual(
            "duplicate_message",
            classify_decryption_error(DuplicateMessageExceptionForTest("duplicate message")),
        )
        self.assertEqual(
            "decrypt_failure",
            classify_decryption_error(ValueError("Malformed Signal body")),
        )
        self.assertEqual(
            "chunk_duplicate",
            classify_fragment_error(ValueError("Conflicting MQTT chunk duplicate")),
        )
        self.assertEqual(
            "fragment_rejected",
            classify_fragment_error(ValueError("MQTT chunk integrity check failed")),
        )
        self.assertRegex(anonymized_reference("route"), r"^[0-9a-f]{12}$")

    def test_concurrent_records_are_not_lost(self) -> None:
        diagnostics = LinkTransportDiagnostics(self.path, maximum_events=10)

        threads = [
            threading.Thread(
                target=lambda: [
                    diagnostics.record("duplicate_receipt", message_id=f"{index}-{offset}")
                    for offset in range(20)
                ]
            )
            for index in range(5)
        ]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()

        snapshot = diagnostics.snapshot()
        self.assertEqual(100, snapshot["total_events"])
        self.assertEqual(100, snapshot["counts"]["duplicate_receipt"])
        self.assertEqual(10, len(snapshot["recent_events"]))

    def test_malformed_persisted_fields_recover_without_breaking_diagnostics(self) -> None:
        self.path.write_text(
            '{"total_events":"bad","counts":{"old_counter":"bad"},'
            '"recent_events":[{"kind":"old_counter","recorded_at":"bad"}]}',
            encoding="utf-8",
        )

        snapshot = LinkTransportDiagnostics(self.path).snapshot()

        self.assertEqual(0, snapshot["total_events"])
        self.assertEqual(0, snapshot["counts"]["old_counter"])
        self.assertEqual(0, snapshot["recent_events"][0]["recorded_at"])


if __name__ == "__main__":
    unittest.main()
