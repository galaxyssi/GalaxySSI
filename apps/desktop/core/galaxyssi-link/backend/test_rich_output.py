import base64
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from rich_output import MAX_INLINE_ARTIFACT_BYTES, MAX_TOTAL_INLINE_ARTIFACT_B64, build_rich_output


class RichOutputTests(unittest.TestCase):
    def test_extracts_explicit_blocks_and_keeps_fallback(self):
        content = """Summary

```galaxyssi-rich
{"blocks":[{"id":"t1","type":"table","columns":["A"],"rows":[["B"]]}]}
```"""
        fallback, document = build_rich_output(content)
        self.assertEqual(fallback, "Summary")
        self.assertEqual(document["version"], 1)
        self.assertEqual([item["type"] for item in document["blocks"]], ["text", "table"])
        self.assertEqual(document["blocks"][0]["text"], "Summary")

    def test_converts_artifacts_to_media_blocks(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ, {"GALAXYSSI_WORKSPACE_ROOT": temporary}
        ):
            output = Path(temporary) / "tasks" / "task-1" / "outputs" / "preview.png"
            output.parent.mkdir(parents=True)
            output.write_bytes(b"not-a-real-image")
            fallback, document = build_rich_output(
                "Created the requested output.",
                [{"name": "preview.png", "relative_path": "outputs/preview.png", "size": 12}],
                "task-1",
            )
        self.assertEqual(fallback, "Created the requested output.")
        self.assertEqual(document["blocks"][0]["type"], "text")
        self.assertEqual(document["blocks"][1]["type"], "image")
        self.assertTrue(document["blocks"][1]["uri"].startswith("galaxyssi-artifact://"))

    def test_does_not_return_conversation_context_as_output(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ, {"GALAXYSSI_WORKSPACE_ROOT": temporary}
        ):
            task = Path(temporary) / "tasks" / "task-context"
            context = task / "downloads" / "context" / "original.png"
            output = task / "outputs" / "edited.png"
            context.parent.mkdir(parents=True)
            output.parent.mkdir(parents=True)
            context.write_bytes(b"original")
            output.write_bytes(b"edited")
            _, document = build_rich_output(
                "Created the edited image.",
                [
                    {
                        "name": context.name,
                        "relative_path": "downloads/context/original.png",
                        "size": context.stat().st_size,
                    },
                    {
                        "name": output.name,
                        "relative_path": "outputs/edited.png",
                        "size": output.stat().st_size,
                    },
                ],
                "task-context",
            )

        self.assertEqual(2, len(document["blocks"]))
        self.assertEqual("Created the edited image.", document["blocks"][0]["text"])
        self.assertEqual("edited.png", document["blocks"][1]["title"])

    def test_preserves_self_contained_html_animation(self):
        fallback, document = build_rich_output(
            """```galaxyssi-rich
{"blocks":[{"id":"anim","type":"html","text":"<div class='dot'></div>","fallback_text":"Animated result"}]}
```"""
        )
        self.assertEqual(document["blocks"][0]["type"], "html")
        self.assertEqual(document["blocks"][0]["fallback_text"], "Animated result")

    def test_preserves_https_webpage_preview(self):
        fallback, document = build_rich_output(
            '''```galaxyssi-rich
{"blocks":[{"id":"page","type":"webpage","title":"Result","uri":"https://example.com"}]}
```'''
        )
        self.assertEqual(document["blocks"][0]["type"], "webpage")
        self.assertEqual(document["blocks"][0]["uri"], "https://example.com")

    def test_corrects_mislabelled_webpage_gif_to_image(self):
        fallback, document = build_rich_output(
            '''```galaxyssi-rich
{"blocks":[{"type":"webpage","uri":"https://cdn.example.com/character.gif"}]}
```'''
        )
        self.assertEqual(document["blocks"][0]["type"], "image")
        self.assertEqual(fallback, "https://cdn.example.com/character.gif")

    def test_preserves_structured_document_blocks_and_metadata(self):
        fallback, document = build_rich_output(
            '''```galaxyssi-rich
{"blocks":[
  {"type":"list","rows":[["checked","Build"],["unchecked","Verify"]],"metadata":{"style":"checklist"}},
  {"type":"chart","columns":["Run","ms"],"rows":[["1","120"]]},
  {"type":"notice","title":"Ready","text":"Result available","metadata":{"style":"success"}}
]}
```'''
        )
        self.assertEqual(["list", "chart", "notice"], [item["type"] for item in document["blocks"]])
        self.assertEqual("checklist", document["blocks"][0]["metadata"]["style"])
        self.assertEqual([["1", "120"]], document["blocks"][1]["rows"])

    def test_artifact_includes_human_readable_metadata(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ, {"GALAXYSSI_WORKSPACE_ROOT": temporary}
        ):
            output = Path(temporary) / "tasks" / "task-2" / "outputs" / "report.pdf"
            output.parent.mkdir(parents=True)
            output.write_bytes(b"x" * 2048)
            _, document = build_rich_output(
                "Created output.",
                [{"name": "report.pdf", "relative_path": "outputs/report.pdf", "size": 2048}],
                "task-2",
            )
        self.assertEqual("2.0 KB", document["blocks"][1]["metadata"]["size"])

    def test_phone_handoff_uses_apk_mime_without_inline_payload(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ, {"GALAXYSSI_WORKSPACE_ROOT": temporary}
        ):
            output = Path(temporary) / "tasks" / "apk-output" / "outputs" / "SnakeGame.apk"
            output.parent.mkdir(parents=True)
            output.write_bytes(b"apk")
            _, document = build_rich_output(
                "Built the app.",
                [{"name": output.name, "relative_path": "outputs/SnakeGame.apk", "size": 3}],
                "apk-output",
                inline_artifacts=False,
            )

        block = document["blocks"][1]
        self.assertEqual("application/vnd.android.package-archive", block["mime_type"])
        self.assertEqual("encrypted-fragmented", block["metadata"]["transport"])
        self.assertNotIn("data_b64", block)

    def test_small_image_artifact_is_embedded_for_encrypted_phone_delivery(self):
        png = base64.b64decode(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ, {"GALAXYSSI_WORKSPACE_ROOT": temporary}
        ):
            output = Path(temporary) / "tasks" / "task-inline" / "outputs" / "marked.png"
            output.parent.mkdir(parents=True)
            output.write_bytes(png)
            _, document = build_rich_output(
                "Created output.",
                [{"name": output.name, "relative_path": "outputs/marked.png", "size": len(png)}],
                "task-inline",
            )

        block = document["blocks"][1]
        self.assertEqual(base64.b64encode(png).decode("ascii"), block["data_b64"])
        self.assertEqual("encrypted-inline", block["metadata"]["transport"])
        self.assertEqual(str(len(png)), block["metadata"]["size_bytes"])
        self.assertEqual(str(len(png)), block["metadata"]["original_size_bytes"])

    def test_large_image_is_compressed_below_one_hundred_kilobytes_without_modifying_source(self):
        from PIL import Image

        width, height = 1200, 1920
        pixels = bytearray(width * height * 3)
        state = 0x13579BDF
        for index in range(0, len(pixels), 3):
            state = (state * 1103515245 + 12345) & 0xFFFFFFFF
            pixels[index:index + 3] = bytes((state & 0xFF, (state >> 8) & 0xFF, (state >> 16) & 0xFF))

        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ, {"GALAXYSSI_WORKSPACE_ROOT": temporary}
        ):
            output = Path(temporary) / "tasks" / "task-large" / "outputs" / "marked.png"
            output.parent.mkdir(parents=True)
            Image.frombytes("RGB", (width, height), bytes(pixels)).save(output, format="PNG")
            original = output.read_bytes()
            _, document = build_rich_output(
                "Created output.",
                [{"name": output.name, "relative_path": "outputs/marked.png", "size": output.stat().st_size}],
                "task-large",
            )
            self.assertEqual(original, output.read_bytes())

        block = document["blocks"][1]
        transported = base64.b64decode(block["data_b64"], validate=True)
        self.assertLessEqual(len(transported), MAX_INLINE_ARTIFACT_BYTES)
        self.assertEqual("image/jpeg", block["mime_type"])
        self.assertEqual(str(len(transported)), block["metadata"]["size_bytes"])
        self.assertEqual(str(len(original)), block["metadata"]["original_size_bytes"])
        self.assertEqual(f"outputs · {block['metadata']['size']}", block["text"])
        self.assertNotEqual(block["metadata"]["sha256"], block["metadata"]["original_sha256"])

    def test_oversized_explicit_inline_image_is_not_truncated_into_invalid_base64(self):
        encoded = base64.b64encode(b"x" * (MAX_INLINE_ARTIFACT_BYTES + 1)).decode("ascii")
        _, document = build_rich_output(
            f"""```galaxyssi-rich
{{"blocks":[{{"type":"image","title":"oversized.png","mime_type":"image/png","data_b64":"{encoded}"}}]}}
```"""
        )

        self.assertNotIn("data_b64", document["blocks"][0])

    def test_multiple_images_share_one_bounded_inline_transport_budget(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ, {"GALAXYSSI_WORKSPACE_ROOT": temporary}
        ):
            output = Path(temporary) / "tasks" / "task-gallery" / "outputs"
            output.mkdir(parents=True)
            first = output / "first.png"
            second = output / "second.png"
            first.write_bytes(b"a" * 80_000)
            second.write_bytes(b"b" * 80_000)
            _, document = build_rich_output(
                "Created two images.",
                [
                    {"name": first.name, "relative_path": "outputs/first.png", "size": first.stat().st_size},
                    {"name": second.name, "relative_path": "outputs/second.png", "size": second.stat().st_size},
                ],
                "task-gallery",
            )

        encoded = [
            str(block.get("data_b64") or "")
            for block in document["blocks"]
            if block["type"] in {"image", "file", "video", "audio"}
        ]
        self.assertLessEqual(sum(map(len, encoded)), MAX_TOTAL_INLINE_ARTIFACT_B64)
        self.assertEqual(1, sum(bool(value) for value in encoded))

    def test_hydrates_relative_image_and_deduplicates_auto_discovery(self):
        png = base64.b64decode(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )
        content = """Done.

```galaxyssi-rich
{"blocks":[{"type":"file","title":"\u4f5c\u4e1a\u6279\u6539_\u5168\u5bf9.jpg","uri":"outputs/\u4f5c\u4e1a\u6279\u6539_\u5168\u5bf9.jpg"}]}
```"""
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ, {"GALAXYSSI_WORKSPACE_ROOT": temporary}
        ):
            output = Path(temporary) / "tasks" / "current" / "outputs" / "\u4f5c\u4e1a\u6279\u6539_\u5168\u5bf9.jpg"
            output.parent.mkdir(parents=True)
            output.write_bytes(png)
            fallback, document = build_rich_output(
                content,
                [{
                    "name": output.name,
                    "relative_path": "outputs/\u4f5c\u4e1a\u6279\u6539_\u5168\u5bf9.jpg",
                    "size": len(png),
                }],
                "current",
            )

        self.assertEqual("Done.", fallback)
        self.assertEqual(2, len(document["blocks"]))
        self.assertEqual("Done.", document["blocks"][0]["text"])
        block = document["blocks"][1]
        self.assertEqual("image", block["type"])
        self.assertEqual("image/jpeg", block["mime_type"])
        self.assertEqual(base64.b64encode(png).decode("ascii"), block["data_b64"])
        self.assertRegex(block["metadata"]["sha256"], r"^[0-9a-f]{64}$")

    def test_keeps_failure_explanation_and_removes_duplicate_sandbox_artifact_link(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            os.environ, {"GALAXYSSI_WORKSPACE_ROOT": temporary}
        ):
            output = Path(temporary) / "tasks" / "snake" / "outputs" / "SnakeGame-source.zip"
            output.parent.mkdir(parents=True)
            output.write_bytes(b"source")
            fallback, document = build_rich_output(
                "Source is ready.\n\n"
                "[Download source](sandbox:/outputs/SnakeGame-source.zip)\n\n"
                "APK was not generated because the build environment is unavailable.",
                [{
                    "name": output.name,
                    "relative_path": "outputs/SnakeGame-source.zip",
                    "size": output.stat().st_size,
                }],
                "snake",
            )

        self.assertNotIn("sandbox:", fallback)
        self.assertIn("APK was not generated", fallback)
        self.assertEqual(["text", "file"], [item["type"] for item in document["blocks"]])
        self.assertEqual(fallback, document["blocks"][0]["text"])

    def test_drops_unresolvable_relative_card_without_exposing_protocol(self):
        fallback, document = build_rich_output(
            """```galaxyssi-rich
{"blocks":[{"type":"file","title":"missing.jpg","uri":"outputs/missing.jpg"}]}
```""",
            task_id="missing-task",
        )
        self.assertEqual("The generated file is unavailable. Please try again.", fallback)
        self.assertIsNone(document)


if __name__ == "__main__":
    unittest.main()
