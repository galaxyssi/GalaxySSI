import unittest
import os
import tempfile
from unittest.mock import patch

from agent_execution_harness import AgentTaskIntent, AgentTaskKind, classify_task_intent, execution_contract, execution_policy_for, finalize_task_artifacts
from artifact_request_policy import keep_office_outputs_separate, office_artifact_requested, pdf_artifact_requested, positive_term
from task_workspace import task_workspace


class ArtifactRequestPolicyTests(unittest.TestCase):
    def test_pdf_export_requires_artifact_delivery_not_research(self):
        prompts = (
            "Generate a downloadable PDF and PNG previews, preserve the editable original.",
            "Convert this document to PDF",
            "Export the current content as PDF",
            "\u57fa\u4e8e\u5f53\u524d\u5185\u5bb9\uff0c\u518d\u751f\u6210\u4e00\u4efd\u53ef\u4e0b\u8f7d\u7684PDF\u53ca\u5176PNG\u9884\u89c8\uff0c\u4fdd\u7559\u539f\u683c\u5f0f\uff0c\u4e0d\u8981\u53ea\u6539\u6587\u4ef6\u6269\u5c55\u540d\u3002",
            "\u8f6c\u6210PDF\u6587\u4ef6",
        )
        for prompt in prompts:
            with self.subTest(prompt=prompt):
                self.assertTrue(pdf_artifact_requested(prompt))
                policy = execution_policy_for(prompt)
                self.assertEqual(AgentTaskKind.ARTIFACT, policy.task_kind)
                self.assertTrue(policy.requires_artifact)
                contract = execution_contract(policy)
                self.assertIn("current native source alongside the export", contract)
                self.assertIn("PDF-only or preview-only", contract)
                self.assertIn("reconcile all requested formats", contract)

    def test_pdf_negation_boundaries_and_read_only_are_preserved(self):
        for prompt in ("Do not generate a PDF", "\u4e0d\u8981\u751f\u6210PDF", "Explain PDF",
                       "Generate pdfkit code", "Create a notpdf report"):
            self.assertFalse(pdf_artifact_requested(prompt), prompt)
        self.assertTrue(pdf_artifact_requested("Do not generate Word; export PDF instead."))
        policy = execution_policy_for("Generate PDF", request_kind="screen_analysis")
        self.assertEqual(AgentTaskKind.CHAT, policy.task_kind)
        self.assertFalse(policy.requires_artifact)
        policy = execution_policy_for("Generate PDF", requested_execution_mode="plan_only")
        self.assertFalse(policy.requires_artifact)

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
