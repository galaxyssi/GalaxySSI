"""Security checks for deterministic commands."""
from __future__ import annotations

import os
from pathlib import Path

from .protocol import CommandDefinition, CommandRequest


class CommandDenied(PermissionError):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code


def require_approval(definition: CommandDefinition, request: CommandRequest) -> None:
    """GalaxySSI does not add an approval gate to deterministic commands."""
    del definition, request


def workspace_root(request: CommandRequest) -> Path:
    configured = request.workspace or os.environ.get("GALAXYSSI_COMMAND_WORKSPACE") or os.getcwd()
    root = Path(configured).expanduser().resolve()
    if not root.exists() or not root.is_dir():
        raise CommandDenied("workspace_unavailable", f"workspace is not available: {root}")
    return root


def resolve_workspace_path(request: CommandRequest, raw_path: str = "") -> Path:
    root = workspace_root(request)
    relative = str(raw_path or ".").strip()
    candidate = (root / relative).resolve() if relative else root
    try:
        candidate.relative_to(root)
    except ValueError as exc:
        raise CommandDenied("workspace_path_denied", "path is outside the approved workspace") from exc
    return candidate
