"""Local long-term memory for the SignalASI Desktop super agent."""
from __future__ import annotations

import hashlib
import json
import os
import re
import sqlite3
import threading
import time
from contextlib import contextmanager
from functools import wraps
from pathlib import Path
from typing import Any


MAX_CONTENT_CHARS = 2_000
REVIEW_KINDS = {"identity", "preference", "security"}
MEMORY_NAMESPACES = {"general", "user", "project", "device", "security"}
TEMPORAL_STATES = {"current", "historical", "planned", "deprecated", "conflicted", "pending"}
SECRET_PATTERN = re.compile(
    r"(?i)(api[_ -]?key|access[_ -]?token|password|passwd|secret|authorization)\s*[:=]\s*\S+"
)
PRIVATE_MEMORY_PATTERN = re.compile(
    r"(?i)(?:do not (?:remember|save)|private mode|this (?:is|contains) confidential|confidential\s*[:=]|"
    r"\u4e0d\u8981\u8bb0(?:\u4f4f)?|\u4e0d\u8981\u4fdd\u5b58|\u9690\u79c1\u6a21\u5f0f|\u79c1\u5bc6)"
)
GREETING_PATTERN = re.compile(r"(?i)^\s*(hello|hi|hey|thanks?|ok(?:ay)?|\u4f60\u597d|\u8c22\u8c22|\u597d\u7684)[.!\s]*$")
VOLATILE_PATTERN = re.compile(
    r"(?i)(?:\b(?:today|now|current|latest|weather|news|status|cpu|ram|memory usage|battery|process(?:es)?)\b|"
    r"\u4eca\u5929|\u73b0\u5728|\u5f53\u524d|\u6700\u65b0|\u5929\u6c14|\u65b0\u95fb|\u7cfb\u7edf\u72b6\u6001|"
    r"\u7535\u91cf|\u5185\u5b58\u4f7f\u7528|\u8fdb\u7a0b)"
)
FAILED_OUTCOME_PATTERN = re.compile(
    r"(?i)(?:timed?\s*out|failed|could not|unavailable|no response|\u8d85\u65f6|\u5931\u8d25|\u65e0\u6cd5|\u65e0\u54cd\u5e94)"
)
WORD_PATTERN = re.compile(r"[a-z0-9_\-]{2,}|[\u4e00-\u9fff]")
REPLACEMENT_PATTERN = re.compile(
    r"(?i)(?:\b(?:now|changed? to|renamed? to|replaced? by|no longer|removed|disabled|enabled)\b|"
    r"\u73b0\u5728|\u6539\u4e3a|\u66f4\u540d\u4e3a|\u66ff\u6362\u4e3a|\u4e0d\u518d|"
    r"\u5df2\u79fb\u9664|\u5df2\u5220\u9664|\u5df2\u505c\u7528|\u5df2\u542f\u7528)"
)
PLANNED_PATTERN = re.compile(
    r"(?i)(?:\b(?:plan|planned|will|next|todo|goal)\b|"
    r"\u8ba1\u5212|\u5c06\u8981|\u4e0b\u4e00\u6b65|\u5f85\u529e|\u76ee\u6807)"
)
HISTORICAL_PATTERN = re.compile(
    r"(?i)(?:\b(?:previously|formerly|completed|finished|historical)\b|"
    r"\u4e4b\u524d|\u66fe\u7ecf|\u5df2\u5b8c\u6210|\u5386\u53f2)"
)


def _state_root() -> Path:
    configured = str(os.environ.get("SIGNALASI_STATE_DIR") or "").strip()
    return Path(configured) if configured else Path(os.environ.get("APPDATA") or Path.home()) / "SignalASI"


def _clean(value: str, maximum: int = MAX_CONTENT_CHARS) -> str:
    return re.sub(r"\s+", " ", str(value or "")).strip()[:maximum]


def _tokens(value: str) -> set[str]:
    text = _clean(value).casefold()
    tokens = set(WORD_PATTERN.findall(text))
    cjk = "".join(character for character in text if "\u4e00" <= character <= "\u9fff")
    tokens.update(cjk[index:index + 2] for index in range(max(0, len(cjk) - 1)))
    return {token for token in tokens if token}


