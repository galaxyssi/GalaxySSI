"""Immutable provider observations, separate from bounded UI progress history."""
from __future__ import annotations

import base64
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import threading
import time

from agent_task_recovery_query import IDENTITY_FIELDS, TASK_FIELDS
from agent_task_store import AgentTaskWriteConflict
from secure_state import decrypt_text, encrypt_text, seal_identifier

CONTRACT = "galaxyssi.desktop-tool-evidence/1"
PAGE_BYTES = 16 * 1024
INDEX_PAGE_SIZE = 20
TOOL_TYPES = frozenset({"commandExecution", "fileChange", "mcpToolCall", "dynamicToolCall", "webSearch"})
TRUST = "execution_observed_not_claim_verified"


def canonical(value) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def task_identity(task: dict) -> dict:
    return {key: task.get(field) for key, field in zip(IDENTITY_FIELDS, TASK_FIELDS)}


def valid_identity(value: dict) -> bool:
    return all(isinstance(value.get(key), str) and 1 <= len(value[key]) <= 200 for key in IDENTITY_FIELDS)


def completed_tool_observation(item: dict, *, thread_id: str, turn_id: str) -> dict | None:
    """Only operational completed items, never reasoning, plans or model replies."""
    if (not isinstance(item, dict) or not isinstance(item.get("type"), str) or item["type"] not in TOOL_TYPES
            or not all(isinstance(value, str) and 1 <= len(value) <= 200
                       for value in (item.get("id"), thread_id, turn_id))):
        return None
    # Detach the event before downstream progress adapters truncate or normalize it.
    try:
        return json.loads(canonical({"provider": "codex", "thread_id": thread_id, "turn_id": turn_id, "item": item}))
    except (TypeError, ValueError):
        return None


def observation_outcome(item: dict) -> str:
    result = item.get("result")
    failed = (str(item.get("status", "")).lower() in {"failed", "error", "cancelled", "canceled", "declined"}
              or bool(item.get("error")) or item.get("isError") is True
              or isinstance(result, dict) and result.get("isError") is True
              or type(item.get("exitCode")) is int and item["exitCode"] != 0)
    return "failed" if failed else "returned"


class EvidenceConflict(ValueError):
    """A completed provider item cannot be rewritten under the same identity."""


