"""Authenticated wire-chunk state, separate from business RX_STORED receipts."""
from __future__ import annotations

import base64
from contextlib import closing
from dataclasses import dataclass
import secrets
import time

from mqtt_broker_catalog import BROKER_IDS
from mqtt_durable_chunks import Chunk, DurableChunkAssembler, _hash

FIELD = "_mqtt_chunks"
PROBE = "link_chunk_probe"
STATE = "link_chunk_state"
BROKERS = tuple(sorted(BROKER_IDS))


def _nonce(value):
    if not isinstance(value, str) or len(value) != 32 or any(c not in "0123456789abcdef" for c in value):
        raise ValueError("Invalid chunk request identity")
    return value


def _integer(value, minimum, maximum):
    if type(value) is not int or not minimum <= value <= maximum:
        raise ValueError("Invalid chunk state counter")
    return value


def bitmap(count, indices):
    result = bytearray((count + 7) // 8)
    for index in indices:
        _integer(index, 0, count - 1)
        result[index // 8] |= 1 << (index % 8)
    return bytes(result)


@dataclass(frozen=True)
class Query:
    transfer: str
    manifest: str
    count: int
    request: str

    def wire(self):
        return {"type": PROBE, "version": 1, "transfer_id": self.transfer,
                "manifest_hash": self.manifest, "chunk_count": self.count, "request_id": self.request}

    @classmethod
    def parse(cls, raw):
        if not isinstance(raw, dict) or raw.get("type") not in (PROBE, STATE) or type(raw.get("version")) is not int or raw["version"] != 1:
            raise ValueError("Invalid chunk control frame")
        return cls(_hash(raw.get("transfer_id")), _hash(raw.get("manifest_hash")),
                   _integer(raw.get("chunk_count"), 1, 96), _nonce(raw.get("request_id")))

    @classmethod
    def from_chunk(cls, raw):
        if FIELD not in raw:
            return None
        query, chunk = cls.parse(raw[FIELD]), Chunk.parse(raw)
        if (query.transfer, query.manifest, query.count) != (chunk.transfer, chunk.manifest_hash, chunk.count):
            raise ValueError("Chunk request does not match its manifest")
        return query

    def response(self, epoch, revision, indices):
        return {**self.wire(), "type": STATE, "store_epoch": _nonce(epoch),
                "revision": _integer(revision, 0, 9_007_199_254_740_991),
                "stored_bitmap": base64.b64encode(bitmap(self.count, indices)).decode("ascii")}


def parse_state(raw):
    query = Query.parse(raw)
    if raw.get("type") != STATE:
        raise ValueError("Not a chunk state receipt")
    epoch = _nonce(raw.get("store_epoch"))
    revision = _integer(raw.get("revision"), 0, 9_007_199_254_740_991)
    encoded = raw.get("stored_bitmap")
    size = (query.count + 7) // 8
    if not isinstance(encoded, str) or len(encoded) != 4 * ((size + 2) // 3):
        raise ValueError("Invalid chunk bitmap size")
    data = base64.b64decode(encoded, validate=True)
    if (len(data) != size or base64.b64encode(data).decode("ascii") != encoded
            or (query.count % 8 and data[-1] >> (query.count % 8))
            or (epoch == "0" * 32 and (revision or any(data)))):
        raise ValueError("Invalid chunk state bitmap")
    return query, epoch, revision, data


class OutgoingChunks:
    """Only bitmap/path metadata; the existing durable outbox owns wire bytes."""
    def __init__(self, connect, *, clock=time.time):
        self.connect, self.clock = connect, clock

    @staticmethod
    def initialize(db):
        db.execute("""CREATE TABLE IF NOT EXISTS mqtt_outgoing_chunks (
            scope_digest TEXT NOT NULL, transfer_id TEXT NOT NULL, manifest_hash TEXT NOT NULL,
            chunk_count INTEGER NOT NULL, request_id TEXT NOT NULL, store_epoch TEXT NOT NULL,
            revision INTEGER NOT NULL, stored_bitmap BLOB NOT NULL, path_bits BLOB NOT NULL,
            expires_at REAL NOT NULL, PRIMARY KEY(scope_digest,transfer_id))""")
        db.execute("CREATE INDEX IF NOT EXISTS mqtt_outgoing_chunk_expiry ON mqtt_outgoing_chunks(expires_at)")

    def prepare(self, scope, parts):
        chunk = Chunk.parse(parts[0])
        if len(parts) != chunk.count:
            raise ValueError("Incomplete outgoing chunk manifest")
        key = DurableChunkAssembler.scope_key(scope), chunk.transfer
        request = secrets.token_hex(16)
        with closing(self.connect()) as db:
            self.initialize(db)
            with db:
                db.execute("BEGIN IMMEDIATE")
                db.execute("DELETE FROM mqtt_outgoing_chunks WHERE scope_digest=? AND transfer_id=? AND expires_at<=?", (*key, self.clock()))
                db.execute("DELETE FROM mqtt_outgoing_chunks WHERE rowid IN (SELECT rowid FROM mqtt_outgoing_chunks WHERE expires_at<=? LIMIT 256)", (self.clock(),))
                row = db.execute("SELECT manifest_hash,chunk_count,stored_bitmap,path_bits FROM mqtt_outgoing_chunks WHERE scope_digest=? AND transfer_id=?", key).fetchone()
                if row is None:
                    for where, args, limit in (("", (), 65536), (" WHERE scope_digest=?", (key[0],), 4096)):
                        if db.execute("SELECT COUNT(*) FROM mqtt_outgoing_chunks" + where, args).fetchone()[0] >= limit:
                            raise ValueError("Outgoing chunk metadata capacity exceeded")
                    stored, paths = bytes((chunk.count + 7) // 8), bytes(chunk.count)
                    db.execute("INSERT INTO mqtt_outgoing_chunks VALUES(?,?,?,?,?,'',-1,?,?,?)",
                               (*key, chunk.manifest_hash, chunk.count, request, stored, paths, self.clock() + 7 * 86400))
                else:
                    if row[:2] != (chunk.manifest_hash, chunk.count):
                        raise ValueError("Outgoing chunk manifest changed")
                    stored, paths = bytes(row[2]), bytes(row[3])
                    db.execute("UPDATE mqtt_outgoing_chunks SET request_id=?,store_epoch='',revision=-1 WHERE scope_digest=? AND transfer_id=?", (request, *key))
        query = Query(chunk.transfer, chunk.manifest_hash, chunk.count, request)
        selected = [(index, {**part, FIELD: query.wire()}) for index, part in enumerate(parts)
                    if not stored[index // 8] & (1 << (index % 8))]
        return query, selected or [(-1, query.wire())], paths

    def accept(self, scope, raw):
        query, epoch, revision, data = parse_state(raw)
        key = DurableChunkAssembler.scope_key(scope), query.transfer
        with closing(self.connect()) as db:
            self.initialize(db)
            with db:
                db.execute("BEGIN IMMEDIATE")
                row = db.execute("SELECT manifest_hash,chunk_count,request_id,store_epoch,revision,stored_bitmap FROM mqtt_outgoing_chunks "
                                 "WHERE scope_digest=? AND transfer_id=? AND expires_at>?", (*key, self.clock())).fetchone()
                if not row or row[:3] != (query.manifest, query.count, query.request):
                    return False
                if row[3] and (row[3] != epoch or revision < row[4]):
                    return False
                if row[3] and revision == row[4]:
                    if bytes(row[5]) != data:
                        raise ValueError("Conflicting chunk state revision")
                    return False
                db.execute("UPDATE mqtt_outgoing_chunks SET store_epoch=?,revision=?,stored_bitmap=? WHERE scope_digest=? AND transfer_id=?", (epoch, revision, data, *key))
                return True

    def record_path(self, scope, query, index, broker):
        if index < 0:
            return
        _integer(index, 0, query.count - 1)
        bit = 1 << BROKERS.index(broker)
        with closing(self.connect()) as db:
            self.initialize(db)
            with db:
                db.execute("BEGIN IMMEDIATE")
                key = DurableChunkAssembler.scope_key(scope), query.transfer, query.request
                row = db.execute("SELECT path_bits FROM mqtt_outgoing_chunks WHERE scope_digest=? AND transfer_id=? AND request_id=?", key).fetchone()
                if row:
                    paths = bytearray(row[0]); paths[index] |= bit
                    db.execute("UPDATE mqtt_outgoing_chunks SET path_bits=? WHERE scope_digest=? AND transfer_id=? AND request_id=?", (bytes(paths), *key))

    @staticmethod
    def attempted(paths, index):
        return frozenset(broker for bit, broker in enumerate(BROKERS) if index >= 0 and paths[index] & (1 << bit))
