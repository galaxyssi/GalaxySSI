"""Content-free latency tracing for voice and remote Agent diagnostics."""
from __future__ import annotations

import json
import math
import os
import platform
import threading
import time
import uuid
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Callable, Iterable, Protocol


VOICE_LATENCY_TRACE_FLAG = "GALAXYSSI_VOICE_LATENCY_TRACING_V1"
VOICE_LATENCY_SCHEMA = "galaxyssi.voice-latency/1.0"
DEFAULT_TRACE_PATH = Path.home() / ".galaxyssi" / "diagnostics" / "voice_latency_v1.jsonl"
MAX_TRACE_BYTES = 2 * 1024 * 1024
MAX_SNAPSHOT_EVENTS = 8_000


class VoiceTraceEvents:
    AGENT_QUEUE_ENTERED = "agent_queue_entered"
    AGENT_RUN_STARTED = "agent_run_started"
    AGENT_FIRST_PROGRESS = "agent_first_progress"
    AGENT_FIRST_PARTIAL_RESULT = "agent_first_partial_result"
    AGENT_COMPLETED = "agent_completed"


@dataclass(frozen=True)
class VoiceTraceEvent:
    trace_id: str
    session_id: str
    event: str
    elapsed_realtime_ns: int
    wall_clock_ms: int
    attributes: dict[str, str]


class VoiceTraceEventSink(Protocol):
    def append(self, event: VoiceTraceEvent) -> None: ...

    def snapshot(self) -> list[VoiceTraceEvent]: ...


class InMemoryVoiceTraceEventSink:
    def __init__(self) -> None:
        self._events: list[VoiceTraceEvent] = []
        self._lock = threading.Lock()

    def append(self, event: VoiceTraceEvent) -> None:
        with self._lock:
            self._events.append(event)

    def snapshot(self) -> list[VoiceTraceEvent]:
        with self._lock:
            return list(self._events)


class JsonlVoiceTraceEventSink:
    def __init__(self, path: Path = DEFAULT_TRACE_PATH) -> None:
        self.path = Path(path)
        self.rotated_path = self.path.with_suffix(".previous.jsonl")
        self._lock = threading.Lock()

    def append(self, event: VoiceTraceEvent) -> None:
        encoded = json.dumps(asdict(event), ensure_ascii=True, separators=(",", ":"))
        with self._lock:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            if self.path.is_file() and self.path.stat().st_size >= MAX_TRACE_BYTES:
                self.rotated_path.unlink(missing_ok=True)
                self.path.replace(self.rotated_path)
            with self.path.open("a", encoding="utf-8", newline="\n") as stream:
                stream.write(encoded + "\n")

    def snapshot(self) -> list[VoiceTraceEvent]:
        events: list[VoiceTraceEvent] = []
        with self._lock:
            for source in (self.rotated_path, self.path):
                if not source.is_file():
                    continue
                with source.open("r", encoding="utf-8") as stream:
                    for line in stream:
                        try:
                            raw = json.loads(line)
                            events.append(VoiceTraceEvent(
                                trace_id=str(raw["trace_id"]),
                                session_id=str(raw.get("session_id") or raw["trace_id"]),
                                event=str(raw["event"]),
                                elapsed_realtime_ns=max(0, int(raw["elapsed_realtime_ns"])),
                                wall_clock_ms=max(0, int(raw["wall_clock_ms"])),
                                attributes=sanitize_attributes(raw.get("attributes") or {}),
                            ))
                        except (KeyError, TypeError, ValueError, json.JSONDecodeError):
                            continue
        return events[-MAX_SNAPSHOT_EVENTS:]


_ALLOWED_ATTRIBUTE_KEYS = {
    "agent_provider",
    "app_version",
    "cold_start",
    "error_code",
    "fallback",
    "queue_depth",
    "retry_count",
    "success",
    "task_status",
    "transport",
}
_NUMERIC_ATTRIBUTE_KEYS = {"queue_depth", "retry_count"}
_BOOLEAN_ATTRIBUTE_KEYS = {"cold_start", "fallback", "success"}
_IDENTIFIER_CHARS = frozenset("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-")
_EVENT_CHARS = frozenset("abcdefghijklmnopqrstuvwxyz0123456789_")
_TECHNICAL_VALUE_CHARS = _IDENTIFIER_CHARS | frozenset(" +")


def _bounded_safe_value(value: object, allowed: frozenset[str], limit: int) -> str | None:
    candidate = str(value or "").strip()
    if not candidate or len(candidate) > limit or any(char not in allowed for char in candidate):
        return None
    return candidate


