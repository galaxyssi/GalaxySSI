"""Immutable, execution-scoped usage journal separate from UI and estimates."""
from __future__ import annotations

import hashlib
from contextlib import closing
import json
import os
from pathlib import Path
import sqlite3
import threading
import time

from agent_task_store import AgentTaskWriteConflict
from agent_tool_evidence import canonical, task_identity, valid_identity
from codex_provider_usage import CONTRACT, COUNTERS, MAX_COUNTER, normalize
from secure_state import (MASTER_KEY_ENV, MASTER_KEY_NAME, SecureStateError,
                          decrypt_text, encrypt_text, seal_identifier)

PAGE_SIZE = 100


def _validated(observation):
    if (not isinstance(observation, dict) or observation.get("contract") != CONTRACT
            or observation.get("provider") != "codex"):
        return None
    # Reconstruct through an allowlist so callers cannot persist content or secrets.
    params = {"threadId": observation.get("provider_thread_id"), "turnId": observation.get("provider_turn_id")}
    if observation.get("kind") == "usage_snapshot":
        params["tokenUsage"] = {
            key: {field: (observation.get(key) or {}).get(name) for field, name in COUNTERS.items()}
            for key in ("total", "last") if isinstance(observation.get(key), dict)
        }
        params["tokenUsage"]["modelContextWindow"] = observation.get("model_context_window")
    value = normalize(params, model=observation.get("requested_model"),
                      effort=observation.get("requested_reasoning_effort"), kind=observation.get("kind"),
                      status=observation.get("provider_status", ""))
    # Invalid numeric payloads were already redacted by the provider boundary.
    # Keep its bounded diagnostic codes, but never arbitrary diagnostic text.
    if value is not None and value.get("kind") == "usage_snapshot":
        allowed = {"tokenUsage:invalid_or_missing_object", "total:invalid_or_missing_object", "last:invalid_or_missing_object",
                   "modelContextWindow:invalid_or_missing_counter"}
        allowed.update(f"{key}.{field}:invalid_or_missing_counter" for key in ("total", "last") for field in COUNTERS)
        allowed.update(f"{key}.{field}:exceeds_parent_counter" for key in ("total", "last")
                       for field in ("cached_input_tokens", "reasoning_output_tokens"))
        issues = observation.get("issues")
        if not isinstance(issues, list) or len(issues) > len(allowed) or any(
                not isinstance(issue, str) or issue not in allowed for issue in issues):
            return None
        value["issues"] = sorted(set(value["issues"]) | set(issues))
    return value


