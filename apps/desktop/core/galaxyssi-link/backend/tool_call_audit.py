"""Privacy-preserving durable audit records for Desktop tool calls."""
from __future__ import annotations

import hashlib
import json
import os
import threading
import uuid
from pathlib import Path
from typing import Any, Mapping


CONTRACT_VERSION = "galaxyssi.tool-call-audit/1.0"
MAX_RECORDS = 10_000
MAX_LIST_LIMIT = 500
IDENTITY_FIELDS = (
    "client_route_id",
    "conversation_id",
    "task_id",
    "turn_id",
    "collaboration_task_id",
)


def canonical_digest(value: Any) -> str:
    encoded = json.dumps(
        value,
        ensure_ascii=True,
        sort_keys=True,
        separators=(",", ":"),
        default=str,
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


class ToolCallAuditStore:
    def __init__(self, path: Path | None) -> None:
        self.path = Path(path) if path is not None else None
        self._lock = threading.RLock()
        self._records = self._load()

    def append(
        self,
        *,
        tool_id: str,
        tool_version: str,
        location: str,
        status: str,
        started_at: int,
        finished_at: int,
        input_sha256: str,
        output_sha256: str,
        context: Mapping[str, Any] | None = None,
        invocation_id: str = "",
        risk: str = "unknown",
        confirmation: str = "none",
        error_code: str = "",
        replayed: bool = False,
        original_invocation_id: str = "",
    ) -> dict[str, Any]:
        safe_context = dict(context or {})
        record = {
            "contract_version": CONTRACT_VERSION,
            "audit_id": uuid.uuid4().hex,
            "invocation_id": str(invocation_id or "")[:160],
            "tool_id": str(tool_id or "unknown")[:240],
            "tool_version": str(tool_version or "")[:80],
            "location": str(location or "unknown")[:80],
            "risk": str(risk or "unknown")[:40],
            "confirmation": self._confirmation_state(confirmation, safe_context),
            "caller_id": str(
                safe_context.get("agent_id")
                or safe_context.get("caller_id")
                or "galaxyssi.desktop"
            )[:160],
            "identity_hashes": {
                f"{field}_sha256": self._identity_digest(safe_context.get(field))
                for field in IDENTITY_FIELDS
                if str(safe_context.get(field) or "").strip()
            },
            "started_at": max(0, int(started_at or 0)),
            "finished_at": max(0, int(finished_at or 0)),
            "duration_ms": max(0, int(finished_at or 0) - int(started_at or 0)),
            "status": str(status or "failed")[:40],
            "error_code": str(error_code or "")[:160],
            "input_sha256": self._digest_value(input_sha256),
            "output_sha256": self._digest_value(output_sha256),
            "replayed": bool(replayed),
            "original_invocation_id": str(original_invocation_id or "")[:160],
        }
        record["record_sha256"] = canonical_digest(record)
        with self._lock:
            self._records.append(record)
            self._records = self._records[-MAX_RECORDS:]
            self._save()
        return dict(record)

    def list(
        self,
        *,
        limit: int = 100,
        tool_id: str = "",
        status: str = "",
    ) -> list[dict[str, Any]]:
        bounded_limit = max(1, min(MAX_LIST_LIMIT, int(limit or 100)))
        requested_tool = str(tool_id or "").strip()
        requested_status = str(status or "").strip()
        with self._lock:
            records = [
                dict(record)
                for record in reversed(self._records)
                if (not requested_tool or record.get("tool_id") == requested_tool)
                and (not requested_status or record.get("status") == requested_status)
            ]
        return records[:bounded_limit]

    def clear(self) -> None:
        with self._lock:
            self._records = []
            self._save()

    @staticmethod
    def _identity_digest(value: Any) -> str:
        return hashlib.sha256(str(value or "").encode("utf-8")).hexdigest()

    @staticmethod
    def _digest_value(value: Any) -> str:
        candidate = str(value or "").strip().lower()
        if len(candidate) == 64 and all(character in "0123456789abcdef" for character in candidate):
            return candidate
        return canonical_digest(value)

    @staticmethod
    def _confirmation_state(confirmation: str, context: Mapping[str, Any]) -> str:
        policy = str(confirmation or "none")
        if policy == "none":
            return "not_required"
        decision = context.get("confirmation")
        if isinstance(decision, Mapping) and decision.get("decision") == "approved":
            return "approved"
        return "missing_or_denied"

    def _load(self) -> list[dict[str, Any]]:
        if self.path is None:
            return []
        try:
            value = json.loads(self.path.read_text(encoding="utf-8"))
            if isinstance(value, list):
                return [dict(item) for item in value if isinstance(item, dict)][-MAX_RECORDS:]
        except (FileNotFoundError, OSError, json.JSONDecodeError):
            pass
        return []

    def _save(self) -> None:
        if self.path is None:
            return
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.path.with_suffix(self.path.suffix + ".tmp")
        temporary.write_text(
            json.dumps(
                self._records,
                ensure_ascii=True,
                sort_keys=True,
                separators=(",", ":"),
            ),
            encoding="utf-8",
        )
        temporary.replace(self.path)


_default_store: ToolCallAuditStore | None = None
_default_store_lock = threading.Lock()


def desktop_tool_call_audit_store() -> ToolCallAuditStore:
    global _default_store
    with _default_store_lock:
        if _default_store is None:
            root = Path(
                os.environ.get("GALAXYSSI_STATE_DIR")
                or Path(os.environ.get("APPDATA") or Path.home()) / "GalaxySSI"
            )
            _default_store = ToolCallAuditStore(root / "desktop-tool-call-audit.json")
        return _default_store
