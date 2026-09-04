"""Canonical command catalog for the deterministic command plane.

The catalog is intentionally data-driven: adding roots or actions here creates
stable command contracts without adding UI buttons or prompt fallbacks.
"""
from __future__ import annotations

from .protocol import CommandDefinition


CORE_COMMANDS: tuple[CommandDefinition, ...] = (
    CommandDefinition(
        "commands.list",
        "commands",
        "list",
        "List registered GalaxySSI commands and handler availability.",
        aliases=("/commands",),
        parameters={"root": "optional command root filter"},
    ),
    CommandDefinition(
        "capabilities.list",
        "capabilities",
        "list",
        "Report command capability readiness without pretending missing runtimes are available.",
        aliases=("/capabilities",),
    ),
    CommandDefinition(
        "help.show",
        "help",
        "show",
        "Show structured help for a command or command root.",
        aliases=("/help",),
        parameters={"command": "optional command id, root, or slash command"},
    ),
    CommandDefinition(
        "file.list",
        "file",
        "list",
        "List files inside an approved workspace path.",
        aliases=("/file list",),
        parameters={"path": "workspace-relative directory", "limit": "maximum entries"},
    ),
    CommandDefinition(
        "file.read",
        "file",
        "read",
        "Read a text file inside an approved workspace path.",
        aliases=("/file read",),
        parameters={"path": "workspace-relative file path", "max_bytes": "read limit"},
    ),
    CommandDefinition(
        "file.write",
        "file",
        "write",
        "Atomically write a text file inside an approved workspace and snapshot the previous file.",
        risk="write",
        requires_approval=True,
        required_permission="workspace.write",
        aliases=("/file write",),
        parameters={"path": "workspace-relative file path", "content": "text content"},
    ),
    CommandDefinition(
        "file.move",
        "file",
        "move",
        "Move a file or directory inside the approved workspace with overwrite protection.",
        risk="write",
        requires_approval=True,
        required_permission="workspace.write",
        aliases=("/file move",),
        parameters={"source": "workspace-relative source path", "destination": "workspace-relative destination path", "overwrite": "allow replacing destination"},
    ),
    CommandDefinition(
        "file.copy",
        "file",
        "copy",
        "Copy a file or directory inside the approved workspace with overwrite protection.",
        risk="write",
        requires_approval=True,
        required_permission="workspace.write",
        aliases=("/file copy",),
        parameters={"source": "workspace-relative source path", "destination": "workspace-relative destination path", "overwrite": "allow replacing destination"},
    ),
    CommandDefinition(
        "file.delete",
        "file",
        "delete",
        "Soft-delete a workspace file or directory by moving it into the command snapshot area.",
        risk="high",
        requires_approval=True,
        required_permission="workspace.write",
        aliases=("/file delete",),
        parameters={"path": "workspace-relative file or directory path"},
    ),
    CommandDefinition(
        "file.mkdir",
        "file",
        "mkdir",
        "Create a directory inside the approved workspace.",
        risk="write",
        requires_approval=True,
        required_permission="workspace.write",
        aliases=("/file mkdir",),
        parameters={"path": "workspace-relative directory path"},
    ),
    CommandDefinition(
        "git.status",
        "git",
        "status",
        "Run git status using an argument array inside an approved workspace.",
        aliases=("/git status",),
        parameters={"path": "workspace-relative repository path"},
    ),
    CommandDefinition(
        "git.diff",
        "git",
        "diff",
        "Run git diff using an argument array inside an approved workspace.",
        aliases=("/git diff",),
        parameters={"path": "workspace-relative repository path", "max_bytes": "output limit"},
    ),
    CommandDefinition(
        "git.log",
        "git",
        "log",
        "Read recent git history using an argument array inside an approved workspace.",
        aliases=("/git log",),
        parameters={"path": "workspace-relative repository path", "limit": "maximum commits"},
    ),
    CommandDefinition(
        "git.branch",
        "git",
        "branch",
        "List git branches using an argument array inside an approved workspace.",
        aliases=("/git branch",),
        parameters={"path": "workspace-relative repository path"},
    ),
    CommandDefinition(
        "process.output",
        "process",
        "output",
        "Read stdout and stderr logs for a GalaxySSI-managed process.",
        aliases=("/process output",),
        parameters={"id": "managed process id", "max_bytes": "output limit"},
    ),
    CommandDefinition(
        "process.stdin",
        "process",
        "stdin",
        "Write a line to stdin for a GalaxySSI-managed process.",
        risk="high",
        requires_approval=True,
        required_permission="workspace.write",
        aliases=("/process stdin",),
        parameters={"id": "managed process id", "text": "stdin text"},
    ),
    CommandDefinition(
        "process.kill",
        "process",
        "kill",
        "Force-kill a GalaxySSI-managed process.",
        risk="high",
        requires_approval=True,
        required_permission="workspace.write",
        aliases=("/process kill",),
        parameters={"id": "managed process id"},
    ),
)

