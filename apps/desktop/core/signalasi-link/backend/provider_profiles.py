"""Unified routing profiles for model providers and native Agent products."""
from __future__ import annotations

import json
import os
import threading
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Callable, Iterable


PROFILE_SCHEMA_VERSION = 1
METRICS_SCHEMA_VERSION = 1
EWMA_ALPHA = 0.25
ROUTABLE_PROVIDER_STATUSES = frozenset({"configured", "ready", "busy", "degraded"})


@dataclass(frozen=True)
class ModelProviderDefinition:
    provider_id: str
    display_name: str
    protocol_family: str
    location: str
    cost_tier: str
    latency_tier: str
    quality_tier: str
    context_window_tokens: int
    supports_tools: bool
    supports_streaming: bool
    endpoint_hint: str = ""


MODEL_PROVIDER_DEFINITIONS: tuple[ModelProviderDefinition, ...] = (
    ModelProviderDefinition(
        "openai", "OpenAI", "openai", "cloud", "medium", "normal", "frontier",
        128_000, True, True, "https://api.openai.com/v1/chat/completions",
    ),
    ModelProviderDefinition(
        "anthropic", "Claude", "anthropic", "cloud", "medium", "normal", "frontier",
        200_000, True, True, "https://api.anthropic.com/v1/messages",
    ),
    ModelProviderDefinition(
        "gemini", "Gemini", "gemini", "cloud", "medium", "fast", "frontier",
        1_000_000, True, True, "https://generativelanguage.googleapis.com/v1beta/models",
    ),
    ModelProviderDefinition(
        "deepseek", "DeepSeek", "openai", "cloud", "low", "normal", "frontier",
        128_000, True, True, "https://api.deepseek.com/chat/completions",
    ),
    ModelProviderDefinition(
        "qwen", "Qwen", "openai", "cloud", "low", "normal", "strong",
        131_072, True, True, "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
    ),
    ModelProviderDefinition(
        "ollama", "Ollama", "ollama", "private", "free", "fast", "standard",
        32_768, False, True, "http://127.0.0.1:11434/api/generate",
    ),
    ModelProviderDefinition(
        "lm-studio", "LM Studio", "openai", "private", "free", "fast", "standard",
        32_768, False, True, "http://127.0.0.1:1234/v1/chat/completions",
    ),
    ModelProviderDefinition(
        "openrouter", "OpenRouter", "openai", "cloud", "medium", "normal", "frontier",
        128_000, True, True, "https://openrouter.ai/api/v1/chat/completions",
    ),
)


def normalize_provider_id(value: Any) -> str:
    normalized = str(value or "").strip().casefold().replace("_", "-").replace(" ", "-")
    aliases = {
        "claude": "anthropic",
        "google": "gemini",
        "google-gemini": "gemini",
        "lmstudio": "lm-studio",
        "open-router": "openrouter",
        "dashscope": "qwen",
        "auto": "",
    }
    return aliases.get(normalized, normalized)


def infer_provider_id(config: dict[str, Any], *, local: bool = False) -> str:
    explicit = normalize_provider_id(config.get("provider"))
    if explicit:
        return explicit
    endpoint = str(config.get("url") or "").casefold()
    if local:
        if "11434" in endpoint or "/api/generate" in endpoint:
            return "ollama"
        if "1234" in endpoint or "/v1/chat/completions" in endpoint:
            return "lm-studio"
        return "ollama"
    for provider in MODEL_PROVIDER_DEFINITIONS:
        host = provider.endpoint_hint.split("/")[2] if "://" in provider.endpoint_hint else ""
        if host and host in endpoint:
            return provider.provider_id
    return "openai"


@dataclass(frozen=True)
class ProviderPerformance:
    attempts: int = 0
    successes: int = 0
    failures: int = 0
    consecutive_failures: int = 0
    failure_rate: float = 0.0
    ewma_latency_ms: float = 0.0
    last_observed_at_millis: int = 0


