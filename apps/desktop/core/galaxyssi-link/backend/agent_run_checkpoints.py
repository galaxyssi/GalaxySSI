"""Materialized recovery checkpoints committed in the Run event transaction."""

from __future__ import annotations

import json
import sqlite3
from typing import Mapping


def initialize_checkpoints(connection: sqlite3.Connection) -> None:
    connection.executescript("""
        CREATE TABLE IF NOT EXISTS agent_run_checkpoints (
            run_id TEXT NOT NULL,
            kind TEXT NOT NULL,
            sequence INTEGER NOT NULL,
            updated_at_millis INTEGER NOT NULL,
            data_json TEXT NOT NULL,
            PRIMARY KEY(kind, run_id),
            FOREIGN KEY(run_id) REFERENCES agent_run_roots(run_id)
        );
        CREATE INDEX IF NOT EXISTS agent_run_checkpoints_page
            ON agent_run_checkpoints(kind, updated_at_millis DESC, run_id DESC);
    """)


def persist_event_checkpoint(connection: sqlite3.Connection, event) -> None:
    checkpoint = event.payload.get("projection_checkpoint")
    if checkpoint is None:
        return
    if not isinstance(checkpoint, Mapping):
        raise ValueError("Run checkpoint must be an object")
    kind = checkpoint.get("kind")
    data = checkpoint.get("data")
    if not isinstance(kind, str) or not kind.strip() or len(kind) > 256:
        raise ValueError("Run checkpoint requires a kind of 1-256 characters")
    if not isinstance(data, Mapping):
        raise ValueError("Run checkpoint data must be an object")
    connection.execute("""
        INSERT INTO agent_run_checkpoints (
            run_id, kind, sequence, updated_at_millis, data_json
        ) VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(kind, run_id) DO UPDATE SET
            sequence = excluded.sequence,
            updated_at_millis = excluded.updated_at_millis,
            data_json = excluded.data_json
    """, (
        event.run_id, kind, event.sequence, event.timestamp_millis,
        json.dumps(dict(data), ensure_ascii=False, separators=(",", ":"), sort_keys=True),
    ))


def checkpoint_page(
    connection: sqlite3.Connection,
    kind: str,
    *,
    limit: int = 256,
    before: tuple[int, str] | None = None,
    recoverable_only: bool = False,
) -> list[dict]:
    clauses = ["c.kind = ?"]
    parameters: list[object] = [kind]
    if before is not None:
        clauses.append("(c.updated_at_millis, c.run_id) < (?, ?)")
        parameters.extend(before)
    if recoverable_only:
        clauses.append("r.state NOT IN ('completed', 'failed', 'cancelled')")
    parameters.append(max(1, int(limit)))
    rows = connection.execute(f"""
        SELECT c.run_id, c.sequence, c.updated_at_millis, c.data_json,
               r.client_route_id, r.conversation_id, r.goal_id, r.task_id, r.state
        FROM agent_run_checkpoints c
        JOIN agent_run_roots r ON r.run_id = c.run_id
        WHERE {' AND '.join(clauses)}
        ORDER BY c.updated_at_millis DESC, c.run_id DESC
        LIMIT ?
    """, parameters).fetchall()
    return [
        {
            "run_id": row[0], "sequence": int(row[1]),
            "updated_at_millis": int(row[2]), "data": json.loads(row[3]),
            "client_route_id": row[4], "conversation_id": row[5],
            "goal_id": row[6], "task_id": row[7], "state": row[8],
        }
        for row in rows
    ]
