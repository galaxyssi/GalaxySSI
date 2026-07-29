import json
import os
import tempfile
import threading
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

from agent_execution_harness import (
    AgentClarificationMode,
    AgentClarificationQuestion,
    AgentExecutionMode,
    AgentExecutionHarness,
    AgentExecutionPolicy,
    AgentReasoningEffort,
    AgentTaskIntent,
    AgentTaskKind,
    classify_task_intent,
    clarification_decision_for,
    execution_contract,
    execution_policy_for,
    finalize_task_artifacts,
)
from task_workspace import task_workspace


class AgentExecutionHarnessTests(unittest.TestCase):
    def test_missing_required_details_ask_one_targeted_question(self):
        cases = {
            "Help me": AgentClarificationQuestion.TASK_GOAL,
            "Write a program": AgentClarificationQuestion.CODE_OUTCOME,
            "Control my computer": AgentClarificationQuestion.CONTROL_ACTION,
            "Research": AgentClarificationQuestion.RESEARCH_TOPIC,
            "Process the file": AgentClarificationQuestion.FILE_ACTION,
            "Remember this": AgentClarificationQuestion.MEMORY_CONTENT,
            "Create an automation": AgentClarificationQuestion.AUTOMATION_DETAILS,
            "\u5e2e\u6211\u5f04\u4e00\u4e0b": AgentClarificationQuestion.TASK_GOAL,
            "\u5199\u4e2a\u7a0b\u5e8f": AgentClarificationQuestion.CODE_OUTCOME,
            "\u63a7\u5236\u624b\u673a": AgentClarificationQuestion.CONTROL_ACTION,
            "\u641c\u7d22": AgentClarificationQuestion.RESEARCH_TOPIC,
            "\u8bb0\u4f4f\u8fd9\u4e2a": AgentClarificationQuestion.MEMORY_CONTENT,
            "\u521b\u5efa\u81ea\u52a8\u5316": AgentClarificationQuestion.AUTOMATION_DETAILS,
        }

        for prompt, expected_question in cases.items():
            with self.subTest(prompt=prompt):
                decision = clarification_decision_for(prompt)
                self.assertEqual(AgentClarificationMode.ASK_LOCALLY, decision.mode)
                self.assertEqual(expected_question, decision.question)

    def test_low_risk_and_contextual_requests_execute_without_clarification(self):
        direct_requests = (
            "Hello",
            "What is the battery level?",
            "Turn on the flashlight",
            "Set a one minute timer",
            "Research today's AI news",
            "Remember that I prefer concise replies",
            "Build an Android calculator app",
            "\u4f60\u597d",
            "\u6253\u5f00\u624b\u7535\u7b52",
            "\u67e5\u4e00\u4e0b\u4eca\u5929\u4e0a\u6d77\u7684\u5929\u6c14",
        )
        contextual_requests = (
            "Continue",
            "Try again",
            "Handle this",
            "\u7ee7\u7eed",
            "\u518d\u8bd5\u8bd5",
            "\u5e2e\u6211\u5f04\u4e00\u4e0b",
        )

        for prompt in direct_requests:
            with self.subTest(prompt=prompt):
                self.assertEqual(
                    AgentClarificationMode.EXECUTE,
                    clarification_decision_for(prompt).mode,
                )
        for prompt in contextual_requests:
            with self.subTest(prompt=prompt):
                self.assertEqual(
                    AgentClarificationMode.EXECUTE,
                    clarification_decision_for(
                        prompt,
                        has_conversation_context=True,
                    ).mode,
                )

    def test_attachment_only_clarification_stays_model_generated(self):
        for prompt in ("", "Take a look", "\u5904\u7406\u4e00\u4e0b"):
            with self.subTest(prompt=prompt):
                decision = clarification_decision_for(
                    prompt,
                    has_attachments=True,
                )
                self.assertEqual(AgentClarificationMode.ASK_WITH_MODEL, decision.mode)
                self.assertEqual(AgentClarificationQuestion.FILE_ACTION, decision.question)

    def test_classifier_covers_the_eight_canonical_task_intents(self):
        cases = {
            "Hello, how are you?": AgentTaskIntent.CHAT,
            "Build an Android app and run unit tests": AgentTaskIntent.CODE,
            "Turn on the flashlight on my phone": AgentTaskIntent.PHONE_CONTROL,
            "Open the browser on my computer": AgentTaskIntent.DESKTOP_CONTROL,
            "Research today's AI news and cite sources": AgentTaskIntent.RESEARCH,
            "Extract text from this PDF": AgentTaskIntent.FILE,
            "Remember that I prefer concise replies": AgentTaskIntent.MEMORY,
            "Run this health check every hour": AgentTaskIntent.AUTOMATION,
        }

        for prompt, expected in cases.items():
            with self.subTest(prompt=prompt):
                classification = classify_task_intent(prompt)
                self.assertEqual(expected, classification.intent)
                self.assertGreaterEqual(classification.confidence, 55)

    def test_attachment_is_a_file_intent_without_prompt_text(self):
        classification = classify_task_intent("", has_attachments=True)

        self.assertEqual(AgentTaskIntent.FILE, classification.intent)
        self.assertIn("attachment", classification.matched_signals)

    def test_classifier_uses_the_same_intents_for_chinese_prompts(self):
        cases = {
            "\u4f60\u597d": AgentTaskIntent.CHAT,
            "\u7f16\u8bd1\u8fd9\u4e2a\u9879\u76ee": AgentTaskIntent.CODE,
            "\u6253\u5f00\u624b\u673a\u624b\u7535\u7b52": AgentTaskIntent.PHONE_CONTROL,
            "\u63a7\u5236\u7535\u8111\u6253\u5f00\u6d4f\u89c8\u5668":
                AgentTaskIntent.DESKTOP_CONTROL,
            "\u641c\u7d22\u4eca\u5929\u7684\u65b0\u95fb": AgentTaskIntent.RESEARCH,
            "\u63d0\u53d6\u8fd9\u4e2a PDF \u6587\u4ef6\u7684\u6587\u5b57":
                AgentTaskIntent.FILE,
            "\u8bb0\u4f4f\u6211\u7684\u504f\u597d": AgentTaskIntent.MEMORY,
            "\u6bcf\u5929\u76d1\u63a7\u8fd9\u4e2a\u670d\u52a1":
                AgentTaskIntent.AUTOMATION,
        }

        for prompt, expected in cases.items():
            with self.subTest(prompt=prompt):
                self.assertEqual(expected, classify_task_intent(prompt).intent)

    def test_automation_outweighs_the_individual_phone_action(self):
        classification = classify_task_intent(
            "Turn on the phone flashlight every day at 8"
        )

        self.assertEqual(AgentTaskIntent.AUTOMATION, classification.intent)

    def test_generic_open_app_does_not_invent_a_phone_location(self):
        classification = classify_task_intent(
            "Open the app and show me its status"
        )

        self.assertEqual(AgentTaskIntent.CHAT, classification.intent)

    def test_malformed_intent_diagnostics_fail_closed_to_chat_metadata(self):
        policy = AgentExecutionPolicy.from_public({
            "task_intent": "invented_intent",
            "task_intent_confidence": "not-a-number",
            "task_intent_signals": "not-an-array",
        })

        self.assertEqual(AgentTaskIntent.CHAT, policy.task_intent)
        self.assertEqual(100, policy.task_intent_confidence)
        self.assertEqual((), policy.task_intent_signals)

    def test_policy_classifies_complex_tasks_and_has_no_absolute_deadline(self):
        policy = execution_policy_for(
            "Build an Android phone game and return the APK"
        )

        self.assertEqual(AgentTaskKind.BUILD, policy.task_kind)
        self.assertEqual(AgentTaskIntent.CODE, policy.task_intent)
        self.assertEqual(AgentReasoningEffort.MEDIUM, policy.reasoning_effort)
        self.assertEqual("android", policy.target_platform)
        self.assertTrue(policy.requires_artifact)
        self.assertGreaterEqual(policy.task_intent_confidence, 55)
        self.assertIn("build", policy.task_intent_signals)
        self.assertIsNone(policy.public()["absolute_timeout_seconds"])
        self.assertEqual(
            policy,
            type(policy).from_public(policy.public()),
        )

    def test_plan_only_mode_can_be_selected_by_prompt_or_request(self):
        explicit = execution_policy_for(
            "Build an Android app, but first give me a plan without executing"
        )
        configured = execution_policy_for(
            "Build an Android app",
            requested_execution_mode="plan_only",
        )

        for policy in (explicit, configured):
            with self.subTest(source=policy.public()):
                self.assertEqual(AgentExecutionMode.PLAN_ONLY, policy.execution_mode)
                self.assertFalse(policy.requires_artifact)
                self.assertFalse(policy.verify_installation)
                self.assertIn("Do not create, edit, delete", execution_contract(policy))
                self.assertEqual(
                    policy,
                    AgentExecutionPolicy.from_public(policy.public()),
                )

    def test_explicit_auto_complete_overrides_configured_plan_only(self):
        policy = execution_policy_for(
            "Implement this plan and execute until complete",
            requested_execution_mode="plan_only",
        )

        self.assertEqual(AgentExecutionMode.AUTO_COMPLETE, policy.execution_mode)
        self.assertTrue(policy.requires_artifact)

    def test_scoped_negative_instruction_does_not_disable_the_whole_task(self):
        policy = execution_policy_for(
            "\u5220\u9664\u8fc7\u671f\u8bb0\u5f55\uff0c\u4f46\u4e0d\u8981\u6267\u884c\u5220\u9664\u7cfb\u7edf\u6587\u4ef6"
        )

        self.assertEqual(AgentExecutionMode.AUTO_COMPLETE, policy.execution_mode)

    def test_input_attachment_uses_medium_reasoning_without_requiring_new_output(self):
        policy = execution_policy_for(
            "Summarize this spreadsheet",
            attachments=("downloads/input/report.xlsx",),
        )

        self.assertEqual(AgentTaskKind.ARTIFACT, policy.task_kind)
        self.assertEqual(AgentTaskIntent.FILE, policy.task_intent)
        self.assertEqual(AgentReasoningEffort.MEDIUM, policy.reasoning_effort)
        self.assertFalse(policy.requires_artifact)

    def test_checkpoint_and_same_failure_budget_are_persistent(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ,
            {"SIGNALASI_WORKSPACE_ROOT": temporary},
        ):
            harness = AgentExecutionHarness(
                "task-checkpoint",
                "hermes",
                "Build a small program",
            )
            can_replan, first_count = harness.record_failure(
                "command",
                "python verify.py exited 1",
            )
            second_replan, second_count = harness.record_failure(
                "command",
                "python verify.py exited 2",
            )
            checkpoint = (
                task_workspace("task-checkpoint", "hermes")
                / ".signalasi"
                / "execution-checkpoint.json"
            )
            data = json.loads(checkpoint.read_text(encoding="utf-8"))

            self.assertTrue(can_replan)
            self.assertEqual(1, first_count)
            self.assertFalse(second_replan)
            self.assertEqual(2, second_count)
            self.assertEqual("failed", data["phase"])
            self.assertEqual(1, data["replans"])
            self.assertEqual([2], list(data["failure_counts"].values()))

            AgentExecutionHarness(
                "task-checkpoint",
                "codex",
                "Build a small program",
            ).begin_attempt()
            restored = AgentExecutionHarness(
                "task-checkpoint",
                "hermes",
                "Build a small program",
            )

            self.assertEqual("failed", restored.checkpoint.phase)
            self.assertEqual(1, restored.checkpoint.replans)
            self.assertEqual([2], list(restored.checkpoint.failure_counts.values()))

    def test_concurrent_checkpoint_progress_keeps_valid_json(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ,
            {"SIGNALASI_WORKSPACE_ROOT": temporary},
        ):
            harness = AgentExecutionHarness(
                "task-concurrent-checkpoint",
                "codex",
                "Build a small program",
            )
            failures = []

            def update(index):
                try:
                    harness.progress("act", event_index=index)
                except Exception as exc:
                    failures.append(exc)

            threads = [
                threading.Thread(target=update, args=(index,))
                for index in range(40)
            ]
            for thread in threads:
                thread.start()
            for thread in threads:
                thread.join()

            checkpoint = (
                task_workspace("task-concurrent-checkpoint", "codex")
                / ".signalasi"
                / "execution-checkpoint.json"
            )
            data = json.loads(checkpoint.read_text(encoding="utf-8"))
            temporary_files = list(checkpoint.parent.glob("*.tmp"))

            self.assertEqual([], failures)
            self.assertEqual("task-concurrent-checkpoint", data["task_id"])
            self.assertEqual("act", data["phase"])
            self.assertEqual([], temporary_files)

    def test_locked_checkpoint_does_not_interrupt_execution(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ,
            {"SIGNALASI_WORKSPACE_ROOT": temporary},
        ):
            harness = AgentExecutionHarness(
                "task-locked-checkpoint",
                "codex",
                "Build a small program",
            )
            with patch(
                "agent_execution_harness.os.replace",
                side_effect=PermissionError(5, "access denied"),
            ):
                harness.progress("observe", tool="python verify.py")

            self.assertEqual("observe", harness.checkpoint.phase)
            self.assertEqual(
                "python verify.py",
                harness.checkpoint.verification["tool"],
            )

    def test_single_file_stays_native(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ,
            {"SIGNALASI_WORKSPACE_ROOT": temporary},
        ):
            root = task_workspace("task-single", "codex")
            (root / "main.py").write_text("print('ok')\n", encoding="utf-8")

            result = finalize_task_artifacts(
                "task-single",
                "Write a program and return the file",
                "codex",
            )

            self.assertFalse(result.packaged)
            self.assertEqual(["main.py"], [item["name"] for item in result.output_files])
            self.assertEqual("passed", result.verification["status"])

    def test_multi_file_project_is_packaged_and_verified(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ,
            {"SIGNALASI_WORKSPACE_ROOT": temporary},
        ):
            root = task_workspace("task-project", "claude")
            project = root / "game"
            project.mkdir()
            (project / "index.html").write_text("<canvas></canvas>", encoding="utf-8")
            (project / "game.js").write_text("console.log('ok')", encoding="utf-8")

            result = finalize_task_artifacts(
                "task-project",
                "Build a phone game and return the project",
                "claude",
            )

            self.assertTrue(result.packaged)
            self.assertEqual(1, len(result.output_files))
            archive = root / result.output_files[0]["relative_path"]
            with zipfile.ZipFile(archive) as bundle:
                self.assertEqual(
                    {"game/game.js", "game/index.html"},
                    set(bundle.namelist()),
                )
            self.assertEqual("passed", result.verification["status"])

    def test_valid_apk_requires_phone_handoff_when_install_is_not_authorized(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ,
            {"SIGNALASI_WORKSPACE_ROOT": temporary},
        ):
            root = task_workspace("task-apk", "codex")
            apk = root / "build" / "app-debug.apk"
            apk.parent.mkdir()
            with zipfile.ZipFile(apk, "w") as bundle:
                bundle.writestr("AndroidManifest.xml", b"manifest")
                bundle.writestr("classes.dex", b"dex")

            result = finalize_task_artifacts(
                "task-apk",
                "Build and install an Android APK on the phone",
                "codex",
                allow_device_install=False,
            )

            self.assertEqual(["app-debug.apk"], [item["name"] for item in result.output_files])
            self.assertEqual("passed", result.verification["status"])
            self.assertEqual(
                "phone_handoff_required",
                result.verification["installation"]["status"],
            )


if __name__ == "__main__":
    unittest.main()
