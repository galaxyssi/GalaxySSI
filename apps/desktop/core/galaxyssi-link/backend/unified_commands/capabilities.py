"""Side-effect-free readiness probes for the unified command catalog."""
from __future__ import annotations

import json
import os
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

from .catalog import NATIVE_ROOTS
from .protocol import CommandDefinition

CapabilityStatus = Literal[
    "ready",
    "needs_input",
    "needs_configuration",
    "missing_runtime",
    "unsupported",
]


@dataclass(frozen=True)
class CommandCapability:
    command_id: str
    status: CapabilityStatus
    implementation: str
    handler_bound: bool
    risk: str
    requires_approval: bool
    reason: str = ""
    required_inputs: tuple[str, ...] = ()
    required_runtime: str = ""
    required_configuration: str = ""

    def public(self) -> dict:
        return {
            "command_id": self.command_id,
            "status": self.status,
            "implementation": self.implementation,
            "registered": True,
            "handler_bound": self.handler_bound,
            "risk": self.risk,
            "requires_approval": self.requires_approval,
            "reason": self.reason,
            "required_inputs": list(self.required_inputs),
            "required_runtime": self.required_runtime,
            "required_configuration": self.required_configuration,
        }


TOOL_SUPPORTED_ACTIONS: dict[str, frozenset[str]] = {
    "project": frozenset({"status", "list", "validate", "report"}),
    "test": frozenset({"status", "list", "run", "validate", "report"}),
    "build": frozenset({"status", "list", "run", "validate", "report"}),
    "lint": frozenset({"status", "list", "run", "validate", "report"}),
    "format": frozenset({"status", "list", "run", "validate", "report"}),
    "deploy": frozenset({"status", "list", "run", "validate", "report", "start"}),
    "release": frozenset({"status", "list", "run", "validate", "report", "start"}),
    "rollback": frozenset({"status", "list", "run", "validate", "report", "start"}),
    "shell": frozenset({"status", "list", "run", "validate", "report"}),
    "process": frozenset({"status", "list", "run", "validate", "report", "start", "stop", "restart"}),
    "port": frozenset({"status", "list", "validate", "report"}),
    "service": frozenset({"status", "list", "run", "validate", "report", "start", "stop", "restart"}),
    "gateway": frozenset({"status", "list", "run", "validate", "report", "start", "stop", "restart"}),
    "tool": frozenset({"status", "list", "validate", "report"}),
    "mcp": frozenset({"status", "list", "validate", "report"}),
    "skill": frozenset({"status", "list", "validate", "report"}),
    "plugin": frozenset({"status", "list", "validate", "report"}),
    "document": frozenset({"status", "list", "validate", "report"}),
    "pr": frozenset({"status", "list", "validate", "report"}),
    "issue": frozenset({"status", "list", "validate", "report"}),
    "env": frozenset({"status", "list", "run", "validate", "report"}),
    "archive": frozenset({"status", "list", "run", "validate", "report", "start"}),
    "checksum": frozenset({"status", "list", "run", "validate", "report"}),
    "database": frozenset({"status", "list", "validate", "report"}),
    "python": frozenset({"status", "list", "run", "validate", "report"}),
    "package": frozenset({"status", "list", "run", "validate", "report"}),
}

EXTERNAL_SUPPORTED_ACTIONS: dict[str, frozenset[str]] = {
    "web": frozenset({"status", "list", "run", "send", "receive", "search", "inspect", "sync"}),
    "http": frozenset({"status", "list", "run", "send", "receive", "search", "inspect", "sync"}),
    "url": frozenset({"status", "list", "run", "send", "receive", "search", "inspect", "sync"}),
    "dns": frozenset({"status", "list", "run", "send", "receive", "search", "inspect", "sync"}),
    "browser": frozenset({"status", "list", "run", "send", "search", "inspect"}),
    "playwright": frozenset({"status", "list", "run", "send", "search", "inspect"}),
    "chromium": frozenset({"status", "list", "run", "send", "search", "inspect"}),
    "device": frozenset({"status", "list", "run", "send", "inspect", "sync"}),
    "android": frozenset({"status", "list", "run", "send", "inspect", "sync"}),
    "camera": frozenset({"status", "list", "inspect"}),
    "microphone": frozenset({"status", "list", "inspect"}),
    "accessibility": frozenset({"status", "list", "inspect"}),
    "sensor": frozenset({"status", "list", "inspect"}),
    "notification": frozenset({"status", "list", "inspect"}),
    "location": frozenset({"status", "list", "inspect"}),
    "ssh": frozenset({"status", "list", "run", "inspect"}),
    "scp": frozenset({"status", "list", "run", "send", "receive", "sync"}),
    "node": frozenset({"status", "list", "run", "inspect"}),
    "webhook": frozenset({"status", "list", "run", "send", "sync"}),
    "smtp": frozenset({"status", "list", "send"}),
    "channel": frozenset({"status", "list", "run", "send", "receive", "search", "inspect", "sync"}),
    "message": frozenset({"status", "list", "run", "send", "receive", "search", "inspect", "sync"}),
    "contact": frozenset({"status", "list", "run", "send", "receive", "search", "inspect", "sync"}),
    "worker": frozenset({"status", "list", "run", "send", "receive", "search", "inspect", "sync"}),
    "automation": frozenset({"status", "list", "run", "send", "receive", "search", "inspect", "sync"}),
}

