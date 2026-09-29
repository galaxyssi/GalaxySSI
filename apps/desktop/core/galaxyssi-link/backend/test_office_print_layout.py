import hashlib
import json
import os
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch
from xml.sax.saxutils import escape

from office_print_layout import inspect_print_layout, _S, _R, _D, _P


class OfficePrintLayoutTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.source = Path(self.temp.name) / "source.xlsx"

    def fixture(self, area="'Sheet'!$A$1:$D$31", end_col=4, offset=342900,
                end_row=30, row_offset=95250, start_col=0, start_row=14,
                anchor="twoCellAnchor", sheet="Sheet", hidden=False, extra=None):
        definition = (f'<definedName name="_xlnm.Print_Area" localSheetId="0">{escape(area)}</definedName>'
                      if area is not None else "")
        data = {
            "[Content_Types].xml": "<Types/>",
            "xl/workbook.xml": f'<workbook xmlns="{_S}" xmlns:r="{_R}"><sheets><sheet name="{escape(sheet)}" sheetId="1" r:id="rId1" state="{"hidden" if hidden else "visible"}"/></sheets><definedNames>{definition}</definedNames></workbook>',
            "xl/_rels/workbook.xml.rels": f'<Relationships xmlns="{_P}"><Relationship Id="rId1" Type="{_R}/worksheet" Target="worksheets/sheet1.xml"/></Relationships>',
            "xl/worksheets/sheet1.xml": f'<worksheet xmlns="{_S}" xmlns:r="{_R}"><drawing r:id="rId1"/></worksheet>',
            "xl/worksheets/_rels/sheet1.xml.rels": f'<Relationships xmlns="{_P}"><Relationship Id="rId1" Type="{_R}/drawing" Target="../drawings/drawing1.xml"/></Relationships>',
            "xl/drawings/drawing1.xml": f'<wsDr xmlns="{_D}"><{anchor}><from><col>{start_col}</col><colOff>0</colOff><row>{start_row}</row><rowOff>0</rowOff></from><to><col>{end_col}</col><colOff>{offset}</colOff><row>{end_row}</row><rowOff>{row_offset}</rowOff></to><graphicFrame/></{anchor}></wsDr>',
        }
        data.update(extra or {})
        with zipfile.ZipFile(self.source, "w") as archive:
            for name, value in data.items():
                archive.writestr(name, value)

    def test_observed_right_edge_clip_is_detected_without_changing_source(self):
        self.fixture()
        before = hashlib.sha256(self.source.read_bytes()).hexdigest()
        result = inspect_print_layout(self.source)
        self.assertEqual("issues_found", result["status"])
        self.assertEqual(1, result["checked_drawings"])
        self.assertEqual("drawing_exceeds_print_area", result["issues"][0]["code"])
        self.assertTrue(result["visual_review_required"])
        self.assertEqual(before, hashlib.sha256(self.source.read_bytes()).hexdigest())

    def test_exact_exclusive_edge_is_not_clipped(self):
        self.fixture(offset=0, end_row=31, row_offset=0)
        result = inspect_print_layout(self.source)
        self.assertEqual("no_issue_in_checked_scope", result["status"])
        self.assertEqual(1, result["checked_drawings"])
        self.assertEqual([], result["issues"])

    def test_all_four_edges_are_checked(self):
        for arguments in ({"offset": 1}, {"offset": 0, "end_row": 31, "row_offset": 1},
                          {"area": "'Sheet'!$B$1:$F$40"},
                          {"area": "'Sheet'!$A$16:$F$40"}):
            with self.subTest(arguments=arguments):
                self.fixture(**arguments)
                self.assertEqual("issues_found", inspect_print_layout(self.source)["status"])

    def test_multiple_rectangles_and_quoted_sheet_name(self):
        self.fixture(sheet="Bob's Data", area="'Bob''s Data'!$H$1:$J$3,'Bob''s Data'!$A$1:$F$40")
        self.assertEqual("no_issue_in_checked_scope", inspect_print_layout(self.source)["status"])

    def test_disjoint_ranges_do_not_form_a_false_containing_rectangle(self):
        self.fixture(area="'Sheet'!$A$1:$B$40,'Sheet'!$D$1:$F$40")
        self.assertEqual("issues_found", inspect_print_layout(self.source)["status"])

    def test_missing_dynamic_and_full_column_areas_are_not_approved(self):
        for area in (None, "OFFSET(Sheet!$A$1,0,0,20,4)", "'Sheet'!$A:$D"):
            with self.subTest(area=area):
                self.fixture(area=area)
                result = inspect_print_layout(self.source)
                self.assertEqual("partial", result["status"])
                self.assertTrue(result["unverified"])

    def test_hidden_sheets_and_unsupported_anchor_kinds(self):
        self.fixture(hidden=True)
        self.assertEqual(0, inspect_print_layout(self.source)["checked_drawings"])
        for anchor in ("oneCellAnchor", "absoluteAnchor"):
            self.fixture(anchor=anchor)
            result = inspect_print_layout(self.source)
            self.assertEqual("partial", result["status"])
            self.assertIn("unsupported_drawing_anchor", result["unverified"])

    def test_non_printing_drawing_is_not_reported_as_clipped(self):
        drawing = f'<wsDr xmlns="{_D}"><twoCellAnchor><clientData fPrintsWithSheet="0"/></twoCellAnchor></wsDr>'
        self.fixture(extra={"xl/drawings/drawing1.xml": drawing})
        result = inspect_print_layout(self.source)
        self.assertEqual(0, result["checked_drawings"])
        self.assertEqual([], result["issues"])

    def test_invalid_or_unsafe_xml_is_unverified_not_a_layout_pass(self):
        for data in ("<bad", '<!DOCTYPE a [<!ENTITY x "bad">]><a/>', "x" * (4 * 1024 * 1024 + 1)):
            self.fixture(extra={"xl/drawings/drawing1.xml": data})
            self.assertEqual("partial", inspect_print_layout(self.source)["status"])

    def test_invalid_relationship_and_inverted_marker_are_unverified(self):
        for target in ("../../../../outside.xml", "https://example.invalid/a", "%2e%2e/a.xml"):
            self.fixture(extra={"xl/worksheets/_rels/sheet1.xml.rels": f'<Relationships xmlns="{_P}"><Relationship Id="rId1" Type="{_R}/drawing" Target="{target}"/></Relationships>'})
            self.assertEqual("partial", inspect_print_layout(self.source)["status"])
        self.fixture(end_col=0, offset=0)
        self.assertEqual("partial", inspect_print_layout(self.source)["status"])

    def test_other_office_formats_are_not_claimed_checked(self):
        result = inspect_print_layout(Path("report.docx"))
        self.assertEqual("not_applicable", result["status"])
        self.assertTrue(result["visual_review_required"])

    def test_preview_returns_diagnostic_with_unchanged_native_file(self):
        import office_preview as preview
        from task_workspace import task_workspace
        from test_office_preview import OfficePreviewTests
        with patch.dict(os.environ, {"GALAXYSSI_WORKSPACE_ROOT": self.temp.name}):
            root = task_workspace("layout-preview")
            self.source = root / "outputs" / "source.xlsx"
            self.fixture()
            original = self.source.read_bytes()
            with patch.object(preview.shutil, "which", side_effect=lambda name: name), \
                 patch.object(preview, "_convert", OfficePreviewTests.fake_convert), \
                 patch.object(preview.subprocess, "run", OfficePreviewTests.fake_run):
                response = preview.execute({"path": str(self.source)}, "layout-preview")
            result = json.loads(response["contentItems"][0]["text"])
            self.assertTrue(response["success"])
            self.assertEqual("issues_found", result["layout_check"]["status"])
            self.assertEqual(original, self.source.read_bytes())
            self.assertTrue(result["original_included"])
            self.assertFalse(result["complete_preview"])


if __name__ == "__main__":
    unittest.main()
