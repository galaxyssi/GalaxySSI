"""Device-bound encrypted persistence for security-sensitive Desktop state."""
from __future__ import annotations

import base64
import ctypes
import hashlib
import json
import os
import re
import secrets
import tempfile
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from cryptography.hazmat.primitives.ciphers.aead import AESGCM, AESSIV
from cryptography.hazmat.primitives.hashes import SHA256
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

PROTOCOL = "galaxyssi.secure-state/1.0"
CIPHER = "AES-256-GCM"
MASTER_KEY_ENV = "GALAXYSSI_STATE_MASTER_KEY"
MASTER_KEY_NAME = ".galaxyssi-state-key"
MAX_DOCUMENT_BYTES = 64 * 1024 * 1024
_PURPOSE_PATTERN = re.compile(r"^[a-z0-9][a-z0-9._-]{2,95}$")
_KEY_LOCK = threading.RLock()
_KEY_CACHE: dict[str, bytes] = {}
_DPAPI_PREFIX = b"dpapi:v1:"
_POSIX_PREFIX = b"local-user:v1:"
_DPAPI_ENTROPY = b"GalaxySSI Desktop secure state master key v1"
_TEXT_PREFIX = "enc:v1:"
_IDENTIFIER_PREFIX = "sid:v1:"


class SecureStateError(RuntimeError):
    """Raised when encrypted state cannot be authenticated or recovered."""


@dataclass(frozen=True)
class SecureJsonDocument:
    value: dict[str, Any]
    legacy_plaintext: bool = False


def derived_storage_key(path: Path, purpose: str) -> bytes:
    """Return a per-purpose key derived from the device-bound master key."""
    return _derive_storage_key(path, purpose, length=32)


def encrypt_text(path: Path, value: str, *, purpose: str) -> str:
    clean_purpose = _validate_purpose(purpose)
    nonce = os.urandom(12)
    ciphertext = AESGCM(derived_storage_key(path, clean_purpose)).encrypt(
        nonce,
        str(value).encode("utf-8"),
        _associated_data(f"{clean_purpose}.text"),
    )
    return f"{_TEXT_PREFIX}{_b64encode(nonce)}:{_b64encode(ciphertext)}"


def decrypt_text(path: Path, value: str, *, purpose: str) -> str:
    text = str(value or "")
    if not text.startswith(_TEXT_PREFIX):
        raise SecureStateError("Plaintext field was rejected")
    parts = text[len(_TEXT_PREFIX):].split(":", maxsplit=1)
    if len(parts) != 2:
        raise SecureStateError("Encrypted field is malformed")
    clean_purpose = _validate_purpose(purpose)
    try:
        plaintext = AESGCM(derived_storage_key(path, clean_purpose)).decrypt(
            _b64decode(parts[0]),
            _b64decode(parts[1]),
            _associated_data(f"{clean_purpose}.text"),
        )
        return plaintext.decode("utf-8")
    except Exception as exc:
        raise SecureStateError("Encrypted field authentication failed") from exc


def seal_identifier(path: Path, value: str, *, purpose: str) -> str:
    """Deterministically protect an identifier that remains queryable at rest."""
    clean_purpose = _validate_purpose(purpose)
    key = _derive_storage_key(path, f"{clean_purpose}.identifier", length=64)
    ciphertext = AESSIV(key).encrypt(
        str(value).encode("utf-8"),
        [_associated_data(f"{clean_purpose}.identifier")],
    )
    return _IDENTIFIER_PREFIX + _b64encode(ciphertext)


def unseal_identifier(path: Path, value: str, *, purpose: str) -> str:
    text = str(value or "")
    if not text.startswith(_IDENTIFIER_PREFIX):
        raise SecureStateError("Plaintext identifier was rejected")
    clean_purpose = _validate_purpose(purpose)
    key = _derive_storage_key(path, f"{clean_purpose}.identifier", length=64)
    try:
        plaintext = AESSIV(key).decrypt(
            _b64decode(text[len(_IDENTIFIER_PREFIX):]),
            [_associated_data(f"{clean_purpose}.identifier")],
        )
        return plaintext.decode("utf-8")
    except Exception as exc:
        raise SecureStateError("Encrypted identifier authentication failed") from exc


def _derive_storage_key(path: Path, purpose: str, *, length: int) -> bytes:
    clean_purpose = _validate_purpose(purpose)
    master = _master_key(Path(path).expanduser().resolve().parent)
    return HKDF(
        algorithm=SHA256(),
        length=length,
        salt=b"GalaxySSI secure state HKDF v1",
        info=clean_purpose.encode("ascii"),
    ).derive(master)


