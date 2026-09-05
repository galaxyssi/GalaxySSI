"""Portable event-sourced Run ledger shared by Desktop Agent runtimes.

The wire shape is defined by ``core/protocol/agent-run-event-v1.schema.json``.
Existing runtime stores remain lightweight projections; this append-only SQLite
ledger is the durable lifecycle source used for replay and recovery.
"""

from __future__ import annotations

from contextlib import contextmanager
from dataclasses import dataclass, replace
import hashlib
import json
from pathlib import Path
import sqlite3
import time
from typing import Callable, Iterator, Mapping
import uuid

from agent_run_checkpoints import checkpoint_page, initialize_checkpoints, persist_event_checkpoint


RUN_EVENT_PROTOCOL = "galaxyssi.agent-run-event.v1"
RUN_EVENT_SCHEMA_VERSION = 1

RUN_EVENT_TYPES = frozenset({
    "RUN_CREATED",
    "RUN_QUEUED",
    "RUN_STARTED",
    "PLANNING",
    "THINKING",
    "AGENT_CONNECTED",
    "STEP_STARTED",
    "TOOL_PERMISSION_REQUIRED",
    "PERMISSION_REVOKED",
    "TOOL_STARTED",
    "TOOL_PROGRESS",
    "TOOL_COMPLETED",
    "CHECKPOINT_SAVED",
    "WAITING_FOR_USER",
    "WAITING_FOR_DEVICE",
    "PAUSED",
    "RETRYING",
    "HANDOFF",
    "STEP_COMPLETED",
    "RUN_INTERRUPTED",
    "RUN_COMPLETED",
    "RUN_FAILED",
    "RUN_CANCELLED",
    "RUN_RECOVERED",
})

TERMINAL_RUN_STATES = frozenset({"completed", "failed", "cancelled"})

_EVENT_ALIASES = {
    "RUN_OBSERVED": "RUN_COMPLETED",
    "RUN_IGNORED": "RUN_COMPLETED",
}


class AgentRunKernelError(RuntimeError):
    pass


class AgentRunIdentityConflict(AgentRunKernelError):
    pass


class AgentRunSequenceConflict(AgentRunKernelError):
    pass


class AgentRunTerminalConflict(AgentRunKernelError):
    pass


@dataclass(frozen=True)
class AgentRunRootIdentity:
    client_route_id: str
    conversation_id: str
    goal_id: str
    task_id: str
    run_id: str

    def public(self) -> dict:
        return {
            "client_route_id": self.client_route_id,
            "conversation_id": self.conversation_id,
            "goal_id": self.goal_id,
            "task_id": self.task_id,
            "run_id": self.run_id,
        }