EXTERNAL_HISTORY_ACTIONS: dict[str, frozenset[str]] = {
    "accessibility": frozenset({"receive", "search"}),
    "android": frozenset({"receive", "search"}),
    "browser": frozenset({"receive"}),
    "camera": frozenset({"receive", "search"}),
    "chromium": frozenset({"receive"}),
    "claude": frozenset({"inspect", "receive", "search"}),
    "code": frozenset({"inspect", "receive", "search"}),
    "codex": frozenset({"inspect", "receive", "search"}),
    "device": frozenset({"receive", "search"}),
    "hermes": frozenset({"inspect", "receive", "search"}),
    "homework": frozenset({"inspect", "receive", "search"}),
    "image": frozenset({"inspect", "receive", "search"}),
    "location": frozenset({"receive", "search"}),
    "microphone": frozenset({"receive", "search"}),
    "node": frozenset({"receive", "search"}),
    "notification": frozenset({"receive", "search"}),
    "openclaw": frozenset({"inspect", "receive", "search"}),
    "playwright": frozenset({"receive"}),
    "remote": frozenset({"inspect", "receive", "search"}),
    "research": frozenset({"inspect", "receive", "search"}),
    "scp": frozenset({"inspect", "search"}),
    "screen": frozenset({"inspect", "receive", "search"}),
    "sensor": frozenset({"receive", "search"}),
    "smtp": frozenset({"inspect", "receive", "search"}),
    "ssh": frozenset({"receive", "search"}),
    "team": frozenset({"inspect", "receive", "search"}),
    "webhook": frozenset({"inspect", "receive", "search"}),
}

for _root, _actions in EXTERNAL_HISTORY_ACTIONS.items():
    EXTERNAL_SUPPORTED_ACTIONS[_root] = (
        EXTERNAL_SUPPORTED_ACTIONS.get(_root, frozenset({"status", "list"}))
        | _actions
    )

CORE_REQUIRED_INPUTS: dict[str, tuple[str, ...]] = {
    "file.read": ("path",),
    "file.write": ("path", "content"),
    "file.move": ("source", "destination"),
    "file.copy": ("source", "destination"),
    "file.delete": ("path",),
    "file.mkdir": ("path",),
    "process.output": ("id",),
    "process.stdin": ("id", "text"),
    "process.kill": ("id",),
}

TOOL_REQUIRED_INPUTS: dict[tuple[str, str], tuple[str, ...]] = {
    ("shell", "run"): ("argv",),
    ("process", "start"): ("argv",),
    ("process", "stop"): ("id",),
    ("process", "restart"): ("id",),
    ("process", "run"): ("id",),
    ("service", "start"): ("id", "argv"),
    ("service", "stop"): ("id",),
    ("service", "restart"): ("id",),
    ("service", "run"): ("id",),
    ("gateway", "start"): ("id", "argv"),
    ("gateway", "stop"): ("id",),
    ("gateway", "restart"): ("id",),
    ("gateway", "run"): ("id",),
    ("port", "status"): ("port",),
    ("port", "validate"): ("port",),
    ("port", "report"): ("port",),
    ("env", "run"): ("argv",),
    ("archive", "run"): ("path",),
    ("archive", "start"): ("path",),
    ("checksum", "run"): ("path",),
    ("checksum", "validate"): ("path",),
    ("checksum", "report"): ("path",),
    ("python", "run"): ("code",),
    ("python", "validate"): ("code",),
    ("python", "report"): ("code",),
}

