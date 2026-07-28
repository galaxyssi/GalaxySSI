"""Managed local MCP connections for SignalASI Desktop."""
from __future__ import annotations

import argparse
import json
import os
import re
import threading
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

from mcp_agent_wrapper import call_mcp_detailed, list_mcp_tools
from mcp_security import (
    McpAuditStore,
    McpPermissionDenied,
    McpPermissionMode,
    McpToolAssessment,
    assess_mcp_tool,
    decide_mcp_permission,
    new_audit_record,
    normalize_permission_mode,
    sha256_json,
    source_fingerprint,
)


MCP_ID = re.compile(r"[a-z0-9][a-z0-9._-]{1,63}\Z")


def _state_path() -> Path:
    configured = str(os.environ.get("SIGNALASI_STATE_DIR") or "").strip()
    root = Path(configured) if configured else Path(os.environ.get("APPDATA") or Path.home()) / "SignalASI"
    return root / "desktop-mcp.json"


@dataclass(frozen=True)
class DesktopMcpConnection:
    id: str
    name: str
    command: str
    default_tool: str = ""
    triggers: tuple[str, ...] = ()
    enabled: bool = True
    auto_invoke: bool = False
    permission_mode: str = McpPermissionMode.ASK_FOR_CHANGES.value
    timeout_seconds: int = 20
    updated_at: int = 0

    def public(self, include_command: bool = False) -> dict[str, Any]:
        value = asdict(self)
        value["triggers"] = list(self.triggers)
        value["transport"] = "stdio"
        value["configured"] = bool(self.command)
        if not include_command:
            value.pop("command", None)
        return value