def _memory_key(content: str, kind: str) -> str:
    normalized = _clean(content).casefold()
    if kind == "identity" and re.search(
        r"(?i)(?:\b(?:my name is|call me|display name)\b|\u6211\u53eb|\u79f0\u547c\u6211|\u6635\u79f0)",
        normalized,
    ):
        return "identity:display-name"
    if kind == "preference":
        categories = (
            ("response-language", r"(?i)(?:\b(?:language|english|chinese)\b|\u8bed\u8a00|\u4e2d\u6587|\u82f1\u6587)"),
            ("response-style", r"(?i)(?:\b(?:response style|concise|detailed|tone)\b|\u56de\u590d\u98ce\u683c|\u7b80\u6d01|\u8be6\u7ec6|\u8bed\u6c14)"),
            ("default-model", r"(?i)(?:\b(?:default model|model)\b|\u9ed8\u8ba4\u6a21\u578b|\u6a21\u578b)"),
            ("appearance", r"(?i)(?:\b(?:theme|appearance|dark mode)\b|\u4e3b\u9898|\u5916\u89c2|\u6df1\u8272\u6a21\u5f0f)"),
        )
        for category, pattern in categories:
            if re.search(pattern, normalized):
                return f"preference:{category}"
    if kind == "security" and re.search(
        r"(?i)(?:\b(?:confirm|approval|permission|external message)\b|"
        r"\u786e\u8ba4|\u5ba1\u6279|\u6743\u9650|\u5916\u90e8\u6d88\u606f)",
        normalized,
    ):
        return "security:approval-policy"
    separators = (" is ", " are ", " should ", " uses ", " use ", "\u6539\u4e3a", "\u8bbe\u7f6e\u4e3a", "\u9ed8\u8ba4")
    topic = normalized
    for separator in separators:
        if separator in normalized:
            prefix = normalized.split(separator, 1)[0].strip()
            if 2 <= len(prefix) <= 120:
                topic = prefix
                break
    digest = hashlib.sha256(f"{kind}:{topic}".encode("utf-8")).hexdigest()[:32]
    return f"{kind}:{digest}"


def _normalize_kind(value: str) -> str:
    return re.sub(r"[^a-z0-9_-]", "", str(value or "fact").casefold())[:32] or "fact"


def _normalize_namespace(value: str, kind: str, content: str) -> str:
    requested = re.sub(r"[^a-z0-9_-]", "", str(value or "").casefold())[:32]
    if requested in MEMORY_NAMESPACES:
        return requested
    if kind in {"identity", "preference", "explicit"}:
        return "user"
    if kind == "security":
        return "security"
    if kind in {"device", "device_state"} or re.search(
        r"(?i)(?:\b(?:phone|desktop|computer|device|android|windows)\b|"
        r"\u624b\u673a|\u7535\u8111|\u8bbe\u5907)",
        content,
    ):
        return "device"
    if kind in {"decision", "goal", "project_state", "episode"}:
        return "project"
    return "general"


def _infer_temporal_state(content: str, kind: str) -> str:
    if kind == "goal" or PLANNED_PATTERN.search(content):
        return "planned"
    if HISTORICAL_PATTERN.search(content):
        return "historical"
    return "current"


def _json_list(raw: Any) -> list[Any]:
    try:
        value = json.loads(str(raw or "[]"))
    except (TypeError, ValueError, json.JSONDecodeError):
        return []
    return value if isinstance(value, list) else []


def _synchronized(method):
    @wraps(method)
    def wrapped(self, *args, **kwargs):
        with self._lock:
            return method(self, *args, **kwargs)

    return wrapped


