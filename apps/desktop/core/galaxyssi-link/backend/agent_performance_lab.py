"""Comparable, privacy-preserving performance reports for core Agents."""
from __future__ import annotations

import json
import math
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable


REPORT_SCHEMA_VERSION = 1
CORE_AGENT_DEFINITIONS: tuple[tuple[str, str], ...] = (
    ("codex", "Codex"),
    ("claude", "Claude Code"),
    ("hermes", "Hermes"),
    ("openclaw", "OpenClaw"),
)
WINDOW_SECONDS = {
    "24h": 24 * 60 * 60,
    "7d": 7 * 24 * 60 * 60,
    "30d": 30 * 24 * 60 * 60,
    "all": None,
}
AVAILABLE_STATUSES = frozenset({"ready", "busy", "degraded"})


def build_agent_performance_report(
    *,
    window: str,
    agents: Iterable[dict[str, Any]],
    execution_log_path: Path,
    now: datetime | None = None,
) -> dict[str, Any]:
    normalized_window = str(window or "7d").strip().lower()
    if normalized_window not in WINDOW_SECONDS:
        raise ValueError(f"Unsupported performance window: {window}")

    observed_at = _as_utc(now or datetime.now(timezone.utc))
    window_seconds = WINDOW_SECONDS[normalized_window]
    started_at = (
        observed_at - timedelta(seconds=window_seconds)
        if window_seconds is not None
        else None
    )
    status_by_id = {
        str(agent.get("id") or ""): dict(agent)
        for agent in agents
        if isinstance(agent, dict)
    }
    entries, invalid_entries = _read_execution_entries(Path(execution_log_path))
    samples_by_agent: dict[str, list[dict[str, Any]]] = {
        agent_id: [] for agent_id, _ in CORE_AGENT_DEFINITIONS
    }
    earliest_sample: datetime | None = None
    latest_sample: datetime | None = None

    for entry in entries:
        agent_id = str(entry.get("contact_id") or "").strip().lower()
        if agent_id not in samples_by_agent:
            continue
        timestamp = _parse_timestamp(entry.get("ts"))
        if timestamp is None or (started_at is not None and timestamp < started_at):
            continue
        normalized = {
            "timestamp": timestamp,
            "duration_ms": _nonnegative_float(entry.get("duration_ms")),
            "ok": bool(entry.get("ok")) and not bool(str(entry.get("error") or "").strip()),
        }
        samples_by_agent[agent_id].append(normalized)
        earliest_sample = timestamp if earliest_sample is None else min(earliest_sample, timestamp)
        latest_sample = timestamp if latest_sample is None else max(latest_sample, timestamp)

    rows = [
        _agent_row(
            agent_id=agent_id,
            display_name=display_name,
            status=status_by_id.get(agent_id, {}),
            samples=samples_by_agent[agent_id],
        )
        for agent_id, display_name in CORE_AGENT_DEFINITIONS
    ]
    _rank_rows(rows)
    total_attempts = sum(row["attempts"] for row in rows)
    total_successes = sum(row["successes"] for row in rows)
    measured = [row for row in rows if row["attempts"] > 0]
    ranked = sorted(
        (row for row in rows if row["rank"] is not None),
        key=lambda row: row["rank"],
    )
    fastest = min(
        (row for row in measured if row["successful_latency_observations"] > 0),
        key=lambda row: (row["p50_latency_ms"], row["p95_latency_ms"]),
        default=None,
    )
    reliable = max(
        measured,
        key=lambda row: (
            row["success_rate"],
            row["attempts"],
            -row["p95_latency_ms"],
        ),
        default=None,
    )
    return {
        "schema_version": REPORT_SCHEMA_VERSION,
        "window": {
            "id": normalized_window,
            "seconds": window_seconds,
            "started_at": started_at.isoformat() if started_at else None,
            "ended_at": observed_at.isoformat(),
        },
        "summary": {
            "agents": len(rows),
            "available_agents": sum(row["available"] for row in rows),
            "measured_agents": len(measured),
            "attempts": total_attempts,
            "successes": total_successes,
            "failures": max(0, total_attempts - total_successes),
            "success_rate": round(total_successes / total_attempts, 6) if total_attempts else None,
            "recommended_agent_id": ranked[0]["agent_id"] if ranked else None,
            "fastest_agent_id": fastest["agent_id"] if fastest else None,
            "most_reliable_agent_id": reliable["agent_id"] if reliable else None,
        },
        "agents": rows,
        "evidence": {
            "source": "local_anonymous_execution_metrics",
            "retention": "current_and_previous_log_segment",
            "earliest_sample_at": earliest_sample.isoformat() if earliest_sample else None,
            "latest_sample_at": latest_sample.isoformat() if latest_sample else None,
            "invalid_entries": invalid_entries,
            "contains_prompt_or_reply_content": False,
        },
        "generated_at": observed_at.isoformat(),
    }


