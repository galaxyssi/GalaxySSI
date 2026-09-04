"""Protocol-aware MCP transports used by GalaxySSI Desktop."""
from __future__ import annotations

import json
import os
import queue
import subprocess
import threading
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from typing import Any, Callable


DEFAULT_PROTOCOL_VERSION = "2025-11-25"
SUPPORTED_PROTOCOL_VERSIONS = frozenset(
    {
        "2025-11-25",
        "2025-06-18",
        "2025-03-26",
        "2024-11-05",
    }
)
MAX_MESSAGE_BYTES = 8 * 1024 * 1024
MAX_TOOL_PAGES = 16
MAX_TOOLS = 512


class McpTransportError(RuntimeError):
    pass


@dataclass(frozen=True)
class McpClientConfig:
    transport: str
    timeout_seconds: float = 20.0
    protocol_version: str = DEFAULT_PROTOCOL_VERSION
    command: str = ""
    command_argv: tuple[str, ...] = ()
    process_environment: dict[str, str] = field(default_factory=dict)
    working_directory: str = ""
    stdio_framing: str = "newline"
    endpoint: str = ""
    request_headers: dict[str, str] = field(default_factory=dict)

    def __post_init__(self) -> None:
        if self.transport not in {"local_stdio", "streamable_http"}:
            raise ValueError(f"Unsupported MCP transport: {self.transport}")
        if self.protocol_version not in SUPPORTED_PROTOCOL_VERSIONS:
            raise ValueError(f"Unsupported MCP protocol version: {self.protocol_version}")
        if not 3 <= float(self.timeout_seconds) <= 300:
            raise ValueError("MCP timeout must be between 3 and 300 seconds")
        if (
            self.transport == "local_stdio"
            and not self.command.strip()
            and not self.command_argv
        ):
            raise ValueError("Local MCP requires a server command")
        if any(not str(value) or "\x00" in str(value) for value in self.command_argv):
            raise ValueError("Local MCP command arguments are invalid")
        if any(
            not str(key) or "\x00" in str(key) or "\x00" in str(value)
            for key, value in self.process_environment.items()
        ):
            raise ValueError("Local MCP process environment is invalid")
        if self.transport == "streamable_http" and not self.endpoint.strip():
            raise ValueError("Remote MCP requires an endpoint")
        if self.stdio_framing not in {"newline", "content_length"}:
            raise ValueError("Unsupported MCP stdio framing")


