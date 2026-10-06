"""Content-free Codex usage observations; notifications are not request receipts."""
from __future__ import annotations

import logging
import re


log = logging.getLogger(__name__)
CONTRACT = "galaxyssi.codex-provider-usage/1"
MAX_COUNTER = 2**53 - 1
COUNTERS = {
    "inputTokens": "input_tokens",
    "cachedInputTokens": "cached_input_tokens",
    "cacheWriteInputTokens": "cache_write_input_tokens",
    "outputTokens": "output_tokens",
    "reasoningOutputTokens": "reasoning_output_tokens",
    "totalTokens": "total_tokens",
}
KINDS = frozenset({"usage_snapshot", "turn_started", "turn_terminal", "model_rerouted"})


def identifier(value) -> bool:
    return isinstance(value, str) and bool(value.strip()) and len(value) <= 200


def normalize(params: dict, *, model: str, effort: str, kind="usage_snapshot", status="") -> dict | None:
    if (not isinstance(params, dict) or not identifier(params.get("threadId"))
            or not identifier(params.get("turnId")) or not identifier(model)
            or not identifier(effort) or not isinstance(kind, str)
            or kind not in KINDS):
        return None
    result = {"contract": CONTRACT, "provider": "codex", "kind": kind,
              "provider_thread_id": params["threadId"], "provider_turn_id": params["turnId"],
              "requested_model": model, "requested_reasoning_effort": effort,
              "actual_model": None, "request_count": None, "billed_cost": None}
    if kind == "model_rerouted":
        issues = []
        for field, name in (("fromModel", "reported_from_model"), ("toModel", "reported_to_model")):
            value = params.get(field)
            valid = isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}", value) is not None
            result[name] = value if valid else None
            if not valid:
                issues.append(field + ":invalid_or_missing_model")
        result["issues"] = issues
        # This notification establishes a reported change, not a whole-turn model identity.
        result["model_scope"] = "provider_reported_reroute_not_served_model_attestation"
        return result
    if kind != "usage_snapshot":
        if kind == "turn_terminal":
            result["provider_status"] = status if isinstance(status, str) and status in {
                "completed", "failed", "interrupted"} else "unknown"
        return result
    issues = []

    def counter(value, name, *, optional=False):
        if type(value) is int and 0 <= value <= MAX_COUNTER:
            return value
        if value is not None or not optional:
            issues.append(name + ":invalid_or_missing_counter")
        return None

    usage = params.get("tokenUsage")
    if not isinstance(usage, dict):
        issues.append("tokenUsage:invalid_or_missing_object")
        usage = {}
    for key in ("total", "last"):
        value = usage.get(key)
        if not isinstance(value, dict):
            issues.append(key + ":invalid_or_missing_object")
            value = {}
        counts = {name: counter(value.get(field), key + "." + field,
                               optional=field == "cacheWriteInputTokens") for field, name in COUNTERS.items()}
        for part, whole in (("cached_input_tokens", "input_tokens"), ("reasoning_output_tokens", "output_tokens")):
            if counts[part] is not None and counts[whole] is not None and counts[part] > counts[whole]:
                issues.append(key + "." + part + ":exceeds_parent_counter")
        result[key] = counts
    result["model_context_window"] = counter(usage.get("modelContextWindow"), "modelContextWindow", optional=True)
    result["issues"] = issues
    result["total_scope"] = "provider_thread_cumulative_not_task_total"
    result["last_scope"] = "provider_last_usage_snapshot_not_unique_response"
    return result


def capture(mutations, event: dict) -> dict | None:
    """No UI mutation, retry, model call or task resurrection on audit failure."""
    observation = event.get("provider_usage")
    if not isinstance(observation, dict) or observation.get("contract") != CONTRACT:
        return None
    try:
        snapshot = mutations.snapshot()
        if snapshot is None:
            return None
        return mutations.manager.provider_usage.record(snapshot, observation)
    except Exception:
        log.warning("Codex provider usage was not durably recorded; coverage remains incomplete")
        return None
