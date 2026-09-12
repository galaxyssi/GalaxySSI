"""Crash-aware business handoff using the existing Link inbox and bounded OS locks."""
from __future__ import annotations

import hashlib
import errno
import json
import os
import secrets
import time
from dataclasses import dataclass

import link_delivery as delivery
from signal_receive_handoff import _body

STRIPES = 256
PENDING_SQL = """SELECT b.client_route_id,b.message_id,b.byte_count FROM inbound_messages m
                 JOIN inbound_signal_bodies b USING(client_route_id,message_id)
                 WHERE m.dispatch_state IN ('stored','retry','running') AND m.dispatch_retry_at<=?
                 ORDER BY m.dispatch_retry_at,m.received_at LIMIT ?"""
REPLAYABLE_TYPES = frozenset({
    "delivery_ack", "peer_message", "connector_status_request", "agent_task_recovery_request",
    "agent_task_result_page_request", "agent_task_result_received", "agent_task_approval",
    "input_attachment_manifest", "input_attachment_chunk", "input_attachment_request_result",
    "input_attachment_blob_offer", "artifact_blob_capability", "artifact_blob_receipt",
    "artifact_receipt", "artifact_redelivery_request",
})


def retry_safe(envelope: dict) -> bool:
    payload = envelope.get("payload") or {}
    kind = str(payload.get("type") or "text")
    if kind in REPLAYABLE_TYPES:
        return True
    # Cancel replay additionally needs an execution-generation fence; until that
    # exists, an interrupted cancel must not stop a subsequently resumed run.
    # The existing task manager checks stable identity before creating any run.
    return (kind in {"text", "image", "file_notify", "audio", "voice"}
            and payload.get("audio_mode") != "transcribe_only"
            and all(isinstance(payload.get(key), str) and payload[key].strip()
                    for key in ("client_route_id", "conversation_id", "task_id", "turn_id")))


