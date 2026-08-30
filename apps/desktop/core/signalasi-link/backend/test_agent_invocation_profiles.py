import os
import unittest
from unittest.mock import patch

from agent_invocation_profiles import (
    invocation_profile_for,
    requested_agent_invocation,
)


class AgentInvocationProfileTests(unittest.TestCase):
    def test_codex_profile_uses_configured_command_model_and_all_efforts(self):
        profile = invocation_profile_for(
            "codex",
            ["codex", "exec", "--model", "gpt-5.6-sol", "-"],
        )

        self.assertEqual("gpt-5.6-sol", profile.default_model)
        self.assertEqual(("gpt-5.6-sol",), profile.models)
        self.assertEqual(("low", "medium", "high", "xhigh"), profile.reasoning_efforts)

    def test_codex_additional_models_are_advertised_without_duplicates(self):
        with patch.dict(
            os.environ,
            {"SIGNALASI_CODEX_MODELS": "gpt-5.6-sol,gpt-5.6-sol-fast"},
        ):
            profile = invocation_profile_for(
                "codex",
                ["codex", "exec", "--model", "gpt-5.6-sol", "-"],
            )

        self.assertEqual(("gpt-5.6-sol", "gpt-5.6-sol-fast"), profile.models)

    def test_selected_model_and_extra_high_effort_are_validated(self):
        selection = requested_agent_invocation(
            "codex",
            {"model_id": "gpt-5.6-sol", "reasoning_effort": "xhigh"},
            ["codex", "exec", "--model", "gpt-5.6-sol", "-"],
        )

        self.assertEqual("gpt-5.6-sol", selection.model_id)
        self.assertEqual("xhigh", selection.reasoning_effort)

    def test_unadvertised_model_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "not advertised"):
            requested_agent_invocation(
                "codex",
                {"model_id": "unknown-model", "reasoning_effort": "high"},
                ["codex", "exec", "--model", "gpt-5.6-sol", "-"],
            )

    def test_automatic_effort_keeps_desktop_policy(self):
        selection = requested_agent_invocation(
            "codex",
            {"model_id": "gpt-5.6-sol", "reasoning_effort": "auto"},
            ["codex", "exec", "--model", "gpt-5.6-sol", "-"],
        )

        self.assertEqual("", selection.reasoning_effort)


if __name__ == "__main__":
    unittest.main()
