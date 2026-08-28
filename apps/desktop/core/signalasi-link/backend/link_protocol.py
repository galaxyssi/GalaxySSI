"""Opaque node-to-node routing and encrypted wire primitives."""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import re
import secrets
import struct
import time
import uuid
from dataclasses import dataclass
from typing import Any

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

PROTOCOL_NAME = "signalasi-link"
PROTOCOL_VERSION = 2
ROUTE_ID_BYTES = 16
LINK_SECRET_BYTES = 32
TOPIC_ID_BYTES = 32
TOPIC_EPOCH_SECONDS = 6 * 60 * 60
TOPIC_RECEIVE_WINDOW = 1
MAX_CLOCK_SKEW_MS = 5 * 60 * 1000
DEFAULT_MESSAGE_TTL_MS = 7 * 24 * 60 * 60 * 1000
MAX_ENVELOPE_BYTES = 512 * 1024
MAX_TEXT_BYTES = 128 * 1024
MAX_OPAQUE_PACKET_BYTES = 288 * 1024
ROUTE_ID_RE = re.compile(r"^[A-Za-z0-9_-]{22}$")
SECRET_RE = re.compile(r"^[A-Za-z0-9_-]{43}$")
TOPIC_RE = re.compile(r"^[A-Za-z0-9_-]{43}$")
_WIRE_BUCKETS = (1024, 4096, 16 * 1024, 40 * 1024, 48 * 1024, 192 * 1024)
_WIRE_VERSION = 2
_WIRE_HEADER = struct.Struct(">BI")


def _b64url_decode(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def _b64url_encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).decode("ascii").rstrip("=")


def _secret_bytes(value: str) -> bytes:
    if not valid_link_secret(value):
        raise ValueError("invalid link secret")
    return _b64url_decode(value)


def _kdf(secret: bytes, label: bytes) -> bytes:
    return hmac.new(secret, b"signalasi-opaque-v2\x00" + label, hashlib.sha256).digest()


def new_route_id() -> str:
    """Return an opaque internal 128-bit identifier; it is never used as a topic."""
    return secrets.token_urlsafe(ROUTE_ID_BYTES)


def valid_route_id(value: object) -> bool:
    return bool(ROUTE_ID_RE.fullmatch(str(value or "")))


def new_link_secret() -> str:
    return _b64url_encode(secrets.token_bytes(LINK_SECRET_BYTES))


def valid_link_secret(value: object) -> bool:
    return bool(SECRET_RE.fullmatch(str(value or "")))


def valid_topic(value: object) -> bool:
    return bool(TOPIC_RE.fullmatch(str(value or "")))


def pairing_topic(secret: str) -> str:
    return _b64url_encode(_kdf(_secret_bytes(secret), b"rendezvous-topic"))


def derive_link_secret(pairing_secret: str, first_fingerprint: str, second_fingerprint: str) -> str:
    fingerprints = sorted((str(first_fingerprint or ""), str(second_fingerprint or "")))
    if not fingerprints[0] or not fingerprints[1]:
        raise ValueError("both identity fingerprints are required")
    binding = "\x00".join(fingerprints).encode("utf-8")
    return _b64url_encode(_kdf(_secret_bytes(pairing_secret), b"relationship\x00" + binding))


def topic_epoch(at_seconds: float | None = None) -> int:
    return int(at_seconds if at_seconds is not None else time.time()) // TOPIC_EPOCH_SECONDS


def relationship_topic(
    link_secret: str,
    sender_fingerprint: str,
    receiver_fingerprint: str,
    *,
    epoch: int | None = None,
) -> str:
    sender = str(sender_fingerprint or "")
    receiver = str(receiver_fingerprint or "")
    if not sender or not receiver or sender == receiver:
        raise ValueError("distinct sender and receiver fingerprints are required")
    window = topic_epoch() if epoch is None else int(epoch)
    binding = b"mailbox\x00" + sender.encode("utf-8") + b"\x00" + receiver.encode("utf-8")
    binding += b"\x00" + str(window).encode("ascii")
    return _b64url_encode(_kdf(_secret_bytes(link_secret), binding))


@dataclass(frozen=True)
class LinkTopics:
    link_secret: str
    local_fingerprint: str
    remote_fingerprint: str
    epoch: int | None = None

    def __post_init__(self) -> None:
        _secret_bytes(self.link_secret)
        if not self.local_fingerprint or not self.remote_fingerprint:
            raise ValueError("identity fingerprints are required")
        if self.local_fingerprint == self.remote_fingerprint:
            raise ValueError("identity fingerprints must differ")

    @property
    def send(self) -> str:
        return relationship_topic(
            self.link_secret,
            self.local_fingerprint,
            self.remote_fingerprint,
            epoch=self.epoch,
        )

    @property
    def receive(self) -> str:
        return relationship_topic(
            self.link_secret,
            self.remote_fingerprint,
            self.local_fingerprint,
            epoch=self.epoch,
        )

    @property
    def receive_window(self) -> tuple[str, ...]:
        current = topic_epoch() if self.epoch is None else int(self.epoch)
        return tuple(
            relationship_topic(
                self.link_secret,
                self.remote_fingerprint,
                self.local_fingerprint,
                epoch=current + offset,
            )
            for offset in range(-TOPIC_RECEIVE_WINDOW, TOPIC_RECEIVE_WINDOW + 1)
        )


