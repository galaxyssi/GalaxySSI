"""Authenticated multipath capability validation and durable per-pair route epochs.

The caller must first open the existing relationship AEAD and authenticate the
peer. This module never authorizes a new peer, decrypts Signal, or creates a
second business-delivery ledger; it uses Link's existing metadata transaction.
"""
from __future__ import annotations

import hashlib
import json
import re
import secrets
from dataclasses import dataclass
from enum import Enum

import link_delivery
from mqtt_broker_catalog import BROKER_IDS, CATALOG

FINGERPRINT = re.compile(r"[a-f0-9]{64}")
RESUME_ID = re.compile(r"[a-f0-9]{32}")
MAX_EPOCH = 9_007_199_254_740_991
TTL_MS = CATALOG["timing"]["resume_ttl_seconds"] * 1000
MAX_CLOCK_SKEW_MS = 300_000


@dataclass(frozen=True)
class RouteAdvertisement:
    sender: str
    receiver: str
    epoch: int
    resume_id: str
    issued_at_ms: int
    expires_at_ms: int
    receive_brokers: frozenset[str]
    packet_bytes: int

    def to_wire(self) -> dict:
        return {
            "type": "link_resume", "transport_version": CATALOG["transport_version"],
            "sender_fingerprint": self.sender, "receiver_fingerprint": self.receiver,
            "route_epoch": self.epoch, "resume_id": self.resume_id,
            "issued_at_ms": self.issued_at_ms, "expires_at_ms": self.expires_at_ms,
            "supported_brokers": sorted(BROKER_IDS), "receive_brokers": sorted(self.receive_brokers),
            "max_encoded_packet_bytes": self.packet_bytes, "multipath": True, "chunk_acks": True,
        }

    def digest(self) -> str:
        return hashlib.sha256(json.dumps(self.to_wire(), sort_keys=True, separators=(",", ":")).encode()).hexdigest()


class ResumeResult(Enum):
    NEW = "new"
    DUPLICATE = "duplicate"
    STALE = "stale"
    CONFLICT = "conflict"


def parse_verified_resume(payload: dict, *, sender: str, receiver: str, now_ms: int) -> RouteAdvertisement:
    if (not isinstance(payload, dict) or payload.get("type") != "link_resume"
            or type(payload.get("transport_version")) is not int
            or payload["transport_version"] != CATALOG["transport_version"]
            or payload.get("multipath") is not True or payload.get("chunk_acks") is not True):
        raise ValueError("unsupported multipath capabilities")
    if (not FINGERPRINT.fullmatch(sender) or not FINGERPRINT.fullmatch(receiver) or sender == receiver
            or payload.get("sender_fingerprint") != sender or payload.get("receiver_fingerprint") != receiver):
        raise ValueError("resume identity binding mismatch")
    fields = ("route_epoch", "issued_at_ms", "expires_at_ms", "max_encoded_packet_bytes")
    if any(type(payload.get(key)) is not int for key in fields):
        raise ValueError("resume counters must be integers")
    epoch, issued, expires, packet_bytes = (payload[key] for key in fields)
    if (not 0 < epoch <= MAX_EPOCH or not 0 <= issued <= MAX_EPOCH or not 0 < expires <= MAX_EPOCH
            or issued > now_ms + MAX_CLOCK_SKEW_MS
            or not 0 < expires - issued <= TTL_MS or expires <= now_ms
            or not 0 < packet_bytes <= CATALOG["limits"]["encoded_packet_bytes"]):
        raise ValueError("invalid or expired resume")
    resume_id = payload.get("resume_id")
    if not isinstance(resume_id, str) or not RESUME_ID.fullmatch(resume_id):
        raise ValueError("invalid resume identifier")
    supported, active = payload.get("supported_brokers"), payload.get("receive_brokers")
    if (not isinstance(supported, list) or not isinstance(active, list)
            or any(not isinstance(value, str) for value in supported + active)
            or len(supported) != 3 or frozenset(supported) != BROKER_IDS
            or len(active) > 3 or len(set(active)) != len(active) or not set(active) <= BROKER_IDS):
        raise ValueError("invalid broker receive collection")
    return RouteAdvertisement(sender, receiver, epoch, resume_id, issued, expires, frozenset(active), packet_bytes)


