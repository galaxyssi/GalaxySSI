import unittest

from conversation_context import ContextAttachment
from model_recovery import (
    ModelRecoveryAction,
    RECOVERY_ACTION_FOOTER,
    RECOVERY_ACTION_HEADER,
    parse_model_recovery,
    recovery_contract,
)


class ModelRecoveryTests(unittest.TestCase):
    def setUp(self):
        self.image = ContextAttachment(
            artifact_id="image-one",
            kind="image",
            name="homework.jpg",
            mime_type="image/jpeg",
            size_bytes=120_000,
            group_id="turn-one",
        )

    def test_explicit_attachment_request_uses_only_catalog_ids(self):
        reply = (
            f"{RECOVERY_ACTION_HEADER}\n"
            '{"version":1,"action":"request_attachment",'
            '"attachment_ids":["image-one","forged"],'
            '"reason":"Need the original pixels"}\n'
            f"{RECOVERY_ACTION_FOOTER}"
        )

        parsed = parse_model_recovery(reply, [self.image])

        self.assertEqual("", parsed.visible_reply)
        self.assertEqual(ModelRecoveryAction.REQUEST_ATTACHMENT, parsed.decision.action)
        self.assertEqual(("image-one",), parsed.decision.attachment_ids)

    def test_implicit_model_failure_requests_prior_image(self):
        parsed = parse_model_recovery(
            "I cannot see the previous image. Please upload it again.",
            [self.image],
        )

        self.assertEqual(ModelRecoveryAction.REQUEST_ATTACHMENT, parsed.decision.action)
        self.assertEqual(("image-one",), parsed.decision.attachment_ids)
        self.assertFalse(parsed.decision.explicit)

    def test_normal_answer_does_not_trigger_recovery(self):
        parsed = parse_model_recovery("The image shows three completed exercises.", [self.image])

        self.assertIsNone(parsed.decision)
        self.assertIn("three completed", parsed.visible_reply)

    def test_contract_exposes_metadata_but_not_file_bytes(self):
        contract = recovery_contract([self.image])

        self.assertIn("image-one", contract)
        self.assertIn("homework.jpg", contract)
        self.assertIn("infer the user's most likely useful intent", contract)
        self.assertNotIn("data_b64", contract)


if __name__ == "__main__":
    unittest.main()
