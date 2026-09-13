"""Retire delivered large bodies, retaining authenticated, non-executable proofs."""
from contextlib import closing
import hashlib
import json

import link_delivery as delivery

MIN_BODY_BYTES = 64 * 1024
MAX_PROOF_BYTES = 8192
HEADERS = ("protocol", "version", "message_id", "source_id", "target_id", "conversation_id", "sent_at", "expires_at")
ACK_FIELDS = ("type", "source_message_id", "contact_id")


class CompletedReceiveReplay(Exception):
    """Internal cache result, never a marker accepted from a wire payload."""
    def __init__(self, envelope):
        super().__init__("Authenticated receive already completed")
        self.envelope = envelope


def ensure_schema(db):
    db.execute("""CREATE TABLE IF NOT EXISTS inbound_signal_completed (
        client_route_id TEXT NOT NULL, message_id TEXT NOT NULL,
        proof TEXT NOT NULL, byte_count INTEGER NOT NULL,
        PRIMARY KEY(client_route_id,message_id))""")


def _purpose(route, mid):
    return "recv-done-" + hashlib.sha256((route + "\0" + mid).encode("utf-8")).hexdigest()


def completed_in_transaction(db, route, mid):
    row = db.execute("SELECT proof FROM inbound_signal_completed WHERE client_route_id=? AND message_id=?",
                     (route, mid)).fetchone()
    if row is None:
        return None
    proof = json.loads(delivery._reveal(row[0], _purpose(route, mid)))
    state = db.execute("""SELECT m.dispatch_state,h.content_hash FROM inbound_messages m
                          JOIN inbound_content_hashes h USING(client_route_id,message_id)
                          WHERE m.client_route_id=? AND m.message_id=?""", (route, mid)).fetchone()
    if (state != ("dispatched", proof.get("content_hash")) or
            proof.get("envelope", {}).get("message_id") != mid):
        raise RuntimeError("Completed receive proof binding mismatch")
    return proof


def completed_envelope(route_id, mid):
    with delivery._lock, closing(delivery._connect()) as db:
        proof = completed_in_transaction(db, delivery._route(route_id), mid)
        return proof["envelope"] if proof else None


def compact_in_transaction(db, route, mid):
    from signal_receive_handoff import _body, _adjust, MAX_TOTAL_BYTES, MAX_TOTAL_RECORDS, MAX_PEER_BYTES, MAX_PEER_RECORDS
    row = db.execute("""SELECT b.byte_count,b.content_hash FROM inbound_signal_bodies b
                        JOIN inbound_messages m USING(client_route_id,message_id)
                        WHERE b.client_route_id=? AND b.message_id=? AND m.dispatch_state='dispatched'
                          AND b.byte_count>=?
                          AND EXISTS (SELECT 1 FROM inbound_signal_handoffs h WHERE h.client_route_id=b.client_route_id
                                      AND h.message_id=b.message_id)
                          AND NOT EXISTS (SELECT 1 FROM inbound_signal_handoffs h WHERE h.client_route_id=b.client_route_id
                                          AND h.message_id=b.message_id AND h.released=0)
                          AND EXISTS (SELECT 1 FROM inbound_ciphertexts c WHERE c.client_route_id=b.client_route_id
                                      AND c.message_id=b.message_id AND c.receipt_hash<>'')""",
                     (route, mid, MIN_BODY_BYTES)).fetchone()
    if row is None:
        return False
    envelope = json.loads(_body(db, route, mid))
    summary = {key: envelope[key] for key in HEADERS if key in envelope}
    summary["payload"] = {key: envelope["payload"][key] for key in ACK_FIELDS if key in envelope["payload"]}
    proof = json.dumps({"content_hash": row[1], "envelope": summary}, ensure_ascii=False, separators=(",", ":"))
    if len(proof.encode("utf-8")) > MAX_PROOF_BYTES:
        return False
    protected = delivery._protect(proof, _purpose(route, mid))
    size = len(protected.encode("utf-8")) + 512
    if size >= row[0]:
        return False
    db.execute("INSERT INTO inbound_signal_completed VALUES(?,?,?,?)", (route, mid, protected, size))
    db.execute("DELETE FROM inbound_signal_bodies WHERE client_route_id=? AND message_id=?", (route, mid))
    _adjust(db, "total", size - row[0], 0, MAX_TOTAL_BYTES, MAX_TOTAL_RECORDS)
    _adjust(db, route, size - row[0], 0, MAX_PEER_BYTES, MAX_PEER_RECORDS)
    return True


def compact_backlog(db, route, limit=16):
    # Only completed large bodies are candidates; unfinished recovery bodies and
    # the permanent ID/content/cipher bindings never become quota eviction victims.
    rows = db.execute(f"""SELECT b.message_id FROM inbound_signal_bodies b
                         JOIN inbound_messages m USING(client_route_id,message_id)
                         WHERE b.client_route_id=? AND m.dispatch_state='dispatched' AND b.byte_count>={MIN_BODY_BYTES}
                         ORDER BY b.created_at LIMIT ?""", (route, limit)).fetchall()
    for (mid,) in rows:
        compact_in_transaction(db, route, mid)
