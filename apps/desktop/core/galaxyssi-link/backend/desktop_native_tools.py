"""Typed, bounded native tools executed by GalaxySSI Desktop on Windows.

The phone remains the policy controller. This module independently validates
tool schemas, confirmation bindings, workspace confinement, idempotency, and
receipts before touching the Desktop host.
"""
from __future__ import annotations

import base64
import csv
import ctypes
import hashlib
import ipaddress
import json
import os
import platform
import re
import shutil
import socket
import subprocess
import threading
import time
import uuid
import webbrowser
import zipfile
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from html.parser import HTMLParser
from pathlib import Path, PurePosixPath
from typing import Any, Callable, Mapping
from urllib.parse import urlsplit
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from desktop_perception import DesktopPerceptionError, DesktopPerceptionService
from desktop_runtime import DesktopRuntimeManager, desktop_runtime_manager
from tool_call_audit import ToolCallAuditStore, desktop_tool_call_audit_store
from web_intelligence import (
    TOOL_OPERATIONS as WEB_INTELLIGENCE_OPERATIONS,
    WebIntelligenceError,
    WebIntelligenceService,
)


CONTRACT_VERSION = "galaxyssi.desktop-native-tools/1.2"
TOOL_VERSION = "1.2.0"
MAX_JSON_BYTES = 256 * 1024
MAX_TEXT_BYTES = 128 * 1024
MAX_WRITE_BYTES = 1024 * 1024
MAX_PROCESS_OUTPUT_BYTES = 64 * 1024
MAX_ARCHIVE_ENTRIES = 2_048
MAX_ARCHIVE_FILE_BYTES = 32 * 1024 * 1024
MAX_ARCHIVE_TOTAL_BYTES = 128 * 1024 * 1024
MAX_OFFICE_FILE_BYTES = 64 * 1024 * 1024
MAX_RECEIPTS = 2_048
WORKSPACE_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,159}\Z")

SYSTEM_STATUS = "galaxyssi.desktop.windows.system.status"
RUNTIME_STATUS = "galaxyssi.desktop.runtime.status"
PROCESS_LIST = "galaxyssi.desktop.windows.process.list"
APP_LIST = "galaxyssi.desktop.windows.app.list"
APP_LAUNCH = "galaxyssi.desktop.windows.app.launch"
HOST_FILE_SEARCH = "galaxyssi.desktop.files.search"
BROWSER_OPEN = "galaxyssi.desktop.browser.open"
WEB_FETCH = "galaxyssi.desktop.web.fetch"
FILE_LIST = "galaxyssi.desktop.workspace.file.list"
FILE_READ_TEXT = "galaxyssi.desktop.workspace.file.read.text"
FILE_WRITE_TEXT = "galaxyssi.desktop.workspace.file.write.text"
FILE_SHA256 = "galaxyssi.desktop.workspace.file.sha256"
ARCHIVE_CREATE = "galaxyssi.desktop.workspace.archive.create"
TERMINAL_RUN = "galaxyssi.desktop.terminal.run"
OFFICE_INSPECT = "galaxyssi.desktop.office.document.inspect"
OFFICE_CONVERT = "galaxyssi.desktop.office.document.convert"
PERCEPTION_SNAPSHOT = "galaxyssi.desktop.perception.snapshot"


class DesktopNativeToolError(RuntimeError):
    def __init__(
        self,
        code: str,
        message: str,
        *,
        retryable: bool = False,
        details: Mapping[str, Any] | None = None,
    ) -> None:
        super().__init__(message)
        self.code = str(code or "desktop_tool_failed")
        self.retryable = bool(retryable)
        self.details = dict(details or {})


@dataclass(frozen=True)
class DesktopToolSpec:
    tool_id: str
    title: str
    description: str
    input_schema: dict[str, Any]
    output_schema: dict[str, Any] = field(default_factory=lambda: {"type": "object"})
    risk: str = "low"
    capabilities: tuple[str, ...] = ()
    timeout_ms: int = 30_000
    idempotency: str = "idempotent"
    confirmation: str = "none"
    availability: Callable[[], tuple[str, str]] = lambda: ("available", "")

    def public(self) -> dict[str, Any]:
        status, reason = self.availability()
        return {
            "id": self.tool_id,
            "version": TOOL_VERSION,
            "title": self.title,
            "description": self.description,
            "location": "desktop",
            "input_schema": self.input_schema,
            "output_schema": self.output_schema,
            "risk": self.risk,
            "capabilities": list(self.capabilities),
            "required_permissions": [],
            "required_consents": [] if self.confirmation == "none" else [{
                "id": f"galaxyssi.consent.desktop.{self.confirmation}",
                "title": f"Desktop {self.confirmation}",
                "description": "Approval is bound to this exact Desktop tool call.",
                "required": True,
            }],
            "timeout_ms": self.timeout_ms,
            "idempotency": self.idempotency,
            "availability": {
                "status": status,
                "reason": reason,
                "checked_at_epoch_ms": int(time.time() * 1_000),
            },
        }


@dataclass(frozen=True)
class DesktopToolExecution:
    output: dict[str, Any]
    message: str
    verification_status: str = "passed"
    verification_message: str = "Host-observed result satisfies the tool contract"
    verification_evidence: dict[str, Any] = field(default_factory=dict)
    artifacts: tuple[dict[str, Any], ...] = ()


def _canonical_json(value: Any) -> str:
    try:
        return json.dumps(
            value,
            ensure_ascii=False,
            allow_nan=False,
            sort_keys=True,
            separators=(",", ":"),
        )
    except (TypeError, ValueError, RecursionError) as exc:
        raise DesktopNativeToolError("invalid_json", "Tool input must be bounded JSON") from exc


def _digest(value: Any) -> str:
    return hashlib.sha256(_canonical_json(value).encode("utf-8")).hexdigest()


def canonical_input_sha256(value: Any) -> str:
    """Return the cross-platform canonical digest used for confirmation binding."""
    return _digest(value)


def _bounded_json(value: dict[str, Any], limit: int = MAX_JSON_BYTES) -> dict[str, Any]:
    if len(_canonical_json(value).encode("utf-8")) > limit:
        raise DesktopNativeToolError("result_too_large", "Desktop tool result exceeds its negotiated limit")
    return value


def _object_schema(
    properties: Mapping[str, Any] | None = None,
    required: tuple[str, ...] = (),
) -> dict[str, Any]:
    return {
        "type": "object",
        "properties": dict(properties or {}),
        "required": list(required),
        "additionalProperties": False,
    }


def _string(*, max_length: int = 4_096, enum: tuple[str, ...] = ()) -> dict[str, Any]:
    result: dict[str, Any] = {"type": "string", "maxLength": max_length}
    if enum:
        result["enum"] = list(enum)
    return result


def _integer(minimum: int, maximum: int) -> dict[str, Any]:
    return {"type": "integer", "minimum": minimum, "maximum": maximum}


def _array(items: dict[str, Any], maximum: int) -> dict[str, Any]:
    return {"type": "array", "items": items, "maxItems": maximum}


WORKSPACE_PROPERTIES = {
    "workspace_id": _string(max_length=160),
    "path": _string(max_length=4_096),
}


def _windows_availability() -> tuple[str, str]:
    if os.name != "nt":
        return "unavailable", "This tool requires Windows"
    return "available", ""


def _office_availability() -> tuple[str, str]:
    if os.name != "nt":
        return "unavailable", "Office conversion requires Windows"
    if not (shutil.which("powershell.exe") or shutil.which("powershell")):
        return "requires_setup", "Windows PowerShell is unavailable"
    return "available", "Microsoft Office is required only for PDF/CSV conversion"


class _WebTextParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []
        self.title_parts: list[str] = []
        self._hidden_depth = 0
        self._in_title = False

    def handle_starttag(self, tag: str, _attrs) -> None:
        if tag in {"script", "style", "noscript", "svg"}:
            self._hidden_depth += 1
        if tag == "title":
            self._in_title = True
        if tag in {"p", "div", "br", "li", "article", "section", "h1", "h2", "h3"}:
            self.parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if tag in {"script", "style", "noscript", "svg"} and self._hidden_depth:
            self._hidden_depth -= 1
        if tag == "title":
            self._in_title = False

    def handle_data(self, data: str) -> None:
        if self._hidden_depth:
            return
        text = re.sub(r"\s+", " ", str(data or "")).strip()
        if not text:
            return
        self.parts.append(text)
        if self._in_title:
            self.title_parts.append(text)

    def result(self) -> tuple[str, str]:
        title = re.sub(r"\s+", " ", " ".join(self.title_parts)).strip()
        text = re.sub(r"[ \t]+", " ", " ".join(self.parts))
        text = re.sub(r"\s*\n\s*", "\n", text)
        return title[:500], text.strip()


