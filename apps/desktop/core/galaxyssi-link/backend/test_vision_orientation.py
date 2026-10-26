import base64
import io
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from PIL import Image
from vision_orientation import CAPTION, HEADER, MAX_BYTES, TILE, reference_sheet, supplementary_input


class OrientationEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "source.png"
        with Image.new("RGB", (400, 200), "white") as source:
            source.paste("red", (0, 0, 200, 100))
            source.paste("blue", (200, 100, 400, 200))
            source.save(self.path)

    def test_actual_clockwise_views_preserve_original_and_fit_budget(self):
        before = self.path.read_bytes()
        encoded = reference_sheet(str(self.path))
        self.assertLessEqual(len(encoded), MAX_BYTES)
        self.assertEqual(before, self.path.read_bytes())
        with Image.open(io.BytesIO(encoded)) as sheet:
            self.assertEqual((1280, 1344), sheet.size)
            # Source is centered without upscaling. Red top-left becomes top-right at 90 degrees.
            for point in ((TILE // 2 - 100, HEADER + TILE // 2 - 50),
                          (TILE + TILE // 2 + 50, HEADER + TILE // 2 - 100),
                          (TILE // 2 + 100, TILE + HEADER * 2 + TILE // 2 + 50),
                          (TILE + TILE // 2 - 50, TILE + HEADER * 2 + TILE // 2 + 100)):
                red, green, blue = sheet.getpixel(point)
                self.assertGreater(red, green + 100)
                self.assertGreater(red, blue + 100)

    def test_reference_is_labeled_not_a_second_user_attachment(self):
        result = supplementary_input([str(self.path)])
        self.assertIn("SAME image", result[0]["text"])
        self.assertIn("NOT additional user photos", CAPTION)
        self.assertEqual("image", result[1]["type"])
        self.assertTrue(base64.b64decode(result[1]["url"].split(",", 1)[1]))

    def test_no_extra_payload_for_text_or_multiple_images(self):
        self.assertEqual([], supplementary_input([]))
        self.assertEqual([], supplementary_input([str(self.path), str(self.path)]))

    def test_corrupt_missing_and_oversized_inputs_keep_original_delivery(self):
        self.assertEqual([], supplementary_input([str(self.path) + ".missing"]))
        self.path.write_bytes(b"not an image")
        self.assertEqual([], supplementary_input([str(self.path)]))
        with patch("vision_orientation.MAX_SOURCE_BYTES", 1):
            self.assertEqual([], supplementary_input([str(self.path)]))

    def test_codex_integration_keeps_source_first(self):
        from codex_app_server import CodexAppServer
        result = CodexAppServer._user_input("Inspect this image", [str(self.path)],
                                           include_task_policy=False, include_response_policy=False)
        self.assertEqual({"type": "localImage", "path": str(self.path), "detail": "original"}, result[1])
        self.assertEqual("image", result[-1]["type"])
        self.assertEqual(1, sum(item["type"] == "localImage" for item in result))

    def test_missing_optional_image_dependency_does_not_block_delivery(self):
        from codex_app_server import CodexAppServer
        with patch.dict("sys.modules", {"vision_orientation": None}):
            plain = CodexAppServer._user_input("Hello", [], include_task_policy=False,
                                              include_response_policy=False)
            image = CodexAppServer._user_input("Inspect", [str(self.path)],
                                              include_task_policy=False, include_response_policy=False)
        self.assertEqual(1, len(plain))
        self.assertEqual(2, len(image))
        self.assertEqual("localImage", image[1]["type"])

    def test_exif_rotation_is_applied_before_reference_angles(self):
        with Image.open(self.path) as source:
            exif = Image.Exif()
            exif[274] = 6
            source.save(self.path, exif=exif)
        with Image.open(io.BytesIO(reference_sheet(str(self.path)))) as sheet:
            r, g, b = sheet.getpixel((TILE // 2 + 50, HEADER + TILE // 2 - 100))
            self.assertGreater(r, b + 100)


if __name__ == "__main__":
    unittest.main()