class DispatchGuard:
    """Locks are held across the handler, not across model execution or network ACKs.

    OS release after process death proves the old handler cannot still run. A
    bounded stripe set avoids one permanent file/thread for every peer/message.
    """
    def __init__(self, route: str, message_id: str):
        self.route, self.message_id = route, message_id
        self.file = None

    def __enter__(self):
        root = delivery.DB_PATH.parent / (delivery.DB_PATH.name + ".dispatch-locks")
        root.mkdir(parents=True, exist_ok=True)
        stripe = hashlib.sha256((self.route + "\0" + self.message_id).encode()).digest()[0] % STRIPES
        handle = open(root / f"{stripe:02x}.lock", "a+b")
        try:
            if os.fstat(handle.fileno()).st_size == 0:
                handle.write(b"\0")
                handle.flush()
            handle.seek(0)
            if os.name == "nt":
                import msvcrt
                msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as exc:
            handle.close()
            if exc.errno not in (errno.EACCES, errno.EAGAIN):
                raise
            return self
        self.file = handle
        return self

    @property
    def acquired(self):
        return self.file is not None

    def __exit__(self, *_):
        if self.file is None:
            return
        try:
            self.file.seek(0)
            if os.name == "nt":
                import msvcrt
                msvcrt.locking(self.file.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                import fcntl
                fcntl.flock(self.file, fcntl.LOCK_UN)
        finally:
            self.file.close()
            self.file = None


@dataclass(frozen=True)
class Claim:
    state: str
    token: str = ""
    recovered: bool = False


def load_envelope(route_id: str, message_id: str) -> dict:
    with delivery._lock:
        db = delivery._connect()
        try:
            return json.loads(_body(db, delivery._route(route_id), message_id))
        finally:
            db.close()


def begin(guard: DispatchGuard, envelope: dict, *, now: float | None = None, admission_token="") -> Claim:
    if not guard.acquired:
        return Claim("busy")
    route, message_id = delivery._route(guard.route), guard.message_id
    if envelope.get("message_id") != message_id:
        raise ValueError("Dispatch message binding mismatch")
    at = time.time() if now is None else now
    with delivery._lock:
        db = delivery._connect()
        try:
            db.execute("BEGIN IMMEDIATE")
            stored = json.loads(_body(db, route, message_id))
            if json.dumps(stored, sort_keys=True, separators=(",", ":"), allow_nan=False) != json.dumps(
                    envelope, sort_keys=True, separators=(",", ":"), allow_nan=False):
                raise delivery.InboundContentConflict("Dispatch body differs from durable message")
            db.execute("""INSERT OR IGNORE INTO inbound_messages(client_route_id,message_id,received_at,status)
                          VALUES(?,?,?,'RX_STORED')""", (route, message_id, at))
            state, retry_at, admission = db.execute("""SELECT dispatch_state,dispatch_retry_at,dispatch_admission_token FROM inbound_messages
                                           WHERE client_route_id=? AND message_id=?""", (route, message_id)).fetchone()
            admitted = bool(admission_token) and secrets.compare_digest(admission_token, admission)
            if state in {"dispatched", "uncertain", "rejected"}:
                db.commit()
                return Claim(state)
            if retry_at > at and not admitted:
                db.commit()
                return Claim("deferred")
            if state == "running" and not retry_safe(envelope):
                db.execute("""UPDATE inbound_messages SET dispatch_state='uncertain',dispatch_updated_at=?,
                              dispatch_error='interrupted_external_handoff' WHERE client_route_id=? AND message_id=?""",
                           (at, route, message_id))
                db.commit()
                return Claim("uncertain", recovered=True)
            token = secrets.token_hex(16)
            db.execute("""UPDATE inbound_messages SET dispatch_state='running',dispatch_token=?,dispatch_admission_token='',dispatch_attempts=dispatch_attempts+1,
                          dispatch_updated_at=?,dispatch_error='' WHERE client_route_id=? AND message_id=?""",
                       (token, at, route, message_id))
            db.commit()
            return Claim("run", token, state == "running")
        finally:
            db.close()


def finish(guard: DispatchGuard, claim: Claim, *, error: Exception | None = None, replayable: bool = False):
    if not guard.acquired or claim.state != "run" or not claim.token:
        raise ValueError("An owned dispatch claim is required")
    route, message_id = delivery._route(guard.route), guard.message_id
    with delivery._lock:
        db = delivery._connect()
        try:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("""SELECT dispatch_attempts FROM inbound_messages
                              WHERE client_route_id=? AND message_id=? AND dispatch_token=? AND dispatch_state='running'""",
                             (route, message_id, claim.token)).fetchone()
            if row is None:
                return False  # Explicit revocation may have removed the inbox during this handler.
            state = "dispatched" if error is None else ("retry" if replayable else "uncertain")
            retry_at = time.time() + min(60.0, 0.5 * 2 ** min(7, row[0])) if state == "retry" else 0
            db.execute("""UPDATE inbound_messages SET dispatch_state=?,dispatch_updated_at=?,dispatch_retry_at=?,dispatch_error=?
                          WHERE client_route_id=? AND message_id=? AND dispatch_token=?""",
                       (state, time.time(), retry_at, type(error).__name__ if error else "", route, message_id, claim.token))
            db.commit()
            return True
        finally:
            db.close()


def pending(*, limit=16, now=None):
    if not 1 <= limit <= 64:
        raise ValueError("Invalid dispatch page limit")
    at = time.time() if now is None else now
    with delivery._lock:
        db = delivery._connect()
        try:
            db.execute("BEGIN IMMEDIATE")
            rows = db.execute(PENDING_SQL, (at, limit)).fetchall()
            # This only spaces queue admission; OS locks, never this deadline,
            # establish that an interrupted business handler no longer runs.
            admitted = []
            for route, message_id, size in rows:
                token = secrets.token_hex(16)
                db.execute("""UPDATE inbound_messages SET dispatch_retry_at=?,dispatch_admission_token=? WHERE client_route_id=? AND message_id=?""",
                           (at + 5.0, token, route, message_id))
                admitted.append((delivery._unroute(route), message_id, size, token))
            db.commit()
            return admitted
        finally:
            db.close()


def reject_stored(route: str, message_id: str, reason: str):
    with DispatchGuard(route, message_id) as guard:
        if not guard.acquired:
            return
        with delivery._lock:
            db = delivery._connect()
            try:
                db.execute("""UPDATE inbound_messages SET dispatch_state='rejected',dispatch_error=?,dispatch_updated_at=?
                              WHERE client_route_id=? AND message_id=? AND dispatch_state IN ('stored','retry','running')""",
                           (reason, time.time(), delivery._route(route), message_id))
                db.commit()
            finally:
                db.close()
