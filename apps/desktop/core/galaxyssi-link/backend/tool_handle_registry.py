"""Opaque, scoped handles for stateful GalaxySSI tools."""
from __future__ import annotations

import secrets
import threading
import time
from dataclasses import dataclass
from typing import Any, Callable, Iterable, Mapping


TOOL_HANDLE_CONTRACT = "galaxyssi.tool-handle/1.0"
DEFAULT_TTL_SECONDS = 60 * 60
MAX_TTL_SECONDS = 30 * 24 * 60 * 60
DEFAULT_MAX_HANDLES = 2_048
MAX_CAPABILITIES = 128
MAX_METADATA_ITEMS = 32


class ToolHandleError(RuntimeError):
    def __init__(self, code: str, message: str, *, retryable: bool = False) -> None:
        super().__init__(message)
        self.code = str(code or "tool_handle_failed")
        self.retryable = bool(retryable)


@dataclass(frozen=True)
class ToolHandleScope:
    owner_id: str
    context_id: str = ""

    def normalized(self) -> "ToolHandleScope":
        owner_id = _bounded_identifier(self.owner_id, "owner_id", 240)
        if not owner_id:
            raise ToolHandleError("tool_handle_owner_required", "Tool handle owner is required")
        return ToolHandleScope(
            owner_id=owner_id,
            context_id=_bounded_identifier(self.context_id, "context_id", 240),
        )


