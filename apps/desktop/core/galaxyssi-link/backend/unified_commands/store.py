"""SQLite-backed run and audit persistence for unified commands."""
from __future__ import annotations

import json
from contextlib import closing
import os
import sqlite3
from pathlib import Path
from threading import RLock
from typing import Any


def default_store_path() -> Path:
    configured = os.environ.get("GALAXYSSI_COMMAND_DB")
    if configured:
        return Path(configured)
    return Path.home() / ".galaxyssi" / "commands.sqlite3"


class CommandStore:
    def __init__(self, path: Path | None = None):
        self.path = path or default_store_path()
        self._lock = RLock()
        self._init()

    def _connect(self) -> sqlite3.Connection:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        conn = sqlite3.connect(self.path)
        conn.row_factory = sqlite3.Row
        return conn

    def _init(self) -> None:
        with self._lock, closing(self._connect()) as conn, conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS command_runs (
                    run_id TEXT PRIMARY KEY,
                    command_id TEXT NOT NULL,
                    source TEXT NOT NULL,
                    requested_by TEXT NOT NULL,
                    workspace TEXT NOT NULL,
                    status TEXT NOT NULL,
                    started_at TEXT NOT NULL,
                    completed_at TEXT NOT NULL,
                    request_json TEXT NOT NULL,
                    result_json TEXT NOT NULL
                )
                """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS command_audit (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    run_id TEXT NOT NULL,
                    command_id TEXT NOT NULL,
                    event_type TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    created_at TEXT NOT NULL
                )
                """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS command_entities (
                    entity_id TEXT PRIMARY KEY,
                    root TEXT NOT NULL,
                    name TEXT NOT NULL,
                    value_json TEXT NOT NULL,
                    status TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS command_kv (
                    namespace TEXT NOT NULL,
                    key TEXT NOT NULL,
                    value_json TEXT NOT NULL,
                    status TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    PRIMARY KEY (namespace, key)
                )
                """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS command_events (
                    event_id TEXT PRIMARY KEY,
                    root TEXT NOT NULL,
                    event_type TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    status TEXT NOT NULL,
                    created_at TEXT NOT NULL
                )
                """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS command_text_records (
                    record_id TEXT PRIMARY KEY,
                    root TEXT NOT NULL,
                    title TEXT NOT NULL,
                    body TEXT NOT NULL,
                    metadata_json TEXT NOT NULL,
                    status TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS command_schedules (
                    schedule_id TEXT PRIMARY KEY,
                    root TEXT NOT NULL,
                    name TEXT NOT NULL,
                    command_json TEXT NOT NULL,
                    schedule_json TEXT NOT NULL,
                    status TEXT NOT NULL,
                    next_run_at TEXT NOT NULL,
                    last_run_at TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS command_usage (
                    usage_id TEXT PRIMARY KEY,
                    root TEXT NOT NULL,
                    metric TEXT NOT NULL,
                    amount REAL NOT NULL,
                    unit TEXT NOT NULL,
                    metadata_json TEXT NOT NULL,
                    created_at TEXT NOT NULL
                )
                """
            )

    def record_run(self, request: Any, result: Any) -> None:
        public = result.public()
        with self._lock, closing(self._connect()) as conn, conn:
            conn.execute(
                """
                INSERT OR REPLACE INTO command_runs
                (run_id, command_id, source, requested_by, workspace, status, started_at, completed_at, request_json, result_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    result.run_id,
                    result.command_id,
                    request.source,
                    request.requested_by,
                    request.workspace,
                    result.status,
                    result.started_at,
                    result.completed_at,
                    json.dumps(request.__dict__, ensure_ascii=False, sort_keys=True),
                    json.dumps(public, ensure_ascii=False, sort_keys=True),
                ),
            )

    def record_audit(self, run_id: str, command_id: str, event_type: str, payload: dict[str, Any], created_at: str) -> None:
        with self._lock, closing(self._connect()) as conn, conn:
            conn.execute(
                """
                INSERT INTO command_audit (run_id, command_id, event_type, payload_json, created_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                (run_id, command_id, event_type, json.dumps(payload, ensure_ascii=False, sort_keys=True), created_at),
            )

    def recent_runs(self, limit: int = 50) -> list[dict[str, Any]]:
        with self._lock, closing(self._connect()) as conn, conn:
            rows = conn.execute(
                "SELECT result_json FROM command_runs ORDER BY started_at DESC LIMIT ?",
                (max(1, min(int(limit), 200)),),
            ).fetchall()
        return [json.loads(row["result_json"]) for row in rows]

    def search_runs(
        self,
        root: str,
        *,
        query: str = "",
        run_id: str = "",
        limit: int = 50,
        excluded_actions: tuple[str, ...] = (),
    ) -> list[dict[str, Any]]:
        clauses = ["command_id LIKE ?"]
        parameters: list[Any] = [f"{root}.%"]
        if run_id:
            clauses.append("run_id = ?")
            parameters.append(run_id)
        if query:
            clauses.append(
                "instr(lower(command_id || ' ' || status || ' ' || result_json), lower(?)) > 0"
            )
            parameters.append(query)
        if excluded_actions:
            placeholders = ", ".join("?" for _ in excluded_actions)
            clauses.append(f"command_id NOT IN ({placeholders})")
            parameters.extend(f"{root}.{action}" for action in excluded_actions)
        parameters.append(max(1, min(int(limit), 200)))
        statement = f"""
            SELECT run_id, command_id, source, requested_by, status,
                   started_at, completed_at, result_json
            FROM command_runs
            WHERE {' AND '.join(clauses)}
            ORDER BY started_at DESC
            LIMIT ?
        """
        with self._lock, closing(self._connect()) as conn, conn:
            rows = conn.execute(statement, parameters).fetchall()
        return [
            {
                "run_id": row["run_id"],
                "command_id": row["command_id"],
                "source": row["source"],
                "requested_by": row["requested_by"],
                "status": row["status"],
                "started_at": row["started_at"],
                "completed_at": row["completed_at"],
                "result": json.loads(row["result_json"]),
            }
            for row in rows
        ]

    def upsert_entity(self, entity_id: str, root: str, name: str, value: dict[str, Any], status: str, timestamp: str) -> dict[str, Any]:
        with self._lock, closing(self._connect()) as conn, conn:
            row = conn.execute(
                "SELECT created_at FROM command_entities WHERE entity_id = ?",
                (entity_id,),
            ).fetchone()
            created_at = row["created_at"] if row else timestamp
            conn.execute(
                """
                INSERT OR REPLACE INTO command_entities
                (entity_id, root, name, value_json, status, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (entity_id, root, name, json.dumps(value, ensure_ascii=False, sort_keys=True), status, created_at, timestamp),
            )
        return self.get_entity(entity_id) or {}

    def get_entity(self, entity_id: str) -> dict[str, Any] | None:
        with self._lock, closing(self._connect()) as conn, conn:
            row = conn.execute("SELECT * FROM command_entities WHERE entity_id = ?", (entity_id,)).fetchone()
        if row is None:
            return None
        return {
            "id": row["entity_id"],
            "root": row["root"],
            "name": row["name"],
            "value": json.loads(row["value_json"]),
            "status": row["status"],
            "created_at": row["created_at"],
            "updated_at": row["updated_at"],
        }

    def list_entities(self, root: str, limit: int = 100) -> list[dict[str, Any]]:
        with self._lock, closing(self._connect()) as conn, conn:
            rows = conn.execute(
                "SELECT entity_id FROM command_entities WHERE root = ? ORDER BY updated_at DESC LIMIT ?",
                (root, max(1, min(int(limit), 500))),
            ).fetchall()
        return [entity for row in rows if (entity := self.get_entity(row["entity_id"]))]

    def delete_entity(self, entity_id: str) -> bool:
        with self._lock, closing(self._connect()) as conn, conn:
            cursor = conn.execute("DELETE FROM command_entities WHERE entity_id = ?", (entity_id,))
            return cursor.rowcount > 0

    def table_names(self) -> list[str]:
        with self._lock, closing(self._connect()) as conn, conn:
            rows = conn.execute("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name").fetchall()
        return [row["name"] for row in rows]

    def set_kv(self, namespace: str, key: str, value: dict[str, Any], status: str, timestamp: str) -> dict[str, Any]:
        with self._lock, closing(self._connect()) as conn, conn:
            row = conn.execute(
                "SELECT created_at FROM command_kv WHERE namespace = ? AND key = ?",
                (namespace, key),
            ).fetchone()
            created_at = row["created_at"] if row else timestamp
            conn.execute(
                """
                INSERT OR REPLACE INTO command_kv
                (namespace, key, value_json, status, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (namespace, key, json.dumps(value, ensure_ascii=False, sort_keys=True), status, created_at, timestamp),
            )
        return self.get_kv(namespace, key) or {}

    def get_kv(self, namespace: str, key: str) -> dict[str, Any] | None:
        with self._lock, closing(self._connect()) as conn, conn:
            row = conn.execute(
                "SELECT * FROM command_kv WHERE namespace = ? AND key = ?",
                (namespace, key),
            ).fetchone()
        if row is None:
            return None
        return {
            "id": row["key"],
            "root": row["namespace"],
            "name": row["key"],
            "value": json.loads(row["value_json"]),
            "status": row["status"],
            "created_at": row["created_at"],
            "updated_at": row["updated_at"],
        }

    def list_kv(self, namespace: str, limit: int = 100) -> list[dict[str, Any]]:
        with self._lock, closing(self._connect()) as conn, conn:
            rows = conn.execute(
                "SELECT key FROM command_kv WHERE namespace = ? ORDER BY updated_at DESC LIMIT ?",
                (namespace, max(1, min(int(limit), 500))),
            ).fetchall()
        return [item for row in rows if (item := self.get_kv(namespace, row["key"]))]

    def delete_kv(self, namespace: str, key: str) -> bool:
        with self._lock, closing(self._connect()) as conn, conn:
            cursor = conn.execute("DELETE FROM command_kv WHERE namespace = ? AND key = ?", (namespace, key))
            return cursor.rowcount > 0

    def clear_kv(self, namespace: str) -> int:
        with self._lock, closing(self._connect()) as conn, conn:
            cursor = conn.execute("DELETE FROM command_kv WHERE namespace = ?", (namespace,))
            return cursor.rowcount

    def append_event(
        self,
        event_id: str,
        root: str,
        event_type: str,
        payload: dict[str, Any],
        status: str,
        timestamp: str,
    ) -> dict[str, Any]:
        with self._lock, closing(self._connect()) as conn, conn:
            conn.execute(
                """
                INSERT OR REPLACE INTO command_events
                (event_id, root, event_type, payload_json, status, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (event_id, root, event_type, json.dumps(payload, ensure_ascii=False, sort_keys=True), status, timestamp),
            )
        return self.get_event(event_id) or {}

    def get_event(self, event_id: str) -> dict[str, Any] | None:
        with self._lock, closing(self._connect()) as conn, conn:
            row = conn.execute("SELECT * FROM command_events WHERE event_id = ?", (event_id,)).fetchone()
        if row is None:
            return None
        return {
            "id": row["event_id"],
            "root": row["root"],
            "name": row["event_type"],
            "value": json.loads(row["payload_json"]),
            "status": row["status"],
            "created_at": row["created_at"],
            "updated_at": row["created_at"],
        }

    def list_events(self, root: str, limit: int = 100) -> list[dict[str, Any]]:
        with self._lock, closing(self._connect()) as conn, conn:
            rows = conn.execute(
                "SELECT event_id FROM command_events WHERE root = ? ORDER BY created_at DESC LIMIT ?",
                (root, max(1, min(int(limit), 500))),
            ).fetchall()
        return [item for row in rows if (item := self.get_event(row["event_id"]))]

    def clear_events(self, root: str) -> int:
        with self._lock, closing(self._connect()) as conn, conn:
            cursor = conn.execute("DELETE FROM command_events WHERE root = ?", (root,))
            return cursor.rowcount

    def upsert_text_record(
        self,
        record_id: str,
        root: str,
        title: str,
        body: str,
        metadata: dict[str, Any],
        status: str,
        timestamp: str,
    ) -> dict[str, Any]:
        with self._lock, closing(self._connect()) as conn, conn:
            row = conn.execute("SELECT created_at FROM command_text_records WHERE record_id = ?", (record_id,)).fetchone()
            created_at = row["created_at"] if row else timestamp
            conn.execute(
                """
                INSERT OR REPLACE INTO command_text_records
                (record_id, root, title, body, metadata_json, status, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (record_id, root, title, body, json.dumps(metadata, ensure_ascii=False, sort_keys=True), status, created_at, timestamp),
            )
        return self.get_text_record(record_id) or {}

    def get_text_record(self, record_id: str) -> dict[str, Any] | None:
        with self._lock, closing(self._connect()) as conn, conn:
            row = conn.execute("SELECT * FROM command_text_records WHERE record_id = ?", (record_id,)).fetchone()
        if row is None:
            return None
        return {
            "id": row["record_id"],
            "root": row["root"],
            "name": row["title"],
            "value": {"body": row["body"], "metadata": json.loads(row["metadata_json"])},
            "status": row["status"],
            "created_at": row["created_at"],
            "updated_at": row["updated_at"],
        }

    def list_text_records(self, root: str, limit: int = 100) -> list[dict[str, Any]]:
        with self._lock, closing(self._connect()) as conn, conn:
            rows = conn.execute(
                "SELECT record_id FROM command_text_records WHERE root = ? ORDER BY updated_at DESC LIMIT ?",
                (root, max(1, min(int(limit), 500))),
            ).fetchall()
        return [item for row in rows if (item := self.get_text_record(row["record_id"]))]

    def delete_text_record(self, record_id: str) -> bool:
        with self._lock, closing(self._connect()) as conn, conn:
            cursor = conn.execute("DELETE FROM command_text_records WHERE record_id = ?", (record_id,))
            return cursor.rowcount > 0

    def clear_text_records(self, root: str) -> int:
        with self._lock, closing(self._connect()) as conn, conn:
            cursor = conn.execute("DELETE FROM command_text_records WHERE root = ?", (root,))
            return cursor.rowcount

    def upsert_schedule(
        self,
        schedule_id: str,
        root: str,
        name: str,
        command: dict[str, Any],
        schedule: dict[str, Any],
        status: str,
        timestamp: str,
    ) -> dict[str, Any]:
        next_run_at = str(schedule.get("next_run_at") or schedule.get("next") or "")
        last_run_at = str(schedule.get("last_run_at") or "")
        with self._lock, closing(self._connect()) as conn, conn:
            row = conn.execute("SELECT created_at FROM command_schedules WHERE schedule_id = ?", (schedule_id,)).fetchone()
            created_at = row["created_at"] if row else timestamp
            conn.execute(
                """
                INSERT OR REPLACE INTO command_schedules
                (schedule_id, root, name, command_json, schedule_json, status, next_run_at, last_run_at, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    schedule_id,
                    root,
                    name,
                    json.dumps(command, ensure_ascii=False, sort_keys=True),
                    json.dumps(schedule, ensure_ascii=False, sort_keys=True),
                    status,
                    next_run_at,
                    last_run_at,
                    created_at,
                    timestamp,
                ),
            )
        return self.get_schedule(schedule_id) or {}

    def get_schedule(self, schedule_id: str) -> dict[str, Any] | None:
        with self._lock, closing(self._connect()) as conn, conn:
            row = conn.execute("SELECT * FROM command_schedules WHERE schedule_id = ?", (schedule_id,)).fetchone()
        if row is None:
            return None
        return {
            "id": row["schedule_id"],
            "root": row["root"],
            "name": row["name"],
            "value": {
                "command": json.loads(row["command_json"]),
                "schedule": json.loads(row["schedule_json"]),
                "next_run_at": row["next_run_at"],
                "last_run_at": row["last_run_at"],
            },
            "status": row["status"],
            "created_at": row["created_at"],
            "updated_at": row["updated_at"],
        }

    def list_schedules(self, root: str, limit: int = 100) -> list[dict[str, Any]]:
        with self._lock, closing(self._connect()) as conn, conn:
            rows = conn.execute(
                "SELECT schedule_id FROM command_schedules WHERE root = ? ORDER BY updated_at DESC LIMIT ?",
                (root, max(1, min(int(limit), 500))),
            ).fetchall()
        return [item for row in rows if (item := self.get_schedule(row["schedule_id"]))]

    def delete_schedule(self, schedule_id: str) -> bool:
        with self._lock, closing(self._connect()) as conn, conn:
            cursor = conn.execute("DELETE FROM command_schedules WHERE schedule_id = ?", (schedule_id,))
            return cursor.rowcount > 0

    def clear_schedules(self, root: str) -> int:
        with self._lock, closing(self._connect()) as conn, conn:
            cursor = conn.execute("DELETE FROM command_schedules WHERE root = ?", (root,))
            return cursor.rowcount

    def record_usage_item(
        self,
        usage_id: str,
        root: str,
        metric: str,
        amount: float,
        unit: str,
        metadata: dict[str, Any],
        timestamp: str,
    ) -> dict[str, Any]:
        with self._lock, closing(self._connect()) as conn, conn:
            conn.execute(
                """
                INSERT OR REPLACE INTO command_usage
                (usage_id, root, metric, amount, unit, metadata_json, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (usage_id, root, metric, float(amount), unit, json.dumps(metadata, ensure_ascii=False, sort_keys=True), timestamp),
            )
        return self.get_usage(usage_id) or {}

    def get_usage(self, usage_id: str) -> dict[str, Any] | None:
        with self._lock, closing(self._connect()) as conn, conn:
            row = conn.execute("SELECT * FROM command_usage WHERE usage_id = ?", (usage_id,)).fetchone()
        if row is None:
            return None
        return {
            "id": row["usage_id"],
            "root": row["root"],
            "name": row["metric"],
            "value": {
                "amount": row["amount"],
                "unit": row["unit"],
                "metadata": json.loads(row["metadata_json"]),
            },
            "status": "recorded",
            "created_at": row["created_at"],
            "updated_at": row["created_at"],
        }

    def list_usage(self, root: str, limit: int = 100) -> list[dict[str, Any]]:
        with self._lock, closing(self._connect()) as conn, conn:
            rows = conn.execute(
                "SELECT usage_id FROM command_usage WHERE root = ? ORDER BY created_at DESC LIMIT ?",
                (root, max(1, min(int(limit), 500))),
            ).fetchall()
        return [item for row in rows if (item := self.get_usage(row["usage_id"]))]

    def clear_usage(self, root: str) -> int:
        with self._lock, closing(self._connect()) as conn, conn:
            cursor = conn.execute("DELETE FROM command_usage WHERE root = ?", (root,))
            return cursor.rowcount
