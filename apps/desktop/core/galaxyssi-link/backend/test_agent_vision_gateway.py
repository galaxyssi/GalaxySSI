import base64
import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from PIL import Image

import agent_gateway as gateway
from desktop_agent_adapters import AgentAdapterRequest


class VisionGatewayTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.path = self.root / "source.png"
        with Image.new("RGB", (80, 40), "green") as image:
            image.save(self.path)
        self.paths = [str(self.path)]

    def config(self):
        return {"url": "https://model.invalid/v1/chat/completions", "api_key": "fixture-only",
                "model": "chosen-vision-model", "context_window_tokens": 64000}

    def test_cloud_tool_continuation_keeps_native_images_and_selected_model(self):
        payloads = []
        def post(_url, payload, **kwargs):
            payloads.append(copy.deepcopy(payload))
            if len(payloads) == 1:
                return {"choices": [{"message": {"role": "assistant", "content": "", "tool_calls": [
                    {"id": "one", "type": "function", "function": {"name": "web_search", "arguments": '{"query":"fixture"}'}}
                ]}}]}
            return {"choices": [{"message": {"content": "Verified answer."}}]}
        with patch.object(gateway, "cloud_model_config", side_effect=self.config), \
             patch.object(gateway, "_post_json", side_effect=post), \
             patch.object(gateway, "_execute_audited_cloud_web_tool", return_value='{"status":"completed"}'), \
             patch.object(gateway, "_desktop_cloud_web_service", return_value=object()):
            answer = gateway.ask_cloud_model("inspect", image_paths=self.paths, raise_errors=True)
        self.assertEqual("Verified answer.", answer)
        self.assertEqual(2, len(payloads))
        for payload in payloads:
            self.assertEqual("chosen-vision-model", payload["model"])
            user = next(m for m in payload["messages"] if m["role"] == "user")
            images = [b for b in user["content"] if b["type"] == "image_url"]
            self.assertEqual(2, len(images))
            self.assertEqual(self.path.read_bytes(), base64.b64decode(images[0]["image_url"]["url"].split(",", 1)[1]))

    def test_context_overflow_retry_retains_image_paths(self):
        request = AgentAdapterRequest(agent_id="cloud-model", run_id="turn", prompt="inspect")
        with patch.object(gateway, "cloud_model_config", side_effect=self.config), \
             patch.object(gateway, "_stateless_model_messages", return_value=[{"role": "user", "content": "inspect"}]), \
             patch.object(gateway, "ask_cloud_model", side_effect=[gateway.ModelHttpError(400, "maximum context length exceeded"), "answer"]) as ask:
            result = gateway._ask_cloud_model_for_request(request, gateway.BASE_AGENTS["cloud-model"], image_paths=self.paths)
        self.assertEqual("answer", result)
        self.assertEqual(2, ask.call_count)
        self.assertTrue(all(call.kwargs["image_paths"] == self.paths for call in ask.call_args_list))

    def test_local_ollama_fallback_keeps_native_images_in_chat_not_generate(self):
        captured = []
        def post(url, payload, **kwargs):
            captured.append((url, payload))
            return {"message": {"content": "Local visual answer."}}
        config = {"provider": "ollama", "url": "http://localhost:11434/api/generate", "model": "local-vision", "api_key": ""}
        with patch.object(gateway, "local_model_config", return_value=config), \
             patch.object(gateway, "_ask_local_model_with_web_tools", side_effect=RuntimeError("tools unsupported")), \
             patch.object(gateway, "_post_json", side_effect=post):
            answer = gateway.ask_local_model("inspect", image_paths=self.paths)
        self.assertEqual("Local visual answer.", answer)
        self.assertEqual("http://localhost:11434/api/chat", captured[0][0])
        payload = captured[0][1]
        self.assertNotIn("prompt", payload)
        self.assertEqual(2, len(payload["messages"][-1]["images"]))
        self.assertEqual(self.path.read_bytes(), base64.b64decode(payload["messages"][-1]["images"][0]))

    def test_api_rejecting_images_surfaces_real_error_without_text_only_retry(self):
        with patch.object(gateway, "cloud_model_config", side_effect=self.config), \
             patch.object(gateway, "_post_json", side_effect=gateway.ModelHttpError(400, "model does not support images")) as post:
            with self.assertRaisesRegex(gateway.ModelHttpError, "does not support images"):
                gateway.ask_cloud_model("inspect", image_paths=self.paths, raise_errors=True)
        self.assertEqual(1, post.call_count)

    def test_recovery_uses_original_task_images_not_recovery_run_directory(self):
        from agent_execution_harness import AgentExecutionMode
        harness = MagicMock()
        harness.policy.execution_mode = AgentExecutionMode.PLAN_ONLY
        harness.effective_timeout.return_value = 30
        for agent_id, target in (("cloud-model", "_ask_cloud_model_for_request"),
                                 ("local-llm", "ask_local_model"), ("claude", "_ask_agent_sync_inner")):
            request = AgentAdapterRequest(agent_id=agent_id, run_id="turn:recovery:1", prompt="inspect",
                checkpoint={"task_id": "original-turn", "connector_task_mode": "phone_supervised_project_plan_v1"})
            with self.subTest(agent=agent_id), \
                 patch("agent_vision.task_image_paths", return_value=self.paths) as lookup, \
                 patch("agent_execution_harness.AgentExecutionHarness", return_value=harness), \
                 patch("agent_execution_harness.execution_contract", return_value="contract"), \
                 patch("agent_task_manager.agent_task_manager", MagicMock()), \
                 patch.object(gateway, target, return_value='{"type":"ANSWER","text":"answer"}') as ask:
                gateway._execute_agent_adapter_request(agent_id, request)
                lookup.assert_called_once_with("original-turn")
                self.assertEqual(self.paths, ask.call_args.kwargs["image_paths"])
                if agent_id == "claude":
                    self.assertTrue(ask.call_args.kwargs["plan_only"])

    def test_real_cli_subprocess_receives_claude_images_and_returns_only_answer(self):
        script = self.root / "fake_claude.py"
        script.write_text(
            "import json,sys,base64\n"
            "event=json.loads(sys.stdin.readline())\n"
            "images=[b for b in event['message']['content'] if b['type']=='image']\n"
            "assert len(images)==2\n"
            "assert base64.b64decode(images[0]['source']['data']).startswith(b'\\x89PNG')\n"
            "print(json.dumps({'type':'result','result':'Visual answer.'}))\n", encoding="utf-8")
        with patch.object(gateway, "cli_agent_runtime_config", return_value={"enabled": False}), \
             patch("task_workspace.task_workspace", return_value=self.root), \
             patch("host_execution_config_guard.HostExecutionConfigGuard.begin", return_value=MagicMock(finish=lambda: [])):
            result = gateway._run_cli_agent_process(gateway.BASE_AGENTS["claude"],
                [sys.executable, str(script), "-p", "{prompt}"], "inspect", original_text="inspect",
                task_id="", conversation_id="", response_language="en", restricted_workspace=True,
                plan_only=True, image_paths=self.paths)
        self.assertEqual("Visual answer.", result)

    def test_persistent_text_only_transport_rejects_images_before_process(self):
        with patch.object(gateway, "cli_agent_runtime_config", return_value={"enabled": True, "mode": "galaxyssi-jsonl-v1"}), \
             patch.object(gateway, "external_cli_process_pool") as pool:
            result = gateway._run_cli_agent_process(gateway.BASE_AGENTS["hermes"], ["hermes"], "inspect",
                original_text="inspect", task_id="", conversation_id="", response_language="en",
                restricted_workspace=False, image_paths=self.paths)
        self.assertIn("vision_transport_unsupported", result)
        pool.assert_not_called()


if __name__ == "__main__":
    unittest.main()
