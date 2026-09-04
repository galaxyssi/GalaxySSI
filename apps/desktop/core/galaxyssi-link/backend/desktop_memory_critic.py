"""Persistent memory hygiene for the GalaxySSI Desktop super agent."""
from __future__ import annotations

import hashlib
import json
import re
import sqlite3
import threading
from difflib import SequenceMatcher
from typing import Any, Callable

from desktop_memory_graph import project_memory_graph, retract_memory_graph_evidence


AUDIT_INTERVAL_MS = 24 * 60 * 60 * 1_000
MUTATION_THRESHOLD = 20
STALE_CANDIDATE_MS = 30 * 24 * 60 * 60 * 1_000
PROTECTED_KINDS = {"identity", "preference", "security"}
MERGEABLE_TEMPORAL_STATES = {"current", "planned"}
_WORD_PATTERN = re.compile(r"[a-z0-9]{2,}|[\u4e00-\u9fff]")


def initialize_critic_schema(connection: sqlite3.Connection) -> None:
    connection.execute(
        """
        CREATE TABLE IF NOT EXISTS memory_critic_state (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            last_run_at INTEGER NOT NULL DEFAULT 0,
            mutations_since_run INTEGER NOT NULL DEFAULT 0
        )
        """
    )
    connection.execute(
        "INSERT OR IGNORE INTO memory_critic_state (id, last_run_at, mutations_since_run) "
        "VALUES (1, 0, 0)"
    )
    connection.execute(
        """
        CREATE TABLE IF NOT EXISTS memory_critic_runs (
            id TEXT PRIMARY KEY,
            status TEXT NOT NULL,
            trigger TEXT NOT NULL,
            started_at INTEGER NOT NULL,
            completed_at INTEGER NOT NULL DEFAULT 0,
            audited_count INTEGER NOT NULL DEFAULT 0,
            finding_count INTEGER NOT NULL DEFAULT 0,
            action_count INTEGER NOT NULL DEFAULT 0,
            findings_json TEXT NOT NULL DEFAULT '[]',
            actions_json TEXT NOT NULL DEFAULT '[]',
            error TEXT NOT NULL DEFAULT ''
        )
        """
    )
    connection.execute(
        "CREATE INDEX IF NOT EXISTS idx_memory_critic_runs_started "
        "ON memory_critic_runs(started_at DESC)"
    )


def note_memory_mutation(connection: sqlite3.Connection) -> None:
    connection.execute(
        "UPDATE memory_critic_state "
        "SET mutations_since_run = mutations_since_run + 1 WHERE id = 1"
    )


def clear_memory_critic(connection: sqlite3.Connection) -> None:
    connection.execute("DELETE FROM memory_critic_runs")
    connection.execute(
        "UPDATE memory_critic_state SET last_run_at = 0, mutations_since_run = 0 WHERE id = 1"
    )


def _json_list(raw: Any) -> list[Any]:
    try:
        value = json.loads(str(raw or "[]"))
    except (TypeError, ValueError, json.JSONDecodeError):
        return []
    return value if isinstance(value, list) else []


def _canonical_text(value: str) -> str:
    return "".join(
        character
        for character in str(value or "").casefold()
        if character.isalnum()
    )


def _tokens(value: str) -> set[str]:
    return set(_WORD_PATTERN.findall(str(value or "").casefold()))


def _similarity(left: str, right: str) -> float:
    canonical_left = _canonical_text(left)
    canonical_right = _canonical_text(right)
    if not canonical_left or not canonical_right:
        return 0.0
    sequence = SequenceMatcher(None, canonical_left, canonical_right).ratio()
    left_tokens = _tokens(left)
    right_tokens = _tokens(right)
    union = left_tokens | right_tokens
    jaccard = len(left_tokens & right_tokens) / len(union) if union else 0.0
    return max(sequence, jaccard)


def _equivalent(left: sqlite3.Row, right: sqlite3.Row) -> bool:
    if str(left["namespace"]) != str(right["namespace"]):
        return False
    if str(left["kind"]) != str(right["kind"]):
        return False
    if str(left["kind"]) in PROTECTED_KINDS:
        return False
    if str(left["temporal_state"]) not in MERGEABLE_TEMPORAL_STATES:
        return False
    if str(right["temporal_state"]) != str(left["temporal_state"]):
        return False
    return _similarity(str(left["content"]), str(right["content"])) >= 0.94