class DesktopMemoryStore:
    def __init__(self, path: Path | None = None, now=time.time) -> None:
        self.path = Path(path) if path else _state_root() / "desktop-memory.db"
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.now = now
        self._lock = threading.RLock()
        self._initialize()

    @contextmanager
    def _connect(self):
        connection = sqlite3.connect(self.path, timeout=10)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute("PRAGMA synchronous=NORMAL")
        try:
            yield connection
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()

    def _initialize(self) -> None:
        with self._lock, self._connect() as connection:
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS memories (
                    id TEXT PRIMARY KEY,
                    memory_key TEXT NOT NULL,
                    namespace TEXT NOT NULL DEFAULT 'general',
                    kind TEXT NOT NULL,
                    content TEXT NOT NULL,
                    status TEXT NOT NULL,
                    temporal_state TEXT NOT NULL DEFAULT 'current',
                    confidence REAL NOT NULL,
                    importance REAL NOT NULL,
                    source_conversation_id TEXT NOT NULL,
                    source_task_id TEXT NOT NULL,
                    tags_json TEXT NOT NULL,
                    evidence_json TEXT NOT NULL DEFAULT '[]',
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    last_accessed_at INTEGER NOT NULL,
                    use_count INTEGER NOT NULL DEFAULT 0,
                    supersedes_id TEXT NOT NULL DEFAULT '',
                    valid_from_at INTEGER NOT NULL DEFAULT 0,
                    valid_until_at INTEGER NOT NULL DEFAULT 0
                )
                """
            )
            self._ensure_columns(
                connection,
                "memories",
                {
                    "namespace": "TEXT NOT NULL DEFAULT 'general'",
                    "temporal_state": "TEXT NOT NULL DEFAULT 'current'",
                    "evidence_json": "TEXT NOT NULL DEFAULT '[]'",
                    "valid_from_at": "INTEGER NOT NULL DEFAULT 0",
                    "valid_until_at": "INTEGER NOT NULL DEFAULT 0",
                },
            )
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS memory_candidates (
                    id TEXT PRIMARY KEY,
                    memory_key TEXT NOT NULL,
                    namespace TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    content TEXT NOT NULL,
                    status TEXT NOT NULL,
                    risk TEXT NOT NULL,
                    temporal_state TEXT NOT NULL,
                    intended_temporal_state TEXT NOT NULL,
                    confidence REAL NOT NULL,
                    importance REAL NOT NULL,
                    source_conversation_id TEXT NOT NULL,
                    source_task_id TEXT NOT NULL,
                    tags_json TEXT NOT NULL,
                    evidence_json TEXT NOT NULL,
                    conflicting_memory_ids_json TEXT NOT NULL,
                    evolution_action TEXT NOT NULL DEFAULT 'create',
                    target_memory_ids_json TEXT NOT NULL DEFAULT '[]',
                    resulting_memory_id TEXT NOT NULL DEFAULT '',
                    created_at INTEGER NOT NULL,
                    reviewed_at INTEGER NOT NULL DEFAULT 0,
                    review_note TEXT NOT NULL DEFAULT ''
                )
                """
            )
            self._ensure_columns(
                connection,
                "memory_candidates",
                {
                    "evolution_action": "TEXT NOT NULL DEFAULT 'create'",
                    "target_memory_ids_json": "TEXT NOT NULL DEFAULT '[]'",
                },
            )
            connection.execute("CREATE INDEX IF NOT EXISTS idx_memory_status ON memories(status, updated_at DESC)")
            connection.execute("CREATE INDEX IF NOT EXISTS idx_memory_key ON memories(namespace, memory_key, status)")
            connection.execute(
                "CREATE INDEX IF NOT EXISTS idx_memory_candidate_status "
                "ON memory_candidates(status, created_at DESC)"
            )

    @staticmethod
    def _ensure_columns(
        connection: sqlite3.Connection,
        table: str,
        columns: dict[str, str],
    ) -> None:
        existing = {
            str(row["name"])
            for row in connection.execute(f"PRAGMA table_info({table})").fetchall()
        }
        for name, definition in columns.items():
            if name not in existing:
                connection.execute(f"ALTER TABLE {table} ADD COLUMN {name} {definition}")

    @_synchronized
    def remember(
        self,
        content: str,
        *,
        kind: str = "fact",
        confidence: float = 0.75,
        importance: float = 0.55,
        conversation_id: str = "",
        task_id: str = "",
        tags: list[str] | None = None,
        key: str = "",
        namespace: str = "",
        temporal_state: str = "",
        evidence: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any] | None:
        content = _clean(content)
        if (
            len(content) < 4
            or SECRET_PATTERN.search(content)
            or PRIVATE_MEMORY_PATTERN.search(content)
            or GREETING_PATTERN.fullmatch(content)
        ):
            return None
        kind = _normalize_kind(kind)
        namespace = _normalize_namespace(namespace, kind, content)
        temporal_state = str(temporal_state or _infer_temporal_state(content, kind)).casefold()
        if temporal_state not in TEMPORAL_STATES:
            temporal_state = "current"
        key = str(key or _memory_key(content, kind))[:160]
        now_ms = int(self.now() * 1_000)
        memory_id = hashlib.sha256(f"{key}:{content}:{now_ms}".encode("utf-8")).hexdigest()[:32]
        supersedes_id = ""
        evidence_rows = list(evidence or [])
        if conversation_id or task_id:
            source_evidence = {
                "conversation_id": str(conversation_id)[:160],
                "task_id": str(task_id)[:160],
                "observed_at": now_ms,
            }
            if not any(
                str(item.get("conversation_id") or "") == source_evidence["conversation_id"]
                and str(item.get("task_id") or "") == source_evidence["task_id"]
                for item in evidence_rows
                if isinstance(item, dict)
            ):
                evidence_rows.append(source_evidence)
        with self._lock, self._connect() as connection:
            previous = connection.execute(
                "SELECT * FROM memories WHERE namespace = ? AND memory_key = ? "
                "AND status = 'active' ORDER BY updated_at DESC LIMIT 1",
                (namespace, key),
            ).fetchone()
            if previous and _clean(previous["content"]).casefold() == content.casefold():
                merged_evidence = (
                    _json_list(previous["evidence_json"]) + evidence_rows
                )[-100:]
                connection.execute(
                    "UPDATE memories SET confidence = ?, importance = ?, updated_at = ?, "
                    "use_count = use_count + 1, evidence_json = ? WHERE id = ?",
                    (
                        max(float(previous["confidence"]), confidence),
                        max(float(previous["importance"]), importance),
                        now_ms,
                        json.dumps(merged_evidence, ensure_ascii=False),
                        previous["id"],
                    ),
                )
                return self.get(str(previous["id"]))
            if previous:
                supersedes_id = str(previous["id"])
                connection.execute(
                    "UPDATE memories SET status = 'superseded', temporal_state = 'deprecated', "
                    "valid_until_at = ?, updated_at = ? WHERE id = ?",
                    (now_ms, now_ms, supersedes_id),
                )
            connection.execute(
                """
                INSERT INTO memories (
                    id, memory_key, namespace, kind, content, status, temporal_state,
                    confidence, importance, source_conversation_id, source_task_id,
                    tags_json, evidence_json, created_at, updated_at, last_accessed_at,
                    use_count, supersedes_id, valid_from_at, valid_until_at
                ) VALUES (?, ?, ?, ?, ?, 'active', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, 0)
                """,
                (
                    memory_id,
                    key,
                    namespace,
                    kind,
                    content,
                    temporal_state,
                    max(0.0, min(1.0, confidence)),
                    max(0.0, min(1.0, importance)),
                    str(conversation_id)[:160],
                    str(task_id)[:160],
                    json.dumps(sorted(set(tags or []))[:24], ensure_ascii=False),
                    json.dumps(evidence_rows[-100:], ensure_ascii=False),
                    now_ms,
                    now_ms,
                    now_ms,
                    supersedes_id,
                    now_ms,
                ),
            )
        return self.get(memory_id)

    @_synchronized
    def propose(
        self,
        content: str,
        *,
        kind: str = "fact",
        confidence: float = 0.75,
        importance: float = 0.55,
        conversation_id: str = "",
        task_id: str = "",
        tags: list[str] | None = None,
        key: str = "",
        namespace: str = "",
        evidence: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any] | None:
        content = _clean(content)
        if len(content) < 4 or GREETING_PATTERN.fullmatch(content):
            return None
        kind = _normalize_kind(kind)
        namespace = _normalize_namespace(namespace, kind, content)
        key = str(key or _memory_key(content, kind))[:160]
        now_ms = int(self.now() * 1_000)
        if SECRET_PATTERN.search(content) or PRIVATE_MEMORY_PATTERN.search(content):
            blocked_id = hashlib.sha256(
                f"blocked:{namespace}:{kind}:{now_ms}".encode("utf-8")
            ).hexdigest()[:32]
            return {
                "id": blocked_id,
                "memory_key": key,
                "namespace": namespace,
                "kind": kind,
                "content": "",
                "status": "private_blocked",
                "risk": "private",
                "temporal_state": "pending",
                "intended_temporal_state": "current",
                "confidence": 0.0,
                "importance": 0.0,
                "conversation_id": str(conversation_id)[:160],
                "task_id": str(task_id)[:160],
                "tags": [],
                "evidence": [],
                "conflicting_memory_ids": [],
                "resulting_memory_id": "",
                "created_at": now_ms,
                "reviewed_at": now_ms,
                "review_note": "private_content_not_retained",
                "persisted": False,
            }

        intended_temporal_state = _infer_temporal_state(content, kind)
        evidence_rows = list(evidence or [])
        if conversation_id or task_id:
            evidence_rows.append({
                "conversation_id": str(conversation_id)[:160],
                "task_id": str(task_id)[:160],
                "observed_at": now_ms,
            })
        with self._lock, self._connect() as connection:
            duplicate = connection.execute(
                "SELECT * FROM memory_candidates WHERE namespace = ? AND memory_key = ? "
                "AND lower(content) = lower(?) AND status IN ('pending_review', 'conflicted') "
                "ORDER BY created_at DESC LIMIT 1",
                (namespace, key, content),
            ).fetchone()
            if duplicate:
                return self._candidate_public(duplicate)
            current_rows = connection.execute(
                "SELECT * FROM memories WHERE namespace = ? AND memory_key = ? "
                "AND status = 'active' ORDER BY updated_at DESC",
                (namespace, key),
            ).fetchall()

        conflicts = [
            str(row["id"])
            for row in current_rows
            if _clean(row["content"]).casefold() != content.casefold()
        ]
        matching = [
            str(row["id"])
            for row in current_rows
            if _clean(row["content"]).casefold() == content.casefold()
        ]
        protected = kind in REVIEW_KINDS
        replacement = bool(conflicts and REPLACEMENT_PATTERN.search(content))
        if conflicts and not replacement:
            evolution_action = "review_conflict"
            target_memory_ids = conflicts
        elif conflicts:
            evolution_action = "supersede"
            target_memory_ids = conflicts
        elif matching:
            evolution_action = "strengthen"
            target_memory_ids = matching
        else:
            evolution_action = "create"
            target_memory_ids = []
        if protected:
            status = "pending_review"
            risk = "review_required"
            temporal_state = "pending"
        elif conflicts and not replacement:
            status = "conflicted"
            risk = "review_required"
            temporal_state = "conflicted"
        else:
            status = "auto_merged"
            risk = "low"
            temporal_state = intended_temporal_state

        candidate_id = hashlib.sha256(
            f"{namespace}:{key}:{content}:{now_ms}".encode("utf-8")
        ).hexdigest()[:32]
        with self._lock, self._connect() as connection:
            connection.execute(
                """
                INSERT INTO memory_candidates (
                    id, memory_key, namespace, kind, content, status, risk,
                    temporal_state, intended_temporal_state, confidence, importance,
                    source_conversation_id, source_task_id, tags_json, evidence_json,
                    conflicting_memory_ids_json, evolution_action,
                    target_memory_ids_json, resulting_memory_id, created_at,
                    reviewed_at, review_note
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '', ?, 0, '')
                """,
                (
                    candidate_id,
                    key,
                    namespace,
                    kind,
                    content,
                    status,
                    risk,
                    temporal_state,
                    intended_temporal_state,
                    max(0.0, min(1.0, confidence)),
                    max(0.0, min(1.0, importance)),
                    str(conversation_id)[:160],
                    str(task_id)[:160],
                    json.dumps(sorted(set(tags or []))[:24], ensure_ascii=False),
                    json.dumps(evidence_rows[-100:], ensure_ascii=False),
                    json.dumps(conflicts, ensure_ascii=False),
                    evolution_action,
                    json.dumps(target_memory_ids, ensure_ascii=False),
                    now_ms,
                ),
            )

        if status == "auto_merged":
            memory = self.remember(
                content,
                kind=kind,
                confidence=confidence,
                importance=importance,
                conversation_id=conversation_id,
                task_id=task_id,
                tags=tags,
                key=key,
                namespace=namespace,
                temporal_state=intended_temporal_state,
                evidence=evidence_rows,
            )
            with self._lock, self._connect() as connection:
                connection.execute(
                    "UPDATE memory_candidates SET resulting_memory_id = ?, reviewed_at = ?, "
                    "review_note = 'low_risk_auto_merge' WHERE id = ?",
                    (str(memory["id"]) if memory else "", now_ms, candidate_id),
                )
        return self.get_candidate(candidate_id)

    def list_candidates(
        self,
        *,
        statuses: tuple[str, ...] = ("pending_review", "conflicted"),
        limit: int = 100,
    ) -> list[dict[str, Any]]:
        clean_statuses = tuple(
            status for status in statuses
            if status in {
                "pending_review", "conflicted", "auto_merged", "approved",
                "rejected",
            }
        )
        if not clean_statuses:
            return []
        placeholders = ",".join("?" for _ in clean_statuses)
        with self._lock, self._connect() as connection:
            rows = connection.execute(
                f"SELECT * FROM memory_candidates WHERE status IN ({placeholders}) "
                "ORDER BY created_at DESC LIMIT ?",
                (*clean_statuses, max(1, min(limit, 500))),
            ).fetchall()
        return [self._candidate_public(row) for row in rows]

    def get_candidate(self, candidate_id: str) -> dict[str, Any] | None:
        with self._lock, self._connect() as connection:
            row = connection.execute(
                "SELECT * FROM memory_candidates WHERE id = ?",
                (str(candidate_id),),
            ).fetchone()
        return self._candidate_public(row) if row else None

    @_synchronized
    def approve_candidate(self, candidate_id: str) -> dict[str, Any] | None:
        candidate = self.get_candidate(candidate_id)
        if not candidate or candidate["status"] not in {"pending_review", "conflicted"}:
            return None
        memory = self.remember(
            candidate["content"],
            kind=candidate["kind"],
            confidence=candidate["confidence"],
            importance=candidate["importance"],
            conversation_id=candidate["conversation_id"],
            task_id=candidate["task_id"],
            tags=candidate["tags"],
            key=candidate["memory_key"],
            namespace=candidate["namespace"],
            temporal_state=candidate["intended_temporal_state"],
            evidence=candidate["evidence"],
        )
        now_ms = int(self.now() * 1_000)
        with self._lock, self._connect() as connection:
            connection.execute(
                "UPDATE memory_candidates SET status = 'approved', temporal_state = ?, "
                "resulting_memory_id = ?, reviewed_at = ?, review_note = 'user_approved' "
                "WHERE id = ? AND status IN ('pending_review', 'conflicted')",
                (
                    candidate["intended_temporal_state"],
                    str(memory["id"]) if memory else "",
                    now_ms,
                    str(candidate_id),
                ),
            )
        return self.get_candidate(candidate_id)

    @_synchronized
    def reject_candidate(self, candidate_id: str) -> dict[str, Any] | None:
        now_ms = int(self.now() * 1_000)
        with self._lock, self._connect() as connection:
            cursor = connection.execute(
                "UPDATE memory_candidates SET status = 'rejected', reviewed_at = ?, "
                "review_note = 'user_rejected' "
                "WHERE id = ? AND status IN ('pending_review', 'conflicted')",
                (now_ms, str(candidate_id)),
            )
        return self.get_candidate(candidate_id) if cursor.rowcount > 0 else None

    def evolve(self, prompt: str, reply: str, *, conversation_id: str = "", task_id: str = "") -> list[dict[str, Any]]:
        prompt = _clean(prompt, 1_200)
        reply = _clean(reply, 1_200)
        if not prompt or not reply or GREETING_PATTERN.fullmatch(prompt):
            return []
        learned: list[dict[str, Any]] = []
        explicit = re.search(r"(?is)(?:remember(?: that)?|\u8bf7?\u8bb0\u4f4f)\s*[:\uff1a]?\s*(.+)", prompt)
        preference = re.search(
            r"(?is)(?:i prefer|my preference is|use .+ by default|"
            r"\u6211\u559c\u6b22|\u6211\u504f\u597d|\u9ed8\u8ba4\u4f7f\u7528)\s*[:\uff1a]?\s*(.+)",
            prompt,
        )
        identity = re.search(
            r"(?is)(?:\b(?:my name is|call me|my display name is)\b|"
            r"\u6211\u53eb|\u8bf7\u79f0\u547c\u6211|\u6211\u7684\u6635\u79f0\u662f)\s*[:\uff1a]?\s*(.+)",
            prompt,
        )
        security = re.search(
            r"(?is)(?:\b(?:always ask before|require confirmation|never send without|security policy)\b|"
            r"\u5fc5\u987b\u786e\u8ba4|\u53d1\u9001\u524d\u786e\u8ba4|\u5b89\u5168\u7b56\u7565|\u672a\u786e\u8ba4\u4e0d\u5f97)\s*[:\uff1a]?\s*(.+)",
            prompt,
        )
        decision = re.search(
            r"(?is)(?:we decided|change .+ to|set .+ to|"
            r"\u51b3\u5b9a|\u6539\u4e3a|\u8bbe\u7f6e\u4e3a)\s*[:\uff1a]?\s*(.+)",
            prompt,
        )
        if explicit:
            explicit_value = explicit.group(1)
            explicit_kind = "identity" if identity else "security" if security else "preference" if preference or re.search(
                r"(?i)(?:\b(?:prefer|default|language|response style)\b|"
                r"\u504f\u597d|\u9ed8\u8ba4|\u8bed\u8a00|\u56de\u590d\u98ce\u683c)",
                explicit_value,
            ) else "explicit"
            value = self.propose(
                explicit_value,
                kind=explicit_kind,
                confidence=0.98,
                importance=0.9,
                conversation_id=conversation_id,
                task_id=task_id,
                tags=["explicit"],
            )
            if value:
                learned.append(value)
        elif identity:
            value = self.propose(
                prompt,
                kind="identity",
                confidence=0.94,
                importance=0.9,
                conversation_id=conversation_id,
                task_id=task_id,
            )
            if value:
                learned.append(value)
        elif security:
            value = self.propose(
                prompt,
                kind="security",
                confidence=0.96,
                importance=0.95,
                conversation_id=conversation_id,
                task_id=task_id,
            )
            if value:
                learned.append(value)
        elif preference:
            value = self.propose(
                prompt,
                kind="preference",
                confidence=0.9,
                importance=0.8,
                conversation_id=conversation_id,
                task_id=task_id,
            )
            if value:
                learned.append(value)
        elif decision:
            value = self.propose(
                prompt,
                kind="decision",
                confidence=0.88,
                importance=0.82,
                conversation_id=conversation_id,
                task_id=task_id,
            )
            if value:
                learned.append(value)

        if (
            len(prompt) >= 12
            and len(reply) >= 24
            and not VOLATILE_PATTERN.search(prompt)
            and not FAILED_OUTCOME_PATTERN.search(reply)
            and not any(
                item.get("status") in {
                    "pending_review", "conflicted", "private_blocked",
                }
                for item in learned
            )
        ):
            episode = f"Request: {prompt[:500]} Outcome: {reply[:700]}"
            value = self.propose(
                episode,
                kind="episode",
                confidence=0.7,
                importance=0.42,
                conversation_id=conversation_id,
                task_id=task_id,
                key=f"episode:{task_id or hashlib.sha256(prompt.encode('utf-8')).hexdigest()[:24]}",
            )
            if value:
                learned.append(value)
        return learned

    def search(self, query: str, limit: int = 8) -> list[dict[str, Any]]:
        query_tokens = _tokens(query)
        if not query_tokens:
            return []
        with self._lock, self._connect() as connection:
            rows = connection.execute(
                "SELECT * FROM memories WHERE status = 'active' ORDER BY importance DESC, updated_at DESC LIMIT 500"
            ).fetchall()
            now_ms = int(self.now() * 1_000)
            ranked: list[tuple[float, sqlite3.Row]] = []
            for row in rows:
                memory_tokens = _tokens(str(row["content"]))
                overlap = len(query_tokens & memory_tokens)
                if overlap <= 0:
                    continue
                coverage = overlap / max(1, len(query_tokens))
                age_days = max(0.0, (now_ms - int(row["updated_at"])) / 86_400_000)
                recency = 1.0 / (1.0 + age_days / 30.0)
                score = coverage * 0.62 + float(row["importance"]) * 0.25 + recency * 0.13
                ranked.append((score, row))
            selected = [row for _score, row in sorted(ranked, key=lambda item: item[0], reverse=True)[:max(1, min(limit, 20))]]
            if selected:
                connection.executemany(
                    "UPDATE memories SET last_accessed_at = ?, use_count = use_count + 1 WHERE id = ?",
                    [(now_ms, row["id"]) for row in selected],
                )
        return [self._public(row) for row in selected]

    def compile_context(self, query: str, *, limit: int = 6, max_chars: int = 5_000) -> str:
        rows = self.search(query, limit=limit)
        lines = [f"- [{row['kind']}] {row['content']}" for row in rows]
        return "\n".join(lines)[:max_chars]

    def list(self, limit: int = 100, status: str = "active") -> list[dict[str, Any]]:
        statuses = {
            "active": ("active",),
            "history": ("superseded", "retracted"),
            "all": ("active", "superseded", "retracted"),
            "superseded": ("superseded",),
            "retracted": ("retracted",),
        }.get(str(status or "active").casefold(), ("active",))
        placeholders = ",".join("?" for _ in statuses)
        with self._lock, self._connect() as connection:
            rows = connection.execute(
                f"SELECT * FROM memories WHERE status IN ({placeholders}) "
                "ORDER BY updated_at DESC, importance DESC LIMIT ?",
                (*statuses, max(1, min(limit, 500))),
            ).fetchall()
        return [self._public(row) for row in rows]

    def get(self, memory_id: str) -> dict[str, Any] | None:
        with self._lock, self._connect() as connection:
            row = connection.execute("SELECT * FROM memories WHERE id = ?", (str(memory_id),)).fetchone()
        return self._public(row) if row else None

    def forget(self, memory_id: str) -> bool:
        now_ms = int(self.now() * 1_000)
        with self._lock, self._connect() as connection:
            cursor = connection.execute(
                "UPDATE memories SET status = 'retracted', temporal_state = 'deprecated', "
                "valid_until_at = ?, updated_at = ? WHERE id = ?",
                (now_ms, now_ms, str(memory_id)),
            )
            return cursor.rowcount > 0

    def clear(self) -> int:
        with self._lock, self._connect() as connection:
            count = int(connection.execute("SELECT COUNT(*) FROM memories").fetchone()[0])
            connection.execute("DELETE FROM memories")
            connection.execute("DELETE FROM memory_candidates")
            return count

    def stats(self) -> dict[str, Any]:
        with self._lock, self._connect() as connection:
            rows = connection.execute("SELECT status, COUNT(*) AS count FROM memories GROUP BY status").fetchall()
            candidate_rows = connection.execute(
                "SELECT status, COUNT(*) AS count FROM memory_candidates GROUP BY status"
            ).fetchall()
            temporal_rows = connection.execute(
                "SELECT temporal_state, COUNT(*) AS count FROM memories GROUP BY temporal_state"
            ).fetchall()
        counts = {str(row["status"]): int(row["count"]) for row in rows}
        candidate_counts = {str(row["status"]): int(row["count"]) for row in candidate_rows}
        temporal_counts = {str(row["temporal_state"]): int(row["count"]) for row in temporal_rows}
        pending = candidate_counts.get("pending_review", 0) + candidate_counts.get("conflicted", 0)
        return {
            "active": counts.get("active", 0),
            "superseded": counts.get("superseded", 0),
            "retracted": counts.get("retracted", 0),
            "pending": pending,
            "conflicted": candidate_counts.get("conflicted", 0),
            "candidate_counts": candidate_counts,
            "temporal_counts": temporal_counts,
            "total": sum(counts.values()),
        }

    def evolution_snapshot(self, limit: int = 100) -> dict[str, Any]:
        bounded_limit = max(1, min(int(limit or 100), 500))
        current = self.list(limit=bounded_limit, status="active")
        history = self.list(limit=bounded_limit, status="history")
        candidates = self.list_candidates(
            statuses=(
                "pending_review",
                "conflicted",
                "auto_merged",
                "approved",
                "rejected",
            ),
            limit=bounded_limit,
        )
        now_ms = int(self.now() * 1_000)
        stats = self.stats()
        candidate_by_status = dict(stats["candidate_counts"])
        temporal_counts = {
            state: int(stats["temporal_counts"].get(state, 0))
            for state in sorted(TEMPORAL_STATES)
        }
        with self._lock, self._connect() as connection:
            namespace_rows = connection.execute(
                "SELECT namespace, COUNT(*) AS count FROM memories "
                "WHERE status = 'active' GROUP BY namespace"
            ).fetchall()
            evidence_rows = connection.execute(
                "SELECT evidence_json FROM memories WHERE status = 'active'"
            ).fetchall()
        raw_namespace_counts = {
            str(row["namespace"]): int(row["count"])
            for row in namespace_rows
        }
        namespace_counts = {
            namespace: raw_namespace_counts.get(namespace, 0)
            for namespace in sorted(MEMORY_NAMESPACES)
        }
        evidence_count = sum(len(_json_list(row["evidence_json"])) for row in evidence_rows)
        conflicts: list[dict[str, Any]] = []
        for candidate in candidates:
            if candidate["status"] != "conflicted":
                continue
            conflict = dict(candidate)
            conflict["current_memories"] = [
                memory
                for memory_id in candidate["conflicting_memory_ids"]
                if (memory := self.get(str(memory_id))) is not None
            ]
            conflicts.append(conflict)

        findings: list[dict[str, Any]] = []
        if conflicts:
            findings.append({
                "kind": "unresolved_conflict",
                "count": len(conflicts),
                "severity": "attention",
            })
        stale_candidates = [
            candidate
            for candidate in candidates
            if candidate["status"] in {"pending_review", "conflicted"}
            and now_ms - int(candidate["created_at"]) >= 30 * 86_400_000
        ]
        if stale_candidates:
            findings.append({
                "kind": "stale_candidate",
                "count": len(stale_candidates),
                "severity": "attention",
            })
        low_confidence = [
            memory
            for memory in current
            if float(memory["confidence"]) < 0.5 and int(memory["use_count"]) >= 3
        ]
        if low_confidence:
            findings.append({
                "kind": "low_confidence_reused",
                "count": len(low_confidence),
                "severity": "review",
            })
        missing_evidence = [
            memory
            for memory in current
            if not memory["evidence"] and "manual" not in memory["tags"]
        ]
        if missing_evidence:
            findings.append({
                "kind": "missing_evidence",
                "count": len(missing_evidence),
                "severity": "review",
            })

        recent_evolution = sorted(
            candidates,
            key=lambda candidate: int(candidate["reviewed_at"] or candidate["created_at"]),
            reverse=True,
        )
        return {
            "contract_version": 1,
            "generated_at": now_ms,
            "summary": {
                "current": temporal_counts.get("current", 0),
                "planned": temporal_counts.get("planned", 0),
                "historical": temporal_counts.get("historical", 0),
                "deprecated": temporal_counts.get("deprecated", 0),
                "pending_review": candidate_by_status.get("pending_review", 0),
                "conflicted": candidate_by_status.get("conflicted", 0),
                "evidence": evidence_count,
            },
            "temporal_counts": temporal_counts,
            "namespace_counts": namespace_counts,
            "candidate_counts": candidate_by_status,
            "health": {
                "status": "attention" if findings else "healthy",
                "findings": findings,
            },
            "conflicts": conflicts,
            "recent_evolution": recent_evolution,
        }

    @staticmethod
    def _public(row: sqlite3.Row) -> dict[str, Any]:
        return {
            "id": str(row["id"]), "kind": str(row["kind"]), "content": str(row["content"]),
            "memory_key": str(row["memory_key"]), "namespace": str(row["namespace"]),
            "status": str(row["status"]), "confidence": float(row["confidence"]),
            "temporal_state": str(row["temporal_state"]),
            "importance": float(row["importance"]), "conversation_id": str(row["source_conversation_id"]),
            "task_id": str(row["source_task_id"]), "tags": _json_list(row["tags_json"]),
            "evidence": _json_list(row["evidence_json"]),
            "created_at": int(row["created_at"]), "updated_at": int(row["updated_at"]),
            "last_accessed_at": int(row["last_accessed_at"]), "use_count": int(row["use_count"]),
            "supersedes_id": str(row["supersedes_id"]),
            "valid_from_at": int(row["valid_from_at"]),
            "valid_until_at": int(row["valid_until_at"]),
        }

    @staticmethod
    def _candidate_public(row: sqlite3.Row) -> dict[str, Any]:
        return {
            "id": str(row["id"]),
            "memory_key": str(row["memory_key"]),
            "namespace": str(row["namespace"]),
            "kind": str(row["kind"]),
            "content": str(row["content"]),
            "status": str(row["status"]),
            "risk": str(row["risk"]),
            "temporal_state": str(row["temporal_state"]),
            "intended_temporal_state": str(row["intended_temporal_state"]),
            "confidence": float(row["confidence"]),
            "importance": float(row["importance"]),
            "conversation_id": str(row["source_conversation_id"]),
            "task_id": str(row["source_task_id"]),
            "tags": _json_list(row["tags_json"]),
            "evidence": _json_list(row["evidence_json"]),
            "conflicting_memory_ids": _json_list(row["conflicting_memory_ids_json"]),
            "evolution_action": str(row["evolution_action"]),
            "target_memory_ids": _json_list(row["target_memory_ids_json"]),
            "resulting_memory_id": str(row["resulting_memory_id"]),
            "created_at": int(row["created_at"]),
            "reviewed_at": int(row["reviewed_at"]),
            "review_note": str(row["review_note"]),
            "persisted": True,
        }


_MEMORY: DesktopMemoryStore | None = None
_MEMORY_LOCK = threading.Lock()


def desktop_memory_store() -> DesktopMemoryStore:
    global _MEMORY
    with _MEMORY_LOCK:
        if _MEMORY is None:
            _MEMORY = DesktopMemoryStore()
        return _MEMORY
