"""Authenticated attempt metadata around immutable Signal ciphertext.

Use only inside Link's existing authenticated outer envelope. This module does
not authenticate a packet or authorize a route. A receipt may be constructed
only from a committed inbox record, never from a successful MQTT publication.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import re

from mqtt_broker_catalog import BROKER_IDS

FIELD = "_mqtt_delivery"
VERSION = 1
ALGORITHM = "signal-wire-sha256-v1"
RECEIPT_TYPE = "link_rx_stored"
MAX_WIRE_BODY = 4 * 1024 * 1024
MAX_SAFE_INTEGER = 9_007_199_254_740_991
HASH = re.compile(r"[a-f0-9]{64}")
TOKEN = re.compile(r"[a-f0-9]{32}")
TRAFFIC = frozenset({"control", "message", "final", "progress", "chunk", "receipt"})
TEXT_FIELDS = ("scheme", "from", "to", "signal_type", "type", "body", "protocol")
NUMBER_FIELDS = ("message_type", "messageType", "device_id", "version")


def _string(value, *, maximum=256):
    if (not isinstance(value, str) or not value or len(value.encode("utf-8")) > maximum
            or any(ord(char) < 32 or ord(char) == 127 for char in value)):
        raise ValueError("Invalid delivery string")
    return value


def _hash(value):
    if not isinstance(value, str) or not HASH.fullmatch(value):
        raise ValueError("Invalid delivery digest")
    return value


def _integer(value):
    if type(value) is not int or not 0 < value <= MAX_SAFE_INTEGER:
        raise ValueError("Invalid delivery integer")
    return value


def content_hash(wire: dict) -> str:
    """Cross-runtime digest of Signal fields, not reserialized application JSON.

    Domain-separated UTF-8 length prefixes avoid language-dependent JSON key
    order, floating-point formatting, and UTF-16 character-count differences.
    Mutable wall-clock/transport fields are intentionally excluded. A changed
    Signal ciphertext (including a session repair) gets a different digest.
    """
    if not isinstance(wire, dict) or wire.get("scheme") != "signal":
        raise ValueError("A Signal wire envelope is required")
    for key in ("from", "to", "body"):
        _string(wire.get(key), maximum=MAX_WIRE_BODY if key == "body" else 512)
    digest = hashlib.sha256(b"GalaxySSI/SignalWireReceipt/v1\0")
    for key in (*TEXT_FIELDS, *NUMBER_FIELDS):
        if key not in wire:
            continue
        value = wire[key]
        if key in TEXT_FIELDS:
            encoded = _string(value, maximum=MAX_WIRE_BODY if key == "body" else 512).encode("utf-8")
            kind = b"s"
        else:
            encoded = str(_integer(value)).encode("ascii")
            kind = b"i"
        digest.update(f"{len(key)}:{key}".encode("ascii") + kind + str(len(encoded)).encode("ascii") + b":" + encoded)
    return digest.hexdigest()


@dataclass(frozen=True)
class Message:
    message_id: str
    content_hash: str
    sender: str
    receiver: str
    traffic: str

    def __post_init__(self):
        _string(self.message_id)
        _hash(self.content_hash)
        _hash(self.sender)
        _hash(self.receiver)
        if self.sender == self.receiver or not isinstance(self.traffic, str) or self.traffic not in TRAFFIC:
            raise ValueError("Invalid delivery message identity")


@dataclass(frozen=True)
class Attempt:
    attempt_id: str
    broker_id: str
    generation: int

    def __post_init__(self):
        if not isinstance(self.attempt_id, str) or not TOKEN.fullmatch(self.attempt_id):
            raise ValueError("Invalid delivery attempt")
        if not isinstance(self.broker_id, str) or self.broker_id not in BROKER_IDS:
            raise ValueError("Unknown delivery broker")
        _integer(self.generation)


@dataclass(frozen=True)
class Frame:
    message: Message
    attempt: Attempt

    def metadata(self):
        return {"version": VERSION, "content_hash_algorithm": ALGORITHM,
                "message_id": self.message.message_id, "content_hash": self.message.content_hash,
                "sender": self.message.sender, "receiver": self.message.receiver,
                "traffic": self.message.traffic, "attempt_id": self.attempt.attempt_id,
                "broker_id": self.attempt.broker_id, "generation": self.attempt.generation}

    def attach(self, wire):
        if FIELD in wire or content_hash(wire) != self.message.content_hash:
            raise ValueError("Attempt does not match immutable ciphertext")
        return {**wire, FIELD: self.metadata()}

    def receipt_after_store(self, *, stored_message_id, stored_content_hash):
        if (stored_message_id, stored_content_hash) != (self.message.message_id, self.message.content_hash):
            raise ValueError("Attempt is not bound to the committed inbox record")
        if self.message.traffic == "receipt":
            raise ValueError("Receipts cannot request further receipts")
        return {"type": RECEIPT_TYPE, "status": "RX_STORED", **self.metadata()}


def _parse_metadata(value):
    if not isinstance(value, dict) or type(value.get("version")) is not int or value["version"] != VERSION:
        raise ValueError("Invalid delivery metadata version")
    if value.get("content_hash_algorithm") != ALGORITHM:
        raise ValueError("Unsupported delivery digest algorithm")
    return Frame(Message(value.get("message_id"), value.get("content_hash"), value.get("sender"),
                         value.get("receiver"), value.get("traffic")),
                 Attempt(value.get("attempt_id"), value.get("broker_id"), value.get("generation")))


def parse_verified_frame(wire, *, sender, receiver, ingress_broker):
    """Call after pair AEAD authentication; no dedup writes occur on failure."""
    if not isinstance(wire, dict) or FIELD not in wire:
        raise ValueError("Missing delivery attempt")
    frame = _parse_metadata(wire[FIELD])
    if (frame.message.sender, frame.message.receiver, frame.attempt.broker_id) != (sender, receiver, ingress_broker):
        raise ValueError("Delivery attempt belongs to another pair or path")
    if frame.message.content_hash != content_hash(wire):
        raise ValueError("Delivery ciphertext digest mismatch")
    return frame


def parse_verified_receipt(payload, *, original_sender, original_receiver):
    """Call after authenticating the receipt sender as original_receiver.

    Sender generation describes the original publication, not the ACK ingress
    generation. An ACK is allowed to return over another authenticated path.
    The dispatcher must still match a locally reserved attempt before acting.
    """
    if not isinstance(payload, dict) or payload.get("type") != RECEIPT_TYPE or payload.get("status") != "RX_STORED":
        raise ValueError("Not a durable receive receipt")
    frame = _parse_metadata(payload)
    if (frame.message.sender, frame.message.receiver) != (original_sender, original_receiver):
        raise ValueError("Receipt belongs to another pair")
    if frame.message.traffic == "receipt":
        raise ValueError("Receipt loops are forbidden")
    return frame


def receipt_binding(scope, sender, receiver, secret):
    digest = hashlib.sha256(b"GalaxySSI/OutboundReceiptBinding/v1\0")
    for value in (scope, sender, receiver, secret):
        encoded = _string(value, maximum=512).encode("utf-8")
        digest.update(str(len(encoded)).encode("ascii") + b":" + encoded)
    return digest.hexdigest()


def stored_receipt(message_id, wire_hash):
    return {"type": "delivery_ack", "delivery_status": "RX_STORED",
            "transport_message_id": _string(message_id), "content_hash": _hash(wire_hash),
            "content_hash_algorithm": ALGORITHM}


def parse_stored_receipt(payload):
    if (not isinstance(payload, dict) or payload.get("type") != "delivery_ack"
            or payload.get("delivery_status") != "RX_STORED" or payload.get("content_hash_algorithm") != ALGORITHM):
        raise ValueError("Unverified durable receipt semantics")
    return _string(payload.get("transport_message_id")), _hash(payload.get("content_hash"))
