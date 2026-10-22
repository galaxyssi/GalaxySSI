import ctypes
import unittest

import test_desktop_control as fixtures
from desktop_control import CLICK_XY, TYPE_TEXT, HOTKEY, SCROLL, SCREENSHOT, DesktopControlError
from desktop_input_focus import focus_for_surface
from desktop_unicode_input import Input, unicode_events


class DesktopDirectInputTests(unittest.TestCase):
    setUp = fixtures.DesktopControlTests.setUp
    tearDown = fixtures.DesktopControlTests.tearDown
    authorize = fixtures.DesktopControlTests.authorize
    request = fixtures.DesktopControlTests.request

    def execute(self, tool, arguments, focus=None):
        self.manager._input_focus = lambda: focus or {
            "available": True, "editable": True, "password": False, "target_id": "field-1",
            "bounds": {"left": 10, "top": 20, "width": 100, "height": 30},
        }
        return self.manager.execute_request(self.request(self.authorize(), tool, {
            **arguments, "interactive_input": True,
        }), self.client)

    def test_double_click_has_two_left_clicks_and_no_screenshot(self):
        result = self.execute(CLICK_XY, {"x": 10, "y": 20, "clicks": 2})
        self.assertEqual("succeeded", result["status"])
        self.assertEqual([("click", 10, 20, "left")] * 2, self.input.calls)
        self.assertEqual(0, self.screenshot_calls)
        self.assertTrue(result["output"]["input_focus"]["editable"])
        self.assertTrue(self.identity.verify(result))

    def test_long_press_is_exactly_one_right_click(self):
        self.execute(CLICK_XY, {"x": 10, "y": 20, "button": "right"})
        self.assertEqual([("click", 10, 20, "right")], self.input.calls)

    def test_changed_focus_does_not_receive_text(self):
        result = self.execute(TYPE_TEXT, {"text": "private", "input_target_id": "old-field"})
        self.assertEqual("failed", result["status"])
        self.assertEqual("input_focus_changed", result["error"]["code"])
        self.assertEqual([], self.input.calls)

    def test_read_only_focus_does_not_receive_text(self):
        result = self.execute(TYPE_TEXT, {"text": "private", "input_target_id": "field-1"},
                              {"available": True, "editable": False, "target_id": "field-1"})
        self.assertEqual("failed", result["status"])
        self.assertEqual([], self.input.calls)

    def test_spaces_and_chinese_are_preserved_without_returning_them(self):
        result = self.execute(TYPE_TEXT, {"text": " \u4e2d\u6587\n ", "input_target_id": "field-1"})
        self.assertEqual("succeeded", result["status"])
        self.assertEqual([("type", " \u4e2d\u6587\n ")], self.input.calls)
        self.assertNotIn("text", result["output"])
        self.assertEqual(0, self.screenshot_calls)

    def test_manual_keyboard_works_without_accessibility_focus(self):
        result = self.execute(TYPE_TEXT, {"text": "hello"}, {"available": False, "editable": False})
        self.assertEqual("succeeded", result["status"])
        self.assertFalse(result["output"]["input_focus"]["editable"])

    def test_hotkey_and_scroll_are_compact(self):
        self.execute(HOTKEY, {"keys": ["enter"]})
        self.execute(SCROLL, {"delta": -120})
        self.assertEqual([("hotkey", ["enter"]), ("scroll", -120)], self.input.calls)
        self.assertEqual(0, self.screenshot_calls)

    def test_interactive_duplicate_is_not_reexecuted(self):
        self.manager._input_focus = lambda: {"available": False, "editable": False}
        request = self.request(self.authorize(), TYPE_TEXT, {"text": "once", "interactive_input": True})
        events = []
        self.manager.execute_request(request, self.client, on_running=events.append)
        replay = self.manager.execute_request(request, self.client)
        self.assertTrue(replay["replayed"])
        self.assertEqual([("type", "once")], self.input.calls)
        self.assertEqual([], events)

    def test_legacy_click_still_captures(self):
        self.manager.execute_request(self.request(self.authorize(), CLICK_XY, {"x": 10, "y": 20}), self.client)
        self.assertEqual(1, self.screenshot_calls)

    def test_interactive_screenshot_is_rejected(self):
        with self.assertRaises(DesktopControlError):
            self.execute(SCREENSHOT, {})

    def test_invalid_click_counts_do_not_execute(self):
        for options in ({"clicks": 3}, {"clicks": 0}, {"clicks": 2, "button": "right"}):
            with self.subTest(options=options):
                result = self.execute(CLICK_XY, {"x": 10, "y": 20, **options})
                self.assertEqual("failed", result["status"])
        self.assertEqual([], self.input.calls)


class DesktopInputMetadataTests(unittest.TestCase):
    def test_secondary_display_coordinates_and_outside_focus(self):
        surface = {"left": -1280, "top": 40, "width": 1280, "height": 1024}
        field = {"editable": True, "bounds": {"left": -1200, "top": 100, "width": 200, "height": 40}}
        result = focus_for_surface(field, surface)
        self.assertEqual(80, result["bounds"]["left"])
        self.assertEqual(60, result["bounds"]["top"])
        self.assertTrue(result["editable"])
        self.assertFalse(focus_for_surface(field, {"width": 1920, "height": 1080})["editable"])
        self.assertEqual(-1200, field["bounds"]["left"])

    def test_input_union_size_and_unicode_surrogates(self):
        self.assertEqual(40 if ctypes.sizeof(ctypes.c_void_p) == 8 else 28, ctypes.sizeof(Input))
        events = unicode_events("\u4e2d\U0001f600")
        self.assertEqual(6, len(events))
        self.assertEqual([0x4e2d, 0x4e2d, 0xd83d, 0xd83d, 0xde00, 0xde00], [e.ki.scan for e in events])
        self.assertEqual([4, 6] * 3, [e.ki.flags for e in events])


if __name__ == "__main__":
    unittest.main()