class ToolHandleRegistry:
    def __init__(
        self,
        *,
        now: Callable[[], float] = time.time,
        max_handles: int = DEFAULT_MAX_HANDLES,
    ) -> None:
        self._now = now
        self._max_handles = max(1, min(int(max_handles or DEFAULT_MAX_HANDLES), 16_384))
        self._lock = threading.RLock()
        self._handles: dict[str, dict[str, Any]] = {}
        self._metrics = {
            "created": 0,
            "reused": 0,
            "resolved": 0,
            "released": 0,
            "expired": 0,
            "rejected": 0,
        }

    def create(
        self,
        *,
        kind: str,
        resource_id: str,
        scope: ToolHandleScope,
        capabilities: Iterable[str],
        ttl_seconds: int = DEFAULT_TTL_SECONDS,
        idle_timeout_seconds: int = 0,
        parent_run_id: str = "",
        metadata: Mapping[str, Any] | None = None,
        reuse: bool = True,
    ) -> dict[str, Any]:
        normalized_kind = _bounded_kind(kind)
        normalized_resource_id = _bounded_identifier(resource_id, "resource_id", 512)
        if not normalized_resource_id:
            raise ToolHandleError(
                "tool_handle_resource_required",
                "Tool handle resource is required",
            )
        normalized_scope = scope.normalized()
        normalized_capabilities = _capabilities(capabilities)
        ttl = max(1, min(int(ttl_seconds or DEFAULT_TTL_SECONDS), MAX_TTL_SECONDS))
        idle_timeout = max(0, min(int(idle_timeout_seconds or 0), ttl))
        normalized_parent_run_id = _bounded_identifier(
            parent_run_id,
            "parent_run_id",
            240,
        )
        public_metadata = _public_metadata(metadata or {})
        now_ms = self._now_ms()
        with self._lock:
            self._prune_locked(now_ms)
            if reuse:
                existing = self._matching_locked(
                    normalized_kind,
                    normalized_resource_id,
                    normalized_scope,
                )
                if existing is not None:
                    existing["capabilities"] = sorted(normalized_capabilities)
                    existing["expires_at"] = now_ms + ttl * 1_000
                    existing["idle_timeout_ms"] = idle_timeout * 1_000
                    existing["parent_run_id"] = normalized_parent_run_id
                    existing["metadata"] = public_metadata
                    self._metrics["reused"] += 1
                    return self._public(existing)
            self._make_capacity_locked(now_ms)
            handle_id = self._new_handle_id(normalized_kind)
            row = {
                "handle_id": handle_id,
                "kind": normalized_kind,
                "resource_id": normalized_resource_id,
                "owner_id": normalized_scope.owner_id,
                "context_id": normalized_scope.context_id,
                "capabilities": sorted(normalized_capabilities),
                "parent_run_id": normalized_parent_run_id,
                "metadata": public_metadata,
                "created_at": now_ms,
                "last_used_at": now_ms,
                "expires_at": now_ms + ttl * 1_000,
                "idle_timeout_ms": idle_timeout * 1_000,
                "use_count": 0,
            }
            self._handles[handle_id] = row
            self._metrics["created"] += 1
            return self._public(row)

    def resolve(
        self,
        handle_id: str,
        *,
        kind: str,
        scope: ToolHandleScope,
        required_capability: str = "",
        touch: bool = True,
    ) -> dict[str, Any]:
        normalized_handle_id = _bounded_identifier(handle_id, "handle_id", 240)
        normalized_kind = _bounded_kind(kind)
        normalized_scope = scope.normalized()
        capability = _bounded_identifier(
            required_capability,
            "required_capability",
            160,
        )
        now_ms = self._now_ms()
        with self._lock:
            row = self._handles.get(normalized_handle_id)
            if row is None:
                self._reject(
                    "tool_handle_not_found",
                    "Tool handle is missing, expired, or was released",
                    retryable=True,
                )
            if self._expired(row, now_ms):
                self._handles.pop(normalized_handle_id, None)
                self._metrics["expired"] += 1
                self._reject(
                    "tool_handle_expired",
                    "Tool handle expired; create a new handle and retry",
                    retryable=True,
                )
            if str(row.get("kind") or "") != normalized_kind:
                self._reject(
                    "tool_handle_kind_mismatch",
                    "Tool handle belongs to a different resource type",
                )
            if not secrets.compare_digest(
                str(row.get("owner_id") or ""),
                normalized_scope.owner_id,
            ):
                self._reject(
                    "tool_handle_owner_mismatch",
                    "Tool handle belongs to a different caller",
                )
            expected_context = str(row.get("context_id") or "")
            if expected_context and not secrets.compare_digest(
                expected_context,
                normalized_scope.context_id,
            ):
                self._reject(
                    "tool_handle_context_mismatch",
                    "Tool handle belongs to a different conversation context",
                )
            if capability and capability not in set(row.get("capabilities") or []):
                self._reject(
                    "tool_handle_capability_denied",
                    "Tool handle does not grant the requested capability",
                )
            if touch:
                row["last_used_at"] = now_ms
                row["use_count"] = int(row.get("use_count") or 0) + 1
            self._metrics["resolved"] += 1
            return self._private(row)

    def release(
        self,
        handle_id: str,
        *,
        scope: ToolHandleScope,
    ) -> bool:
        normalized_handle_id = _bounded_identifier(handle_id, "handle_id", 240)
        normalized_scope = scope.normalized()
        with self._lock:
            row = self._handles.get(normalized_handle_id)
            if row is None:
                return False
            if not secrets.compare_digest(
                str(row.get("owner_id") or ""),
                normalized_scope.owner_id,
            ):
                self._reject(
                    "tool_handle_owner_mismatch",
                    "Tool handle belongs to a different caller",
                )
            expected_context = str(row.get("context_id") or "")
            if expected_context and not secrets.compare_digest(
                expected_context,
                normalized_scope.context_id,
            ):
                self._reject(
                    "tool_handle_context_mismatch",
                    "Tool handle belongs to a different conversation context",
                )
            self._handles.pop(normalized_handle_id, None)
            self._metrics["released"] += 1
            return True

    def revoke_resource(self, kind: str, resource_id: str) -> int:
        normalized_kind = _bounded_kind(kind)
        normalized_resource_id = _bounded_identifier(resource_id, "resource_id", 512)
        with self._lock:
            targets = [
                handle_id
                for handle_id, row in self._handles.items()
                if row.get("kind") == normalized_kind
                and row.get("resource_id") == normalized_resource_id
            ]
            for handle_id in targets:
                self._handles.pop(handle_id, None)
            self._metrics["released"] += len(targets)
            return len(targets)

    def revoke_owner(self, owner_id: str) -> int:
        normalized_owner_id = _bounded_identifier(owner_id, "owner_id", 240)
        with self._lock:
            targets = [
                handle_id
                for handle_id, row in self._handles.items()
                if row.get("owner_id") == normalized_owner_id
            ]
            for handle_id in targets:
                self._handles.pop(handle_id, None)
            self._metrics["released"] += len(targets)
            return len(targets)

    def revoke_kind(self, kind: str) -> int:
        normalized_kind = _bounded_kind(kind)
        with self._lock:
            targets = [
                handle_id
                for handle_id, row in self._handles.items()
                if row.get("kind") == normalized_kind
            ]
            for handle_id in targets:
                self._handles.pop(handle_id, None)
            self._metrics["released"] += len(targets)
            return len(targets)

    def list(
        self,
        *,
        scope: ToolHandleScope | None = None,
        kind: str = "",
    ) -> list[dict[str, Any]]:
        normalized_scope = scope.normalized() if scope is not None else None
        normalized_kind = _bounded_kind(kind) if kind else ""
        now_ms = self._now_ms()
        with self._lock:
            self._prune_locked(now_ms)
            rows = [
                self._public(row)
                for row in self._handles.values()
                if (not normalized_kind or row.get("kind") == normalized_kind)
                and (
                    normalized_scope is None
                    or row.get("owner_id") == normalized_scope.owner_id
                    and (
                        not row.get("context_id")
                        or row.get("context_id") == normalized_scope.context_id
                    )
                )
            ]
            rows.sort(
                key=lambda row: (
                    -int(row.get("last_used_at") or 0),
                    str(row.get("handle_id") or ""),
                )
            )
            return rows

    def status(self) -> dict[str, Any]:
        now_ms = self._now_ms()
        with self._lock:
            self._prune_locked(now_ms)
            by_kind: dict[str, int] = {}
            for row in self._handles.values():
                kind = str(row.get("kind") or "unknown")
                by_kind[kind] = by_kind.get(kind, 0) + 1
            return {
                "contract": TOOL_HANDLE_CONTRACT,
                "active_count": len(self._handles),
                "max_handles": self._max_handles,
                "by_kind": dict(sorted(by_kind.items())),
                "metrics": dict(self._metrics),
            }

    def _matching_locked(
        self,
        kind: str,
        resource_id: str,
        scope: ToolHandleScope,
    ) -> dict[str, Any] | None:
        return next(
            (
                row
                for row in self._handles.values()
                if row.get("kind") == kind
                and row.get("resource_id") == resource_id
                and row.get("owner_id") == scope.owner_id
                and row.get("context_id") == scope.context_id
            ),
            None,
        )

    def _make_capacity_locked(self, now_ms: int) -> None:
        self._prune_locked(now_ms)
        if len(self._handles) < self._max_handles:
            return
        oldest = min(
            self._handles.values(),
            key=lambda row: (
                int(row.get("last_used_at") or 0),
                int(row.get("created_at") or 0),
            ),
        )
        self._handles.pop(str(oldest.get("handle_id") or ""), None)
        self._metrics["released"] += 1

    def _prune_locked(self, now_ms: int) -> int:
        expired = [
            handle_id
            for handle_id, row in self._handles.items()
            if self._expired(row, now_ms)
        ]
        for handle_id in expired:
            self._handles.pop(handle_id, None)
        self._metrics["expired"] += len(expired)
        return len(expired)

    @staticmethod
    def _expired(row: Mapping[str, Any], now_ms: int) -> bool:
        if now_ms >= int(row.get("expires_at") or 0):
            return True
        idle_timeout_ms = int(row.get("idle_timeout_ms") or 0)
        return (
            idle_timeout_ms > 0
            and now_ms >= int(row.get("last_used_at") or 0) + idle_timeout_ms
        )

    @staticmethod
    def _public(row: Mapping[str, Any]) -> dict[str, Any]:
        return {
            "contract": TOOL_HANDLE_CONTRACT,
            "handle_id": str(row.get("handle_id") or ""),
            "kind": str(row.get("kind") or ""),
            "capabilities": list(row.get("capabilities") or []),
            "owner_id": str(row.get("owner_id") or ""),
            "context_id": str(row.get("context_id") or ""),
            "parent_run_id": str(row.get("parent_run_id") or ""),
            "metadata": dict(row.get("metadata") or {}),
            "created_at": int(row.get("created_at") or 0),
            "last_used_at": int(row.get("last_used_at") or 0),
            "expires_at": int(row.get("expires_at") or 0),
            "use_count": int(row.get("use_count") or 0),
        }

    @classmethod
    def _private(cls, row: Mapping[str, Any]) -> dict[str, Any]:
        return {
            **cls._public(row),
            "resource_id": str(row.get("resource_id") or ""),
        }

    def _reject(self, code: str, message: str, *, retryable: bool = False) -> None:
        self._metrics["rejected"] += 1
        raise ToolHandleError(code, message, retryable=retryable)

    def _now_ms(self) -> int:
        return int(self._now() * 1_000)

    @staticmethod
    def _new_handle_id(kind: str) -> str:
        prefix = "".join(character for character in kind if character.isalnum())[:8]
        return f"sth_{prefix}_{secrets.token_urlsafe(24)}"


