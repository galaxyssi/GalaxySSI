import threading
import unittest

from attachment_request_broker import AttachmentRequestBroker, AttachmentRequestError
from input_attachment_transfer import AttachmentTransferReceipt
from link_protocol import new_route_id


class AttachmentRequestBrokerTests(unittest.TestCase):
    def test_verified_receipt_completes_exact_task_scoped_request(self):
        broker = AttachmentRequestBroker()
        route_id = new_route_id()
        published = []

        def publish(payload):
            published.append(payload)

            def answer():
                broker.accept_result(
                    {
                        **payload,
                        "type": "input_attachment_request_result",
                        "status": "transferring",
                        "available_attachment_ids": ["image-one"],
                        "missing_attachment_ids": [],
                    },
                    client_route_id=route_id,
                )
                broker.accept_receipt(
                    AttachmentTransferReceipt(
                        transfer_id="a" * 64,
                        status="stored",
                        sha256="b" * 64,
                        attachment_id="image-one",
                        attachment_request_id=payload["request_id"],
                        name="homework.jpg",
                        mime_type="image/jpeg",
                        size_bytes=120_000,
                        client_route_id=route_id,
                        conversation_id="conversation-one",
                        task_id="task-one",
                        turn_id="turn-one",
                        contact_id="codex",
                        source_message_id="42",
                    )
                )

            threading.Thread(target=answer).start()
            return True

        descriptors = broker.request(
            client_route_id=route_id,
            conversation_id="conversation-one",
            task_id="task-one",
            turn_id="turn-one",
            contact_id="codex",
            source_message_id="42",
            attachment_ids=["image-one"],
            reason="The model needs the original image",
            publish=publish,
            timeout_seconds=2,
        )

        self.assertEqual(1, len(published))
        self.assertEqual("image-one", descriptors[0]["id"])
        self.assertEqual("a" * 64, descriptors[0]["transfer_id"])

    def test_cross_task_receipt_is_rejected(self):
        broker = AttachmentRequestBroker()
        receipt = AttachmentTransferReceipt(
            transfer_id="a" * 64,
            status="stored",
            sha256="b" * 64,
            attachment_id="image-one",
            attachment_request_id="c" * 32,
            name="homework.jpg",
            mime_type="image/jpeg",
            size_bytes=12,
            client_route_id=new_route_id(),
            conversation_id="other",
            task_id="other",
            turn_id="other",
            contact_id="codex",
            source_message_id="42",
        )

        self.assertFalse(broker.accept_receipt(receipt))

    def test_offline_publish_fails_without_waiting_for_timeout(self):
        broker = AttachmentRequestBroker()

        with self.assertRaisesRegex(AttachmentRequestError, "could not be delivered"):
            broker.request(
                client_route_id=new_route_id(),
                conversation_id="conversation-one",
                task_id="task-one",
                turn_id="turn-one",
                contact_id="codex",
                source_message_id="42",
                attachment_ids=["image-one"],
                reason="Need image",
                publish=lambda _payload: False,
                timeout_seconds=2,
            )


if __name__ == "__main__":
    unittest.main()
