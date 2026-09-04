"""Safe import of common Claude, Codex, OpenClaw, and Hermes MCP configurations."""
from __future__ import annotations

import hashlib
import ipaddress
import json
import os
import re
import subprocess
import tomllib
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

import json5
import yaml


MAX_IMPORT_BYTES = 1_048_576
MAX_SERVERS = 128
SUPPORTED_SOURCE_HINTS = {
    "auto",
    "claude",
    "codex",
    "openclaw",
    "hermes",
    "mcp_json",
    "mcp_toml",
    "mcp_yaml",
}
ENVIRONMENT_NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]{0,127}\Z")
ENVIRONMENT_REFERENCE = re.compile(
    r"^(?:\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-[^}]*)?\}"
    r"|\$([A-Za-z_][A-Za-z0-9_]*)"
    r"|%([A-Za-z_][A-Za-z0-9_]*)%)$"
)
ENVIRONMENT_REFERENCE_TOKEN = re.compile(
    r"(?:\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-[^}]*)?\}"
    r"|\$([A-Za-z_][A-Za-z0-9_]*)"
    r"|%([A-Za-z_][A-Za-z0-9_]*)%)"
)
SENSITIVE_NAME = re.compile(
    r"(?:api[-_]?key|token|secret|password|passwd|credential|authorization|cookie)",
    re.IGNORECASE,
)
SAFE_IDENTIFIER = re.compile(r"[^a-z0-9._-]+")


class McpConfigImportError(ValueError):
    """Raised when an MCP import file cannot be interpreted safely."""


class _NoAliasSafeLoader(yaml.SafeLoader):
    """Safe YAML loader that rejects aliases to prevent expansion attacks."""

    def compose_node(self, parent, index):
        if self.check_event(yaml.AliasEvent):
            raise McpConfigImportError("YAML aliases are not supported in MCP imports.")
        return super().compose_node(parent, index)

    def construct_mapping(self, node, deep=False):
        self.flatten_mapping(node)
        result = {}
        for key_node, value_node in node.value:
            key = self.construct_object(key_node, deep=deep)
            try:
                duplicate = key in result
            except TypeError as exc:
                raise McpConfigImportError(
                    "YAML MCP configuration keys must be scalar values."
                ) from exc
            if duplicate:
                raise McpConfigImportError(
                    f"The MCP configuration contains a duplicate key: {key}"
                )
            result[key] = self.construct_object(value_node, deep=deep)
        return result


@dataclass(frozen=True)
class McpImportCandidate:
    connection: dict[str, Any]
    source: str
    importable: bool
    warnings: tuple[str, ...]
    missing_environment: tuple[str, ...]
    credential_references: int

    def public(self, existing_ids: set[str]) -> dict[str, Any]:
        connection = dict(self.connection)
        return {
            "id": connection["id"],
            "name": connection["name"],
            "source": self.source,
            "transport": connection["transport"],
            "command": connection.get("command", ""),
            "endpoint": connection.get("endpoint", ""),
            "enabled": bool(connection.get("enabled", True)),
            "permission_mode": connection.get("permission_mode", "ask_for_changes"),
            "importable": self.importable,
            "conflict": connection["id"] in existing_ids,
            "warnings": list(self.warnings),
            "missing_environment": list(self.missing_environment),
            "credential_references": self.credential_references,
        }


@dataclass(frozen=True)
class McpImportDocument:
    source: str
    digest: str
    candidates: tuple[McpImportCandidate, ...]

    def public(self, existing_ids: Iterable[str] = ()) -> dict[str, Any]:
        known = {str(value) for value in existing_ids}
        return {
            "source": self.source,
            "digest": self.digest,
            "candidates": [candidate.public(known) for candidate in self.candidates],
            "summary": {
                "total": len(self.candidates),
                "importable": sum(1 for value in self.candidates if value.importable),
                "blocked": sum(1 for value in self.candidates if not value.importable),
                "conflicts": sum(
                    1 for value in self.candidates if value.connection["id"] in known
                ),
            },
        }