def _deduplicate_json_rows(values: list[Any], maximum: int) -> list[Any]:
    result: list[Any] = []
    seen: set[str] = set()
    for value in values:
        serialized = json.dumps(value, ensure_ascii=False, sort_keys=True)
        if serialized in seen:
            continue
        seen.add(serialized)
        result.append(value)
    return result[-maximum:]


def _finding(
    kind: str,
    severity: str,
    summary: str,
    *,
    memory_ids: list[str] | None = None,
    candidate_ids: list[str] | None = None,
    action: str = "review",
    auto_applied: bool = False,
) -> dict[str, Any]:
    return {
        "kind": kind,
        "severity": severity,
        "summary": summary,
        "memory_ids": list(memory_ids or []),
        "candidate_ids": list(candidate_ids or []),
        "action": action,
        "auto_applied": auto_applied,
    }


def critic_status(
    connection: sqlite3.Connection,
    now_ms: int,
    *,
    history_limit: int = 20,
) -> dict[str, Any]:
    state = connection.execute(
        "SELECT last_run_at, mutations_since_run FROM memory_critic_state WHERE id = 1"
    ).fetchone()
    last_run_at = int(state["last_run_at"] if state else 0)
    mutations = int(state["mutations_since_run"] if state else 0)
    due_by_time = last_run_at == 0 or now_ms - last_run_at >= AUDIT_INTERVAL_MS
    due_by_mutation = mutations >= MUTATION_THRESHOLD
    rows = connection.execute(
        "SELECT * FROM memory_critic_runs ORDER BY started_at DESC LIMIT ?",
        (max(1, min(int(history_limit or 20), 100)),),
    ).fetchall()
    history = [_public_run(row) for row in rows]
    next_due_at = (
        now_ms
        if due_by_time or due_by_mutation
        else last_run_at + AUDIT_INTERVAL_MS
    )
    return {
        "due": due_by_time or due_by_mutation,
        "due_reason": (
            "initial"
            if last_run_at == 0
            else "mutation_threshold"
            if due_by_mutation
            else "time_interval"
            if due_by_time
            else "scheduled"
        ),
        "last_run_at": last_run_at,
        "next_due_at": next_due_at,
        "mutations_since_run": mutations,
        "mutation_threshold": MUTATION_THRESHOLD,
        "audit_interval_ms": AUDIT_INTERVAL_MS,
        "latest": history[0] if history else None,
        "history": history,
    }


def _public_run(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": str(row["id"]),
        "status": str(row["status"]),
        "trigger": str(row["trigger"]),
        "started_at": int(row["started_at"]),
        "completed_at": int(row["completed_at"]),
        "audited_count": int(row["audited_count"]),
        "finding_count": int(row["finding_count"]),
        "action_count": int(row["action_count"]),
        "findings": _json_list(row["findings_json"]),
        "actions": _json_list(row["actions_json"]),
        "error": str(row["error"]),
    }