def safe_identifier(value: object) -> str | None:
    return _bounded_safe_value(value, _IDENTIFIER_CHARS, 128)


def safe_event(value: object) -> str | None:
    candidate = _bounded_safe_value(str(value or "").lower(), _EVENT_CHARS, 96)
    return candidate if candidate and candidate[0].isalpha() else None


def sanitize_attributes(attributes: dict | None) -> dict[str, str]:
    sanitized: dict[str, str] = {}
    for raw_key, raw_value in dict(attributes or {}).items():
        key = str(raw_key or "").strip().lower()
        if key not in _ALLOWED_ATTRIBUTE_KEYS:
            continue
        value = str(raw_value or "").strip()
        if key in _NUMERIC_ATTRIBUTE_KEYS:
            try:
                number = float(value)
            except (TypeError, ValueError):
                continue
            if not math.isfinite(number):
                continue
            sanitized[key] = value
        elif key in _BOOLEAN_ATTRIBUTE_KEYS:
            normalized = value.lower()
            if normalized in {"true", "false"}:
                sanitized[key] = normalized
        else:
            safe_value = _bounded_safe_value(value, _TECHNICAL_VALUE_CHARS, 120)
            if safe_value is not None:
                sanitized[key] = safe_value
    return sanitized


def latency_tracing_enabled() -> bool:
    value = str(os.environ.get(VOICE_LATENCY_TRACE_FLAG, "1")).strip().lower()
    return value not in {"0", "false", "no", "off", "disabled"}


