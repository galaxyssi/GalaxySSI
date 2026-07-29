import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import agent_gateway
from provider_profiles import (
    MODEL_PROVIDER_DEFINITIONS,
    ProviderMetricsStore,
    ProviderPricing,
    build_provider_profile_catalog,
    estimate_provider_cost_micros,
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
                "input_micros_per_million_tokens": 500_000,
                "output_micros_per_million_tokens": 1_500_000,
                "pricing_currency": "usd",
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
        self.assertEqual(500_000, profile["pricing"]["input_micros_per_million_tokens"])
        self.assertEqual(1_500_000, profile["pricing"]["output_micros_per_million_tokens"])
        self.assertEqual("USD", profile["pricing"]["currency"])
        self.assertEqual("configured", profile["pricing"]["source"])
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

    def test_runtime_telemetry_records_latency_usage_cost_context_and_tools(self) -> None:
        self.metrics.record(
            "cloud-model",
            success=True,
            latency_ms=1_000,
            input_tokens=1_000,
            output_tokens=200,
            cost_micros=800,
            usage_estimated=False,
            context_window_tokens=4_000,
            tool_calls=2,
            tool_failures=0,
        )
        self.metrics.record(
            "cloud-model",
            success=False,
            latency_ms=5_000,
            input_tokens=2_000,
            output_tokens=100,
            cost_micros=None,
            usage_estimated=True,
            context_window_tokens=4_000,
            tool_calls=1,
            tool_failures=1,
        )
        snapshot = self.metrics.record(
            "cloud-model",
            success=True,
            latency_ms=2_000,
            input_tokens=500,
            output_tokens=300,
            cost_micros=400,
            usage_estimated=True,
            context_window_tokens=4_000,
            tool_calls=0,
            tool_failures=0,
        )

        self.assertEqual(3, snapshot.attempts)
        self.assertAlmostEqual(1 / 3, snapshot.failure_rate, places=6)
        self.assertEqual(3, snapshot.latency_observations)
        self.assertEqual(2_000, snapshot.last_latency_ms)
        self.assertEqual(1_000, snapshot.min_latency_ms)
        self.assertEqual(5_000, snapshot.max_latency_ms)
        self.assertEqual(2_000, snapshot.p50_latency_ms)
        self.assertEqual(5_000, snapshot.p95_latency_ms)
        self.assertAlmostEqual(2_666.667, snapshot.average_latency_ms, places=3)
        self.assertEqual(3_500, snapshot.input_tokens)
        self.assertEqual(600, snapshot.output_tokens)
        self.assertEqual(4_100, snapshot.total_tokens)
        self.assertEqual(2, snapshot.estimated_usage_observations)
        self.assertEqual(2_000, snapshot.max_input_tokens)
        self.assertEqual(0.5, snapshot.max_context_utilization)
        self.assertEqual(2, snapshot.priced_attempts)
        self.assertEqual(1, snapshot.unpriced_attempts)
        self.assertEqual(1_200, snapshot.total_cost_micros)
        self.assertEqual(600, snapshot.average_cost_micros)
        self.assertEqual(400, snapshot.last_cost_micros)
        self.assertEqual(3, snapshot.tool_calls)
        self.assertEqual(1, snapshot.tool_failures)
        self.assertAlmostEqual(1 / 3, snapshot.tool_failure_rate, places=6)

    def test_latency_samples_are_bounded_and_invalid_values_are_sanitized(self) -> None:
        for latency in range(200):
            self.metrics.record("codex", success=True, latency_ms=latency)
        self.metrics.record("codex", success=False, latency_ms=float("nan"))

        document = json.loads(self.metrics_path.read_text(encoding="utf-8"))
        samples = document["metrics"]["codex"]["latency_samples"]
        snapshot = self.metrics.snapshot("codex")

        self.assertEqual(128, len(samples))
        self.assertGreaterEqual(snapshot.p50_latency_ms, 0)
        self.assertGreaterEqual(snapshot.p95_latency_ms, snapshot.p50_latency_ms)

    def test_cost_estimation_requires_complete_explicit_pricing(self) -> None:
        configured = ProviderPricing(
            tier="medium",
            input_micros_per_million_tokens=500_000,
            output_micros_per_million_tokens=1_500_000,
        )
        partial = ProviderPricing(
            tier="medium",
            input_micros_per_million_tokens=500_000,
        )

        self.assertEqual(800, estimate_provider_cost_micros(1_000, 200, configured))
        self.assertIsNone(estimate_provider_cost_micros(1_000, 200, partial))

    def test_gateway_observation_uses_explicit_pricing_and_context(self) -> None:
        config = {
            "provider": "deepseek",
            "context_window_tokens": 100_000,
            "input_micros_per_million_tokens": 500_000,
            "output_micros_per_million_tokens": 1_500_000,
            "pricing_currency": "USD",
        }
        with patch.object(agent_gateway, "cloud_model_config", return_value=config):
            observation = agent_gateway._provider_usage_estimate(
                "cloud-model",
                "a" * 4_000,
                "b" * 800,
            )

        self.assertEqual(1_000, observation["input_tokens"])
        self.assertEqual(200, observation["output_tokens"])
        self.assertEqual("model:deepseek", observation["metrics_key"])
        self.assertEqual(100_000, observation["context_window_tokens"])
        self.assertEqual(800, observation["cost_micros"])
        self.assertEqual("USD", observation["cost_currency"])

    def test_model_provider_metrics_are_isolated_from_generic_contact_ids(self) -> None:
        self.metrics.record("model:deepseek", success=True, latency_ms=900)
        self.metrics.record("model:openai", success=False, latency_ms=4_500)
        catalog = self.catalog({
            "cloud_model": {
                "provider": "deepseek",
                "url": "https://api.deepseek.com/chat/completions",
                "model": "deepseek-test",
                "api_key": "secret",
            }
        })
        profiles = {
            profile["provider_id"]: profile
            for profile in catalog["profiles"]
            if profile["kind"] in {"cloud_model", "local_model"}
        }

        self.assertEqual(1, profiles["deepseek"]["performance"]["successes"])
        self.assertEqual(0, profiles["deepseek"]["performance"]["failures"])
        self.assertEqual(1, profiles["openai"]["performance"]["failures"])
        self.assertEqual("model:deepseek", profiles["deepseek"]["metadata"]["metrics_key"])

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
