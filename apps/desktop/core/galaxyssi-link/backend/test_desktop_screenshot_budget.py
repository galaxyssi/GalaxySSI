"""Remote display compression must not change other image transport budgets."""

import base64
from io import BytesIO
from random import Random
import unittest
from unittest.mock import patch

from PIL import Image, ImageDraw

from desktop_control import DesktopControlError, MAX_SCREENSHOT_BYTES, capture_desktop_screenshot
from desktop_screenshot_encoding import encode_desktop_screenshot
from image_transport import MAX_IMAGE_TRANSPORT_BYTES


class DesktopScreenshotBudgetTest(unittest.TestCase):
    def test_remote_budget_is_independent_of_agent_images(self):
        self.assertEqual(100_000, MAX_SCREENSHOT_BYTES)
        self.assertEqual(100_000, MAX_IMAGE_TRANSPORT_BYTES)

    def test_capture_keeps_valid_jpeg_and_original_coordinates_within_budget(self):
        plain = Image.new("RGB", (1280, 720), "white")
        gradient = Image.linear_gradient("L").resize((1920, 1080)).convert("RGB")
        for name, source in (("plain", plain), ("gradient", gradient)):
            try:
                with self.subTest(name=name), patch("desktop_control.os.name", "nt"), \
                        patch("PIL.ImageGrab.grab", return_value=source):
                    result = capture_desktop_screenshot()
                    data = base64.b64decode(result["image_base64"], validate=True)
                    self.assertGreater(len(data), 0)
                    self.assertLessEqual(len(data), 100_000)
                    self.assertEqual(len(data), result["bytes"])
                    self.assertEqual(source.size, (result["original_width"],
                                                   result["original_height"]))
                    with Image.open(BytesIO(data)) as decoded:
                        decoded.load()
                        self.assertEqual("JPEG", decoded.format)
                        self.assertEqual(decoded.size, (result["width"], result["height"]))
            finally:
                source.close()

    def test_one_fixed_encode_without_mutating_source_or_upscaling(self):
        source = Image.new("RGB", (200, 100), "white")
        try:
            with patch.object(Image.Image, "save", autospec=True, side_effect=Image.Image.save) as save:
                result = encode_desktop_screenshot(source)
            save.assert_called_once()
            self.assertEqual(70, save.call_args.kwargs["quality"])
            self.assertFalse(save.call_args.kwargs["optimize"])
            self.assertFalse(save.call_args.kwargs["progressive"])
            self.assertGreater(len(result.data), 0)
            self.assertEqual((200, 100), (result.width, result.height))
            self.assertEqual((255, 255, 255), source.getpixel((0, 0)))
        finally:
            source.close()

    def test_landscape_frame_preserves_720p_detail(self):
        with Image.new("RGB", (3840, 2160), "white") as source:
            result = encode_desktop_screenshot(source)
            self.assertEqual((1280, 720), (result.width, result.height))

    def test_portrait_frame_keeps_aspect_ratio(self):
        with Image.new("RGB", (1080, 1920), "white") as source:
            result = encode_desktop_screenshot(source)
            self.assertEqual((720, 1280), (result.width, result.height))

    def test_over_budget_frame_is_not_reencoded_or_transmitted(self):
        def oversized_save(image, output, **options):
            output.write(b"x" * 100_001)

        with Image.new("RGB", (1280, 720), "white") as source, \
                patch("desktop_control.os.name", "nt"), \
                patch("PIL.ImageGrab.grab", return_value=source), \
                patch.object(Image.Image, "save", autospec=True, side_effect=oversized_save) as save:
            with self.assertRaises(DesktopControlError) as raised:
                capture_desktop_screenshot()
            self.assertEqual("screenshot_too_large", raised.exception.code)
            save.assert_called_once()

    def test_high_entropy_frame_also_respects_budget_and_single_encode(self):
        with Image.frombytes("L", (1280, 720), Random(0).randbytes(1280 * 720)) as source, \
                patch.object(Image.Image, "save", autospec=True, side_effect=Image.Image.save) as save:
            self.assertIsNone(encode_desktop_screenshot(source))
            save.assert_called_once()

    def test_dense_4k_text_is_explicitly_rejected_when_720p_exceeds_budget(self):
        with Image.new("RGB", (3840, 2160), "white") as source:
            draw = ImageDraw.Draw(source)
            for y in range(0, source.height, 24):
                draw.text((20, y), "Remote display text and controls 0123456789 " * 15,
                          fill="black")
            with patch("desktop_control.os.name", "nt"), \
                    patch("PIL.ImageGrab.grab", return_value=source), \
                    patch.object(Image.Image, "save", autospec=True, side_effect=Image.Image.save) as save:
                with self.assertRaises(DesktopControlError) as raised:
                    capture_desktop_screenshot()
                self.assertEqual("screenshot_too_large", raised.exception.code)
                save.assert_called_once()


if __name__ == "__main__":
    unittest.main()
