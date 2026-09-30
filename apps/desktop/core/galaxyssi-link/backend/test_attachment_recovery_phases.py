from dataclasses import replace
import unittest
from unittest.mock import patch

from attachment_request_broker import AttachmentRequestBroker, AttachmentRecoveryTimeout
from input_attachment_transfer import AttachmentTransferReceipt
from link_protocol import new_route_id


class AttachmentRecoveryPhaseTests(unittest.TestCase):
    def setUp(self):
        self.broker = AttachmentRequestBroker()
        self.route = new_route_id()

    def request(self, publish, ids=("image-one",)):
        return self.broker.request(
            client_route_id=self.route, conversation_id="private-conversation",
            task_id="private-task", turn_id="private-turn", contact_id="private-contact",
            source_message_id="42", attachment_ids=ids, reason="private-reason",
            publish=publish, timeout_seconds=1,
        )

    def receipt(self, payload, attachment_id="image-one"):
        return AttachmentTransferReceipt(
            transfer_id="a" * 64, status="stored", sha256="b" * 64,
            attachment_id=attachment_id, attachment_request_id=payload["request_id"],
            name="private-file.xlsx", mime_type="application/octet-stream", size_bytes=12,
            client_route_id=self.route, conversation_id=payload["conversation_id"],
            task_id=payload["task_id"], turn_id=payload["turn_id"],
            contact_id=payload["contact_id"], source_message_id="42",
        )

    def response(self, payload, **changes):
        return {**payload, "type": "input_attachment_request_result", "status": "transferring",
                "available_attachment_ids": list(payload["attachment_ids"]),
                "missing_attachment_ids": [], **changes}

    def assert_timeout(self, publish, phase, received=0, ids=("image-one",)):
        with patch("attachment_request_broker.threading.Event.wait", return_value=False):
            with self.assertRaises(AttachmentRecoveryTimeout) as failure:
                self.request(publish, ids)
        self.assertEqual(phase, failure.exception.phase)
        self.assertEqual(received, failure.exception.received)
        self.assertEqual(len(ids), failure.exception.expected)
        self.assertFalse(self.broker._pending)

    def test_transport_acceptance_does_not_prove_phone_response(self):
        self.assert_timeout(lambda _: True, "awaiting_phone_response")

    def test_phone_confirmation_does_not_prove_verified_transfer(self):
        def publish(payload):
            self.assertTrue(self.broker.accept_result(self.response(payload), client_route_id=self.route))
            return True
        self.assert_timeout(publish, "awaiting_files")

    def test_partial_receipts_identify_missing_transfer_even_without_status_response(self):
        def publish(payload):
            self.assertTrue(self.broker.accept_receipt(self.receipt(payload)))
            return True
        self.assert_timeout(publish, "awaiting_files", received=1, ids=("image-one", "image-two"))

    def test_unknown_status_cannot_inject_missing_or_available_state(self):
        def publish(payload):
            for changes in (
                {"status": "unknown", "available_attachment_ids": [], "missing_attachment_ids": ["image-one"]},
                {"status": "unknown"},
                {"status": "missing", "missing_attachment_ids": []},
                {"missing_attachment_ids": ["image-one"]},
            ):
                self.assertFalse(self.broker.accept_result(self.response(payload, **changes), client_route_id=self.route))
            self.assertTrue(self.broker.accept_receipt(self.receipt(payload)))
            return True
        self.assertEqual("image-one", self.request(publish)[0]["id"])

    def test_cross_scope_response_cannot_advance_timeout_phase(self):
        for field in ("request_id", "client_route_id", "conversation_id", "task_id",
                      "turn_id", "contact_id", "source_message_id"):
            with self.subTest(field=field):
                def publish(payload):
                    self.assertFalse(self.broker.accept_result(
                        self.response(payload, **{field: "unrelated"}), client_route_id=self.route))
                    return True
                self.assert_timeout(publish, "awaiting_phone_response")

    def test_cross_scope_receipt_cannot_advance_timeout_phase(self):
        def publish(payload):
            for field in ("attachment_request_id", "client_route_id", "conversation_id", "task_id",
                          "turn_id", "contact_id", "source_message_id", "attachment_id"):
                self.assertFalse(self.broker.accept_receipt(replace(self.receipt(payload), **{field: "unrelated"})))
            return True
        self.assert_timeout(publish, "awaiting_phone_response")

    def test_stored_status_alone_cannot_complete_recovery(self):
        def publish(payload):
            self.assertTrue(self.broker.accept_result(self.response(payload, status="stored"), client_route_id=self.route))
            return True
        self.assert_timeout(publish, "awaiting_files")

    def test_receipt_at_wait_boundary_wins_over_false_timeout(self):
        def publish(payload):
            self.assertTrue(self.broker.accept_receipt(self.receipt(payload)))
            return True
        with patch("attachment_request_broker.threading.Event.wait", return_value=False):
            self.assertEqual("image-one", self.request(publish)[0]["id"])

    def test_diagnostics_are_content_free_and_duplicate_receipts_are_quiet(self):
        def publish(payload):
            self.assertTrue(self.broker.accept_result(self.response(payload), client_route_id=self.route))
            self.assertTrue(self.broker.accept_result(self.response(payload), client_route_id=self.route))
            self.assertTrue(self.broker.accept_receipt(self.receipt(payload)))
            self.assertTrue(self.broker.accept_receipt(self.receipt(payload)))
            self.assertTrue(self.broker.accept_receipt(self.receipt(payload, "image-two")))
            return True
        with self.assertLogs("galaxyssi.attachment_recovery", "INFO") as captured:
            self.request(publish, ("image-one", "image-two"))
        logs = "\n".join(captured.output)
        self.assertNotIn("private-", logs)
        self.assertNotIn(self.route, logs)
        self.assertNotIn("image-one", logs)
        self.assertEqual(1, logs.count("outcome=phone_response"))
        self.assertEqual(2, logs.count("outcome=file_verified"))
        self.assertIn("outcome=completed phase=verified verified=2 expected=2", logs)


if __name__ == "__main__":
    unittest.main()
