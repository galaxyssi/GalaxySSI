"""Authenticated contact reminders, separate from chat and Agent execution."""
from __future__ import annotations

import json
import hashlib
import re
import sqlite3
import threading
import time
import uuid
from contextlib import contextmanager
from pathlib import Path

from pairing_state import DATA_DIR
from secure_state import decrypt_text, encrypt_text

TERMINAL = {"acknowledged", "dismissed", "cancelled", "expired"}


class PeerReminders:
    def __init__(self, path: Path | None = None, clock=None):
        self.path = Path(path or DATA_DIR / "peer_reminders.db")
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.clock = clock or (lambda: int(time.time() * 1000))
        self.lock = threading.RLock()
        self.listeners = {}
        with self._db() as db:
            db.execute("CREATE TABLE IF NOT EXISTS reminders (id TEXT PRIMARY KEY, expires INTEGER NOT NULL, payload TEXT NOT NULL)")
            db.execute("CREATE INDEX IF NOT EXISTS reminder_expiry ON reminders(expires)")

    @contextmanager
    def _db(self):
        connection = sqlite3.connect(self.path, timeout=5)
        try:
            with connection:
                yield connection
        finally:
            connection.close()

    def _read(self, db, identifier):
        row = db.execute("SELECT payload FROM reminders WHERE id=?", (identifier,)).fetchone()
        return json.loads(decrypt_text(self.path, row[0], purpose=self._purpose(identifier))) if row else None

    @staticmethod
    def _purpose(identifier):
        return "reminder." + hashlib.sha256(identifier.encode("utf-8")).hexdigest()

    def _write(self, db, value):
        encrypted = encrypt_text(self.path, json.dumps(value), purpose=self._purpose(value["id"]))
        db.execute("INSERT OR REPLACE INTO reminders VALUES (?,?,?)", (value["id"], value["expires_at"], encrypted))

    def receive(self, route: str, name: str, payload: dict):
        identifier = str(payload.get("reminder_id") or "")
        created, expires = payload.get("created_at"), payload.get("expires_at")
        event = payload.get("reminder_action")
        now = self.clock()
        if (not route or not re.fullmatch(r"[a-zA-Z0-9-]{16,64}", identifier)
                or type(created) is not int or type(expires) is not int
                or created <= 0 or created > now + 30_000 or not 0 < expires - created <= 120_000
                or expires <= now or event not in {"request", "cancelled"}):
            return None
        changed = False
        with self.lock, self._db() as db:
            db.execute("DELETE FROM reminders WHERE expires<?", (now - 86_400_000,))
            value = self._read(db, identifier)
            if value and (value["client_route_id"] != route or value["created_at"] != created or value["expires_at"] != expires):
                return None
            if value is None:
                value = {"id": identifier, "client_route_id": route, "sender_name": name[:160],
                         "created_at": created, "expires_at": expires,
                         "status": "received" if event == "request" else "cancelled"}
                value["revision"] = 0
                changed = True
            elif event == "cancelled" and value["status"] not in TERMINAL:
                value["status"] = "cancelled"
                changed = True
            if changed:
                value["revision"] = value.get("revision", 0) + 1
                self._write(db, value)
        if changed:
            self._emit(value)
        return value

    def act(self, identifier: str, action: str):
        if action not in {"muted", "dismissed", "acknowledged"}:
            raise ValueError("Invalid reminder action")
        with self.lock, self._db() as db:
            value = self._read(db, identifier)
            if not value:
                raise ValueError("Reminder not found")
            if value["status"] not in TERMINAL:
                value["status"] = action if value["expires_at"] > self.clock() else "expired"
                value["revision"] = value.get("revision", 0) + 1
                self._write(db, value)
        self._emit(value)
        return value

    def active(self):
        with self.lock, self._db() as db:
            ids = db.execute("SELECT id FROM reminders WHERE expires>? ORDER BY expires", (self.clock(),)).fetchall()
            return [value for (identifier,) in ids if (value := self._read(db, identifier))["status"] not in TERMINAL]

    def subscribe(self, listener):
        identifier = uuid.uuid4().hex
        with self.lock:
            self.listeners[identifier] = listener
        return identifier

    def unsubscribe(self, identifier):
        with self.lock:
            self.listeners.pop(identifier, None)

    def _emit(self, value):
        with self.lock:
            listeners = list(self.listeners.values())
        for listener in listeners:
            try:
                listener(dict(value))
            except Exception:
                import logging
                logging.getLogger(__name__).exception("Reminder observer failed")


_instance = None
_instance_lock = threading.Lock()


def peer_reminders():
    global _instance
    with _instance_lock:
        if _instance is None:
            _instance = PeerReminders()
        return _instance


def reply_payload(value):
    return {"type": "peer_attention", "peer_chat": True, "reminder_id": value["id"],
            "reminder_action": value["status"], "created_at": value["created_at"],
            "expires_at": value["expires_at"], "time": int(time.time() * 1000)}


def respond(identifier, action):
    from mqtt_bridge import client, _publish_phone_payload
    from pairing_state import get_client
    value = peer_reminders().act(identifier, action)
    route = value["client_route_id"]
    if not get_client(route):
        raise ValueError("Contact is no longer paired")
    queued = _publish_phone_payload(client, {"_client_route_id": route}, reply_payload(value), durable=True)
    return {"reminder": value, "queued": bool(queued)}
