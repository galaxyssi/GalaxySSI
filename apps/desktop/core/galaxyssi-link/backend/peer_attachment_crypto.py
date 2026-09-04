"""Device-bound, authenticated streaming storage for Desktop peer attachments."""
from __future__ import annotations

import hashlib
import os
import struct
import uuid
from pathlib import Path
from typing import Iterator

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from secure_state import SecureStateError, derived_storage_key


MAGIC = b"SASI-PEER-ATTACHMENT\x01"
CHUNK_BYTES = 1024 * 1024
MAX_ATTACHMENT_BYTES = 1024 * 1024 * 1024
_HEADER = struct.Struct(">Q32sI8s")
_LENGTH = struct.Struct(">I")
_PURPOSE = "desktop.peer-attachment.v1"


class PeerAttachmentError(SecureStateError):
    """Raised when a peer attachment cannot be authenticated or recovered."""


class PeerAttachmentCipher:
    def __init__(self, key_anchor: Path) -> None:
        self._key = derived_storage_key(Path(key_anchor), _PURPOSE)

    def encrypt_file(
        self,
        source: Path,
        target: Path,
        *,
        expected_sha256: str = "",
    ) -> tuple[int, str]:
        source_path = Path(source).resolve()
        target_path = Path(target).resolve()
        if not source_path.is_file() or source_path.is_symlink():
            raise PeerAttachmentError("Peer attachment source is unavailable")
        size = source_path.stat().st_size
        if not 0 < size <= MAX_ATTACHMENT_BYTES:
            raise PeerAttachmentError("Peer attachment size is outside the supported range")
        digest = _file_sha256(source_path)
        expected = str(expected_sha256 or "").strip().lower()
        if expected and (len(expected) != 64 or expected != digest):
            raise PeerAttachmentError("Peer attachment SHA-256 does not match")

        nonce_prefix = os.urandom(8)
        header = MAGIC + _HEADER.pack(size, bytes.fromhex(digest), CHUNK_BYTES, nonce_prefix)
        target_path.parent.mkdir(parents=True, exist_ok=True)
        temporary = target_path.with_name(f".{target_path.name}.{uuid.uuid4().hex}.tmp")
        cipher = AESGCM(self._key)
        actual = hashlib.sha256()
        try:
            with source_path.open("rb") as reader, temporary.open("xb") as writer:
                writer.write(header)
                index = 0
                while True:
                    chunk = bytearray(reader.read(CHUNK_BYTES))
                    if not chunk:
                        break
                    actual.update(chunk)
                    nonce = nonce_prefix + struct.pack(">I", index)
                    aad = header + struct.pack(">II", index, len(chunk))
                    encrypted = cipher.encrypt(nonce, bytes(chunk), aad)
                    writer.write(_LENGTH.pack(len(chunk)))
                    writer.write(encrypted)
                    chunk[:] = b"\x00" * len(chunk)
                    index += 1
                writer.flush()
                os.fsync(writer.fileno())
            if actual.hexdigest() != digest:
                raise PeerAttachmentError("Peer attachment changed while it was encrypted")
            os.replace(temporary, target_path)
        finally:
            temporary.unlink(missing_ok=True)
        return size, digest

    def decrypt_stream(
        self,
        encrypted_path: Path,
        *,
        expected_size: int = 0,
        expected_sha256: str = "",
    ) -> Iterator[bytes]:
        path = Path(encrypted_path).resolve()
        if not path.is_file() or path.is_symlink():
            raise PeerAttachmentError("Encrypted peer attachment is unavailable")
        cipher = AESGCM(self._key)
        with path.open("rb") as reader:
            magic = reader.read(len(MAGIC))
            packed = reader.read(_HEADER.size)
            if magic != MAGIC or len(packed) != _HEADER.size:
                raise PeerAttachmentError("Peer attachment storage format is invalid")
            total_size, digest_bytes, chunk_bytes, nonce_prefix = _HEADER.unpack(packed)
            digest = digest_bytes.hex()
            header = magic + packed
            if not 0 < total_size <= MAX_ATTACHMENT_BYTES or chunk_bytes != CHUNK_BYTES:
                raise PeerAttachmentError("Peer attachment storage header is invalid")
            if expected_size and int(expected_size) != total_size:
                raise PeerAttachmentError("Peer attachment size metadata does not match")
            expected = str(expected_sha256 or "").strip().lower()
            if expected and expected != digest:
                raise PeerAttachmentError("Peer attachment SHA-256 metadata does not match")
            chunk_count = (total_size + chunk_bytes - 1) // chunk_bytes
            expected_file_size = len(header) + total_size + chunk_count * (_LENGTH.size + 16)
            if path.stat().st_size != expected_file_size:
                raise PeerAttachmentError("Encrypted peer attachment is incomplete")

            actual = hashlib.sha256()
            recovered = 0
            for index in range(chunk_count):
                packed_length = reader.read(_LENGTH.size)
                if len(packed_length) != _LENGTH.size:
                    raise PeerAttachmentError("Encrypted peer attachment is truncated")
                plain_length = _LENGTH.unpack(packed_length)[0]
                required = min(chunk_bytes, total_size - recovered)
                if plain_length != required:
                    raise PeerAttachmentError("Encrypted peer attachment chunk length is invalid")
                encrypted = reader.read(plain_length + 16)
                if len(encrypted) != plain_length + 16:
                    raise PeerAttachmentError("Encrypted peer attachment chunk is truncated")
                nonce = nonce_prefix + struct.pack(">I", index)
                aad = header + struct.pack(">II", index, plain_length)
                try:
                    plaintext = cipher.decrypt(nonce, encrypted, aad)
                except Exception as exc:
                    raise PeerAttachmentError("Peer attachment authentication failed") from exc
                actual.update(plaintext)
                recovered += len(plaintext)
                yield plaintext
            if recovered != total_size or actual.hexdigest() != digest or reader.read(1):
                raise PeerAttachmentError("Peer attachment integrity verification failed")

    @staticmethod
    def is_encrypted(path: Path) -> bool:
        candidate = Path(path)
        if not candidate.is_file() or candidate.is_symlink():
            return False
        try:
            with candidate.open("rb") as handle:
                return handle.read(len(MAGIC)) == MAGIC
        except OSError:
            return False


def _file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        while True:
            block = handle.read(CHUNK_BYTES)
            if not block:
                break
            digest.update(block)
    return digest.hexdigest()
