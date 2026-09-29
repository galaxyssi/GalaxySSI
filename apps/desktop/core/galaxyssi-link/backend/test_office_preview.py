import json
import os
import tempfile
import unittest
import zipfile
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import office_preview as preview
from task_workspace import task_workspace


class OfficePreviewTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.env = patch.dict(os.environ, {"GALAXYSSI_WORKSPACE_ROOT": self.temporary.name})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.addCleanup(self.temporary.cleanup)
        self.root = task_workspace("preview-test")
        self.source = self.root / "outputs" / "report.docx"
        self.office(self.source)

    def office(self, path, extra=None):
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("[Content_Types].xml", "<Types/>")
            archive.writestr("word/document.xml", "<document/>")
            for name, value in (extra or {}).items():
                archive.writestr(name, value)

    def test_rejects_external_paths_and_unsupported_formats(self):
        outside = Path(self.temporary.name) / "outside.docx"
        self.office(outside)
        with self.assertRaises(ValueError):
            preview._validated_source(self.root, str(outside))
        with self.assertRaises(ValueError):
            preview._validated_source(self.root, str(self.root))

    def test_rejects_macros_connections_and_external_resources(self):
        for extra in ({"word/vbaProject.bin": b"macro"}, {"xl/connections.xml": "<connections/>"},
                      {"word/_rels/document.xml.rels": '<Relationships><Relationship TargetMode="External" Type="image" Target="http://example.invalid/a"/></Relationships>'},
                      {"word/_rels/document.xml.rels": '<!DOCTYPE Relationships><Relationships/>'}):
            with self.subTest(extra=list(extra)):
                self.office(self.source, extra)
                with self.assertRaises(ValueError):
                    preview._validated_source(self.root, str(self.source))

    def test_plain_hyperlinks_are_not_external_media_loads(self):
        self.office(self.source, {"word/_rels/document.xml.rels": '<Relationships><Relationship TargetMode="External" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="https://example.invalid"/></Relationships>'})
        self.assertEqual(self.source.resolve(), preview._validated_source(self.root, str(self.source)))

    def test_rejects_case_ambiguous_container_entries(self):
        self.office(self.source, {"WORD/DOCUMENT.XML": "<other/>"})
        with self.assertRaisesRegex(ValueError, "duplicate"):
            preview._validated_source(self.root, str(self.source))

    def test_revalidates_copied_container_before_conversion(self):
        original_digest = preview._digest

        def mutate_before_hash(path):
            if path == self.source:
                self.office(self.source, {"word/vbaProject.bin": b"macro"})
            return original_digest(path)

        with patch.object(preview.shutil, "which", return_value="renderer"), \
             patch.object(preview, "_digest", side_effect=mutate_before_hash), \
             patch.object(preview, "_convert") as convert, self.assertRaises(ValueError):
            preview.render("preview-test", str(self.source))
        convert.assert_not_called()

    def test_validates_page_limit_before_running_any_converter(self):
        for limit in (True, 0, 21, "4"):
            with self.subTest(limit=limit), self.assertRaises(ValueError):
                preview.render("preview-test", str(self.source), limit)

    @staticmethod
    def fake_convert(source, pdf, scratch):
        pdf.write_bytes(b"%PDF-1.4\nfixture")
        return "fixture_renderer"

    @staticmethod
    def fake_run(args, **kwargs):
        if args[0] == "pdfinfo":
            return SimpleNamespace(returncode=0, stdout="Pages: 3\n")
        Path(str(args[-1]) + "-1.png").write_bytes(b"\x89PNG\r\n\x1a\nfixture")
        return SimpleNamespace(returncode=0, stdout="")

    def test_publishes_atomic_original_bound_preview_with_honest_coverage(self):
        before = self.source.read_bytes()
        with patch.object(preview.shutil, "which", side_effect=lambda name: name), \
             patch.object(preview, "_convert", self.fake_convert), \
             patch.object(preview.subprocess, "run", self.fake_run):
            result = preview.render("preview-test", str(self.source), 1)
        self.assertEqual("rendered", result["status"])
        self.assertFalse(result["complete_preview"])
        self.assertEqual(3, result["page_count"])
        self.assertEqual(1, result["preview_pages"])
        self.assertEqual(before, self.source.read_bytes())
        self.assertEqual(2, len(result["files"]))
        self.assertTrue(all((self.root / item["path"]).is_file() for item in result["files"]))

    def test_failed_conversion_does_not_publish_or_replace_original(self):
        before = self.source.read_bytes()
        with patch.object(preview.shutil, "which", return_value="renderer"), \
             patch.object(preview, "_convert", side_effect=RuntimeError("fixture conversion failed")):
            result = preview.execute({"path": str(self.source)}, "preview-test")
        self.assertFalse(result["success"])
        self.assertEqual("unavailable", json.loads(result["contentItems"][0]["text"])["status"])
        self.assertEqual(before, self.source.read_bytes())
        self.assertEqual([self.source], list((self.root / "outputs").iterdir()))
        self.assertEqual([], list((self.root / "temp").iterdir()))

    def test_source_change_prevents_stale_preview_publication(self):
        def mutate(args, **kwargs):
            result = self.fake_run(args, **kwargs)
            if args[0] == "pdftoppm":
                self.source.write_bytes(b"changed by another task")
            return result
        with patch.object(preview.shutil, "which", side_effect=lambda name: name), \
             patch.object(preview, "_convert", self.fake_convert), \
             patch.object(preview.subprocess, "run", mutate), self.assertRaisesRegex(RuntimeError, "Source changed"):
            preview.render("preview-test", str(self.source))
        self.assertEqual([self.source], list((self.root / "outputs").iterdir()))

    def test_busy_worker_returns_retryable_without_conversion(self):
        preview._SLOT.acquire()
        try:
            with patch.object(preview.shutil, "which", return_value="renderer"), patch.object(preview, "_convert") as convert:
                result = preview.render("preview-test", str(self.source))
            self.assertEqual("busy", result["status"])
            self.assertTrue(result["retryable"])
            convert.assert_not_called()
        finally:
            preview._SLOT.release()


if __name__ == "__main__":
    unittest.main()
