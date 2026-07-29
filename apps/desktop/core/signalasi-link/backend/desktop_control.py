"""Trusted, auditable remote display and input control for SignalASI Desktop.

SignalASI Link supplies the authenticated, encrypted transport.  This module
adds a second authorization boundary for desktop control, plus replay
protection, bounded screen capture, redacted audit records, and the small P0
input surface exposed to an explicitly approved phone.
"""
from __future__ import annotations

import base64
import ctypes
import hashlib
import json
import os
import secrets
import threading
import time
import uuid
from pathlib import Path
from typing import Any, Callable, Mapping

from image_transport import MAX_IMAGE_TRANSPORT_BYTES, compress_pil_image
from pairing_access import (
    DESKTOP_EXECUTOR,
    client_grant,
    grant_binding,
    has_full_executor,
)
from pairing_state import DATA_DIR
from signalasi_client import get_signal_bundle, sign_signal_identity
from tool_handle_registry import (
    TOOL_HANDLE_CONTRACT,
    ToolHandleError,
    ToolHandleRegistry,
    ToolHandleScope,
    tool_handle_registry,
)


CONTRACT_VERSION = "signalasi.desktop-control/1.2"
AUTHORIZED_APP_CONTRACT = "signalasi.authorized-app/1.0"
AUTHORIZATION_VERSION = 1
RECEIPT_VERSION = 4
OFFER_TTL_SECONDS = 10 * 60
ACTION_TTL_MILLIS = 30_000
DESKTOP_SESSION_TTL_SECONDS = 7 * 24 * 60 * 60
MAX_CLOCK_SKEW_MILLIS = 30_000
MAX_SCREENSHOT_BYTES = MAX_IMAGE_TRANSPORT_BYTES
MAX_AUDIT_EVENTS = 1_000
MAX_RECENT_ACTIONS = 256
MAX_VISIBLE_RECEIPTS = 50

SCREENSHOT = "desktop.screenshot"
CLICK_XY = "desktop.click_xy"
TYPE_TEXT = "desktop.type_text"
HOTKEY = "desktop.hotkey"
SCROLL = "desktop.scroll"
WINDOW_SWITCH = "desktop.window_switch"
FILE_SELECT = "desktop.file_select"

DEFAULT_ALLOWED_TOOLS = (
    SCREENSHOT,
    CLICK_XY,
    TYPE_TEXT,
    HOTKEY,
    SCROLL,
    WINDOW_SWITCH,
    FILE_SELECT,
)
RECEIPT_SIGNED_FIELDS = (
    "receipt_version",
    "receipt_id",
    "task_id",
    "action_id",
    "authorization_id",
    "desktop_session_id",
    "tool_id",
    "status",
    "summary",
    "error_code",
    "error_retryable",
    "request_sha256",
    "input_sha256",
    "output_sha256",
    "evidence_sha256",
    "controller_app_instance_id",
    "controller_name",
    "controller_platform",
    "controller_fingerprint",
    "started_at",
    "completed_at",
    "duration_ms",
    "signer_id",
    "signature_key_id",
)

IdentityProvider = Callable[[], dict[str, str]]
ReceiptSigner = Callable[[bytes], dict[str, str]]


class DesktopControlError(RuntimeError):
    def __init__(self, code: str, message: str, *, retryable: bool = False) -> None:
        super().__init__(message)
        self.code = str(code or "desktop_control_failed")
        self.retryable = bool(retryable)


def _default_state() -> dict[str, Any]:
    return {
        "schema": 1,
        "settings": {
            "enabled": False,
            "require_unlocked": False,
        },
        "authorizations": {},
        "recent_actions": {},
        "audit": [],
        "updated_at": int(time.time() * 1_000),
    }


