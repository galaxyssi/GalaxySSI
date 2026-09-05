"""SQLite persistence for complete Desktop Agent task history."""

from __future__ import annotations

from contextlib import contextmanager
import hashlib
import json
from pathlib import Path
import sqlite3
from typing import Iterable, Iterator

from agent_run_storage import require_shared_transaction


OUTPUT_CHUNK_THRESHOLD = 16 * 1024
OUTPUT_CHUNK_CHARACTERS = 8 * 1024
OUTPUT_PREVIEW_CHARACTERS = 4 * 1024
MAX_OUTPUT_PAGE_CHUNKS = 16


class AgentTaskStore:
    def __init__(self, path: Path) -> None:
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self._connection() as connection:
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS agent_tasks (
                    task_id TEXT PRIMARY KEY NOT NULL,
                    conversation_id TEXT NOT NULL,
                    source_message_id TEXT NOT NULL,
                    status TEXT NOT NULL,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    payload TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS agent_tasks_conversation_order
                    ON agent_tasks(conversation_id, created_at, task_id);
                CREATE INDEX IF NOT EXISTS agent_tasks_updated_order
                    ON agent_tasks(updated_at DESC, task_id DESC);
                CREATE INDEX IF NOT EXISTS agent_tasks_status
                    ON agent_tasks(status, updated_at DESC);
                CREATE TABLE IF NOT EXISTS agent_task_output_chunks (
                    task_id TEXT NOT NULL,
                    field_name TEXT NOT NULL,
                    chunk_index INTEGER NOT NULL,
                    content TEXT NOT NULL,
                    char_count INTEGER NOT NULL,
                    chunk_sha256 TEXT NOT NULL,
                    PRIMARY KEY(task_id, field_name, chunk_index),
                    FOREIGN KEY(task_id) REFERENCES agent_tasks(task_id)
                        ON DELETE CASCADE
                );
                CREATE INDEX IF NOT EXISTS agent_task_output_chunks_order
                    ON agent_task_output_chunks(task_id, field_name, chunk_index);
                """
            )

    def upsert(self, record: dict, *, connection: sqlite3.Connection | None = None) -> None:
        task_id = str(record.get("task_id") or "").strip()
        if not task_id:
            raise ValueError("Agent task ID is required")
        stored_record, output_chunks = self._prepare_record(record)
        payload = json.dumps(stored_record, ensure_ascii=False, separators=(",", ":"))
        with self._connection(connection) as connection:
            connection.execute(
                """
                INSERT INTO agent_tasks (
                    task_id, conversation_id, source_message_id, status,
                    created_at, updated_at, payload
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(task_id) DO UPDATE SET
                    conversation_id = excluded.conversation_id,
                    source_message_id = excluded.source_message_id,
                    status = excluded.status,
                    created_at = excluded.created_at,
                    updated_at = excluded.updated_at,
                    payload = excluded.payload
                """,
                (
                    task_id,
                    str(record.get("conversation_id") or ""),
                    str(record.get("source_message_id") or ""),
                    str(record.get("status") or ""),
                    max(0, int(record.get("created_at") or 0)),
                    max(0, int(record.get("updated_at") or 0)),
                    payload,
                ),
            )
            connection.execute(
                """
                DELETE FROM agent_task_output_chunks
                WHERE task_id = ? AND field_name = 'result'
                """,
                (task_id,),
            )
            connection.executemany(
                """
                INSERT INTO agent_task_output_chunks (
                    task_id, field_name, chunk_index, content,
                    char_count, chunk_sha256
                ) VALUES (?, 'result', ?, ?, ?, ?)
                """,
                [
                    (
                        task_id,
                        index,
                        chunk,
                        len(chunk),
                        self._digest(chunk),
                    )
                    for index, chunk in enumerate(output_chunks)
                ],
            )

    def get(self, task_id: str, *, hydrate_output: bool = True) -> dict | None:
        clean_id = str(task_id or "").strip()
        if not clean_id:
            return None
        with self._connection() as connection:
            row = connection.execute(
                "SELECT payload FROM agent_tasks WHERE task_id = ?",
                (clean_id,),
            ).fetchone()
            record = self._decode(row[0]) if row else None
            return (
                self._hydrate_output(connection, record)
                if record is not None and hydrate_output
                else record
            )

    def list_recent(self, limit: int, *, hydrate_output: bool = False) -> list[dict]:
        safe_limit = max(1, int(limit or 1))
        with self._connection() as connection:
            rows = connection.execute(
                """
                SELECT payload
                FROM agent_tasks
                ORDER BY updated_at DESC, task_id DESC
                LIMIT ?
                """,
                (safe_limit,),
            ).fetchall()
            records = [record for row in rows if (record := self._decode(row[0])) is not None]
            return (
                [self._hydrate_output(connection, record) for record in records]
                if hydrate_output
                else records
            )

    def recoverable(self, terminal_states: Iterable[str]) -> list[dict]:
        terminal = tuple(sorted({str(value) for value in terminal_states if str(value)}))
        placeholders = ",".join("?" for _ in terminal)
        where = f"status NOT IN ({placeholders})" if terminal else "1 = 1"
        with self._connection() as connection:
            rows = connection.execute(
                f"""
                SELECT payload
                FROM agent_tasks
                WHERE {where}
                ORDER BY updated_at ASC, task_id ASC
                """,
                terminal,
            ).fetchall()
            return [
                self._hydrate_output(connection, record)
                for row in rows
                if (record := self._decode(row[0])) is not None
            ]

    def conversation(
        self,
        conversation_id: str,
        *,
        source_prefix: str | None = None,
        after_cursor: tuple[int, str] = (0, ""),
        limit: int | None = None,
        hydrate_output: bool = True,
    ) -> list[dict]:
        clean_id = str(conversation_id or "").strip()
        if not clean_id:
            return []
        cursor_time = max(0, int(after_cursor[0] or 0))
        cursor_id = str(after_cursor[1] or "")
        clauses = [
            "conversation_id = ?",
            "(created_at > ? OR (created_at = ? AND task_id > ?))",
        ]
        arguments: list[object] = [clean_id, cursor_time, cursor_time, cursor_id]
        if source_prefix is not None:
            clauses.append("source_message_id LIKE ? ESCAPE '\\'")
            arguments.append(self._like_prefix(source_prefix))
        where = " AND ".join(clauses)
        with self._connection() as connection:
            if limit is None:
                rows = connection.execute(
                    f"""
                    SELECT payload
                    FROM agent_tasks
                    WHERE {where}
                    ORDER BY created_at ASC, task_id ASC
                    """,
                    arguments,
                ).fetchall()
            else:
                safe_limit = max(1, int(limit or 1))
                rows = connection.execute(
                    f"""
                    SELECT payload
                    FROM (
                        SELECT payload, created_at, task_id
                        FROM agent_tasks
                        WHERE {where}
                        ORDER BY created_at DESC, task_id DESC
                        LIMIT ?
                    )
                    ORDER BY created_at ASC, task_id ASC
                    """,
                    [*arguments, safe_limit],
                ).fetchall()
            records = [record for row in rows if (record := self._decode(row[0])) is not None]
            return (
                [self._hydrate_output(connection, record) for record in records]
                if hydrate_output
                else records
            )

    def output_page(
        self,
        task_id: str,
        *,
        offset: int = 0,
        limit: int = 2,
    ) -> dict | None:
        clean_id = str(task_id or "").strip()
        if not clean_id:
            return None
        safe_offset = max(0, int(offset or 0))
        safe_limit = max(1, min(int(limit or 1), MAX_OUTPUT_PAGE_CHUNKS))
        with self._connection() as connection:
            row = connection.execute(
                "SELECT payload FROM agent_tasks WHERE task_id = ?",
                (clean_id,),
            ).fetchone()
            record = self._decode(row[0]) if row else None
            if record is None:
                return None
            if not bool(record.get("result_chunked")):
                inline = str(record.get("result") or "")
                chunks = [] if safe_offset > 0 or not inline else [{
                    "index": 0,
                    "content": inline,
                    "char_count": len(inline),
                    "sha256": self._digest(inline),
                }]
                return {
                    "task_id": clean_id,
                    "field": "result",
                    "offset": safe_offset,
                    "next_offset": 1 if chunks else safe_offset,
                    "total_chunks": 1 if inline else 0,
                    "total_length": len(inline),
                    "sha256": self._digest(inline),
                    "chunks": chunks,
                    "done": True,
                }
            rows = connection.execute(
                """
                SELECT chunk_index, content, char_count, chunk_sha256
                FROM agent_task_output_chunks
                WHERE task_id = ? AND field_name = 'result' AND chunk_index >= ?
                ORDER BY chunk_index ASC
                LIMIT ?
                """,
                (clean_id, safe_offset, safe_limit),
            ).fetchall()
        chunks = []
        for index, content, char_count, chunk_sha256 in rows:
            if int(index) != safe_offset + len(chunks):
                raise ValueError(f"Agent task output chunk order mismatch: {clean_id}")
            value = str(content or "")
            if len(value) != int(char_count) or self._digest(value) != str(chunk_sha256):
                raise ValueError(f"Agent task output chunk integrity failed: {clean_id}:{index}")
            chunks.append({
                "index": int(index),
                "content": value,
                "char_count": int(char_count),
                "sha256": str(chunk_sha256),
            })
        total_chunks = max(0, int(record.get("result_chunk_count") or 0))
        next_offset = safe_offset + len(chunks)
        return {
            "task_id": clean_id,
            "field": "result",
            "offset": safe_offset,
            "next_offset": next_offset,
            "total_chunks": total_chunks,
            "total_length": max(0, int(record.get("result_length") or 0)),
            "sha256": str(record.get("result_sha256") or ""),
            "chunks": chunks,
            "done": next_offset >= total_chunks,
        }

    def delete_conversation(
        self,
        conversation_id: str,
        task_ids: set[str] | None = None,
    ) -> list[str]:
        clean_id = str(conversation_id or "").strip()
        explicit = sorted({str(value).strip() for value in (task_ids or set()) if str(value).strip()})
        clauses: list[str] = []
        arguments: list[object] = []
        if clean_id:
            clauses.append("conversation_id = ?")
            arguments.append(clean_id)
        if explicit:
            clauses.append(f"task_id IN ({','.join('?' for _ in explicit)})")
            arguments.extend(explicit)
        if not clauses:
            return []
        where = " OR ".join(f"({clause})" for clause in clauses)
        with self._connection() as connection:
            rows = connection.execute(
                f"SELECT task_id FROM agent_tasks WHERE {where} ORDER BY created_at ASC, task_id ASC",
                arguments,
            ).fetchall()
            deleted = [str(row[0]) for row in rows]
            connection.execute(f"DELETE FROM agent_tasks WHERE {where}", arguments)
        return deleted

    def count(self) -> int:
        with self._connection() as connection:
            row = connection.execute("SELECT COUNT(*) FROM agent_tasks").fetchone()
        return int(row[0] if row else 0)

    @contextmanager
    def _connection(self, shared: sqlite3.Connection | None = None) -> Iterator[sqlite3.Connection]:
        if shared is not None:
            require_shared_transaction(shared, self.path)
            yield shared
            return
        connection = sqlite3.connect(self.path, timeout=30.0)
        try:
            connection.execute("PRAGMA foreign_keys = ON")
            connection.execute("PRAGMA journal_mode = WAL")
            connection.execute("PRAGMA synchronous = NORMAL")
            yield connection
            connection.commit()
        finally:
            connection.close()

    @staticmethod
    def _decode(value: object) -> dict | None:
        try:
            decoded = json.loads(str(value or ""))
            return decoded if isinstance(decoded, dict) else None
        except (TypeError, ValueError):
            return None

    def _prepare_record(self, record: dict) -> tuple[dict, list[str]]:
        stored = dict(record)
        result = str(record.get("result") or "")
        for key in (
            "result_chunked",
            "result_length",
            "result_chunk_count",
            "result_sha256",
            "result_preview_length",
        ):
            stored.pop(key, None)
        if len(result) <= OUTPUT_CHUNK_THRESHOLD:
            stored["result"] = result
            return stored, []
        chunks = self._split_output(result)
        preview = result[:OUTPUT_PREVIEW_CHARACTERS]
        stored.update({
            "result": preview,
            "result_chunked": True,
            "result_length": len(result),
            "result_chunk_count": len(chunks),
            "result_sha256": self._digest(result),
            "result_preview_length": len(preview),
        })
        return stored, chunks

    def _hydrate_output(self, connection: sqlite3.Connection, record: dict) -> dict:
        if not bool(record.get("result_chunked")):
            return record
        task_id = str(record.get("task_id") or "")
        rows = connection.execute(
            """
            SELECT chunk_index, content, char_count, chunk_sha256
            FROM agent_task_output_chunks
            WHERE task_id = ? AND field_name = 'result'
            ORDER BY chunk_index ASC
            """,
            (task_id,),
        ).fetchall()
        expected_count = max(0, int(record.get("result_chunk_count") or 0))
        if len(rows) != expected_count:
            raise ValueError(f"Agent task output chunk count mismatch: {task_id}")
        chunks: list[str] = []
        for expected_index, (index, content, char_count, chunk_sha256) in enumerate(rows):
            value = str(content or "")
            if int(index) != expected_index:
                raise ValueError(f"Agent task output chunk order mismatch: {task_id}")
            if len(value) != int(char_count) or self._digest(value) != str(chunk_sha256):
                raise ValueError(f"Agent task output chunk integrity failed: {task_id}:{index}")
            chunks.append(value)
        result = "".join(chunks)
        if len(result) != int(record.get("result_length") or 0):
            raise ValueError(f"Agent task output length mismatch: {task_id}")
        if self._digest(result) != str(record.get("result_sha256") or ""):
            raise ValueError(f"Agent task output digest mismatch: {task_id}")
        hydrated = dict(record)
        hydrated["result"] = result
        return hydrated

    @staticmethod
    def _digest(value: str) -> str:
        return hashlib.sha256(value.encode("utf-8")).hexdigest()

    @staticmethod
    def _split_output(value: str) -> list[str]:
        chunks: list[str] = []
        offset = 0
        while offset < len(value):
            end = min(len(value), offset + OUTPUT_CHUNK_CHARACTERS)
            if end < len(value):
                minimum = offset + OUTPUT_CHUNK_CHARACTERS // 2
                paragraph = value.rfind("\n\n", minimum, end)
                line = value.rfind("\n", minimum, end)
                boundary = paragraph + 2 if paragraph >= minimum else line + 1
                if boundary > offset:
                    end = boundary
            chunks.append(value[offset:end])
            offset = end
        return chunks

    @staticmethod
    def _like_prefix(value: str) -> str:
        escaped = (
            str(value or "")
            .replace("\\", "\\\\")
            .replace("%", "\\%")
            .replace("_", "\\_")
        )
        return f"{escaped}%"