@dataclass(frozen=True)
class AgentRunEvent:
    event_id: str
    idempotency_key: str
    client_route_id: str
    conversation_id: str
    goal_id: str
    task_id: str
    run_id: str
    turn_id: str
    action_id: str
    message_id: str
    step_id: str
    tool_call_id: str
    agent_id: str
    device_id: str
    type: str
    sequence: int
    timestamp_millis: int
    payload: dict
    protocol: str = RUN_EVENT_PROTOCOL
    schema_version: int = RUN_EVENT_SCHEMA_VERSION

    @property
    def root_identity(self) -> AgentRunRootIdentity:
        return AgentRunRootIdentity(
            client_route_id=self.client_route_id,
            conversation_id=self.conversation_id,
            goal_id=self.goal_id,
            task_id=self.task_id,
            run_id=self.run_id,
        )

    def public(self) -> dict:
        return {
            "protocol": self.protocol,
            "schema_version": self.schema_version,
            "event_id": self.event_id,
            "idempotency_key": self.idempotency_key,
            "client_route_id": self.client_route_id,
            "conversation_id": self.conversation_id,
            "goal_id": self.goal_id,
            "task_id": self.task_id,
            "run_id": self.run_id,
            "turn_id": self.turn_id,
            "action_id": self.action_id,
            "message_id": self.message_id,
            "step_id": self.step_id,
            "tool_call_id": self.tool_call_id,
            "agent_id": self.agent_id,
            "device_id": self.device_id,
            "type": self.type,
            "sequence": self.sequence,
            "timestamp_millis": self.timestamp_millis,
            "payload": dict(self.payload),
        }

    def idempotency_fingerprint(self) -> str:
        body = self.public()
        for key in ("event_id", "idempotency_key", "sequence", "timestamp_millis"):
            body.pop(key, None)
        encoded = json.dumps(
            body,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            default=str,
        ).encode("utf-8")
        return hashlib.sha256(encoded).hexdigest()

    @classmethod
    def from_mapping(
        cls,
        value: Mapping[str, object],
        *,
        now_millis: int | None = None,
    ) -> "AgentRunEvent":
        event_id = _clean(value.get("event_id")) or str(uuid.uuid4())
        task_id = _clean(value.get("task_id"))
        run_id = _clean(value.get("run_id"))
        if not task_id or not run_id:
            raise AgentRunKernelError("Run event requires task_id and run_id")

        agent_id = _clean(value.get("agent_id")) or "unknown-agent"
        device_id = _clean(value.get("device_id")) or "local"
        message_id = _clean(value.get("message_id"))
        step_id = _clean(value.get("step_id"))
        tool_call_id = _clean(value.get("tool_call_id"))
        event_type = _normalize_event_type(value.get("type"))
        payload = value.get("payload")
        sequence = _integer(value.get("sequence"), 0)
        timestamp = _integer(value.get("timestamp_millis"), 0)
        if timestamp <= 0 and now_millis is not None:
            timestamp = max(0, int(now_millis))

        protocol = _clean(value.get("protocol")) or RUN_EVENT_PROTOCOL
        schema_version = _integer(
            value.get("schema_version"),
            RUN_EVENT_SCHEMA_VERSION,
        )
        if protocol != RUN_EVENT_PROTOCOL or schema_version != RUN_EVENT_SCHEMA_VERSION:
            raise AgentRunKernelError(
                f"Unsupported Run event contract: {protocol}@{schema_version}"
            )

        client_route_id = _clean(value.get("client_route_id")) or device_id
        conversation_id = _clean(value.get("conversation_id")) or f"conversation:{task_id}"
        goal_id = _clean(value.get("goal_id")) or task_id
        turn_id = _clean(value.get("turn_id")) or message_id or f"turn:{task_id}"
        action_id = (
            _clean(value.get("action_id"))
            or tool_call_id
            or step_id
            or event_id
        )
        return cls(
            event_id=event_id,
            idempotency_key=_clean(value.get("idempotency_key")) or event_id,
            client_route_id=client_route_id,
            conversation_id=conversation_id,
            goal_id=goal_id,
            task_id=task_id,
            run_id=run_id,
            turn_id=turn_id,
            action_id=action_id,
            message_id=message_id,
            step_id=step_id,
            tool_call_id=tool_call_id,
            agent_id=agent_id,
            device_id=device_id,
            type=event_type,
            sequence=sequence,
            timestamp_millis=timestamp,
            payload=dict(payload) if isinstance(payload, Mapping) else {},
            protocol=protocol,
            schema_version=schema_version,
        )