def _canonical_digest(value: Any) -> str:
    raw = json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _canonical_json(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")


def _default_identity() -> dict[str, str]:
    bundle = get_signal_bundle()
    fingerprint = str(bundle.get("identityKeySha256") or "").lower()
    return {
        "signer_id": f"desktop_{fingerprint[:16]}",
        "signature_key_id": fingerprint,
    }


def _uuid(value: Any, field: str) -> str:
    text = str(value or "").strip()
    try:
        uuid.UUID(text)
    except (ValueError, TypeError, AttributeError) as exc:
        raise DesktopControlError("invalid_input", f"{field} must be a UUID") from exc
    return text


def _bounded_text(value: Any, field: str, maximum: int) -> str:
    text = str(value or "")
    if len(text) > maximum or any(ord(char) == 0 for char in text):
        raise DesktopControlError("invalid_input", f"{field} exceeds its safe limit")
    return text


class DesktopControlManager:
    def __init__(
        self,
        state_path: Path | None = None,
        *,
        now: Callable[[], float] = time.time,
        screenshot_provider: Callable[[], dict[str, Any]] | None = None,
        input_controller: "WindowsInputController | None" = None,
        identity_provider: IdentityProvider = _default_identity,
        receipt_signer: ReceiptSigner = sign_signal_identity,
        handle_registry: ToolHandleRegistry | None = None,
    ) -> None:
        self.state_path = Path(state_path or DATA_DIR / "desktop_control.json")
        self.now = now
        self._lock = threading.RLock()
        self._input_lock = threading.Lock()
        self._offers: dict[str, dict[str, Any]] = {}
        self._state = self._load()
        self._screenshot_provider = screenshot_provider or capture_desktop_screenshot
        self._input = input_controller or WindowsInputController()
        self._identity_provider = identity_provider
        self._receipt_signer = receipt_signer
        self._handles = handle_registry or tool_handle_registry()

    def settings(self) -> dict[str, Any]:
        with self._lock:
            return dict(self._state["settings"])

    def update_settings(
        self,
        *,
        enabled: bool | None = None,
        require_unlocked: bool | None = None,
    ) -> dict[str, Any]:
        with self._lock:
            settings = self._state["settings"]
            if enabled is not None:
                settings["enabled"] = bool(enabled)
                if not settings["enabled"]:
                    self._offers.clear()
                    self._handles.revoke_kind("desktop_session")
            if require_unlocked is not None:
                settings["require_unlocked"] = bool(require_unlocked)
            self._append_audit_locked(
                "settings_changed",
                status="succeeded",
                summary=(
                    f"executor={'enabled' if settings['enabled'] else 'disabled'}; "
                    f"require_unlocked={bool(settings['require_unlocked'])}"
                ),
            )
            self._save_locked()
            return self.status()

    def create_offer(self, pairing_token: str) -> dict[str, Any] | None:
        if not self.settings().get("enabled"):
            return None
        now = self.now()
        token = secrets.token_urlsafe(32)
        token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
        with self._lock:
            self._prune_offers_locked(now)
            self._offers[token_hash] = {
                "pairing_token": str(pairing_token or ""),
                "created_at": now,
                "expires_at": now + OFFER_TTL_SECONDS,
            }
        return {
            "version": AUTHORIZATION_VERSION,
            "token": token,
            "expires_at": int((now + OFFER_TTL_SECONDS) * 1_000),
            "tools": list(DEFAULT_ALLOWED_TOOLS),
        }

    def accept_pairing_offer(
        self,
        control_token: str,
        pairing_token: str,
        paired_client: Mapping[str, Any],
    ) -> dict[str, Any] | None:
        token = str(control_token or "")
        if not token:
            return None
        token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
        now = self.now()
        with self._lock:
            if not self._state["settings"].get("enabled"):
                raise DesktopControlError(
                    "desktop_executor_disabled",
                    "Desktop Executor is disabled",
                )
            self._prune_offers_locked(now)
            offer = self._offers.pop(token_hash, None)
            if not offer or not secrets.compare_digest(
                str(offer.get("pairing_token") or ""), str(pairing_token or "")
            ):
                self._append_audit_locked(
                    "authorization_offer_rejected",
                    client_route_id=str(paired_client.get("client_route_id") or ""),
                    phone_fingerprint=str(paired_client.get("identity_fingerprint") or ""),
                    status="rejected",
                    summary="Invalid, expired, or already consumed authorization offer",
                )
                self._save_locked()
                raise DesktopControlError(
                    "authorization_offer_invalid",
                    "Desktop control authorization offer is invalid or expired",
                )

            route_id = str(paired_client.get("client_route_id") or "")
            fingerprint = str(paired_client.get("identity_fingerprint") or "").lower()
            signal_name = str(paired_client.get("signal_name") or "")
            if not route_id or len(fingerprint) != 64 or not signal_name:
                raise DesktopControlError("authorization_identity_invalid", "Paired phone identity is incomplete")
            if not has_full_executor(paired_client):
                self._append_audit_locked(
                    "authorization_offer_rejected",
                    client_route_id=route_id,
                    phone_fingerprint=fingerprint,
                    status="rejected",
                    summary="Pairing did not grant Desktop Executor access",
                )
                self._save_locked()
                raise DesktopControlError(
                    "desktop_executor_scope_required",
                    "Desktop control requires a pairing QR with Desktop Executor access",
                )
            pairing_access = client_grant(paired_client)
            access_binding = grant_binding(paired_client)

            existing = next(
                (
                    row for row in self._state["authorizations"].values()
                    if row.get("status") == "active"
                    and secrets.compare_digest(str(row.get("phone_identity_fingerprint") or "").lower(), fingerprint)
                    and str(row.get("phone_signal_name") or "") == signal_name
                ),
                None,
            )
            if existing is not None:
                existing["client_route_id"] = route_id
                existing["phone_name"] = str(
                    paired_client.get("display_name") or existing.get("phone_name") or "SignalASI Phone"
                )[:120]
                existing["grant_source"] = "pairing_qr"
                existing["access_profile"] = DESKTOP_EXECUTOR
                existing["access_scopes"] = list(pairing_access["scopes"])
                existing["pairing_access_sha256"] = access_binding
                existing["allowed_tools"] = list(DEFAULT_ALLOWED_TOOLS)
                existing["status"] = "active"
                existing["granted_at"] = int(existing.get("granted_at") or now * 1_000)
                existing["updated_at"] = int(now * 1_000)
                self._append_audit_locked(
                    "authorization_rebound",
                    authorization_id=str(existing["authorization_id"]),
                    client_route_id=route_id,
                    phone_fingerprint=fingerprint,
                    status="succeeded",
                    summary="Existing trusted phone identity moved to a new Link route",
                )
                self._save_locked()
                return self._public_authorization(existing)

            authorization_id = str(uuid.uuid4())
            granted_at = int(now * 1_000)
            row = {
                "authorization_id": authorization_id,
                "grant_type": "desktop_control",
                "grant_source": "pairing_qr",
                "access_profile": DESKTOP_EXECUTOR,
                "access_scopes": list(pairing_access["scopes"]),
                "pairing_access_sha256": access_binding,
                "phone_identity_fingerprint": fingerprint,
                "phone_signal_name": signal_name,
                "phone_name": str(paired_client.get("display_name") or "SignalASI Phone")[:120],
                "client_route_id": route_id,
                "platform": str(paired_client.get("platform") or "unknown")[:32],
                "requested_at": int(now * 1_000),
                "granted_at": granted_at,
                "last_used_at": 0,
                "updated_at": int(now * 1_000),
                "allowed_tools": list(DEFAULT_ALLOWED_TOOLS),
                "status": "active",
            }
            self._state["authorizations"][authorization_id] = row
            self._append_audit_locked(
                "authorization_approved_at_pairing",
                authorization_id=authorization_id,
                client_route_id=route_id,
                phone_fingerprint=fingerprint,
                status="succeeded",
                summary="Desktop Executor access was approved by the pairing QR",
            )
            self._save_locked()
            return self._public_authorization(row)

    def revoke(self, authorization_id: str, reason: str = "user_revoked") -> dict[str, Any]:
        with self._lock:
            row = self._authorization_locked(authorization_id, include_revoked=True)
            now_ms = int(self.now() * 1_000)
            row["status"] = "revoked"
            row["revoked_at"] = now_ms
            row["revoke_reason"] = str(reason or "user_revoked")[:120]
            row["updated_at"] = now_ms
            self._handles.revoke_resource("desktop_session", authorization_id)
            self._append_audit_locked(
                "authorization_revoked",
                authorization_id=authorization_id,
                client_route_id=str(row.get("client_route_id") or ""),
                phone_fingerprint=str(row.get("phone_identity_fingerprint") or ""),
                status="succeeded",
                summary=row["revoke_reason"],
            )
            self._save_locked()
            return self._public_authorization(row)

    def revoke_by_client(
        self,
        authorization_id: str,
        paired_client: Mapping[str, Any],
        reason: str = "revoked_by_phone",
    ) -> dict[str, Any]:
        with self._lock:
            row = self._authorization_locked(authorization_id)
            route_matches = str(row.get("client_route_id") or "") == str(
                paired_client.get("client_route_id") or ""
            )
            fingerprint_matches = secrets.compare_digest(
                str(row.get("phone_identity_fingerprint") or "").lower(),
                str(paired_client.get("identity_fingerprint") or "").lower(),
            )
            if not route_matches or not fingerprint_matches:
                raise DesktopControlError(
                    "authorization_identity_mismatch",
                    "Phone identity does not own this authorization",
                )
        return self.revoke(authorization_id, reason)

    def revoke_for_client(self, client_route_id: str, reason: str = "pairing_revoked") -> list[dict[str, Any]]:
        revoked: list[dict[str, Any]] = []
        with self._lock:
            ids = [
                key for key, row in self._state["authorizations"].items()
                if str(row.get("client_route_id") or "") == str(client_route_id or "")
                and row.get("status") != "revoked"
            ]
        for authorization_id in ids:
            revoked.append(self.revoke(authorization_id, reason))
        return revoked

    def status(self, client_route_id: str = "", *, include_revoked: bool = False) -> dict[str, Any]:
        with self._lock:
            rows = [
                self._public_authorization(row)
                for row in self._state["authorizations"].values()
                if (not client_route_id or str(row.get("client_route_id") or "") == client_route_id)
                and (include_revoked or row.get("status") != "revoked")
            ]
            rows.sort(key=lambda row: int(row.get("updated_at") or 0), reverse=True)
            visible_authorization_ids = {
                str(row.get("authorization_id") or "")
                for row in rows
            }
            receipts = [
                dict(action.get("receipt") or {})
                for action in sorted(
                    self._state["recent_actions"].values(),
                    key=lambda item: int(item.get("created_at") or 0),
                    reverse=True,
                )
                if isinstance(action, dict)
                and isinstance(action.get("receipt"), dict)
                and int(action["receipt"].get("receipt_version") or 0) == RECEIPT_VERSION
                and str(action["receipt"].get("authorization_id") or "") in visible_authorization_ids
            ][:MAX_VISIBLE_RECEIPTS]
            return {
                "contract_version": CONTRACT_VERSION,
                "authorized_app_contract": AUTHORIZED_APP_CONTRACT,
                "tool_handle_contract": TOOL_HANDLE_CONTRACT,
                "enabled": bool(self._state["settings"].get("enabled")),
                "require_unlocked": bool(self._state["settings"].get("require_unlocked")),
                "allowed_tools": list(DEFAULT_ALLOWED_TOOLS),
                "authorizations": rows,
                "pending_count": sum(row.get("status") == "pending" for row in rows),
                "active_count": sum(row.get("status") == "active" for row in rows),
                "recent_audit": list(reversed(self._state["audit"][-50:])),
                "recent_receipts": receipts,
            }

    def execute_request(
        self,
        payload: Mapping[str, Any],
        paired_client: Mapping[str, Any],
        *,
        on_running: Callable[[dict[str, Any]], None] | None = None,
    ) -> dict[str, Any]:
        (
            action_id,
            authorization,
            desktop_session_id,
            tool_id,
            arguments,
            request_digest,
        ) = self._validate_request(payload, paired_client)
        with self._lock:
            previous = self._state["recent_actions"].get(action_id)
            if isinstance(previous, dict):
                if not secrets.compare_digest(str(previous.get("request_sha256") or ""), request_digest):
                    raise DesktopControlError("duplicate_action_conflict", "Action ID was already used for different input")
                receipt = dict(previous.get("receipt") or {})
                receipt["replayed"] = True
                receipt["post_screenshot"] = None
                return receipt
            self._state["recent_actions"][action_id] = {
                "request_sha256": request_digest,
                "status": "running",
                "created_at": int(self.now() * 1_000),
                "receipt": {},
            }
            self._prune_recent_actions_locked()
            self._save_locked()

        started_at = int(self.now() * 1_000)
        if on_running:
            on_running({
                "type": "desktop_executor_event",
                "task_id": str(payload.get("task_id") or ""),
                "action_id": action_id,
                "authorization_id": str(authorization["authorization_id"]),
                "desktop_session_id": desktop_session_id,
                "tool_id": tool_id,
                "status": "running",
                "summary": self._action_summary(tool_id, arguments, running=True),
                "seq": 1,
                "timestamp": started_at,
            })

        try:
            with self._input_lock:
                if not self.settings().get("enabled"):
                    raise DesktopControlError("desktop_executor_disabled", "Desktop Executor is disabled")
                authorization = self._revalidate_authorization(
                    str(authorization["authorization_id"]),
                    paired_client,
                    desktop_session_id,
                    tool_id,
                )
                if self.settings().get("require_unlocked") and self._input.is_locked():
                    raise DesktopControlError("desktop_locked", "Desktop must be unlocked before remote control")
                screenshot = None
                output: dict[str, Any] = {}
                if tool_id == SCREENSHOT:
                    screenshot = self._screenshot_provider()
                    output = {"screenshot": screenshot}
                elif tool_id == CLICK_XY:
                    x = self._bounded_int(arguments.get("x"), "x", 0, 100_000)
                    y = self._bounded_int(arguments.get("y"), "y", 0, 100_000)
                    coordinate_width_value = arguments.get("coordinate_width")
                    coordinate_height_value = arguments.get("coordinate_height")
                    if (coordinate_width_value is None) != (coordinate_height_value is None):
                        raise DesktopControlError(
                            "invalid_input",
                            "coordinate_width and coordinate_height must be provided together",
                        )
                    coordinate_width = None
                    coordinate_height = None
                    if coordinate_width_value is not None:
                        coordinate_width = self._bounded_int(
                            coordinate_width_value, "coordinate_width", 1, 100_000
                        )
                        coordinate_height = self._bounded_int(
                            coordinate_height_value, "coordinate_height", 1, 100_000
                        )
                        if x >= coordinate_width or y >= coordinate_height:
                            raise DesktopControlError(
                                "invalid_input",
                                "Click coordinates are outside the supplied coordinate space",
                            )
                    button = str(arguments.get("button") or "left").lower()
                    if button not in {"left", "right"}:
                        raise DesktopControlError("invalid_input", "button must be left or right")
                    self._input.click(
                        x,
                        y,
                        button,
                        source_width=coordinate_width,
                        source_height=coordinate_height,
                    )
                    output = {"x": x, "y": y, "button": button}
                    screenshot = self._screenshot_provider()
                elif tool_id == TYPE_TEXT:
                    text = _bounded_text(arguments.get("text"), "text", 4_096)
                    if not text:
                        raise DesktopControlError("invalid_input", "text must not be empty")
                    self._input.type_text(text)
                    output = {"characters": len(text)}
                    screenshot = self._screenshot_provider()
                elif tool_id == HOTKEY:
                    keys = arguments.get("keys")
                    if not isinstance(keys, list) or not 1 <= len(keys) <= 4:
                        raise DesktopControlError("invalid_input", "keys must contain one to four key names")
                    normalized = [str(key or "").strip().lower() for key in keys]
                    self._input.hotkey(normalized)
                    output = {"keys": normalized}
                    screenshot = self._screenshot_provider()
                elif tool_id == SCROLL:
                    delta = self._bounded_int(arguments.get("delta"), "delta", -2_400, 2_400)
                    if delta == 0:
                        raise DesktopControlError("invalid_input", "delta must not be zero")
                    self._input.scroll(delta)
                    output = {"delta": delta}
                    screenshot = self._screenshot_provider()
                elif tool_id == WINDOW_SWITCH:
                    direction = str(arguments.get("direction") or "next").lower()
                    if direction not in {"next", "previous"}:
                        raise DesktopControlError(
                            "invalid_input",
                            "direction must be next or previous",
                        )
                    self._input.window_switch(direction)
                    output = {"direction": direction}
                    screenshot = self._screenshot_provider()
                elif tool_id == FILE_SELECT:
                    raw_path = _bounded_text(
                        arguments.get("path"),
                        "path",
                        32_767,
                    ).strip()
                    if not raw_path:
                        raise DesktopControlError(
                            "invalid_input",
                            "path must not be empty",
                        )
                    try:
                        selected_path = Path(raw_path).expanduser().resolve(strict=True)
                    except (OSError, RuntimeError) as exc:
                        raise DesktopControlError(
                            "file_not_found",
                            "The selected Desktop file does not exist",
                        ) from exc
                    if not selected_path.is_file():
                        raise DesktopControlError(
                            "file_not_found",
                            "The selected Desktop path is not a file",
                        )
                    self._input.select_file(str(selected_path))
                    output = {
                        "selected": True,
                        "file_name": selected_path.name,
                    }
                    screenshot = self._screenshot_provider()
                else:
                    raise DesktopControlError("invalid_tool", "Desktop control tool is not supported")

            completed_at = int(self.now() * 1_000)
            receipt = self._seal_receipt({
                "type": "desktop_action_receipt",
                "task_id": str(payload.get("task_id") or ""),
                "action_id": action_id,
                "authorization_id": str(authorization["authorization_id"]),
                "desktop_session_id": desktop_session_id,
                "tool_id": tool_id,
                "status": "succeeded",
                "summary": self._action_summary(tool_id, arguments),
                "output": output,
                "started_at": started_at,
                "completed_at": completed_at,
                "duration_ms": max(0, completed_at - started_at),
                "replayed": False,
                "post_screenshot": screenshot if tool_id != SCREENSHOT else None,
            }, request_digest, arguments, paired_client)
            with self._lock:
                authorization["last_used_at"] = completed_at
                authorization["updated_at"] = completed_at
                self._complete_action_locked(action_id, request_digest, receipt)
                self._append_audit_locked(
                    "desktop_action",
                    authorization_id=str(authorization["authorization_id"]),
                    client_route_id=str(authorization["client_route_id"]),
                    phone_fingerprint=str(authorization["phone_identity_fingerprint"]),
                    tool_id=tool_id,
                    status="succeeded",
                    summary=self._audit_summary(tool_id, arguments),
                )
                self._save_locked()
            return receipt
        except DesktopControlError as exc:
            receipt = self._failure_receipt(
                payload,
                action_id,
                tool_id,
                started_at,
                exc,
                request_digest=request_digest,
                arguments=arguments,
                paired_client=paired_client,
            )
            with self._lock:
                self._complete_action_locked(action_id, request_digest, receipt)
                self._append_audit_locked(
                    "desktop_action",
                    authorization_id=str(authorization.get("authorization_id") or ""),
                    client_route_id=str(authorization.get("client_route_id") or ""),
                    phone_fingerprint=str(authorization.get("phone_identity_fingerprint") or ""),
                    tool_id=tool_id,
                    status="failed",
                    summary=f"{exc.code}: {str(exc)[:240]}",
                )
                self._save_locked()
            return receipt
        except Exception as exc:
            wrapped = DesktopControlError("input_execution_failed", str(exc) or "Desktop input execution failed")
            receipt = self._failure_receipt(
                payload,
                action_id,
                tool_id,
                started_at,
                wrapped,
                request_digest=request_digest,
                arguments=arguments,
                paired_client=paired_client,
            )
            with self._lock:
                self._complete_action_locked(action_id, request_digest, receipt)
                self._append_audit_locked(
                    "desktop_action",
                    authorization_id=str(authorization.get("authorization_id") or ""),
                    client_route_id=str(authorization.get("client_route_id") or ""),
                    phone_fingerprint=str(authorization.get("phone_identity_fingerprint") or ""),
                    tool_id=tool_id,
                    status="failed",
                    summary=f"input_execution_failed: {str(exc)[:240]}",
                )
                self._save_locked()
            return receipt

    def _validate_request(
        self,
        payload: Mapping[str, Any],
        paired_client: Mapping[str, Any],
    ) -> tuple[str, dict[str, Any], str, str, dict[str, Any], str]:
        if not self.settings().get("enabled"):
            raise DesktopControlError("desktop_executor_disabled", "Desktop Executor is disabled")
        action_id = _uuid(payload.get("action_id"), "action_id")
        authorization_id = _uuid(payload.get("authorization_id"), "authorization_id")
        desktop_session_id = _bounded_text(
            payload.get("desktop_session_id"),
            "desktop_session_id",
            240,
        ).strip()
        if not desktop_session_id:
            raise DesktopControlError(
                "desktop_session_required",
                "Desktop control requires an explicit desktop_session_id",
                retryable=True,
            )
        task_id = _bounded_text(payload.get("task_id"), "task_id", 160).strip()
        if not task_id:
            raise DesktopControlError("invalid_input", "task_id must not be empty")
        tool_id = str(payload.get("tool_id") or "")
        if tool_id not in DEFAULT_ALLOWED_TOOLS:
            raise DesktopControlError("invalid_tool", "Desktop control tool is not allowed")
        arguments = payload.get("input")
        if not isinstance(arguments, dict):
            raise DesktopControlError("invalid_input", "input must be an object")
        encoded = json.dumps(arguments, ensure_ascii=False, allow_nan=False).encode("utf-8")
        if len(encoded) > 32 * 1024:
            raise DesktopControlError("invalid_input", "Desktop control input is too large")
        now_ms = int(self.now() * 1_000)
        sent_at = self._bounded_int(payload.get("sent_at"), "sent_at", 1, 9_999_999_999_999)
        expires_at = self._bounded_int(payload.get("expires_at"), "expires_at", 1, 9_999_999_999_999)
        if sent_at - now_ms > MAX_CLOCK_SKEW_MILLIS or expires_at <= sent_at:
            raise DesktopControlError("message_expired", "Desktop control request has invalid timing")
        if expires_at - sent_at > ACTION_TTL_MILLIS or now_ms > expires_at:
            raise DesktopControlError("message_expired", "Desktop control request expired")
        with self._lock:
            authorization = self._authorization_locked(authorization_id)
            if authorization.get("status") != "active":
                raise DesktopControlError("authorization_required", "Desktop control authorization is not active")
            route = str(paired_client.get("client_route_id") or "")
            fingerprint = str(paired_client.get("identity_fingerprint") or "").lower()
            if route != str(authorization.get("client_route_id") or ""):
                raise DesktopControlError("authorization_identity_mismatch", "Phone route does not match authorization")
            if not secrets.compare_digest(
                fingerprint, str(authorization.get("phone_identity_fingerprint") or "").lower()
            ):
                raise DesktopControlError("authorization_identity_mismatch", "Phone identity does not match authorization")
            self._validate_pairing_grant(authorization, paired_client)
            if tool_id not in set(authorization.get("allowed_tools") or []):
                raise DesktopControlError("tool_not_allowed", "Tool is outside this authorization")
            self._resolve_desktop_session(
                desktop_session_id,
                authorization_id,
                route,
                tool_id,
            )
        digest = _canonical_digest({
            "contract_version": CONTRACT_VERSION,
            "type": "desktop_executor_request",
            "task_id": task_id,
            "action_id": action_id,
            "authorization_id": authorization_id,
            "desktop_session_id": desktop_session_id,
            "tool_id": tool_id,
            "input": arguments,
            "sent_at": sent_at,
            "expires_at": expires_at,
            "client_route_id": route,
            "controller_fingerprint": fingerprint,
            "controller_signal_name": str(paired_client.get("signal_name") or ""),
        })
        return (
            action_id,
            authorization,
            desktop_session_id,
            tool_id,
            dict(arguments),
            digest,
        )

    def _revalidate_authorization(
        self,
        authorization_id: str,
        paired_client: Mapping[str, Any],
        desktop_session_id: str,
        tool_id: str,
    ) -> dict[str, Any]:
        with self._lock:
            authorization = self._authorization_locked(authorization_id)
            if authorization.get("status") != "active":
                raise DesktopControlError("authorization_required", "Desktop control authorization is not active")
            route = str(paired_client.get("client_route_id") or "")
            fingerprint = str(paired_client.get("identity_fingerprint") or "").lower()
            if route != str(authorization.get("client_route_id") or ""):
                raise DesktopControlError("authorization_identity_mismatch", "Phone route does not match authorization")
            if not secrets.compare_digest(
                fingerprint,
                str(authorization.get("phone_identity_fingerprint") or "").lower(),
            ):
                raise DesktopControlError("authorization_identity_mismatch", "Phone identity does not match authorization")
            self._validate_pairing_grant(authorization, paired_client)
            if tool_id not in set(authorization.get("allowed_tools") or []):
                raise DesktopControlError("tool_not_allowed", "Tool is outside this authorization")
            self._resolve_desktop_session(
                desktop_session_id,
                authorization_id,
                route,
                tool_id,
            )
            return authorization

    @staticmethod
    def _validate_pairing_grant(
        authorization: Mapping[str, Any],
        paired_client: Mapping[str, Any],
    ) -> None:
        if not has_full_executor(paired_client):
            raise DesktopControlError(
                "desktop_executor_scope_required",
                "The current pairing does not grant Desktop Executor access",
            )
        expected_binding = grant_binding(paired_client)
        stored_binding = str(authorization.get("pairing_access_sha256") or "")
        if (
            authorization.get("grant_source") != "pairing_qr"
            or authorization.get("access_profile") != DESKTOP_EXECUTOR
            or len(stored_binding) != 64
            or not secrets.compare_digest(stored_binding, expected_binding)
        ):
            raise DesktopControlError(
                "pairing_authorization_stale",
                "Desktop control authorization no longer matches the trusted pairing",
            )

    def _resolve_desktop_session(
        self,
        desktop_session_id: str,
        authorization_id: str,
        client_route_id: str,
        tool_id: str,
    ) -> dict[str, Any]:
        try:
            handle = self._handles.resolve(
                desktop_session_id,
                kind="desktop_session",
                scope=ToolHandleScope(client_route_id),
                required_capability=tool_id,
            )
        except ToolHandleError as exc:
            raise DesktopControlError(
                exc.code,
                str(exc),
                retryable=exc.retryable,
            ) from exc
        if not secrets.compare_digest(
            str(handle.get("resource_id") or ""),
            authorization_id,
        ):
            raise DesktopControlError(
                "desktop_session_authorization_mismatch",
                "Desktop session belongs to a different authorization",
            )
        return handle

    def _failure_receipt(
        self,
        payload: Mapping[str, Any],
        action_id: str,
        tool_id: str,
        started_at: int,
        error: DesktopControlError,
        *,
        request_digest: str,
        arguments: Mapping[str, Any],
        paired_client: Mapping[str, Any],
    ) -> dict[str, Any]:
        completed_at = int(self.now() * 1_000)
        return self._seal_receipt({
            "type": "desktop_action_receipt",
            "task_id": str(payload.get("task_id") or ""),
            "action_id": action_id,
            "authorization_id": str(payload.get("authorization_id") or ""),
            "desktop_session_id": str(payload.get("desktop_session_id") or ""),
            "tool_id": tool_id,
            "status": "failed",
            "summary": str(error)[:500],
            "error": {"code": error.code, "message": str(error)[:500], "retryable": error.retryable},
            "started_at": started_at,
            "completed_at": completed_at,
            "duration_ms": max(0, completed_at - started_at),
            "replayed": False,
            "post_screenshot": None,
        }, request_digest, arguments, paired_client)

    def failure_receipt(
        self,
        payload: Mapping[str, Any],
        paired_client: Mapping[str, Any],
        error: DesktopControlError,
    ) -> dict[str, Any]:
        started_at = int(self.now() * 1_000)
        arguments = payload.get("input")
        safe_arguments = dict(arguments) if isinstance(arguments, dict) else {}
        request_digest = _canonical_digest({
            "contract_version": CONTRACT_VERSION,
            "type": "desktop_executor_request",
            "task_id": str(payload.get("task_id") or "")[:160],
            "action_id": str(payload.get("action_id") or "")[:160],
            "authorization_id": str(payload.get("authorization_id") or "")[:160],
            "desktop_session_id": str(payload.get("desktop_session_id") or "")[:240],
            "tool_id": str(payload.get("tool_id") or "")[:160],
            "input": safe_arguments,
            "sent_at": self._safe_int(payload.get("sent_at")),
            "expires_at": self._safe_int(payload.get("expires_at")),
            "client_route_id": str(paired_client.get("client_route_id") or ""),
            "controller_fingerprint": str(paired_client.get("identity_fingerprint") or "").lower(),
            "controller_signal_name": str(paired_client.get("signal_name") or ""),
        })
        return self._failure_receipt(
            payload,
            str(payload.get("action_id") or "")[:160],
            str(payload.get("tool_id") or "")[:160],
            started_at,
            error,
            request_digest=request_digest,
            arguments=safe_arguments,
            paired_client=paired_client,
        )

    def _seal_receipt(
        self,
        receipt: dict[str, Any],
        request_digest: str,
        arguments: Mapping[str, Any],
        paired_client: Mapping[str, Any],
    ) -> dict[str, Any]:
        error = receipt.get("error") if isinstance(receipt.get("error"), dict) else {}
        evidence = receipt.get("post_screenshot")
        output = receipt.get("output") if isinstance(receipt.get("output"), dict) else {}
        if not isinstance(evidence, dict):
            candidate = output.get("screenshot")
            evidence = candidate if isinstance(candidate, dict) else {}
        evidence_sha256 = self._screenshot_digest(evidence)
        input_sha256 = _canonical_digest(dict(arguments))
        output_sha256 = _canonical_digest(
            self._receipt_output_contract(receipt, evidence_sha256)
        )
        identity = self._identity_provider()
        signer_id = str(identity.get("signer_id") or "").strip()
        signature_key_id = str(identity.get("signature_key_id") or "").lower()
        if not signer_id or len(signature_key_id) != 64:
            raise DesktopControlError("receipt_signing_failed", "Desktop signing identity is unavailable")

        receipt_id = _canonical_digest({
            "task_id": str(receipt.get("task_id") or ""),
            "action_id": str(receipt.get("action_id") or ""),
            "authorization_id": str(receipt.get("authorization_id") or ""),
            "desktop_session_id": str(receipt.get("desktop_session_id") or ""),
            "request_sha256": request_digest,
            "output_sha256": output_sha256,
            "evidence_sha256": evidence_sha256,
            "completed_at": int(receipt.get("completed_at") or 0),
        })
        signed_fields = {
            "receipt_version": RECEIPT_VERSION,
            "receipt_id": receipt_id,
            "task_id": str(receipt.get("task_id") or ""),
            "action_id": str(receipt.get("action_id") or ""),
            "authorization_id": str(receipt.get("authorization_id") or ""),
            "desktop_session_id": str(receipt.get("desktop_session_id") or ""),
            "tool_id": str(receipt.get("tool_id") or ""),
            "status": str(receipt.get("status") or "failed"),
            "summary": str(receipt.get("summary") or ""),
            "error_code": str(error.get("code") or ""),
            "error_retryable": bool(error.get("retryable")),
            "request_sha256": request_digest,
            "input_sha256": input_sha256,
            "output_sha256": output_sha256,
            "evidence_sha256": evidence_sha256,
            "controller_app_instance_id": str(
                paired_client.get("signal_name") or ""
            ),
            "controller_name": str(
                paired_client.get("display_name") or "SignalASI App"
            )[:120],
            "controller_platform": str(
                paired_client.get("platform") or "unknown"
            )[:32],
            "controller_fingerprint": str(paired_client.get("identity_fingerprint") or "").lower(),
            "started_at": int(receipt.get("started_at") or 0),
            "completed_at": int(receipt.get("completed_at") or 0),
            "duration_ms": int(receipt.get("duration_ms") or 0),
            "signer_id": signer_id,
            "signature_key_id": signature_key_id,
        }
        signed = self._receipt_signer(_canonical_json(signed_fields))
        if (
            str(signed.get("signer_id") or "") != signer_id
            or str(signed.get("signature_key_id") or "").lower() != signature_key_id
            or not str(signed.get("signature") or "")
        ):
            raise DesktopControlError(
                "receipt_signing_failed",
                "Desktop signing identity changed while recording the action",
            )
        receipt.update(signed_fields)
        receipt["signature"] = str(signed["signature"])
        return receipt

    @staticmethod
    def _screenshot_digest(screenshot: Mapping[str, Any]) -> str:
        encoded = str(screenshot.get("image_base64") or "")
        if not encoded:
            return ""
        if str(screenshot.get("image_mime") or "") != "image/jpeg":
            raise DesktopControlError(
                "invalid_screenshot",
                "Desktop screenshot evidence must be JPEG",
            )
        try:
            value = base64.b64decode(encoded, validate=True)
        except (ValueError, TypeError) as exc:
            raise DesktopControlError("invalid_screenshot", "Desktop screenshot evidence is invalid") from exc
        if not value:
            raise DesktopControlError(
                "invalid_screenshot",
                "Desktop screenshot evidence is empty",
            )
        if len(value) > MAX_SCREENSHOT_BYTES:
            raise DesktopControlError(
                "screenshot_too_large",
                "Desktop screenshot exceeds the 100 KB transport budget",
            )
        try:
            declared_bytes = int(screenshot.get("bytes") or len(value))
        except (TypeError, ValueError) as exc:
            raise DesktopControlError(
                "invalid_screenshot",
                "Desktop screenshot byte metadata is invalid",
            ) from exc
        if declared_bytes != len(value):
            raise DesktopControlError(
                "invalid_screenshot",
                "Desktop screenshot byte metadata does not match its payload",
            )
        return hashlib.sha256(value).hexdigest()

    @classmethod
    def _receipt_output_contract(
        cls,
        receipt: Mapping[str, Any],
        evidence_sha256: str,
    ) -> dict[str, Any]:
        error = receipt.get("error") if isinstance(receipt.get("error"), dict) else {}
        output = dict(receipt.get("output") or {}) if isinstance(receipt.get("output"), dict) else {}
        if isinstance(output.get("screenshot"), dict):
            output["screenshot"] = cls._screenshot_metadata(
                output["screenshot"],
                evidence_sha256,
            )
        post_screenshot = receipt.get("post_screenshot")
        return {
            "status": str(receipt.get("status") or "failed"),
            "summary": str(receipt.get("summary") or ""),
            "error": {
                "code": str(error.get("code") or ""),
                "message": str(error.get("message") or ""),
                "retryable": bool(error.get("retryable")),
            } if error else None,
            "output": output,
            "post_screenshot": cls._screenshot_metadata(
                post_screenshot,
                evidence_sha256,
            ) if isinstance(post_screenshot, dict) else None,
        }

    @staticmethod
    def _screenshot_metadata(
        screenshot: Mapping[str, Any],
        evidence_sha256: str,
    ) -> dict[str, Any]:
        metadata = {
            str(key): value
            for key, value in screenshot.items()
            if str(key) != "image_base64"
        }
        metadata["image_sha256"] = evidence_sha256
        return metadata

    @staticmethod
    def _safe_int(value: Any) -> int:
        if isinstance(value, bool):
            return 0
        try:
            return int(value)
        except (TypeError, ValueError):
            return 0

    def _authorization_locked(self, authorization_id: str, *, include_revoked: bool = False) -> dict[str, Any]:
        row = self._state["authorizations"].get(str(authorization_id or ""))
        if not isinstance(row, dict) or (row.get("status") == "revoked" and not include_revoked):
            raise DesktopControlError("authorization_not_found", "Desktop control authorization was not found")
        return row

    def _public_authorization(self, row: Mapping[str, Any]) -> dict[str, Any]:
        fingerprint = str(row.get("phone_identity_fingerprint") or "")
        desktop_session = {}
        if row.get("status") == "active":
            desktop_session = self._handles.create(
                kind="desktop_session",
                resource_id=str(row.get("authorization_id") or ""),
                scope=ToolHandleScope(str(row.get("client_route_id") or "")),
                capabilities=list(row.get("allowed_tools") or []),
                ttl_seconds=DESKTOP_SESSION_TTL_SECONDS,
                metadata={
                    "authorization_id": str(row.get("authorization_id") or ""),
                    "platform": str(row.get("platform") or "unknown"),
                },
                reuse=True,
            )
        return {
            "record_version": 1,
            "authorization_id": str(row.get("authorization_id") or ""),
            "grant_type": "desktop_control",
            "app_instance_id": str(row.get("phone_signal_name") or ""),
            "app_name": str(row.get("phone_name") or "SignalASI Phone"),
            "app_identity_fingerprint": fingerprint,
            "app_platform": str(row.get("platform") or "unknown"),
            "phone_name": str(row.get("phone_name") or "SignalASI Phone"),
            "phone_fingerprint": fingerprint,
            "phone_fingerprint_short": fingerprint[:16],
            "client_route_id": str(row.get("client_route_id") or ""),
            "platform": str(row.get("platform") or "unknown"),
            "grant_source": str(row.get("grant_source") or ""),
            "access_profile": str(row.get("access_profile") or ""),
            "access_scopes": list(row.get("access_scopes") or []),
            "pairing_access_sha256": str(row.get("pairing_access_sha256") or ""),
            "requested_at": int(row.get("requested_at") or 0),
            "granted_at": int(row.get("granted_at") or 0),
            "last_used_at": int(row.get("last_used_at") or 0),
            "updated_at": int(row.get("updated_at") or 0),
            "allowed_tools": list(row.get("allowed_tools") or []),
            "status": str(row.get("status") or "unknown"),
            "revoked_at": int(row.get("revoked_at") or 0),
            "revoke_reason": str(row.get("revoke_reason") or ""),
            "desktop_session_id": str(desktop_session.get("handle_id") or ""),
            "desktop_session_expires_at": int(
                desktop_session.get("expires_at") or 0
            ),
        }

    def _append_audit_locked(
        self,
        event_type: str,
        *,
        authorization_id: str = "",
        client_route_id: str = "",
        phone_fingerprint: str = "",
        tool_id: str = "",
        status: str,
        summary: str,
    ) -> None:
        self._state["audit"].append({
            "event_id": str(uuid.uuid4()),
            "event_type": str(event_type),
            "authorization_id": str(authorization_id),
            "client_route_id": str(client_route_id),
            "phone_fingerprint_short": str(phone_fingerprint)[:16],
            "tool_id": str(tool_id),
            "status": str(status),
            "summary": str(summary)[:500],
            "created_at": int(self.now() * 1_000),
        })
        if len(self._state["audit"]) > MAX_AUDIT_EVENTS:
            self._state["audit"] = self._state["audit"][-MAX_AUDIT_EVENTS:]

    def _complete_action_locked(self, action_id: str, digest: str, receipt: dict[str, Any]) -> None:
        durable_receipt = dict(receipt)
        post_screenshot = durable_receipt.get("post_screenshot")
        if isinstance(post_screenshot, dict):
            durable_receipt["post_screenshot"] = self._screenshot_metadata(
                post_screenshot,
                str(receipt.get("evidence_sha256") or ""),
            )
        output = durable_receipt.get("output")
        if isinstance(output, dict) and isinstance(output.get("screenshot"), dict):
            durable_output = dict(output)
            durable_output["screenshot"] = self._screenshot_metadata(
                output["screenshot"],
                str(receipt.get("evidence_sha256") or ""),
            )
            durable_receipt["output"] = durable_output
        self._state["recent_actions"][action_id] = {
            "request_sha256": digest,
            "status": str(receipt.get("status") or "failed"),
            "created_at": int(self.now() * 1_000),
            "receipt": durable_receipt,
        }
        self._prune_recent_actions_locked()

    def _prune_recent_actions_locked(self) -> None:
        rows = self._state["recent_actions"]
        if len(rows) <= MAX_RECENT_ACTIONS:
            return
        ordered = sorted(rows, key=lambda key: int(rows[key].get("created_at") or 0))
        for key in ordered[: len(rows) - MAX_RECENT_ACTIONS]:
            rows.pop(key, None)

    def _prune_offers_locked(self, now: float) -> None:
        self._offers = {
            key: value for key, value in self._offers.items()
            if float(value.get("expires_at") or 0) >= now
        }

    @staticmethod
    def _bounded_int(value: Any, field: str, minimum: int, maximum: int) -> int:
        if isinstance(value, bool):
            raise DesktopControlError("invalid_input", f"{field} must be an integer")
        try:
            result = int(value)
        except (TypeError, ValueError) as exc:
            raise DesktopControlError("invalid_input", f"{field} must be an integer") from exc
        if result < minimum or result > maximum:
            raise DesktopControlError("invalid_input", f"{field} is outside the allowed range")
        return result

    @staticmethod
    def _action_summary(tool_id: str, arguments: Mapping[str, Any], *, running: bool = False) -> str:
        prefix = "Executing" if running else "Executed"
        if tool_id == SCREENSHOT:
            return f"{prefix} desktop screenshot"
        if tool_id == CLICK_XY:
            return f"{prefix} click at {arguments.get('x')}, {arguments.get('y')}"
        if tool_id == TYPE_TEXT:
            return f"{prefix} text input"
        if tool_id == HOTKEY:
            return f"{prefix} shortcut {'+'.join(str(key) for key in arguments.get('keys') or [])}"
        if tool_id == SCROLL:
            return f"{prefix} desktop scroll"
        if tool_id == WINDOW_SWITCH:
            return f"{prefix} window switch"
        if tool_id == FILE_SELECT:
            return f"{prefix} file selection"
        return f"{prefix} desktop action"

    @staticmethod
    def _audit_summary(tool_id: str, arguments: Mapping[str, Any]) -> str:
        if tool_id == TYPE_TEXT:
            return f"typed {len(str(arguments.get('text') or ''))} chars"
        if tool_id == SCREENSHOT:
            return "captured screen; image not retained"
        if tool_id == CLICK_XY:
            return f"clicked {arguments.get('button', 'left')} at {arguments.get('x')}, {arguments.get('y')}"
        if tool_id == HOTKEY:
            return f"pressed {'+'.join(str(key) for key in arguments.get('keys') or [])}"
        if tool_id == SCROLL:
            return f"scrolled {arguments.get('delta')}"
        if tool_id == WINDOW_SWITCH:
            return f"switched to the {arguments.get('direction', 'next')} window"
        if tool_id == FILE_SELECT:
            return "selected an existing file in the active file dialog"
        return "executed desktop action"

    def _load(self) -> dict[str, Any]:
        try:
            value = json.loads(self.state_path.read_text(encoding="utf-8"))
            if not isinstance(value, dict):
                raise ValueError("invalid state")
        except (OSError, ValueError, json.JSONDecodeError):
            value = _default_state()
        defaults = _default_state()
        for key in ("settings", "authorizations", "recent_actions", "audit"):
            if not isinstance(value.get(key), type(defaults[key])):
                value[key] = defaults[key]
        for key, default in defaults["settings"].items():
            value["settings"].setdefault(key, default)
        for row in value["recent_actions"].values():
            if isinstance(row, dict) and row.get("status") == "running":
                row["status"] = "ambiguous"
                row["receipt"] = {
                    "type": "desktop_action_receipt",
                    "status": "failed",
                    "summary": "Previous Desktop session ended before the action result was recorded",
                    "error": {"code": "action_state_ambiguous", "retryable": False},
                    "replayed": True,
                }
        return value

    def _save_locked(self) -> None:
        self._state["updated_at"] = int(self.now() * 1_000)
        self.state_path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.state_path.with_suffix(self.state_path.suffix + ".tmp")
        temporary.write_text(json.dumps(self._state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        temporary.replace(self.state_path)


class WindowsInputController:
    _VK = {
        "backspace": 0x08,
        "tab": 0x09,
        "enter": 0x0D,
        "shift": 0x10,
        "ctrl": 0x11,
        "control": 0x11,
        "alt": 0x12,
        "escape": 0x1B,
        "esc": 0x1B,
        "space": 0x20,
        "pageup": 0x21,
        "pagedown": 0x22,
        "end": 0x23,
        "home": 0x24,
        "left": 0x25,
        "up": 0x26,
        "right": 0x27,
        "down": 0x28,
        "delete": 0x2E,
        "win": 0x5B,
        "meta": 0x5B,
        **{chr(code).lower(): code for code in range(ord("A"), ord("Z") + 1)},
        **{str(number): 0x30 + number for number in range(10)},
        **{f"f{number}": 0x6F + number for number in range(1, 13)},
    }

    def _require_windows(self) -> None:
        if os.name != "nt":
            raise DesktopControlError("input_execution_failed", "Desktop input control requires Windows")

    def is_locked(self) -> bool:
        self._require_windows()
        user32 = ctypes.windll.user32
        desktop = user32.OpenInputDesktop(0, False, 0x0100)
        if not desktop:
            return True
        try:
            return not bool(user32.SwitchDesktop(desktop))
        finally:
            user32.CloseDesktop(desktop)

    def click(
        self,
        x: int,
        y: int,
        button: str,
        *,
        source_width: int | None = None,
        source_height: int | None = None,
    ) -> None:
        self._require_windows()
        user32 = ctypes.windll.user32
        width = int(user32.GetSystemMetrics(0))
        height = int(user32.GetSystemMetrics(1))
        if source_width is not None and source_height is not None:
            x, y = self.scale_point(
                x,
                y,
                source_width=source_width,
                source_height=source_height,
                target_width=width,
                target_height=height,
            )
        if not (0 <= x < width and 0 <= y < height):
            raise DesktopControlError("invalid_input", "Click coordinates are outside the primary display")
        if not user32.SetCursorPos(x, y):
            raise DesktopControlError("input_execution_failed", "Windows rejected the pointer position")
        down, up = (0x0002, 0x0004) if button == "left" else (0x0008, 0x0010)
        user32.mouse_event(down, 0, 0, 0, 0)
        user32.mouse_event(up, 0, 0, 0, 0)

    @staticmethod
    def scale_point(
        x: int,
        y: int,
        *,
        source_width: int,
        source_height: int,
        target_width: int,
        target_height: int,
    ) -> tuple[int, int]:
        if min(source_width, source_height, target_width, target_height) <= 0:
            raise DesktopControlError("invalid_input", "Desktop coordinate dimensions must be positive")
        if not (0 <= x < source_width and 0 <= y < source_height):
            raise DesktopControlError("invalid_input", "Click coordinates are outside the supplied coordinate space")
        target_x = 0 if target_width == 1 or source_width == 1 else round(
            x * (target_width - 1) / (source_width - 1)
        )
        target_y = 0 if target_height == 1 or source_height == 1 else round(
            y * (target_height - 1) / (source_height - 1)
        )
        return target_x, target_y

    def scroll(self, delta: int) -> None:
        self._require_windows()
        ctypes.windll.user32.mouse_event(0x0800, 0, 0, int(delta), 0)

    def window_switch(self, direction: str) -> None:
        keys = ["alt", "tab"] if direction == "next" else ["alt", "shift", "tab"]
        self.hotkey(keys)

    def select_file(self, path: str) -> None:
        self._require_windows()
        if self._foreground_window_class() != "#32770":
            raise DesktopControlError(
                "file_dialog_required",
                "A standard Windows file dialog must be active",
            )
        self.hotkey(["ctrl", "l"])
        self.type_text(path)
        self.hotkey(["enter"])

    def _foreground_window_class(self) -> str:
        self._require_windows()
        user32 = ctypes.windll.user32
        window = user32.GetForegroundWindow()
        if not window:
            return ""
        buffer = ctypes.create_unicode_buffer(256)
        if user32.GetClassNameW(window, buffer, len(buffer)) <= 0:
            return ""
        return buffer.value

    def hotkey(self, keys: list[str]) -> None:
        self._require_windows()
        try:
            codes = [self._VK[key] for key in keys]
        except KeyError as exc:
            raise DesktopControlError("invalid_input", f"Unsupported shortcut key: {exc.args[0]}") from exc
        user32 = ctypes.windll.user32
        for code in codes:
            user32.keybd_event(code, 0, 0, 0)
        for code in reversed(codes):
            user32.keybd_event(code, 0, 0x0002, 0)

    def type_text(self, text: str) -> None:
        self._require_windows()

        class KeyInput(ctypes.Structure):
            _fields_ = [
                ("wVk", ctypes.c_ushort),
                ("wScan", ctypes.c_ushort),
                ("dwFlags", ctypes.c_ulong),
                ("time", ctypes.c_ulong),
                ("dwExtraInfo", ctypes.POINTER(ctypes.c_ulong)),
            ]

        class InputUnion(ctypes.Union):
            _fields_ = [("ki", KeyInput)]

        class Input(ctypes.Structure):
            _anonymous_ = ("union",)
            _fields_ = [("type", ctypes.c_ulong), ("union", InputUnion)]

        extra = ctypes.c_ulong(0)
        events: list[Input] = []
        encoded = text.encode("utf-16-le")
        for index in range(0, len(encoded), 2):
            code_unit = int.from_bytes(encoded[index:index + 2], "little")
            events.append(Input(type=1, ki=KeyInput(0, code_unit, 0x0004, 0, ctypes.pointer(extra))))
            events.append(Input(type=1, ki=KeyInput(0, code_unit, 0x0004 | 0x0002, 0, ctypes.pointer(extra))))
        if events:
            array_type = Input * len(events)
            sent = ctypes.windll.user32.SendInput(len(events), array_type(*events), ctypes.sizeof(Input))
            if sent != len(events):
                raise DesktopControlError("input_execution_failed", "Windows did not accept the full text input")


def capture_desktop_screenshot() -> dict[str, Any]:
    if os.name != "nt":
        raise DesktopControlError("screen_capture_failed", "Desktop screen capture requires Windows")
    try:
        from PIL import ImageGrab
    except ImportError as exc:
        raise DesktopControlError("screen_capture_failed", "Pillow screen capture support is unavailable") from exc
    try:
        source = ImageGrab.grab(all_screens=False).convert("RGB")
    except Exception as exc:
        raise DesktopControlError("screen_capture_failed", str(exc) or "Windows screen capture failed") from exc
    original_width, original_height = source.size
    try:
        transport = compress_pil_image(source, MAX_SCREENSHOT_BYTES)
    finally:
        source.close()
    if transport is None:
        raise DesktopControlError("screenshot_too_large", "Desktop screenshot could not fit the encrypted transport limit")
    return {
        "image_mime": transport.mime_type,
        "image_base64": base64.b64encode(transport.data).decode("ascii"),
        "width": transport.width,
        "height": transport.height,
        "original_width": original_width,
        "original_height": original_height,
        "bytes": len(transport.data),
        "captured_at": int(time.time() * 1_000),
    }


_manager_lock = threading.RLock()
_manager: DesktopControlManager | None = None


def desktop_control_manager() -> DesktopControlManager:
    global _manager
    with _manager_lock:
        if _manager is None:
            _manager = DesktopControlManager()
        return _manager
