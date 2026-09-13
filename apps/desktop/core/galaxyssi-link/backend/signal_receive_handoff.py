"""Encrypted receive-body extension of the existing delivery ledger.

The JVM owns the ratchet transaction. Its handoff journal is released only after
this database commits the complete authenticated body; this is not a cross-DB
transaction or permission to repeat an external task after a crash.
"""
from __future__ import annotations

import hashlib
import json
import re
import time

import link_delivery as delivery

MAX_TOTAL_BYTES = 64 * 1024 * 1024
MAX_PEER_BYTES = 16 * 1024 * 1024
MAX_TOTAL_RECORDS = 100_000
MAX_PEER_RECORDS = 20_000
MAX_CIPHER_BINDINGS = 8


def ensure_schema(db):
    from signal_receive_compaction import ensure_schema as ensure_completed_schema
    ensure_completed_schema(db)
    db.execute("""CREATE TABLE IF NOT EXISTS inbound_signal_bodies (
        client_route_id TEXT NOT NULL, message_id TEXT NOT NULL,
        content_hash TEXT NOT NULL, body TEXT NOT NULL, byte_count INTEGER NOT NULL,
        created_at REAL NOT NULL, PRIMARY KEY(client_route_id,message_id))""")
    db.execute("""CREATE TABLE IF NOT EXISTS inbound_signal_handoffs (
        client_route_id TEXT NOT NULL, cipher_key TEXT NOT NULL, message_id TEXT NOT NULL,
        receive_digest TEXT NOT NULL, content_hash TEXT NOT NULL,
        remote_name TEXT NOT NULL, remote_device_id INTEGER NOT NULL,
        released INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(client_route_id,cipher_key))""")
    db.execute("CREATE INDEX IF NOT EXISTS signal_handoff_message ON inbound_signal_handoffs(client_route_id,message_id)")
    db.execute("CREATE INDEX IF NOT EXISTS signal_handoff_pending ON inbound_signal_handoffs(released)")
    db.execute("""CREATE TABLE IF NOT EXISTS inbound_signal_usage (
        scope TEXT PRIMARY KEY, byte_count INTEGER NOT NULL, record_count INTEGER NOT NULL)""")


def _cipher_key(remote_name, remote_device_id, receive_digest):
    if not isinstance(receive_digest, str) or not re.fullmatch(r"[a-f0-9]{64}", receive_digest):
        raise ValueError("Invalid authenticated receive digest")
    return hashlib.sha256(json.dumps([remote_name, int(remote_device_id), receive_digest],
                                     separators=(",", ":")).encode()).hexdigest()


