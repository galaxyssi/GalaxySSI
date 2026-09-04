"""Unified command engine with parser, registry, security, run, and audit paths."""
from __future__ import annotations

from typing import Any

from .handlers import bind_handlers
from .parser import CommandParseError, parse_slash_command
from .protocol import CommandRequest, CommandResult, new_run_id, now_iso
from .registry import CommandRegistry
from .security import CommandDenied, require_approval
from .store import CommandStore, default_store_path


class UnifiedCommandEngine:
    def __init__(self, store: CommandStore | None = None):
        self.registry = CommandRegistry()
        self.store = store or CommandStore()
        bind_handlers(self.registry, self.store)

    def execute(self, request: CommandRequest) -> CommandResult:
        started = now_iso()
        request = CommandRequest(
            command_id=request.command_id,
            args=request.args,
            source=request.source,
            requested_by=request.requested_by,
            workspace=request.workspace,
            approve=request.approve,
            run_id=request.run_id or new_run_id(),
            raw=request.raw,
        )
        definition = self.registry.definition(request.command_id)
        if definition is None:
            result = CommandResult(
                "not_found",
                request.command_id,
                request.run_id,
                error_code="command_not_found",
                message="No deterministic handler is registered for this command.",
                started_at=started,
                completed_at=now_iso(),
            )
            self.store.record_run(request, result)
            return result
        handler = self.registry.handler(definition.command_id)
        if handler is None or not definition.implemented:
            result = CommandResult(
                "unavailable",
                definition.command_id,
                request.run_id,
                error_code="handler_unavailable",
                message="The command is registered but no deterministic handler is available.",
                started_at=started,
                completed_at=now_iso(),
            )
            self.store.record_run(request, result)
            return result
        try:
            require_approval(definition, request)
        except CommandDenied as exc:
            result = CommandResult(
                "denied",
                definition.command_id,
                request.run_id,
                error_code=exc.code,
                message=str(exc),
                started_at=started,
                completed_at=now_iso(),
            )
            self.store.record_run(request, result)
            return result
        if bool(request.args.get("dry_run")):
            result = CommandResult(
                "completed",
                definition.command_id,
                request.run_id,
                data={
                    "dry_run": True,
                    "command": definition.public(),
                    "handler": True,
                },
                display={"type": "command_dry_run"},
                started_at=started,
                completed_at=now_iso(),
            )
            self.store.record_run(request, result)
            return result
        try:
            self.store.record_audit(
                request.run_id,
                definition.command_id,
                "command_started",
                {"source": request.source, "risk": definition.risk},
                started,
            )
            result = handler(definition, request)
            result = CommandResult(
                result.status,
                result.command_id,
                request.run_id,
                data=result.data,
                display=result.display,
                error_code=result.error_code,
                message=result.message,
                started_at=started,
                completed_at=now_iso(),
            )
        except CommandDenied as exc:
            result = CommandResult(
                "denied",
                definition.command_id,
                request.run_id,
                error_code=exc.code,
                message=str(exc),
                started_at=started,
                completed_at=now_iso(),
            )
        except Exception as exc:
            result = CommandResult(
                "failed",
                definition.command_id,
                request.run_id,
                error_code="command_failed",
                message=str(exc)[:500],
                started_at=started,
                completed_at=now_iso(),
            )
        self.store.record_run(request, result)
        self.store.record_audit(
            request.run_id,
            definition.command_id,
            f"command_{result.status}",
            {"error_code": result.error_code, "message": result.message},
            result.completed_at,
        )
        return result

    def execute_payload(self, payload: dict[str, Any]) -> CommandResult:
        raw = str(payload.get("raw") or payload.get("slash") or "")
        if raw:
            try:
                request = parse_slash_command(
                    raw,
                    source=str(payload.get("source") or "desktop"),
                    workspace=str(payload.get("workspace") or ""),
                    approve=bool(payload.get("approve") or False),
                )
            except CommandParseError as exc:
                now = now_iso()
                return CommandResult(
                    "failed",
                    "parse",
                    new_run_id(),
                    error_code="command_parse_failed",
                    message=str(exc),
                    started_at=now,
                    completed_at=now,
                )
            return self.execute(request)
        return self.execute(
            CommandRequest(
                command_id=str(payload.get("command_id") or ""),
                args=dict(payload.get("args") or {}),
                source=str(payload.get("source") or "desktop"),
                requested_by=str(payload.get("requested_by") or "user"),
                workspace=str(payload.get("workspace") or ""),
                approve=bool(payload.get("approve") or False),
                raw=raw,
            )
        )

    def recent_runs(self, limit: int = 50) -> list[dict[str, Any]]:
        return self.store.recent_runs(limit)


_default_engine: UnifiedCommandEngine | None = None


def default_command_engine() -> UnifiedCommandEngine:
    global _default_engine
    configured_path = default_store_path()
    if _default_engine is None or _default_engine.store.path != configured_path:
        _default_engine = UnifiedCommandEngine(CommandStore(configured_path))
    return _default_engine
