"""Durable local history for direct phone-to-Desktop conversations."""
from __future__ import annotations

import json
import os
import shutil
import sqlite3
import threading
import time
import uuid
from contextlib import closing
from pathlib import Path
from typing import Callable

from pairing_state import DATA_DIR


MAX_MESSAGE_CHARS = 24_000
MAX_ATTACHMENTS = 12
MAX_ATTACHMENT_BYTES = 64 * 1024 * 1024
_SAFE_NAME_CHARS = frozenset(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.() []"
)


class PeerChatStore:
    def __init__(self, database_path: Path | None = None) -> None:
        self.database_path = Path(database_path or (DATA_DIR / "peer_chat.db"))
        self.files_root = self.database_path.parent / "peer-chat-files"
        self._lock = threading.RLock()
        self._listeners: dict[str, Callable[[dict], None]] = {}
        self._initialize()

    def _connect(self) -> sqlite3.Connection:
        self.database_path.parent.mkdir(parents=True, exist_ok=True)
        connection = sqlite3.connect(self.database_path, timeout=10)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute("PRAGMA synchronous=NORMAL")
        return connection

    def _initialize(self) -> None:
        with self._lock, closing(self._connect()) as connection:
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS peer_messages (
                    message_id TEXT PRIMARY KEY,
                    client_route_id TEXT NOT NULL,
                    remote_message_id TEXT NOT NULL DEFAULT '',
                    direction TEXT NOT NULL,
                    sender_name TEXT NOT NULL DEFAULT '',
                    content TEXT NOT NULL DEFAULT '',
                    attachments_json TEXT NOT NULL DEFAULT '[]',
                    delivery_status TEXT NOT NULL DEFAULT 'stored',
                    created_at_ms INTEGER NOT NULL
                );
                CREATE UNIQUE INDEX IF NOT EXISTS peer_messages_remote_unique
                  ON peer_messages(client_route_id, remote_message_id)
                  WHERE remote_message_id <> '';
                CREATE INDEX IF NOT EXISTS peer_messages_route_time
                  ON peer_messages(client_route_id, created_at_ms, message_id);
                """
            )
            connection.execute(
                """UPDATE peer_messages SET delivery_status = 'failed'
                   WHERE delivery_status IN ('sending', 'preparing')"""
            )
            connection.commit()

    def subscribe(self, listener: Callable[[dict], None]) -> str:
        subscription_id = uuid.uuid4().hex
        with self._lock:
            self._listeners[subscription_id] = listener
        return subscription_id

    def unsubscribe(self, subscription_id: str) -> None:
        with self._lock:
            self._listeners.pop(subscription_id, None)

    def append(
        self,
        *,
        client_route_id: str,
        direction: str,
        content: str = "",
        sender_name: str = "",
        attachments: list[dict] | None = None,
        message_id: str = "",
        remote_message_id: str = "",
        delivery_status: str = "stored",
        created_at_ms: int = 0,
    ) -> dict:
        route_id = str(client_route_id or "").strip()
        if not route_id:
            raise ValueError("client_route_id is required")
        normalized_direction = str(direction or "").strip().lower()
        if normalized_direction not in {"inbound", "outbound"}:
            raise ValueError("direction must be inbound or outbound")
        normalized_content = str(content or "")[:MAX_MESSAGE_CHARS]
        normalized_attachments = self._normalize_attachments(attachments or [])
        if not normalized_content.strip() and not normalized_attachments:
            raise ValueError("peer message requires text or an attachment")
        local_id = str(message_id or "").strip() or f"peer-{uuid.uuid4()}"
        created = int(created_at_ms or int(time.time() * 1000))
        encoded_attachments = json.dumps(
            normalized_attachments,
            ensure_ascii=True,
            separators=(",", ":"),
        )
        with self._lock, closing(self._connect()) as connection:
            if remote_message_id:
                existing = connection.execute(
                    """
                    SELECT * FROM peer_messages
                    WHERE client_route_id = ? AND remote_message_id = ?
                    """,
                    (route_id, str(remote_message_id)),
                ).fetchone()
                if existing is not None:
                    return self._public(existing)
            connection.execute(
                """
                INSERT INTO peer_messages (
                    message_id, client_route_id, remote_message_id, direction,
                    sender_name, content, attachments_json, delivery_status,
                    created_at_ms
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    local_id,
                    route_id,
                    str(remote_message_id or "")[:160],
                    normalized_direction,
                    str(sender_name or "")[:160],
                    normalized_content,
                    encoded_attachments,
                    str(delivery_status or "stored")[:32],
                    created,
                ),
            )
            row = connection.execute(
                "SELECT * FROM peer_messages WHERE message_id = ?",
                (local_id,),
            ).fetchone()
            connection.commit()
        result = self._public(row)
        self._notify(result)
        return result

    def update_delivery_status(self, message_id: str, status: str) -> dict | None:
        with self._lock, closing(self._connect()) as connection:
            connection.execute(
                "UPDATE peer_messages SET delivery_status = ? WHERE message_id = ?",
                (str(status or "")[:32], str(message_id or "")),
            )
            row = connection.execute(
                "SELECT * FROM peer_messages WHERE message_id = ?",
                (str(message_id or ""),),
            ).fetchone()
            connection.commit()
        if row is None:
            return None
        result = self._public(row)
        self._notify(result)
        return result

    def get_message(self, message_id: str) -> dict | None:
        with self._lock, closing(self._connect()) as connection:
            row = connection.execute(
                "SELECT * FROM peer_messages WHERE message_id = ?",
                (str(message_id or ""),),
            ).fetchone()
        return self._public(row) if row is not None else None

    def list_messages(self, client_route_id: str = "", limit: int = 500) -> list[dict]:
        bounded_limit = max(1, min(int(limit or 500), 2_000))
        route_id = str(client_route_id or "").strip()
        with self._lock, closing(self._connect()) as connection:
            if route_id:
                rows = connection.execute(
                    """
                    SELECT * FROM peer_messages
                    WHERE client_route_id = ?
                    ORDER BY created_at_ms DESC, message_id DESC LIMIT ?
                    """,
                    (route_id, bounded_limit),
                ).fetchall()
            else:
                rows = connection.execute(
                    """
                    SELECT * FROM peer_messages
                    ORDER BY created_at_ms DESC, message_id DESC LIMIT ?
                    """,
                    (bounded_limit,),
                ).fetchall()
        return [self._public(row) for row in reversed(rows)]

    def import_attachment(
        self,
        *,
        client_route_id: str,
        message_id: str,
        source: Path,
        name: str,
        mime_type: str,
        sha256: str,
    ) -> dict:
        source_path = Path(source).resolve()
        if not source_path.is_file() or source_path.is_symlink():
            raise ValueError("peer attachment is unavailable")
        size = source_path.stat().st_size
        if size <= 0 or size > MAX_ATTACHMENT_BYTES:
            raise ValueError("peer attachment size is outside the supported range")
        route_directory = self.files_root / self._safe_component(client_route_id)
        message_directory = route_directory / self._safe_component(message_id)
        message_directory.mkdir(parents=True, exist_ok=True)
        safe_name = self._safe_name(name or source_path.name)
        target = message_directory / safe_name
        counter = 1
        while target.exists() and target.resolve() != source_path:
            target = message_directory / f"{target.stem}-{counter}{target.suffix}"
            counter += 1
        if target.resolve() != source_path:
            shutil.copy2(source_path, target)
        return {
            "name": safe_name,
            "mime_type": str(mime_type or "application/octet-stream")[:160],
            "size_bytes": int(target.stat().st_size),
            "sha256": str(sha256 or "")[:64],
            "local_path": str(target.resolve()),
        }

    def attachment_path(self, message_id: str, index: int) -> Path | None:
        with self._lock, closing(self._connect()) as connection:
            row = connection.execute(
                "SELECT attachments_json FROM peer_messages WHERE message_id = ?",
                (str(message_id or ""),),
            ).fetchone()
        if row is None:
            return None
        attachments = self._decode_attachments(row["attachments_json"])
        if index not in range(len(attachments)):
            return None
        value = Path(str(attachments[index].get("local_path") or "")).resolve()
        allowed_roots = (self.files_root.resolve(),)
        try:
            if not any(value.is_relative_to(root) for root in allowed_roots):
                return None
        except AttributeError:
            if not any(str(value).startswith(str(root) + os.sep) for root in allowed_roots):
                return None
        return value if value.is_file() and not value.is_symlink() else None

    def _public(self, row: sqlite3.Row | None) -> dict:
        if row is None:
            raise ValueError("peer message was not stored")
        attachments = self._decode_attachments(row["attachments_json"])
        return {
            "message_id": row["message_id"],
            "client_route_id": row["client_route_id"],
            "direction": row["direction"],
            "sender_name": row["sender_name"],
            "content": row["content"],
            "attachments": [
                {key: value for key, value in item.items() if key != "local_path"}
                | {"available": bool(item.get("local_path"))}
                for item in attachments
            ],
            "delivery_status": row["delivery_status"],
            "created_at_ms": int(row["created_at_ms"]),
        }

    def _notify(self, message: dict) -> None:
        with self._lock:
            listeners = list(self._listeners.values())
        for listener in listeners:
            try:
                listener(dict(message))
            except Exception:
                continue

    @staticmethod
    def _normalize_attachments(attachments: list[dict]) -> list[dict]:
        normalized = []
        for item in attachments[:MAX_ATTACHMENTS]:
            if not isinstance(item, dict):
                continue
            normalized.append({
                "name": str(item.get("name") or "attachment")[:180],
                "mime_type": str(item.get("mime_type") or "application/octet-stream")[:160],
                "size_bytes": max(0, int(item.get("size_bytes") or item.get("size") or 0)),
                "sha256": str(item.get("sha256") or "")[:64],
                "artifact_uri": str(item.get("artifact_uri") or "")[:1_024],
                "local_path": str(item.get("local_path") or "")[:4_096],
            })
        return normalized

    @staticmethod
    def _decode_attachments(value: str) -> list[dict]:
        try:
            decoded = json.loads(value or "[]")
        except (TypeError, ValueError):
            return []
        return [item for item in decoded if isinstance(item, dict)][:MAX_ATTACHMENTS]

    @staticmethod
    def _safe_component(value: str) -> str:
        cleaned = "".join(character for character in str(value or "") if character.isalnum() or character in "-_")
        return cleaned[:96] or uuid.uuid4().hex

    @staticmethod
    def _safe_name(value: str) -> str:
        name = Path(str(value or "attachment")).name
        cleaned = "".join(character if character in _SAFE_NAME_CHARS or ord(character) > 127 else "_" for character in name)
        return cleaned.strip(" .")[:180] or "attachment"


_store: PeerChatStore | None = None
_store_lock = threading.Lock()


def peer_chat_store() -> PeerChatStore:
    global _store
    with _store_lock:
        if _store is None:
            _store = PeerChatStore()
        return _store
