"""Pairing tokens and persisted SignalASI Link v1 client registry."""
from __future__ import annotations

import json
import logging
import os
import secrets
import tempfile
import threading
import time
from copy import deepcopy
from pathlib import Path

from link_protocol import LinkTopics, new_route_id, valid_route_id
from pairing_access import grant_for_executor, normalize_grant

TTL_SECONDS = 10 * 60
DEFAULT_DATA_DIR = (
    Path(os.environ["APPDATA"]) / "signalasi-desktop" / "runtime"
    if os.name == "nt" and os.environ.get("APPDATA")
    else Path.home() / ".signalasi"
)
DATA_DIR = Path(os.environ.get("SIGNALASI_DATA_DIR", DEFAULT_DATA_DIR))
STATE_PATH = DATA_DIR / "signalasi_link_registry.json"

_tokens: dict[str, dict] = {}
_registry_lock = threading.RLock()
_last_good_state: dict | None = None
_last_good_path = ""
logger = logging.getLogger(__name__)


class PairingRegistryError(RuntimeError):
    """Raised when an existing pairing registry cannot be recovered safely."""


def _empty_state() -> dict:
    return {
        "schema": 2,
        "server_route_id": new_route_id(),
        "clients": {},
        "updated_at": time.time(),
    }


def _backup_path() -> Path:
    return STATE_PATH.with_name(f"{STATE_PATH.name}.bak")


def _state_path_key() -> str:
    return str(STATE_PATH.resolve())


def _validated_state(data: object) -> dict:
    if not isinstance(data, dict):
        raise ValueError("registry root must be an object")
    if not valid_route_id(data.get("server_route_id")):
        raise ValueError("registry has an invalid server route")
    if not isinstance(data.get("clients"), dict):
        raise ValueError("registry clients must be an object")
    clean = deepcopy(data)
    clean.setdefault("schema", 2)
    clean.setdefault("updated_at", time.time())
    return clean


def _load_state(path: Path) -> dict:
    return _validated_state(json.loads(path.read_text(encoding="utf-8")))


def _remember_state(data: dict) -> dict:
    global _last_good_path, _last_good_state
    clean = _validated_state(data)
    _last_good_path = _state_path_key()
    _last_good_state = deepcopy(clean)
    return clean


def _cached_state() -> dict | None:
    if _last_good_path != _state_path_key() or _last_good_state is None:
        return None
    return deepcopy(_last_good_state)