EXTERNAL_REQUIRED_INPUTS: dict[tuple[str, str], tuple[str, ...]] = {
    **{
        (root, action): ("url",)
        for root in ("web", "http", "url", "browser", "playwright", "chromium", "webhook")
        for action in ("run", "send", "receive", "search", "inspect", "sync")
    },
    **{
        ("dns", action): ("host",)
        for action in ("run", "send", "receive", "search", "inspect", "sync")
    },
    ("device", "run"): ("argv",),
    ("device", "send"): ("text",),
    ("android", "run"): ("argv",),
    ("android", "send"): ("text",),
    ("ssh", "run"): ("host", "argv"),
    ("ssh", "inspect"): ("host", "argv"),
    ("scp", "run"): ("source", "destination"),
    ("scp", "send"): ("source", "destination"),
    ("scp", "receive"): ("source", "destination"),
    ("scp", "sync"): ("source", "destination"),
    ("node", "run"): ("code",),
    ("node", "inspect"): ("code",),
    ("smtp", "send"): ("host", "from", "to"),
}

for _root, _actions in EXTERNAL_HISTORY_ACTIONS.items():
    for _action in _actions:
        EXTERNAL_REQUIRED_INPUTS.pop((_root, _action), None)

SCRIPT_ROOTS = frozenset({"test", "build", "lint", "format", "deploy", "release", "rollback", "package"})
SCRIPT_DEFAULTS = {
    "test": "check",
    "build": "check:android",
    "lint": "check",
    "format": "format",
    "deploy": "deploy",
    "release": "release",
    "rollback": "rollback",
    "package": "check",
}


def _workspace(workspace: str) -> Path:
    configured = workspace or os.environ.get("GALAXYSSI_COMMAND_WORKSPACE") or os.getcwd()
    return Path(configured).expanduser().resolve()