def current_agent_performance_report(window: str = "7d") -> dict[str, Any]:
    from agent_gateway import BASE_AGENTS, _execution_log_path, agent_status

    core_agents = [
        agent_status(BASE_AGENTS[agent_id], quick=True)
        for agent_id, _ in CORE_AGENT_DEFINITIONS
    ]

    return build_agent_performance_report(
        window=window,
        agents=core_agents,
        execution_log_path=_execution_log_path(),
    )


def _read_execution_entries(path: Path) -> tuple[list[dict[str, Any]], int]:
    entries: list[dict[str, Any]] = []
    invalid_entries = 0
    sources = (path.with_suffix(f"{path.suffix}.1"), path)
    for source in sources:
        if not source.is_file():
            continue
        try:
            lines = source.read_text(encoding="utf-8-sig").splitlines()
        except (OSError, UnicodeError):
            invalid_entries += 1
            continue
        for line in lines:
            if not line.strip():
                continue
            try:
                entry = json.loads(line)
            except (TypeError, ValueError):
                invalid_entries += 1
                continue
            if not isinstance(entry, dict):
                invalid_entries += 1
                continue
            entries.append(entry)
    return entries, invalid_entries


def _agent_row(
    *,
    agent_id: str,
    display_name: str,
    status: dict[str, Any],
    samples: list[dict[str, Any]],
) -> dict[str, Any]:
    attempts = len(samples)
    successes = sum(bool(sample["ok"]) for sample in samples)
    successful_latencies = sorted(
        sample["duration_ms"] for sample in samples if sample["ok"]
    )
    raw_status = str(status.get("status") or "unknown")
    available = raw_status in AVAILABLE_STATUSES
    if attempts:
        measurement_state = "measured"
    elif not available:
        measurement_state = "unavailable"
    else:
        measurement_state = "no_data"
    return {
        "agent_id": agent_id,
        "display_name": str(status.get("name") or display_name),
        "availability_status": raw_status,
        "available": available,
        "runtime_status": str(status.get("runtime_status") or "unknown"),
        "active_tasks": max(0, _integer(status.get("active_tasks"))),
        "measurement_state": measurement_state,
        "attempts": attempts,
        "successes": successes,
        "failures": max(0, attempts - successes),
        "success_rate": round(successes / attempts, 6) if attempts else None,
        "successful_latency_observations": len(successful_latencies),
        "average_latency_ms": round(
            sum(successful_latencies) / len(successful_latencies), 3
        ) if successful_latencies else None,
        "p50_latency_ms": _percentile(successful_latencies, 0.50),
        "p95_latency_ms": _percentile(successful_latencies, 0.95),
        "max_latency_ms": round(max(successful_latencies), 3) if successful_latencies else None,
        "latest_sample_at": max(
            (sample["timestamp"] for sample in samples),
            default=None,
        ).isoformat() if samples else None,
        "confidence": _confidence(attempts),
        "rank": None,
    }


def _rank_rows(rows: list[dict[str, Any]]) -> None:
    eligible = [
        row for row in rows
        if row["available"] and row["attempts"] > 0
    ]
    eligible.sort(
        key=lambda row: (
            -row["success_rate"],
            row["p95_latency_ms"] if row["p95_latency_ms"] is not None else math.inf,
            row["p50_latency_ms"] if row["p50_latency_ms"] is not None else math.inf,
            -row["attempts"],
            row["agent_id"],
        )
    )
    for rank, row in enumerate(eligible, start=1):
        row["rank"] = rank


def _confidence(attempts: int) -> str:
    if attempts <= 0:
        return "none"
    if attempts < 5:
        return "insufficient"
    if attempts < 20:
        return "indicative"
    return "established"


def _parse_timestamp(value: Any) -> datetime | None:
    raw = str(value or "").strip()
    if not raw:
        return None
    try:
        parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None
    return _as_utc(parsed)


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _nonnegative_float(value: Any) -> float:
    try:
        return max(0.0, float(value or 0))
    except (TypeError, ValueError):
        return 0.0


def _integer(value: Any) -> int:
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


def _percentile(values: list[float], quantile: float) -> float | None:
    if not values:
        return None
    if len(values) == 1:
        return round(values[0], 3)
    position = (len(values) - 1) * quantile
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return round(values[lower], 3)
    fraction = position - lower
    return round(values[lower] + (values[upper] - values[lower]) * fraction, 3)
