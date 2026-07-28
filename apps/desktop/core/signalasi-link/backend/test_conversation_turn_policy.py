from __future__ import annotations

import unittest

from conversation_turn_policy import (
    ActiveTurnDisposition,
    ActiveTurnInterventionKind,
    classify_active_turn,
    should_steer_active_turn,
    superseding_prompt,
)


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

    def test_standalone_interrupt_is_not_sent_as_model_guidance(self) -> None:
        for request in (
            "stop",
            "Cancel the current task.",
            "\u505c\u6b62\u5f53\u524d\u4efb\u52a1",
            "\u4e0d\u7528\u7ee7\u7eed\u4e86",
        ):
            with self.subTest(request=request):
                decision = classify_active_turn(request, "Build the Android app")
                self.assertEqual(ActiveTurnDisposition.INTERRUPT, decision.disposition)
                self.assertEqual(
                    ActiveTurnInterventionKind.INTERRUPT,
                    decision.intervention_kind,
                )
                self.assertFalse(should_steer_active_turn(request, "Build the Android app"))

    def test_interrupt_words_inside_constraints_do_not_cancel(self) -> None:
        decision = classify_active_turn(
            "Do not stop after the first page.",
            "Export the whole report.",
        )
        self.assertEqual(ActiveTurnDisposition.STEER, decision.disposition)
        self.assertEqual(ActiveTurnInterventionKind.CONSTRAINT, decision.intervention_kind)

    def test_goal_change_and_constraint_are_distinguished(self) -> None:
        goal_change = classify_active_turn(
            "\u6539\u6210 Android \u539f\u751f\u5e94\u7528",
            "\u505a\u4e00\u4e2a\u7f51\u9875\u5e94\u7528",
        )
        constraint = classify_active_turn(
            "\u8981\u4fdd\u8bc1\u79bb\u7ebf\u53ef\u7528",
            "\u505a\u4e00\u4e2a Android \u5e94\u7528",
        )
        self.assertEqual(
            ActiveTurnInterventionKind.GOAL_CHANGE,
            goal_change.intervention_kind,
        )
        self.assertEqual(
            ActiveTurnInterventionKind.CONSTRAINT,
            constraint.intervention_kind,
        )

    def test_superseding_prompt_preserves_both_requests_with_latest_priority(self) -> None:
        prompt = superseding_prompt(
            "Build a web game",
            "Change the goal to an Android game",
            kind=ActiveTurnInterventionKind.GOAL_CHANGE,
        )
        self.assertIn("Build a web game", prompt)
        self.assertIn("Change the goal to an Android game", prompt)
        self.assertIn("latest instruction has priority", prompt)


if __name__ == "__main__":
    unittest.main()
