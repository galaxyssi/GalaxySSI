"""Atomic, restartable import of legacy task data into the shared Run database."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sqlite3
import time

from agent_run_kernel import AgentRunEventLedger
from agent_run_legacy_import import copy_legacy_run_events


def migrate_task_run_data(
    ledger: AgentRunEventLedger, *, legacy_tasks: Path, legacy_events: Path,
) -> dict:
    sources = [path.resolve() for path in (legacy_tasks, legacy_events)]
    target = ledger.path.resolve()
    tasks_present = sources[0] != target and sources[0].is_file()
    events_present = sources[1] != target and sources[1].is_file()
    if not tasks_present and not events_present:
        return {"tasks": 0, "events": 0, "migrated": False}
    identity = "\0".join(str(path) for path in sources)
    key = "legacy-task-run-v1:" + hashlib.sha256(identity.encode()).hexdigest()
    with ledger.transaction() as connection:
        connection.execute("""
            CREATE TABLE IF NOT EXISTS agent_run_migrations (
                migration_id TEXT PRIMARY KEY NOT NULL,
                completed_at_millis INTEGER NOT NULL,
                task_count INTEGER NOT NULL, event_count INTEGER NOT NULL
            )
        """)
        if connection.execute(
            "SELECT 1 FROM agent_run_migrations WHERE migration_id = ?", (key,),
        ).fetchone():
            return {"tasks": 0, "events": 0, "migrated": False}
        tasks = events = 0
        if tasks_present:
            connection.execute("ATTACH DATABASE ? AS legacy_tasks", (sources[0].as_uri() + "?mode=ro",))
            tasks = _copy_tasks(connection)
        if events_present:
            connection.execute("ATTACH DATABASE ? AS legacy_runs", (sources[1].as_uri() + "?mode=ro",))
            events = copy_legacy_run_events(connection)
        connection.execute(
            "INSERT INTO agent_run_migrations VALUES (?, ?, ?, ?)",
            (key, int(time.time() * 1000), tasks, events),
        )
    return {"tasks": tasks, "events": events, "migrated": True}


def _copy_tasks(connection: sqlite3.Connection) -> int:
    if not connection.execute(
        "SELECT 1 FROM legacy_tasks.sqlite_master WHERE type='table' AND name='agent_tasks'"
    ).fetchone():
        return 0
    if connection.execute(
        "SELECT 1 FROM legacy_tasks.agent_tasks WHERE NOT json_valid(payload) LIMIT 1"
    ).fetchone():
        raise ValueError("Legacy task payload contains invalid JSON")
    if connection.execute(
        "SELECT 1 FROM legacy_tasks.agent_tasks WHERE json_type(payload) <> 'object' LIMIT 1"
    ).fetchone():
        raise ValueError("Legacy task payload must be an object")
    if connection.execute("""
        SELECT a.task_id FROM legacy_tasks.agent_tasks a
        JOIN main.agent_tasks b ON a.task_id = b.task_id
        WHERE a.conversation_id IS NOT b.conversation_id
           OR a.source_message_id IS NOT b.source_message_id
           OR (coalesce(json_extract(a.payload, '$.client_route_id'), '') <> ''
               AND coalesce(json_extract(b.payload, '$.client_route_id'), '') <> ''
               AND json_extract(a.payload, '$.client_route_id') IS NOT json_extract(b.payload, '$.client_route_id'))
        LIMIT 1
    """).fetchone():
        raise ValueError("Legacy task identity conflicts with the current task store")
    connection.execute("""
        CREATE TEMP TABLE imported_task_ids AS
        SELECT a.task_id FROM legacy_tasks.agent_tasks a
        LEFT JOIN main.agent_tasks b ON a.task_id = b.task_id WHERE b.task_id IS NULL
    """)
    count = connection.execute("SELECT count(*) FROM imported_task_ids").fetchone()[0]
    connection.execute("""
        INSERT INTO main.agent_tasks (task_id, conversation_id, source_message_id, status,
                                     created_at, updated_at, payload)
        SELECT a.task_id, a.conversation_id, a.source_message_id, a.status,
               a.created_at, a.updated_at, a.payload
        FROM legacy_tasks.agent_tasks a JOIN imported_task_ids i ON a.task_id = i.task_id
    """)
    chunks_present = connection.execute(
        "SELECT 1 FROM legacy_tasks.sqlite_master WHERE type='table' AND name='agent_task_output_chunks'"
    ).fetchone()
    if chunks_present:
        connection.execute("""
            INSERT INTO main.agent_task_output_chunks
                (task_id, field_name, chunk_index, content, char_count, chunk_sha256)
            SELECT a.task_id, a.field_name, a.chunk_index, a.content, a.char_count, a.chunk_sha256
            FROM legacy_tasks.agent_task_output_chunks a
            JOIN imported_task_ids i ON a.task_id = i.task_id
        """)
    missing_chunks = connection.execute("""
        SELECT t.task_id FROM main.agent_tasks t JOIN imported_task_ids i ON t.task_id = i.task_id
        LEFT JOIN main.agent_task_output_chunks c ON t.task_id = c.task_id AND c.field_name = 'result'
        WHERE json_extract(t.payload, '$.result_chunked') = 1
        GROUP BY t.task_id
        HAVING count(c.chunk_index) <> json_extract(t.payload, '$.result_chunk_count')
            OR coalesce(sum(c.char_count), 0) <> json_extract(t.payload, '$.result_length')
            OR min(c.chunk_index) <> 0
            OR max(c.chunk_index) <> json_extract(t.payload, '$.result_chunk_count') - 1
        LIMIT 1
    """).fetchone()
    if missing_chunks:
        raise ValueError("Legacy task result is incomplete; migration was rolled back")
    _validate_imported_results(connection)
    return int(count)


def _validate_imported_results(connection: sqlite3.Connection) -> None:
    # Stream one chunk at a time so importing large results does not double their memory.
    for task_id, payload in connection.execute("""
        SELECT t.task_id, t.payload FROM main.agent_tasks t
        JOIN imported_task_ids i ON t.task_id = i.task_id
        WHERE json_extract(t.payload, '$.result_chunked') = 1
    """):
        record = json.loads(payload)
        digest = hashlib.sha256()
        length = count = 0
        for index, content, char_count, chunk_hash in connection.execute("""
            SELECT chunk_index, content, char_count, chunk_sha256
            FROM main.agent_task_output_chunks
            WHERE task_id = ? AND field_name = 'result' ORDER BY chunk_index
        """, (task_id,)):
            encoded = content.encode("utf-8")
            if (index != count or len(content) != char_count
                    or hashlib.sha256(encoded).hexdigest() != chunk_hash):
                raise ValueError("Legacy task result chunk failed integrity validation")
            digest.update(encoded)
            length += len(content)
            count += 1
        if (count != record.get("result_chunk_count") or length != record.get("result_length")
                or digest.hexdigest() != record.get("result_sha256")):
            raise ValueError("Legacy task result failed integrity validation")