def parse_mcp_import(
    content: str,
    *,
    source_hint: str = "auto",
    file_name: str = "",
    base_directory: str = "",
) -> McpImportDocument:
    raw = str(content or "")
    encoded = raw.encode("utf-8")
    if not raw.strip():
        raise McpConfigImportError("The MCP configuration file is empty.")
    if len(encoded) > MAX_IMPORT_BYTES:
        raise McpConfigImportError("The MCP configuration file is too large.")
    hint = str(source_hint or "auto").strip().casefold()
    if hint not in SUPPORTED_SOURCE_HINTS:
        raise McpConfigImportError("The MCP configuration source is unsupported.")

    normalized = raw.lstrip("\ufeff \t\r\n")
    config_format = _config_format(
        normalized,
        hint=hint,
        file_name=file_name,
    )
    try:
        if config_format == "json":
            data = json.loads(
                normalized,
                object_pairs_hook=_reject_duplicate_pairs,
            )
        elif config_format == "json5":
            data = json5.loads(normalized, allow_duplicate_keys=False)
        elif config_format == "yaml":
            data = yaml.load(normalized, Loader=_NoAliasSafeLoader)
        else:
            data = tomllib.loads(normalized)
    except (
        json.JSONDecodeError,
        tomllib.TOMLDecodeError,
        ValueError,
        yaml.YAMLError,
    ) as exc:
        raise McpConfigImportError(
            "The MCP configuration is not valid JSON, JSON5, TOML, or YAML."
        ) from exc
    if not isinstance(data, dict):
        raise McpConfigImportError("The MCP configuration root must be an object.")

    source = _detect_source(
        data,
        hint=hint,
        file_name=file_name,
        config_format=config_format,
    )
    raw_servers = _extract_servers(data)
    if not raw_servers:
        raise McpConfigImportError("No MCP servers were found in this configuration.")
    if len(raw_servers) > MAX_SERVERS:
        raise McpConfigImportError("The MCP configuration contains too many servers.")

    candidates: list[McpImportCandidate] = []
    used_ids: set[str] = set()
    for index, (raw_name, raw_server) in enumerate(raw_servers):
        if not isinstance(raw_server, dict):
            continue
        connection_id = _unique_id(_safe_id(raw_name or f"server-{index + 1}"), used_ids)
        candidates.append(
            _parse_server(
                connection_id,
                str(raw_name or connection_id),
                raw_server,
                source=source,
                base_directory=base_directory,
            )
        )
    if not candidates:
        raise McpConfigImportError("No supported MCP server entries were found.")
    return McpImportDocument(
        source=source,
        digest=hashlib.sha256(encoded).hexdigest(),
        candidates=tuple(candidates),
    )


def discover_mcp_config_sources(home: Path | None = None) -> list[dict[str, str]]:
    user_home = Path(home) if home else Path.home()
    appdata = Path(os.environ.get("APPDATA") or user_home / "AppData" / "Roaming")
    openclaw_state = Path(
        os.environ.get("OPENCLAW_STATE_DIR") or user_home / ".openclaw"
    )
    openclaw_config = Path(
        os.environ.get("OPENCLAW_CONFIG_PATH") or openclaw_state / "openclaw.json"
    )
    candidates = [
        ("claude", appdata / "Claude" / "claude_desktop_config.json"),
        ("claude", user_home / ".claude.json"),
        ("codex", user_home / ".codex" / "config.toml"),
        ("openclaw", openclaw_config),
        ("hermes", user_home / ".hermes" / "config.yaml"),
    ]
    result = []
    seen: set[str] = set()
    for source, path in candidates:
        resolved = str(path.resolve())
        if resolved.casefold() in seen or not path.is_file():
            continue
        try:
            size = path.stat().st_size
        except OSError:
            continue
        if size <= 0 or size > MAX_IMPORT_BYTES:
            continue
        seen.add(resolved.casefold())
        result.append(
            {
                "source": source,
                "path": resolved,
                "file_name": path.name,
            }
        )
    return result


