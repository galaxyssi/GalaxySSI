import json
import tempfile
import unittest
from pathlib import Path

from provider_profiles import (
    MODEL_PROVIDER_DEFINITIONS,
    ProviderMetricsStore,
    build_provider_profile_catalog,
    infer_provider_id,
    routable_model_profiles,
)


class ProviderProfileTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.metrics_path = Path(self.temporary.name) / "provider-metrics.json"
        self.now = 1_000
        self.metrics = ProviderMetricsStore(self.metrics_path, clock=lambda: self.now)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def catalog(self, config=None, agents=None):
        return build_provider_profile_catalog(
            agents=agents or [],
            config=config or {},
            metrics_store=self.metrics,
        )

    def test_catalog_contains_all_supported_model_provider_families(self) -> None:
        catalog = self.catalog()
        model_profiles = {
            profile["provider_id"]: profile
            for profile in catalog["profiles"]
            if profile["kind"] in {"cloud_model", "local_model"}
        }

        self.assertEqual(
            {
                "openai",
                "anthropic",
                "gemini",
                "deepseek",
                "qwen",
                "ollama",
                "lm-studio",
                "openrouter",
            },
            set(model_profiles),
        )
        self.assertEqual(len(MODEL_PROVIDER_DEFINITIONS), catalog["summary"]["model_providers"])
        for profile in model_profiles.values():
            self.assertGreater(profile["context_window_tokens"], 0)
            self.assertIn(profile["pricing"]["tier"], {"free", "low", "medium", "high"})
            self.assertIn("failure_rate", profile["performance"])
            self.assertIn("supports_tools", profile)

    def test_configured_cloud_profile_preserves_model_limits_without_exposing_secret(self) -> None:
        catalog = self.catalog({
            "cloud_model": {
                "provider": "deepseek",
                "name": "DeepSeek",
                "url": "https://api.deepseek.com/chat/completions",
                "model": "deepseek-v4-pro",
                "api_key": "secret-value",
                "context_window_tokens": 96_000,
                "max_output_tokens": 8_192,
            }
        })
        profile = next(
            item for item in catalog["profiles"] if item["provider_id"] == "deepseek"
        )

        self.assertEqual("configured", profile["status"])
        self.assertEqual("cloud-model", profile["resource_id"])
        self.assertEqual("deepseek-v4-pro", profile["model_id"])
        self.assertEqual(96_000, profile["context_window_tokens"])
        self.assertEqual(8_192, profile["max_output_tokens"])
        self.assertTrue(profile["credential_configured"])
        self.assertNotIn("secret-value", json.dumps(catalog))

    def test_native_agent_identity_and_adapter_are_not_replaced_by_generic_provider(self) -> None:
        catalog = self.catalog(agents=[
            {
                "id": "codex",
                "name": "Codex Agent",
                "kind": "local-cli",
                "status": "ready",
                "capabilities": ["code", "terminal", "files", "tasks"],
                "adapter": {
                    "adapter_type": "codex-app-server",
                    "independently_upgradeable": True,
                },
            },
            {
                "id": "hermes",
                "name": "Hermes Agent",
                "kind": "local-cli",
                "status": "busy",
                "capabilities": ["conversation", "research", "tools"],
                "adapter": {"adapter_type": "hermes-native-session"},
            },
        ])
        profiles = {item["resource_id"]: item for item in catalog["profiles"]}

        self.assertEqual("codex", profiles["codex"]["product_id"])
        self.assertEqual("codex-app-server", profiles["codex"]["adapter_type"])
        self.assertEqual("agent", profiles["codex"]["kind"])
        self.assertEqual("hermes", profiles["hermes"]["product_id"])
        self.assertEqual("hermes-native-session", profiles["hermes"]["adapter_type"])

    def test_observations_persist_ewma_failure_rate_and_recovery(self) -> None:
        first = self.metrics.record("codex", success=False, latency_ms=4_000)
        self.now += 500
        second = self.metrics.record("codex", success=True, latency_ms=1_000)
        reloaded = ProviderMetricsStore(self.metrics_path, clock=lambda: self.now).snapshot("codex")

        self.assertEqual(1, first.consecutive_failures)
        self.assertEqual(0, second.consecutive_failures)
        self.assertEqual(2, reloaded.attempts)
        self.assertEqual(0.5, reloaded.failure_rate)
        self.assertEqual(3_250.0, reloaded.ewma_latency_ms)
        self.assertEqual(self.now, reloaded.last_observed_at_millis)

    def test_provider_inference_handles_local_and_product_aliases(self) -> None:
        self.assertEqual("anthropic", infer_provider_id({"provider": "Claude"}))
        self.assertEqual("gemini", infer_provider_id({"provider": "Google Gemini"}))
        self.assertEqual(
            "ollama",
            infer_provider_id({"url": "http://127.0.0.1:11434/api/generate"}, local=True),
        )
        self.assertEqual(
            "lm-studio",
            infer_provider_id({"url": "http://localhost:1234/v1/chat/completions"}, local=True),
        )

    def test_agent_and_model_profile_namespaces_cannot_collide(self) -> None:
        catalog = self.catalog(
            config={
                "cloud_model": {
                    "provider": "openai",
                    "url": "https://api.openai.com/v1/chat/completions",
                    "model": "gpt-test",
                    "api_key": "key",
                }
            },
            agents=[{
                "id": "openai",
                "name": "OpenAI CLI Agent",
                "kind": "custom-cli",
                "status": "ready",
                "capabilities": ["conversation"],
                "adapter": {"adapter_type": "custom-native-session"},
            }],
        )
        profile_ids = [item["profile_id"] for item in catalog["profiles"]]

        self.assertIn("model:openai", profile_ids)
        self.assertIn("agent:openai", profile_ids)
        self.assertEqual(len(profile_ids), len(set(profile_ids)))

    def test_routable_model_profiles_include_live_states_and_exclude_unconfigured_catalog(self) -> None:
        catalog = {
            "profiles": [
                {"resource_id": "cloud-model", "kind": "cloud_model", "status": "ready"},
                {"resource_id": "local-llm", "kind": "local_model", "status": "busy"},
                {"resource_id": "fallback", "kind": "cloud_model", "status": "degraded"},
                {"resource_id": "catalog:openai", "kind": "cloud_model", "status": "not_configured"},
                {"resource_id": "codex", "kind": "agent", "status": "ready"},
            ]
        }

        self.assertEqual(
            ["cloud-model", "local-llm", "fallback"],
            [profile["resource_id"] for profile in routable_model_profiles(catalog)],
        )


if __name__ == "__main__":
    unittest.main()
