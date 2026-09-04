"""Durable, secret-free lifecycle receipts for Tool Marketplace items."""
from __future__ import annotations

import json
import os
import re
import threading
import time
from copy import deepcopy
from pathlib import Path
from typing import Any, Mapping


STORE_VERSION = 1
MAX_HISTORY = 8
MAX_EVENTS = 64
ITEM_ID = re.compile(r"[a-z][a-z0-9]*(?:[._-][a-z0-9]+)+")
SENSITIVE_KEYS = {
    "api_key",
    "access_token",
    "refresh_token",
    "authorization",
    "credentials",
    "otp",
    "password",
    "secret",
    "token",
}
REFERENCE_CONTAINERS = {
    "environment_env",
    "header_env",
    "header_templates",
}


def _state_path() -> Path:
    configured = str(os.environ.get("GALAXYSSI_STATE_DIR") or "").strip()
    root = Path(configured) if configured else Path(os.environ.get("APPDATA") or Path.home()) / "GalaxySSI"
    return root / "tool-marketplace-lifecycle.json"


class MarketplaceLifecycleStore:
    def __init__(self, path: Path | None = None) -> None:
        self.path = Path(path) if path else _state_path()
        self._lock = threading.RLock()

    def record(self, item_id: str) -> dict[str, Any]:
        clean_id = self._item_id(item_id)
        with self._lock:
            return deepcopy(self._load()["items"].get(clean_id) or self._empty_record())

    def ensure_active(
        self,
        item_id: str,
        *,
        version: str,
        permissions: list[str],
        capabilities: list[str],
        snapshot: Mapping[str, Any],
    ) -> dict[str, Any]:
        clean_id = self._item_id(item_id)
        with self._lock:
            root = self._load()
            record = root["items"].setdefault(clean_id, self._empty_record())
            if record.get("active") is None:
                record["active"] = self._release(
                    version,
                    permissions,
                    capabilities,
                    snapshot,
                )
                record["revoked"] = False
                self._event(record, "discovered", version)
                self._save(root)
            return deepcopy(record)

    def activate(
        self,
        item_id: str,
        *,
        version: str,
        permissions: list[str],
        capabilities: list[str],
        snapshot: Mapping[str, Any],
    ) -> dict[str, Any]:
        clean_id = self._item_id(item_id)
        with self._lock:
            root = self._load()
            record = root["items"].setdefault(clean_id, self._empty_record())
            release = self._release(version, permissions, capabilities, snapshot)
            current = record.get("active")
            if current and self._release_identity(current) != self._release_identity(release):
                self._append_history(record, current)
            record["active"] = release
            record["revoked"] = False
            record["revision"] = int(record.get("revision") or 0) + 1
            self._event(record, "activated", version)
            self._save(root)
            return deepcopy(record)

    def revoke(self, item_id: str) -> dict[str, Any]:
        clean_id = self._item_id(item_id)
        with self._lock:
            root = self._load()
            record = root["items"].setdefault(clean_id, self._empty_record())
            if record.get("active") is None:
                raise ValueError("Marketplace item has no active installation")
            record["revoked"] = True
            record["revision"] = int(record.get("revision") or 0) + 1
            self._event(record, "revoked", str(record["active"].get("version") or ""))
            self._save(root)
            return deepcopy(record)

    def uninstall(self, item_id: str) -> dict[str, Any]:
        clean_id = self._item_id(item_id)
        with self._lock:
            root = self._load()
            record = root["items"].setdefault(clean_id, self._empty_record())
            current = record.get("active")
            if current:
                self._append_history(record, current)
            record["active"] = None
            record["revoked"] = False
            record["revision"] = int(record.get("revision") or 0) + 1
            self._event(record, "uninstalled", str((current or {}).get("version") or ""))
            self._save(root)
            return deepcopy(record)

    def rollback_candidate(self, item_id: str) -> dict[str, Any] | None:
        record = self.record(item_id)
        history = list(record.get("history") or [])
        return deepcopy(history[-1]) if history else None

    def commit_rollback(self, item_id: str) -> dict[str, Any]:
        clean_id = self._item_id(item_id)
        with self._lock:
            root = self._load()
            record = root["items"].setdefault(clean_id, self._empty_record())
            history = list(record.get("history") or [])
            if not history:
                raise ValueError("No rollback version is available")
            candidate = history.pop()
            current = record.get("active")
            if current:
                history.append(current)
            record["history"] = self._deduplicate(history)[-MAX_HISTORY:]
            record["active"] = candidate
            record["revoked"] = False
            record["revision"] = int(record.get("revision") or 0) + 1
            self._event(record, "rolled_back", str(candidate.get("version") or ""))
            self._save(root)
            return deepcopy(record)

    def _load(self) -> dict[str, Any]:
        if not self.path.exists():
            return {"version": STORE_VERSION, "items": {}}
        try:
            value = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return {"version": STORE_VERSION, "items": {}}
        items = value.get("items")
        return {
            "version": STORE_VERSION,
            "items": dict(items) if isinstance(items, dict) else {},
        }

    def _save(self, value: Mapping[str, Any]) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        staging = self.path.with_suffix(self.path.suffix + ".tmp")
        staging.write_text(
            json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")),
            encoding="utf-8",
        )
        staging.replace(self.path)

    @staticmethod
    def _empty_record() -> dict[str, Any]:
        return {
            "active": None,
            "history": [],
            "revoked": False,
            "revision": 0,
            "events": [],
        }

    @staticmethod
    def _release(
        version: str,
        permissions: list[str],
        capabilities: list[str],
        snapshot: Mapping[str, Any],
    ) -> dict[str, Any]:
        return {
            "version": str(version).strip()[:80],
            "permissions": sorted({str(value)[:160] for value in permissions if str(value)}),
            "capabilities": sorted({str(value)[:160] for value in capabilities if str(value)}),
            "snapshot": MarketplaceLifecycleStore._secret_free_snapshot(snapshot),
            "activated_at": int(time.time() * 1_000),
        }

    @staticmethod
    def _secret_free_snapshot(
        value: Any,
        *,
        parent: str = "",
        depth: int = 0,
    ) -> Any:
        if depth > 12:
            raise ValueError("Marketplace rollback snapshot is too deeply nested")
        if isinstance(value, Mapping):
            result: dict[str, Any] = {}
            for raw_key, raw_value in value.items():
                key = str(raw_key)
                normalized = key.strip().casefold()
                if normalized in SENSITIVE_KEYS and parent not in REFERENCE_CONTAINERS:
                    raise ValueError(
                        f"Marketplace rollback snapshot cannot store secret field: {key}"
                    )
                result[key[:160]] = MarketplaceLifecycleStore._secret_free_snapshot(
                    raw_value,
                    parent=normalized,
                    depth=depth + 1,
                )
            return result
        if isinstance(value, (list, tuple)):
            return [
                MarketplaceLifecycleStore._secret_free_snapshot(
                    item,
                    parent=parent,
                    depth=depth + 1,
                )
                for item in list(value)[:512]
            ]
        if value is None or isinstance(value, (bool, int, float)):
            return value
        return str(value)[:8_000]

    @staticmethod
    def _release_identity(value: Mapping[str, Any]) -> str:
        comparable = {
            "version": value.get("version"),
            "permissions": value.get("permissions"),
            "capabilities": value.get("capabilities"),
            "snapshot": value.get("snapshot"),
        }
        return json.dumps(comparable, sort_keys=True, separators=(",", ":"))

    def _append_history(self, record: dict[str, Any], release: Mapping[str, Any]) -> None:
        history = list(record.get("history") or [])
        history.append(deepcopy(dict(release)))
        record["history"] = self._deduplicate(history)[-MAX_HISTORY:]

    def _deduplicate(self, values: list[Mapping[str, Any]]) -> list[dict[str, Any]]:
        result: list[dict[str, Any]] = []
        for value in values:
            identity = self._release_identity(value)
            result = [item for item in result if self._release_identity(item) != identity]
            result.append(deepcopy(dict(value)))
        return result

    @staticmethod
    def _event(record: dict[str, Any], action: str, version: str) -> None:
        events = list(record.get("events") or [])
        events.append(
            {
                "action": action,
                "version": str(version)[:80],
                "at": int(time.time() * 1_000),
            }
        )
        record["events"] = events[-MAX_EVENTS:]

    @staticmethod
    def _item_id(value: str) -> str:
        clean = str(value or "").strip().casefold()
        if not ITEM_ID.fullmatch(clean):
            raise ValueError("Marketplace item id is invalid")
        return clean