def _bounded_identifier(value: Any, field: str, maximum: int) -> str:
    text = str(value or "").strip()
    if len(text) > maximum or any(ord(character) < 32 for character in text):
        raise ToolHandleError(
            "tool_handle_input_invalid",
            f"{field} exceeds its safe limit",
        )
    return text


def _bounded_kind(value: Any) -> str:
    text = _bounded_identifier(value, "kind", 80).lower()
    if not text or any(
        not (character.isalnum() or character in "._-")
        for character in text
    ):
        raise ToolHandleError("tool_handle_kind_invalid", "Tool handle kind is invalid")
    return text


def _capabilities(values: Iterable[str]) -> set[str]:
    normalized = {
        _bounded_identifier(value, "capability", 160)
        for value in values
        if str(value or "").strip()
    }
    if not normalized:
        raise ToolHandleError(
            "tool_handle_capability_required",
            "Tool handle requires at least one capability",
        )
    if len(normalized) > MAX_CAPABILITIES:
        raise ToolHandleError(
            "tool_handle_input_invalid",
            "Tool handle has too many capabilities",
        )
    return normalized


def _public_metadata(values: Mapping[str, Any]) -> dict[str, Any]:
    if len(values) > MAX_METADATA_ITEMS:
        raise ToolHandleError(
            "tool_handle_input_invalid",
            "Tool handle metadata has too many entries",
        )
    result: dict[str, Any] = {}
    for key, value in values.items():
        normalized_key = _bounded_identifier(key, "metadata key", 80)
        if not normalized_key:
            continue
        if isinstance(value, bool):
            result[normalized_key] = value
        elif isinstance(value, int):
            result[normalized_key] = value
        elif isinstance(value, str):
            result[normalized_key] = _bounded_identifier(
                value,
                f"metadata {normalized_key}",
                240,
            )
    return result


_TOOL_HANDLES: ToolHandleRegistry | None = None
_TOOL_HANDLES_LOCK = threading.Lock()


def tool_handle_registry() -> ToolHandleRegistry:
    global _TOOL_HANDLES
    with _TOOL_HANDLES_LOCK:
        if _TOOL_HANDLES is None:
            _TOOL_HANDLES = ToolHandleRegistry()
        return _TOOL_HANDLES
