import base64
import copy
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from PIL import Image

import agent_vision as vision
from agent_vision_cli import cli_input, final_cli_output
from agent_gateway import _apply_prompt


class NativeEvidenceTest(unittest.TestCase):
    def test_followup_policy_keeps_orientation_internal_and_respects_current_request(self):
        from vision_orientation import CAPTION
        for policy in (vision.VISION_POLICY, CAPTION):
            self.assertIn("historical", policy.lower())
            self.assertIn("internally", policy)
            self.assertIn("not prefix replies", policy)
            self.assertIn("ambiguity", policy)
        self.assertIn("not as new uploads", vision.VISION_POLICY)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source.png"
        with Image.new("RGB", (100, 50), "red") as image:
            image.save(self.source)
        self.paths = [str(self.source)]

    def test_original_bytes_and_order_are_preserved_reference_is_not_a_photo(self):
        original = self.source.read_bytes()
        images = vision.load_images(self.paths)
        self.assertEqual(original, images[0].data)
        self.assertEqual("image/png", images[0].mime_type)
        self.assertIn("SAME image", images[1].label)
        self.assertLessEqual(len(images[1].data), 100_000)
        self.assertEqual(original, self.source.read_bytes())
        multiple = vision.load_images(self.paths * 2)
        self.assertEqual(["Source image 1", "Source image 2"], [image.label for image in multiple])

    def test_text_requires_no_decoder_or_reference_generation(self):
        with patch.dict("sys.modules", {"PIL": None}):
            self.assertEqual([], vision.load_images([]))
            messages = [{"role": "user", "content": "Hello"}]
            self.assertIs(messages, vision.openai_messages(messages, []))

    def test_invalid_missing_oversized_images_fail_before_model(self):
        with self.assertRaisesRegex(vision.VisionInputError, "missing"):
            vision.load_images([str(self.root / "absent.png")])
        with patch.object(vision, "MAX_SOURCE_BYTES", 1):
            with self.assertRaisesRegex(vision.VisionInputError, "oversized"):
                vision.load_images(self.paths)
        self.source.write_bytes(b"bad image")
        with self.assertRaisesRegex(vision.VisionInputError, "could not be decoded"):
            vision.load_images(self.paths)

    def test_task_resolution_never_reads_a_different_task(self):
        inputs = self.root / "downloads" / "input"
        inputs.mkdir(parents=True)
        (inputs / "02-b.png").write_bytes(self.source.read_bytes())
        (inputs / "01-a.png").write_bytes(self.source.read_bytes())
        (inputs / "03-note.txt").write_text("not an image")
        with patch("task_workspace.existing_task_workspace", return_value=self.root) as workspace:
            self.assertEqual(["01-a.png", "02-b.png"], [Path(p).name for p in vision.task_image_paths("turn-2")])
            workspace.assert_called_once_with("turn-2")
        self.assertEqual([], vision.task_image_paths(""))

    def test_no_workspace_is_created_for_text_only_request(self):
        import task_workspace
        missing = self.root / "not-created"
        with patch("task_workspace._task_directory", return_value=(self.root, missing)):
            self.assertEqual([], vision.task_image_paths("new-text-turn"))
        self.assertFalse(missing.exists())

    def test_task_lookup_rejects_path_outside_task_root(self):
        import task_workspace
        with patch("task_workspace._task_directory", return_value=(self.root, self.root.parent)):
            with self.assertRaisesRegex(ValueError, "escaped"):
                vision.task_image_paths("escaped")

    def test_only_current_user_receives_native_blocks_without_mutating_history(self):
        history = [{"role": "system", "content": "contract"}, {"role": "user", "content": "earlier"},
                   {"role": "assistant", "content": "earlier answer"}, {"role": "user", "content": "current"}]
        before = copy.deepcopy(history)
        result = vision.openai_messages(history, vision.load_images(self.paths))
        self.assertEqual(before, history)
        self.assertEqual(before[:-1], result[:-1])
        blocks = result[-1]["content"]
        pixels = [b for b in blocks if b["type"] == "image_url"]
        self.assertEqual(2, len(pixels))
        self.assertEqual(self.source.read_bytes(), base64.b64decode(pixels[0]["image_url"]["url"].split(",", 1)[1]))
        self.assertEqual("high", pixels[0]["image_url"]["detail"])
        ollama = vision.ollama_messages(result)
        self.assertEqual(2, len(ollama[-1]["images"]))
        self.assertNotIn("data:image", ollama[-1]["content"])
        self.assertIsInstance(result[-1]["content"], list)

    def test_acp_native_blocks_require_advertised_capability(self):
        import acp
        from acp.schema import AgentCapabilities, PromptCapabilities
        with self.assertRaisesRegex(vision.VisionInputError, "does not advertise"):
            vision.acp_blocks("inspect", self.paths, AgentCapabilities(), acp)
        blocks = vision.acp_blocks("inspect", self.paths,
            AgentCapabilities(prompt_capabilities=PromptCapabilities(image=True)), acp)
        images = [block for block in blocks if block.type == "image"]
        self.assertEqual(2, len(images))
        self.assertEqual(self.source.read_bytes(), base64.b64decode(images[0].data))
        self.assertEqual("image/png", images[0].mime_type)
        self.assertEqual(1, len(vision.acp_blocks("hello", [], None, acp)))

    def test_claude_native_stream_preserves_model_and_execution_boundary(self):
        command = ["claude", "-p", "{prompt}", "--model", "sonnet", "--permission-mode", "plan"]
        with cli_input("claude", command, "inspect", self.paths, self.root, _apply_prompt) as (args, stdin):
            self.assertNotIn("{prompt}", args)
            self.assertEqual("sonnet", args[args.index("--model") + 1])
            self.assertEqual("plan", args[args.index("--permission-mode") + 1])
            event = json.loads(stdin)
            self.assertEqual("user", event["type"])
            images = [b for b in event["message"]["content"] if b["type"] == "image"]
            self.assertEqual(2, len(images))
            self.assertEqual(self.source.read_bytes(), base64.b64decode(images[0]["source"]["data"]))
        self.assertEqual("answer", final_cli_output("claude", '{"type":"system"}\n{"type":"result","result":"answer"}'))
        for raw in ('{"type":"result","is_error":true,"result":"image unsupported"}', '{}'):
            with self.assertRaises(vision.VisionInputError):
                final_cli_output("claude", raw)

    def test_hermes_query_placeholder_and_native_image_option_survive(self):
        command = ["hermes", "chat", "-Q", "-q", "{prompt}", "--toolsets", "none"]
        with cli_input("hermes", command, "inspect", self.paths, self.root, _apply_prompt) as (args, stdin):
            self.assertIsNone(stdin)
            query = args[args.index("-q") + 1]
            self.assertTrue(query.startswith('"'))
            self.assertIn("inspect", query)
            first = Path(query.split('"')[1])
            second = Path(args[args.index("--image") + 1])
            self.assertEqual(self.source.read_bytes(), first.read_bytes())
            self.assertTrue(second.exists())
            self.assertIn("none", args)
        self.assertFalse(first.exists())
        self.assertFalse(second.exists())

    def test_gemini_references_files_relative_to_working_directory(self):
        with cli_input("gemini", ["gemini", "-p", "{prompt}"], "inspect", self.paths, self.root, _apply_prompt) as (args, stdin):
            references = [word[1:] for word in args[-1].split() if word.startswith("@temp/")]
            self.assertEqual(2, len(references))
            self.assertTrue(all((self.root / name).is_file() for name in references))
        self.assertTrue(all(not (self.root / name).exists() for name in references))

    def test_codex_cli_preserves_stdin_mode_and_cleans_on_failure(self):
        with self.assertRaisesRegex(RuntimeError, "test failure"):
            with cli_input("codex", ["codex", "exec", "--sandbox", "read-only", "-"], "inspect",
                           self.paths, self.root, _apply_prompt) as (args, stdin):
                self.assertEqual("-", args[-1])
                self.assertEqual(2, args.count("--image"))
                self.assertIn("read-only", args)
                self.assertIn("inspect", stdin)
                raise RuntimeError("test failure")
        self.assertEqual([], list((self.root / "temp").iterdir()))

    def test_unknown_transport_fails_instead_of_guessing_from_path(self):
        with self.assertRaisesRegex(vision.VisionInputError, "image-capable ACP"):
            with cli_input("custom", ["custom"], "inspect", self.paths, self.root, _apply_prompt):
                self.fail("should not invoke a text-only provider")
        with cli_input("custom", ["custom"], "hello", [], self.root, _apply_prompt) as result:
            self.assertEqual((["custom"], "hello"), result)


if __name__ == "__main__":
    unittest.main()