def _detect_source(
    data: dict[str, Any],
    *,
    hint: str,
    file_name: str,
    config_format: str,
) -> str:
    if hint != "auto":
        return hint
    lower_name = Path(str(file_name or "")).name.casefold()
    if "claude" in lower_name:
        return "claude"
    if lower_name == ".mcp.json":
        return "mcp_json"
    if "openclaw" in lower_name:
        return "openclaw"
    if "hermes" in lower_name:
        return "hermes"
    if "codex" in lower_name:
        return "codex"
    if "mcp_servers" in data:
        return "hermes" if config_format == "yaml" else "codex"
    mcp = data.get("mcp")
    if isinstance(mcp, dict) and isinstance(mcp.get("servers"), dict):
        return "openclaw"
    if "mcpServers" in data:
        return {
            "yaml": "mcp_yaml",
            "toml": "mcp_toml",
        }.get(config_format, "mcp_json")
    return {
        "yaml": "mcp_yaml",
        "toml": "mcp_toml",
    }.get(config_format, "mcp_json")


def _extract_servers(data: dict[str, Any]) -> list[tuple[str, dict[str, Any]]]:
    standard = data.get("mcpServers")
    if isinstance(standard, dict):
        return [(str(name), value) for name, value in standard.items()]
    flat = data.get("mcp_servers")
    if isinstance(flat, dict):
        return [(str(name), value) for name, value in flat.items()]
    mcp = data.get("mcp")
    if isinstance(mcp, dict) and isinstance(mcp.get("servers"), dict):
        return [(str(name), value) for name, value in mcp["servers"].items()]
    return []


def _parse_server(
    connection_id: str,
    name: str,
    value: dict[str, Any],
    *,
    source: str,
    base_directory: str,
) -> McpImportCandidate:
    warnings: list[str] = []
    missing: set[str] = set()
    credential_references = 0
    importable = True
    command = str(value.get("command") or "").strip()
    url = str(value.get("url") or value.get("endpoint") or "").strip()
    transport_hint = str(value.get("transport") or value.get("type") or "").casefold()
    remote = bool(url) or transport_hint in {
        "http",
        "shttp",
        "sse",
        "streamable_http",
        "streamable-http",
    }

    connection: dict[str, Any] = {
        "id": connection_id,
        "name": str(name or connection_id).strip()[:80] or connection_id,
        "transport": "streamable_http" if remote else "local_stdio",
        "command": "",
        "command_argv": [],
        "endpoint": "",
        "working_directory": _working_directory(
            value.get("cwd") or value.get("working_directory"),
            base_directory,
        ),
        "environment_env": {},
        "header_env": {},
        "header_templates": {},
        "default_tool": "",
        "triggers": [],
        "enabled": bool(value.get("enabled", not bool(value.get("disabled", False)))),
        "auto_invoke": False,
        "permission_mode": _permission_mode(value),
        "timeout_seconds": _timeout_seconds(value),
        "allow_insecure_http": False,
        "import_source": source,
    }

    if _has_tool_filter(value):
        warnings.append(
            "Per-tool filters cannot be imported safely yet; configure this connection manually."
        )
        importable = False

    if remote:
        safe_url, url_safe, url_warnings = _sanitize_url(url)
        connection["endpoint"] = safe_url
        warnings.extend(url_warnings)
        importable = importable and url_safe and bool(safe_url)
        if transport_hint == "sse":
            warnings.append(
                "Legacy SSE transport needs a Streamable HTTP endpoint before it can be enabled."
            )
            importable = False
        (
            header_env,
            header_templates,
            header_missing,
            header_credentials,
        ) = _header_environment(
            connection_id,
            value,
        )
        connection["header_env"] = header_env
        connection["header_templates"] = header_templates
        missing.update(header_missing)
        credential_references += header_credentials
        if str(value.get("auth") or "").casefold() == "oauth":
            warnings.append(
                "OAuth credentials are not imported; authenticate this server separately."
            )
            importable = False
    else:
        args = _string_list(value.get("args"))
        argv, argv_safe, argv_warnings = _safe_argv(command, args)
        warnings.extend(argv_warnings)
        importable = importable and argv_safe and bool(argv)
        connection["command_argv"] = argv
        connection["command"] = subprocess.list2cmdline(argv) if argv else ""
        environment_env, env_missing, env_credentials = _process_environment(
            value.get("env"),
            value.get("env_vars"),
        )
        connection["environment_env"] = environment_env
        missing.update(env_missing)
        credential_references += env_credentials

    if not connection["enabled"]:
        warnings.append("The source configuration has this server disabled.")
    if missing:
        warnings.append(
            "Set the listed environment variables before testing this connection."
        )
    return McpImportCandidate(
        connection=connection,
        source=source,
        importable=importable,
        warnings=tuple(dict.fromkeys(warnings)),
        missing_environment=tuple(sorted(missing)),
        credential_references=credential_references,
    )