def _wire_plaintext(payload: bytes) -> bytes:
    required = _WIRE_HEADER.size + len(payload)
    bucket = next((candidate for candidate in _WIRE_BUCKETS if required <= candidate), None)
    if bucket is None:
        raise ValueError("wire payload exceeds opaque packet limit")
    padding = secrets.token_bytes(bucket - required)
    return _WIRE_HEADER.pack(_WIRE_VERSION, len(payload)) + payload + padding


def seal_wire_packet(payload: str | bytes, secret: str) -> str:
    raw = payload.encode("utf-8") if isinstance(payload, str) else bytes(payload)
    nonce = secrets.token_bytes(12)
    key = _kdf(_secret_bytes(secret), b"wire-aead")
    sealed = nonce + AESGCM(key).encrypt(nonce, _wire_plaintext(raw), None)
    encoded = _b64url_encode(sealed)
    if len(encoded.encode("ascii")) > MAX_OPAQUE_PACKET_BYTES:
        raise ValueError("opaque packet exceeds broker limit")
    return encoded


def open_wire_packet(wire: str | bytes, secret: str) -> bytes:
    encoded = wire.decode("ascii") if isinstance(wire, bytes) else str(wire or "")
    sealed = _b64url_decode(encoded)
    if len(sealed) < 12 + 16 + _WIRE_HEADER.size:
        raise ValueError("opaque packet is truncated")
    nonce, ciphertext = sealed[:12], sealed[12:]
    key = _kdf(_secret_bytes(secret), b"wire-aead")
    plaintext = AESGCM(key).decrypt(nonce, ciphertext, None)
    version, payload_size = _WIRE_HEADER.unpack_from(plaintext)
    if version != _WIRE_VERSION:
        raise ValueError("unsupported opaque packet version")
    payload_start = _WIRE_HEADER.size
    payload_end = payload_start + payload_size
    if payload_size < 0 or payload_end > len(plaintext):
        raise ValueError("invalid opaque packet length")
    return plaintext[payload_start:payload_end]


def encrypt_pairing_claim(claim: dict[str, Any], secret: str) -> str:
    raw = json.dumps(claim, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    return seal_wire_packet(raw, secret)


def decrypt_pairing_claim(wire: str | bytes, secret: str) -> dict[str, Any]:
    claim = json.loads(open_wire_packet(wire, secret).decode("utf-8"))
    if not isinstance(claim, dict):
        raise ValueError("pairing claim must be an object")
    return claim


def make_envelope(
    payload: dict[str, Any],
    *,
    source_id: str,
    target_id: str,
    conversation_id: str = "",
    reply_to: str = "",
) -> dict[str, Any]:
    now = int(time.time() * 1000)
    requested_message_id = str(payload.get("message_id") or "")
    try:
        message_id = str(uuid.UUID(requested_message_id))
    except ValueError:
        message_id = str(uuid.uuid4())
    envelope = {
        "protocol": PROTOCOL_NAME,
        "version": PROTOCOL_VERSION,
        "message_id": message_id,
        "conversation_id": str(conversation_id or payload.get("conversation_id") or ""),
        "source_id": source_id,
        "target_id": target_id,
        "reply_to": str(reply_to or payload.get("reply_to") or ""),
        "sent_at": now,
        "expires_at": now + DEFAULT_MESSAGE_TTL_MS,
        "payload": payload,
    }
    return validate_envelope(envelope, now_ms=now)


def validate_envelope(envelope: object, now_ms: int | None = None) -> dict[str, Any]:
    if not isinstance(envelope, dict):
        raise ValueError("envelope must be an object")
    if envelope.get("protocol") != PROTOCOL_NAME or envelope.get("version") != PROTOCOL_VERSION:
        raise ValueError("unsupported protocol")
    try:
        uuid.UUID(str(envelope.get("message_id") or ""))
    except ValueError as exc:
        raise ValueError("invalid message id") from exc
    if not str(envelope.get("source_id") or "") or not str(envelope.get("target_id") or ""):
        raise ValueError("source and target are required")
    if not isinstance(envelope.get("payload"), dict):
        raise ValueError("payload must be an object")
    if len(json.dumps(envelope, ensure_ascii=False, separators=(",", ":")).encode("utf-8")) > MAX_ENVELOPE_BYTES:
        raise ValueError("envelope exceeds size limit")
    content = envelope["payload"].get("content")
    if isinstance(content, str) and len(content.encode("utf-8")) > MAX_TEXT_BYTES:
        raise ValueError("text exceeds size limit")
    sent_at = int(envelope.get("sent_at") or 0)
    reference = int(now_ms if now_ms is not None else time.time() * 1000)
    expires_at = int(envelope.get("expires_at") or 0)
    if sent_at <= 0 or sent_at - reference > MAX_CLOCK_SKEW_MS:
        raise ValueError("message timestamp is in the future")
    if expires_at <= sent_at or reference > expires_at:
        raise ValueError("message expired")
    return envelope
