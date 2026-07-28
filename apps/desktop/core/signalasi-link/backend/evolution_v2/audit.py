"""Append-only, hash-chained audit ledger with secret redaction."""
from __future__ import annotations

import json
import os
import threading
import uuid
from collections import deque
from pathlib import Path
from typing import Any

from .common import now_millis, redact, sha256_text, stable_json, state_root


class AuditLedger:
    def __init__(self, path: Path | None = None) -> None:
        self.path = Path(path) if path else state_root() / "evolution" / "v2" / "audit" / "events.jsonl"
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.RLock()

    def append(
        self,
        event: str,
        *,
        actor: str = "desktop",
        task_id: str = "",
        payload: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        with self._lock:
            previous = self._last_record()
            record = {
                "record_id": f"audit-{uuid.uuid4().hex}",
                "timestamp_millis": now_millis(),
                "event": str(event or "unknown")[:120],
                "actor": str(actor or "desktop")[:120],
                "task_id": str(task_id or "")[:128],
                "payload": redact(payload or {}, maximum_text=8_000),
                "previous_hash": str(previous.get("record_hash") or "") if previous else "",
            }
            record["record_hash"] = sha256_text(stable_json(record))
            with self.path.open("a", encoding="utf-8", newline="\n") as stream:
                stream.write(json.dumps(record, ensure_ascii=True, separators=(",", ":"), sort_keys=True))
                stream.write("\n")
                stream.flush()
                os.fsync(stream.fileno())
            return record

    def verify(self) -> dict[str, Any]:
        previous_hash = ""
        count = 0
        errors: list[str] = []
        try:
            lines = self.path.read_text(encoding="utf-8").splitlines()
        except FileNotFoundError:
            lines = []
        except OSError as exc:
            return {
                "valid": False,
                "records": 0,
                "errors": [f"audit read failed: {exc}"],
                "head_hash": "",
            }
        for index, line in enumerate(lines, start=1):
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                errors.append(f"record {index}: invalid JSON")
                continue
            if not isinstance(record, dict):
                errors.append(f"record {index}: record is not an object")
                continue
            count += 1
            claimed = str(record.get("record_hash") or "")
            body = {key: value for key, value in record.items() if key != "record_hash"}
            expected = sha256_text(stable_json(body))
            if str(record.get("previous_hash") or "") != previous_hash:
                errors.append(f"record {index}: previous_hash mismatch")
            if claimed != expected:
                errors.append(f"record {index}: record_hash mismatch")
            previous_hash = claimed
        return {"valid": not errors, "records": count, "errors": errors[:50], "head_hash": previous_hash}

    def list(self, *, limit: int = 200, newest_first: bool = True) -> list[dict[str, Any]]:
        try:
            lines = self.path.read_text(encoding="utf-8").splitlines()
        except OSError:
            return []
        records: list[dict[str, Any]] = []
        for line in lines:
            try:
                value = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(value, dict):
                records.append(value)
        if newest_first:
            records.reverse()
        return records[: max(1, min(int(limit), 1_000_000))]

    def list_for_task(self, task_id: str, *, limit: int = 200) -> list[dict[str, Any]]:
        identifier = str(task_id or "")
        if not identifier:
            return []
        return self.list_for_tasks([identifier], limit_per_task=limit).get(identifier, [])

    def list_for_tasks(
        self,
        task_ids: list[str] | set[str] | tuple[str, ...],
        *,
        limit_per_task: int = 200,
    ) -> dict[str, list[dict[str, Any]]]:
        identifiers = {str(value or "") for value in task_ids if str(value or "")}
        if not identifiers:
            return {}
        bounded_limit = max(1, min(int(limit_per_task), 1_000))
        rows = {
            identifier: deque(maxlen=bounded_limit)
            for identifier in identifiers
        }
        try:
            lines = self.path.read_text(encoding="utf-8").splitlines()
        except OSError:
            return {identifier: [] for identifier in identifiers}
        for line in lines:
            try:
                value = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(value, dict):
                continue
            identifier = str(value.get("task_id") or "")
            if identifier in rows:
                rows[identifier].append(value)
        return {
            identifier: list(values)
            for identifier, values in rows.items()
        }

    def _last_record(self) -> dict[str, Any] | None:
        rows = self.list(limit=1)
        return rows[0] if rows else None
