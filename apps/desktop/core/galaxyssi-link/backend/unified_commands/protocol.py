"""Structured command protocol shared by Desktop, Android, and agents."""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Literal
from uuid import uuid4

CommandStatus = Literal["completed", "failed", "denied", "unavailable", "not_found"]
CommandRisk = Literal["read", "write", "high"]


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


@dataclass(frozen=True)
class CommandDefinition:
    command_id: str
    root: str
    action: str
    summary: str
    risk: CommandRisk = "read"
    aliases: tuple[str, ...] = ()
    implemented: bool = True
    requires_approval: bool = False
    required_permission: str = ""
    parameters: dict[str, Any] = field(default_factory=dict)

    def public(self) -> dict[str, Any]:
        return {
            "command_id": self.command_id,
            "root": self.root,
            "action": self.action,
            "summary": self.summary,
            "risk": self.risk,
            "aliases": list(self.aliases),
            "implemented": self.implemented,
            "requires_approval": False,
            "required_permission": self.required_permission,
            "parameters": self.parameters,
        }


@dataclass(frozen=True)
class CommandRequest:
    command_id: str
    args: dict[str, Any] = field(default_factory=dict)
    source: str = "desktop"
    requested_by: str = "user"
    workspace: str = ""
    approve: bool = False
    run_id: str = ""
    raw: str = ""


@dataclass(frozen=True)
class CommandResult:
    status: CommandStatus
    command_id: str
    run_id: str
    data: dict[str, Any] = field(default_factory=dict)
    display: dict[str, Any] = field(default_factory=dict)
    error_code: str = ""
    message: str = ""
    started_at: str = ""
    completed_at: str = ""

    def public(self) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "status": self.status,
            "command_id": self.command_id,
            "run_id": self.run_id,
            "data": self.data,
            "display": self.display,
            "started_at": self.started_at,
            "completed_at": self.completed_at,
        }
        if self.error_code:
            payload["error_code"] = self.error_code
        if self.message:
            payload["message"] = self.message
        return payload


def new_run_id() -> str:
    return f"run-{uuid4().hex[:16]}"
