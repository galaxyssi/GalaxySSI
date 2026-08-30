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
        self.assertEqual(
            (
                "gpt-5.6-sol",
                "gpt-5.6-terra",
                "gpt-5.6-luna",
                "gpt-5.5",
                "gpt-5.4",
                "gpt-5.4-mini",
                "gpt-5.3-codex-spark",
            ),
            profile.models,
        )
        self.assertEqual(("low", "medium", "high", "xhigh"), profile.reasoning_efforts)
        self.assertEqual(
            "\u80fd\u529b\u6700\u5f3a\uff0c\u590d\u6742\u7f16\u7801\u4e0e\u957f\u671f\u4efb\u52a1",
            profile.public()["models"][0]["description"],
        )

    def test_codex_additional_models_are_advertised_without_duplicates(self):
        with patch.dict(
            os.environ,
            {"SIGNALASI_CODEX_MODELS": "gpt-5.6-sol,gpt-5.6-sol-fast"},
        ):
            profile = invocation_profile_for(
                "codex",
                ["codex", "exec", "--model", "gpt-5.6-sol", "-"],
            )

        self.assertEqual("gpt-5.6-sol", profile.models[0])
        self.assertEqual("gpt-5.6-sol-fast", profile.models[-1])
        self.assertEqual(len(profile.models), len(set(profile.models)))

    def test_claude_profile_advertises_models_without_reasoning_effort(self):
        profile = invocation_profile_for("claude", ["claude", "-p"])

        self.assertEqual("best", profile.default_model)
        self.assertEqual(
            (
                "best",
                "fableclaude-fable-5",
                "opusclaude-opus-5",
                "sonnetclaude-sonnet-5",
                "haikuclaude-haiku-4-5-20251001",
                "opusplan",
                "opus[1m]",
                "sonnet[1m]",
            ),
            profile.models,
        )
        self.assertEqual((), profile.reasoning_efforts)
        self.assertEqual(
            "\u6709\u6743\u9650\u65f6\u4f7f\u7528 Fable 5\uff0c\u5426\u5219 Opus 5",
            profile.public()["models"][0]["description"],
        )

    def test_claude_selected_model_is_validated_without_reasoning(self):
        selection = requested_agent_invocation(
            "claude",
            {"model_id": "opus[1m]", "reasoning_effort": "auto"},
            ["claude", "-p"],
        )

        self.assertEqual("opus[1m]", selection.model_id)
        self.assertEqual("", selection.reasoning_effort)

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