class _McpSession:
    def __init__(self, config: McpClientConfig) -> None:
        self.config = config
        self.initialization: dict[str, Any] = {}
        self.protocol_version = config.protocol_version
        self._next_id = 1

    def open(self) -> None:
        result = self.request(
            "initialize",
            {
                "protocolVersion": self.config.protocol_version,
                "capabilities": {},
                "clientInfo": {
                    "name": "galaxyssi-desktop",
                    "title": "GalaxySSI Desktop",
                    "version": "0.2",
                },
            },
        )
        selected = str(result.get("protocolVersion") or "")
        if selected not in SUPPORTED_PROTOCOL_VERSIONS:
            raise McpTransportError(
                f"MCP server selected unsupported protocol version: {selected or 'missing'}"
            )
        self.protocol_version = selected
        self.initialization = result
        self.notify("notifications/initialized")

    def request(self, method: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        request_id = self._next_id
        self._next_id += 1
        response = self._exchange(
            {
                "jsonrpc": "2.0",
                "id": request_id,
                "method": method,
                "params": params or {},
            },
            request_id=request_id,
        )
        if "error" in response:
            error = response.get("error") or {}
            message = str(error.get("message") or "MCP request failed")
            code = error.get("code")
            raise McpTransportError(f"{message} ({code})" if code is not None else message)
        result = response.get("result")
        if result is None:
            return {}
        if not isinstance(result, dict):
            raise McpTransportError(f"MCP {method} result must be an object")
        return result

    def notify(self, method: str, params: dict[str, Any] | None = None) -> None:
        self._exchange(
            {
                "jsonrpc": "2.0",
                "method": method,
                "params": params or {},
            },
            request_id=None,
        )

    def list_tools(self) -> list[dict[str, Any]]:
        tools: list[dict[str, Any]] = []
        cursor = ""
        for _page in range(MAX_TOOL_PAGES):
            result = self.request("tools/list", {"cursor": cursor} if cursor else {})
            page = result.get("tools") or []
            if not isinstance(page, list):
                raise McpTransportError("MCP server returned an invalid tool list")
            tools.extend(item for item in page if isinstance(item, dict))
            if len(tools) > MAX_TOOLS:
                raise McpTransportError("MCP server returned too many tools")
            cursor = str(result.get("nextCursor") or "")
            if not cursor:
                return tools
        raise McpTransportError("MCP tool pagination exceeded the bounded limit")

    def call_tool(self, name: str, arguments: dict[str, Any]) -> dict[str, Any]:
        return self.request(
            "tools/call",
            {
                "name": name,
                "arguments": arguments,
            },
        )

    def close(self) -> None:
        return None

    def _exchange(
        self,
        payload: dict[str, Any],
        *,
        request_id: int | None,
    ) -> dict[str, Any]:
        raise NotImplementedError


class _StdioSession(_McpSession):
    def __init__(
        self,
        config: McpClientConfig,
        on_process: Callable[[subprocess.Popen], None] | None = None,
    ) -> None:
        super().__init__(config)
        self.on_process = on_process
        self.process: subprocess.Popen | None = None
        self._incoming: queue.Queue[Any] = queue.Queue()
        self._stderr: list[str] = []
        self._write_lock = threading.Lock()

    def open(self) -> None:
        cwd = self.config.working_directory.strip() or None
        imported_argv = list(self.config.command_argv)
        environment = (
            _restricted_process_environment(self.config.process_environment)
            if imported_argv
            else os.environ.copy()
        )
        self.process = subprocess.Popen(
            imported_argv or self.config.command,
            shell=not bool(imported_argv),
            cwd=cwd,
            env=environment,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=False,
        )
        if self.on_process is not None:
            self.on_process(self.process)
        threading.Thread(target=self._read_stdout, daemon=True).start()
        threading.Thread(target=self._read_stderr, daemon=True).start()
        try:
            super().open()
        except Exception:
            self.close()
            raise

    def _exchange(
        self,
        payload: dict[str, Any],
        *,
        request_id: int | None,
    ) -> dict[str, Any]:
        self._write(payload)
        if request_id is None:
            return {}
        deadline = time.monotonic() + float(self.config.timeout_seconds)
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise McpTransportError(
                    f"Timed out waiting for MCP response{self._stderr_detail()}"
                )
            try:
                message = self._incoming.get(timeout=remaining)
            except queue.Empty as exc:
                raise McpTransportError(
                    f"Timed out waiting for MCP response{self._stderr_detail()}"
                ) from exc
            if isinstance(message, BaseException):
                raise McpTransportError(f"{message}{self._stderr_detail()}") from message
            if not isinstance(message, dict):
                continue
            if message.get("id") == request_id:
                return message
            if "method" in message and "id" in message:
                self._write(
                    {
                        "jsonrpc": "2.0",
                        "id": message.get("id"),
                        "error": {
                            "code": -32601,
                            "message": "GalaxySSI Desktop does not expose this client method",
                        },
                    }
                )

    def _write(self, payload: dict[str, Any]) -> None:
        process = self.process
        if process is None or process.stdin is None or process.poll() is not None:
            raise McpTransportError(f"MCP server is not running{self._stderr_detail()}")
        body = json.dumps(
            payload,
            ensure_ascii=False,
            separators=(",", ":"),
        ).encode("utf-8")
        if len(body) > MAX_MESSAGE_BYTES:
            raise McpTransportError("MCP request exceeds the message limit")
        framed = (
            f"Content-Length: {len(body)}\r\n\r\n".encode("ascii") + body
            if self.config.stdio_framing == "content_length"
            else body + b"\n"
        )
        with self._write_lock:
            process.stdin.write(framed)
            process.stdin.flush()

    def _read_stdout(self) -> None:
        try:
            process = self.process
            if process is None or process.stdout is None:
                return
            while True:
                if self.config.stdio_framing == "content_length":
                    message = self._read_content_length(process.stdout)
                else:
                    line = process.stdout.readline()
                    if not line:
                        break
                    if len(line) > MAX_MESSAGE_BYTES:
                        raise McpTransportError("MCP response exceeds the message limit")
                    message = json.loads(line.decode("utf-8"))
                self._incoming.put(message)
        except BaseException as exc:
            self._incoming.put(exc)
        finally:
            self._incoming.put(
                McpTransportError(
                    f"MCP server closed its output stream{self._stderr_detail()}"
                )
            )

    @staticmethod
    def _read_content_length(stream) -> dict[str, Any]:
        headers: dict[str, str] = {}
        while True:
            line = stream.readline()
            if not line:
                raise McpTransportError("MCP server closed its output stream")
            text = line.decode("ascii", errors="replace").strip()
            if not text:
                break
            if ":" in text:
                key, value = text.split(":", 1)
                headers[key.casefold()] = value.strip()
        try:
            length = int(headers["content-length"])
        except Exception as exc:
            raise McpTransportError("Invalid MCP Content-Length framing") from exc
        if length < 0 or length > MAX_MESSAGE_BYTES:
            raise McpTransportError("MCP response exceeds the message limit")
        body = stream.read(length)
        if len(body) != length:
            raise McpTransportError("MCP server closed during a framed response")
        return json.loads(body.decode("utf-8"))

    def _read_stderr(self) -> None:
        process = self.process
        if process is None or process.stderr is None:
            return
        for raw in iter(process.stderr.readline, b""):
            if sum(len(item) for item in self._stderr) >= 16_000:
                break
            self._stderr.append(raw.decode("utf-8", errors="replace"))

    def _stderr_detail(self) -> str:
        text = "".join(self._stderr).strip()
        return f": {text[-1_000:]}" if text else ""

    def close(self) -> None:
        process = self.process
        self.process = None
        if process is None:
            return
        try:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=2)
        except Exception:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=2)
        finally:
            for stream in (process.stdin, process.stdout, process.stderr):
                if stream is not None:
                    try:
                        stream.close()
                    except Exception:
                        pass


