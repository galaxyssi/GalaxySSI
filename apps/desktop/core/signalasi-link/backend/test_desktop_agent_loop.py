from __future__ import annotations

import unittest

from desktop_agent_loop import (
    AgentLoopBudget,
    AgentLoopFailureKind,
    AgentLoopObservation,
    AgentLoopTrace,
    classify_failure,
)


class DesktopAgentLoopTest(unittest.TestCase):
    def test_failure_classification_preserves_recovery_semantics(self):
        cases = (
            ({"code": "approval_required"}, AgentLoopFailureKind.PERMISSION_REQUIRED),
            ({"code": "missing_input"}, AgentLoopFailureKind.INPUT_REQUIRED),
            ({"message": "Agent timed out"}, AgentLoopFailureKind.TIMEOUT),
            ({"code": "tool_unavailable"}, AgentLoopFailureKind.TOOL_UNAVAILABLE),
            ({"code": "desktop_tool_busy", "retryable": True}, AgentLoopFailureKind.TRANSIENT),
        )

        for arguments, expected in cases:
            with self.subTest(arguments=arguments):
                self.assertEqual(classify_failure(**arguments), expected)

    def test_verification_is_required_for_a_successful_observation(self):
        missing = AgentLoopObservation("tool", "read", "succeeded", output={"value": 1})
        passed = AgentLoopObservation(
            "tool",
            "read",
            "succeeded",
            output={"value": 1},
            verification={"status": "passed"},
        )

        self.assertFalse(missing.verified)
        self.assertTrue(passed.verified)

    def test_iteration_budget_stops_unbounded_execution(self):
        trace = AgentLoopTrace(AgentLoopBudget(max_iterations=2))

        self.assertEqual(trace.next_iteration(), 1)
        self.assertEqual(trace.next_iteration(), 2)
        with self.assertRaisesRegex(RuntimeError, "budget exhausted"):
            trace.next_iteration()


if __name__ == "__main__":
    unittest.main()