def _metadata_key(peer: str, direction: str) -> str:
    if not peer or len(peer) > 512:
        raise ValueError("bounded authenticated peer scope is required")
    return f"multipath:{direction}:{link_delivery._route(peer)}"


def issue_local_resume(peer: str, *, sender: str, receiver: str, receive_brokers: frozenset[str],
                       now_ms: int, packet_bytes: int = CATALOG["limits"]["encoded_packet_bytes"]) -> RouteAdvertisement:
    key = _metadata_key(peer, "local")
    with link_delivery._lock:
        db = link_delivery._connect()
        try:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT value FROM delivery_metadata WHERE key=?", (key,)).fetchone()
            epoch = int(row[0]) + 1 if row else 1
            advertisement = RouteAdvertisement(sender, receiver, epoch, secrets.token_hex(16), now_ms,
                                                 now_ms + TTL_MS, receive_brokers, packet_bytes)
            parse_verified_resume(advertisement.to_wire(), sender=sender, receiver=receiver, now_ms=now_ms)
            db.execute("INSERT INTO delivery_metadata(key,value) VALUES(?,?) "
                       "ON CONFLICT(key) DO UPDATE SET value=excluded.value", (key, str(epoch)))
            db.commit()
            return advertisement
        finally:
            db.close()


def record_verified_resume(peer: str, advertisement: RouteAdvertisement, *, now_ms: int) -> ResumeResult:
    parse_verified_resume(advertisement.to_wire(), sender=advertisement.sender,
                          receiver=advertisement.receiver, now_ms=now_ms)
    key = _metadata_key(peer, "remote")
    digest = advertisement.digest()
    with link_delivery._lock:
        db = link_delivery._connect()
        try:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT value FROM delivery_metadata WHERE key=?", (key,)).fetchone()
            if row:
                previous = json.loads(link_delivery._reveal(row[0], "multipath-route"))
                if advertisement.epoch < previous["route_epoch"]:
                    return ResumeResult.STALE
                if advertisement.epoch == previous["route_epoch"]:
                    return ResumeResult.DUPLICATE if secrets.compare_digest(previous["digest"], digest) else ResumeResult.CONFLICT
            value = link_delivery._protect(json.dumps({"route_epoch": advertisement.epoch,
                "digest": digest, "advertisement": advertisement.to_wire()}, separators=(",", ":")), "multipath-route")
            db.execute("INSERT INTO delivery_metadata(key,value) VALUES(?,?) "
                       "ON CONFLICT(key) DO UPDATE SET value=excluded.value", (key, value))
            db.commit()
            return ResumeResult.NEW
        finally:
            db.close()


def load_verified_resume(peer: str, *, sender: str, receiver: str, now_ms: int) -> RouteAdvertisement | None:
    key = _metadata_key(peer, "remote")
    with link_delivery._lock:
        db = link_delivery._connect()
        try:
            row = db.execute("SELECT value FROM delivery_metadata WHERE key=?", (key,)).fetchone()
        finally:
            db.close()
    if row is None:
        return None
    try:
        value = json.loads(link_delivery._reveal(row[0], "multipath-route"))
        return parse_verified_resume(value["advertisement"], sender=sender, receiver=receiver, now_ms=now_ms)
    except (ValueError, KeyError, TypeError):
        return None


def forget_route(peer: str) -> None:
    """Use only on revocation/re-pairing; network failure must preserve epoch watermarks."""
    keys = (_metadata_key(peer, "local"), _metadata_key(peer, "remote"))
    with link_delivery._lock:
        db = link_delivery._connect()
        try:
            db.executemany("DELETE FROM delivery_metadata WHERE key=?", ((key,) for key in keys))
            db.commit()
        finally:
            db.close()
