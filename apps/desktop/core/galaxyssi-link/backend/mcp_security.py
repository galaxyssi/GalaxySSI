"""Permission decisions, redaction, and durable audit records for MCP tools."""
from __future__ import annotations

import hashlib
import json
import os
import re
import threading
import time
import uuid
from dataclasses import asdict, dataclass
from enum import Enum
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit, urlunsplit


AUDIT_SCHEMA_VERSION = 1
MAX_AUDIT_RECORDS = 2_000
MAX_PARAMETER_DEPTH = 6
MAX_PARAMETER_ITEMS = 64
MAX_PARAMETER_STRING = 320


class McpPermissionMode(str, Enum):
    READ_ONLY = "read_only"
    ASK_FOR_CHANGES = "ask_for_changes"
    TRUSTED = "trusted"
    DISABLED = "disabled"


class McpToolRisk(str, Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


@dataclass(frozen=True)
class McpToolAssessment:
    risk: str
    permissions: tuple[str, ...]
    reason: str
    parameter_preview: dict[str, Any]
    input_sha256: str

    def public(self) -> dict[str, Any]:
        return {
            "risk": self.risk,
            "permissions": list(self.permissions),
            "reason": self.reason,
            "parameter_preview": self.parameter_preview,
            "input_sha256": self.input_sha256,
        }


@dataclass(frozen=True)
class McpPermissionDecision:
    allowed: bool
    code: str
    message: str
    required_user_action: str = ""


class McpPermissionDenied(PermissionError):
    def __init__(
        self,
        decision: McpPermissionDecision,
        assessment: McpToolAssessment,
    ) -> None:
        super().__init__(decision.message)
        self.decision = decision
        self.assessment = assessment


@dataclass(frozen=True)
class McpAuditRecord:
    audit_id: str
    timestamp_ms: int
    connection_id: str
    connection_name: str
    tool_name: str
    transport: str
    source: str
    source_sha256: str
    caller_id: str
    task_id: str
    conversation_id: str
    risk: str
    permissions: tuple[str, ...]
    permission_mode: str
    permission_decision: str
    parameter_preview: dict[str, Any]
    input_sha256: str
    status: str
    duration_ms: int
    output_sha256: str = ""
    error_code: str = ""
    error_message: str = ""

    def public(self) -> dict[str, Any]:
        value = asdict(self)
        value["permissions"] = list(self.permissions)
        return value


def normalize_permission_mode(value: Any) -> str:
    normalized = str(value or "").strip().casefold().replace("-", "_")
    return (
        normalized
        if normalized in {mode.value for mode in McpPermissionMode}
        else McpPermissionMode.ASK_FOR_CHANGES.value
    )


def assess_mcp_tool(
    tool: dict[str, Any],
    arguments: dict[str, Any],
    *,
    transport: str,
) -> McpToolAssessment:
    name = str(tool.get("name") or "unknown").strip()
    normalized_name = re.sub(r"[^a-z0-9]+", " ", name.casefold()).strip()
    annotations = tool.get("annotations") if isinstance(tool.get("annotations"), dict) else {}
    read_only = _annotation_bool(annotations, "readOnlyHint", "read_only_hint")
    destructive = _annotation_bool(annotations, "destructiveHint", "destructive_hint")
    open_world = _annotation_bool(annotations, "openWorldHint", "open_world_hint")
    tokens = set(normalized_name.split())

    risk = McpToolRisk.MEDIUM
    reason = "The MCP server did not declare a read-only contract."
    if destructive is True or tokens & HIGH_RISK_TERMS:
        risk = McpToolRisk.HIGH
        reason = "The tool is destructive or controls a sensitive external action."
    elif read_only is True and not tokens & MUTATING_TERMS:
        risk = McpToolRisk.LOW
        reason = "The MCP server declares this tool read-only."
    elif tokens & READ_ONLY_TERMS and not tokens & MUTATING_TERMS:
        risk = McpToolRisk.LOW
        reason = "The tool name describes a read-only operation."
    elif read_only is False or tokens & MUTATING_TERMS:
        risk = McpToolRisk.MEDIUM
        reason = "The tool can change data or external state."

    argument_keys = {
        str(key).casefold()
        for key in _walk_keys(arguments)
    }
    permissions = {"mcp.data.read"}
    if transport == "stdio":
        permissions.add("mcp.process.execute")
    else:
        permissions.add("mcp.network.connect")
    if risk in {McpToolRisk.MEDIUM, McpToolRisk.HIGH}:
        permissions.add("mcp.data.write")
    if risk == McpToolRisk.HIGH:
        permissions.add("mcp.destructive")
    if open_world is True:
        permissions.add("mcp.network.open_world")
    if any(SECRET_KEY_PATTERN.search(key) for key in argument_keys):
        permissions.add("mcp.secrets.use")
    if any(PATH_KEY_PATTERN.search(key) for key in argument_keys):
        permissions.add("mcp.files.access")

    preview = sanitize_mcp_parameters(arguments)
    return McpToolAssessment(
        risk=risk.value,
        permissions=tuple(sorted(permissions)),
        reason=reason,
        parameter_preview=preview,
        input_sha256=sha256_json(arguments),
    )


def decide_mcp_permission(
    permission_mode: str,
    assessment: McpToolAssessment,
    *,
    explicit_user_selection: bool,
) -> McpPermissionDecision:
    mode = normalize_permission_mode(permission_mode)
    if mode == McpPermissionMode.DISABLED.value:
        return McpPermissionDecision(
            False,
            "mcp_disabled",
            "This MCP connection is disabled by its permission policy.",
            "enable_connection",
        )
    return McpPermissionDecision(
        True,
        "allowed_full_access",
        "GalaxySSI full-access MCP policy allowed the call.",
    )


def sanitize_mcp_parameters(value: Any) -> dict[str, Any]:
    sanitized = _sanitize(value, key="", depth=0)
    return sanitized if isinstance(sanitized, dict) else {"value": sanitized}


def sanitize_mcp_text(value: Any, limit: int = 500) -> str:
    text = _redact_inline_secrets(str(value or ""))
    text = URL_IN_TEXT_PATTERN.sub(
        lambda match: _redact_url_query(match.group(0)),
        text,
    )
    return text[:max(0, min(int(limit or 500), 2_000))]


def sha256_json(value: Any) -> str:
    payload = json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        default=str,
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def source_fingerprint(value: str) -> str:
    return hashlib.sha256(str(value or "").encode("utf-8")).hexdigest()


class McpAuditStore:
    def __init__(self, path: Path | None = None) -> None:
        self.path = Path(path) if path else _default_audit_path()
        self._lock = threading.RLock()

    def append(self, record: McpAuditRecord) -> dict[str, Any]:
        with self._lock:
            records = self._load()
            records.append(record)
            self._save(records[-MAX_AUDIT_RECORDS:])
        return record.public()

    def list(
        self,
        *,
        connection_id: str = "",
        limit: int = 100,
    ) -> list[dict[str, Any]]:
        clean_id = str(connection_id or "").strip()
        with self._lock:
            records = self._load()
        if clean_id:
            records = [record for record in records if record.connection_id == clean_id]
        return [
            record.public()
            for record in reversed(records[-max(1, min(int(limit or 100), 500)):])
        ]

    def clear(self, connection_id: str = "") -> int:
        clean_id = str(connection_id or "").strip()
        with self._lock:
            records = self._load()
            if clean_id:
                kept = [record for record in records if record.connection_id != clean_id]
            else:
                kept = []
            removed = len(records) - len(kept)
            self._save(kept)
        return removed

    def _load(self) -> list[McpAuditRecord]:
        if not self.path.exists():
            return []
        try:
            document = json.loads(self.path.read_text(encoding="utf-8-sig"))
            if int(document.get("schema_version") or 0) != AUDIT_SCHEMA_VERSION:
                return []
            return [
                _audit_from_json(item)
                for item in document.get("records") or []
                if isinstance(item, dict)
            ]
        except Exception:
            return []

    def _save(self, records: list[McpAuditRecord]) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.path.with_suffix(self.path.suffix + ".tmp")
        temporary.write_text(
            json.dumps(
                {
                    "schema_version": AUDIT_SCHEMA_VERSION,
                    "records": [record.public() for record in records],
                },
                ensure_ascii=False,
                separators=(",", ":"),
            ),
            encoding="utf-8",
        )
        temporary.replace(self.path)


def new_audit_record(**values: Any) -> McpAuditRecord:
    values["error_message"] = sanitize_mcp_text(values.get("error_message", ""))
    return McpAuditRecord(
        audit_id=str(values.pop("audit_id", "") or uuid.uuid4()),
        timestamp_ms=int(values.pop("timestamp_ms", 0) or time.time() * 1_000),
        **values,
    )


def _default_audit_path() -> Path:
    configured = str(os.environ.get("GALAXYSSI_STATE_DIR") or "").strip()
    root = Path(configured) if configured else Path(os.environ.get("APPDATA") or Path.home()) / "GalaxySSI"
    return root / "mcp-tool-audit.json"


def _audit_from_json(value: dict[str, Any]) -> McpAuditRecord:
    fields = McpAuditRecord.__dataclass_fields__
    normalized = {key: value.get(key) for key in fields}
    normalized["permissions"] = tuple(str(item) for item in value.get("permissions") or [])
    for key in ("timestamp_ms", "duration_ms"):
        normalized[key] = max(0, int(normalized.get(key) or 0))
    for key in fields:
        if key not in {"timestamp_ms", "duration_ms", "permissions", "parameter_preview"}:
            normalized[key] = str(normalized.get(key) or "")
    normalized["parameter_preview"] = (
        dict(value.get("parameter_preview"))
        if isinstance(value.get("parameter_preview"), dict)
        else {}
    )
    return McpAuditRecord(**normalized)


def _annotation_bool(annotations: dict[str, Any], *names: str) -> bool | None:
    for name in names:
        value = annotations.get(name)
        if isinstance(value, bool):
            return value
    return None


def _walk_keys(value: Any):
    if isinstance(value, dict):
        for key, item in value.items():
            yield str(key)
            yield from _walk_keys(item)
    elif isinstance(value, (list, tuple)):
        for item in value:
            yield from _walk_keys(item)


def _sanitize(value: Any, *, key: str, depth: int) -> Any:
    if SECRET_KEY_PATTERN.search(key):
        return "[REDACTED]"
    if depth >= MAX_PARAMETER_DEPTH:
        return "[TRUNCATED]"
    if isinstance(value, dict):
        return {
            str(item_key)[:128]: _sanitize(item, key=str(item_key), depth=depth + 1)
            for item_key, item in list(value.items())[:MAX_PARAMETER_ITEMS]
        }
    if isinstance(value, (list, tuple)):
        return [
            _sanitize(item, key=key, depth=depth + 1)
            for item in list(value)[:MAX_PARAMETER_ITEMS]
        ]
    if isinstance(value, str):
        text = _redact_inline_secrets(value)
        if URL_PATTERN.match(text):
            text = _redact_url_query(text)
        return text[:MAX_PARAMETER_STRING] + ("..." if len(text) > MAX_PARAMETER_STRING else "")
    if value is None or isinstance(value, (bool, int, float)):
        return value
    return str(value)[:MAX_PARAMETER_STRING]


def _redact_inline_secrets(value: str) -> str:
    text = BEARER_PATTERN.sub("Bearer [REDACTED]", value)
    return ASSIGNMENT_SECRET_PATTERN.sub(lambda match: f"{match.group(1)}=[REDACTED]", text)


def _redact_url_query(value: str) -> str:
    try:
        parsed = urlsplit(value)
        return urlunsplit((parsed.scheme, parsed.netloc, parsed.path, "[REDACTED]" if parsed.query else "", ""))
    except Exception:
        return value


SECRET_KEY_PATTERN = re.compile(
    r"(?:^|[_.-])(?:password|passwd|passphrase|secret|token|api[_-]?key|authorization|cookie|otp|totp|private[_-]?key)(?:$|[_.-])",
    re.IGNORECASE,
)
PATH_KEY_PATTERN = re.compile(r"(?:^|[_.-])(?:path|file|folder|directory|uri|url)(?:$|[_.-])", re.IGNORECASE)
URL_PATTERN = re.compile(r"^https?://", re.IGNORECASE)
URL_IN_TEXT_PATTERN = re.compile(r"https?://[^\s<>\"]+", re.IGNORECASE)
BEARER_PATTERN = re.compile(r"\bBearer\s+[A-Za-z0-9._~+/=-]{8,}", re.IGNORECASE)
ASSIGNMENT_SECRET_PATTERN = re.compile(
    r"\b(password|passwd|secret|token|api[_-]?key|authorization)\s*=\s*[^\s,;]+",
    re.IGNORECASE,
)

READ_ONLY_TERMS = {
    "get", "list", "read", "search", "query", "find", "inspect", "status",
    "describe", "fetch", "lookup", "view", "download",
}
MUTATING_TERMS = {
    "set", "create", "update", "write", "edit", "send", "post", "put", "patch",
    "upload", "execute", "run", "start", "stop", "control", "toggle", "install",
    "approve", "merge", "comment", "reply", "publish",
}
HIGH_RISK_TERMS = {
    "delete", "remove", "destroy", "drop", "wipe", "reset", "payment", "purchase",
    "transfer", "credential", "permission", "shell", "terminal", "sudo", "lock",
    "unlock", "reboot", "shutdown", "deploy", "release",
}