def _safe_argv(
    command: str,
    args: list[str],
) -> tuple[list[str], bool, list[str]]:
    if not command:
        return [], False, ["A local MCP server command is missing."]
    values = [command, *args]
    warnings: list[str] = []
    safe = True
    redacted: list[str] = []
    redact_next = False
    for index, raw in enumerate(values):
        value = str(raw)
        if "\x00" in value or len(value) > 4_000:
            return [], False, ["The local MCP command contains an invalid argument."]
        if index > 0 and (redact_next or _argument_contains_secret(value)):
            redacted.append("<credential-not-imported>")
            redact_next = False
            safe = False
            continue
        redacted.append(value)
        if index > 0 and value.startswith("-") and SENSITIVE_NAME.search(value):
            redact_next = "=" not in value
            if "=" in value:
                redacted[-1] = value.split("=", 1)[0] + "=<credential-not-imported>"
                safe = False
    if not safe:
        warnings.append(
            "A credential embedded in command arguments was removed; use an environment variable instead."
        )
    return redacted, safe, warnings


def _working_directory(value: Any, base_directory: str) -> str:
    raw = str(value or "").strip()
    if not raw:
        return ""
    path = Path(raw).expanduser()
    if not path.is_absolute() and str(base_directory or "").strip():
        path = Path(base_directory).expanduser() / path
    return str(path.resolve())[:1_000]


def _argument_contains_secret(value: str) -> bool:
    parsed = urlsplit(value)
    if parsed.scheme in {"http", "https"}:
        return any(SENSITIVE_NAME.search(key) for key, _item in parse_qsl(parsed.query))
    return bool("=" in value and SENSITIVE_NAME.search(value.split("=", 1)[0]))


def _process_environment(
    value: Any,
    forwarded: Any = None,
) -> tuple[dict[str, str], set[str], int]:
    result: dict[str, str] = {}
    missing: set[str] = set()
    references = 0
    if isinstance(value, dict):
        for raw_name, raw_value in list(value.items())[:64]:
            name = str(raw_name or "").strip()
            if not ENVIRONMENT_NAME.fullmatch(name):
                continue
            source = _environment_reference(raw_value) or name
            result[name] = source
    if isinstance(forwarded, list):
        for item in forwarded[:64]:
            name = (
                str(item.get("name") or "").strip()
                if isinstance(item, dict)
                else str(item or "").strip()
            )
            if ENVIRONMENT_NAME.fullmatch(name):
                result[name] = name
    for source in result.values():
        references += 1
        if not os.environ.get(source):
            missing.add(source)
    return result, missing, references


