"""Command registry and handler binding."""
from __future__ import annotations

from collections.abc import Callable
from typing import Any

from .catalog import COMMANDS
from .protocol import CommandDefinition, CommandRequest, CommandResult

CommandHandler = Callable[[CommandDefinition, CommandRequest], CommandResult]


class CommandRegistry:
    def __init__(self):
        self._definitions = {command.command_id: command for command in COMMANDS}
        self._handlers: dict[str, CommandHandler] = {}

    def register(self, command_id: str, handler: CommandHandler) -> None:
        if command_id not in self._definitions:
            raise KeyError(f"unknown command {command_id}")
        self._handlers[command_id] = handler

    def definition(self, command_id: str) -> CommandDefinition | None:
        return self._definitions.get(command_id)

    def handler(self, command_id: str) -> CommandHandler | None:
        return self._handlers.get(command_id)

    def list(self, root: str = "") -> list[dict[str, Any]]:
        commands = self._definitions.values()
        if root:
            commands = [command for command in commands if command.root == root]
        return [
            {
                **command.public(),
                "handler": command.command_id in self._handlers,
            }
            for command in sorted(commands, key=lambda item: item.command_id)
        ]

    def roots(self) -> list[str]:
        return sorted({command.root for command in self._definitions.values()})
