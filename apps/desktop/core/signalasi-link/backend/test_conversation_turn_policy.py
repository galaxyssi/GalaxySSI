from __future__ import annotations

import unittest

from conversation_turn_policy import should_steer_active_turn


class ConversationTurnPolicyTests(unittest.TestCase):
    def test_independent_rapid_requests_do_not_steer(self) -> None:
        self.assertFalse(
            should_steer_active_turn(
                "Reply exactly FAST-B-726.",
                "Reply exactly FAST-A-726.",
            )
        )
        self.assertFalse(
            should_steer_active_turn(
                "Write a Python calculator.",
                "Find today's technology news.",
            )
        )

    def test_explicit_correction_steers_active_turn(self) -> None:
        self.assertTrue(
            should_steer_active_turn(
                "\u66f4\u6b63\u4e3a Android \u624b\u673a\u4e0a\u53ef\u4ee5\u73a9\u7684\u8d2a\u5403\u86c7",
                "\u5199\u4e00\u4e2a\u8d2a\u5403\u86c7\u6e38\u620f",
            )
        )
        self.assertTrue(
            should_steer_active_turn(
                "\u8981\u4fdd\u8bc1\u6b63\u786e",
                "\u6279\u6539\u8fd9\u5f20\u4f5c\u4e1a",
            )
        )

    def test_reference_to_previous_result_steers(self) -> None:
        self.assertTrue(
            should_steer_active_turn(
                "Use the previous image and make the title larger.",
                "Create a poster.",
            )
        )

    def test_new_attachment_is_independent_without_continuation_cue(self) -> None:
        self.assertFalse(
            should_steer_active_turn(
                "Review this image.",
                "Build an Android game.",
                has_new_attachments=True,
            )
        )
        self.assertTrue(
            should_steer_active_turn(
                "Use this image instead.",
                "Review the earlier image.",
                has_new_attachments=True,
            )
        )

    def test_explicit_new_task_never_steers(self) -> None:
        self.assertFalse(
            should_steer_active_turn(
                "\u65b0\u4efb\u52a1\uff1a\u67e5\u4e0a\u6d77\u5929\u6c14",
                "\u4fee\u6539 Android \u9879\u76ee",
            )
        )


if __name__ == "__main__":
    unittest.main()
