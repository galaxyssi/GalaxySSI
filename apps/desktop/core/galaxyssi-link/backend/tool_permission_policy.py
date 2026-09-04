"""Encrypted, action-bound tool permission decisions for paired clients."""
from __future__ import annotations

import re
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from secure_state import read_secure_json, write_secure_json

ALLOW_ONCE = "allow_once"
ALLOW_SESSION = "allow_session"
ALLOW_ALWAYS = "allow_always"
DENY_ALWAYS = "deny_always"
VALID_CHOICES = frozenset({
    ALLOW_ONCE,
    ALLOW_SESSION,
    ALLOW_ALWAYS,
    DENY_ALWAYS,
})

STATE_PATH = Path.home() / ".galaxyssi" / "tool_permission_policy.json"
STATE_PURPOSE = "tool-permission-policy"
STATE_VERSION = 1
MAX_ENTRIES = 2_000
_ACTION_HASH = re.compile(r"^[0-9a-f]{64}$")


@dataclass(frozen=True)
class ToolPermissionDecision:
    choice: str
    client_route_id: str
    contact_id: str
    conversation_id: str
    action_hash: str
    created_at_ms: int

    @property
    def approved(self) -> bool:
        return self.choice != DENY_ALWAYS


class ToolPermissionPolicy:
    def __init__(
        self,
        path: Path | None = None,
        *,
        clock: Callable[[], float] = time.time,
    ) -> None:
        self.path = Path(path or STATE_PATH)
        self.clock = clock
        self._lock = threading.RLock()

    def resolve(
        self,
        *,
        client_route_id: str,
        contact_id: str,
        conversation_id: str,
        action_hash: str,
    ) -> ToolPermissionDecision | None:
        identity = self._identity(
            client_route_id,
            contact_id,
            conversation_id,
            action_hash,
        )
        with self._lock:
            matches = [
                self._decode(entry)
                for entry in self._load()["entries"]
                if isinstance(entry, dict)
            ]
        candidates = [
            decision
            for decision in matches
            if decision is not None
            and decision.client_route_id == identity.client_route_id
            and decision.contact_id == identity.contact_id
            and decision.action_hash == identity.action_hash
            and (
                decision.choice in {ALLOW_ALWAYS, DENY_ALWAYS}
                or (
                    decision.choice == ALLOW_SESSION
                    and decision.conversation_id == identity.conversation_id
                )
            )
        ]
        denied = [item for item in candidates if item.choice == DENY_ALWAYS]
        if denied:
            return max(denied, key=lambda item: item.created_at_ms)
        return max(candidates, key=lambda item: item.created_at_ms, default=None)

    def record(
        self,
        *,
        choice: str,
        client_route_id: str,
        contact_id: str,
        conversation_id: str,
        action_hash: str,
    ) -> ToolPermissionDecision:
        clean_choice = normalize_choice(choice)
        identity = self._identity(
            client_route_id,
            contact_id,
            conversation_id,
            action_hash,
        )
        decision = ToolPermissionDecision(
            choice=clean_choice,
            client_route_id=identity.client_route_id,
            contact_id=identity.contact_id,
            conversation_id=(
                identity.conversation_id if clean_choice == ALLOW_SESSION else ""
            ),
            action_hash=identity.action_hash,
            created_at_ms=max(0, int(self.clock() * 1_000)),
        )
        with self._lock:
            document = self._load()
            retained = [
                entry
                for entry in document["entries"]
                if not self._same_action(entry, identity)
            ]
            if clean_choice != ALLOW_ONCE:
                retained.append(self._encode(decision))
            document["entries"] = retained[-MAX_ENTRIES:]
            self._write(document)
        return decision

    def clear(self) -> None:
        with self._lock:
            self._write({"version": STATE_VERSION, "entries": []})

    def _load(self) -> dict:
        if not self.path.exists():
            return {"version": STATE_VERSION, "entries": []}
        document = read_secure_json(
            self.path,
            purpose=STATE_PURPOSE,
        ).value
        entries = document.get("entries")
        if document.get("version") != STATE_VERSION or not isinstance(entries, list):
            raise ValueError("Tool permission policy state is invalid")
        return {"version": STATE_VERSION, "entries": entries[-MAX_ENTRIES:]}

    def _write(self, document: dict) -> None:
        write_secure_json(
            self.path,
            {
                "version": STATE_VERSION,
                "entries": list(document.get("entries") or [])[-MAX_ENTRIES:],
            },
            purpose=STATE_PURPOSE,
        )

    @staticmethod
    def _identity(
        client_route_id: str,
        contact_id: str,
        conversation_id: str,
        action_hash: str,
    ) -> ToolPermissionDecision:
        clean_route = _required(client_route_id, "client route", 200)
        clean_contact = _required(contact_id, "contact", 160)
        clean_conversation = _required(conversation_id, "conversation", 200)
        clean_hash = str(action_hash or "").strip().lower()
        if not _ACTION_HASH.fullmatch(clean_hash):
            raise ValueError("Tool permission action hash is invalid")
        return ToolPermissionDecision(
            choice=ALLOW_ONCE,
            client_route_id=clean_route,
            contact_id=clean_contact,
            conversation_id=clean_conversation,
            action_hash=clean_hash,
            created_at_ms=0,
        )

    @staticmethod
    def _encode(decision: ToolPermissionDecision) -> dict:
        return {
            "choice": decision.choice,
            "client_route_id": decision.client_route_id,
            "contact_id": decision.contact_id,
            "conversation_id": decision.conversation_id,
            "action_hash": decision.action_hash,
            "created_at_ms": decision.created_at_ms,
        }

    @staticmethod
    def _decode(value: dict) -> ToolPermissionDecision | None:
        try:
            choice = normalize_choice(value.get("choice"))
            if choice == ALLOW_ONCE:
                return None
            route = _required(value.get("client_route_id"), "client route", 200)
            contact = _required(value.get("contact_id"), "contact", 160)
            conversation = str(value.get("conversation_id") or "").strip()[:200]
            if choice == ALLOW_SESSION and not conversation:
                return None
            action_hash = str(value.get("action_hash") or "").strip().lower()
            if not _ACTION_HASH.fullmatch(action_hash):
                return None
            return ToolPermissionDecision(
                choice=choice,
                client_route_id=route,
                contact_id=contact,
                conversation_id=conversation,
                action_hash=action_hash,
                created_at_ms=max(0, int(value.get("created_at_ms") or 0)),
            )
        except (TypeError, ValueError):
            return None

    @staticmethod
    def _same_action(entry: object, identity: ToolPermissionDecision) -> bool:
        if not isinstance(entry, dict):
            return False
        return (
            str(entry.get("client_route_id") or "").strip() == identity.client_route_id
            and str(entry.get("contact_id") or "").strip() == identity.contact_id
            and str(entry.get("action_hash") or "").strip().lower()
            == identity.action_hash
        )


def normalize_choice(value: object) -> str:
    choice = str(value or "").strip().lower()
    if choice not in VALID_CHOICES:
        raise ValueError("Tool permission decision scope is invalid")
    return choice


def _required(value: object, label: str, limit: int) -> str:
    clean = str(value or "").strip()[:limit]
    if not clean:
        raise ValueError(f"Tool permission {label} is required")
    return clean


tool_permission_policy = ToolPermissionPolicy()