class DesktopMcpRegistry:
    def __init__(
        self,
        path: Path | None = None,
        audit_store: McpAuditStore | None = None,
    ) -> None:
        self.path = Path(path) if path else _state_path()
        self.audit_store = audit_store or McpAuditStore(
            self.path.with_name("mcp-tool-audit.json")
        )
        self._lock = threading.RLock()

    def list(self, include_command: bool = False) -> list[dict[str, Any]]:
        return [item.public(include_command) for item in self._load()]

    def get(self, connection_id: str) -> DesktopMcpConnection | None:
        return next((item for item in self._load() if item.id == str(connection_id)), None)

    def upsert(self, value: dict[str, Any]) -> dict[str, Any]:
        connection_id = str(value.get("id") or "").strip().casefold()
        if not MCP_ID.fullmatch(connection_id):
            raise ValueError("MCP connection id is invalid")
        name = str(value.get("name") or "").strip()[:80]
        command = str(value.get("command") or "").strip()[:4_000]
        default_tool = str(value.get("default_tool") or "").strip()[:160]
        triggers = tuple(dict.fromkeys(str(item).strip()[:80] for item in list(value.get("triggers") or []) if str(item).strip()))[:32]
        timeout = max(3, min(int(value.get("timeout_seconds") or 20), 120))
        if not name or not command:
            raise ValueError("MCP connection requires a name and stdio server command")
        connection = DesktopMcpConnection(
            id=connection_id,
            name=name,
            command=command,
            default_tool=default_tool,
            triggers=triggers,
            enabled=bool(value.get("enabled", True)),
            auto_invoke=bool(value.get("auto_invoke", False)),
            permission_mode=normalize_permission_mode(value.get("permission_mode")),
            timeout_seconds=timeout,
            updated_at=int(time.time() * 1_000),
        )
        with self._lock:
            rows = [item for item in self._load() if item.id != connection_id]
            rows.append(connection)
            self._save(rows)
        return connection.public(include_command=True)

    def delete(self, connection_id: str) -> bool:
        with self._lock:
            rows = self._load()
            updated = [item for item in rows if item.id != str(connection_id)]
            if len(rows) == len(updated):
                return False
            self._save(updated)
            self.audit_store.clear(str(connection_id))
            return True

    def match(self, prompt: str) -> DesktopMcpConnection | None:
        normalized = re.sub(r"\s+", " ", str(prompt or "")).casefold()
        ranked = []
        for item in self._load():
            if not item.enabled:
                continue
            explicitly_named = item.name.casefold() in normalized or item.id.casefold() in normalized
            score = sum(1 for trigger in item.triggers if trigger.casefold() in normalized) if item.auto_invoke else 0
            if explicitly_named:
                score += 2
            if score:
                ranked.append((score, item))
        return sorted(ranked, key=lambda pair: (-pair[0], pair[1].id))[0][1] if ranked else None

    @staticmethod
    def explicitly_named(connection: DesktopMcpConnection, prompt: str) -> bool:
        normalized = re.sub(r"\s+", " ", str(prompt or "")).casefold()
        return connection.name.casefold() in normalized or connection.id.casefold() in normalized

    def probe(self, connection_id: str) -> dict[str, Any]:
        connection = self._require(connection_id)
        started = time.monotonic()
        try:
            tools = list_mcp_tools(self._args(connection))
            return {
                "id": connection.id,
                "status": "ready",
                "duration_ms": round((time.monotonic() - started) * 1_000),
                "tools": [
                    self._public_tool(
                        item,
                        assess_mcp_tool(item, {}, transport="stdio"),
                    )
                    for item in tools[:200]
                ],
            }
        except Exception as exc:
            return {
                "id": connection.id,
                "status": "error",
                "duration_ms": round((time.monotonic() - started) * 1_000),
                "tools": [],
                "error": str(exc)[:500],
            }

    def invoke_prompt(
        self,
        connection_id: str,
        prompt: str,
        process_callback=None,
        *,
        explicit_user_selection: bool = False,
        audit_context: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        connection = self._require(connection_id)
        if not connection.enabled:
            raise RuntimeError("MCP connection is disabled")
        started = time.monotonic()
        assessment: McpToolAssessment | None = None
        permission_decision = None
        selected_tool = connection.default_tool
        context = dict(audit_context or {})

        def authorize(tool: dict[str, Any], arguments: dict[str, Any]) -> None:
            nonlocal assessment, permission_decision, selected_tool
            selected_tool = str(tool.get("name") or connection.default_tool or "unknown")
            assessment = assess_mcp_tool(tool, arguments, transport="stdio")
            permission_decision = decide_mcp_permission(
                connection.permission_mode,
                assessment,
                explicit_user_selection=explicit_user_selection,
            )
            if not permission_decision.allowed:
                raise McpPermissionDenied(permission_decision, assessment)

        try:
            detailed = call_mcp_detailed(
                self._args(connection),
                str(prompt or ""),
                on_process=process_callback,
                before_call=authorize,
            )
            result = str(detailed.get("text") or "")
            duration_ms = round((time.monotonic() - started) * 1_000)
            audit = self._append_audit(
                connection,
                selected_tool,
                assessment or assess_mcp_tool(
                    {"name": selected_tool},
                    dict(detailed.get("arguments") or {}),
                    transport="stdio",
                ),
                permission_decision.code if permission_decision else "allowed",
                context,
                status="succeeded",
                duration_ms=duration_ms,
                output_sha256=sha256_json({"result": result}),
            )
            return {
                "id": connection.id,
                "name": connection.name,
                "tool": selected_tool,
                "result": result,
                "duration_ms": duration_ms,
                "security": assessment.public() if assessment else {},
                "audit": audit,
            }
        except Exception as error:
            duration_ms = round((time.monotonic() - started) * 1_000)
            fallback = assessment or assess_mcp_tool(
                {"name": selected_tool or "unknown"},
                {"prompt": str(prompt or "")},
                transport="stdio",
            )
            decision_code = (
                error.decision.code
                if isinstance(error, McpPermissionDenied)
                else permission_decision.code if permission_decision else "execution_failed"
            )
            self._append_audit(
                connection,
                selected_tool or "unknown",
                fallback,
                decision_code,
                context,
                status="denied" if isinstance(error, McpPermissionDenied) else "failed",
                duration_ms=duration_ms,
                error_code=decision_code,
                error_message=str(error)[:500],
            )
            raise

    def audit(self, connection_id: str = "", limit: int = 100) -> list[dict[str, Any]]:
        return self.audit_store.list(connection_id=connection_id, limit=limit)

    def _append_audit(
        self,
        connection: DesktopMcpConnection,
        tool_name: str,
        assessment: McpToolAssessment,
        permission_decision: str,
        context: dict[str, Any],
        *,
        status: str,
        duration_ms: int,
        output_sha256: str = "",
        error_code: str = "",
        error_message: str = "",
    ) -> dict[str, Any]:
        return self.audit_store.append(new_audit_record(
            connection_id=connection.id,
            connection_name=connection.name,
            tool_name=str(tool_name or "unknown")[:160],
            transport="stdio",
            source=f"desktop-mcp:{connection.id}",
            source_sha256=source_fingerprint(connection.command),
            caller_id=str(context.get("caller_id") or "signalasi.desktop"),
            task_id=str(context.get("task_id") or ""),
            conversation_id=str(context.get("conversation_id") or ""),
            risk=assessment.risk,
            permissions=assessment.permissions,
            permission_mode=connection.permission_mode,
            permission_decision=permission_decision,
            parameter_preview=assessment.parameter_preview,
            input_sha256=assessment.input_sha256,
            status=status,
            duration_ms=max(0, int(duration_ms)),
            output_sha256=output_sha256,
            error_code=error_code,
            error_message=error_message,
        ))

    @staticmethod
    def _args(connection: DesktopMcpConnection) -> argparse.Namespace:
        return argparse.Namespace(
            server=connection.command,
            server_python=None,
            tool=connection.default_tool or None,
            arg_json=None,
            timeout=float(connection.timeout_seconds),
            stdio=True,
        )

    @staticmethod
    def _public_tool(
        value: dict[str, Any],
        assessment: McpToolAssessment | None = None,
    ) -> dict[str, Any]:
        return {
            "name": str(value.get("name") or "")[:160],
            "description": str(value.get("description") or "")[:1_000],
            "input_schema": value.get("inputSchema") if isinstance(value.get("inputSchema"), dict) else {},
            "security": assessment.public() if assessment else {},
        }

    def _require(self, connection_id: str) -> DesktopMcpConnection:
        connection = self.get(connection_id)
        if connection is None:
            raise KeyError(f"MCP connection not found: {connection_id}")
        return connection

    def _load(self) -> list[DesktopMcpConnection]:
        if not self.path.exists():
            return []
        try:
            data = json.loads(self.path.read_text(encoding="utf-8-sig"))
        except Exception:
            return []
        result: list[DesktopMcpConnection] = []
        for item in list(data.get("connections") or []):
            try:
                result.append(DesktopMcpConnection(
                    id=str(item["id"]), name=str(item["name"]), command=str(item["command"]),
                    default_tool=str(item.get("default_tool") or ""),
                    triggers=tuple(str(value) for value in list(item.get("triggers") or [])),
                    enabled=bool(item.get("enabled", True)),
                    auto_invoke=bool(item.get("auto_invoke", False)),
                    permission_mode=normalize_permission_mode(item.get("permission_mode")),
                    timeout_seconds=max(3, min(int(item.get("timeout_seconds") or 20), 120)),
                    updated_at=int(item.get("updated_at") or 0),
                ))
            except Exception:
                continue
        return result

    def _save(self, rows: list[DesktopMcpConnection]) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.path.with_suffix(self.path.suffix + ".tmp")
        temporary.write_text(
            json.dumps({"connections": [item.public(include_command=True) for item in rows]}, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        temporary.replace(self.path)


_MCP: DesktopMcpRegistry | None = None
_MCP_LOCK = threading.Lock()


def desktop_mcp_registry() -> DesktopMcpRegistry:
    global _MCP
    with _MCP_LOCK:
        if _MCP is None:
            _MCP = DesktopMcpRegistry()
        return _MCP
