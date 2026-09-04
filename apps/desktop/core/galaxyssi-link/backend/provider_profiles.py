"""Unified routing profiles for model providers and native Agent products."""
from __future__ import annotations

import json
import math
import os
import threading
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Callable, Iterable


PROFILE_SCHEMA_VERSION = 1
METRICS_SCHEMA_VERSION = 2
EWMA_ALPHA = 0.25
LATENCY_SAMPLE_LIMIT = 128
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
    latency_observations: int = 0
    last_latency_ms: float = 0.0
    average_latency_ms: float = 0.0
    ewma_latency_ms: float = 0.0
    min_latency_ms: float = 0.0
    max_latency_ms: float = 0.0
    p50_latency_ms: float = 0.0
    p95_latency_ms: float = 0.0
    usage_observations: int = 0
    estimated_usage_observations: int = 0
    input_tokens: int = 0
    output_tokens: int = 0
    total_tokens: int = 0
    average_input_tokens: float = 0.0
    average_output_tokens: float = 0.0
    max_input_tokens: int = 0
    max_context_utilization: float = 0.0
    priced_attempts: int = 0
    unpriced_attempts: int = 0
    total_cost_micros: int = 0
    average_cost_micros: float = 0.0
    last_cost_micros: int | None = None
    cost_currency: str = "USD"
    tool_observations: int = 0
    tool_calls: int = 0
    tool_failures: int = 0
    tool_failure_rate: float = 0.0
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
        latency_observations = max(0, int(raw.get("latency_observations") or 0))
        latency_total = _nonnegative_float(raw.get("latency_total_ms"))
        latency_samples = _latency_samples(raw.get("latency_samples"))
        usage_observations = max(0, int(raw.get("usage_observations") or 0))
        input_tokens = _nonnegative_int(raw.get("input_tokens"))
        output_tokens = _nonnegative_int(raw.get("output_tokens"))
        priced_attempts = max(0, int(raw.get("priced_attempts") or 0))
        total_cost_micros = _nonnegative_int(raw.get("total_cost_micros"))
        tool_calls = _nonnegative_int(raw.get("tool_calls"))
        tool_failures = min(tool_calls, _nonnegative_int(raw.get("tool_failures")))
        return ProviderPerformance(
            attempts=attempts,
            successes=successes,
            failures=failures,
            consecutive_failures=max(0, int(raw.get("consecutive_failures") or 0)),
            failure_rate=round(failures / attempts, 6) if attempts else 0.0,
            latency_observations=latency_observations,
            last_latency_ms=round(_nonnegative_float(raw.get("last_latency_ms")), 3),
            average_latency_ms=round(
                latency_total / latency_observations if latency_observations else 0.0,
                3,
            ),
            ewma_latency_ms=round(_nonnegative_float(raw.get("ewma_latency_ms")), 3),
            min_latency_ms=round(_nonnegative_float(raw.get("min_latency_ms")), 3),
            max_latency_ms=round(_nonnegative_float(raw.get("max_latency_ms")), 3),
            p50_latency_ms=round(_percentile(latency_samples, 0.50), 3),
            p95_latency_ms=round(_percentile(latency_samples, 0.95), 3),
            usage_observations=usage_observations,
            estimated_usage_observations=max(
                0,
                int(raw.get("estimated_usage_observations") or 0),
            ),
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            total_tokens=input_tokens + output_tokens,
            average_input_tokens=round(
                input_tokens / usage_observations if usage_observations else 0.0,
                3,
            ),
            average_output_tokens=round(
                output_tokens / usage_observations if usage_observations else 0.0,
                3,
            ),
            max_input_tokens=_nonnegative_int(raw.get("max_input_tokens")),
            max_context_utilization=round(
                _nonnegative_float(raw.get("max_context_utilization")),
                6,
            ),
            priced_attempts=priced_attempts,
            unpriced_attempts=max(0, int(raw.get("unpriced_attempts") or 0)),
            total_cost_micros=total_cost_micros,
            average_cost_micros=round(
                total_cost_micros / priced_attempts if priced_attempts else 0.0,
                3,
            ),
            last_cost_micros=(
                _nonnegative_int(raw.get("last_cost_micros"))
                if raw.get("last_cost_micros") is not None
                else None
            ),
            cost_currency=_currency(raw.get("cost_currency")),
            tool_observations=max(0, int(raw.get("tool_observations") or 0)),
            tool_calls=tool_calls,
            tool_failures=tool_failures,
            tool_failure_rate=round(tool_failures / tool_calls, 6) if tool_calls else 0.0,
            last_observed_at_millis=max(0, int(raw.get("last_observed_at_millis") or 0)),
        )

    def record(
        self,
        resource_id: str,
        *,
        success: bool,
        latency_ms: int | float,
        input_tokens: int | None = None,
        output_tokens: int | None = None,
        cost_micros: int | None = None,
        cost_currency: str = "USD",
        usage_estimated: bool = False,
        context_window_tokens: int | None = None,
        tool_calls: int | None = None,
        tool_failures: int | None = None,
    ) -> ProviderPerformance:
        key = str(resource_id or "").strip()
        if not key:
            return ProviderPerformance()
        latency = _nonnegative_float(latency_ms)
        observed_input_tokens = (
            _nonnegative_int(input_tokens) if input_tokens is not None else None
        )
        observed_output_tokens = (
            _nonnegative_int(output_tokens) if output_tokens is not None else None
        )
        observed_cost_micros = (
            _nonnegative_int(cost_micros) if cost_micros is not None else None
        )
        observed_tool_calls = (
            _nonnegative_int(tool_calls) if tool_calls is not None else None
        )
        observed_tool_failures = (
            min(
                observed_tool_calls or 0,
                _nonnegative_int(tool_failures),
            )
            if tool_calls is not None
            else None
        )
        with self._lock:
            self._load_locked()
            current = dict(self._metrics.get(key) or {})
            attempts = max(0, int(current.get("attempts") or 0)) + 1
            successes = max(0, int(current.get("successes") or 0)) + int(success)
            failures = max(0, int(current.get("failures") or 0)) + int(not success)
            latency_observations = max(0, int(current.get("latency_observations") or 0)) + 1
            previous_latency = _nonnegative_float(current.get("ewma_latency_ms"))
            ewma_latency = latency if latency_observations == 1 else (
                previous_latency * (1.0 - EWMA_ALPHA) + latency * EWMA_ALPHA
            )
            latency_samples = _latency_samples(current.get("latency_samples"))
            latency_samples.append(latency)
            latency_samples = latency_samples[-LATENCY_SAMPLE_LIMIT:]
            usage_observed = input_tokens is not None or output_tokens is not None
            usage_observations = max(0, int(current.get("usage_observations") or 0))
            estimated_usage_observations = max(
                0,
                int(current.get("estimated_usage_observations") or 0),
            )
            input_total = _nonnegative_int(current.get("input_tokens"))
            output_total = _nonnegative_int(current.get("output_tokens"))
            max_input_tokens = _nonnegative_int(current.get("max_input_tokens"))
            max_context_utilization = _nonnegative_float(
                current.get("max_context_utilization")
            )
            if usage_observed:
                usage_observations += 1
                input_total += observed_input_tokens or 0
                output_total += observed_output_tokens or 0
                max_input_tokens = max(max_input_tokens, observed_input_tokens or 0)
                estimated_usage_observations += int(usage_estimated)
                context_window = _nonnegative_int(context_window_tokens)
                if context_window > 0 and observed_input_tokens is not None:
                    max_context_utilization = max(
                        max_context_utilization,
                        min(10.0, observed_input_tokens / context_window),
                    )
            priced_attempts = max(0, int(current.get("priced_attempts") or 0))
            unpriced_attempts = max(0, int(current.get("unpriced_attempts") or 0))
            total_cost_micros = _nonnegative_int(current.get("total_cost_micros"))
            current_currency = _currency(current.get("cost_currency"))
            observed_currency = _currency(cost_currency)
            if observed_cost_micros is None:
                unpriced_attempts += 1
            else:
                if priced_attempts > 0 and current_currency != observed_currency:
                    priced_attempts = 0
                    total_cost_micros = 0
                priced_attempts += 1
                total_cost_micros += observed_cost_micros
            tool_observations = max(0, int(current.get("tool_observations") or 0))
            tool_call_total = _nonnegative_int(current.get("tool_calls"))
            tool_failure_total = _nonnegative_int(current.get("tool_failures"))
            if observed_tool_calls is not None:
                tool_observations += 1
                tool_call_total += observed_tool_calls
                tool_failure_total += observed_tool_failures or 0
            self._metrics[key] = {
                "attempts": attempts,
                "successes": successes,
                "failures": failures,
                "consecutive_failures": 0 if success else max(
                    0, int(current.get("consecutive_failures") or 0)
                ) + 1,
                "latency_observations": latency_observations,
                "last_latency_ms": latency,
                "latency_total_ms": (
                    _nonnegative_float(current.get("latency_total_ms")) + latency
                ),
                "ewma_latency_ms": ewma_latency,
                "min_latency_ms": (
                    latency
                    if latency_observations == 1
                    else min(_nonnegative_float(current.get("min_latency_ms")), latency)
                ),
                "max_latency_ms": max(
                    _nonnegative_float(current.get("max_latency_ms")),
                    latency,
                ),
                "latency_samples": latency_samples,
                "usage_observations": usage_observations,
                "estimated_usage_observations": estimated_usage_observations,
                "input_tokens": input_total,
                "output_tokens": output_total,
                "max_input_tokens": max_input_tokens,
                "max_context_utilization": max_context_utilization,
                "priced_attempts": priced_attempts,
                "unpriced_attempts": unpriced_attempts,
                "total_cost_micros": total_cost_micros,
                "last_cost_micros": observed_cost_micros,
                "cost_currency": (
                    observed_currency if observed_cost_micros is not None
                    else current_currency
                ),
                "tool_observations": tool_observations,
                "tool_calls": tool_call_total,
                "tool_failures": min(tool_call_total, tool_failure_total),
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
    configured = os.environ.get("GALAXYSSI_STATE_DIR", "").strip()
    root = Path(configured) if configured else Path(os.environ.get("APPDATA") or Path.home()) / "GalaxySSI"
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
        metrics_key = f"model:{definition.provider_id}"
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
            pricing=_provider_pricing(selected, definition.cost_tier),
            performance=store.snapshot(metrics_key),
            metadata={
                "endpoint_hint": definition.endpoint_hint,
                "configuration_role": "local_model" if is_local else "cloud_model",
                "metrics_key": metrics_key,
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
        metrics_key = f"agent:{resource_id}"
        profiles.append(ProviderProfile(
            profile_id=f"agent:{resource_id}",
            resource_id=resource_id,
            provider_id=resource_id,
            product_id=resource_id,
            display_name=str(agent.get("name") or resource_id),
            kind="agent",
            location="trusted_desktop",
            status=str(agent.get("status") or "unknown"),
            protocol_family="galaxyssi-agent-adapter",
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
            performance=store.snapshot(metrics_key),
            metadata={
                "native_product_identity": resource_id,
                "independently_upgradeable": bool(adapter.get("independently_upgradeable", True)),
                "metrics_key": metrics_key,
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


def _provider_pricing(config: dict[str, Any], default_tier: str) -> ProviderPricing:
    input_price = _optional_nonnegative_int(config.get("input_micros_per_million_tokens"))
    output_price = _optional_nonnegative_int(config.get("output_micros_per_million_tokens"))
    configured = input_price is not None or output_price is not None
    return ProviderPricing(
        tier=default_tier,
        input_micros_per_million_tokens=input_price,
        output_micros_per_million_tokens=output_price,
        currency=_currency(config.get("pricing_currency")),
        source="configured" if configured else "catalog_tier",
    )


def estimate_provider_cost_micros(
    input_tokens: int,
    output_tokens: int,
    pricing: ProviderPricing,
) -> int | None:
    if (
        pricing.input_micros_per_million_tokens is None
        or pricing.output_micros_per_million_tokens is None
    ):
        return None
    numerator = (
        _nonnegative_int(input_tokens) * pricing.input_micros_per_million_tokens
        + _nonnegative_int(output_tokens) * pricing.output_micros_per_million_tokens
    )
    return max(0, int(round(numerator / 1_000_000)))


def _latency_samples(value: Any) -> list[float]:
    if not isinstance(value, list):
        return []
    return [
        _nonnegative_float(item)
        for item in value[-LATENCY_SAMPLE_LIMIT:]
        if _finite_number(item)
    ]


def _percentile(samples: list[float], quantile: float) -> float:
    if not samples:
        return 0.0
    ordered = sorted(samples)
    rank = max(0, min(len(ordered) - 1, math.ceil(quantile * len(ordered)) - 1))
    return ordered[rank]


def _finite_number(value: Any) -> bool:
    try:
        return math.isfinite(float(value))
    except (TypeError, ValueError):
        return False


def _nonnegative_float(value: Any) -> float:
    if not _finite_number(value):
        return 0.0
    return max(0.0, float(value))


def _nonnegative_int(value: Any) -> int:
    try:
        return max(0, int(value or 0))
    except (TypeError, ValueError, OverflowError):
        return 0


def _optional_nonnegative_int(value: Any) -> int | None:
    if value is None or str(value).strip() == "":
        return None
    return _nonnegative_int(value)


def _currency(value: Any) -> str:
    normalized = str(value or "USD").strip().upper()
    return normalized if len(normalized) == 3 and normalized.isalpha() else "USD"
