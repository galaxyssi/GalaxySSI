"""Pairing-bound access profiles for GalaxySSI Desktop."""
from __future__ import annotations

import hashlib
import json
import re
import time
from pathlib import Path
from typing import Any, Mapping


CONTRACT_VERSION = "galaxyssi.pairing-access/1.0"
GRANT_VERSION = 1

RESTRICTED = "restricted"
DESKTOP_EXECUTOR = "desktop_executor"

AGENT_CHAT = "agent.chat"
EXPLICIT_ATTACHMENTS = "agent.attachments.explicit"
TASK_WORKSPACE = "desktop.task_workspace"
EXECUTOR_FULL = "desktop.executor.full"
DESKTOP_CONTROL = "desktop.control"
DESKTOP_NATIVE_TOOLS = "desktop.native_tools"
DESKTOP_EXTERNAL_FILES = "desktop.files.external"

RESTRICTED_SCOPES = (
    AGENT_CHAT,
    EXPLICIT_ATTACHMENTS,
    TASK_WORKSPACE,
)
EXECUTOR_SCOPES = (
    *RESTRICTED_SCOPES,
    EXECUTOR_FULL,
    DESKTOP_CONTROL,
    DESKTOP_NATIVE_TOOLS,
    DESKTOP_EXTERNAL_FILES,
)

_WINDOWS_PATH = re.compile(
    r"(?<![A-Za-z0-9_])(?:[A-Za-z]:[\\/][^\r\n\"'<>|?*]+|\\\\[^\r\n\"'<>|?*]+)"
)
_FILE_URI = re.compile(r"(?i)\bfile://[^\s\"'<>]+")
_POSIX_HOST_PATH = re.compile(r"(?<![A-Za-z0-9_])/(?:Users|home|etc|mnt|opt|root|var)/[^\s\"'<>]+")


def grant_for_executor(enabled: bool, *, issued_at_millis: int | None = None) -> dict[str, Any]:
    profile = DESKTOP_EXECUTOR if enabled else RESTRICTED
    return {
        "contract_version": CONTRACT_VERSION,
        "version": GRANT_VERSION,
        "profile": profile,
        "scopes": list(EXECUTOR_SCOPES if enabled else RESTRICTED_SCOPES),
        "desktop_executor": bool(enabled),
        "issued_at": int(issued_at_millis or time.time() * 1_000),
    }


def normalize_grant(value: Mapping[str, Any] | None) -> dict[str, Any]:
    source = dict(value or {})
    profile = (
        DESKTOP_EXECUTOR
        if source.get("profile") == DESKTOP_EXECUTOR and source.get("desktop_executor") is True
        else RESTRICTED
    )
    expected = EXECUTOR_SCOPES if profile == DESKTOP_EXECUTOR else RESTRICTED_SCOPES
    offered = {
        str(scope or "").strip()
        for scope in (source.get("scopes") or [])
        if str(scope or "").strip()
    }
    if profile == DESKTOP_EXECUTOR and not set(EXECUTOR_SCOPES).issubset(offered):
        profile = RESTRICTED
        expected = RESTRICTED_SCOPES
    scopes = list(expected)
    return {
        "contract_version": CONTRACT_VERSION,
        "version": GRANT_VERSION,
        "profile": profile,
        "scopes": scopes,
        "desktop_executor": profile == DESKTOP_EXECUTOR,
        "issued_at": int(source.get("issued_at") or time.time() * 1_000),
    }


def client_grant(client: Mapping[str, Any] | None) -> dict[str, Any]:
    source = dict(client or {})
    access = source.get("access")
    if isinstance(access, Mapping):
        return normalize_grant(access)
    return normalize_grant({
        "profile": source.get("access_profile"),
        "scopes": source.get("access_scopes"),
        "desktop_executor": source.get("access_profile") == DESKTOP_EXECUTOR,
        "issued_at": source.get("access_granted_at"),
    })


def has_scope(client: Mapping[str, Any] | None, scope: str) -> bool:
    return str(scope or "") in set(client_grant(client)["scopes"])


def has_full_executor(client: Mapping[str, Any] | None) -> bool:
    return has_scope(client, EXECUTOR_FULL)


def grant_binding(client: Mapping[str, Any] | None) -> str:
    """Bind a durable authorization to the exact server-issued pairing grant."""
    grant = client_grant(client)
    payload = {
        "contract_version": grant["contract_version"],
        "version": grant["version"],
        "profile": grant["profile"],
        "scopes": sorted(grant["scopes"]),
        "issued_at": grant["issued_at"],
    }
    encoded = json.dumps(
        payload,
        ensure_ascii=True,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def external_paths(text: str, allowed_roots: tuple[str | Path, ...] = ()) -> list[str]:
    candidates = []
    for pattern in (_WINDOWS_PATH, _FILE_URI, _POSIX_HOST_PATH):
        candidates.extend(match.group(0).rstrip(".,;:)]}") for match in pattern.finditer(str(text or "")))
    allowed = tuple(_normalized_path(root) for root in allowed_roots if str(root or "").strip())
    blocked = []
    for candidate in dict.fromkeys(candidates):
        normalized = _normalized_path(candidate.removeprefix("file://"))
        if allowed and any(normalized == root or normalized.startswith(f"{root}/") for root in allowed):
            continue
        blocked.append(candidate)
    return blocked


def apply_restricted_agent_boundary(prompt: str, workspace_root: str | Path) -> str:
    root_path = Path(workspace_root).resolve()
    root = str(root_path)
    safe_prompt = str(prompt or "").rstrip()
    blocked_paths = external_paths(safe_prompt, (root_path,))
    for blocked_path in blocked_paths:
        safe_prompt = safe_prompt.replace(blocked_path, "[blocked external Desktop path]")
    return (
        f"{safe_prompt}\n\n"
        "[GalaxySSI restricted pairing boundary]\n"
        f"- The only permitted Desktop file boundary is this task workspace: {root}\n"
        "- Use only files explicitly attached to this task or created inside that workspace.\n"
        "- Do not inspect, search, read, write, launch, or control anything elsewhere on the Desktop.\n"
        "- Do not request elevated permissions. Explain that Desktop Executor access requires re-pairing "
        "when the task needs capabilities outside this boundary.\n"
        f"- External Desktop path references removed from this request: {len(blocked_paths)}"
    )


def _normalized_path(value: str | Path) -> str:
    return str(value).replace("\\", "/").rstrip("/").casefold()