def _header_environment(
    connection_id: str,
    value: dict[str, Any],
) -> tuple[dict[str, str], dict[str, str], set[str], int]:
    result: dict[str, str] = {}
    templates: dict[str, str] = {}
    missing: set[str] = set()
    references = 0
    mapped = value.get("env_http_headers")
    if isinstance(mapped, dict):
        for raw_header, raw_environment in list(mapped.items())[:32]:
            header = str(raw_header or "").strip()
            environment = str(raw_environment or "").strip()
            if header and ENVIRONMENT_NAME.fullmatch(environment):
                result[header] = environment
                templates[header] = "{value}"
    headers = value.get("headers") or value.get("http_headers")
    if isinstance(headers, dict):
        for raw_header, raw_value in list(headers.items())[:32]:
            header = str(raw_header or "").strip()
            if not header:
                continue
            environment, template = _header_environment_reference(raw_value)
            if not environment:
                environment = _generated_environment_name(connection_id, header)
                template = "{value}"
            result[header] = environment
            templates[header] = template
    bearer = str(value.get("bearer_token_env_var") or "").strip()
    if ENVIRONMENT_NAME.fullmatch(bearer):
        result["Authorization"] = bearer
        templates["Authorization"] = "Bearer {value}"
    if value.get("api_key") not in (None, "") and "Authorization" not in result:
        result["Authorization"] = _generated_environment_name(
            connection_id,
            "authorization",
        )
        templates["Authorization"] = "Bearer {value}"
    for environment in result.values():
        references += 1
        if not os.environ.get(environment):
            missing.add(environment)
    return result, templates, missing, references


def _environment_reference(value: Any) -> str:
    if isinstance(value, dict):
        source = str(value.get("source") or "").strip().casefold()
        identifier = str(value.get("id") or "").strip()
        return identifier if source == "env" and ENVIRONMENT_NAME.fullmatch(identifier) else ""
    match = ENVIRONMENT_REFERENCE.fullmatch(str(value or "").strip())
    if not match:
        return ""
    return next((part for part in match.groups() if part), "")


def _header_environment_reference(value: Any) -> tuple[str, str]:
    direct = _environment_reference(value)
    if direct:
        return direct, "{value}"
    if not isinstance(value, str):
        return "", ""
    matches = list(ENVIRONMENT_REFERENCE_TOKEN.finditer(value))
    if len(matches) != 1:
        return "", ""
    match = matches[0]
    environment = next((part for part in match.groups() if part), "")
    if not environment:
        return "", ""
    template = f"{value[:match.start()]}{{value}}{value[match.end():]}"
    if (
        len(template) > 256
        or "\r" in template
        or "\n" in template
        or template.count("{value}") != 1
    ):
        return "", ""
    return environment, template


def _generated_environment_name(connection_id: str, name: str) -> str:
    suffix = re.sub(r"[^A-Za-z0-9]+", "_", name).strip("_").upper() or "SECRET"
    prefix = re.sub(r"[^A-Za-z0-9]+", "_", connection_id).strip("_").upper()
    return f"GALAXYSSI_MCP_{prefix}_{suffix}"[:128]


def _sanitize_url(value: str) -> tuple[str, bool, list[str]]:
    if not value:
        return "", False, ["A remote MCP endpoint is missing."]
    try:
        parsed = urlsplit(value)
    except ValueError:
        return "", False, ["The remote MCP endpoint is invalid."]
    if parsed.scheme.casefold() not in {"http", "https"} or not parsed.hostname:
        return "", False, ["The remote MCP endpoint must use HTTP or HTTPS."]
    safe = True
    warnings: list[str] = []
    if parsed.username or parsed.password:
        safe = False
        warnings.append(
            "Credentials embedded in the endpoint were removed; use an environment-backed header."
        )
    if parsed.scheme.casefold() == "http" and not _loopback_host(parsed.hostname):
        safe = False
        warnings.append(
            "Plain HTTP outside localhost was not imported; use HTTPS or configure trusted LAN access manually."
        )
    query = []
    for key, item in parse_qsl(parsed.query, keep_blank_values=True):
        if SENSITIVE_NAME.search(key):
            safe = False
            warnings.append(
                "Credential-like endpoint parameters were removed; use an environment-backed header."
            )
            continue
        query.append((key, item))
    host = parsed.hostname or ""
    if ":" in host:
        host = f"[{host}]"
    try:
        if parsed.port:
            host = f"{host}:{parsed.port}"
    except ValueError:
        return "", False, ["The remote MCP endpoint contains an invalid port."]
    return (
        urlunsplit(
            (
                parsed.scheme.casefold(),
                host,
                parsed.path or "/",
                urlencode(query),
                "",
            )
        ),
        safe,
        list(dict.fromkeys(warnings)),
    )


