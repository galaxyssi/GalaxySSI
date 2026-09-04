import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import agent_config


class AgentConfigStorageTest(unittest.TestCase):
    def test_missing_current_config_uses_defaults_without_creating_state(self):
        with tempfile.TemporaryDirectory() as directory:
            state_dir = Path(directory) / "state"
            with patch.dict(
                os.environ,
                {"GALAXYSSI_STATE_DIR": str(state_dir), "GALAXYSSI_CONFIG_PATH": ""},
                clear=False,
            ):
                loaded = agent_config.load_config()

            self.assertEqual(agent_config.DEFAULT_CONFIG["commands"]["claude"], loaded["commands"]["claude"])
            self.assertFalse((state_dir / "agents.json").exists())

    def test_save_config_writes_only_to_runtime_state(self):
        with tempfile.TemporaryDirectory() as directory:
            state_dir = Path(directory) / "state"
            with patch.dict(
                os.environ,
                {"GALAXYSSI_STATE_DIR": str(state_dir), "GALAXYSSI_CONFIG_PATH": ""},
                clear=False,
            ):
                agent_config.save_config({"custom_agent": {"name": "Test Agent"}})

            saved = json.loads((state_dir / "agents.json").read_text(encoding="utf-8"))
            self.assertEqual("Test Agent", saved["custom_agent"]["name"])

    def test_cloud_api_and_context_settings_round_trip_without_exposing_secret(self):
        with tempfile.TemporaryDirectory() as directory:
            state_dir = Path(directory) / "state"
            with patch.dict(
                os.environ,
                {"GALAXYSSI_STATE_DIR": str(state_dir), "GALAXYSSI_CONFIG_PATH": ""},
                clear=False,
            ):
                masked = agent_config.save_config({
                    "cloud_model": {
                        "provider": "deepseek",
                        "name": "DeepSeek",
                        "url": "https://api.deepseek.com/chat/completions",
                        "model": "deepseek-test",
                        "api_key": "secret-key",
                        "context_window_tokens": "128000",
                        "max_output_tokens": "8192",
                        "context_model_summary": "true",
                        "input_micros_per_million_tokens": "2500000",
                        "output_micros_per_million_tokens": "10000000",
                        "pricing_currency": "usd",
                    }
                })
                persisted = agent_config.load_config(mask_secrets=False)["cloud_model"]
                effective = agent_config.cloud_model_config()

            self.assertEqual(agent_config.MASK, masked["cloud_model"]["api_key"])
            self.assertEqual("secret-key", persisted["api_key"])
            self.assertEqual("deepseek", persisted["provider"])
            self.assertEqual("128000", persisted["context_window_tokens"])
            self.assertEqual("8192", persisted["max_output_tokens"])
            self.assertEqual("true", persisted["context_model_summary"])
            self.assertEqual(2_500_000, effective["input_micros_per_million_tokens"])
            self.assertEqual(10_000_000, effective["output_micros_per_million_tokens"])
            self.assertEqual("USD", effective["pricing_currency"])

    def test_language_policy_defaults_and_round_trip_are_normalized(self):
        with tempfile.TemporaryDirectory() as directory:
            state_dir = Path(directory) / "state"
            with patch.dict(
                os.environ,
                {"GALAXYSSI_STATE_DIR": str(state_dir), "GALAXYSSI_CONFIG_PATH": ""},
                clear=False,
            ):
                self.assertEqual(
                    {
                        "response_language": "auto",
                        "asr_language": "auto",
                        "tts_language": "auto",
                    },
                    agent_config.language_policy_config(),
                )
                agent_config.save_config({
                    "language_policy": {
                        "response_language": "zh-hk",
                        "asr_language": "unsupported",
                        "tts_language": "EN-us",
                    }
                })
                persisted = agent_config.load_config()["language_policy"]
                effective = agent_config.language_policy_config()

            self.assertEqual("zh-HK", persisted["response_language"])
            self.assertEqual("auto", persisted["asr_language"])
            self.assertEqual("en-US", persisted["tts_language"])
            self.assertEqual(persisted, effective)

    def test_web_source_credentials_round_trip_without_exposing_secrets(self):
        with tempfile.TemporaryDirectory() as directory:
            state_dir = Path(directory) / "state"
            with patch.dict(
                os.environ,
                {"GALAXYSSI_STATE_DIR": str(state_dir), "GALAXYSSI_CONFIG_PATH": ""},
                clear=False,
            ):
                masked = agent_config.save_config({
                    "web_search": {
                        "brave_api_key": "brave-secret",
                        "github_token": "github-secret",
                    }
                })
                persisted = agent_config.web_search_config()

            self.assertEqual(agent_config.MASK, masked["web_search"]["brave_api_key"])
            self.assertEqual(agent_config.MASK, masked["web_search"]["github_token"])
            self.assertEqual("brave-secret", persisted["brave_api_key"])
            self.assertEqual("github-secret", persisted["github_token"])

    def test_cli_runtime_settings_and_custom_transport_are_normalized(self):
        with tempfile.TemporaryDirectory() as directory:
            state_dir = Path(directory) / "state"
            with patch.dict(
                os.environ,
                {"GALAXYSSI_STATE_DIR": str(state_dir), "GALAXYSSI_CONFIG_PATH": ""},
                clear=False,
            ):
                agent_config.save_config({
                    "cli_runtime": {
                        "enabled": True,
                        "max_processes": 99,
                        "max_processes_per_agent": 3,
                        "idle_timeout_seconds": 42,
                        "max_requests_per_process": 12,
                    },
                    "custom_agents": [{
                        "id": "research-agent",
                        "name": "Research Agent",
                        "command": "research-agent --serve-jsonl",
                        "transport": "jsonl",
                        "pool_size": 2,
                        "prewarm": True,
                    }],
                })
                runtime = agent_config.cli_runtime_config()
                custom = agent_config.custom_agent_configs()

            self.assertEqual(32, runtime["max_processes"])
            self.assertEqual(3, runtime["max_processes_per_agent"])
            self.assertEqual(42, runtime["idle_timeout_seconds"])
            self.assertEqual("galaxyssi-jsonl-v1", runtime["transports"]["research-agent"]["mode"])
            self.assertEqual("galaxyssi-jsonl-v1", custom[0]["transport"])
            self.assertEqual(2, custom[0]["pool_size"])
            self.assertTrue(custom[0]["prewarm"])

    def test_jsonl_command_marker_enables_persistent_transport_explicitly(self):
        runtime = agent_config.cli_agent_runtime_config(
            "custom-agent",
            ["python", "agent.py", "--serve-jsonl"],
        )

        self.assertTrue(runtime["enabled"])
        self.assertEqual("galaxyssi-jsonl-v1", runtime["mode"])

    def test_acp_runtime_normalizes_hermes_and_capacity_settings(self):
        with tempfile.TemporaryDirectory() as directory:
            state_dir = Path(directory) / "state"
            with patch.dict(
                os.environ,
                {"GALAXYSSI_STATE_DIR": str(state_dir), "GALAXYSSI_CONFIG_PATH": ""},
                clear=False,
            ):
                agent_config.save_config({
                    "acp_runtime": {
                        "enabled": True,
                        "max_processes": 99,
                        "idle_timeout_seconds": 5,
                        "agents": {
                            "hermes": {
                                "enabled": True,
                                "command": "hermes acp --profile mobile",
                                "prewarm": True,
                            }
                        },
                    }
                })
                runtime = agent_config.acp_runtime_config()
                hermes = agent_config.acp_agent_runtime_config("hermes")

        self.assertEqual(16, runtime["max_processes"])
        self.assertEqual(30, runtime["idle_timeout_seconds"])
        self.assertEqual("hermes acp --profile mobile", hermes["command"])
        self.assertTrue(hermes["enabled"])
        self.assertTrue(hermes["prewarm"])


if __name__ == "__main__":
    unittest.main()
