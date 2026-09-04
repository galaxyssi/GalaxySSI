from __future__ import annotations

import base64
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import desktop_native_tools
from desktop_perception import (
    CONTRACT_VERSION,
    DesktopPerceptionError,
    DesktopPerceptionService,
)


def screenshot() -> dict:
    encoded = base64.b64encode(b"\xff\xd8\xff\xd9").decode("ascii")
    return {
        "image_mime": "image/jpeg",
        "image_base64": encoded,
        "bytes": 4,
        "width": 480,
        "height": 270,
        "original_width": 1920,
        "original_height": 1080,
        "captured_at": 1_800_000_000_000,
    }


def ui_tree(max_elements: int, max_depth: int) -> dict:
    return {
        "engine": "test-ui-tree",
        "active_window": {
            "title": "GalaxySSI",
            "class_name": "Chrome_WidgetWin_1",
            "process_id": 42,
        },
        "elements": [{
            "id": "root.1",
            "parent_id": "",
            "depth": min(1, max_depth),
            "name": "Send",
            "control_type": "Button",
            "bounds": {"left": 10, "top": 20, "width": 80, "height": 40},
            "enabled": True,
            "actions": ["invoke"],
        }][:max_elements],
        "element_count": 1,
        "truncated": False,
    }


def ocr(image_bytes: bytes, max_chars: int) -> dict:
    assert image_bytes == b"\xff\xd8\xff\xd9"
    text = "Visible screen text"[:max_chars]
    return {
        "engine": "test-ocr",
        "language": "en-US",
        "text": text,
        "lines": [text],
        "character_count": len(text),
        "line_count": 1,
        "truncated": False,
    }


class DesktopPerceptionTests(unittest.TestCase):
    def test_fuses_screenshot_ocr_and_ui_tree_as_untrusted_evidence(self) -> None:
        service = DesktopPerceptionService(
            screenshot,
            ui_tree_provider=ui_tree,
            ocr_provider=ocr,
            now=lambda: 1_800_000_000.0,
        )

        result = service.capture()

        self.assertEqual(CONTRACT_VERSION, result["contract_version"])
        self.assertEqual(["ui_tree", "ocr", "screenshot"], result["available_layers"])
        self.assertEqual("ui_tree", result["preferred_grounding"])
        self.assertTrue(result["untrusted_evidence"])
        self.assertEqual("GalaxySSI", result["active_window"]["title"])
        self.assertEqual(1, result["ui_tree"]["element_count"])
        self.assertEqual("Visible screen text", result["ocr"]["text"])
        self.assertEqual(4, result["screenshot"]["bytes"])

    def test_layer_failure_degrades_without_losing_available_evidence(self) -> None:
        def failed_ocr(_image: bytes, _maximum: int) -> dict:
            raise DesktopPerceptionError("ocr_unavailable", "OCR is unavailable")

        service = DesktopPerceptionService(
            screenshot,
            ui_tree_provider=ui_tree,
            ocr_provider=failed_ocr,
        )

        result = service.capture()

        self.assertEqual(["ui_tree", "screenshot"], result["available_layers"])
        self.assertEqual("unavailable", result["ocr"]["status"])
        self.assertEqual("ocr_unavailable", result["ocr"]["error"]["code"])

    def test_no_available_layer_returns_a_retryable_failure(self) -> None:
        def fail(*_args, **_kwargs):
            raise DesktopPerceptionError("unavailable", "Layer unavailable")

        service = DesktopPerceptionService(
            fail,
            ui_tree_provider=fail,
            ocr_provider=fail,
        )

        with self.assertRaises(DesktopPerceptionError) as raised:
            service.capture()

        self.assertEqual("desktop_perception_unavailable", raised.exception.code)
        self.assertTrue(raised.exception.retryable)

    def test_native_tool_manifest_and_execution_expose_all_three_layers(self) -> None:
        service = DesktopPerceptionService(
            screenshot,
            ui_tree_provider=ui_tree,
            ocr_provider=ocr,
        )
        with tempfile.TemporaryDirectory() as temporary, patch.object(
            desktop_native_tools,
            "_windows_availability",
            return_value=("available", ""),
        ):
            state_root = Path(temporary) / "state"
            registry = desktop_native_tools.DesktopNativeToolRegistry(
                state_root,
                Path(temporary) / "workspaces",
                perception_service=service,
            )
            result = registry.invoke(
                desktop_native_tools.PERCEPTION_SNAPSHOT,
                {"include_screenshot": False},
                {
                    "invocation_id": "perception-test",
                    "idempotency_key": "private-capture-1",
                },
            )
            replay = registry.invoke(
                desktop_native_tools.PERCEPTION_SNAPSHOT,
                {"include_screenshot": False},
                {
                    "invocation_id": "perception-replay",
                    "idempotency_key": "private-capture-1",
                },
            )
            durable_receipts = state_root / "desktop-native-tool-receipts.json"
            durable_text = (
                durable_receipts.read_text(encoding="utf-8")
                if durable_receipts.exists()
                else ""
            )

        self.assertEqual("succeeded", result["status"])
        self.assertTrue(replay["receipt"]["replayed"])
        self.assertNotIn("Visible screen text", durable_text)
        self.assertNotIn("GalaxySSI", durable_text)
        self.assertNotIn("screenshot", result["output"])
        self.assertEqual(
            ["ui_tree", "ocr", "screenshot"],
            result["output"]["available_layers"],
        )
        manifest = {
            item["id"]: item
            for item in registry.manifest()["tools"]
        }
        self.assertIn(desktop_native_tools.PERCEPTION_SNAPSHOT, manifest)
        self.assertEqual(
            [
                "desktop.perception.screenshot",
                "desktop.perception.ocr",
                "desktop.perception.ui_tree",
            ],
            manifest[desktop_native_tools.PERCEPTION_SNAPSHOT]["capabilities"],
        )


if __name__ == "__main__":
    unittest.main()