@dataclass(frozen=True)
class ProviderPricing:
    tier: str
    input_micros_per_million_tokens: int | None = None
    output_micros_per_million_tokens: int | None = None
    currency: str = "USD"
    source: str = "catalog_tier"


@dataclass(frozen=True)
class ProviderProfile:
    profile_id: str
    resource_id: str
    provider_id: str
    product_id: str
    display_name: str
    kind: str
    location: str
    status: str
    protocol_family: str
    adapter_type: str
    model_id: str
    capabilities: tuple[str, ...]
    tool_ids: tuple[str, ...]
    context_window_tokens: int
    max_output_tokens: int
    max_parallel_runs: int
    supports_tools: bool
    supports_streaming: bool
    supports_background: bool
    latency_tier: str
    quality_tier: str
    trust: str
    failure_domain: str
    endpoint_configured: bool
    credential_configured: bool
    pricing: ProviderPricing
    performance: ProviderPerformance
    schema_version: int = PROFILE_SCHEMA_VERSION
    metadata: dict[str, Any] = field(default_factory=dict)

    def public(self) -> dict[str, Any]:
        return asdict(self)


class ProviderMetricsStore:
    """Durable aggregate observations; never stores prompts, replies, or credentials."""

    def __init__(self, path: Path, clock: Callable[[], int] | None = None):
        self.path = Path(path)
        self.clock = clock or (lambda: int(time.time() * 1000))
        self._lock = threading.RLock()
        self._loaded = False
        self._metrics: dict[str, dict[str, Any]] = {}

    def snapshot(self, resource_id: str) -> ProviderPerformance:
        with self._lock:
            self._load_locked()
            raw = dict(self._metrics.get(str(resource_id or "")) or {})
        attempts = max(0, int(raw.get("attempts") or 0))
        failures = max(0, int(raw.get("failures") or 0))
        successes = max(0, int(raw.get("successes") or 0))
        return ProviderPerformance(
            attempts=attempts,
            successes=successes,
            failures=failures,
            consecutive_failures=max(0, int(raw.get("consecutive_failures") or 0)),
            failure_rate=round(failures / attempts, 6) if attempts else 0.0,
            ewma_latency_ms=round(max(0.0, float(raw.get("ewma_latency_ms") or 0.0)), 3),
            last_observed_at_millis=max(0, int(raw.get("last_observed_at_millis") or 0)),
        )

    def record(self, resource_id: str, *, success: bool, latency_ms: int | float) -> ProviderPerformance:
        key = str(resource_id or "").strip()
        if not key:
            return ProviderPerformance()
        latency = max(0.0, float(latency_ms or 0))
        with self._lock:
            self._load_locked()
            current = dict(self._metrics.get(key) or {})
            attempts = max(0, int(current.get("attempts") or 0)) + 1
            successes = max(0, int(current.get("successes") or 0)) + int(success)
            failures = max(0, int(current.get("failures") or 0)) + int(not success)
            previous_latency = max(0.0, float(current.get("ewma_latency_ms") or 0.0))
            ewma_latency = latency if attempts == 1 else (
                previous_latency * (1.0 - EWMA_ALPHA) + latency * EWMA_ALPHA
            )
            self._metrics[key] = {
                "attempts": attempts,
                "successes": successes,
                "failures": failures,
                "consecutive_failures": 0 if success else max(
                    0, int(current.get("consecutive_failures") or 0)
                ) + 1,
                "ewma_latency_ms": ewma_latency,
                "last_observed_at_millis": int(self.clock()),
            }
            self._persist_locked()
        return self.snapshot(key)

    def _load_locked(self) -> None:
        if self._loaded:
            return
        self._loaded = True
        if not self.path.exists():
            return
        try:
            document = json.loads(self.path.read_text(encoding="utf-8-sig"))
            if int(document.get("schema_version") or 0) != METRICS_SCHEMA_VERSION:
                return
            metrics = document.get("metrics")
            if isinstance(metrics, dict):
                self._metrics = {
                    str(key): dict(value)
                    for key, value in metrics.items()
                    if str(key).strip() and isinstance(value, dict)
                }
        except Exception:
            self._metrics = {}

    def _persist_locked(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.path.with_suffix(f"{self.path.suffix}.tmp")
        temporary.write_text(
            json.dumps(
                {"schema_version": METRICS_SCHEMA_VERSION, "metrics": self._metrics},
                ensure_ascii=False,
                separators=(",", ":"),
            ),
            encoding="utf-8",
        )
        temporary.replace(self.path)


_metrics_store_lock = threading.RLock()
_metrics_store: ProviderMetricsStore | None = None


def _default_metrics_path() -> Path:
    configured = os.environ.get("SIGNALASI_STATE_DIR", "").strip()
    root = Path(configured) if configured else Path(os.environ.get("APPDATA") or Path.home()) / "SignalASI"
    return root / "provider-profile-metrics.json"


def provider_metrics_store() -> ProviderMetricsStore:
    global _metrics_store
    with _metrics_store_lock:
        if _metrics_store is None:
            _metrics_store = ProviderMetricsStore(_default_metrics_path())
        return _metrics_store


def build_provider_profile_catalog(
    agents: Iterable[dict[str, Any]],
    config: dict[str, Any],
    metrics_store: ProviderMetricsStore | None = None,
) -> dict[str, Any]:
    store = metrics_store or provider_metrics_store()
    agent_rows = [dict(agent) for agent in agents if isinstance(agent, dict)]
    agent_statuses = {
        str(agent.get("id") or ""): str(agent.get("status") or "unknown")
        for agent in agent_rows
    }
    cloud_config = dict(config.get("cloud_model") or {})
    local_config = dict(config.get("local_model") or {})
    active_cloud = infer_provider_id(cloud_config)
    active_local = infer_provider_id(local_config, local=True)
    profiles: list[ProviderProfile] = []

    for definition in MODEL_PROVIDER_DEFINITIONS:
        configured = (
            definition.provider_id == active_cloud
            and _configured_model(cloud_config, require_credential=True)
        ) or (
            definition.provider_id == active_local
            and _configured_model(local_config, require_credential=False)
        )
        is_local = definition.location == "private"
        resource_id = (
            "local-llm" if configured and is_local
            else "cloud-model" if configured
            else f"catalog:{definition.provider_id}"
        )
        selected = local_config if configured and is_local else cloud_config if configured else {}
        configured_status = (
            agent_statuses.get(resource_id, "configured")
            if configured else "not_configured"
        )
        profile = ProviderProfile(
            profile_id=f"model:{definition.provider_id}",
            resource_id=resource_id,
            provider_id=definition.provider_id,
            product_id=definition.provider_id,
            display_name=definition.display_name,
            kind="local_model" if is_local else "cloud_model",
            location=definition.location,
            status=configured_status,
            protocol_family=definition.protocol_family,
            adapter_type=f"{definition.protocol_family}-model-api",
            model_id=str(selected.get("model") or ""),
            capabilities=tuple(
                ["conversation", "reasoning"]
                + (["tools", "live_data"] if definition.supports_tools else [])
                + (["local_inference"] if is_local else [])
            ),
            tool_ids=(),
            context_window_tokens=_positive_int(
                selected.get("context_window_tokens"),
                definition.context_window_tokens,
            ),
            max_output_tokens=_positive_int(selected.get("max_output_tokens"), 4_096),
            max_parallel_runs=2 if is_local else 4,
            supports_tools=definition.supports_tools,
            supports_streaming=definition.supports_streaming,
            supports_background=True,
            latency_tier=definition.latency_tier,
            quality_tier=definition.quality_tier,
            trust="private_configured" if is_local else "cloud_configured",
            failure_domain=(
                f"private-model:{definition.provider_id}"
                if is_local else f"cloud-model:{definition.provider_id}"
            ),
            endpoint_configured=bool(str(selected.get("url") or "").strip()),
            credential_configured=(
                True if is_local and not str(selected.get("api_key") or "").strip()
                else bool(str(selected.get("api_key") or "").strip())
            ),
            pricing=ProviderPricing(tier=definition.cost_tier),
            performance=store.snapshot(resource_id),
            metadata={
                "endpoint_hint": definition.endpoint_hint,
                "configuration_role": "local_model" if is_local else "cloud_model",
            },
        )
        profiles.append(profile)

    for agent in agent_rows:
        resource_id = str(agent.get("id") or "").strip()
        if not resource_id or resource_id in {"cloud-model", "local-llm"}:
            continue
        capabilities = tuple(sorted({
            str(value).strip()
            for value in agent.get("capabilities") or []
            if str(value).strip()
        }))
        adapter = agent.get("adapter") if isinstance(agent.get("adapter"), dict) else {}
        profiles.append(ProviderProfile(
            profile_id=f"agent:{resource_id}",
            resource_id=resource_id,
            provider_id=resource_id,
            product_id=resource_id,
            display_name=str(agent.get("name") or resource_id),
            kind="agent",
            location="trusted_desktop",
            status=str(agent.get("status") or "unknown"),
            protocol_family="signalasi-agent-adapter",
            adapter_type=str(adapter.get("adapter_type") or agent.get("kind") or "native-agent"),
            model_id="",
            capabilities=capabilities,
            tool_ids=(),
            context_window_tokens=64_000,
            max_output_tokens=16_000,
            max_parallel_runs=max(1, int(adapter.get("max_parallel_runs") or 1)),
            supports_tools=bool({"tools", "terminal", "files", "tasks"} & set(capabilities)),
            supports_streaming=bool(adapter.get("streaming", True)),
            supports_background=bool({"tasks", "automation"} & set(capabilities)),
            latency_tier="normal",
            quality_tier="strong",
            trust="verified_paired",
            failure_domain=str(adapter.get("failure_domain") or f"desktop-agent:{resource_id}"),
            endpoint_configured=True,
            credential_configured=True,
            pricing=ProviderPricing(tier="free"),
            performance=store.snapshot(resource_id),
            metadata={
                "native_product_identity": resource_id,
                "independently_upgradeable": bool(adapter.get("independently_upgradeable", True)),
            },
        ))

    profiles.sort(key=lambda item: (item.kind, item.display_name.casefold(), item.profile_id))
    configured_profiles = sum(profile.status in ROUTABLE_PROVIDER_STATUSES for profile in profiles)
    return {
        "schema_version": PROFILE_SCHEMA_VERSION,
        "profiles": [profile.public() for profile in profiles],
        "summary": {
            "total": len(profiles),
            "configured": configured_profiles,
            "model_providers": len(MODEL_PROVIDER_DEFINITIONS),
            "agents": sum(profile.kind == "agent" for profile in profiles),
        },
        "generated_at_millis": int(time.time() * 1000),
    }


def routable_model_profiles(catalog: dict[str, Any]) -> list[dict[str, Any]]:
    return [
        dict(profile)
        for profile in catalog.get("profiles") or []
        if isinstance(profile, dict)
        and profile.get("kind") in {"local_model", "cloud_model"}
        and str(profile.get("status") or "") in ROUTABLE_PROVIDER_STATUSES
    ]


def _configured_model(config: dict[str, Any], *, require_credential: bool) -> bool:
    if not str(config.get("model") or "").strip():
        return False
    if require_credential and not str(config.get("api_key") or "").strip():
        return False
    return bool(str(config.get("url") or "").strip()) or not require_credential


def _positive_int(value: Any, default: int) -> int:
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        parsed = default
    return max(0, parsed)