def run_memory_critic(
    connection: sqlite3.Connection,
    now_ms: int,
    *,
    trigger: str = "manual",
    force: bool = True,
) -> dict[str, Any]:
    before = critic_status(connection, now_ms, history_limit=1)
    if not force and not before["due"]:
        return {
            "executed": False,
            "reason": "not_due",
            "status": before,
            "run": before["latest"],
        }

    run_sequence = int(
        connection.execute("SELECT COUNT(*) FROM memory_critic_runs").fetchone()[0]
    ) + 1
    run_id = hashlib.sha256(
        f"memory-critic:{now_ms}:{trigger}:{run_sequence}".encode("utf-8")
    ).hexdigest()[:32]
    connection.execute(
        "INSERT INTO memory_critic_runs "
        "(id, status, trigger, started_at) VALUES (?, 'running', ?, ?)",
        (run_id, str(trigger or "manual")[:48], now_ms),
    )

    memories = connection.execute(
        "SELECT * FROM memories WHERE status = 'active' ORDER BY created_at, id"
    ).fetchall()
    candidates = connection.execute(
        "SELECT * FROM memory_candidates "
        "WHERE status IN ('pending_review', 'conflicted') ORDER BY created_at, id"
    ).fetchall()
    findings: list[dict[str, Any]] = []
    actions: list[dict[str, Any]] = []

    expired = [
        row for row in memories
        if int(row["valid_until_at"] or 0) > 0
        and int(row["valid_until_at"]) <= now_ms
    ]
    for row in expired:
        memory_id = str(row["id"])
        connection.execute(
            "UPDATE memories SET status = 'retracted', temporal_state = 'deprecated', "
            "updated_at = ? WHERE id = ? AND status = 'active'",
            (now_ms, memory_id),
        )
        retract_memory_graph_evidence(connection, memory_id, now_ms)
        finding = _finding(
            "expired",
            "info",
            "Expired memory was retired.",
            memory_ids=[memory_id],
            action="retire",
            auto_applied=True,
        )
        findings.append(finding)
        actions.append({
            "kind": "retire",
            "memory_id": memory_id,
            "reason": "expired",
        })

    expired_ids = {str(row["id"]) for row in expired}
    active_rows = [row for row in memories if str(row["id"]) not in expired_ids]
    consumed: set[str] = set()
    for index, primary_candidate in enumerate(active_rows):
        primary_id = str(primary_candidate["id"])
        if primary_id in consumed:
            continue
        duplicate_rows = [
            row for row in active_rows[index + 1:]
            if str(row["id"]) not in consumed and _equivalent(primary_candidate, row)
        ]
        if not duplicate_rows:
            continue
        cluster = [primary_candidate, *duplicate_rows]
        primary = max(
            cluster,
            key=lambda row: (
                float(row["importance"]),
                float(row["confidence"]),
                len(_json_list(row["evidence_json"])),
                int(row["use_count"]),
                -int(row["created_at"]),
            ),
        )
        primary_id = str(primary["id"])
        duplicate_ids = [
            str(row["id"]) for row in cluster if str(row["id"]) != primary_id
        ]
        merged_evidence = _deduplicate_json_rows(
            [
                evidence
                for row in cluster
                for evidence in _json_list(row["evidence_json"])
            ],
            100,
        )
        merged_tags = sorted({
            str(tag)
            for row in cluster
            for tag in _json_list(row["tags_json"])
            if str(tag)
        })[:24]
        connection.execute(
            "UPDATE memories SET confidence = ?, importance = ?, tags_json = ?, "
            "evidence_json = ?, use_count = ?, updated_at = ? WHERE id = ?",
            (
                max(float(row["confidence"]) for row in cluster),
                max(float(row["importance"]) for row in cluster),
                json.dumps(merged_tags, ensure_ascii=False),
                json.dumps(merged_evidence, ensure_ascii=False),
                sum(int(row["use_count"]) for row in cluster),
                now_ms,
                primary_id,
            ),
        )
        for duplicate_id in duplicate_ids:
            connection.execute(
                "UPDATE memories SET status = 'retracted', temporal_state = 'deprecated', "
                "valid_until_at = ?, updated_at = ? WHERE id = ? AND status = 'active'",
                (now_ms, now_ms, duplicate_id),
            )
            retract_memory_graph_evidence(connection, duplicate_id, now_ms)
            consumed.add(duplicate_id)
        refreshed = connection.execute(
            "SELECT * FROM memories WHERE id = ?",
            (primary_id,),
        ).fetchone()
        project_memory_graph(connection, refreshed)
        findings.append(_finding(
            "duplicate",
            "info",
            "Equivalent memories were consolidated.",
            memory_ids=[primary_id, *duplicate_ids],
            action="consolidate",
            auto_applied=True,
        ))
        actions.append({
            "kind": "consolidate",
            "primary_memory_id": primary_id,
            "retired_memory_ids": duplicate_ids,
        })

    current_rows = connection.execute(
        "SELECT * FROM memories WHERE status = 'active' ORDER BY updated_at DESC"
    ).fetchall()
    low_confidence = [
        str(row["id"]) for row in current_rows
        if float(row["confidence"]) < 0.5 and int(row["use_count"]) >= 3
    ]
    if low_confidence:
        findings.append(_finding(
            "low_confidence_reused",
            "review",
            "Frequently reused low-confidence memory needs review.",
            memory_ids=low_confidence,
        ))

    conflicted = [
        str(row["id"]) for row in candidates if str(row["status"]) == "conflicted"
    ]
    if conflicted:
        findings.append(_finding(
            "unresolved_conflict",
            "attention",
            "Conflicting memory candidates need review.",
            candidate_ids=conflicted,
        ))

    stale = [
        str(row["id"]) for row in candidates
        if now_ms - int(row["created_at"]) >= STALE_CANDIDATE_MS
    ]
    if stale:
        findings.append(_finding(
            "stale_candidate",
            "attention",
            "Old memory candidates need review.",
            candidate_ids=stale,
        ))

    completed_at = now_ms
    connection.execute(
        "UPDATE memory_critic_runs SET status = 'completed', completed_at = ?, "
        "audited_count = ?, finding_count = ?, action_count = ?, findings_json = ?, "
        "actions_json = ? WHERE id = ?",
        (
            completed_at,
            len(memories) + len(candidates),
            len(findings),
            len(actions),
            json.dumps(findings, ensure_ascii=False),
            json.dumps(actions, ensure_ascii=False),
            run_id,
        ),
    )
    connection.execute(
        "UPDATE memory_critic_state SET last_run_at = ?, mutations_since_run = 0 WHERE id = 1",
        (completed_at,),
    )
    row = connection.execute(
        "SELECT * FROM memory_critic_runs WHERE id = ?",
        (run_id,),
    ).fetchone()
    return {
        "executed": True,
        "reason": str(trigger or "manual"),
        "run": _public_run(row),
        "status": critic_status(connection, now_ms, history_limit=20),
    }


