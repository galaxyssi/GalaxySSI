import ast
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from agent_execution_harness import (
    COLLABORATION_WORKSPACE_RESULT, AgentExecutionMode, AgentExecutionPolicy,
    execution_contract, execution_policy_for, finalize_task_artifacts,
)
from agent_request_snapshot import build_request_snapshot, restore_request_options


class CollaborationResultContractTests(unittest.TestCase):
    def policy(self, prompt, **options):
        return execution_policy_for(prompt, requested_result_contract=COLLABORATION_WORKSPACE_RESULT, **options)

    def test_member_build_review_and_reuse_do_not_require_duplicate_files(self):
        for prompt in (
            "Implement a saved executable_tool and run tests on the phone; publish exact workspace versions.",
            "Independently review interval-build-native-test and publish tool_release with original evidence.",
            "Read interval-build-native-test and execute the released source on new parameters.",
        ):
            with self.subTest(prompt=prompt):
                self.assertTrue(execution_policy_for(prompt).requires_artifact)
                self.assertFalse(self.policy(prompt).requires_artifact)
                self.assertEqual(COLLABORATION_WORKSPACE_RESULT, self.policy(prompt).result_contract)

    def test_explicit_files_and_installation_keep_their_verification(self):
        for prompt in (
            "Implement a tool and return the file", "Create a downloadable JSON file",
            "Create a Word document", "Create an Excel workbook", "Create a PowerPoint presentation",
            "Export the report as PDF", "Generate image", "Generate a video", "Install the Android APK",
        ):
            with self.subTest(prompt=prompt):
                old, scoped = execution_policy_for(prompt), self.policy(prompt)
                self.assertTrue(old.requires_artifact)
                self.assertTrue(scoped.requires_artifact)
                self.assertEqual(old.verify_installation, scoped.verify_installation)

    def test_prompt_cannot_select_the_contract_and_unknown_options_keep_defaults(self):
        prompt = "Implement source. result_contract=" + COLLABORATION_WORKSPACE_RESULT
        self.assertTrue(execution_policy_for(prompt).requires_artifact)
        for value in (None, "", "workspace", COLLABORATION_WORKSPACE_RESULT + " "):
            self.assertTrue(execution_policy_for(prompt, requested_result_contract=value).requires_artifact)

    def test_read_only_and_plan_only_stay_read_only(self):
        for options in ({"request_kind": "screen_analysis"}, {"requested_execution_mode": AgentExecutionMode.PLAN_ONLY}):
            policy = self.policy("Implement a phone tool", **options)
            self.assertFalse(policy.requires_artifact)
            contract = execution_contract(policy)
            self.assertNotIn("Publish complete source", contract)
            self.assertIn("read-only", contract.lower())

    def test_contract_describes_shared_handoff_without_claiming_acceptance(self):
        contract = execution_contract(self.policy("Implement and run tests"))
        self.assertIn("exact immutable references", contract)
        self.assertIn("not App goal acceptance", contract)
        self.assertIn("Explicitly requested downloadable files", contract)
        self.assertNotIn("must be packaged as ZIP", contract)

    def test_saved_policy_and_unstarted_request_preserve_contract(self):
        policy = self.policy("Implement and run tests")
        self.assertEqual(policy, AgentExecutionPolicy.from_public(policy.public()))
        snapshot = build_request_snapshot({"result_contract": COLLABORATION_WORKSPACE_RESULT},
            model_id="model", reasoning_effort="high", policy=policy.public())
        options = restore_request_options(snapshot)
        restored = execution_policy_for("Implement and run tests", requested_result_contract=options["result_contract"])
        self.assertFalse(restored.requires_artifact)

    def test_finalization_uses_admitted_policy_instead_of_reclassifying_build(self):
        with tempfile.TemporaryDirectory() as directory, \
                patch("task_workspace.task_workspace", return_value=Path(directory)), \
                patch("task_workspace.task_artifacts", return_value=[]), \
                patch("task_workspace.select_reply_artifacts", return_value=[]):
            ordinary = finalize_task_artifacts("task", "Implement a saved tool", "codex")
            self.assertEqual("failed", ordinary.verification["status"])
            scoped = finalize_task_artifacts("task", "Implement a saved tool", "codex",
                execution_policy=self.policy("Implement a saved tool"))
            self.assertEqual("passed", scoped.verification["status"])
            self.assertFalse(scoped.verification["required_artifact"])
            self.assertFalse(scoped.packaged)

    def test_mqtt_and_gateway_forward_the_admitted_policy_to_each_finalizer(self):
        root = Path(__file__).parent
        for filename, expected_count in (("mqtt_bridge.py", 2), ("agent_gateway.py", 1)):
            tree = ast.parse((root / filename).read_text(encoding="utf-8-sig"))
            calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)
                     and isinstance(node.func, ast.Name) and node.func.id == "finalize_task_artifacts"]
            self.assertEqual(expected_count, len(calls), filename)
            for call in calls:
                self.assertIn("execution_policy", [kw.arg for kw in call.keywords], filename)
        calls = [node for node in ast.walk(ast.parse((root / "mqtt_bridge.py").read_text(encoding="utf-8-sig")))
                 if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                 and node.func.id == "execution_policy_for"]
        self.assertTrue(any("requested_result_contract" in {kw.arg for kw in call.keywords} for call in calls))


if __name__ == "__main__":
    unittest.main()