class AgentToolEvidence:
    def __init__(self, path: Path):
        # Share the Run database so capture and execution-generation checks are atomic.
        self.path = Path(path)
        self._lock = threading.RLock()
        self._initialized = False

    def _connect(self):
        db = sqlite3.connect(self.path, timeout=5)
        try:
            self._initialize(db)
        except Exception:
            db.close()
            raise
        return db

    def _initialize(self, db):
        db.execute("PRAGMA foreign_keys=ON")
        db.execute("PRAGMA synchronous=FULL")
        if not self._initialized:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS agent_tool_evidence (
                    scope TEXT NOT NULL, evidence_id TEXT NOT NULL, sequence INTEGER NOT NULL,
                    task_id TEXT NOT NULL REFERENCES agent_tasks(task_id) ON DELETE CASCADE,
                    digest TEXT NOT NULL, descriptor TEXT NOT NULL, phone_import INTEGER NOT NULL DEFAULT 1,
                    PRIMARY KEY(scope,evidence_id), UNIQUE(scope,sequence));
                CREATE TABLE IF NOT EXISTS agent_tool_evidence_pages (
                    scope TEXT NOT NULL, evidence_id TEXT NOT NULL, page INTEGER NOT NULL, body TEXT NOT NULL,
                    PRIMARY KEY(scope,evidence_id,page),
                    FOREIGN KEY(scope,evidence_id) REFERENCES agent_tool_evidence(scope,evidence_id) ON DELETE CASCADE);
            """)
            columns = {row[1] for row in db.execute("PRAGMA table_info(agent_tool_evidence)")}
            if "phone_import" not in columns:
                db.execute("ALTER TABLE agent_tool_evidence ADD COLUMN phone_import INTEGER NOT NULL DEFAULT 1")
            db.execute("CREATE INDEX IF NOT EXISTS tool_evidence_phone_import ON agent_tool_evidence(scope,phone_import,sequence)")
            self._initialized = True

    def _scope(self, fields: dict, generation: int) -> str:
        value = canonical([fields[key] for key in IDENTITY_FIELDS] + [generation]).decode()
        return hashlib.sha256(seal_identifier(self.path, value, purpose="tool-evidence-scope").encode()).hexdigest()

    @staticmethod
    def _purpose(scope: str, evidence_id: str, part) -> str:
        return f"tool-evidence-{scope[:24]}-{evidence_id[:24]}-{part}"

    @staticmethod
    def _current(db, fields, generation):
        row = db.execute("SELECT payload FROM agent_tasks WHERE task_id=?", (fields["task_id"],)).fetchone()
        if row is None:
            return None
        task = json.loads(row[0])
        if task_identity(task) != fields or task.get("execution_generation", 1) != generation:
            return None
        return task

    def record(self, snapshot: dict, observation: dict) -> dict | None:
        if not isinstance(observation, dict) or observation.get("provider") != "codex":
            return None
        fields, generation = task_identity(snapshot), snapshot.get("execution_generation", 1)
        if not valid_identity(fields) or type(generation) is not int or not 1 <= generation <= 2**53 - 1:
            return None
        item = observation.get("item")
        observation = completed_tool_observation(item, thread_id=observation.get("thread_id"),
                                                 turn_id=observation.get("turn_id"))
        if observation is None or fields["agent_id"] != "codex":
            return None
        scope = self._scope(fields, generation)
        evidence_id = hashlib.sha256(canonical([scope, observation["provider"], observation["thread_id"],
                                               observation["turn_id"], item["id"]])).hexdigest()
        body = canonical({"contract": CONTRACT, **fields, "execution_generation": generation,
                          "trust": TRUST, "coverage": "provider_payload_as_received", "observation": observation})
        digest = hashlib.sha256(body).hexdigest()
        with self._lock:
            db = self._connect()
            try:
                with db:
                    db.execute("BEGIN IMMEDIATE")
                    task = self._current(db, fields, generation)
                    if task is None:
                        raise AgentTaskWriteConflict("Evidence execution is no longer current")
                    from agent_worker_leases import require_task_writer
                    require_task_writer(db, task, None)
                    existing = db.execute("SELECT digest,descriptor FROM agent_tool_evidence WHERE scope=? AND evidence_id=?",
                                          (scope, evidence_id)).fetchone()
                    if existing:
                        if existing[0] != digest:
                            raise EvidenceConflict("Completed tool observation changed")
                        return self._descriptor(existing[1], scope, evidence_id, digest)
                    if task.get("status") in {"completed", "failed", "cancelled", "timed_out", "paused", "takeover"}:
                        raise AgentTaskWriteConflict("Task no longer accepts new tool evidence")
                    sequence = db.execute("SELECT COALESCE(MAX(sequence),0)+1 FROM agent_tool_evidence WHERE scope=?",
                                          (scope,)).fetchone()[0]
                    descriptor = {"evidence_id": evidence_id, "sha256": digest, "sequence": sequence,
                                  "total_bytes": len(body), "page_count": (len(body) + PAGE_BYTES - 1) // PAGE_BYTES,
                                  "item_type": item["type"], "outcome": observation_outcome(item), "trust": TRUST,
                                  "coverage": "provider_payload_as_received", "recorded_at": int(time.time() * 1000),
                                  "phone_import": not (item["type"] == "dynamicToolCall" and item.get("tool") == "collaboration_recall")}
                    encrypted = encrypt_text(self.path, canonical(descriptor).decode(),
                                             purpose=self._purpose(scope, evidence_id, "meta"))
                    db.execute("INSERT INTO agent_tool_evidence(scope,evidence_id,sequence,task_id,digest,descriptor,phone_import) "
                               "VALUES(?,?,?,?,?,?,?)", (scope, evidence_id, sequence, fields["task_id"], digest, encrypted,
                                                         int(descriptor["phone_import"])))
                    for page in range(descriptor["page_count"]):
                        chunk = base64.b64encode(body[page * PAGE_BYTES:(page + 1) * PAGE_BYTES]).decode()
                        encrypted = encrypt_text(self.path, chunk, purpose=self._purpose(scope, evidence_id, page))
                        db.execute("INSERT INTO agent_tool_evidence_pages VALUES(?,?,?,?)", (scope, evidence_id, page, encrypted))
                    return descriptor
            finally:
                db.close()

    def _descriptor(self, encrypted, scope, evidence_id, digest):
        result = json.loads(decrypt_text(self.path, encrypted, purpose=self._purpose(scope, evidence_id, "meta")))
        if result["evidence_id"] != evidence_id or result["sha256"] != digest:
            raise EvidenceConflict("Evidence index integrity check failed")
        return result

    def query(self, request: dict, *, client_route_id: str, phone_import: bool = False) -> dict | None:
        fields = {key: request.get(key) for key in IDENTITY_FIELDS}
        generation, nonce = request.get("execution_generation"), request.get("request_id")
        mode = request.get("mode", "index")
        if (not valid_identity(fields) or fields["client_route_id"] != client_route_id or not client_route_id
                or type(generation) is not int or not 1 <= generation <= 2**53 - 1
                or not isinstance(nonce, str) or not 1 <= len(nonce) <= 128
                or not isinstance(mode, str) or mode not in {"index", "page"}):
            return None
        cursor, page, evidence_id, digest = (request.get("after_sequence", 0), request.get("page_index"),
                                             request.get("evidence_id"), request.get("sha256"))
        if mode == "index" and (type(cursor) is not int or not 0 <= cursor <= 2**53 - 1):
            return None
        if mode == "page" and (type(page) is not int or not 0 <= page <= 2**31 - 1 or any(
                not isinstance(value, str) or not re.fullmatch("[a-f0-9]{64}", value) for value in (evidence_id, digest))):
            return None
        response = {**fields, "execution_generation": generation, "request_id": nonce,
                    "type": "agent_task_evidence", "contract": CONTRACT, "mode": mode, "status": "unavailable"}
        scope = self._scope(fields, generation)
        with self._lock:
            db = self._connect()
            try:
                with db:
                    db.execute("BEGIN")
                    if self._current(db, fields, generation) is None:
                        return response
                    if mode == "index":
                        # Keep full originals in the Desktop archive; do not send phone-owned recall bodies back to the phone.
                        selection = " AND phone_import=1" if phone_import else ""
                        rows = db.execute("SELECT evidence_id,digest,descriptor,sequence,phone_import FROM agent_tool_evidence "
                                          "WHERE scope=? AND sequence>?" + selection + " ORDER BY sequence LIMIT ?",
                                          (scope, cursor, INDEX_PAGE_SIZE + 1)).fetchall()
                        entries = [self._descriptor(row[2], scope, row[0], row[1]) for row in rows[:INDEX_PAGE_SIZE]]
                        if any(entry["sequence"] != row[3] or entry.get("phone_import", True) != bool(row[4])
                               for entry, row in zip(entries, rows)):
                            raise EvidenceConflict("Evidence sequence integrity check failed")
                        return {**response, "status": "ready", "entries": entries,
                                "next_sequence": entries[-1]["sequence"] if entries else cursor,
                                "has_more": len(rows) > INDEX_PAGE_SIZE,
                                "projection": "external_execution_observations" if phone_import else "all_observations",
                                "coverage": "observed_completed_items_only", "provider_history_complete": False}
                    row = db.execute("SELECT digest,descriptor FROM agent_tool_evidence WHERE scope=? AND evidence_id=?",
                                     (scope, evidence_id)).fetchone()
                    if row is None or row[0] != digest:
                        return response
                    descriptor = self._descriptor(row[1], scope, evidence_id, digest)
                    chunk = db.execute("SELECT body FROM agent_tool_evidence_pages WHERE scope=? AND evidence_id=? AND page=?",
                                       (scope, evidence_id, page)).fetchone()
                    if chunk is None or page >= descriptor["page_count"]:
                        return response
                    encoded = decrypt_text(self.path, chunk[0], purpose=self._purpose(scope, evidence_id, page))
                    raw = base64.b64decode(encoded, validate=True)
                    return {**response, **descriptor, "status": "ready", "page_index": page,
                            "page_sha256": hashlib.sha256(raw).hexdigest(), "data_b64": encoded}
            finally:
                db.close()
