"""Managed local MCP connections for GalaxySSI Desktop."""
from __future__ import annotations

import argparse
import ipaddress
import json
import logging
import os
import re
import threading
import time
import uuid
from dataclasses import asdict, dataclass, replace
from pathlib import Path
from typing import Any, Callable
from urllib.parse import urlsplit, urlunsplit

from mcp_agent_wrapper import call_mcp_detailed, inspect_mcp_server
from mcp_security import (
    McpAuditStore,
    McpPermissionDenied,
    McpPermissionMode,
    McpToolAssessment,
    assess_mcp_tool,
    decide_mcp_permission,
    new_audit_record,
    normalize_permission_mode,
    sanitize_mcp_text,
    sha256_json,
    source_fingerprint,
)
from mcp_transport import DEFAULT_PROTOCOL_VERSION, SUPPORTED_PROTOCOL_VERSIONS
from tool_handle_registry import (
    DEFAULT_TTL_SECONDS,
    ToolHandleRegistry,
    ToolHandleScope,
    tool_handle_registry,
)


MCP_ID = re.compile(r"[a-z0-9][a-z0-9._-]{1,63}\Z")
HEADER_NAME = re.compile(r"[A-Za-z0-9!#$%&'*+.^_`|~-]{1,128}\Z")
ENVIRONMENT_NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]{0,127}\Z")
MCP_TRANSPORTS = {"local_stdio", "streamable_http"}
MCP_STATES = {"configured", "connecting", "ready", "error", "disabled"}
MAX_LIVE_PARAMETER_PREVIEW_BYTES = 4_096
MCP_HANDLE_KIND = "mcp_connection"
MCP_HANDLE_CAPABILITY = "mcp.invoke"


log = logging.getLogger("galaxyssi.desktop-mcp")


def _state_path() -> Path:
    configured = str(os.environ.get("GALAXYSSI_STATE_DIR") or "").strip()
    root = Path(configured) if configured else Path(os.environ.get("APPDATA") or Path.home()) / "GalaxySSI"
    return root / "desktop-mcp.json"


@dataclass(frozen=True)
class DesktopMcpConnection:
    id: str
    name: str
    transport: str = "local_stdio"
    command: str = ""
    command_argv: tuple[str, ...] = ()
    environment_env: tuple[tuple[str, str], ...] = ()
    endpoint: str = ""
    working_directory: str = ""
    header_env: tuple[tuple[str, str], ...] = ()
    header_templates: tuple[tuple[str, str], ...] = ()
    protocol_version: str = DEFAULT_PROTOCOL_VERSION
    stdio_framing: str = "newline"
    allow_insecure_http: bool = False
    default_tool: str = ""
    triggers: tuple[str, ...] = ()
    enabled: bool = True
    auto_invoke: bool = False
    permission_mode: str = McpPermissionMode.ASK_FOR_CHANGES.value
    timeout_seconds: int = 20
    state: str = "configured"
    last_probed_at: int = 0
    last_latency_ms: int = 0
    last_error: str = ""
    server_name: str = ""
    server_version: str = ""
    capabilities: tuple[str, ...] = ()
    tool_ids: tuple[str, ...] = ()
    import_source: str = ""
    updated_at: int = 0

    def public(self, include_configuration: bool = False) -> dict[str, Any]:
        value = asdict(self)
        value["triggers"] = list(self.triggers)
        value["command_argv"] = list(self.command_argv)
        value["environment_env"] = dict(self.environment_env)
        value["header_env"] = dict(self.header_env)
        value["header_templates"] = dict(self.header_templates)
        value["capabilities"] = list(self.capabilities)
        value["tool_ids"] = list(self.tool_ids)
        value["configured"] = bool(
            (self.command or self.command_argv)
            if self.transport == "local_stdio"
            else self.endpoint
        )
        if not include_configuration:
            value.pop("command", None)
            value.pop("command_argv", None)
            value.pop("environment_env", None)
            value.pop("working_directory", None)
            value.pop("header_env", None)
            value.pop("header_templates", None)
        return value