def _canonical(envelope):
    return json.dumps(envelope, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


def _body_purpose(route, message_id):
    binding = hashlib.sha256((route + "\0" + message_id).encode("utf-8")).hexdigest()
    return "receive-body-" + binding


def _body(db, route, message_id):
    row = db.execute("SELECT body,content_hash FROM inbound_signal_bodies WHERE client_route_id=? AND message_id=?",
                     (route, message_id)).fetchone()
    if row is None:
        raise RuntimeError("Durable receive body is missing")
    plain = delivery._reveal(row[0], _body_purpose(route, message_id))
    if hashlib.sha256(plain.encode("utf-8")).hexdigest() != row[1]:
        raise RuntimeError("Durable receive body failed integrity validation")
    envelope = json.loads(plain)
    if envelope.get("message_id") != message_id:
        raise RuntimeError("Durable receive body has the wrong message binding")
    return plain


def cached_receive(client_route_id, remote_name, remote_device_id, receive_digest):
    from signal_receive_compaction import completed_in_transaction
    route = delivery._route(client_route_id)
    cipher = _cipher_key(remote_name, remote_device_id, receive_digest)
    with delivery._lock:
        db = delivery._connect()
        try:
            row = db.execute("""SELECT message_id,content_hash,released FROM inbound_signal_handoffs
                              WHERE client_route_id=? AND cipher_key=?""", (route, cipher)).fetchone()
            if row is None:
                return None
            completed = completed_in_transaction(db, route, row[0])
            plaintext = _canonical(completed["envelope"]) if completed else _body(db, route, row[0])
            if json.loads(plaintext).get("source_id") != remote_name:
                raise RuntimeError("Durable receive source binding mismatch")
            return {"plaintext": plaintext, "contentHash": row[1], "receiveDigest": receive_digest,
                    "released": bool(row[2]), "replay": True, "completed": completed is not None}
        finally:
            db.close()


def persist_receive(client_route_id, remote_name, remote_device_id, receipt):
    from signal_receive_compaction import completed_in_transaction, compact_backlog
    plaintext = receipt["plaintext"]
    raw_hash = hashlib.sha256(plaintext.encode("utf-8")).hexdigest()
    if raw_hash != receipt["contentHash"]:
        raise ValueError("Signal handoff body digest mismatch")
    envelope = json.loads(plaintext)
    if envelope.get("source_id") != remote_name:
        raise ValueError("Signal handoff source mismatch")
    message_id = envelope["message_id"]
    canonical = _canonical(envelope)
    if len(canonical.encode("utf-8")) > 2 * 1024 * 1024:
        raise ValueError("Signal handoff exceeds body limit")
    digest = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    cipher = _cipher_key(remote_name, remote_device_id, receipt["receiveDigest"])
    route = delivery._route(client_route_id)
    with delivery._lock:
        db = delivery._connect()
        try:
            db.execute("BEGIN IMMEDIATE")
            db.execute("""INSERT OR IGNORE INTO inbound_content_hashes
                          (client_route_id,message_id,content_hash,received_at) VALUES(?,?,?,?)""",
                       (route, message_id, digest, time.time()))
            bound = db.execute("SELECT content_hash FROM inbound_content_hashes WHERE client_route_id=? AND message_id=?",
                               (route, message_id)).fetchone()
            if bound[0] != digest:
                raise delivery.InboundContentConflict("Received message conflicts with existing content")
            completed = completed_in_transaction(db, route, message_id)
            existing = db.execute("SELECT content_hash FROM inbound_signal_bodies WHERE client_route_id=? AND message_id=?",
                                  (route, message_id)).fetchone()
            if existing:
                if existing[0] != digest:
                    raise delivery.InboundContentConflict("Received body cannot replace another message")
                _body(db, route, message_id)
            elif completed is None:
                compact_backlog(db, route)
                protected = delivery._protect(canonical, _body_purpose(route, message_id))
                size = len(protected.encode("utf-8")) + 512
                _adjust(db, "total", size, 1, MAX_TOTAL_BYTES, MAX_TOTAL_RECORDS)
                _adjust(db, route, size, 1, MAX_PEER_BYTES, MAX_PEER_RECORDS)
                db.execute("INSERT INTO inbound_signal_bodies VALUES(?,?,?,?,?,?)",
                           (route, message_id, digest, protected, size, time.time()))
            db.execute("""INSERT OR IGNORE INTO inbound_messages(client_route_id,message_id,received_at,status)
                          VALUES(?,?,?,'RX_STORED')""", (route, message_id, time.time()))
            previous = db.execute("""SELECT message_id,content_hash FROM inbound_signal_handoffs
                                     WHERE client_route_id=? AND cipher_key=?""", (route, cipher)).fetchone()
            if previous and (previous[0] != message_id or previous[1] != raw_hash):
                raise delivery.InboundContentConflict("Ciphertext is bound to different received content")
            if not previous:
                count = db.execute("SELECT count(*) FROM inbound_signal_handoffs WHERE client_route_id=? AND message_id=?",
                                   (route, message_id)).fetchone()[0]
                if count >= MAX_CIPHER_BINDINGS:
                    raise RuntimeError("Too many ciphertext variants for one message")
                db.execute("""INSERT INTO inbound_signal_handoffs
                              (client_route_id,cipher_key,message_id,receive_digest,content_hash,remote_name,remote_device_id)
                              VALUES(?,?,?,?,?,?,?)""",
                           (route, cipher, message_id, receipt["receiveDigest"], raw_hash,
                            delivery._protect(remote_name, "receive-peer"), int(remote_device_id)))
            db.commit()
        finally:
            db.close()


def mark_released(client_route_id, remote_name, remote_device_id, receive_digest):
    from signal_receive_compaction import compact_in_transaction
    with delivery._lock:
        db = delivery._connect()
        try:
            db.execute("BEGIN IMMEDIATE")
            route = delivery._route(client_route_id)
            cipher = _cipher_key(remote_name, remote_device_id, receive_digest)
            db.execute("UPDATE inbound_signal_handoffs SET released=1 WHERE client_route_id=? AND cipher_key=?", (route, cipher))
            row = db.execute("SELECT message_id FROM inbound_signal_handoffs WHERE client_route_id=? AND cipher_key=?",
                             (route, cipher)).fetchone()
            if row:
                compact_in_transaction(db, route, row[0])
            db.commit()
        finally:
            db.close()


def pending_releases(limit=4):
    from signal_receive_compaction import completed_in_transaction
    if not 1 <= limit <= 64:
        raise ValueError("Invalid receive handoff page limit")
    with delivery._lock:
        db = delivery._connect()
        try:
            rows = db.execute("""SELECT client_route_id,remote_name,remote_device_id,receive_digest,content_hash,message_id,cipher_key
                                 FROM inbound_signal_handoffs WHERE released=0 LIMIT ?""", (limit,)).fetchall()
            result = []
            for route, remote, device, digest, content_hash, message_id, cipher in rows:
                remote = delivery._reveal(remote, "receive-peer")
                if _cipher_key(remote, device, digest) != cipher:
                    raise RuntimeError("Receive cleanup peer binding mismatch")
                completed = completed_in_transaction(db, route, message_id)
                envelope = completed["envelope"] if completed else json.loads(_body(db, route, message_id))
                if envelope.get("source_id") != remote:
                    raise RuntimeError("Receive cleanup source binding mismatch")
                result.append({"linkScope": delivery._unroute(route), "remoteName": remote,
                               "remoteDeviceId": device, "receiveDigest": digest, "contentHash": content_hash})
            return result
        finally:
            db.close()


def _adjust(db, scope, byte_count, record_count, max_bytes, max_records):
    row = db.execute("SELECT byte_count,record_count FROM inbound_signal_usage WHERE scope=?", (scope,)).fetchone() or (0, 0)
    total_bytes, total_records = row[0] + byte_count, row[1] + record_count
    if total_bytes < 0 or total_records < 0:
        raise RuntimeError("Receive usage counter underflow")
    if total_bytes > max_bytes or total_records > max_records:
        raise RuntimeError("Durable receive storage is full")
    if total_records == 0:
        db.execute("DELETE FROM inbound_signal_usage WHERE scope=?", (scope,))
    else:
        db.execute("INSERT INTO inbound_signal_usage VALUES(?,?,?) ON CONFLICT(scope) DO UPDATE SET byte_count=excluded.byte_count,record_count=excluded.record_count",
                   (scope, total_bytes, total_records))


def discard_route_in_transaction(db, route):
    usage = db.execute("SELECT byte_count,record_count FROM inbound_signal_usage WHERE scope=?", (route,)).fetchone()
    if usage:
        _adjust(db, "total", -usage[0], -usage[1], MAX_TOTAL_BYTES, MAX_TOTAL_RECORDS)
    db.execute("DELETE FROM inbound_signal_usage WHERE scope=?", (route,))
    db.execute("DELETE FROM inbound_signal_bodies WHERE client_route_id=?", (route,))
    db.execute("DELETE FROM inbound_signal_completed WHERE client_route_id=?", (route,))
    db.execute("DELETE FROM inbound_signal_handoffs WHERE client_route_id=?", (route,))