def read_secure_json(
    path: Path,
    *,
    purpose: str,
    allow_legacy_plaintext: bool = False,
) -> SecureJsonDocument:
    target = Path(path)
    raw = target.read_bytes()
    if len(raw) > MAX_DOCUMENT_BYTES:
        raise SecureStateError("Encrypted state exceeds its safe size limit")
    try:
        envelope = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SecureStateError("Encrypted state is not valid JSON") from exc
    if not isinstance(envelope, dict):
        raise SecureStateError("Encrypted state root must be an object")
    if envelope.get("protocol") != PROTOCOL:
        if allow_legacy_plaintext:
            return SecureJsonDocument(dict(envelope), legacy_plaintext=True)
        raise SecureStateError("Plaintext or unsupported state was rejected")

    clean_purpose = _validate_purpose(purpose)
    if envelope.get("purpose") != clean_purpose or envelope.get("cipher") != CIPHER:
        raise SecureStateError("Encrypted state policy does not match this store")
    try:
        nonce = _b64decode(str(envelope["nonce"]))
        ciphertext = _b64decode(str(envelope["ciphertext"]))
    except (KeyError, ValueError, TypeError) as exc:
        raise SecureStateError("Encrypted state envelope is incomplete") from exc
    if len(nonce) != 12 or len(ciphertext) < 16:
        raise SecureStateError("Encrypted state envelope is malformed")

    key = derived_storage_key(target, clean_purpose)
    expected_key_id = hashlib.sha256(key).hexdigest()[:24]
    if not secrets.compare_digest(str(envelope.get("key_id") or ""), expected_key_id):
        raise SecureStateError("Encrypted state belongs to another device key")
    try:
        plaintext = AESGCM(key).decrypt(
            nonce,
            ciphertext,
            _associated_data(clean_purpose),
        )
        value = json.loads(plaintext.decode("utf-8"))
    except Exception as exc:
        raise SecureStateError("Encrypted state authentication failed") from exc
    if not isinstance(value, dict):
        raise SecureStateError("Decrypted state root must be an object")
    return SecureJsonDocument(value)


def write_secure_json(path: Path, value: dict[str, Any], *, purpose: str) -> None:
    target = Path(path)
    clean_purpose = _validate_purpose(purpose)
    plaintext = json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")
    if len(plaintext) > MAX_DOCUMENT_BYTES:
        raise SecureStateError("State exceeds its safe size limit")
    key = derived_storage_key(target, clean_purpose)
    nonce = os.urandom(12)
    ciphertext = AESGCM(key).encrypt(
        nonce,
        plaintext,
        _associated_data(clean_purpose),
    )
    envelope = {
        "protocol": PROTOCOL,
        "cipher": CIPHER,
        "purpose": clean_purpose,
        "key_id": hashlib.sha256(key).hexdigest()[:24],
        "nonce": _b64encode(nonce),
        "ciphertext": _b64encode(ciphertext),
    }
    encoded = (
        json.dumps(envelope, ensure_ascii=True, separators=(",", ":")) + "\n"
    ).encode("ascii")
    _atomic_write(target, encoded)


def clear_cached_keys() -> None:
    """Clear process-local key material. Intended for reset and tests."""
    with _KEY_LOCK:
        _KEY_CACHE.clear()


def _master_key(directory: Path) -> bytes:
    configured = str(os.environ.get(MASTER_KEY_ENV) or "").strip()
    if configured:
        key = _b64decode(configured)
        if len(key) != 32:
            raise SecureStateError(f"{MASTER_KEY_ENV} must encode exactly 32 bytes")
        return key

    directory.mkdir(parents=True, exist_ok=True)
    key_path = directory / MASTER_KEY_NAME
    cache_key = os.path.normcase(str(key_path.resolve()))
    with _KEY_LOCK:
        cached = _KEY_CACHE.get(cache_key)
        if cached is not None:
            return cached
        candidates = (key_path, key_path.with_suffix(".bak"))
        failures: list[Exception] = []
        for candidate in candidates:
            if not candidate.exists():
                continue
            try:
                key = _decode_master_key(candidate.read_bytes())
                if len(key) != 32:
                    raise SecureStateError("Stored master key has an invalid length")
                _KEY_CACHE[cache_key] = key
                if candidate != key_path:
                    _write_master_key(key_path, key)
                return key
            except Exception as exc:
                failures.append(exc)
        if any(candidate.exists() for candidate in candidates):
            raise SecureStateError(
                "The device-bound state key is unreadable; protected state was not replaced"
            ) from (failures[-1] if failures else None)
        key = os.urandom(32)
        _write_master_key(key_path.with_suffix(".bak"), key)
        _write_master_key(key_path, key)
        _KEY_CACHE[cache_key] = key
        return key