def _atomic_write(path: Path, payload: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temp_name = tempfile.mkstemp(
        dir=path.parent,
        prefix=f".{path.name}.",
        suffix=".tmp",
        text=True,
    )
    temp_path = Path(temp_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_path, path)
    finally:
        temp_path.unlink(missing_ok=True)


def _write_state(data: dict) -> None:
    with _registry_lock:
        clean = _validated_state(data)
        payload = f"{json.dumps(clean, ensure_ascii=False, indent=2)}\n"
        # Write the recovery copy first. A crash between the two replacements
        # still leaves at least one complete registry with the newest state.
        _atomic_write(_backup_path(), payload)
        _atomic_write(STATE_PATH, payload)
        _remember_state(clean)


def _restore_state(reason: Exception | None = None) -> dict | None:
    try:
        recovered = _load_state(_backup_path())
        source = "backup"
    except Exception:
        recovered = _cached_state()
        source = "memory"
    if recovered is None:
        return None
    _write_state(recovered)
    logger.warning(
        "Recovered SignalASI Link pairing registry from %s after primary read failure: %s",
        source,
        reason or "registry missing",
    )
    return recovered


def _read_state() -> dict:
    with _registry_lock:
        if not STATE_PATH.exists():
            recovered = _restore_state()
            if recovered is not None:
                return recovered
            data = _empty_state()
            _write_state(data)
            return deepcopy(data)

        try:
            return _remember_state(_load_state(STATE_PATH))
        except Exception as error:
            recovered = _restore_state(error)
            if recovered is not None:
                return recovered
            logger.error(
                "SignalASI Link pairing registry is unreadable and no recovery copy is available: %s",
                error,
            )
            raise PairingRegistryError(
                "Pairing registry is unreadable; refusing to replace the existing identity"
            ) from error


def server_route_id() -> str:
    return str(_read_state()["server_route_id"])


def new_pairing_session(access_grant: dict | None = None) -> dict:
    with _registry_lock:
        now = time.time()
        for token, entry in list(_tokens.items()):
            if now - float(entry.get("created_at") or 0) > TTL_SECONDS:
                _tokens.pop(token, None)
        token = secrets.token_urlsafe(24)
        secret = secrets.token_urlsafe(32)
        grant = normalize_grant(access_grant or grant_for_executor(False))
        _tokens[token] = {"created_at": now, "secret": secret, "access": grant}
        return {
            "token": token,
            "secret": secret,
            "created_at": now,
            "expires_at": now + TTL_SECONDS,
            "access": grant,
        }


def new_pairing_token() -> str:
    return str(new_pairing_session()["token"])


def pairing_secret(token: str) -> str:
    with _registry_lock:
        entry = _tokens.get(str(token or "")) or {}
        if time.time() - float(entry.get("created_at") or 0) > TTL_SECONDS:
            return ""
        return str(entry.get("secret") or "")


def validate_pairing_token(token: str, consume: bool = False) -> bool:
    return consume_pairing_session(token) is not None if consume else pairing_session(token) is not None


def pairing_session(token: str) -> dict | None:
    with _registry_lock:
        entry = _tokens.get(str(token or ""))
        created_at = float((entry or {}).get("created_at") or 0)
        if not entry or time.time() - created_at > TTL_SECONDS:
            _tokens.pop(str(token or ""), None)
            return None
        return {
            **entry,
            "access": normalize_grant(entry.get("access")),
        }


def consume_pairing_session(token: str) -> dict | None:
    with _registry_lock:
        entry = pairing_session(token)
        if entry is None:
            return None
        _tokens.pop(str(token), None)
        return entry


def token_status() -> dict:
    with _registry_lock:
        now = time.time()
        active = [
            float(entry.get("created_at") or 0)
            for entry in _tokens.values()
            if now - float(entry.get("created_at") or 0) <= TTL_SECONDS
        ]
        newest = max(active, default=0.0)
        return {
            "active": bool(active),
            "active_count": len(active),
            "created_at": newest,
            "expires_at": newest + TTL_SECONDS if newest else 0,
            "expires_in": max(0, int(newest + TTL_SECONDS - now)) if newest else 0,
        }


def record_pairing_success(
    fingerprint: str,
    remote_name: str = "",
    remote_device_id: int = 1,
    *,
    client_route_id: str = "",
    display_name: str = "SignalASI Client",
    platform: str = "unknown",
    access_grant: dict | None = None,
) -> dict:
    if not fingerprint:
        raise ValueError("identity fingerprint required")
    route_id = client_route_id or new_route_id()
    if not valid_route_id(route_id):
        raise ValueError("invalid client route id")
    with _registry_lock:
        state = _read_state()
        previous = state["clients"].get(route_id, {})
        now = time.time()
        access = normalize_grant(access_grant or grant_for_executor(False))
        client = {
            "client_route_id": route_id,
            "signal_name": remote_name or previous.get("signal_name") or f"client_{route_id}",
            "signal_device_id": int(remote_device_id or 1),
            "identity_fingerprint": fingerprint,
            "display_name": display_name or previous.get("display_name") or "SignalASI Client",
            "platform": platform or previous.get("platform") or "unknown",
            "access_profile": access["profile"],
            "access_scopes": list(access["scopes"]),
            "access_granted_at": int(access["issued_at"]),
            "paired_at": float(previous.get("paired_at") or now),
            "updated_at": now,
            "last_seen_at": now,
            "revoked": False,
        }
        state["clients"][route_id] = client
        state["updated_at"] = now
        _write_state(state)
        return client_status(client, state["server_route_id"])


def client_status(client: dict, server_id: str | None = None) -> dict:
    route_id = str(client.get("client_route_id") or "")
    sid = server_id or server_route_id()
    topics = LinkTopics(sid, route_id)
    return {
        **client,
        "access": normalize_grant({
            "profile": client.get("access_profile"),
            "scopes": client.get("access_scopes"),
            "desktop_executor": client.get("access_profile") == "desktop_executor",
            "issued_at": client.get("access_granted_at"),
        }),
        "paired": not bool(client.get("revoked")),
        "identity_fingerprint_short": str(client.get("identity_fingerprint") or "")[:16],
        "topics": {"up": topics.up, "down": topics.down, "control": topics.control},
    }


def get_client(client_route_id: str, include_revoked: bool = False) -> dict | None:
    state = _read_state()
    client = state["clients"].get(client_route_id)
    if not isinstance(client, dict) or (client.get("revoked") and not include_revoked):
        return None
    return client_status(client, state["server_route_id"])


def list_clients(include_revoked: bool = False) -> list[dict]:
    state = _read_state()
    values = []
    for client in state["clients"].values():
        if not isinstance(client, dict) or (client.get("revoked") and not include_revoked):
            continue
        values.append(client_status(client, state["server_route_id"]))
    return sorted(values, key=lambda item: float(item.get("paired_at") or 0))


def clients_for_identity(
    fingerprint: str,
    remote_name: str,
    *,
    exclude_route_id: str = "",
) -> list[dict]:
    """Return active routes owned by the same cryptographic client identity."""
    clean_fingerprint = str(fingerprint or "").lower()
    clean_name = str(remote_name or "")
    return [
        client
        for client in list_clients()
        if client["client_route_id"] != exclude_route_id
        and (
            str(client.get("identity_fingerprint") or "").lower() == clean_fingerprint
            or str(client.get("signal_name") or "") == clean_name
        )
    ]


def touch_client(client_route_id: str) -> None:
    with _registry_lock:
        state = _read_state()
        client = state["clients"].get(client_route_id)
        if not isinstance(client, dict) or client.get("revoked"):
            return
        client["last_seen_at"] = time.time()
        client["updated_at"] = client["last_seen_at"]
        state["updated_at"] = client["updated_at"]
        _write_state(state)


def revoke_client(client_route_id: str, reason: str = "forgotten_by_desktop") -> dict | None:
    with _registry_lock:
        state = _read_state()
        client = state["clients"].get(client_route_id)
        if not isinstance(client, dict):
            return None
        client["revoked"] = True
        client["revoked_at"] = time.time()
        client["revoke_reason"] = reason
        client["updated_at"] = client["revoked_at"]
        state["updated_at"] = client["updated_at"]
        _write_state(state)
        return client_status(client, state["server_route_id"])


def clear_pairing_state(client_route_id: str = "") -> dict:
    state = _read_state()
    if client_route_id:
        revoke_client(client_route_id)
    else:
        for route_id in list(state["clients"]):
            revoke_client(route_id)
    return pairing_status()


def is_paired(client_route_id: str = "") -> bool:
    return bool(get_client(client_route_id)) if client_route_id else bool(list_clients())


def pairing_status() -> dict:
    clients = list_clients()
    return {
        "paired": bool(clients),
        "state": "paired" if clients else ("waiting_for_scan" if token_status()["active"] else "not_paired"),
        "server_route_id": server_route_id(),
        "pairing_topic": LinkTopics(server_route_id()).pairing,
        "client_count": len(clients),
        "clients": clients,
        "token": token_status(),
        # Transitional summary fields for the current Desktop renderer.
        "remote_name": clients[0].get("signal_name", "") if clients else "",
        "remote_device_id": clients[0].get("signal_device_id", 0) if clients else 0,
        "identity_fingerprint": clients[0].get("identity_fingerprint", "") if clients else "",
        "identity_fingerprint_short": clients[0].get("identity_fingerprint_short", "") if clients else "",
    }