def record_failed_memory_critic(
    connection: sqlite3.Connection,
    now_ms: int,
    *,
    trigger: str,
    error: str,
) -> dict[str, Any]:
    run_sequence = int(
        connection.execute("SELECT COUNT(*) FROM memory_critic_runs").fetchone()[0]
    ) + 1
    run_id = hashlib.sha256(
        f"memory-critic-failed:{now_ms}:{trigger}:{run_sequence}".encode("utf-8")
    ).hexdigest()[:32]
    connection.execute(
        "INSERT INTO memory_critic_runs "
        "(id, status, trigger, started_at, completed_at, error) "
        "VALUES (?, 'failed', ?, ?, ?, ?)",
        (
            run_id,
            str(trigger or "manual")[:48],
            now_ms,
            now_ms,
            str(error or "Memory critic failed")[:500],
        ),
    )
    row = connection.execute(
        "SELECT * FROM memory_critic_runs WHERE id = ?",
        (run_id,),
    ).fetchone()
    return _public_run(row)


class DesktopMemoryCriticRuntime:
    def __init__(
        self,
        *,
        interval_seconds: float = 60.0,
        store_factory: Callable[[], Any] | None = None,
    ) -> None:
        self.interval_seconds = max(1.0, float(interval_seconds))
        self._store_factory = store_factory
        self._stop_event = threading.Event()
        self._thread: threading.Thread | None = None

    def _store(self):
        if self._store_factory is not None:
            return self._store_factory()
        from desktop_memory import desktop_memory_store

        return desktop_memory_store()

    def _run(self) -> None:
        while not self._stop_event.is_set():
            try:
                self._store().run_critic(force=False, trigger="scheduled")
            except Exception:
                # A failed maintenance pass must never stop the Desktop backend.
                pass
            self._stop_event.wait(self.interval_seconds)

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._stop_event.clear()
        self._thread = threading.Thread(
            target=self._run,
            name="galaxyssi-memory-critic",
            daemon=True,
        )
        self._thread.start()

    def stop(self) -> None:
        self._stop_event.set()
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=min(5.0, self.interval_seconds + 0.5))
        self._thread = None


_RUNTIME: DesktopMemoryCriticRuntime | None = None
_RUNTIME_LOCK = threading.Lock()


def desktop_memory_critic_runtime() -> DesktopMemoryCriticRuntime:
    global _RUNTIME
    with _RUNTIME_LOCK:
        if _RUNTIME is None:
            _RUNTIME = DesktopMemoryCriticRuntime()
        return _RUNTIME