class AgentProviderUsage:
    def __init__(self, path: Path):
        self.path = Path(path)
        self._lock = threading.RLock()
        self._initialized = False

    def _scope(self, fields, generation):
        encoded = canonical([fields, generation]).decode()
        return hashlib.sha256(seal_identifier(self.path, encoded, purpose="provider-usage-scope").encode()).hexdigest()

    def _require_existing_key(self, db):
        key = self.path.resolve().parent / MASTER_KEY_NAME
        if not (str(os.environ.get(MASTER_KEY_ENV) or "").strip() or key.is_file() or key.with_suffix(".bak").is_file()):
            raise SecureStateError("Existing usage journal key is unavailable; refusing to replace it")
        row = db.execute("SELECT scope,event_id,body FROM agent_provider_usage LIMIT 1").fetchone()
        if row is not None:
            # A wrong override/key must not derive an empty, apparently valid scope.
            decrypt_text(self.path, row[2], purpose=self._purpose(row[0], row[1]))

    @staticmethod
    def _purpose(scope, event_id):
        return f"provider-usage-{scope[:24]}-{event_id[:24]}"

    @staticmethod
    def _task(db, fields):
        row = db.execute("SELECT payload FROM agent_tasks WHERE task_id=?", (fields["task_id"],)).fetchone()
        task = json.loads(row[0]) if row else None
        return task if task is not None and task_identity(task) == fields else None

    def _initialize(self, db):
        if self._initialized:
            return
        db.execute("""CREATE TABLE IF NOT EXISTS agent_provider_usage (
            scope TEXT NOT NULL, event_id TEXT NOT NULL, sequence INTEGER NOT NULL,
            task_id TEXT NOT NULL REFERENCES agent_tasks(task_id) ON DELETE CASCADE,
            digest TEXT NOT NULL, body TEXT NOT NULL,
            PRIMARY KEY(scope,event_id), UNIQUE(scope,sequence))""")
        db.commit()
        self._initialized = True

    def record(self, snapshot: dict, observation: dict) -> dict | None:
        fields, generation = task_identity(snapshot), snapshot.get("execution_generation", 1)
        observation = _validated(observation)
        if (not valid_identity(fields) or fields["agent_id"] != "codex" or observation is None
                or type(generation) is not int or not 1 <= generation <= MAX_COUNTER):
            return None
        content = {"contract": CONTRACT, **fields, "execution_generation": generation, "observation": observation}
        event_id = hashlib.sha256(canonical(content)).hexdigest()
        with self._lock:
            db = sqlite3.connect(self.path, timeout=2)
            try:
                db.execute("PRAGMA foreign_keys=ON")
                db.execute("PRAGMA synchronous=FULL")
                self._initialize(db)
                with db:
                    db.execute("BEGIN IMMEDIATE")
                    task = self._task(db, fields)
                    if task is None or task.get("execution_generation", 1) != generation:
                        raise AgentTaskWriteConflict("Provider usage execution is no longer current")
                    from agent_worker_leases import require_task_writer
                    require_task_writer(db, task, None)
                    if db.execute("SELECT 1 FROM agent_provider_usage LIMIT 1").fetchone():
                        self._require_existing_key(db)
                    scope = self._scope(fields, generation)
                    row = db.execute("SELECT sequence,digest,body FROM agent_provider_usage WHERE scope=? AND event_id=?",
                                     (scope, event_id)).fetchone()
                    if row is not None:
                        return self._decode(row, scope, event_id, fields, generation)
                    # Late usage is allowed for the same finished execution; it never changes task status.
                    sequence = db.execute("SELECT COALESCE(MAX(sequence),0)+1 FROM agent_provider_usage WHERE scope=?",
                                          (scope,)).fetchone()[0]
                    entry = {**content, "event_id": event_id, "sequence": sequence, "recorded_at_ms": time.time_ns() // 1_000_000}
                    body = canonical(entry).decode()
                    digest = hashlib.sha256(body.encode()).hexdigest()
                    encrypted = encrypt_text(self.path, body, purpose=self._purpose(scope, event_id))
                    db.execute("INSERT INTO agent_provider_usage VALUES(?,?,?,?,?,?)",
                               (scope, event_id, sequence, fields["task_id"], digest, encrypted))
                    return entry
            finally:
                db.close()

    def _decode(self, row, scope, event_id, fields, generation):
        sequence, digest, encrypted = row
        body = decrypt_text(self.path, encrypted, purpose=self._purpose(scope, event_id))
        entry = json.loads(body)
        if (hashlib.sha256(body.encode()).hexdigest() != digest or entry.get("event_id") != event_id
                or entry.get("sequence") != sequence or entry.get("execution_generation") != generation
                or any(entry.get(key) != value for key, value in fields.items())):
            raise ValueError("Provider usage integrity check failed")
        return entry

    def observed_generations(self, fields: dict, *, client_route_id: str) -> list[int]:
        """Read observed execution scopes only; absent generations remain unmeasured."""
        if (not valid_identity(fields) or fields["agent_id"] != "codex"
                or fields["client_route_id"] != client_route_id):
            raise ValueError("Exact authenticated Codex task identity required")
        if not self.path.is_file():
            return []
        with self._lock, closing(sqlite3.connect(self.path.resolve().as_uri() + "?mode=ro", uri=True, timeout=2)) as db:
            db.execute("BEGIN")
            task = self._task(db, fields)
            if task is None:
                raise ValueError("Usage task identity mismatch")
            if not db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='agent_provider_usage'").fetchone():
                return []
            rows = db.execute("SELECT scope,event_id,sequence,digest,body FROM agent_provider_usage "
                              "WHERE task_id=? AND sequence=1", (fields["task_id"],)).fetchall()
            if not rows:
                return []
            self._require_existing_key(db)
            generations = set()
            for scope, event_id, sequence, digest, encrypted in rows:
                value = json.loads(decrypt_text(self.path, encrypted, purpose=self._purpose(scope, event_id)))
                generation = value.get("execution_generation")
                if (type(generation) is not int or not 1 <= generation <= task.get("execution_generation", 1)
                        or self._scope(fields, generation) != scope or generation in generations):
                    raise ValueError("Invalid usage execution scope")
                self._decode((sequence, digest, encrypted), scope, event_id, fields, generation)
                generations.add(generation)
            return sorted(generations)

    def query(self, request: dict, *, client_route_id: str) -> dict | None:
        from agent_task_recovery_query import IDENTITY_FIELDS
        fields = {key: request.get(key) for key in IDENTITY_FIELDS}
        generation, cursor = request.get("execution_generation"), request.get("after_sequence", 0)
        through = request.get("through_sequence")
        if (not valid_identity(fields) or fields["client_route_id"] != client_route_id or not client_route_id
                or fields["agent_id"] != "codex" or type(generation) is not int or not 1 <= generation <= MAX_COUNTER
                or type(cursor) is not int or not 0 <= cursor <= MAX_COUNTER
                or (through is not None and (type(through) is not int or not 0 <= through <= MAX_COUNTER))):
            return None
        result = {"contract": CONTRACT, **fields, "execution_generation": generation, "status": "unavailable",
                  "coverage": "observed_notifications_only", "provider_history_complete": False,
                  "request_count": None, "billed_cost": None, "task_token_total": None}
        if not self.path.is_file():
            return result
        with self._lock:
            db = sqlite3.connect(self.path.resolve().as_uri() + "?mode=ro", uri=True, timeout=2)
            try:
                with db:
                    db.execute("BEGIN")
                    task = self._task(db, fields)
                    if task is None or task.get("execution_generation", 1) < generation:
                        return result
                    if not db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='agent_provider_usage'").fetchone():
                        return result
                    if not db.execute("SELECT 1 FROM agent_provider_usage LIMIT 1").fetchone():
                        return {**result, "status": "ready", "entries": [], "has_more": False,
                                "observed_through_sequence": 0, "next_sequence": cursor}
                    self._require_existing_key(db)
                    scope = self._scope(fields, generation)
                    latest = db.execute("SELECT COALESCE(MAX(sequence),0) FROM agent_provider_usage WHERE scope=?",
                                        (scope,)).fetchone()[0]
                    upper = latest if through is None else min(through, latest)
                    rows = db.execute("SELECT event_id,sequence,digest,body FROM agent_provider_usage "
                                      "WHERE scope=? AND sequence>? AND sequence<=? ORDER BY sequence LIMIT ?",
                                      (scope, cursor, upper, PAGE_SIZE + 1)).fetchall()
                    entries = [self._decode(row[1:], scope, row[0], fields, generation) for row in rows[:PAGE_SIZE]]
                    return {**result, "status": "ready", "entries": entries, "has_more": len(rows) > PAGE_SIZE,
                            "observed_through_sequence": upper,
                            "next_sequence": entries[-1]["sequence"] if entries else cursor}
            finally:
                db.close()
