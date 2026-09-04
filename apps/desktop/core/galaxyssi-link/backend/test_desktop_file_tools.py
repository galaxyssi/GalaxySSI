import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from desktop_file_tools import try_execute_explicit_file_task


class DesktopFileToolTests(unittest.TestCase):
    def test_explicit_csv_summary_calculates_revenue_without_model(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "sales.csv"
            source.write_text(
                "product,units,price\nAlpha,3,12.50\nBeta,2,8.00\nGamma,5,4.20\n",
                encoding="utf-8",
            )

            result = try_execute_explicit_file_task(
                "Summarize this CSV and calculate total revenue", [source], root / "outputs"
            )

        self.assertIsNotNone(result)
        self.assertEqual("csv_summary", result.operation)
        self.assertIn("| Alpha | 3 | 12.50 | 37.50 |", result.message)
        self.assertIn("**Total revenue: 74.50**", result.message)
        self.assertIsNone(result.output_path)

    def test_explicit_excel_pdf_conversion_uses_deterministic_tool(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "test.xlsx"
            source.write_bytes(b"xlsx")

            def fake_convert(_source, target, _format):
                target.write_bytes(b"pdf")

            with patch("desktop_file_tools._run_excel_conversion", side_effect=fake_convert):
                result = try_execute_explicit_file_task(
                    "\u4fdd\u5b58\u6210 PDF", [source], root / "outputs"
                )

            self.assertIsNotNone(result)
            self.assertEqual("excel_to_pdf", result.operation)
            self.assertEqual("test.pdf", result.output_path.name)

    def test_ambiguous_file_request_stays_on_model_route(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "test.xlsx"
            source.write_bytes(b"xlsx")
            result = try_execute_explicit_file_task("\u5904\u7406\u4e00\u4e0b", [source], Path(temporary) / "outputs")
        self.assertIsNone(result)

    def test_proactive_attachment_policy_stays_on_model_route(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "phone-test.csv"
            source.write_text("name,value\nAlpha,1\n", encoding="utf-8")
            prompt = (
                "Inspect and understand the attached content first. Infer the user's most likely goal "
                "and directly complete the most helpful relevant action.\n\n"
                "Attached input:\n- phone-test.csv (text/csv, 19 B)\n"
                "Inspect the attached content and use the conversation context."
            )
            result = try_execute_explicit_file_task(prompt, [source], Path(temporary) / "outputs")
        self.assertIsNone(result)

    def test_chinese_proactive_attachment_policy_stays_on_model_route(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "phone-test.csv"
            source.write_text("name,value\nAlpha,1\n", encoding="utf-8")
            prompt = (
                "\u8bf7\u5148\u5b9e\u9645\u8bfb\u53d6\u5e76\u7406\u89e3\u9644\u4ef6\u5185\u5bb9\uff0c"
                "\u63a8\u65ad\u7528\u6237\u6700\u53ef\u80fd\u7684\u76ee\u6807\uff0c"
                "\u7136\u540e\u76f4\u63a5\u5b8c\u6210\u6700\u6709\u5e2e\u52a9\u7684\u76f8\u5173\u5904\u7406\u3002"
            )
            result = try_execute_explicit_file_task(prompt, [source], Path(temporary) / "outputs")
        self.assertIsNone(result)

    def test_multiple_files_stay_on_model_route(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            first = root / "a.xlsx"
            second = root / "b.xlsx"
            first.write_bytes(b"a")
            second.write_bytes(b"b")
            result = try_execute_explicit_file_task("convert to PDF", [first, second], root / "outputs")
        self.assertIsNone(result)

    def test_invalid_excel_returns_actionable_error_without_model_fallback(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "corrupt-test.xlsx"
            source.write_bytes(b"not an xlsx archive")

            result = try_execute_explicit_file_task(
                "Convert this spreadsheet to CSV", [source], root / "outputs"
            )

        self.assertIsNotNone(result)
        self.assertEqual("excel_conversion_failed", result.operation)
        self.assertIn("isn't a valid or readable Excel workbook", result.message)
        self.assertIn("try repairing it", result.message)
        self.assertIsNone(result.output_path)


if __name__ == "__main__":
    unittest.main()
