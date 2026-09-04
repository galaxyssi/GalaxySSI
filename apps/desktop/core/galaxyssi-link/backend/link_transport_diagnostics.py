"""Privacy-safe diagnostics for GalaxySSI Link transport anomalies."""
from __future__ import annotations

import hashlib
import json
import os
import re
import threading
import time
import uuid
from pathlib import Path
from typing import Any, Callable

PROTOCOL = "galaxyssi.link-transport-diagnostics/1.0"
EVENT_KINDS = (
    "encrypted_replay",
    "pending_replay",
    "duplicate_message",
    "duplicate_receipt",
    "old_counter",
    "decrypt_failure",
    "chunk_duplicate",
    "fragment_rejected",
)
DEFAULT_MAXIMUM_EVENTS = 40


def _default_state_path() -> Path:
    configured = str(os.environ.get("GALAXYSSI_STATE_DIR") or "").strip()
    root = (
        Path(configured)
        if configured
        else Path(os.environ.get("APPDATA") or Path.home()) / "GalaxySSI"
    )
    return root / "link-transport-diagnostics.json"


def anonymized_reference(value: str) -> str:
    normalized = str(value or "").strip()
    if not normalized:
        return ""
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()[:12]


def normalized_detail_code(value: str) -> str:
    normalized = re.sub(r"[^a-z0-9_.-]+", "_", str(value or "").strip().lower())
    return normalized.strip("_")[:64]


def _nonnegative_int(value: Any) -> int:
    try:
        return max(0, int(value or 0))
    except (TypeError, ValueError, OverflowError):
        return 0


def classify_decryption_error(error: BaseException) -> str:
    class_name = error.__class__.__name__.lower()
    message = str(error or "").lower()
    if "old counter" in message or "oldcounter" in message:
        return "old_counter"
    if "duplicatemessage" in class_name or "duplicate message" in message:
        return "duplicate_message"
    return "decrypt_failure"


def classify_fragment_error(error: BaseException) -> str:
    return "chunk_duplicate" if "duplicate" in str(error or "").lower() else "fragment_rejected"


class LinkTransportDiagnostics:
    def __init__(
        self,
        state_path: Path | None = None,
        *,
        clock: Callable[[], int] | None = None,
        maximum_events: int = DEFAULT_MAXIMUM_EVENTS,
    ) -> None:
        if maximum_events <= 0:
            raise ValueError("maximum_events must be positive")
        self.state_path = Path(state_path or _default_state_path())
        self._clock = clock or (lambda: int(time.time() * 1000))
        self._maximum_events = int(maximum_events)
        self._lock = threading.RLock()
        self._state = self._load()

    def record(
        self,
        kind: str,
        *,
        route_id: str = "",
        message_id: str = "",
        detail_code: str = "",
    ) -> dict[str, Any]:
        if kind not in EVENT_KINDS:
            raise ValueError(f"Unsupported link diagnostic kind: {kind}")
        with self._lock:
            counts = self._state["counts"]
            counts[kind] = int(counts.get(kind, 0)) + 1
            self._state["total_events"] = int(self._state.get("total_events", 0)) + 1
            self._state["recent_events"].append(
                {
                    "id": str(uuid.uuid4()),
                    "kind": kind,
                    "recorded_at": int(self._clock()),
                    "endpoint_ref": anonymized_reference(route_id),
                    "message_ref": anonymized_reference(message_id),
                    "detail_code": normalized_detail_code(detail_code),
                }
            )
            self._state["recent_events"] = self._state["recent_events"][-self._maximum_events :]
            self._persist()
            return self._snapshot_locked()

    def snapshot(self) -> dict[str, Any]:
        with self._lock:
            return self._snapshot_locked()

    def clear(self) -> None:
        with self._lock:
            self._state = self._empty_state()
            self._persist()

    def _snapshot_locked(self) -> dict[str, Any]:
        snapshot = json.loads(json.dumps(self._state, ensure_ascii=True))
        counts = snapshot["counts"]
        snapshot["summary"] = {
            "replay": int(counts["encrypted_replay"]) + int(counts["pending_replay"]),
            "duplicate": (
                int(counts["duplicate_message"])
                + int(counts["duplicate_receipt"])
                + int(counts["chunk_duplicate"])
            ),
            "old_counter": int(counts["old_counter"]),
            "failure": int(counts["decrypt_failure"]) + int(counts["fragment_rejected"]),
        }
        snapshot["last_event_at"] = (
            int(snapshot["recent_events"][-1]["recorded_at"])
            if snapshot["recent_events"]
            else 0
        )
        snapshot["recent_events"].reverse()
        return snapshot

    def _load(self) -> dict[str, Any]:
        try:
            raw = json.loads(self.state_path.read_text(encoding="utf-8"))
        except (FileNotFoundError, json.JSONDecodeError, OSError, TypeError):
            return self._empty_state()
        if not isinstance(raw, dict):
            return self._empty_state()
        state = self._empty_state()
        state["total_events"] = _nonnegative_int(raw.get("total_events"))
        raw_counts = raw.get("counts") if isinstance(raw.get("counts"), dict) else {}
        state["counts"] = {
            kind: _nonnegative_int(raw_counts.get(kind))
            for kind in EVENT_KINDS
        }
        raw_events = raw.get("recent_events") if isinstance(raw.get("recent_events"), list) else []
        state["recent_events"] = [
            self._normalized_event(item)
            for item in raw_events[-self._maximum_events :]
            if isinstance(item, dict) and str(item.get("kind") or "") in EVENT_KINDS
        ]
        return state

    def _normalized_event(self, value: dict[str, Any]) -> dict[str, Any]:
        return {
            "id": str(value.get("id") or uuid.uuid4()),
            "kind": str(value.get("kind") or ""),
            "recorded_at": _nonnegative_int(value.get("recorded_at")),
            "endpoint_ref": normalized_detail_code(str(value.get("endpoint_ref") or ""))[:12],
            "message_ref": normalized_detail_code(str(value.get("message_ref") or ""))[:12],
            "detail_code": normalized_detail_code(str(value.get("detail_code") or "")),
        }

    def _persist(self) -> None:
        self.state_path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.state_path.with_suffix(f"{self.state_path.suffix}.tmp")
        temporary.write_text(
            json.dumps(self._state, ensure_ascii=True, indent=2, sort_keys=True),
            encoding="utf-8",
        )
        temporary.replace(self.state_path)

    @staticmethod
    def _empty_state() -> dict[str, Any]:
        return {
            "protocol": PROTOCOL,
            "total_events": 0,
            "counts": {kind: 0 for kind in EVENT_KINDS},
            "recent_events": [],
        }


_runtimes: dict[Path, LinkTransportDiagnostics] = {}
_runtimes_lock = threading.Lock()


def link_transport_diagnostics() -> LinkTransportDiagnostics:
    path = _default_state_path().resolve()
    with _runtimes_lock:
        runtime = _runtimes.get(path)
        if runtime is None:
            runtime = LinkTransportDiagnostics(path)
            _runtimes[path] = runtime
        return runtime