class AgentRunEventLedger:
    """Append-only SQLite Run ledger with strict identity and idempotency."""

    def __init__(
        self,
        path: Path,
        now: Callable[[], float] = time.time,
    ) -> None:
        self.path = Path(path)
        self._now = now
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._initialize()

    def append(self, value: AgentRunEvent | Mapping[str, object]) -> tuple[AgentRunEvent, bool]:
        event = value if isinstance(value, AgentRunEvent) else AgentRunEvent.from_mapping(
            value,
            now_millis=self._now_ms(),
        )
        if event.timestamp_millis <= 0:
            event = replace(event, timestamp_millis=self._now_ms())

        with self._connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            replay = self._find_by_idempotency(
                connection,
                event.run_id,
                event.idempotency_key,
            )
            if replay is not None:
                if replay.idempotency_fingerprint() != event.idempotency_fingerprint():
                    raise AgentRunIdentityConflict(
                        f"Run event idempotency key was reused with different content: "
                        f"{event.idempotency_key}"
                    )
                return replay, False

            same_event_id = self._find_by_event_id(connection, event.event_id)
            if same_event_id is not None:
                raise AgentRunIdentityConflict(
                    f"Run event ID was reused with a different idempotency key: {event.event_id}"
                )

            root = self._root(connection, event.run_id)
            if root is not None and root[0] != event.root_identity:
                raise AgentRunIdentityConflict(
                    "Run root identity changed: "
                    f"expected={root[0].public()} actual={event.root_identity.public()}"
                )
            last_sequence = root[1] if root is not None else 0
            current_state = root[2] if root is not None else "created"
            if current_state in TERMINAL_RUN_STATES and event.type != "RUN_RECOVERED":
                raise AgentRunTerminalConflict(
                    f"Run {event.run_id} is terminal in state {current_state}"
                )

            requested_sequence = max(0, int(event.sequence))
            sequence = requested_sequence or last_sequence + 1
            if sequence <= last_sequence:
                raise AgentRunSequenceConflict(
                    f"Run event sequence must increase: {sequence} <= {last_sequence}"
                )
            sequenced = replace(event, sequence=sequence)
            state = reduce_run_state(current_state, sequenced.type)
            payload_json = json.dumps(
                sequenced.payload,
                ensure_ascii=False,
                separators=(",", ":"),
                sort_keys=True,
                default=str,
            )
            connection.execute(
                """
                INSERT INTO agent_run_events (
                    event_id, idempotency_key, protocol, schema_version,
                    client_route_id, conversation_id, goal_id, task_id, run_id,
                    turn_id, action_id, message_id, step_id, tool_call_id,
                    agent_id, device_id, event_type, sequence,
                    timestamp_millis, payload_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    sequenced.event_id,
                    sequenced.idempotency_key,
                    sequenced.protocol,
                    sequenced.schema_version,
                    sequenced.client_route_id,
                    sequenced.conversation_id,
                    sequenced.goal_id,
                    sequenced.task_id,
                    sequenced.run_id,
                    sequenced.turn_id,
                    sequenced.action_id,
                    sequenced.message_id,
                    sequenced.step_id,
                    sequenced.tool_call_id,
                    sequenced.agent_id,
                    sequenced.device_id,
                    sequenced.type,
                    sequenced.sequence,
                    sequenced.timestamp_millis,
                    payload_json,
                ),
            )
            connection.execute(
                """
                INSERT INTO agent_run_roots (
                    run_id, client_route_id, conversation_id, goal_id, task_id,
                    state, last_sequence, updated_at_millis
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(run_id) DO UPDATE SET
                    state = excluded.state,
                    last_sequence = excluded.last_sequence,
                    updated_at_millis = excluded.updated_at_millis
                """,
                (
                    sequenced.run_id,
                    sequenced.client_route_id,
                    sequenced.conversation_id,
                    sequenced.goal_id,
                    sequenced.task_id,
                    state,
                    sequenced.sequence,
                    sequenced.timestamp_millis,
                ),
            )
            persist_event_checkpoint(connection, sequenced)
            return sequenced, True

    def event_for_idempotency(self, run_id: str, key: str) -> AgentRunEvent | None:
        with self._connection() as connection:
            return self._find_by_idempotency(connection, _clean(run_id), _clean(key))

    def checkpoints(
        self,
        kind: str,
        *,
        limit: int = 256,
        before: tuple[int, str] | None = None,
        recoverable_only: bool = False,
    ) -> list[dict]:
        with self._connection() as connection:
            return checkpoint_page(
                connection, kind, limit=limit, before=before,
                recoverable_only=recoverable_only,
            )

    def events(
        self,
        run_id: str,
        *,
        after_sequence: int = 0,
        limit: int | None = None,
    ) -> list[AgentRunEvent]:
        clean_run_id = _clean(run_id)
        if not clean_run_id:
            return []
        limit_clause = " LIMIT ?" if limit is not None else ""
        parameters: tuple[object, ...] = (
            clean_run_id,
            max(0, int(after_sequence or 0)),
        )
        if limit is not None:
            parameters += (max(1, int(limit)),)
        with self._connection() as connection:
            rows = connection.execute(
                f"""
                SELECT event_id, idempotency_key, protocol, schema_version,
                       client_route_id, conversation_id, goal_id, task_id, run_id,
                       turn_id, action_id, message_id, step_id, tool_call_id,
                       agent_id, device_id, event_type, sequence,
                       timestamp_millis, payload_json
                FROM agent_run_events
                WHERE run_id = ? AND sequence > ?
                ORDER BY sequence ASC
                {limit_clause}
                """,
                parameters,
            ).fetchall()
        return [self._decode_event(row) for row in rows]

    def snapshot(self, run_id: str) -> dict | None:
        clean_run_id = _clean(run_id)
        if not clean_run_id:
            return None
        with self._connection() as connection:
            row = connection.execute(
                """
                SELECT run_id, client_route_id, conversation_id, goal_id, task_id,
                       state, last_sequence, updated_at_millis
                FROM agent_run_roots
                WHERE run_id = ?
                """,
                (clean_run_id,),
            ).fetchone()
        return self._decode_snapshot(row) if row else None

    def recoverable_runs(self, limit: int | None = None) -> list[dict]:
        limit_clause = " LIMIT ?" if limit is not None else ""
        parameters: tuple[object, ...] = ()
        if limit is not None:
            parameters = (max(1, int(limit)),)
        with self._connection() as connection:
            rows = connection.execute(
                f"""
                SELECT run_id, client_route_id, conversation_id, goal_id, task_id,
                       state, last_sequence, updated_at_millis
                FROM agent_run_roots
                WHERE state NOT IN ('completed', 'failed', 'cancelled')
                ORDER BY updated_at_millis ASC, run_id ASC
                {limit_clause}
                """,
                parameters,
            ).fetchall()
        return [self._decode_snapshot(row) for row in rows]

    def event_count(self, run_id: str = "") -> int:
        with self._connection() as connection:
            if _clean(run_id):
                row = connection.execute(
                    "SELECT COUNT(*) FROM agent_run_events WHERE run_id = ?",
                    (_clean(run_id),),
                ).fetchone()
            else:
                row = connection.execute("SELECT COUNT(*) FROM agent_run_events").fetchone()
        return int(row[0] if row else 0)

    def _initialize(self) -> None:
        with self._connection() as connection:
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS agent_run_roots (
                    run_id TEXT PRIMARY KEY NOT NULL,
                    client_route_id TEXT NOT NULL,
                    conversation_id TEXT NOT NULL,
                    goal_id TEXT NOT NULL,
                    task_id TEXT NOT NULL,
                    state TEXT NOT NULL,
                    last_sequence INTEGER NOT NULL,
                    updated_at_millis INTEGER NOT NULL
                );
                CREATE INDEX IF NOT EXISTS agent_run_roots_recovery
                    ON agent_run_roots(state, updated_at_millis, run_id);
                CREATE TABLE IF NOT EXISTS agent_run_events (
                    event_id TEXT PRIMARY KEY NOT NULL,
                    idempotency_key TEXT NOT NULL,
                    protocol TEXT NOT NULL,
                    schema_version INTEGER NOT NULL,
                    client_route_id TEXT NOT NULL,
                    conversation_id TEXT NOT NULL,
                    goal_id TEXT NOT NULL,
                    task_id TEXT NOT NULL,
                    run_id TEXT NOT NULL,
                    turn_id TEXT NOT NULL,
                    action_id TEXT NOT NULL,
                    message_id TEXT NOT NULL,
                    step_id TEXT NOT NULL,
                    tool_call_id TEXT NOT NULL,
                    agent_id TEXT NOT NULL,
                    device_id TEXT NOT NULL,
                    event_type TEXT NOT NULL,
                    sequence INTEGER NOT NULL,
                    timestamp_millis INTEGER NOT NULL,
                    payload_json TEXT NOT NULL,
                    UNIQUE(run_id, sequence),
                    UNIQUE(run_id, idempotency_key),
                    FOREIGN KEY(run_id) REFERENCES agent_run_roots(run_id)
                        DEFERRABLE INITIALLY DEFERRED
                );
                CREATE INDEX IF NOT EXISTS agent_run_events_replay
                    ON agent_run_events(run_id, sequence);
                CREATE INDEX IF NOT EXISTS agent_run_events_turn
                    ON agent_run_events(client_route_id, conversation_id, turn_id, sequence);
                """
            )

            initialize_checkpoints(connection)

    def _find_by_idempotency(
        self,
        connection: sqlite3.Connection,
        run_id: str,
        idempotency_key: str,
    ) -> AgentRunEvent | None:
        row = connection.execute(
            """
            SELECT event_id, idempotency_key, protocol, schema_version,
                   client_route_id, conversation_id, goal_id, task_id, run_id,
                   turn_id, action_id, message_id, step_id, tool_call_id,
                   agent_id, device_id, event_type, sequence,
                   timestamp_millis, payload_json
            FROM agent_run_events WHERE run_id = ? AND idempotency_key = ?
            """,
            (run_id, idempotency_key),
        ).fetchone()
        return self._decode_event(row) if row else None

    def _find_by_event_id(
        self,
        connection: sqlite3.Connection,
        event_id: str,
    ) -> AgentRunEvent | None:
        row = connection.execute(
            """
            SELECT event_id, idempotency_key, protocol, schema_version,
                   client_route_id, conversation_id, goal_id, task_id, run_id,
                   turn_id, action_id, message_id, step_id, tool_call_id,
                   agent_id, device_id, event_type, sequence,
                   timestamp_millis, payload_json
            FROM agent_run_events WHERE event_id = ?
            """,
            (event_id,),
        ).fetchone()
        return self._decode_event(row) if row else None

    def _root(
        self,
        connection: sqlite3.Connection,
        run_id: str,
    ) -> tuple[AgentRunRootIdentity, int, str] | None:
        row = connection.execute(
            """
            SELECT client_route_id, conversation_id, goal_id, task_id, run_id,
                   last_sequence, state
            FROM agent_run_roots WHERE run_id = ?
            """,
            (run_id,),
        ).fetchone()
        if not row:
            return None
        return (
            AgentRunRootIdentity(
                client_route_id=str(row[0]),
                conversation_id=str(row[1]),
                goal_id=str(row[2]),
                task_id=str(row[3]),
                run_id=str(row[4]),
            ),
            int(row[5]),
            str(row[6]),
        )

    @staticmethod
    def _decode_event(row: tuple) -> AgentRunEvent:
        payload = json.loads(str(row[19] or "{}"))
        return AgentRunEvent(
            event_id=str(row[0]),
            idempotency_key=str(row[1]),
            protocol=str(row[2]),
            schema_version=int(row[3]),
            client_route_id=str(row[4]),
            conversation_id=str(row[5]),
            goal_id=str(row[6]),
            task_id=str(row[7]),
            run_id=str(row[8]),
            turn_id=str(row[9]),
            action_id=str(row[10]),
            message_id=str(row[11]),
            step_id=str(row[12]),
            tool_call_id=str(row[13]),
            agent_id=str(row[14]),
            device_id=str(row[15]),
            type=str(row[16]),
            sequence=int(row[17]),
            timestamp_millis=int(row[18]),
            payload=dict(payload) if isinstance(payload, dict) else {},
        )

    @staticmethod
    def _decode_snapshot(row: tuple) -> dict:
        return {
            "run_id": str(row[0]),
            "client_route_id": str(row[1]),
            "conversation_id": str(row[2]),
            "goal_id": str(row[3]),
            "task_id": str(row[4]),
            "state": str(row[5]),
            "last_sequence": int(row[6]),
            "updated_at_millis": int(row[7]),
        }

    @contextmanager
    def _connection(self) -> Iterator[sqlite3.Connection]:
        connection = sqlite3.connect(self.path, timeout=30.0)
        try:
            connection.execute("PRAGMA foreign_keys = ON")
            connection.execute("PRAGMA journal_mode = WAL")
            connection.execute("PRAGMA synchronous = NORMAL")
            yield connection
            connection.commit()
        finally:
            connection.close()

    def _now_ms(self) -> int:
        return max(0, int(self._now() * 1_000))


def runtime_projection_event(
    row: Mapping[str, object],
    event_type: object,
    sequence: int,
    timestamp_millis: int,
    payload: Mapping[str, object] | None = None,
) -> AgentRunEvent:
    normalized_type = _normalize_event_type(event_type)
    run_id = _clean(row.get("run_id"))
    seed = f"{run_id}\x1f{normalized_type}\x1f{max(1, int(sequence))}"
    event_id = f"evt-{hashlib.sha256(seed.encode('utf-8')).hexdigest()}"
    request_key = _clean(row.get("idempotency_key")) or run_id
    action_id = _clean(row.get("action_id")) or f"runtime:{max(1, int(sequence))}"
    event_payload = dict(payload or {})
    event_payload.setdefault("source", "desktop-runtime")
    return AgentRunEvent.from_mapping({
        "event_id": event_id,
        "idempotency_key": f"{request_key}:runtime:{normalized_type}:{max(1, int(sequence))}",
        "client_route_id": row.get("client_route_id"),
        "conversation_id": row.get("conversation_id"),
        "goal_id": row.get("goal_id") or row.get("task_id"),
        "task_id": row.get("task_id") or run_id,
        "run_id": run_id,
        "turn_id": row.get("turn_id") or row.get("source_message_id"),
        "action_id": action_id,
        "message_id": row.get("source_message_id"),
        "agent_id": row.get("agent_id"),
        "device_id": row.get("device_id") or "desktop",
        "type": normalized_type,
        "sequence": max(1, int(sequence)),
        "timestamp_millis": max(0, int(timestamp_millis)),
        "payload": event_payload,
    })


def reduce_run_state(current: str, event_type: str) -> str:
    normalized = _normalize_event_type(event_type)
    if current in TERMINAL_RUN_STATES and normalized != "RUN_RECOVERED":
        return current
    if normalized == "RUN_CREATED":
        return "created"
    if normalized == "RUN_QUEUED":
        return "queued"
    if normalized in {"WAITING_FOR_USER", "TOOL_PERMISSION_REQUIRED"}:
        return "waiting_for_user"
    if normalized == "WAITING_FOR_DEVICE":
        return "waiting_for_device"
    if normalized in {"PAUSED", "PERMISSION_REVOKED"}:
        return "paused"
    if normalized == "RUN_INTERRUPTED":
        return "interrupted"
    if normalized == "RUN_COMPLETED":
        return "completed"
    if normalized == "RUN_FAILED":
        return "failed"
    if normalized == "RUN_CANCELLED":
        return "cancelled"
    if normalized == "CHECKPOINT_SAVED":
        return current if current else "running"
    return "running"


def _normalize_event_type(value: object) -> str:
    normalized = _clean(value).replace("-", "_").upper()
    normalized = _EVENT_ALIASES.get(normalized, normalized)
    if normalized not in RUN_EVENT_TYPES:
        raise AgentRunKernelError(f"Unsupported Run event type: {value}")
    return normalized


def _clean(value: object) -> str:
    return str(value or "").strip()


def _integer(value: object, fallback: int) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return int(fallback)