def _specs() -> tuple[DesktopToolSpec, ...]:
    return (
        DesktopToolSpec(
            SYSTEM_STATUS,
            "Read Windows system status",
            "Reads bounded operating-system, CPU, and memory status without user files or credentials.",
            _object_schema(),
            capabilities=("windows.status.read",),
            availability=_windows_availability,
        ),
        DesktopToolSpec(
            RUNTIME_STATUS,
            "Read Desktop runtime status",
            "Reads the verified language, media, automation, archive, and voice runtimes available to this Desktop.",
            _object_schema({"refresh": {"type": "boolean"}}),
            capabilities=("desktop.runtime.read",),
        ),
        DesktopToolSpec(
            PROCESS_LIST,
            "List Windows processes",
            "Lists bounded process names, identifiers, and memory use without command lines.",
            _object_schema({"query": _string(max_length=128), "max_entries": _integer(1, 200)}),
            capabilities=("windows.process.list",),
            availability=_windows_availability,
        ),
        DesktopToolSpec(
            APP_LIST,
            "List Windows applications",
            "Lists bounded launchable system applications and Start menu shortcuts.",
            _object_schema({"query": _string(max_length=128), "max_entries": _integer(1, 200)}),
            capabilities=("windows.app.list",),
            availability=_windows_availability,
        ),
        DesktopToolSpec(
            APP_LAUNCH,
            "Launch Windows application",
            "Launches one named application from the bounded system and Start menu catalog.",
            _object_schema({"name": _string(max_length=160)}, ("name",)),
            capabilities=("windows.app.launch",),
            idempotency="non_idempotent",
            availability=_windows_availability,
        ),
        DesktopToolSpec(
            PERCEPTION_SNAPSHOT,
            "Perceive foreground Desktop window",
            "Captures a bounded screenshot, OCR text, and Windows UI Automation tree for the foreground window.",
            _object_schema({
                "include_screenshot": {"type": "boolean"},
                "include_ocr": {"type": "boolean"},
                "include_ui_tree": {"type": "boolean"},
                "max_elements": _integer(1, 120),
                "max_depth": _integer(1, 12),
                "max_ocr_chars": _integer(0, 24_000),
            }),
            capabilities=(
                "desktop.perception.screenshot",
                "desktop.perception.ocr",
                "desktop.perception.ui_tree",
            ),
            timeout_ms=20_000,
            availability=_windows_availability,
        ),
        DesktopToolSpec(
            HOST_FILE_SEARCH,
            "Search user files",
            "Searches names in a bounded known user folder without reading file contents.",
            _object_schema({
                "root": _string(max_length=20, enum=("workspace", "home", "desktop", "documents", "downloads", "pictures", "videos", "music")),
                "query": _string(max_length=180),
                "extensions": _array(_string(max_length=24), 24),
                "max_depth": _integer(1, 12),
                "max_entries": _integer(1, 200),
            }, ("root", "query")),
            capabilities=("desktop.files.search",),
        ),
        DesktopToolSpec(
            BROWSER_OPEN,
            "Open URL in browser",
            "Opens one explicit HTTP or HTTPS URL in the user's default browser.",
            _object_schema({"url": _string(max_length=4_096)}, ("url",)),
            capabilities=("desktop.browser.open",),
            idempotency="non_idempotent",
        ),
        DesktopToolSpec(
            WEB_FETCH,
            "Fetch public web page",
            "Fetches bounded text from a public HTTP or HTTPS page while blocking local and private network targets.",
            _object_schema({
                "url": _string(max_length=4_096),
                "max_bytes": _integer(1_024, 512 * 1_024),
            }, ("url",)),
            capabilities=("desktop.web.fetch",),
            timeout_ms=35_000,
        ),
        DesktopToolSpec(
            FILE_LIST,
            "List Desktop workspace",
            "Lists bounded entries inside one Desktop-owned GalaxySSI task workspace.",
            _object_schema({
                **WORKSPACE_PROPERTIES,
                "recursive": {"type": "boolean"},
                "max_entries": _integer(1, 1_000),
            }, ("workspace_id",)),
            capabilities=("desktop.workspace.read",),
        ),
        DesktopToolSpec(
            FILE_READ_TEXT,
            "Read Desktop workspace text",
            "Reads bounded UTF-8 text inside one Desktop-owned GalaxySSI task workspace.",
            _object_schema({
                **WORKSPACE_PROPERTIES,
                "max_bytes": _integer(1, MAX_TEXT_BYTES),
            }, ("workspace_id", "path")),
            capabilities=("desktop.workspace.read",),
        ),
        DesktopToolSpec(
            FILE_WRITE_TEXT,
            "Write Desktop workspace text",
            "Atomically writes bounded UTF-8 text inside one Desktop-owned GalaxySSI task workspace.",
            _object_schema({
                **WORKSPACE_PROPERTIES,
                "content": _string(max_length=MAX_WRITE_BYTES),
                "mode": _string(max_length=16, enum=("create", "overwrite")),
                "expected_sha256": _string(max_length=64),
            }, ("workspace_id", "path", "content", "mode")),
            risk="medium",
            capabilities=("desktop.workspace.write",),
            idempotency="idempotency_key_required",
        ),
        DesktopToolSpec(
            FILE_SHA256,
            "Hash Desktop workspace file",
            "Calculates SHA-256 for one bounded file inside a Desktop-owned workspace.",
            _object_schema(WORKSPACE_PROPERTIES, ("workspace_id", "path")),
            capabilities=("desktop.workspace.read", "hash.sha256"),
        ),
        DesktopToolSpec(
            ARCHIVE_CREATE,
            "Create Desktop workspace archive",
            "Creates a bounded ZIP from explicit workspace-relative files without following links.",
            _object_schema({
                "workspace_id": _string(max_length=160),
                "paths": _array(_string(max_length=4_096), 256),
                "output_path": _string(max_length=4_096),
            }, ("workspace_id", "paths", "output_path")),
            risk="medium",
            capabilities=("desktop.workspace.read", "desktop.workspace.write", "archive.zip"),
            timeout_ms=60_000,
            idempotency="idempotency_key_required",
        ),
        DesktopToolSpec(
            TERMINAL_RUN,
            "Run Desktop workspace command",
            "Runs an allowlisted executable with an argument array and no command shell in a Desktop-owned workspace.",
            _object_schema({
                "workspace_id": _string(max_length=160),
                "argv": _array(_string(max_length=1_024), 64),
                "cwd": _string(max_length=4_096),
                "timeout_seconds": _integer(1, 180),
            }, ("workspace_id", "argv")),
            risk="high",
            capabilities=("desktop.terminal.execute", "desktop.workspace.read", "desktop.workspace.write"),
            timeout_ms=185_000,
            idempotency="idempotency_key_required",
            confirmation="execute",
            availability=_windows_availability,
        ),
        DesktopToolSpec(
            OFFICE_INSPECT,
            "Inspect Office document",
            "Extracts bounded structure and text from XLSX, DOCX, or PPTX without macros or active content.",
            _object_schema({
                **WORKSPACE_PROPERTIES,
                "max_items": _integer(1, 200),
            }, ("workspace_id", "path")),
            capabilities=("desktop.office.inspect", "desktop.workspace.read"),
        ),
        DesktopToolSpec(
            OFFICE_CONVERT,
            "Convert Office document",
            "Converts a workspace Office document to PDF, CSV, or text and verifies the generated artifact.",
            _object_schema({
                **WORKSPACE_PROPERTIES,
                "output_format": _string(max_length=8, enum=("pdf", "csv", "txt")),
                "output_path": _string(max_length=4_096),
            }, ("workspace_id", "path", "output_format")),
            risk="medium",
            capabilities=("desktop.office.convert", "desktop.workspace.read", "desktop.workspace.write"),
            timeout_ms=90_000,
            idempotency="idempotency_key_required",
            availability=_office_availability,
        ),
    ) + _web_intelligence_specs()


def _web_intelligence_specs() -> tuple[DesktopToolSpec, ...]:
    request_id = _string(max_length=96)
    query = _string(max_length=4_096)
    url = _string(max_length=4_096)
    engines = _array(_string(max_length=64), 32)
    verticals = _array(_string(max_length=32), 10)
    common = {"request_id": request_id}
    return (
        DesktopToolSpec(
            "galaxyssi.web.intelligence.search",
            "Search the web intelligence network",
            "Fans a query across selected public sources, then deduplicates and locally reranks evidence with source receipts.",
            _object_schema({
                **common,
                "query": query,
                "limit": _integer(1, 100),
                "profile": _string(max_length=16, enum=("fast", "balanced", "deep")),
                "engine_fanout": _integer(1, 32),
                "engines": engines,
                "verticals": verticals,
                "freshness": _string(max_length=32),
                "timeout_seconds": _integer(1, 60),
                "use_cache": {"type": "boolean"},
            }, ("query",)),
            capabilities=("web.search", "web.evidence.rank", "web.source.receipts"),
            timeout_ms=65_000,
        ),
        DesktopToolSpec(
            "galaxyssi.web.intelligence.fetch",
            "Fetch and cache public evidence",
            "Fetches one public page, extracts readable content, and stores a verified local evidence snapshot.",
            _object_schema({
                **common,
                "url": url,
                "timeout_seconds": _integer(1, 120),
                "max_bytes": _integer(1_024, 2 * 1024 * 1024),
                "cache_ttl_seconds": _integer(60, 30 * 24 * 60 * 60),
                "force": {"type": "boolean"},
            }, ("url",)),
            capabilities=("web.fetch", "web.extract", "web.cache"),
            timeout_ms=125_000,
        ),
        DesktopToolSpec(
            "galaxyssi.web.intelligence.crawl",
            "Crawl a bounded public site",
            "Crawls a bounded same-origin site graph with explicit page, depth, pattern, and time budgets.",
            _object_schema({
                **common,
                "url": url,
                "max_pages": _integer(1, 100),
                "max_depth": _integer(0, 5),
                "same_origin": {"type": "boolean"},
                "include_pattern": _string(max_length=512),
                "exclude_pattern": _string(max_length=512),
                "timeout_seconds": _integer(1, 600),
            }, ("url",)),
            capabilities=("web.crawl", "web.extract", "web.cache"),
            timeout_ms=605_000,
        ),
        DesktopToolSpec(
            "galaxyssi.web.intelligence.extract",
            "Extract structured public content",
            "Extracts readable text, metadata, JSON-LD, links, and selected fields from a URL or supplied text.",
            _object_schema({
                **common,
                "url": url,
                "content": _string(max_length=512 * 1024),
                "title": _string(max_length=2_048),
                "source_url": url,
                "fields": _array(_string(max_length=128), 100),
                "timeout_seconds": _integer(1, 120),
                "force": {"type": "boolean"},
            }),
            capabilities=("web.extract", "web.structured_data"),
            timeout_ms=125_000,
        ),
        DesktopToolSpec(
            "galaxyssi.web.intelligence.cache",
            "Query local web evidence",
            "Queries, reads, reports, or cleans the persistent local keyword and vector evidence cache.",
            _object_schema({
                **common,
                "action": _string(
                    max_length=32,
                    enum=(
                        "status", "query", "get", "clear", "clear_expired",
                        "source_health", "reset_source_health",
                    ),
                ),
                "query": query,
                "url": url,
                "limit": _integer(1, 100),
                "engines": engines,
            }),
            capabilities=("web.cache", "web.offline_search"),
        ),
        DesktopToolSpec(
            "galaxyssi.web.intelligence.find_similar",
            "Find similar public evidence",
            "Finds related local evidence with a tiny on-device embedding and optionally fills gaps from public search.",
            _object_schema({
                **common,
                "query": query,
                "url": url,
                "limit": _integer(1, 100),
                "search_web": {"type": "boolean"},
                "timeout_seconds": _integer(1, 120),
            }),
            capabilities=("web.similarity", "web.cache", "web.search"),
            timeout_ms=125_000,
        ),
        DesktopToolSpec(
            "galaxyssi.web.intelligence.research",
            "Research with cited public evidence",
            "Decomposes a question, gathers diverse evidence, fetches sources, and emits a cited brief for the selected Agent.",
            _object_schema({
                **common,
                "query": query,
                "max_rounds": _integer(1, 8),
                "source_budget": _integer(2, 40),
                "timeout_seconds": _integer(5, 900),
            }, ("query",)),
            capabilities=("web.research", "web.search", "web.fetch", "web.citations"),
            timeout_ms=905_000,
        ),
        DesktopToolSpec(
            "galaxyssi.web.intelligence.agent",
            "Run an autonomous evidence-gathering loop",
            "Runs bounded multi-round search, gap discovery, source fetch, and citation assembly without hiding source failures.",
            _object_schema({
                **common,
                "query": query,
                "max_rounds": _integer(1, 8),
                "source_budget": _integer(2, 40),
                "timeout_seconds": _integer(5, 900),
            }, ("query",)),
            capabilities=("web.agent", "web.research", "web.replan", "web.citations"),
            timeout_ms=905_000,
        ),
        DesktopToolSpec(
            "galaxyssi.web.intelligence.diff",
            "Detect public page changes",
            "Fetches a fresh snapshot and compares it with the prior verified local snapshot.",
            _object_schema({
                **common,
                "url": url,
                "timeout_seconds": _integer(1, 120),
            }, ("url",)),
            capabilities=("web.diff", "web.cache"),
            timeout_ms=125_000,
        ),
        DesktopToolSpec(
            "galaxyssi.web.intelligence.watch",
            "Manage persistent public page watches",
            "Creates, lists, checks, and removes bounded persistent page-change watches.",
            _object_schema({
                **common,
                "action": _string(max_length=32, enum=("create", "list", "remove", "check", "check_due")),
                "watch_id": _string(max_length=96),
                "url": url,
                "interval_minutes": _integer(15, 10_080),
                "enabled": {"type": "boolean"},
                "limit": _integer(1, 100),
                "timeout_seconds": _integer(1, 120),
            }),
            capabilities=("web.watch", "web.diff", "web.cache"),
            timeout_ms=125_000,
        ),
    )