def _restricted_process_environment(configured: dict[str, str]) -> dict[str, str]:
    allowed = {
        "appdata",
        "comspec",
        "home",
        "homedrive",
        "homepath",
        "lang",
        "lc_all",
        "localappdata",
        "number_of_processors",
        "path",
        "pathext",
        "processor_architecture",
        "programdata",
        "systemdrive",
        "systemroot",
        "temp",
        "term",
        "tmp",
        "tmpdir",
        "userprofile",
        "windir",
    }
    environment = {
        str(key): str(value)
        for key, value in os.environ.items()
        if str(key).casefold() in allowed
    }
    environment.update(
        {
            str(key): str(value)
            for key, value in configured.items()
        }
    )
    return environment


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class _StreamableHttpSession(_McpSession):
    def __init__(self, config: McpClientConfig) -> None:
        super().__init__(config)
        self.session_id = ""
        self._opener = urllib.request.build_opener(_NoRedirect())

    def _exchange(
        self,
        payload: dict[str, Any],
        *,
        request_id: int | None,
    ) -> dict[str, Any]:
        body = json.dumps(
            payload,
            ensure_ascii=False,
            separators=(",", ":"),
        ).encode("utf-8")
        if len(body) > MAX_MESSAGE_BYTES:
            raise McpTransportError("MCP request exceeds the message limit")
        headers = {
            "Accept": "application/json, text/event-stream",
            "Content-Type": "application/json",
            "User-Agent": "GalaxySSI-Desktop-MCP/1",
            **self.config.request_headers,
        }
        if self.initialization:
            headers["MCP-Protocol-Version"] = self.protocol_version
        if self.session_id:
            headers["Mcp-Session-Id"] = self.session_id
        request = urllib.request.Request(
            self.config.endpoint,
            data=body,
            headers=headers,
            method="POST",
        )
        try:
            with self._opener.open(
                request,
                timeout=float(self.config.timeout_seconds),
            ) as response:
                session_id = str(response.headers.get("Mcp-Session-Id") or "").strip()
                if session_id:
                    self.session_id = session_id
                status = int(getattr(response, "status", 200))
                raw = response.read(MAX_MESSAGE_BYTES + 1)
                if len(raw) > MAX_MESSAGE_BYTES:
                    raise McpTransportError("MCP response exceeds the message limit")
                if request_id is None and status == 202:
                    return {}
                messages = _decode_http_messages(
                    raw,
                    str(response.headers.get("Content-Type") or ""),
                )
        except urllib.error.HTTPError as exc:
            detail = exc.read(2_000).decode("utf-8", errors="replace").strip()
            raise McpTransportError(
                f"MCP endpoint returned HTTP {exc.code}"
                + (f": {detail}" if detail else "")
            ) from exc
        except urllib.error.URLError as exc:
            raise McpTransportError(f"MCP endpoint is unavailable: {exc.reason}") from exc

        if request_id is None:
            return {}
        for message in messages:
            if message.get("id") == request_id:
                return message
        raise McpTransportError("MCP HTTP response did not contain the requested response")

    def close(self) -> None:
        if not self.session_id:
            return
        request = urllib.request.Request(
            self.config.endpoint,
            headers={
                **self.config.request_headers,
                "MCP-Protocol-Version": self.protocol_version,
                "Mcp-Session-Id": self.session_id,
            },
            method="DELETE",
        )
        try:
            self._opener.open(request, timeout=min(float(self.config.timeout_seconds), 5)).close()
        except Exception:
            pass
        finally:
            self.session_id = ""


