import unittest

from desktop_surfaces import DesktopSurfaceError, DesktopSurfaceSessionRegistry


class FakeSurfaceProvider:
    def __init__(self) -> None:
        self.display_rows = [
            {
                "display_id": "display:primary",
                "name": "Display 1",
                "bounds": {"left": 0, "top": 0, "width": 1920, "height": 1080},
                "work_area": {"left": 0, "top": 0, "width": 1920, "height": 1040},
                "primary": True,
            },
            {
                "display_id": "display:left",
                "name": "Display 2",
                "bounds": {"left": -1280, "top": 40, "width": 1280, "height": 1024},
                "work_area": {"left": -1280, "top": 40, "width": 1280, "height": 984},
                "primary": False,
            },
        ]
        self.window_rows = [
            {
                "window_id": "window:editor",
                "title": "Editor",
                "display_id": "display:primary",
                "bounds": {"left": 100, "top": 80, "width": 1200, "height": 800},
                "foreground": True,
                "minimized": False,
            },
            {
                "window_id": "window:browser",
                "title": "Browser",
                "display_id": "display:left",
                "bounds": {"left": -1200, "top": 100, "width": 1000, "height": 760},
                "foreground": False,
                "minimized": False,
            },
        ]
        self.activated: list[str] = []
        self.activation_succeeds = True

    def displays(self):
        return [dict(row) for row in self.display_rows]

    def windows(self, _displays):
        return [dict(row) for row in self.window_rows]

    def activate_window(self, window_id):
        self.activated.append(window_id)
        return self.activation_succeeds


class DesktopSurfaceSessionRegistryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.clock = 1_800_000_000.0
        self.provider = FakeSurfaceProvider()
        self.registry = DesktopSurfaceSessionRegistry(
            self.provider,
            now=lambda: self.clock,
        )

    def test_defaults_to_primary_display(self):
        catalog = self.registry.catalog("session-a")

        self.assertEqual("display:primary", catalog["selection"]["selected_display_id"])
        self.assertEqual("", catalog["selection"]["selected_window_id"])
        self.assertEqual("display", catalog["target"]["kind"])
        self.assertEqual(1920, catalog["target"]["bounds"]["width"])

    def test_sessions_keep_independent_surface_selection(self):
        self.registry.select("session-a", display_id="display:left")
        self.registry.select("session-b", window_id="window:editor")

        first = self.registry.catalog("session-a")
        second = self.registry.catalog("session-b")

        self.assertEqual("display:left", first["selection"]["selected_display_id"])
        self.assertEqual("", first["selection"]["selected_window_id"])
        self.assertEqual("window:editor", second["selection"]["selected_window_id"])
        self.assertEqual("window", second["target"]["kind"])

    def test_selecting_window_also_selects_its_display(self):
        catalog = self.registry.select("session-a", window_id="window:browser")

        self.assertEqual("display:left", catalog["selection"]["selected_display_id"])
        self.assertEqual("window:browser", catalog["selection"]["selected_window_id"])
        self.assertEqual(-1200, catalog["target"]["bounds"]["left"])

    def test_stale_window_falls_back_to_its_display(self):
        self.registry.select("session-a", window_id="window:browser")
        self.provider.window_rows = self.provider.window_rows[:1]

        catalog = self.registry.catalog("session-a")

        self.assertEqual("display:left", catalog["selection"]["selected_display_id"])
        self.assertEqual("", catalog["selection"]["selected_window_id"])
        self.assertEqual("display", catalog["target"]["kind"])

    def test_activate_selects_window_and_reports_failure(self):
        catalog = self.registry.activate_window("session-a", "window:browser")
        self.assertEqual(["window:browser"], self.provider.activated)
        self.assertEqual("window:browser", catalog["selection"]["selected_window_id"])

        self.provider.activation_succeeds = False
        with self.assertRaises(DesktopSurfaceError) as raised:
            self.registry.activate_window("session-a", "window:editor")
        self.assertEqual("window_activation_failed", raised.exception.code)
        self.assertTrue(raised.exception.retryable)

    def test_selection_can_be_exported_and_restored(self):
        self.registry.select("session-a", window_id="window:editor")

        restored = DesktopSurfaceSessionRegistry(
            self.provider,
            sessions=self.registry.export(),
            now=lambda: self.clock,
        )

        self.assertEqual(
            "window:editor",
            restored.catalog("session-a")["selection"]["selected_window_id"],
        )

    def test_persistent_selection_can_follow_a_rotated_session_handle(self):
        self.registry.select("session-old", display_id="display:left")
        self.assertTrue(
            self.registry.mirror("session-old", "authorization:phone-a")
        )
        self.assertTrue(
            self.registry.restore("session-new", "authorization:phone-a")
        )

        self.assertEqual(
            "display:left",
            self.registry.catalog("session-new")["selection"]["selected_display_id"],
        )
        self.assertFalse(
            self.registry.restore("session-new", "authorization:phone-a")
        )

    def test_empty_display_catalog_fails_cleanly(self):
        self.provider.display_rows = []
        with self.assertRaises(DesktopSurfaceError) as raised:
            self.registry.catalog("session-a")
        self.assertEqual("display_not_found", raised.exception.code)


if __name__ == "__main__":
    unittest.main()