def _validate(schema: Mapping[str, Any], value: Any, path: str = "$") -> None:
    expected = schema.get("type")
    if expected == "object":
        if not isinstance(value, dict):
            raise DesktopNativeToolError("invalid_input", f"{path} must be an object")
        properties = schema.get("properties") if isinstance(schema.get("properties"), dict) else {}
        required = schema.get("required") if isinstance(schema.get("required"), list) else []
        missing = [name for name in required if name not in value]
        if missing:
            raise DesktopNativeToolError("invalid_input", f"{path} is missing: {', '.join(missing)}")
        if schema.get("additionalProperties") is False:
            extra = sorted(set(value) - set(properties))
            if extra:
                raise DesktopNativeToolError("invalid_input", f"{path} contains unknown fields: {', '.join(extra)}")
        for key, child in value.items():
            if key in properties:
                _validate(properties[key], child, f"{path}.{key}")
        return
    if expected == "array":
        if not isinstance(value, list):
            raise DesktopNativeToolError("invalid_input", f"{path} must be an array")
        if len(value) > int(schema.get("maxItems") or len(value)):
            raise DesktopNativeToolError("invalid_input", f"{path} has too many items")
        for index, child in enumerate(value):
            _validate(schema.get("items") or {}, child, f"{path}[{index}]")
        return
    if expected == "string":
        if not isinstance(value, str):
            raise DesktopNativeToolError("invalid_input", f"{path} must be a string")
        if len(value) > int(schema.get("maxLength") or len(value)):
            raise DesktopNativeToolError("invalid_input", f"{path} is too long")
        if schema.get("enum") and value not in schema["enum"]:
            raise DesktopNativeToolError("invalid_input", f"{path} has an unsupported value")
        return
    if expected == "integer":
        if isinstance(value, bool) or not isinstance(value, int):
            raise DesktopNativeToolError("invalid_input", f"{path} must be an integer")
        if value < int(schema.get("minimum", value)) or value > int(schema.get("maximum", value)):
            raise DesktopNativeToolError("invalid_input", f"{path} is outside its allowed range")
        return
    if expected == "boolean" and not isinstance(value, bool):
        raise DesktopNativeToolError("invalid_input", f"{path} must be a boolean")


class DesktopToolReceiptStore:
    def __init__(self, path: Path | None) -> None:
        self.path = Path(path) if path is not None else None
        self._lock = threading.RLock()
        self._rows = self._load()

    def claim(self, key: str, fingerprint: str, invocation_id: str, tool_id: str) -> dict[str, Any] | None:
        if not key:
            return None
        with self._lock:
            previous = self._rows.get(key)
            if isinstance(previous, dict):
                if previous.get("fingerprint") != fingerprint:
                    raise DesktopNativeToolError(
                        "idempotency_key_conflict",
                        "The idempotency key was already used with different input",
                    )
                if previous.get("state") == "completed" and isinstance(previous.get("result"), dict):
                    replay = json.loads(json.dumps(previous["result"]))
                    replay.setdefault("receipt", {})["replayed"] = True
                    replay["receipt"]["original_invocation_id"] = previous.get("invocation_id")
                    return replay
                raise DesktopNativeToolError(
                    "ambiguous_previous_execution",
                    "A previous execution with this key has no terminal receipt; it was not repeated",
                )
            self._rows[key] = {
                "state": "running",
                "fingerprint": fingerprint,
                "invocation_id": invocation_id,
                "tool_id": tool_id,
                "updated_at": int(time.time() * 1_000),
            }
            self._prune()
            self._save()
        return None

    def complete(self, key: str, result: dict[str, Any]) -> None:
        if not key:
            return
        with self._lock:
            row = self._rows.get(key)
            if not isinstance(row, dict):
                return
            row["state"] = "completed"
            row["result"] = result
            row["updated_at"] = int(time.time() * 1_000)
            self._save()

    def fail(self, key: str) -> None:
        if not key:
            return
        with self._lock:
            row = self._rows.get(key)
            if isinstance(row, dict):
                row["state"] = "failed"
                row["updated_at"] = int(time.time() * 1_000)
                self._save()

    def _load(self) -> dict[str, dict[str, Any]]:
        if self.path is None:
            return {}
        try:
            value = json.loads(self.path.read_text(encoding="utf-8"))
            if isinstance(value, dict):
                for row in value.values():
                    if isinstance(row, dict) and row.get("state") == "running":
                        row["state"] = "ambiguous"
                return value
        except (FileNotFoundError, OSError, json.JSONDecodeError):
            pass
        return {}

    def _prune(self) -> None:
        if len(self._rows) <= MAX_RECEIPTS:
            return
        ordered = sorted(self._rows.items(), key=lambda item: int(item[1].get("updated_at") or 0))
        for key, row in ordered:
            if len(self._rows) <= MAX_RECEIPTS:
                break
            if row.get("state") != "running":
                self._rows.pop(key, None)

    def _save(self) -> None:
        if self.path is None:
            return
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.path.with_suffix(self.path.suffix + ".tmp")
        temporary.write_text(_canonical_json(self._rows), encoding="utf-8")
        temporary.replace(self.path)