def inspect_mcp(
    config: McpClientConfig,
    on_process: Callable[[subprocess.Popen], None] | None = None,
) -> dict[str, Any]:
    session = _open_session(config, on_process=on_process)
    try:
        tools = session.list_tools()
        initialization = session.initialization
        return {
            "protocol_version": session.protocol_version,
            "server_info": (
                initialization.get("serverInfo")
                if isinstance(initialization.get("serverInfo"), dict)
                else {}
            ),
            "capabilities": (
                initialization.get("capabilities")
                if isinstance(initialization.get("capabilities"), dict)
                else {}
            ),
            "instructions": str(initialization.get("instructions") or "")[:4_000],
            "tools": tools,
        }
    finally:
        session.close()


def call_mcp_tool(
    config: McpClientConfig,
    prompt: str,
    *,
    tool_name: str = "",
    argument_json: str = "",
    on_process: Callable[[subprocess.Popen], None] | None = None,
    before_call: Callable[[dict[str, Any], dict[str, Any]], None] | None = None,
) -> dict[str, Any]:
    session = _open_session(config, on_process=on_process)
    try:
        tools = session.list_tools()
        tool = (
            next((item for item in tools if item.get("name") == tool_name), None)
            if tool_name
            else tools[0] if tools else None
        )
        if tool is None:
            available = ", ".join(str(item.get("name") or "") for item in tools)
            raise McpTransportError(
                f"MCP tool not found: {tool_name}. Available: {available}"
            )
        arguments = _tool_arguments(tool, prompt, argument_json)
        if before_call is not None:
            before_call(tool, arguments)
        result = session.call_tool(str(tool.get("name") or ""), arguments)
        return {
            "text": _result_text(result),
            "tool": tool,
            "arguments": arguments,
            "raw_result": result,
            "protocol_version": session.protocol_version,
            "server_info": session.initialization.get("serverInfo") or {},
            "capabilities": session.initialization.get("capabilities") or {},
        }
    finally:
        session.close()


def _open_session(
    config: McpClientConfig,
    *,
    on_process: Callable[[subprocess.Popen], None] | None = None,
) -> _McpSession:
    session: _McpSession = (
        _StdioSession(config, on_process=on_process)
        if config.transport == "local_stdio"
        else _StreamableHttpSession(config)
    )
    session.open()
    return session


def _tool_arguments(
    tool: dict[str, Any],
    prompt: str,
    argument_json: str,
) -> dict[str, Any]:
    if argument_json:
        data = json.loads(argument_json)
        if not isinstance(data, dict):
            raise McpTransportError("MCP tool arguments must be a JSON object")
        return data
    schema = tool.get("inputSchema") or {}
    properties = schema.get("properties") if isinstance(schema, dict) else None
    if isinstance(properties, dict) and properties:
        for key in ("prompt", "input", "text", "query", "message"):
            if key in properties:
                return {key: prompt}
        return {next(iter(properties)): prompt}
    return {"prompt": prompt}


def _result_text(result: dict[str, Any]) -> str:
    content = result.get("content")
    if isinstance(content, list):
        parts: list[str] = []
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text":
                parts.append(str(item.get("text") or ""))
            elif isinstance(item, dict):
                parts.append(json.dumps(item, ensure_ascii=False))
            else:
                parts.append(str(item))
        text = "\n".join(part for part in parts if part).strip()
        if text:
            return text
    if "structuredContent" in result:
        return json.dumps(result["structuredContent"], ensure_ascii=False)
    return json.dumps(result, ensure_ascii=False)


def _decode_http_messages(raw: bytes, content_type: str) -> list[dict[str, Any]]:
    if not raw.strip():
        return []
    text = raw.decode("utf-8")
    if "text/event-stream" not in content_type.casefold():
        value = json.loads(text)
        if not isinstance(value, dict):
            raise McpTransportError("MCP HTTP response must be a JSON object")
        return [value]
    messages: list[dict[str, Any]] = []
    data: list[str] = []

    def flush() -> None:
        if not data:
            return
        payload = "\n".join(data).strip()
        data.clear()
        if not payload:
            return
        value = json.loads(payload)
        if isinstance(value, dict):
            messages.append(value)

    for raw_line in text.splitlines():
        line = raw_line.rstrip("\r")
        if not line:
            flush()
        elif line.startswith("data:"):
            data.append(line[5:].lstrip())
    flush()
    return messages