def _package_scripts(root: Path) -> set[str]:
    package_json = root / "package.json"
    if not package_json.is_file():
        return set()
    try:
        payload = json.loads(package_json.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return set()
    scripts = payload.get("scripts")
    return set(scripts) if isinstance(scripts, dict) else set()


def _capability(
    definition: CommandDefinition,
    handler_bound: bool,
    status: CapabilityStatus,
    implementation: str,
    reason: str,
    *,
    required_inputs: tuple[str, ...] = (),
    required_runtime: str = "",
    required_configuration: str = "",
) -> CommandCapability:
    return CommandCapability(
        command_id=definition.command_id,
        status=status,
        implementation=implementation,
        handler_bound=handler_bound,
        risk=definition.risk,
        requires_approval=False,
        reason=reason,
        required_inputs=required_inputs,
        required_runtime=required_runtime,
        required_configuration=required_configuration,
    )


def _runtime_capability(
    definition: CommandDefinition,
    handler_bound: bool,
    implementation: str,
    runtime: str,
    required_inputs: tuple[str, ...] = (),
) -> CommandCapability | None:
    executable = shutil.which(runtime)
    if executable:
        return None
    return _capability(
        definition,
        handler_bound,
        "missing_runtime",
        implementation,
        f"{definition.command_id} requires {runtime} on PATH.",
        required_inputs=required_inputs,
        required_runtime=runtime,
    )


def _core_capability(
    definition: CommandDefinition,
    handler_bound: bool,
    workspace: Path,
) -> CommandCapability:
    command_id = definition.command_id
    if command_id.startswith("git."):
        missing = _runtime_capability(definition, handler_bound, "native_tool", "git")
        if missing:
            return missing
        if not (workspace / ".git").exists():
            return _capability(
                definition,
                handler_bound,
                "needs_configuration",
                "native_tool",
                "Select a Git repository workspace.",
                required_configuration="git_repository",
            )
    required_inputs = CORE_REQUIRED_INPUTS.get(command_id, ())
    return _capability(
        definition,
        handler_bound,
        "needs_input" if required_inputs else "ready",
        "native_tool",
        "Deterministic native handler is available.",
        required_inputs=required_inputs,
    )


def _native_state_capability(
    definition: CommandDefinition,
    handler_bound: bool,
) -> CommandCapability:
    required_inputs = ("id",) if definition.action in {"get", "delete"} else ()
    return _capability(
        definition,
        handler_bound,
        "needs_input" if required_inputs else "ready",
        "sqlite_state_service",
        "Command state is persisted in the unified command SQLite store.",
        required_inputs=required_inputs,
    )


def _tool_capability(
    definition: CommandDefinition,
    handler_bound: bool,
    workspace: Path,
) -> CommandCapability:
    root = definition.root
    action = definition.action
    supported = TOOL_SUPPORTED_ACTIONS.get(root, frozenset())
    if action not in supported:
        return _capability(
            definition,
            handler_bound,
            "unsupported",
            "registered_only",
            f"No deterministic {root}.{action} execution contract is implemented.",
        )

    required_inputs = TOOL_REQUIRED_INPUTS.get((root, action), ())
    if root in SCRIPT_ROOTS and action in {"run", "start"}:
        npm = "npm.cmd" if os.name == "nt" else "npm"
        missing = _runtime_capability(definition, handler_bound, "native_tool", npm)
        if missing:
            return missing
        selected_script = SCRIPT_DEFAULTS[root]
        if selected_script not in _package_scripts(workspace):
            return _capability(
                definition,
                handler_bound,
                "needs_configuration",
                "native_tool",
                f"Workspace package.json does not define the {selected_script} script.",
                required_configuration=f"package_script:{selected_script}",
            )
    if root in {"pr", "issue"}:
        missing = _runtime_capability(definition, handler_bound, "external_cli", "gh")
        if missing:
            return missing
        if not (workspace / ".git").exists():
            return _capability(
                definition,
                handler_bound,
                "needs_configuration",
                "external_cli",
                "Select a Git repository workspace before querying GitHub.",
                required_configuration="git_repository",
            )
    if root == "port" and action == "list":
        runtime = "netstat" if shutil.which("netstat") else "ss"
        missing = _runtime_capability(definition, handler_bound, "native_tool", runtime)
        if missing:
            return missing
    return _capability(
        definition,
        handler_bound,
        "needs_input" if required_inputs else "ready",
        "native_tool",
        "Deterministic local tool handler is available.",
        required_inputs=required_inputs,
    )


def _external_capability(
    definition: CommandDefinition,
    handler_bound: bool,
) -> CommandCapability:
    root = definition.root
    action = definition.action
    supported = EXTERNAL_SUPPORTED_ACTIONS.get(root)
    if supported is None:
        if action in {"status", "list"}:
            return _capability(
                definition,
                handler_bound,
                "ready",
                "readiness_probe",
                "Runtime detection is available, but execution is not wired to this command plane.",
            )
        return _capability(
            definition,
            handler_bound,
            "unsupported",
            "registered_only",
            f"{root}.{action} is registered but has no provider-specific execution adapter.",
        )
    if action not in supported:
        return _capability(
            definition,
            handler_bound,
            "unsupported",
            "registered_only",
            f"No deterministic {root}.{action} execution contract is implemented.",
        )

    required_inputs = EXTERNAL_REQUIRED_INPUTS.get((root, action), ())
    runtime = ""
    if root in {"device", "android"}:
        runtime = "adb"
    elif root == "ssh":
        runtime = "ssh"
    elif root == "scp":
        runtime = "scp"
    elif root == "node":
        runtime = "node"
    if runtime:
        missing = _runtime_capability(
            definition,
            handler_bound,
            "external_adapter",
            runtime,
            required_inputs,
        )
        if missing:
            return missing

    return _capability(
        definition,
        handler_bound,
        "needs_input" if required_inputs else "ready",
        "external_adapter",
        "Deterministic adapter entry point is available.",
        required_inputs=required_inputs,
    )


def probe_command_capability(
    definition: CommandDefinition,
    *,
    handler_bound: bool,
    workspace: str = "",
) -> CommandCapability:
    if not definition.implemented or not handler_bound:
        return _capability(
            definition,
            handler_bound,
            "unsupported",
            "registered_only",
            "No deterministic handler is bound.",
        )
    root = _workspace(workspace)
    if definition.command_id in {
        "commands.list",
        "capabilities.list",
        "help.show",
        "file.list",
        "file.read",
        "file.write",
        "file.move",
        "file.copy",
        "file.delete",
        "file.mkdir",
        "git.status",
        "git.diff",
        "git.log",
        "git.branch",
        "process.output",
        "process.stdin",
        "process.kill",
    }:
        return _core_capability(definition, handler_bound, root)
    if definition.root in NATIVE_ROOTS:
        return _native_state_capability(definition, handler_bound)
    if definition.root in TOOL_SUPPORTED_ACTIONS:
        return _tool_capability(definition, handler_bound, root)
    return _external_capability(definition, handler_bound)