class DesktopNativeToolRegistry:
    def __init__(
        self,
        state_root: Path | None = None,
        workspace_root: Path | None = None,
        now: Callable[[], float] = time.time,
        known_roots: Mapping[str, Path] | None = None,
        app_catalog: Callable[[], list[dict[str, str]]] | None = None,
        app_launcher: Callable[[dict[str, str]], None] | None = None,
        browser_opener: Callable[[str], bool] | None = None,
        runtime_manager: DesktopRuntimeManager | None = None,
        web_intelligence_service: WebIntelligenceService | None = None,
        perception_service: DesktopPerceptionService | None = None,
        audit_store: ToolCallAuditStore | None = None,
    ) -> None:
        root = Path(state_root) if state_root else Path(
            os.environ.get("GALAXYSSI_STATE_DIR") or Path(os.environ.get("APPDATA") or Path.home()) / "GalaxySSI"
        )
        if workspace_root is not None:
            self.workspace_root = Path(workspace_root)
        else:
            from task_workspace import workspace_root as galaxyssi_workspace_root

            self.workspace_root = galaxyssi_workspace_root() / "tasks"
        self.workspace_root.mkdir(parents=True, exist_ok=True)
        self.receipts = DesktopToolReceiptStore(root / "desktop-native-tool-receipts.json")
        self.transient_receipts = DesktopToolReceiptStore(None)
        self.audit_store = audit_store or (
            ToolCallAuditStore(root / "desktop-tool-call-audit.json")
            if state_root is not None
            else desktop_tool_call_audit_store()
        )
        self.now = now
        self.known_roots = dict(known_roots or self._default_known_roots())
        self.app_catalog = app_catalog or self._windows_app_catalog
        self.app_launcher = app_launcher or self._launch_catalog_entry
        self.browser_opener = browser_opener or webbrowser.open
        self.runtime_manager = runtime_manager or desktop_runtime_manager()
        self.web_intelligence = web_intelligence_service or WebIntelligenceService(
            root / "web-intelligence"
        )
        if perception_service is None:
            from desktop_control import capture_desktop_screenshot

            perception_service = DesktopPerceptionService(capture_desktop_screenshot)
        self.perception = perception_service
        self.specs = {spec.tool_id: spec for spec in _specs()}
        self.handlers: dict[str, Callable[[dict[str, Any], dict[str, Any]], DesktopToolExecution]] = {
            SYSTEM_STATUS: self._system_status,
            RUNTIME_STATUS: self._runtime_status,
            PROCESS_LIST: self._process_list,
            APP_LIST: self._app_list,
            APP_LAUNCH: self._app_launch,
            PERCEPTION_SNAPSHOT: self._perception_snapshot,
            HOST_FILE_SEARCH: self._host_file_search,
            BROWSER_OPEN: self._browser_open,
            WEB_FETCH: self._web_fetch,
            FILE_LIST: self._file_list,
            FILE_READ_TEXT: self._file_read_text,
            FILE_WRITE_TEXT: self._file_write_text,
            FILE_SHA256: self._file_sha256,
            ARCHIVE_CREATE: self._archive_create,
            TERMINAL_RUN: self._terminal_run,
            OFFICE_INSPECT: self._office_inspect,
            OFFICE_CONVERT: self._office_convert,
        }
        self.handlers.update({
            tool_id: (
                lambda arguments, context, operation=operation:
                self._web_intelligence(operation, arguments, context)
            )
            for tool_id, operation in WEB_INTELLIGENCE_OPERATIONS.items()
        })
        self._process_lock = threading.RLock()
        self._processes: dict[str, subprocess.Popen[str]] = {}
        self._cancelled: set[str] = set()
        self._execution_slots = threading.BoundedSemaphore(4)
        self._side_effect_slot = threading.Lock()

    def manifest(self) -> dict[str, Any]:
        tools = [spec.public() for spec in sorted(self.specs.values(), key=lambda item: item.tool_id)]
        return {
            "contract_version": CONTRACT_VERSION,
            "manifest_revision": 1,
            "generated_at": int(self.now() * 1_000),
            "tools": tools,
            "limits": {
                "max_input_bytes": MAX_JSON_BYTES,
                "max_output_bytes": MAX_JSON_BYTES,
                "max_parallel_side_effects": 1,
            },
        }

    def invoke(
        self,
        tool_id: str,
        arguments: Mapping[str, Any],
        context: Mapping[str, Any] | None = None,
    ) -> dict[str, Any]:
        context = dict(context or {})
        execution_slot = False
        side_effect_slot = False
        receipt_claimed = False
        receipt_store = self.receipts
        host_config_guard = None
        invocation_id = self._identifier(context.get("invocation_id") or uuid.uuid4(), "invocation_id")
        started_at = int(self.now() * 1_000)
        spec = self.specs.get(str(tool_id or ""))
        input_value = dict(arguments) if isinstance(arguments, Mapping) else arguments
        input_sha256 = _digest(input_value)
        idempotency_key = str(context.get("idempotency_key") or "").strip()
        receipt_key = f"{tool_id}:{idempotency_key}" if idempotency_key else ""

        def audited(result: dict[str, Any]) -> dict[str, Any]:
            receipt = result.get("receipt") if isinstance(result.get("receipt"), dict) else {}
            provenance = result.get("provenance") if isinstance(result.get("provenance"), dict) else {}
            error = result.get("error") if isinstance(result.get("error"), dict) else {}
            finished_at = int(self.now() * 1_000)
            self.audit_store.append(
                tool_id=str(provenance.get("tool_id") or tool_id or "unknown"),
                tool_version=str(provenance.get("tool_version") or TOOL_VERSION),
                location=str(provenance.get("location") or "desktop"),
                risk=spec.risk if spec is not None else "unknown",
                confirmation=spec.confirmation if spec is not None else "none",
                status=str(result.get("status") or "failed"),
                started_at=started_at,
                finished_at=finished_at,
                input_sha256=str(receipt.get("input_sha256") or input_sha256),
                output_sha256=str(receipt.get("output_sha256") or _digest({})),
                invocation_id=invocation_id,
                error_code=str(error.get("code") or ""),
                replayed=bool(receipt.get("replayed")),
                original_invocation_id=str(receipt.get("original_invocation_id") or ""),
                context=context,
            )
            return result

        try:
            if spec is None:
                raise DesktopNativeToolError("unknown_tool", f"Unknown Desktop native tool: {tool_id}")
            if spec.tool_id == PERCEPTION_SNAPSHOT:
                receipt_store = self.transient_receipts
            if str(context.get("tool_version") or TOOL_VERSION) != TOOL_VERSION:
                raise DesktopNativeToolError("unsupported_tool_version", "Desktop tool version is not supported")
            availability, reason = spec.availability()
            if availability != "available":
                raise DesktopNativeToolError("tool_unavailable", reason or "Desktop tool is unavailable", retryable=True)
            _validate(spec.input_schema, input_value)
            _bounded_json(input_value)
            if spec.idempotency == "idempotency_key_required" and not idempotency_key:
                raise DesktopNativeToolError("missing_idempotency_key", "This Desktop tool requires an idempotency key")
            execution_slot = self._execution_slots.acquire(blocking=False)
            if not execution_slot:
                raise DesktopNativeToolError("desktop_tool_busy", "Desktop native tool capacity is busy", retryable=True)
            if spec.risk != "low":
                side_effect_slot = self._side_effect_slot.acquire(blocking=False)
                if not side_effect_slot:
                    raise DesktopNativeToolError("desktop_side_effect_busy", "Another Desktop side effect is running", retryable=True)
            replay = receipt_store.claim(receipt_key, input_sha256, invocation_id, spec.tool_id)
            if replay is not None:
                return audited(replay)
            receipt_claimed = bool(receipt_key)
            if self._is_cancelled(invocation_id):
                raise DesktopNativeToolError("cancelled", "Desktop tool call was cancelled")
            if spec.tool_id == TERMINAL_RUN:
                host_config_guard = self._begin_host_config_guard(
                    dict(input_value),
                    context,
                    invocation_id,
                )
            try:
                execution = self.handlers[spec.tool_id](
                    dict(input_value),
                    {**context, "invocation_id": invocation_id},
                )
            except Exception:
                guard = host_config_guard
                host_config_guard = None
                self._finish_host_config_guard(guard)
                raise
            guard = host_config_guard
            host_config_guard = None
            self._finish_host_config_guard(guard)
            output = _bounded_json(dict(execution.output))
            result = self._result(
                spec,
                invocation_id,
                started_at,
                input_sha256,
                idempotency_key,
                "succeeded",
                output=output,
                message=execution.message,
                verification={
                    "status": execution.verification_status,
                    "message": execution.verification_message,
                    "evidence": execution.verification_evidence,
                },
                artifacts=list(execution.artifacts),
            )
            receipt_store.complete(receipt_key, result)
            return audited(result)
        except DesktopNativeToolError as exc:
            if receipt_claimed:
                receipt_store.fail(receipt_key)
            status = "cancelled" if exc.code == "cancelled" else "failed"
            return audited(self._result(
                spec,
                invocation_id,
                started_at,
                input_sha256,
                idempotency_key,
                status,
                error={
                    "code": exc.code,
                    "message": str(exc)[:2_000],
                    "retryable": exc.retryable,
                    "details": _bounded_json(dict(exc.details)) if exc.details else {},
                },
            ))
        except Exception as exc:
            if receipt_claimed:
                receipt_store.fail(receipt_key)
            return audited(self._result(
                spec,
                invocation_id,
                started_at,
                input_sha256,
                idempotency_key,
                "failed",
                error={
                    "code": "desktop_tool_failed",
                    "message": str(exc)[:2_000] or "Desktop tool failed",
                    "retryable": False,
                    "details": {},
                },
            ))
        finally:
            if host_config_guard is not None:
                try:
                    self._finish_host_config_guard(host_config_guard)
                except Exception:
                    pass
            if side_effect_slot:
                self._side_effect_slot.release()
            if execution_slot:
                self._execution_slots.release()
            with self._process_lock:
                self._processes.pop(invocation_id, None)
                self._cancelled.discard(invocation_id)

    def audit(
        self,
        *,
        limit: int = 100,
        tool_id: str = "",
        status: str = "",
    ) -> list[dict[str, Any]]:
        return self.audit_store.list(limit=limit, tool_id=tool_id, status=status)

    @staticmethod
    def _file_access_actor(context: dict[str, Any]) -> str:
        return str(
            context.get("agent_id")
            or context.get("caller_id")
            or "galaxyssi.desktop.native"
        )

    def _begin_host_config_guard(
        self,
        arguments: dict[str, Any],
        context: dict[str, Any],
        invocation_id: str,
    ):
        from host_execution_config_guard import HostExecutionConfigGuard

        workspace_id = str(arguments.get("workspace_id") or "")
        if not workspace_id:
            return None
        return HostExecutionConfigGuard.begin(
            self._workspace(workspace_id),
            agent_id=self._file_access_actor(context),
            capture_id=invocation_id,
        )

    @staticmethod
    def _finish_host_config_guard(guard) -> None:
        if guard is None:
            return
        from host_execution_config_guard import HostExecutionConfigViolation

        violations = guard.finish()
        if violations:
            exc = HostExecutionConfigViolation(violations)
            raise DesktopNativeToolError(
                "host_execution_config_write_blocked",
                str(exc),
                details={"violations": list(exc.violations)},
            ) from exc

    def _ensure_workspace_write_allowed(
        self,
        root: Path,
        target: Path,
        context: dict[str, Any],
    ) -> None:
        from host_execution_config_guard import (
            HostExecutionConfigViolation,
            assert_host_execution_path_writable,
        )

        try:
            assert_host_execution_path_writable(
                root,
                target,
                agent_id=self._file_access_actor(context),
                capture_id=str(context.get("invocation_id") or ""),
            )
        except HostExecutionConfigViolation as exc:
            raise DesktopNativeToolError(
                "host_execution_config_write_blocked",
                str(exc),
                details={"violations": list(exc.violations)},
            ) from exc

    def cancel(self, invocation_id: str) -> bool:
        key = str(invocation_id or "").strip()
        if not key:
            return False
        with self._process_lock:
            self._cancelled.add(key)
            process = self._processes.get(key)
        if process is not None and process.poll() is None:
            process.kill()
            return True
        return False

    def cancel_task(self, task_id: str) -> int:
        prefix = f"{str(task_id or '').strip()}:"
        if prefix == ":":
            return 0
        with self._process_lock:
            invocation_ids = [key for key in self._processes if key.startswith(prefix)]
            self._cancelled.update(invocation_ids)
            processes = [self._processes[key] for key in invocation_ids]
        cancelled = 0
        for process in processes:
            if process.poll() is None:
                process.kill()
                cancelled += 1
        return cancelled

    def _result(
        self,
        spec: DesktopToolSpec | None,
        invocation_id: str,
        started_at: int,
        input_sha256: str,
        idempotency_key: str,
        status: str,
        *,
        output: dict[str, Any] | None = None,
        message: str = "",
        error: dict[str, Any] | None = None,
        verification: dict[str, Any] | None = None,
        artifacts: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any]:
        finished_at = int(self.now() * 1_000)
        output = output or {}
        result = {
            "status": status,
            "output": output,
            "message": str(message or error and error.get("message") or "")[:4_000],
            "metadata": {},
            "error": error,
            "verification": verification,
            "receipt": {
                "invocation_id": invocation_id,
                "idempotency_key": idempotency_key or None,
                "started_at": started_at,
                "finished_at": finished_at,
                "duration_ms": max(0, finished_at - started_at),
                "status": status,
                "input_sha256": input_sha256,
                "output_sha256": _digest(output),
                "replayed": False,
                "original_invocation_id": None,
            },
            "provenance": {
                "tool_id": spec.tool_id if spec else "unknown",
                "tool_version": TOOL_VERSION,
                "location": "desktop",
                "executor_id": "galaxyssi.desktop_native",
                "contract_version": CONTRACT_VERSION,
            },
            "artifacts": artifacts or [],
        }
        return _bounded_json(result)

    @staticmethod
    def _identifier(value: Any, name: str) -> str:
        text = str(value or "").strip()
        if not text or len(text) > 160 or any(ord(char) < 0x20 for char in text):
            raise DesktopNativeToolError("invalid_identity", f"Invalid {name}")
        return text

    def _workspace(self, workspace_id: str) -> Path:
        if not WORKSPACE_ID.fullmatch(str(workspace_id or "")) or ".." in workspace_id:
            raise DesktopNativeToolError("invalid_workspace_id", "Workspace identity is invalid")
        root = (self.workspace_root / workspace_id).resolve()
        root.mkdir(parents=True, exist_ok=True)
        return root

    def _workspace_path(self, workspace_id: str, value: str, *, allow_root: bool = False) -> tuple[Path, Path]:
        root = self._workspace(workspace_id)
        raw = str(value or "").replace("\\", "/")
        pure = PurePosixPath(raw)
        if pure.is_absolute() or pure.drive or any(part in {"", ".", ".."} for part in pure.parts):
            if allow_root and raw in {"", "."}:
                return root, root
            raise DesktopNativeToolError("invalid_path", "Desktop workspace path must be relative and normalized")
        candidate = (root / Path(*pure.parts)).resolve()
        try:
            candidate.relative_to(root)
        except ValueError as exc:
            raise DesktopNativeToolError("path_outside_workspace", "Desktop path leaves the task workspace") from exc
        return root, candidate

    @staticmethod
    def _relative(root: Path, path: Path) -> str:
        return path.relative_to(root).as_posix()

    def _is_cancelled(self, invocation_id: str) -> bool:
        with self._process_lock:
            return invocation_id in self._cancelled

    def _system_status(self, _arguments: dict[str, Any], _context: dict[str, Any]) -> DesktopToolExecution:
        memory_total = memory_available = 0
        if os.name == "nt":
            class MemoryStatus(ctypes.Structure):
                _fields_ = [
                    ("length", ctypes.c_ulong),
                    ("memory_load", ctypes.c_ulong),
                    ("total_physical", ctypes.c_ulonglong),
                    ("available_physical", ctypes.c_ulonglong),
                    ("total_page_file", ctypes.c_ulonglong),
                    ("available_page_file", ctypes.c_ulonglong),
                    ("total_virtual", ctypes.c_ulonglong),
                    ("available_virtual", ctypes.c_ulonglong),
                    ("available_extended_virtual", ctypes.c_ulonglong),
                ]
            status = MemoryStatus()
            status.length = ctypes.sizeof(MemoryStatus)
            if ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(status)):
                memory_total = int(status.total_physical)
                memory_available = int(status.available_physical)
        output = {
            "platform": platform.system(),
            "release": platform.release(),
            "architecture": platform.machine(),
            "logical_cpu_count": os.cpu_count() or 0,
            "memory_total_bytes": memory_total,
            "memory_available_bytes": memory_available,
        }
        return DesktopToolExecution(output, "Windows system status read", verification_evidence=output)

    def _perception_snapshot(
        self,
        arguments: dict[str, Any],
        _context: dict[str, Any],
    ) -> DesktopToolExecution:
        try:
            output = self.perception.capture(
                include_screenshot=bool(arguments.get("include_screenshot", True)),
                include_ocr=bool(arguments.get("include_ocr", True)),
                include_ui_tree=bool(arguments.get("include_ui_tree", True)),
                max_elements=int(arguments.get("max_elements", 80)),
                max_depth=int(arguments.get("max_depth", 8)),
                max_ocr_chars=int(arguments.get("max_ocr_chars", 12_000)),
            )
        except DesktopPerceptionError as exc:
            raise DesktopNativeToolError(
                exc.code,
                str(exc),
                retryable=exc.retryable,
            ) from exc
        available_layers = list(output.get("available_layers") or [])
        return DesktopToolExecution(
            output,
            "Desktop perception captured",
            verification_evidence={
                "capture_id": output.get("capture_id"),
                "available_layers": available_layers,
                "preferred_grounding": output.get("preferred_grounding"),
            },
        )

    def _process_list(self, arguments: dict[str, Any], context: dict[str, Any]) -> DesktopToolExecution:
        query = str(arguments.get("query") or "").casefold()
        maximum = int(arguments.get("max_entries") or 100)
        completed = self._run_process(
            context["invocation_id"],
            ["tasklist.exe", "/FO", "CSV", "/NH"],
            self.workspace_root,
            15,
        )
        if completed.returncode != 0:
            raise DesktopNativeToolError("process_inventory_failed", "Windows process inventory failed")
        rows = []
        for row in csv.reader(completed.stdout.splitlines()):
            if len(row) < 5 or not row[1].replace(",", "").isdigit():
                continue
            name = row[0].strip()
            if query and query not in name.casefold():
                continue
            memory = int(re.sub(r"[^0-9]", "", row[4]) or 0)
            rows.append({"name": name[:260], "pid": int(row[1]), "memory_kb": memory})
            if len(rows) >= maximum:
                break
        output = {"processes": rows, "count": len(rows), "truncated": len(rows) >= maximum}
        return DesktopToolExecution(output, f"Read {len(rows)} Windows processes", verification_evidence={"count": len(rows)})

    def _default_known_roots(self) -> dict[str, Path]:
        home = Path.home()
        return {
            "workspace": self.workspace_root,
            "home": home,
            "desktop": home / "Desktop",
            "documents": home / "Documents",
            "downloads": home / "Downloads",
            "pictures": home / "Pictures",
            "videos": home / "Videos",
            "music": home / "Music",
        }

    @staticmethod
    def _windows_app_catalog() -> list[dict[str, str]]:
        aliases = [
            {"id": "notepad", "name": "Notepad", "kind": "executable", "launch": "notepad.exe"},
            {"id": "calculator", "name": "Calculator", "kind": "executable", "launch": "calc.exe"},
            {"id": "paint", "name": "Paint", "kind": "executable", "launch": "mspaint.exe"},
            {"id": "file-explorer", "name": "File Explorer", "kind": "executable", "launch": "explorer.exe"},
            {"id": "settings", "name": "Settings", "kind": "uri", "launch": "ms-settings:"},
        ]
        roots = [
            Path(os.environ.get("APPDATA") or "") / "Microsoft" / "Windows" / "Start Menu" / "Programs",
            Path(os.environ.get("PROGRAMDATA") or "") / "Microsoft" / "Windows" / "Start Menu" / "Programs",
        ]
        rows = list(aliases)
        seen = {item["name"].casefold() for item in rows}
        for root in roots:
            if not root.is_dir():
                continue
            try:
                shortcuts = root.rglob("*.lnk")
                for shortcut in shortcuts:
                    name = shortcut.stem.strip()
                    normalized = name.casefold()
                    if not name or normalized in seen or any(term in normalized for term in ("uninstall", "readme", "help")):
                        continue
                    digest = hashlib.sha256(str(shortcut).encode("utf-8")).hexdigest()[:16]
                    rows.append({"id": f"shortcut-{digest}", "name": name[:160], "kind": "shortcut", "launch": str(shortcut)})
                    seen.add(normalized)
                    if len(rows) >= 1_000:
                        break
            except OSError:
                continue
        return rows

    @staticmethod
    def _launch_catalog_entry(entry: dict[str, str]) -> None:
        launch = str(entry.get("launch") or "")
        kind = str(entry.get("kind") or "")
        if not launch:
            raise DesktopNativeToolError("app_not_launchable", "Application has no launch target")
        if kind in {"shortcut", "uri"}:
            os.startfile(launch)
            return
        subprocess.Popen([launch], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, close_fds=True)

    def _app_list(self, arguments: dict[str, Any], _context: dict[str, Any]) -> DesktopToolExecution:
        query = str(arguments.get("query") or "").strip().casefold()
        maximum = int(arguments.get("max_entries") or 100)
        rows = []
        for item in self.app_catalog():
            if query and query not in str(item.get("name") or "").casefold():
                continue
            rows.append({"id": str(item.get("id") or ""), "name": str(item.get("name") or ""), "kind": str(item.get("kind") or "")})
            if len(rows) >= maximum:
                break
        output = {"applications": rows, "count": len(rows), "truncated": len(rows) >= maximum}
        return DesktopToolExecution(output, f"Listed {len(rows)} Windows applications", verification_evidence={"count": len(rows)})

    def _app_launch(self, arguments: dict[str, Any], _context: dict[str, Any]) -> DesktopToolExecution:
        requested = str(arguments.get("name") or "").strip()
        normalized = requested.casefold()
        catalog = list(self.app_catalog())
        exact = [item for item in catalog if str(item.get("name") or "").casefold() == normalized or str(item.get("id") or "").casefold() == normalized]
        candidates = exact or [item for item in catalog if normalized in str(item.get("name") or "").casefold()]
        if not candidates:
            raise DesktopNativeToolError("app_not_found", f"Application was not found: {requested}")
        if len(candidates) > 1 and not exact:
            names = [str(item.get("name") or "") for item in candidates[:8]]
            raise DesktopNativeToolError("app_ambiguous", "Application name is ambiguous", details={"candidates": names})
        selected = sorted(candidates, key=lambda item: len(str(item.get("name") or "")))[0]
        self.app_launcher(selected)
        output = {"id": selected.get("id"), "name": selected.get("name"), "launched": True}
        return DesktopToolExecution(output, f"Launched {selected.get('name')}", verification_evidence={"launch_requested": True})

    def _host_file_search(self, arguments: dict[str, Any], _context: dict[str, Any]) -> DesktopToolExecution:
        root_id = str(arguments.get("root") or "workspace")
        root = Path(self.known_roots.get(root_id) or "").expanduser().resolve()
        if not root.is_dir():
            raise DesktopNativeToolError("search_root_unavailable", f"Search root is unavailable: {root_id}")
        query = str(arguments.get("query") or "").strip().casefold()
        extensions = {
            f".{str(value).strip().casefold().lstrip('.')}"
            for value in list(arguments.get("extensions") or [])
            if str(value).strip()
        }
        maximum = int(arguments.get("max_entries") or 100)
        max_depth = int(arguments.get("max_depth") or 6)
        rows = []
        for current, directories, files in os.walk(root, followlinks=False):
            current_path = Path(current)
            try:
                depth = len(current_path.relative_to(root).parts)
            except ValueError:
                continue
            directories[:] = [name for name in directories if not name.startswith(".") and depth < max_depth]
            for name in files:
                if name.startswith(".") or (query and query not in name.casefold()):
                    continue
                path = current_path / name
                if path.is_symlink() or (extensions and path.suffix.casefold() not in extensions):
                    continue
                try:
                    stat = path.stat()
                except OSError:
                    continue
                rows.append({
                    "name": name[:260],
                    "path": str(path),
                    "relative_path": path.relative_to(root).as_posix(),
                    "size_bytes": int(stat.st_size),
                    "modified_at": int(stat.st_mtime * 1_000),
                })
                if len(rows) >= maximum:
                    break
            if len(rows) >= maximum:
                break
        output = {"root": root_id, "files": rows, "count": len(rows), "truncated": len(rows) >= maximum}
        return DesktopToolExecution(output, f"Found {len(rows)} matching files", verification_evidence={"root": root_id, "count": len(rows)})

    @staticmethod
    def _validated_url(value: str, *, public_only: bool) -> str:
        url = str(value or "").strip()
        parsed = urlsplit(url)
        if parsed.scheme not in {"http", "https"} or not parsed.hostname or parsed.username or parsed.password:
            raise DesktopNativeToolError("invalid_url", "URL must be HTTP or HTTPS and must not embed credentials")
        if public_only:
            host = parsed.hostname.casefold()
            if host == "localhost" or host.endswith(".localhost") or host.endswith(".local"):
                raise DesktopNativeToolError("private_network_blocked", "Local and private network web targets are blocked")
            try:
                addresses = {item[4][0] for item in socket.getaddrinfo(parsed.hostname, parsed.port or (443 if parsed.scheme == "https" else 80), type=socket.SOCK_STREAM)}
            except OSError as exc:
                raise DesktopNativeToolError("dns_failed", "Web target could not be resolved", retryable=True) from exc
            if not addresses or any(not ipaddress.ip_address(address.split("%", 1)[0]).is_global for address in addresses):
                raise DesktopNativeToolError("private_network_blocked", "Local and private network web targets are blocked")
        return url

    def _browser_open(self, arguments: dict[str, Any], _context: dict[str, Any]) -> DesktopToolExecution:
        url = self._validated_url(arguments["url"], public_only=False)
        opened = bool(self.browser_opener(url))
        if not opened:
            raise DesktopNativeToolError("browser_open_failed", "The default browser did not accept the URL")
        output = {"url": url, "opened": True}
        return DesktopToolExecution(output, "Opened URL in default browser", verification_evidence={"open_requested": True})

    def _web_fetch(self, arguments: dict[str, Any], _context: dict[str, Any]) -> DesktopToolExecution:
        url = self._validated_url(arguments["url"], public_only=True)
        maximum = int(arguments.get("max_bytes") or 256 * 1_024)
        request = Request(
            url,
            headers={
                "User-Agent": "GalaxySSI-Desktop/0.1",
                "Accept": "text/html,application/json,text/plain;q=0.9,*/*;q=0.5",
            },
        )
        try:
            with urlopen(request, timeout=30) as response:
                final_url = self._validated_url(response.geturl(), public_only=True)
                content_type = str(response.headers.get_content_type() or "application/octet-stream")
                charset = str(response.headers.get_content_charset() or "utf-8")
                raw = response.read(maximum + 1)
                status = int(getattr(response, "status", 200) or 200)
        except HTTPError as exc:
            raise DesktopNativeToolError("web_http_error", f"Web server returned HTTP {exc.code}", retryable=500 <= int(exc.code) < 600) from exc
        except (URLError, OSError) as exc:
            raise DesktopNativeToolError("web_fetch_failed", "Public web page could not be fetched", retryable=True) from exc
        truncated = len(raw) > maximum
        raw = raw[:maximum]
        try:
            decoded = raw.decode(charset, errors="replace")
        except LookupError:
            decoded = raw.decode("utf-8", errors="replace")
        title = ""
        if content_type in {"text/html", "application/xhtml+xml"}:
            parser = _WebTextParser()
            parser.feed(decoded)
            title, text = parser.result()
        elif content_type.startswith("text/") or content_type in {"application/json", "application/xml"}:
            text = decoded.strip()
        else:
            raise DesktopNativeToolError("unsupported_web_content", f"Web content type is not text: {content_type}")
        output = {
            "url": final_url,
            "status_code": status,
            "content_type": content_type,
            "title": title,
            "text": text[:MAX_TEXT_BYTES],
            "size_bytes": len(raw),
            "truncated": truncated or len(text) > MAX_TEXT_BYTES,
            "fetched_at": int(self.now() * 1_000),
        }
        return DesktopToolExecution(output, f"Fetched {len(raw)} bytes from public web", verification_evidence={"url": final_url, "status_code": status})

    def _web_intelligence(
        self,
        operation: str,
        arguments: dict[str, Any],
        context: dict[str, Any],
    ) -> DesktopToolExecution:
        invocation_id = str(context.get("invocation_id") or "")
        if invocation_id and self._is_cancelled(invocation_id):
            raise DesktopNativeToolError("cancelled", "Web intelligence task was cancelled")
        try:
            output = self.web_intelligence.invoke(operation, arguments)
        except WebIntelligenceError as exc:
            raise DesktopNativeToolError(
                exc.code,
                str(exc),
                retryable=exc.retryable,
                details=exc.details,
            ) from exc
        bounded = self._bounded_web_intelligence_output(output)
        status = str(bounded.get("status") or "completed")
        message = {
            "search": "Web intelligence search completed",
            "fetch": "Public evidence fetched and cached",
            "crawl": "Bounded site crawl completed",
            "extract": "Structured content extraction completed",
            "cache": "Local web evidence cache query completed",
            "find_similar": "Similar evidence search completed",
            "research": "Cited research brief prepared",
            "agent": "Autonomous evidence-gathering loop completed",
            "diff": "Page change comparison completed",
            "watch": "Page watch operation completed",
        }.get(operation, "Web intelligence operation completed")
        return DesktopToolExecution(
            bounded,
            message,
            verification_status="passed" if status in {"completed", "partial"} else "failed",
            verification_message="Source receipts and content hashes are included in the result",
            verification_evidence={
                "protocol": bounded.get("protocol"),
                "operation": operation,
                "status": status,
                "receipt_count": len(bounded.get("receipts") or []),
            },
        )

    @staticmethod
    def _bounded_web_intelligence_output(output: dict[str, Any]) -> dict[str, Any]:
        cloned = json.loads(json.dumps(output, ensure_ascii=False))
        if len(_canonical_json(cloned).encode("utf-8")) <= MAX_JSON_BYTES:
            return cloned
        documents = cloned.get("documents")
        if isinstance(documents, list):
            per_document = 96_000 if len(documents) <= 1 else max(2_000, 160_000 // max(1, len(documents)))
            for document in documents:
                if not isinstance(document, dict):
                    continue
                content = str(document.get("content") or "")
                if len(content) > per_document:
                    document["content"] = content[:per_document]
                    document["content_truncated"] = True
                links = document.get("links")
                if isinstance(links, list) and len(links) > 100:
                    document["links"] = links[:100]
                    document["links_truncated"] = True
        if isinstance(cloned.get("brief"), str):
            cloned["brief"] = cloned["brief"][:64_000]
        if isinstance(cloned.get("results"), list):
            cloned["results"] = cloned["results"][:100]
        if isinstance(cloned.get("receipts"), list):
            cloned["receipts"] = cloned["receipts"][:128]
        cloned.setdefault("metadata", {})["output_truncated"] = True
        if len(_canonical_json(cloned).encode("utf-8")) > MAX_JSON_BYTES:
            cloned["documents"] = []
            cloned["metadata"]["documents_retained_in_local_cache"] = True
        return cloned

    def _file_list(self, arguments: dict[str, Any], _context: dict[str, Any]) -> DesktopToolExecution:
        workspace_id = arguments["workspace_id"]
        root, selected = self._workspace_path(workspace_id, str(arguments.get("path") or "."), allow_root=True)
        if not selected.exists() or not selected.is_dir():
            raise DesktopNativeToolError("directory_not_found", "Desktop workspace directory does not exist")
        recursive = bool(arguments.get("recursive", False))
        maximum = int(arguments.get("max_entries") or 200)
        entries = []
        iterator = selected.rglob("*") if recursive else selected.iterdir()
        for path in iterator:
            if path.is_symlink():
                continue
            entries.append({
                "path": self._relative(root, path),
                "type": "directory" if path.is_dir() else "file",
                "size_bytes": path.stat().st_size if path.is_file() else 0,
            })
            if len(entries) >= maximum:
                break
        output = {"entries": entries, "count": len(entries), "truncated": len(entries) >= maximum}
        return DesktopToolExecution(output, f"Listed {len(entries)} Desktop workspace entries", verification_evidence={"count": len(entries)})

    def _file_read_text(self, arguments: dict[str, Any], _context: dict[str, Any]) -> DesktopToolExecution:
        root, source = self._workspace_path(arguments["workspace_id"], arguments["path"])
        if not source.is_file() or source.is_symlink():
            raise DesktopNativeToolError("file_not_found", "Desktop workspace text file does not exist")
        maximum = int(arguments.get("max_bytes") or MAX_TEXT_BYTES)
        raw = source.read_bytes()
        if len(raw) > maximum:
            raise DesktopNativeToolError("file_too_large", "Desktop workspace text exceeds the requested limit")
        try:
            text = raw.decode("utf-8-sig")
        except UnicodeDecodeError as exc:
            raise DesktopNativeToolError("unsupported_text_encoding", "Desktop workspace file is not UTF-8 text") from exc
        sha256 = hashlib.sha256(raw).hexdigest()
        output = {"path": self._relative(root, source), "text": text, "size_bytes": len(raw), "sha256": sha256}
        return DesktopToolExecution(output, f"Read {len(raw)} bytes", verification_evidence={"sha256": sha256, "size_bytes": len(raw)})

    def _file_write_text(self, arguments: dict[str, Any], context: dict[str, Any]) -> DesktopToolExecution:
        root, target = self._workspace_path(arguments["workspace_id"], arguments["path"])
        self._ensure_workspace_write_allowed(root, target, context)
        raw = arguments["content"].encode("utf-8")
        if len(raw) > MAX_WRITE_BYTES:
            raise DesktopNativeToolError("content_too_large", "Desktop workspace write exceeds the limit")
        mode = arguments["mode"]
        if mode == "create" and target.exists():
            raise DesktopNativeToolError("file_exists", "Desktop workspace file already exists")
        expected = str(arguments.get("expected_sha256") or "")
        if expected:
            if not target.is_file() or self._sha256(target) != expected.lower():
                raise DesktopNativeToolError("workspace_conflict", "Desktop workspace file changed before write")
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.with_name(f".{target.name}.{uuid.uuid4().hex}.tmp")
        temporary.write_bytes(raw)
        temporary.replace(target)
        sha256 = self._sha256(target)
        output = {"path": self._relative(root, target), "size_bytes": len(raw), "sha256": sha256}
        return DesktopToolExecution(output, f"Wrote {len(raw)} bytes", verification_evidence=output)

    def _file_sha256(self, arguments: dict[str, Any], _context: dict[str, Any]) -> DesktopToolExecution:
        root, source = self._workspace_path(arguments["workspace_id"], arguments["path"])
        if not source.is_file() or source.is_symlink():
            raise DesktopNativeToolError("file_not_found", "Desktop workspace file does not exist")
        sha256 = self._sha256(source)
        output = {"path": self._relative(root, source), "size_bytes": source.stat().st_size, "sha256": sha256}
        return DesktopToolExecution(output, "Calculated SHA-256", verification_evidence=output)

    def _archive_create(self, arguments: dict[str, Any], context: dict[str, Any]) -> DesktopToolExecution:
        workspace_id = arguments["workspace_id"]
        root, target = self._workspace_path(workspace_id, arguments["output_path"])
        self._ensure_workspace_write_allowed(root, target, context)
        if target.suffix.lower() != ".zip":
            raise DesktopNativeToolError("invalid_archive_path", "Archive output must end with .zip")
        files: list[Path] = []
        total = 0
        for raw_path in arguments["paths"]:
            _, source = self._workspace_path(workspace_id, raw_path)
            candidates = [source] if source.is_file() else list(source.rglob("*")) if source.is_dir() else []
            for item in candidates:
                if item.is_symlink() or not item.is_file() or item == target:
                    continue
                size = item.stat().st_size
                if size > MAX_ARCHIVE_FILE_BYTES:
                    raise DesktopNativeToolError("archive_file_too_large", "One archive input exceeds the per-file limit")
                total += size
                if total > MAX_ARCHIVE_TOTAL_BYTES or len(files) >= MAX_ARCHIVE_ENTRIES:
                    raise DesktopNativeToolError("archive_limit_exceeded", "Archive inputs exceed bounded limits")
                files.append(item)
        if not files:
            raise DesktopNativeToolError("archive_empty", "No workspace files were selected for the archive")
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.with_name(f".{target.name}.{uuid.uuid4().hex}.tmp")
        try:
            with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED) as archive:
                for source in sorted(set(files)):
                    archive.write(source, self._relative(root, source))
            temporary.replace(target)
        finally:
            temporary.unlink(missing_ok=True)
        sha256 = self._sha256(target)
        output = {
            "path": self._relative(root, target),
            "entry_count": len(set(files)),
            "size_bytes": target.stat().st_size,
            "sha256": sha256,
        }
        artifact = self._artifact(root, target, "application/zip")
        return DesktopToolExecution(output, f"Created ZIP with {output['entry_count']} files", verification_evidence=output, artifacts=(artifact,))

    def _terminal_run(self, arguments: dict[str, Any], context: dict[str, Any]) -> DesktopToolExecution:
        workspace_id = arguments["workspace_id"]
        root = self._workspace(workspace_id)
        _, cwd = self._workspace_path(workspace_id, str(arguments.get("cwd") or "."), allow_root=True)
        if not cwd.is_dir():
            raise DesktopNativeToolError("working_directory_not_found", "Desktop command working directory does not exist")
        argv = [str(item) for item in arguments["argv"]]
        if not argv:
            raise DesktopNativeToolError("empty_command", "Desktop command argument list is empty")
        executable = self._resolve_executable(argv[0], root)
        timeout = int(arguments.get("timeout_seconds") or 60)
        completed = self._run_process(context["invocation_id"], [executable, *argv[1:]], cwd, timeout)
        output = {
            "argv": [Path(argv[0]).name, *argv[1:]],
            "cwd": self._relative(root, cwd) if cwd != root else ".",
            "exit_code": completed.returncode,
            "stdout": self._bound_text(completed.stdout),
            "stderr": self._bound_text(completed.stderr),
            "stdout_truncated": len(completed.stdout.encode("utf-8", errors="replace")) > MAX_PROCESS_OUTPUT_BYTES,
            "stderr_truncated": len(completed.stderr.encode("utf-8", errors="replace")) > MAX_PROCESS_OUTPUT_BYTES,
        }
        if completed.returncode != 0:
            raise DesktopNativeToolError(
                "process_failed",
                f"Desktop command exited with code {completed.returncode}",
                details=output,
            )
        return DesktopToolExecution(
            output,
            f"Desktop command completed with exit code {completed.returncode}",
            verification_evidence={"exit_code": completed.returncode},
        )

    def _runtime_status(self, arguments: dict[str, Any], _context: dict[str, Any]) -> DesktopToolExecution:
        snapshot = self.runtime_manager.snapshot(refresh=bool(arguments.get("refresh", False)))
        summary = dict(snapshot.get("summary") or {})
        return DesktopToolExecution(
            snapshot,
            f"Found {summary.get('ready', 0)} ready Desktop runtimes",
            verification_evidence={
                "contract_version": snapshot.get("contract_version"),
                "checked_at_epoch_ms": snapshot.get("checked_at_epoch_ms"),
                "summary": summary,
            },
        )

    def _office_inspect(self, arguments: dict[str, Any], _context: dict[str, Any]) -> DesktopToolExecution:
        root, source = self._workspace_path(arguments["workspace_id"], arguments["path"])
        maximum = int(arguments.get("max_items") or 100)
        inspection = self._inspect_office(source, maximum)
        output = {"path": self._relative(root, source), **inspection, "sha256": self._sha256(source)}
        return DesktopToolExecution(
            output,
            f"Inspected {source.name}",
            verification_evidence={"sha256": output["sha256"], "document_type": output["document_type"]},
        )

    def _office_convert(self, arguments: dict[str, Any], context: dict[str, Any]) -> DesktopToolExecution:
        workspace_id = arguments["workspace_id"]
        root, source = self._workspace_path(workspace_id, arguments["path"])
        if not source.is_file() or source.stat().st_size > MAX_OFFICE_FILE_BYTES:
            raise DesktopNativeToolError("office_file_unavailable", "Office input is missing or exceeds the size limit")
        output_format = arguments["output_format"]
        raw_output = str(arguments.get("output_path") or f"outputs/{source.stem}.{output_format}")
        _, target = self._workspace_path(workspace_id, raw_output)
        self._ensure_workspace_write_allowed(root, target, context)
        if target.suffix.lower() != f".{output_format}":
            raise DesktopNativeToolError("invalid_output_path", "Office output extension does not match output_format")
        target.parent.mkdir(parents=True, exist_ok=True)
        if output_format == "txt":
            inspection = self._inspect_office(source, 2_000)
            text_items = inspection.get("text_items") or []
            if inspection.get("document_type") == "excel":
                text_items = ["\t".join(str(cell) for cell in row) for row in inspection.get("rows") or []]
            text = "\n".join(text_items)[:MAX_WRITE_BYTES]
            target.write_text(text, encoding="utf-8")
        else:
            self._run_office_conversion(context["invocation_id"], source, target, output_format)
        if not target.is_file() or target.stat().st_size <= 0:
            raise DesktopNativeToolError("office_conversion_failed", "Office did not create a nonempty output file")
        sha256 = self._sha256(target)
        mime = {
            "pdf": "application/pdf",
            "csv": "text/csv",
            "txt": "text/plain",
        }[output_format]
        output = {"path": self._relative(root, target), "size_bytes": target.stat().st_size, "sha256": sha256, "mime_type": mime}
        return DesktopToolExecution(
            output,
            f"Converted {source.name} to {target.name}",
            verification_evidence=output,
            artifacts=(self._artifact(root, target, mime),),
        )

    def _inspect_office(self, source: Path, maximum: int) -> dict[str, Any]:
        if not source.is_file() or source.is_symlink() or source.stat().st_size > MAX_OFFICE_FILE_BYTES:
            raise DesktopNativeToolError("office_file_unavailable", "Office file is missing or exceeds the size limit")
        suffix = source.suffix.lower()
        if suffix not in {".xlsx", ".docx", ".pptx"} or not zipfile.is_zipfile(source):
            raise DesktopNativeToolError("unsupported_office_document", "Expected a valid XLSX, DOCX, or PPTX file")
        with zipfile.ZipFile(source) as archive:
            infos = archive.infolist()
            if len(infos) > MAX_ARCHIVE_ENTRIES or sum(item.file_size for item in infos) > MAX_ARCHIVE_TOTAL_BYTES:
                raise DesktopNativeToolError("office_archive_limit_exceeded", "Office package exceeds safe extraction limits")
            if suffix == ".docx":
                root = self._xml_member(archive, "word/document.xml")
                items = ["".join(node.itertext()).strip() for node in root.iter() if node.tag.endswith("}p")]
                items = [item for item in items if item][:maximum]
                return {"document_type": "word", "item_count": len(items), "text_items": items}
            if suffix == ".pptx":
                slide_names = sorted(
                    (name for name in archive.namelist() if re.fullmatch(r"ppt/slides/slide\d+\.xml", name)),
                    key=lambda name: int(re.search(r"\d+", Path(name).stem).group()),
                )
                items = []
                for name in slide_names[:maximum]:
                    text = " ".join(value.strip() for value in self._xml_member(archive, name).itertext() if value.strip())
                    items.append(text[:8_000])
                return {"document_type": "powerpoint", "slide_count": len(slide_names), "item_count": len(items), "text_items": items}
            workbook = self._xml_member(archive, "xl/workbook.xml")
            sheets = [node.attrib.get("name", "")[:260] for node in workbook.iter() if node.tag.endswith("}sheet")]
            shared = []
            if "xl/sharedStrings.xml" in archive.namelist():
                shared_root = self._xml_member(archive, "xl/sharedStrings.xml")
                shared = ["".join(node.itertext()) for node in shared_root if node.tag.endswith("}si")]
            worksheet_names = sorted(name for name in archive.namelist() if re.fullmatch(r"xl/worksheets/sheet\d+\.xml", name))
            rows: list[list[str]] = []
            if worksheet_names:
                sheet = self._xml_member(archive, worksheet_names[0])
                for row in (node for node in sheet.iter() if node.tag.endswith("}row")):
                    values = []
                    for cell in (child for child in row if child.tag.endswith("}c")):
                        value = next((node.text or "" for node in cell.iter() if node.tag.endswith("}v")), "")
                        if cell.attrib.get("t") == "s" and value.isdigit() and int(value) < len(shared):
                            value = shared[int(value)]
                        values.append(value[:2_000])
                    rows.append(values[:100])
                    if len(rows) >= maximum:
                        break
            return {"document_type": "excel", "sheet_count": len(sheets), "sheets": sheets[:maximum], "item_count": len(rows), "rows": rows}

    @staticmethod
    def _xml_member(archive: zipfile.ZipFile, name: str) -> ET.Element:
        try:
            raw = archive.read(name)
        except KeyError as exc:
            raise DesktopNativeToolError("invalid_office_document", f"Office package is missing {name}") from exc
        if b"<!DOCTYPE" in raw.upper() or b"<!ENTITY" in raw.upper():
            raise DesktopNativeToolError("unsafe_office_xml", "Office package contains unsupported XML declarations")
        try:
            return ET.fromstring(raw)
        except ET.ParseError as exc:
            raise DesktopNativeToolError("invalid_office_xml", "Office package contains malformed XML") from exc

    def _run_office_conversion(self, invocation_id: str, source: Path, target: Path, output_format: str) -> None:
        suffix = source.suffix.lower()
        if output_format == "csv" and suffix not in {".xlsx", ".xls"}:
            raise DesktopNativeToolError("unsupported_office_conversion", "CSV output is supported only for Excel workbooks")
        if output_format == "pdf" and suffix not in {".xlsx", ".xls", ".docx", ".doc", ".pptx", ".ppt"}:
            raise DesktopNativeToolError("unsupported_office_conversion", "PDF output requires an Excel, Word, or PowerPoint document")
        if suffix in {".xlsx", ".docx", ".pptx"} and not zipfile.is_zipfile(source):
            raise DesktopNativeToolError("invalid_office_document", "Office input is not a valid package")
        script = self._office_script(suffix, output_format)
        encoded = base64.b64encode(script.encode("utf-16le")).decode("ascii")
        env = self._safe_environment()
        env["GALAXYSSI_INPUT"] = str(source.resolve())
        env["GALAXYSSI_OUTPUT"] = str(target.resolve())
        completed = self._run_process(
            invocation_id,
            [self._powershell(), "-NoLogo", "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded],
            target.parent,
            85,
            env=env,
        )
        if completed.returncode != 0:
            detail = self._bound_text(completed.stderr or completed.stdout or "Office conversion failed")
            raise DesktopNativeToolError("office_conversion_failed", detail or "Office conversion failed", retryable=True)

    @staticmethod
    def _office_script(suffix: str, output_format: str) -> str:
        common = "$ErrorActionPreference = 'Stop'\n"
        if suffix in {".xlsx", ".xls"}:
            action = (
                "$document.ExportAsFixedFormat(0, $env:GALAXYSSI_OUTPUT)"
                if output_format == "pdf" else
                "$document.SaveAs($env:GALAXYSSI_OUTPUT, 6)"
            )
            return common + f"""
$application = New-Object -ComObject Excel.Application
$application.Visible = $false
$application.DisplayAlerts = $false
$document = $null
try {{
  $document = $application.Workbooks.Open($env:GALAXYSSI_INPUT)
  {action}
  $document.Close($false)
  $document = $null
}} finally {{
  if ($null -ne $document) {{ $document.Close($false) }}
  $application.Quit()
  [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($application)
}}
""".strip()
        if suffix in {".docx", ".doc"}:
            return common + """
$application = New-Object -ComObject Word.Application
$application.Visible = $false
$document = $null
try {
  $document = $application.Documents.Open($env:GALAXYSSI_INPUT, $false, $true)
  $document.SaveAs([ref]$env:GALAXYSSI_OUTPUT, [ref]17)
  $document.Close($false)
  $document = $null
} finally {
  if ($null -ne $document) { $document.Close($false) }
  $application.Quit()
  [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($application)
}
""".strip()
        if suffix in {".pptx", ".ppt"}:
            return common + """
$application = New-Object -ComObject PowerPoint.Application
$document = $null
try {
  $document = $application.Presentations.Open($env:GALAXYSSI_INPUT, $true, $true, $false)
  $document.SaveAs($env:GALAXYSSI_OUTPUT, 32)
  $document.Close()
  $document = $null
} finally {
  if ($null -ne $document) { $document.Close() }
  $application.Quit()
  [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($application)
}
""".strip()
        raise DesktopNativeToolError("unsupported_office_conversion", "Office document type is unsupported")

    def _run_process(
        self,
        invocation_id: str,
        argv: list[str],
        cwd: Path,
        timeout: int,
        *,
        env: Mapping[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        if self._is_cancelled(invocation_id):
            raise DesktopNativeToolError("cancelled", "Desktop tool call was cancelled")
        process = subprocess.Popen(
            argv,
            cwd=str(cwd),
            env=dict(env or self._safe_environment()),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            shell=False,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
        )
        with self._process_lock:
            self._processes[invocation_id] = process
        try:
            stdout, stderr = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired as exc:
            process.kill()
            stdout, stderr = process.communicate()
            raise DesktopNativeToolError(
                "tool_timeout",
                "Desktop process exceeded its bounded execution time",
                retryable=True,
                details={"stdout": self._bound_text(stdout), "stderr": self._bound_text(stderr)},
            ) from exc
        if self._is_cancelled(invocation_id):
            raise DesktopNativeToolError("cancelled", "Desktop tool call was cancelled")
        return subprocess.CompletedProcess(argv, process.returncode, stdout, stderr)

    def _resolve_executable(self, value: str, root: Path) -> str:
        token = str(value or "").strip()
        if not token:
            raise DesktopNativeToolError("invalid_executable", "Desktop executable is blank")
        blocked = {"cmd", "cmd.exe", "powershell", "powershell.exe", "pwsh", "pwsh.exe", "wscript", "cscript", "mshta"}
        if Path(token).name.casefold() in blocked:
            raise DesktopNativeToolError("shell_blocked", "General command shells are not available through this tool")
        if any(separator in token for separator in ("/", "\\")):
            _, candidate = self._workspace_path(root.name, token)
            if not candidate.is_file():
                raise DesktopNativeToolError("executable_not_found", "Workspace executable does not exist")
            return str(candidate)
        allowlist = {
            "python", "python.exe", "python3", "py", "py.exe", "node", "node.exe", "npm", "npm.cmd",
            "npx", "npx.cmd", "git", "git.exe", "go", "go.exe", "cargo", "cargo.exe", "rustc", "rustc.exe",
            "java", "java.exe", "javac", "javac.exe", "dotnet", "dotnet.exe", "cmake", "cmake.exe", "ctest",
            "ctest.exe", "ninja", "ninja.exe", "clang", "clang.exe", "clang++", "clang++.exe", "gcc", "gcc.exe",
            "g++", "g++.exe", "ffmpeg", "ffmpeg.exe", "ffprobe", "ffprobe.exe", "7z", "7z.exe", "tar", "tar.exe",
            "zip", "zip.exe", "unzip", "unzip.exe",
        }
        configured = {
            item.strip().casefold()
            for item in os.environ.get("GALAXYSSI_DESKTOP_TOOL_EXECUTABLES", "").split(",")
            if item.strip()
        }
        if token.casefold() not in allowlist | configured:
            raise DesktopNativeToolError("executable_not_allowlisted", f"Desktop executable is not allowlisted: {token}")
        resolved = self.runtime_manager.resolve_executable(token) or shutil.which(token)
        if not resolved:
            raise DesktopNativeToolError("executable_not_found", f"Desktop executable is not installed: {token}", retryable=True)
        return resolved

    @staticmethod
    def _safe_environment() -> dict[str, str]:
        allowed = {
            "PATH", "PATHEXT", "SystemRoot", "SYSTEMROOT", "WINDIR", "TEMP", "TMP", "LANG", "LANGUAGE",
            "LOCALAPPDATA", "APPDATA", "USERPROFILE", "ProgramFiles", "ProgramFiles(x86)", "ProgramData",
        }
        return {key: value for key, value in os.environ.items() if key in allowed}

    @staticmethod
    def _powershell() -> str:
        return shutil.which("powershell.exe") or shutil.which("powershell") or "powershell.exe"

    @staticmethod
    def _bound_text(value: str) -> str:
        raw = str(value or "").encode("utf-8", errors="replace")
        if len(raw) <= MAX_PROCESS_OUTPUT_BYTES:
            return raw.decode("utf-8", errors="replace")
        return raw[:MAX_PROCESS_OUTPUT_BYTES].decode("utf-8", errors="replace")

    @staticmethod
    def _sha256(path: Path) -> str:
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        return digest.hexdigest()

    def _artifact(self, root: Path, path: Path, mime_type: str) -> dict[str, Any]:
        return {
            "artifact_id": str(uuid.uuid4()),
            "name": path.name[:260],
            "path": self._relative(root, path),
            "mime_type": mime_type,
            "size_bytes": path.stat().st_size,
            "sha256": self._sha256(path),
            "location": "desktop_workspace",
        }


_registry_lock = threading.RLock()
_registry: DesktopNativeToolRegistry | None = None


def desktop_native_tool_registry() -> DesktopNativeToolRegistry:
    global _registry
    with _registry_lock:
        if _registry is None:
            _registry = DesktopNativeToolRegistry()
        return _registry
