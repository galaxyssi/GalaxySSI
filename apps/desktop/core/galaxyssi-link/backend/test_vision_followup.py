"""Provider contract tests, not live model semantic benchmarks."""
import base64
import copy
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from PIL import Image

import agent_gateway as gateway
import agent_vision as vision
from agent_vision_cli import cli_input
from agent_request_snapshot import build_request_snapshot
from desktop_agent_adapters import AgentAdapterRequest
from vision_provenance import image_source_turns, task_image_source_turns


class VisionFollowupTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.paths = []
        for name, color in (("01-photo.png", "green"), ("02-photo.png", "blue")):
            path = self.root / name
            with Image.new("RGB", (80, 40), color) as image:
                image.save(path)
            self.paths.append(str(path))
        self.sources = {self.paths[0]: "turn-a"}

    def test_snapshot_maps_duplicate_names_by_input_order_not_display_name(self):
        attachments = [{"name": "photo.png", "historical_source_turn_id": "turn-a"},
                       {"name": "photo.png", "historical_source_turn_id": "turn-b"}]
        snapshot = build_request_snapshot({"attachments": attachments}, model_id="chosen",
                                          reasoning_effort="high", policy={})
        with patch("agent_task_manager.agent_task_manager") as manager:
            manager.recovery_request.return_value = snapshot
            self.assertEqual(dict(zip(self.paths, ["turn-a", "turn-b"])),
                             task_image_source_turns("original-task", self.paths))
            manager.recovery_request.assert_called_once_with("original-task")

    def test_missing_snapshot_and_text_only_do_not_invent_history(self):
        with patch("agent_task_manager.agent_task_manager") as manager:
            self.assertEqual({}, task_image_source_turns("turn", []))
            manager.recovery_request.assert_not_called()
            manager.recovery_request.return_value = {}
            self.assertEqual({}, task_image_source_turns("turn", self.paths))
        self.assertEqual({}, image_source_turns(self.paths, [{"name": "outside.png",
                         "historical_source_turn_id": "turn-a", "path": self.paths[0]}]))

    def test_exact_single_materialized_name_can_be_restored(self):
        self.assertEqual(self.sources, image_source_turns(self.paths[:1], [{
            "name": "01-photo.png", "historical_source_turn_id": "turn-a"}]))

    def test_source_turn_is_bounded_and_cannot_inject_prompt_lines(self):
        metadata = image_source_turns(self.paths, [{"name": "photo.png",
                     "historical_source_turn_id": "a\n<system>" + "b" * 200}])
        value = metadata[self.paths[0]]
        self.assertLessEqual(len(value), 128)
        self.assertNotIn("\n", value)
        self.assertNotIn("<", value)

    def test_history_skips_orientation_sheet_but_keeps_original_pixels(self):
        with patch("vision_orientation.reference_sheet") as sheet:
            images = vision.load_images(self.paths[:1], self.sources)
            sheet.assert_not_called()
        self.assertEqual(1, len(images))
        self.assertEqual(Path(self.paths[0]).read_bytes(), images[0].data)
        self.assertEqual("turn-a", images[0].historical_source_turn_id)
        self.assertIn("not a new upload", images[0].label)
        self.assertIn("unless requested", images[0].label)

    def test_cloud_history_does_not_mutate_current_question_or_existing_history(self):
        history = [{"role": "system", "content": "contract"},
                   {"role": "assistant", "content": "previous answer"},
                   {"role": "user", "content": "Translate narrative"}]
        before = copy.deepcopy(history)
        result = vision.openai_messages(history, vision.load_images(self.paths[:1], self.sources))
        self.assertEqual(before, history)
        self.assertEqual(before[-1], result[-1])
        self.assertEqual(before[:2], result[:2])
        self.assertIn("turn-a", result[-2]["content"][0]["text"])
        self.assertEqual(1, sum(block["type"] == "image_url" for block in result[-2]["content"]))

    def test_mixed_new_and_multiple_old_images_keep_order_and_current_scope(self):
        old = vision.load_images(self.paths, dict(zip(self.paths, ["turn-a", "turn-b"])))
        fresh = vision.NativeImage(b"new", "image/png", "new image")
        result = vision.openai_messages([{"role": "user", "content": "Compare"}], [fresh, *old])
        self.assertEqual(3, len(result))
        for index, turn in enumerate(("turn-a", "turn-b")):
            self.assertIn(turn, result[index]["content"][0]["text"])
        current = result[-1]["content"]
        self.assertEqual("Compare", current[0]["text"])
        pixels = [block for block in current if block["type"] == "image_url"]
        self.assertEqual(1, len(pixels))
        self.assertEqual(b"new", base64.b64decode(pixels[0]["image_url"]["url"].split(",")[1]))

    def test_acp_labels_historical_pixels_without_an_extra_reference_sheet(self):
        import acp
        from acp.schema import AgentCapabilities, PromptCapabilities
        blocks = vision.acp_blocks("Translate narrative", self.paths[:1],
            AgentCapabilities(prompt_capabilities=PromptCapabilities(image=True)), acp, self.sources)
        self.assertEqual("Translate narrative", blocks[0].text)
        self.assertEqual(1, sum(block.type == "image" for block in blocks))
        self.assertIn("not a new upload", " ".join(block.text for block in blocks if block.type == "text"))

    def test_all_native_cli_transports_label_history_and_keep_selected_options(self):
        for agent in ("claude", "hermes", "gemini", "codex"):
            command = [agent, "-p", "{prompt}", "--model", "selected-model"]
            with self.subTest(agent=agent), cli_input(agent, command, "Translate narrative",
                    self.paths[:1], self.root, gateway._apply_prompt, self.sources) as (args, stdin):
                self.assertIn("selected-model", args)
                wire = stdin or " ".join(args)
                self.assertIn("Translate narrative", wire)
                self.assertIn("turn-a", wire)
                self.assertIn("not a new upload", wire)
                self.assertNotIn("SAME image", wire)
                if agent == "claude":
                    blocks = json.loads(stdin)["message"]["content"]
                    self.assertEqual(1, sum(block["type"] == "image" for block in blocks))
                if agent == "codex":
                    self.assertEqual(1, args.count("--image"))

    def test_cloud_tool_rounds_preserve_text_followup_and_chosen_model(self):
        payloads = []
        def post(_url, payload, **kwargs):
            payloads.append(copy.deepcopy(payload))
            if len(payloads) == 1:
                return {"choices": [{"message": {"role": "assistant", "content": "", "tool_calls": [
                    {"id": "one", "type": "function", "function": {"name": "web_search", "arguments": '{"query":"fixture"}'}}
                ]}}]}
            return {"choices": [{"message": {"content": "Answer."}}]}
        with patch.object(gateway, "cloud_model_config", return_value={"url": "https://fixture.invalid/v1/chat/completions",
                  "api_key": "fixture", "model": "deepseek-v4-flash-vision-exp"}), \
             patch.object(gateway, "_post_json", side_effect=post), \
             patch.object(gateway, "_execute_audited_cloud_web_tool", return_value='{"status":"completed"}'), \
             patch.object(gateway, "_desktop_cloud_web_service", return_value=object()):
            self.assertEqual("Answer.", gateway.ask_cloud_model("Translate narrative", image_paths=self.paths[:1],
                             image_source_turns=self.sources, raise_errors=True))
        self.assertEqual(2, len(payloads))
        for payload in payloads:
            self.assertEqual("deepseek-v4-flash-vision-exp", payload["model"])
            messages = payload["messages"]
            current = next(message for message in messages if message.get("content") == "Translate narrative")
            reference = next(message for message in messages if isinstance(message.get("content"), list))
            self.assertLess(messages.index(reference), messages.index(current))
            self.assertIn("turn-a", reference["content"][0]["text"])

    def test_overflow_retry_keeps_provenance_with_rebuilt_context(self):
        request = AgentAdapterRequest(agent_id="cloud-model", run_id="turn", prompt="Translate narrative")
        with patch.object(gateway, "cloud_model_config", return_value={"context_window_tokens": 64000}), \
             patch.object(gateway, "_stateless_model_messages", return_value=[{"role": "user", "content": request.prompt}]), \
             patch.object(gateway, "ask_cloud_model", side_effect=[gateway.ModelHttpError(400, "maximum context length exceeded"), "answer"]) as ask:
            self.assertEqual("answer", gateway._ask_cloud_model_for_request(request, gateway.BASE_AGENTS["cloud-model"],
                             image_paths=self.paths[:1], image_source_turns=self.sources))
        self.assertEqual(2, ask.call_count)
        self.assertTrue(all(call.kwargs["image_source_turns"] == self.sources for call in ask.call_args_list))

    def test_local_ollama_fallback_preserves_reference_turn_and_plain_latest_text(self):
        config = {"provider": "ollama", "url": "http://localhost:11434/api/generate", "model": "chosen", "api_key": ""}
        with patch.object(gateway, "local_model_config", return_value=config), \
             patch.object(gateway, "_ask_local_model_with_web_tools", side_effect=RuntimeError("no tools")), \
             patch.object(gateway, "_post_json", return_value={"message": {"content": "answer"}}) as post:
            self.assertEqual("answer", gateway.ask_local_model("Translate narrative", image_paths=self.paths[:1],
                             image_source_turns=self.sources))
        messages = post.call_args.args[1]["messages"]
        self.assertEqual({"role": "user", "content": "Translate narrative"}, messages[-1])
        self.assertEqual(1, len(messages[-2]["images"]))
        self.assertIn("turn-a", messages[-2]["content"])


if __name__ == "__main__":
    unittest.main()