class DesktopMcpRegistry:
    def __init__(
        self,
        path: Path | None = None,
        audit_store: McpAuditStore | None = None,
        handle_registry: ToolHandleRegistry | None = None,
    ) -> None:
        self.path = Path(path) if path else _state_path()
        self.audit_store = audit_store or McpAuditStore(
            self.path.with_name("mcp-tool-audit.json")
        )
        self.handle_registry = handle_registry or tool_handle_registry()
        self._lock = threading.RLock()

    def list(
        self,
        include_command: bool = False,
        *,
        include_configuration: bool | None = None,
    ) -> list[dict[str, Any]]:
        include = include_command if include_configuration is None else include_configuration
        return [item.public(include) for item in self._load()]

    def get(self, connection_id: str) -> DesktopMcpConnection | None:
        return next((item for item in self._load() if item.id == str(connection_id)), None)

    def upsert(self, value: dict[str, Any]) -> dict[str, Any]:
        connection_id = str(value.get("id") or "").strip().casefold()
        if not MCP_ID.fullmatch(connection_id):
            raise ValueError("MCP connection id is invalid")
        name = str(value.get("name") or "").strip()[:80]
        transport = str(value.get("transport") or "local_stdio").strip().casefold()
        if transport == "stdio":
            transport = "local_stdio"
        if transport not in MCP_TRANSPORTS:
            raise ValueError("MCP transport is invalid")
        command = str(value.get("command") or "").strip()[:4_000]
        command_argv = _normalize_command_argv(value.get("command_argv"))
        environment_env = _normalize_environment_env(value.get("environment_env"))
        endpoint = _normalize_endpoint(
            value.get("endpoint"),
            allow_insecure_http=bool(value.get("allow_insecure_http", False)),
        ) if transport == "streamable_http" else ""
        working_directory = str(value.get("working_directory") or "").strip()[:1_000]
        if working_directory:
            working_directory = str(Path(working_directory).expanduser().resolve())
            if not Path(working_directory).is_dir():
                raise ValueError("MCP working directory does not exist")
        header_env = _normalize_header_env(value.get("header_env"))
        header_templates = _normalize_header_templates(
            value.get("header_templates"),
            header_env,
        )
        protocol_version = str(
            value.get("protocol_version") or DEFAULT_PROTOCOL_VERSION
        ).strip()
        if protocol_version not in SUPPORTED_PROTOCOL_VERSIONS:
            raise ValueError("MCP protocol version is unsupported")
        stdio_framing = str(value.get("stdio_framing") or "newline").strip().casefold()
        if stdio_framing not in {"newline", "content_length"}:
            raise ValueError("MCP stdio framing is invalid")
        default_tool = str(value.get("default_tool") or "").strip()[:160]
        triggers = tuple(dict.fromkeys(str(item).strip()[:80] for item in list(value.get("triggers") or []) if str(item).strip()))[:32]
        timeout = max(3, min(int(value.get("timeout_seconds") or 20), 300))
        if not name:
            raise ValueError("MCP connection requires a name")
        if transport == "local_stdio" and not command and not command_argv:
            raise ValueError("Local MCP requires a server command")
        if transport == "streamable_http" and not endpoint:
            raise ValueError("Remote MCP requires a Streamable HTTP endpoint")
        enabled = bool(value.get("enabled", True))
        existing = self.get(connection_id)
        connection = DesktopMcpConnection(
            id=connection_id,
            name=name,
            transport=transport,
            command=command,
            command_argv=tuple(command_argv),
            environment_env=tuple(sorted(environment_env.items())),
            endpoint=endpoint,
            working_directory=working_directory,
            header_env=tuple(sorted(header_env.items())),
            header_templates=tuple(sorted(header_templates.items())),
            protocol_version=protocol_version,
            stdio_framing=stdio_framing,
            allow_insecure_http=bool(value.get("allow_insecure_http", False)),
            default_tool=default_tool,
            triggers=triggers,
            enabled=enabled,
            auto_invoke=bool(value.get("auto_invoke", False)),
            permission_mode=normalize_permission_mode(value.get("permission_mode")),
            timeout_seconds=timeout,
            state="disabled" if not enabled else "configured",
            import_source=str(value.get("import_source") or "").strip().casefold()[:40],
            updated_at=int(time.time() * 1_000),
        )
        if existing is not None and _connection_target(existing) == _connection_target(connection):
            connection = replace(
                connection,
                state=existing.state if enabled else "disabled",
                last_probed_at=existing.last_probed_at,
                last_latency_ms=existing.last_latency_ms,
                last_error=existing.last_error,
                server_name=existing.server_name,
                server_version=existing.server_version,
                capabilities=existing.capabilities,
                tool_ids=existing.tool_ids,
            )
        with self._lock:
            rows = [item for item in self._load() if item.id != connection_id]
            rows.append(connection)
            self._save(rows)
        if existing is not None and (
            not enabled or _connection_target(existing) != _connection_target(connection)
        ):
            self.handle_registry.revoke_resource(MCP_HANDLE_KIND, connection_id)
        return connection.public(include_configuration=True)

    def delete(self, connection_id: str) -> bool:
        with self._lock:
            rows = self._load()
            updated = [item for item in rows if item.id != str(connection_id)]
            if len(rows) == len(updated):
                return False
            self._save(updated)
            self.audit_store.clear(str(connection_id))
            self.handle_registry.revoke_resource(
                MCP_HANDLE_KIND,
                str(connection_id),
            )
            return True

    def open_handle(
        self,
        connection_id: str,
        *,
        owner_id: str,
        context_id: str = "",
        parent_run_id: str = "",
        ttl_seconds: int = DEFAULT_TTL_SECONDS,
    ) -> dict[str, Any]:
        connection = self._require(connection_id)
        if not connection.enabled:
            raise RuntimeError("MCP connection is disabled")
        return self.handle_registry.create(
            kind=MCP_HANDLE_KIND,
            resource_id=connection.id,
            scope=ToolHandleScope(owner_id=owner_id, context_id=context_id),
            capabilities=[MCP_HANDLE_CAPABILITY],
            ttl_seconds=ttl_seconds,
            parent_run_id=parent_run_id,
            metadata={
                "connection_name": connection.name,
                "transport": connection.transport,
            },
        )

    def invoke_handle(
        self,
        handle_id: str,
        prompt: str,
        process_callback=None,
        *,
        owner_id: str,
        context_id: str = "",
        explicit_user_selection: bool = False,
        audit_context: dict[str, Any] | None = None,
        tool_call_callback: Callable[[dict[str, Any]], None] | None = None,
    ) -> dict[str, Any]:
        resolved = self.handle_registry.resolve(
            handle_id,
            kind=MCP_HANDLE_KIND,
            scope=ToolHandleScope(owner_id=owner_id, context_id=context_id),
            required_capability=MCP_HANDLE_CAPABILITY,
        )
        context = dict(audit_context or {})
        context.setdefault("caller_id", owner_id)
        result = self.invoke_prompt(
            str(resolved["resource_id"]),
            prompt,
            process_callback=process_callback,
            explicit_user_selection=explicit_user_selection,
            audit_context=context,
            tool_call_callback=tool_call_callback,
            tool_handle_id=str(resolved["handle_id"]),
        )
        return {
            **result,
            "mcp_handle_id": str(resolved["handle_id"]),
        }

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
        if not connection.enabled:
            raise RuntimeError("MCP connection is disabled")
        started = time.monotonic()
        self._record_runtime(connection.id, state="connecting", last_error="")
        try:
            inspection = inspect_mcp_server(self._args(connection))
            tools = list(inspection.get("tools") or [])
            server_info = (
                inspection.get("server_info")
                if isinstance(inspection.get("server_info"), dict)
                else {}
            )
            capabilities = (
                inspection.get("capabilities")
                if isinstance(inspection.get("capabilities"), dict)
                else {}
            )
            duration_ms = round((time.monotonic() - started) * 1_000)
            self._record_runtime(
                connection.id,
                state="ready",
                last_probed_at=int(time.time() * 1_000),
                last_latency_ms=duration_ms,
                last_error="",
                server_name=str(server_info.get("title") or server_info.get("name") or "")[:160],
                server_version=str(server_info.get("version") or "")[:80],
                capabilities=tuple(
                    sorted(str(name)[:80] for name in capabilities if str(name).strip())
                ),
                tool_ids=tuple(
                    sorted(
                        dict.fromkeys(
                            str(item.get("name") or "")[:160]
                            for item in tools
                            if str(item.get("name") or "").strip()
                        )
                    )
                ),
            )
            return {
                "id": connection.id,
                "status": "ready",
                "transport": connection.transport,
                "protocol_version": str(inspection.get("protocol_version") or ""),
                "duration_ms": duration_ms,
                "server_info": server_info,
                "capabilities": capabilities,
                "tools": [
                    self._public_tool(
                        item,
                        assess_mcp_tool(item, {}, transport=connection.transport),
                    )
                    for item in tools[:200]
                ],
            }
        except Exception as exc:
            duration_ms = round((time.monotonic() - started) * 1_000)
            self._record_runtime(
                connection.id,
                state="error",
                last_probed_at=int(time.time() * 1_000),
                last_latency_ms=duration_ms,
                last_error=sanitize_mcp_text(str(exc), 500),
            )
            return {
                "id": connection.id,
                "status": "error",
                "transport": connection.transport,
                "duration_ms": duration_ms,
                "tools": [],
                "error": sanitize_mcp_text(str(exc), 500),
            }

    def invoke_prompt(
        self,
        connection_id: str,
        prompt: str,
        process_callback=None,
        *,
        explicit_user_selection: bool = False,
        audit_context: dict[str, Any] | None = None,
        tool_call_callback: Callable[[dict[str, Any]], None] | None = None,
        tool_handle_id: str = "",
    ) -> dict[str, Any]:
        connection = self._require(connection_id)
        if not connection.enabled:
            raise RuntimeError("MCP connection is disabled")
        started = time.monotonic()
        invocation_id = str(uuid.uuid4())
        assessment: McpToolAssessment | None = None
        permission_decision = None
        selected_tool = connection.default_tool
        context = dict(audit_context or {})
        self._record_runtime(connection.id, state="connecting", last_error="")

        def publish_tool_call(status: str, *, duration_ms: int = 0, error: str = "") -> None:
            if tool_call_callback is None or assessment is None or permission_decision is None:
                return
            preview = assessment.parameter_preview
            encoded_preview = json.dumps(
                preview,
                ensure_ascii=False,
                separators=(",", ":"),
                default=str,
            )
            if len(encoded_preview.encode("utf-8")) > MAX_LIVE_PARAMETER_PREVIEW_BYTES:
                preview = {
                    "truncated": True,
                    "summary": sanitize_mcp_text(
                        encoded_preview,
                        MAX_LIVE_PARAMETER_PREVIEW_BYTES,
                    ),
                }
            event = {
                "kind": "mcp_tool_call",
                "invocation_id": invocation_id,
                "connection_id": connection.id,
                "connection_name": connection.name,
                "mcp_handle_id": str(tool_handle_id or ""),
                "tool_name": str(selected_tool or "unknown")[:160],
                "transport": connection.transport,
                "source": f"desktop-mcp:{connection.id}",
                "risk": assessment.risk,
                "permissions": list(assessment.permissions),
                "parameter_preview": preview,
                "input_sha256": assessment.input_sha256,
                "permission_mode": normalize_permission_mode(connection.permission_mode),
                "permission_decision": permission_decision.code,
                "allowed": bool(permission_decision.allowed),
                "required_user_action": permission_decision.required_user_action,
                "status": str(status or "running")[:32],
                "duration_ms": max(0, int(duration_ms)),
            }
            if error:
                event["error"] = sanitize_mcp_text(error, 500)
            try:
                tool_call_callback(event)
            except Exception as exc:
                log.warning(
                    "MCP tool-call event callback failed connection_id=%s invocation_id=%s: %s",
                    connection.id,
                    invocation_id,
                    exc,
                )

        def authorize(tool: dict[str, Any], arguments: dict[str, Any]) -> None:
            nonlocal assessment, permission_decision, selected_tool
            selected_tool = str(tool.get("name") or connection.default_tool or "unknown")
            assessment = assess_mcp_tool(tool, arguments, transport=connection.transport)
            permission_decision = decide_mcp_permission(
                connection.permission_mode,
                assessment,
                explicit_user_selection=explicit_user_selection,
            )
            publish_tool_call(
                "running" if permission_decision.allowed else "denied",
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
            server_info = (
                detailed.get("server_info")
                if isinstance(detailed.get("server_info"), dict)
                else {}
            )
            capabilities = (
                detailed.get("capabilities")
                if isinstance(detailed.get("capabilities"), dict)
                else {}
            )
            self._record_runtime(
                connection.id,
                state="ready",
                last_latency_ms=duration_ms,
                last_error="",
                server_name=str(server_info.get("title") or server_info.get("name") or "")[:160],
                server_version=str(server_info.get("version") or "")[:80],
                capabilities=tuple(
                    sorted(str(name)[:80] for name in capabilities if str(name).strip())
                ),
            )
            audit = self._append_audit(
                connection,
                selected_tool,
                assessment or assess_mcp_tool(
                    {"name": selected_tool},
                    dict(detailed.get("arguments") or {}),
                    transport=connection.transport,
                ),
                permission_decision.code if permission_decision else "allowed",
                context,
                status="succeeded",
                duration_ms=duration_ms,
                output_sha256=sha256_json({"result": result}),
            )
            publish_tool_call("succeeded", duration_ms=duration_ms)
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
                transport=connection.transport,
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
            publish_tool_call(
                "denied" if isinstance(error, McpPermissionDenied) else "failed",
                duration_ms=duration_ms,
                error=str(error),
            )
            if not isinstance(error, McpPermissionDenied):
                self._record_runtime(
                    connection.id,
                    state="error",
                    last_latency_ms=duration_ms,
                    last_error=sanitize_mcp_text(str(error), 500),
                )
            else:
                self._record_runtime(connection.id, state="ready")
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
            transport=connection.transport,
            source=f"desktop-mcp:{connection.id}",
            source_sha256=source_fingerprint(
                connection.command
                if connection.transport == "local_stdio"
                else connection.endpoint
            ),
            caller_id=str(context.get("caller_id") or "galaxyssi.desktop"),
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
        request_headers: dict[str, str] = {}
        header_templates = dict(connection.header_templates)
        for header, environment_name in connection.header_env:
            value = str(os.environ.get(environment_name) or "")
            if not value:
                raise RuntimeError(
                    f"MCP HTTP header {header} requires environment variable {environment_name}"
                )
            if len(value) > 8_192 or "\r" in value or "\n" in value:
                raise RuntimeError(
                    f"MCP HTTP header {header} has an unsafe environment value"
                )
            rendered = header_templates.get(
                header,
                "{value}",
            ).replace("{value}", value)
            if len(rendered) > 8_192 or "\r" in rendered or "\n" in rendered:
                raise RuntimeError(
                    f"MCP HTTP header {header} has an unsafe rendered value"
                )
            request_headers[header] = rendered
        process_environment: dict[str, str] = {}
        for child_name, environment_name in connection.environment_env:
            value = str(os.environ.get(environment_name) or "")
            if not value:
                raise RuntimeError(
                    f"MCP process variable {child_name} requires environment variable {environment_name}"
                )
            if len(value) > 65_536 or "\x00" in value:
                raise RuntimeError(
                    f"MCP process variable {child_name} has an unsafe environment value"
                )
            process_environment[child_name] = value
        return argparse.Namespace(
            server=connection.command,
            command_argv=list(connection.command_argv),
            process_environment=process_environment,
            server_python=None,
            tool=connection.default_tool or None,
            arg_json=None,
            timeout=float(connection.timeout_seconds),
            stdio=True,
            transport=connection.transport,
            endpoint=connection.endpoint,
            request_headers=request_headers,
            working_directory=connection.working_directory,
            protocol_version=connection.protocol_version,
            stdio_framing=connection.stdio_framing,
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

    def _record_runtime(self, connection_id: str, **changes: Any) -> None:
        with self._lock:
            rows = self._load()
            updated: list[DesktopMcpConnection] = []
            for item in rows:
                if item.id != connection_id:
                    updated.append(item)
                    continue
                allowed = {
                    key: value
                    for key, value in changes.items()
                    if key in {
                        "state",
                        "last_probed_at",
                        "last_latency_ms",
                        "last_error",
                        "server_name",
                        "server_version",
                        "capabilities",
                        "tool_ids",
                    }
                }
                if "state" in allowed and allowed["state"] not in MCP_STATES:
                    allowed.pop("state")
                updated.append(replace(item, **allowed))
            self._save(updated)

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
                    id=str(item["id"]),
                    name=str(item["name"]),
                    transport=str(item.get("transport") or "local_stdio"),
                    command=str(item.get("command") or ""),
                    command_argv=tuple(
                        str(value)
                        for value in list(item.get("command_argv") or [])
                    ),
                    environment_env=tuple(
                        sorted(
                            (str(key), str(value))
                            for key, value in dict(
                                item.get("environment_env") or {}
                            ).items()
                        )
                    ),
                    endpoint=str(item.get("endpoint") or ""),
                    working_directory=str(item.get("working_directory") or ""),
                    header_env=tuple(
                        sorted(
                            (str(key), str(value))
                            for key, value in dict(item.get("header_env") or {}).items()
                        )
                    ),
                    header_templates=tuple(
                        sorted(
                            (str(key), str(value))
                            for key, value in dict(
                                item.get("header_templates") or {}
                            ).items()
                        )
                    ),
                    protocol_version=str(item.get("protocol_version") or DEFAULT_PROTOCOL_VERSION),
                    stdio_framing=str(item.get("stdio_framing") or "newline"),
                    allow_insecure_http=bool(item.get("allow_insecure_http", False)),
                    default_tool=str(item.get("default_tool") or ""),
                    triggers=tuple(str(value) for value in list(item.get("triggers") or [])),
                    enabled=bool(item.get("enabled", True)),
                    auto_invoke=bool(item.get("auto_invoke", False)),
                    permission_mode=normalize_permission_mode(item.get("permission_mode")),
                    timeout_seconds=max(3, min(int(item.get("timeout_seconds") or 20), 300)),
                    state=str(item.get("state") or "configured"),
                    last_probed_at=int(item.get("last_probed_at") or 0),
                    last_latency_ms=int(item.get("last_latency_ms") or 0),
                    last_error=str(item.get("last_error") or "")[:500],
                    server_name=str(item.get("server_name") or "")[:160],
                    server_version=str(item.get("server_version") or "")[:80],
                    capabilities=tuple(str(value) for value in list(item.get("capabilities") or [])),
                    tool_ids=tuple(str(value) for value in list(item.get("tool_ids") or [])),
                    import_source=str(item.get("import_source") or ""),
                    updated_at=int(item.get("updated_at") or 0),
                ))
            except Exception:
                continue
        return result

    def _save(self, rows: list[DesktopMcpConnection]) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.path.with_suffix(self.path.suffix + ".tmp")
        temporary.write_text(
            json.dumps(
                {
                    "schema_version": 4,
                    "connections": [
                        item.public(include_configuration=True)
                        for item in rows
                    ],
                },
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        temporary.replace(self.path)


def _normalize_endpoint(value: Any, *, allow_insecure_http: bool) -> str:
    raw = str(value or "").strip()
    if not raw:
        return ""
    parsed = urlsplit(raw)
    if parsed.scheme.casefold() not in {"http", "https"} or not parsed.hostname:
        raise ValueError("MCP endpoint must be an HTTP or HTTPS URL")
    if parsed.username or parsed.password:
        raise ValueError("MCP endpoint must not contain credentials")
    if parsed.fragment:
        raise ValueError("MCP endpoint must not contain a fragment")
    if parsed.scheme.casefold() == "http" and not _is_loopback(parsed.hostname):
        if not allow_insecure_http:
            raise ValueError(
                "Remote HTTP MCP requires HTTPS unless insecure LAN access is explicitly enabled"
            )
    return urlunsplit(
        (
            parsed.scheme.casefold(),
            parsed.netloc,
            parsed.path or "/",
            parsed.query,
            "",
        )
    )


def _is_loopback(host: str) -> bool:
    if host.casefold() == "localhost":
        return True
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False


def _normalize_command_argv(value: Any) -> list[str]:
    if value in (None, ""):
        return []
    if not isinstance(value, (list, tuple)):
        raise ValueError("MCP command arguments must be an array")
    result = []
    for item in list(value)[:256]:
        argument = str(item)
        if not argument or "\x00" in argument or len(argument) > 4_000:
            raise ValueError("MCP command argument is invalid")
        result.append(argument)
    return result


def _normalize_environment_env(value: Any) -> dict[str, str]:
    if value in (None, ""):
        return {}
    if not isinstance(value, dict):
        raise ValueError("MCP process environment mapping must be an object")
    result: dict[str, str] = {}
    for raw_child, raw_environment in list(value.items())[:64]:
        child = str(raw_child or "").strip()
        environment = str(raw_environment or "").strip()
        if not ENVIRONMENT_NAME.fullmatch(child):
            raise ValueError(f"MCP process variable name is invalid: {child}")
        if not ENVIRONMENT_NAME.fullmatch(environment):
            raise ValueError(
                f"MCP process variable {child} requires a valid environment variable name"
            )
        result[child] = environment
    return result


def _normalize_header_env(value: Any) -> dict[str, str]:
    if value in (None, ""):
        return {}
    if not isinstance(value, dict):
        raise ValueError("MCP HTTP header environment mapping must be an object")
    result: dict[str, str] = {}
    for raw_header, raw_environment in list(value.items())[:32]:
        header = str(raw_header or "").strip()
        environment = str(raw_environment or "").strip()
        if not HEADER_NAME.fullmatch(header):
            raise ValueError(f"MCP HTTP header name is invalid: {header}")
        if header.casefold() in {
            "host",
            "content-length",
            "content-type",
            "accept",
            "mcp-session-id",
            "mcp-protocol-version",
        }:
            raise ValueError(f"MCP HTTP header is managed by GalaxySSI: {header}")
        if not ENVIRONMENT_NAME.fullmatch(environment):
            raise ValueError(
                f"MCP HTTP header {header} requires a valid environment variable name"
            )
        result[header] = environment
    return result


def _normalize_header_templates(
    value: Any,
    header_env: dict[str, str],
) -> dict[str, str]:
    if value in (None, ""):
        return {}
    if not isinstance(value, dict):
        raise ValueError("MCP HTTP header templates must be an object")
    result: dict[str, str] = {}
    for raw_header, raw_template in list(value.items())[:32]:
        header = str(raw_header or "").strip()
        template = str(raw_template or "")
        if header not in header_env:
            raise ValueError(f"MCP HTTP header template has no environment mapping: {header}")
        if (
            len(template) > 256
            or "\r" in template
            or "\n" in template
            or template.count("{value}") != 1
        ):
            raise ValueError(f"MCP HTTP header template is invalid: {header}")
        result[header] = template
    return result


def _connection_target(connection: DesktopMcpConnection) -> tuple[Any, ...]:
    return (
        connection.transport,
        connection.command,
        connection.command_argv,
        connection.environment_env,
        connection.endpoint,
        connection.working_directory,
        connection.header_env,
        connection.header_templates,
        connection.protocol_version,
        connection.stdio_framing,
        connection.allow_insecure_http,
        connection.import_source,
    )


_MCP: DesktopMcpRegistry | None = None
_MCP_LOCK = threading.Lock()


def desktop_mcp_registry() -> DesktopMcpRegistry:
    global _MCP
    with _MCP_LOCK:
        if _MCP is None:
            _MCP = DesktopMcpRegistry()
        return _MCP
