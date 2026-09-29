import unittest
import os
import tempfile
from unittest.mock import patch

from agent_execution_harness import AgentTaskIntent, AgentTaskKind, classify_task_intent, execution_policy_for, finalize_task_artifacts
from artifact_request_policy import keep_office_outputs_separate, office_artifact_requested, positive_term
from task_workspace import task_workspace


class ArtifactRequestPolicyTests(unittest.TestCase):
    def test_office_deliverables_are_artifacts_not_code_or_research(self):
        for format_name in ("DOCX", "XLSX", "PPTX"):
            with self.subTest(format=format_name):
                prompt = (f'\u8bf7\u5b9e\u9645\u751f\u6210\u53ef\u7f16\u8f91\u7684 {format_name}\u3002'
                          '{"\u9879\u76ee": "\u7532", "\u6570\u91cf": 11}\u3002'
                          '\u4e0d\u80fd\u53ea\u7ed9\u672c\u673a\u8def\u5f84\u3001\u4ee3\u7801\u3002\u4e0d\u8981\u8054\u7f51\u3002')
                policy = execution_policy_for(prompt)
                self.assertEqual(AgentTaskKind.ARTIFACT, policy.task_kind)
                self.assertEqual(AgentTaskIntent.FILE, policy.task_intent)
                self.assertTrue(policy.requires_artifact)

    def test_negated_generation_does_not_require_an_artifact(self):
        self.assertFalse(office_artifact_requested("Do not generate a Word document; explain the format."))
        self.assertFalse(office_artifact_requested("\u4e0d\u8981\u751f\u6210 Word\u6587\u4ef6"))

    def test_chinese_adjacent_format_and_english_word_boundaries(self):
        self.assertTrue(office_artifact_requested("\u5236\u4f5cWord\u6587\u6863"))
        self.assertTrue(office_artifact_requested("Create an Excel workbook"))
        self.assertFalse(office_artifact_requested("Generate a password"))

    def test_later_affirmative_request_still_matches(self):
        self.assertTrue(positive_term("Do not return code; write code for the exporter.", "code"))
        self.assertTrue(office_artifact_requested("Do not generate Word; create an Excel workbook."))
        self.assertEqual(AgentTaskIntent.CODE, classify_task_intent("Implement the Python code and run tests").intent)

    def test_quoted_keys_and_embedded_words_are_not_code_signals(self):
        self.assertFalse(positive_term('{"\u9879\u76ee": "\u7532"}', "\u9879\u76ee"))
        self.assertFalse(positive_term("decode this image", "code"))
        self.assertTrue(positive_term("fix code", "code"))

    def test_negated_research_does_not_create_a_research_task(self):
        self.assertEqual(AgentTaskKind.CHAT, execution_policy_for("\u4e0d\u8981\u8054\u7f51\uff0c\u8bf4\u4f60\u597d").task_kind)
        self.assertEqual(AgentTaskKind.RESEARCH, execution_policy_for("Do not search now; research the sources instead.").task_kind)

    def test_screen_analysis_remains_read_only(self):
        policy = execution_policy_for("Create a Word document", request_kind="screen_analysis")
        self.assertEqual(AgentTaskKind.CHAT, policy.task_kind)
        self.assertFalse(policy.requires_artifact)

    def test_native_office_file_and_preview_are_not_bundled_as_a_project(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(os.environ, {"GALAXYSSI_WORKSPACE_ROOT": temporary}):
            root = task_workspace("office-unit-fixture", "codex")
            for name in ("report.docx", "preview.png"):
                (root / "outputs" / name).write_bytes(b"synthetic packaging fixture")
            with patch("agent_execution_harness._verify_outputs", return_value={"status": "not_tested"}):
                result = finalize_task_artifacts("office-unit-fixture", "Create a Word document and preview", "codex")
            self.assertFalse(result.packaged)
            self.assertEqual({"report.docx", "preview.png"}, {item["name"] for item in result.output_files})

    def test_explicit_archive_request_and_missing_original_keep_existing_packaging(self):
        artifacts = [{"category": "outputs", "relative_path": "outputs/report.docx"}]
        self.assertTrue(keep_office_outputs_separate("Create a Word document", artifacts))
        self.assertFalse(keep_office_outputs_separate("Create a Word document and ZIP archive", artifacts))
        self.assertFalse(keep_office_outputs_separate("Create a Word document", []))


if __name__ == "__main__":
    unittest.main()