def _write_master_key(path: Path, key: bytes) -> None:
    if os.name == "nt":
        payload = _DPAPI_PREFIX + base64.urlsafe_b64encode(_dpapi_protect(key))
    else:
        # Desktop-win uses DPAPI. The POSIX fallback relies on owner-only file
        # permissions until the macOS/Linux keychain integrations are shipped.
        payload = _POSIX_PREFIX + base64.urlsafe_b64encode(key)
    _atomic_write(path, payload + b"\n", mode=0o600)


def _decode_master_key(payload: bytes) -> bytes:
    raw = payload.strip()
    if raw.startswith(_DPAPI_PREFIX):
        if os.name != "nt":
            raise SecureStateError("A Windows-bound state key cannot be used here")
        try:
            protected = base64.urlsafe_b64decode(raw[len(_DPAPI_PREFIX):])
        except ValueError as exc:
            raise SecureStateError("Device-bound state key is malformed") from exc
        return _dpapi_unprotect(protected)
    if raw.startswith(_POSIX_PREFIX) and os.name != "nt":
        try:
            return base64.urlsafe_b64decode(raw[len(_POSIX_PREFIX):])
        except ValueError as exc:
            raise SecureStateError("Local-user state key is malformed") from exc
    raise SecureStateError("Unsupported device-bound state key")


def _dpapi_protect(value: bytes) -> bytes:
    return _dpapi_call("CryptProtectData", value)


def _dpapi_unprotect(value: bytes) -> bytes:
    return _dpapi_call("CryptUnprotectData", value)


def _dpapi_call(function_name: str, value: bytes) -> bytes:
    if os.name != "nt":
        raise SecureStateError("Windows DPAPI is unavailable")
    from ctypes import wintypes

    class DataBlob(ctypes.Structure):
        _fields_ = [
            ("cbData", wintypes.DWORD),
            ("pbData", ctypes.POINTER(ctypes.c_ubyte)),
        ]

    def blob(data: bytes) -> tuple[DataBlob, ctypes.Array]:
        buffer = ctypes.create_string_buffer(data)
        return (
            DataBlob(
                len(data),
                ctypes.cast(buffer, ctypes.POINTER(ctypes.c_ubyte)),
            ),
            buffer,
        )

    input_blob, input_buffer = blob(value)
    entropy_blob, entropy_buffer = blob(_DPAPI_ENTROPY)
    output_blob = DataBlob()
    crypt32 = ctypes.windll.crypt32
    function = getattr(crypt32, function_name)
    function.argtypes = [
        ctypes.POINTER(DataBlob),
        ctypes.c_wchar_p,
        ctypes.POINTER(DataBlob),
        ctypes.c_void_p,
        ctypes.c_void_p,
        wintypes.DWORD,
        ctypes.POINTER(DataBlob),
    ]
    function.restype = wintypes.BOOL
    description = "GalaxySSI secure state" if function_name == "CryptProtectData" else None
    result = function(
        ctypes.byref(input_blob),
        description,
        ctypes.byref(entropy_blob),
        None,
        None,
        0x1,
        ctypes.byref(output_blob),
    )
    del input_buffer, entropy_buffer
    if not result:
        raise SecureStateError("Windows DPAPI operation failed") from ctypes.WinError()
    try:
        return ctypes.string_at(output_blob.pbData, output_blob.cbData)
    finally:
        ctypes.windll.kernel32.LocalFree(output_blob.pbData)


def _atomic_write(path: Path, payload: bytes, *, mode: int | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        dir=path.parent,
        prefix=f".{path.name}.",
        suffix=".tmp",
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        if mode is not None and os.name != "nt":
            os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def _associated_data(purpose: str) -> bytes:
    return f"{PROTOCOL}|{purpose}".encode("ascii")


def _validate_purpose(value: str) -> str:
    clean = str(value or "").strip().lower()
    if not _PURPOSE_PATTERN.fullmatch(clean):
        raise ValueError("Secure state purpose is invalid")
    return clean


def _b64encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).decode("ascii").rstrip("=")


def _b64decode(value: str) -> bytes:
    text = str(value or "")
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))