def _loopback_host(host: str) -> bool:
    if str(host or "").casefold() == "localhost":
        return True
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False


def _permission_mode(value: dict[str, Any]) -> str:
    codex = value.get("codex")
    scoped = (
        codex.get("defaultToolsApprovalMode")
        if isinstance(codex, dict)
        else ""
    )
    raw = str(
        value.get("permission_mode")
        or value.get("default_tools_approval_mode")
        or scoped
        or ""
    ).casefold()
    if raw in {"trusted", "approve"}:
        return "trusted"
    if raw in {"read_only", "readonly"}:
        return "read_only"
    if raw == "disabled":
        return "disabled"
    return "ask_for_changes"


def _timeout_seconds(value: dict[str, Any]) -> int:
    raw = (
        value.get("tool_timeout_sec")
        or value.get("timeout")
        or value.get("connectTimeout")
        or value.get("startup_timeout_sec")
    )
    if raw in (None, ""):
        milliseconds = (
            value.get("requestTimeoutMs")
            or value.get("connectionTimeoutMs")
        )
        try:
            raw = float(milliseconds) / 1_000 if milliseconds not in (None, "") else 20
        except (TypeError, ValueError):
            raw = 20
    try:
        return max(3, min(int(float(raw)), 300))
    except (TypeError, ValueError):
        return 20


def _string_list(value: Any) -> list[str]:
    if value is None:
        return []
    if not isinstance(value, list):
        raise McpConfigImportError("MCP command arguments must be an array.")
    result = []
    for item in value[:256]:
        if not isinstance(item, (str, int, float, bool)):
            raise McpConfigImportError("MCP command arguments must contain only scalar values.")
        result.append(str(item))
    return result


def _config_format(normalized: str, *, hint: str, file_name: str) -> str:
    suffix = Path(str(file_name or "")).suffix.casefold()
    lower_name = Path(str(file_name or "")).name.casefold()
    if hint == "hermes" or suffix in {".yaml", ".yml"}:
        return "yaml"
    if hint == "openclaw" or suffix == ".json5" or lower_name == "openclaw.json":
        return "json5"
    if normalized.startswith("{"):
        return "json"
    return "toml"


def _has_tool_filter(value: dict[str, Any]) -> bool:
    tools = value.get("tools")
    if isinstance(tools, dict) and any(
        key in tools for key in ("include", "exclude", "allowed", "blocked")
    ):
        return True
    return any(
        key in value
        for key in (
            "allowedTools",
            "allowed_tools",
            "blockedTools",
            "blocked_tools",
        )
    )


def _reject_duplicate_pairs(pairs: Iterable[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise McpConfigImportError(
                f"The MCP configuration contains a duplicate key: {key}"
            )
        result[key] = value
    return result


def _safe_id(value: Any) -> str:
    normalized = SAFE_IDENTIFIER.sub("-", str(value or "").strip().casefold())
    normalized = normalized.strip(".-_")[:64]
    if len(normalized) < 2:
        normalized = f"mcp-{normalized or 'server'}"
    return normalized[:64]


def _unique_id(value: str, used: set[str]) -> str:
    candidate = value
    suffix = 2
    while candidate in used:
        marker = f"-{suffix}"
        candidate = f"{value[:64 - len(marker)]}{marker}"
        suffix += 1
    used.add(candidate)
    return candidate
