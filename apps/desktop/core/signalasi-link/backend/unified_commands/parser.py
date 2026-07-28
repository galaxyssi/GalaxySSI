"""Slash command parser for deterministic command dispatch."""
from __future__ import annotations

import shlex
from typing import Any

from .catalog import ALIASES
from .protocol import CommandRequest


class CommandParseError(ValueError):
    """Raised when a slash command cannot be parsed into a command contract."""


def parse_slash_command(value: str, *, source: str = "desktop", workspace: str = "", approve: bool = False) -> CommandRequest:
    raw = str(value or "").strip()
    if not raw.startswith("/"):
        raise CommandParseError("slash command must start with '/'")
    try:
        parts = shlex.split(raw, posix=True)
    except ValueError as exc:
        raise CommandParseError(str(exc)) from exc
    if not parts:
        raise CommandParseError("empty command")

    root = parts[0].removeprefix("/").strip().lower()
    action = ""
    remaining = parts[1:]
    if root in {"commands", "capabilities"}:
        command_id = f"{root}.list"
    elif root == "help":
        command_id = "help.show"
    else:
        if not remaining:
            raise CommandParseError("command action is required")
        action = remaining[0].strip().lower()
        remaining = remaining[1:]
        command_id = ALIASES.get(f"/{root} {action}", f"{root}.{action}")

    args: dict[str, Any] = {}
    positionals: list[str] = []
    index = 0
    approved = approve
    while index < len(remaining):
        token = remaining[index]
        if token == "--approve":
            approved = True
            index += 1
            continue
        if token.startswith("--"):
            key = token[2:].replace("-", "_")
            if not key:
                raise CommandParseError("empty option name")
            if index + 1 >= len(remaining) or remaining[index + 1].startswith("--"):
                args[key] = True
                index += 1
            else:
                args[key] = remaining[index + 1]
                index += 2
            continue
        positionals.append(token)
        index += 1

    if root == "help" and positionals and "command" not in args:
        args["command"] = positionals[0]
    elif root == "commands" and positionals and "root" not in args:
        args["root"] = positionals[0]
    elif root == "file" and positionals and "path" not in args:
        args["path"] = positionals[0]
    elif root == "git" and positionals and "path" not in args:
        args["path"] = positionals[0]
    elif positionals:
        args["query"] = " ".join(positionals)

    return CommandRequest(
        command_id=command_id,
        args=args,
        source=source,
        workspace=workspace,
        approve=approved,
        raw=raw,
    )