NATIVE_ROOTS = (
    "session", "context", "checkpoint", "task", "run", "goal", "plan",
    "agent", "memory", "knowledge", "config", "profile", "permission",
    "approval", "sandbox", "audit", "log", "usage", "backup", "reset",
    "migrate", "model", "schedule", "cron", "heartbeat", "watch", "trigger",
    "event", "queue", "artifact", "cache", "index", "policy", "template",
    "dataset", "workspace",
)

NATIVE_ACTIONS = (
    "create", "get", "list", "update", "delete", "status", "pause",
    "resume", "cancel", "retry", "checkpoint", "restore", "export", "clear",
)

TOOL_ROOTS = (
    "project", "test", "build", "lint", "format", "deploy", "release",
    "rollback", "shell", "process", "port", "service", "gateway", "tool",
    "mcp", "skill", "plugin", "document", "pr", "issue",
    "env", "archive", "checksum", "database", "python", "package",
)

TOOL_ACTIONS = (
    "status", "list", "run", "validate", "report", "start", "stop", "restart",
)

EXTERNAL_ROOTS = (
    "code", "research", "image", "homework", "screen", "team", "codex",
    "claude", "hermes", "openclaw", "device", "android", "browser", "web",
    "http", "remote", "node", "ssh", "scp", "channel", "message", "contact",
    "webhook", "smtp", "worker", "automation",
    "playwright", "chromium", "url", "dns", "camera", "microphone",
    "accessibility", "sensor", "notification", "location",
)

EXTERNAL_ACTIONS = (
    "status", "list", "run", "send", "receive", "search", "inspect", "sync",
)

HIGH_RISK_ACTIONS = {
    "delete", "clear", "restore", "rollback", "reset", "deploy", "release",
    "run", "start", "stop", "restart", "send", "sync",
}

HIGH_RISK_ROOT_ACTIONS = {
    ("ssh", "inspect"),
    ("scp", "receive"),
    ("node", "inspect"),
    ("python", "validate"),
    ("python", "report"),
}


def _risk(root: str, action: str) -> str:
    if action in HIGH_RISK_ACTIONS or (root, action) in HIGH_RISK_ROOT_ACTIONS:
        return "high"
    if action in {"create", "update", "checkpoint", "pause", "resume", "cancel", "retry"}:
        return "write"
    return "read"


def _generated_command(root: str, action: str, domain: str) -> CommandDefinition:
    risk = _risk(root, action)
    return CommandDefinition(
        f"{root}.{action}",
        root,
        action,
        f"{domain} command for {root} {action}.",
        risk=risk,  # type: ignore[arg-type]
        aliases=(f"/{root} {action}",),
        requires_approval=risk in {"write", "high"},
        required_permission=("workspace.write" if risk in {"write", "high"} else "workspace.read"),
        parameters={
            "id": "optional persistent entity id",
            "name": "optional entity name",
            "value": "optional structured value",
            "dry_run": "validate dispatch without side effects",
        },
    )


def _generated_commands() -> tuple[CommandDefinition, ...]:
    items: list[CommandDefinition] = []
    for root in NATIVE_ROOTS:
        for action in NATIVE_ACTIONS:
            items.append(_generated_command(root, action, "Native state"))
    for root in TOOL_ROOTS:
        for action in TOOL_ACTIONS:
            items.append(_generated_command(root, action, "Local tool"))
    for root in EXTERNAL_ROOTS:
        for action in EXTERNAL_ACTIONS:
            items.append(_generated_command(root, action, "External adapter"))
    return tuple(items)


COMMANDS: tuple[CommandDefinition, ...] = CORE_COMMANDS + _generated_commands()


ALIASES: dict[str, str] = {
    alias: command.command_id
    for command in COMMANDS
    for alias in command.aliases
}


def catalog_version() -> str:
    return "unified-command-foundation-v2"
