"""Copy legacy Run events from a read-only attached database without losing identity."""

from __future__ import annotations

import sqlite3


EVENT_COLUMNS = (
    "event_id", "idempotency_key", "protocol", "schema_version", "client_route_id",
    "conversation_id", "goal_id", "task_id", "run_id", "turn_id", "action_id",
    "message_id", "step_id", "tool_call_id", "agent_id", "device_id", "event_type",
    "sequence", "timestamp_millis", "payload_json",
)


def copy_legacy_run_events(connection: sqlite3.Connection) -> int:
    exists = connection.execute(
        "SELECT 1 FROM legacy_runs.sqlite_master WHERE type='table' AND name='agent_run_events'"
    ).fetchone()
    if not exists:
        return 0
    root_mismatch = connection.execute("""
        SELECT a.run_id FROM legacy_runs.agent_run_roots a
        JOIN main.agent_run_roots b ON a.run_id = b.run_id
        WHERE a.client_route_id IS NOT b.client_route_id
           OR a.conversation_id IS NOT b.conversation_id
           OR a.goal_id IS NOT b.goal_id OR a.task_id IS NOT b.task_id
        LIMIT 1
    """).fetchone()
    if root_mismatch:
        raise ValueError("Legacy Run root identity conflicts with the current ledger")
    differences = " OR ".join(f"a.{name} IS NOT b.{name}" for name in EVENT_COLUMNS)
    for identity in (
        "a.event_id = b.event_id",
        "a.run_id = b.run_id AND a.sequence = b.sequence",
        "a.run_id = b.run_id AND a.idempotency_key = b.idempotency_key",
    ):
        conflict = connection.execute(f"""
            SELECT a.event_id FROM legacy_runs.agent_run_events a
            JOIN main.agent_run_events b ON {identity}
            WHERE {differences} LIMIT 1
        """).fetchone()
        if conflict:
            raise ValueError("Legacy Run event conflicts with the current ledger")
    connection.execute("""
        INSERT INTO main.agent_run_roots (run_id, client_route_id, conversation_id, goal_id,
                                         task_id, state, last_sequence, updated_at_millis)
        SELECT run_id, client_route_id, conversation_id, goal_id,
               task_id, state, last_sequence, updated_at_millis
        FROM legacy_runs.agent_run_roots WHERE 1
        ON CONFLICT(run_id) DO UPDATE SET
            state = excluded.state, last_sequence = excluded.last_sequence,
            updated_at_millis = excluded.updated_at_millis
        WHERE excluded.last_sequence > agent_run_roots.last_sequence
    """)
    columns = ", ".join(EVENT_COLUMNS)
    copied = connection.execute(f"""
        INSERT INTO main.agent_run_events ({columns})
        SELECT {columns} FROM legacy_runs.agent_run_events WHERE 1
        ON CONFLICT DO NOTHING
    """).rowcount
    has_checkpoints = connection.execute(
        "SELECT 1 FROM legacy_runs.sqlite_master WHERE type='table' AND name='agent_run_checkpoints'"
    ).fetchone()
    if has_checkpoints:
        conflict = connection.execute("""
            SELECT a.run_id FROM legacy_runs.agent_run_checkpoints a
            JOIN main.agent_run_checkpoints b ON a.run_id = b.run_id AND a.kind = b.kind
            WHERE a.sequence = b.sequence AND a.data_json IS NOT b.data_json LIMIT 1
        """).fetchone()
        if conflict:
            raise ValueError("Legacy Run checkpoint conflicts with the current ledger")
        connection.execute("""
            INSERT INTO main.agent_run_checkpoints (kind, run_id, sequence, updated_at_millis, data_json)
            SELECT kind, run_id, sequence, updated_at_millis, data_json
            FROM legacy_runs.agent_run_checkpoints WHERE 1
            ON CONFLICT(kind, run_id) DO UPDATE SET
                sequence = excluded.sequence, updated_at_millis = excluded.updated_at_millis,
                data_json = excluded.data_json
            WHERE excluded.sequence > agent_run_checkpoints.sequence
        """)
    return copied