class VoiceLatencyTracer:
    def __init__(
        self,
        *,
        monotonic_ns: Callable[[], int] = time.monotonic_ns,
        wall_clock_ms: Callable[[], int] = lambda: int(time.time() * 1000),
        enabled: Callable[[], bool] = latency_tracing_enabled,
        sink: VoiceTraceEventSink | None = None,
    ) -> None:
        self._monotonic_ns = monotonic_ns
        self._wall_clock_ms = wall_clock_ms
        self._enabled = enabled
        self._sink = sink or InMemoryVoiceTraceEventSink()
        self._once_keys: dict[tuple[str, str], None] = {}
        self._lock = threading.Lock()

    def start_session(self, attributes: dict | None = None) -> str:
        trace_id = uuid.uuid4().hex
        self.record(trace_id, "voice_session_created", attributes, once=True)
        return trace_id

    def record(
        self,
        trace_id: str,
        event: str,
        attributes: dict | None = None,
        *,
        session_id: str = "",
        once: bool = False,
    ) -> VoiceTraceEvent | None:
        if not self._enabled():
            return None
        safe_trace_id = safe_identifier(trace_id)
        safe_session_id = safe_identifier(session_id) or safe_trace_id
        safe_event_name = safe_event(event)
        if safe_trace_id is None or safe_session_id is None or safe_event_name is None:
            return None
        if once:
            key = (safe_trace_id, safe_event_name)
            with self._lock:
                if key in self._once_keys:
                    return None
                self._once_keys[key] = None
                if len(self._once_keys) > 32_000:
                    for stale_key in tuple(self._once_keys)[:8_000]:
                        self._once_keys.pop(stale_key, None)
        trace_event = VoiceTraceEvent(
            trace_id=safe_trace_id,
            session_id=safe_session_id,
            event=safe_event_name,
            elapsed_realtime_ns=max(0, int(self._monotonic_ns())),
            wall_clock_ms=max(0, int(self._wall_clock_ms())),
            attributes=sanitize_attributes(attributes),
        )
        self._sink.append(trace_event)
        return trace_event

    def snapshot(self) -> list[VoiceTraceEvent]:
        return self._sink.snapshot()

    def elapsed_ms(self, trace_id: str, start_event: str, end_event: str) -> int | None:
        ordered = sorted(
            (event for event in self.snapshot() if event.trace_id == trace_id),
            key=lambda event: event.elapsed_realtime_ns,
        )
        started = next((event.elapsed_realtime_ns for event in ordered if event.event == start_event), None)
        if started is None:
            return None
        completed = next((
            event.elapsed_realtime_ns
            for event in ordered
            if event.event == end_event and event.elapsed_realtime_ns >= started
        ), None)
        return None if completed is None else max(0, (completed - started) // 1_000_000)

    def diagnostic_summary(self) -> dict:
        events = self.snapshot()
        by_trace: dict[str, list[VoiceTraceEvent]] = {}
        for event in events:
            by_trace.setdefault(event.trace_id, []).append(event)
        metric_pairs = {
            "agent_queue_ms": (
                VoiceTraceEvents.AGENT_QUEUE_ENTERED,
                VoiceTraceEvents.AGENT_RUN_STARTED,
            ),
            "agent_first_progress_ms": (
                VoiceTraceEvents.AGENT_QUEUE_ENTERED,
                VoiceTraceEvents.AGENT_FIRST_PROGRESS,
            ),
            "agent_first_output_ms": (
                VoiceTraceEvents.AGENT_QUEUE_ENTERED,
                VoiceTraceEvents.AGENT_FIRST_PARTIAL_RESULT,
            ),
            "agent_total_ms": (
                VoiceTraceEvents.AGENT_QUEUE_ENTERED,
                VoiceTraceEvents.AGENT_COMPLETED,
            ),
        }
        samples: dict[str, list[int]] = {name: [] for name in metric_pairs}
        for trace_id in by_trace:
            for metric, (started, completed) in metric_pairs.items():
                value = self.elapsed_ms(trace_id, started, completed)
                if value is not None:
                    samples[metric].append(value)
        completed_traces = [
            trace
            for trace in by_trace.values()
            if any(event.event == VoiceTraceEvents.AGENT_COMPLETED for event in trace)
        ]
        success_count = sum(
            any(
                event.event == VoiceTraceEvents.AGENT_COMPLETED
                and event.attributes.get("success") == "true"
                for event in trace
            )
            for trace in completed_traces
        )
        cancelled_count = sum(
            any(
                event.event == VoiceTraceEvents.AGENT_COMPLETED
                and event.attributes.get("task_status") == "cancelled"
                for event in trace
            )
            for trace in completed_traces
        )
        failure_count = max(0, len(completed_traces) - success_count - cancelled_count)
        fallback_count = sum(
            any(event.attributes.get("fallback") == "true" for event in trace)
            for trace in by_trace.values()
        )

        def rate(count: int, total: int) -> float:
            return count / total if total else 0.0

        return {
            "trace_count": len(by_trace),
            "event_count": len(events),
            "completed_count": len(completed_traces),
            "success_count": success_count,
            "cancelled_count": cancelled_count,
            "failed_count": failure_count,
            "success_rate": rate(success_count, len(completed_traces)),
            "cancellation_rate": rate(cancelled_count, len(completed_traces)),
            "failure_rate": rate(failure_count, len(completed_traces)),
            "fallback_rate": rate(fallback_count, len(by_trace)),
            "metrics": {
                name: _percentiles(values)
                for name, values in samples.items()
                if values
            },
        }

    def export_content_free_diagnostics(self, output_path: Path | None = None) -> Path:
        destination = output_path or (
            DEFAULT_TRACE_PATH.parent
            / "exports"
            / f"voice_latency_{int(time.time() * 1000)}.json"
        )
        destination = Path(destination)
        destination.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "schema": VOICE_LATENCY_SCHEMA,
            "feature_flag": VOICE_LATENCY_TRACE_FLAG,
            "content_included": False,
            "generated_at_ms": int(time.time() * 1000),
            "host": {
                "system": platform.system(),
                "machine": platform.machine(),
                "python": platform.python_version(),
            },
            "summary": self.diagnostic_summary(),
            "events": [asdict(event) for event in self.snapshot()],
        }
        destination.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
        return destination


def _percentiles(values: Iterable[int]) -> dict[str, int]:
    ordered = sorted(max(0, int(value)) for value in values)
    if not ordered:
        return {"count": 0, "p50_ms": 0, "p90_ms": 0, "p95_ms": 0, "p99_ms": 0}

    def percentile(fraction: float) -> int:
        index = max(0, min(len(ordered) - 1, math.ceil(fraction * len(ordered)) - 1))
        return ordered[index]

    return {
        "count": len(ordered),
        "p50_ms": percentile(0.50),
        "p90_ms": percentile(0.90),
        "p95_ms": percentile(0.95),
        "p99_ms": percentile(0.99),
    }


_TRACER_LOCK = threading.Lock()
_TRACER: VoiceLatencyTracer | None = None


def voice_latency_tracer() -> VoiceLatencyTracer:
    global _TRACER
    if _TRACER is not None:
        return _TRACER
    with _TRACER_LOCK:
        if _TRACER is None:
            _TRACER = VoiceLatencyTracer(sink=JsonlVoiceTraceEventSink())
        return _TRACER
