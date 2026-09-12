"""Pair-scoped wire fragments in the existing Link database, before Signal ingress.

Bytes are already Signal ciphertext. No attachment-at-rest encryption, business
ledger or per-transfer worker is introduced here. Call only after pair AEAD.
"""
from __future__ import annotations

import base64
import json
import time
from contextlib import closing
from dataclasses import dataclass

from mqtt_delivery_envelope import content_hash
from mqtt_wire_chunking import (SCHEME, CHUNK_DATA_BYTES, MAX_CHUNK_COUNT,
                                MAX_REASSEMBLED_BYTES, _sha256)


def _text(value, maximum=512):
    if (not isinstance(value, str) or not value or len(value.encode("utf-8")) > maximum
            or any(ord(c) < 32 or ord(c) == 127 for c in value)):
        raise ValueError("Invalid MQTT chunk identity")
    return value


def _hash(value):
    if not isinstance(value, str) or len(value) != 64 or any(c not in "0123456789abcdef" for c in value):
        raise ValueError("Invalid MQTT chunk hash")
    return value


@dataclass(frozen=True)
class Chunk:
    transfer: str
    manifest_hash: str
    count: int
    total: int
    index: int
    digest: str
    data: bytes
    source: str
    target: str

    @classmethod
    def parse(cls, wire):
        if wire.get("scheme") != SCHEME:
            raise ValueError("Not a GalaxySSI MQTT chunk")
        transfer = _hash(wire.get("transfer_id"))
        if transfer != _hash(wire.get("sha256")):
            raise ValueError("Invalid MQTT transfer identity")
        digest = _hash(wire.get("chunk_sha256"))
        # Integers, not numeric strings or booleans, are part of the new contract.
        values = [wire.get(key) for key in ("chunk_count", "total_bytes", "chunk_index")]
        if any(type(value) is not int for value in values):
            raise ValueError("Invalid MQTT chunk counters")
        count, total, index = values
        if not (1 <= count <= MAX_CHUNK_COUNT and count <= total <= MAX_REASSEMBLED_BYTES and 0 <= index < count):
            raise ValueError("Invalid MQTT chunk layout")
        source, target = _text(wire.get("from")), _text(wire.get("to"))
        encoded = wire.get("data")
        if (not isinstance(encoded, str) or not encoded.isascii()
                or not 0 < len(encoded) <= 4 * ((CHUNK_DATA_BYTES + 2) // 3)):
            raise ValueError("Invalid MQTT chunk encoding")
        try:
            data = base64.b64decode(encoded, validate=True)
        except ValueError as error:
            raise ValueError("Invalid MQTT chunk encoding") from error
        if (not data or len(data) > min(CHUNK_DATA_BYTES, total) or _sha256(data) != digest
                or base64.b64encode(data).decode("ascii") != encoded):
            raise ValueError("MQTT chunk integrity check failed")
        pieces = [transfer, str(count), str(total), source, target]
        canonical = b"GalaxySSI/WireChunkManifest/v1\0" + b"".join(
            str(len(raw)).encode("ascii") + b":" + raw for raw in (piece.encode("utf-8") for piece in pieces))
        return cls(transfer, _sha256(canonical), count, total, index, digest, data, source, target)


class DurableChunkAssembler:
    RETENTION_SECONDS = 8 * 24 * 60 * 60

    def __init__(self, connect, *, clock=time.time, max_transfers=16, max_bytes=32 * 1024 * 1024,
                 max_peer_transfers=8, max_peer_bytes=16 * 1024 * 1024):
        if min(max_transfers, max_bytes, max_peer_transfers, max_peer_bytes) <= 0:
            raise ValueError("Invalid MQTT fragment quota")
        self.connect, self.clock = connect, clock
        self.max_transfers, self.max_bytes = max_transfers, max_bytes
        self.max_peer_transfers, self.max_peer_bytes = max_peer_transfers, max_peer_bytes

    @staticmethod
    def initialize(db):
        db.execute("""CREATE TABLE IF NOT EXISTS mqtt_wire_transfers (
            scope_digest TEXT NOT NULL, transfer_id TEXT NOT NULL, manifest_hash TEXT NOT NULL,
            chunk_count INTEGER NOT NULL, total_bytes INTEGER NOT NULL, stored_bytes INTEGER NOT NULL,
            expires_at REAL NOT NULL, wire_hash TEXT NOT NULL DEFAULT '',
            PRIMARY KEY(scope_digest,transfer_id))""")
        db.execute("CREATE INDEX IF NOT EXISTS mqtt_wire_expiry ON mqtt_wire_transfers(expires_at)")
        db.execute("""CREATE TABLE IF NOT EXISTS mqtt_wire_parts (
            scope_digest TEXT NOT NULL, transfer_id TEXT NOT NULL, chunk_index INTEGER NOT NULL,
            chunk_hash TEXT NOT NULL, data BLOB NOT NULL,
            PRIMARY KEY(scope_digest,transfer_id,chunk_index))""")

    @staticmethod
    def scope_key(scope):
        return _sha256(_text(scope).encode("utf-8"))

    @staticmethod
    def _delete(db, scope, transfer):
        db.execute("DELETE FROM mqtt_wire_parts WHERE scope_digest=? AND transfer_id=?", (scope, transfer))
        db.execute("DELETE FROM mqtt_wire_transfers WHERE scope_digest=? AND transfer_id=?", (scope, transfer))

    def _prune(self, db):
        expired = db.execute("SELECT scope_digest,transfer_id FROM mqtt_wire_transfers WHERE expires_at<=? "
                             "ORDER BY expires_at LIMIT 256", (self.clock(),)).fetchall()
        for scope, transfer in expired:
            self._delete(db, scope, transfer)

    def _quota(self, db, scope, total):
        for where, args, max_count, max_bytes in (
                ("", (), self.max_transfers, self.max_bytes),
                (" WHERE scope_digest=?", (scope,), self.max_peer_transfers, self.max_peer_bytes)):
            count, size = db.execute("SELECT COUNT(*),COALESCE(SUM(total_bytes),0) FROM mqtt_wire_transfers" + where, args).fetchone()
            if count >= max_count or size + total > max_bytes:
                raise ValueError("Durable MQTT fragment capacity exceeded")

    def accept(self, scope, wire):
        chunk = Chunk.parse(wire)  # Validation precedes any durable reservation.
        scope = self.scope_key(scope)
        with closing(self.connect()) as db:
            self.initialize(db)
            db.execute("BEGIN IMMEDIATE")
            try:
                self._prune(db)
                row = db.execute("SELECT manifest_hash,stored_bytes FROM mqtt_wire_transfers WHERE scope_digest=? AND transfer_id=?",
                                 (scope, chunk.transfer)).fetchone()
                if row is None:
                    self._quota(db, scope, chunk.total)
                    db.execute("INSERT INTO mqtt_wire_transfers(scope_digest,transfer_id,manifest_hash,chunk_count,total_bytes,stored_bytes,expires_at) "
                               "VALUES(?,?,?,?,?,0,?)", (scope, chunk.transfer, chunk.manifest_hash, chunk.count, chunk.total,
                                                       self.clock() + self.RETENTION_SECONDS))
                    stored = 0
                else:
                    if row[0] != chunk.manifest_hash:
                        raise ValueError("MQTT chunk metadata mismatch")
                    stored = row[1]
                old = db.execute("SELECT chunk_hash,data FROM mqtt_wire_parts WHERE scope_digest=? AND transfer_id=? AND chunk_index=?",
                                 (scope, chunk.transfer, chunk.index)).fetchone()
                if old is not None:
                    if old[0] != chunk.digest:
                        raise ValueError("Conflicting MQTT chunk duplicate")
                    if bytes(old[1]) != chunk.data:
                        if _sha256(old[1]) == old[0]:
                            raise ValueError("Conflicting MQTT chunk duplicate")
                        db.execute("UPDATE mqtt_wire_parts SET data=? WHERE scope_digest=? AND transfer_id=? AND chunk_index=?",
                                   (chunk.data, scope, chunk.transfer, chunk.index))
                else:
                    if stored + len(chunk.data) > chunk.total:
                        raise ValueError("MQTT transfer length check failed")
                    db.execute("INSERT INTO mqtt_wire_parts VALUES(?,?,?,?,?)",
                               (scope, chunk.transfer, chunk.index, chunk.digest, chunk.data))
                    db.execute("UPDATE mqtt_wire_transfers SET stored_bytes=stored_bytes+? WHERE scope_digest=? AND transfer_id=?",
                               (len(chunk.data), scope, chunk.transfer))
                count = db.execute("SELECT COUNT(*) FROM mqtt_wire_parts WHERE scope_digest=? AND transfer_id=?", (scope, chunk.transfer)).fetchone()[0]
                result = None
                if count == chunk.count:
                    parts = db.execute("SELECT chunk_index,chunk_hash,data FROM mqtt_wire_parts WHERE scope_digest=? AND transfer_id=? ORDER BY chunk_index",
                                       (scope, chunk.transfer)).fetchall()
                    for expected, (index, digest, data) in enumerate(parts):
                        if index != expected or _sha256(data) != digest:
                            raise ValueError("Stored MQTT chunk integrity check failed")
                    assembled = b"".join(bytes(row[2]) for row in parts)
                    if len(assembled) != chunk.total or _sha256(assembled) != chunk.transfer:
                        raise ValueError("MQTT transfer integrity check failed")
                    result = assembled.decode("utf-8", errors="strict")
                    decoded = json.loads(result)
                    if decoded.get("from") != chunk.source or decoded.get("to") != chunk.target:
                        raise ValueError("MQTT assembled endpoint mismatch")
                    digest = content_hash(decoded)
                    db.execute("UPDATE mqtt_wire_transfers SET wire_hash=? WHERE scope_digest=? AND transfer_id=?",
                               (digest, scope, chunk.transfer))
                db.commit()
                return result
            except BaseException:
                db.rollback()
                raise

    def stored_indices(self, scope, transfer):
        scope, transfer = self.scope_key(scope), _hash(transfer)
        with closing(self.connect()) as db:
            self.initialize(db)
            return tuple(row[0] for row in db.execute("SELECT p.chunk_index FROM mqtt_wire_parts p JOIN mqtt_wire_transfers t "
                "ON p.scope_digest=t.scope_digest AND p.transfer_id=t.transfer_id WHERE p.scope_digest=? AND p.transfer_id=? "
                "AND t.expires_at>? ORDER BY p.chunk_index", (scope, transfer, self.clock())))

    def release_after_store(self, scope, transfer, stored_wire_hash):
        """Caller must obtain stored_wire_hash from the existing durable inbox proof."""
        scope, transfer, stored_wire_hash = self.scope_key(scope), _hash(transfer), _hash(stored_wire_hash)
        with closing(self.connect()) as db:
            self.initialize(db)
            db.execute("BEGIN IMMEDIATE")
            try:
                row = db.execute("SELECT wire_hash FROM mqtt_wire_transfers WHERE scope_digest=? AND transfer_id=?",
                                 (scope, transfer)).fetchone()
                released = row is not None and row[0] == stored_wire_hash
                if released:
                    self._delete(db, scope, transfer)
                db.commit()
                return released
            except BaseException:
                db.rollback()
                raise
