#!/usr/bin/env python3
"""Loopback runtime broker for a jailbroken iOS device.

This process is deliberately separate from the signed iOS application.  It only
executes through a configured Linux command prefix (for example a rootless
PROot/chroot launcher); it never falls back to a Darwin host shell.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import json
import os
import re
import shlex
import socketserver
import struct
import subprocess
import threading
import time
from collections import OrderedDict
from dataclasses import dataclass
from pathlib import Path
from typing import Any


PROTOCOL_VERSION = 1
MAX_FRAME_BYTES = 1_048_576
MAX_CLOCK_SKEW_MILLIS = 5 * 60_000
MAX_OUTPUT_BYTES = 256 * 1024
MAX_SOURCE_BYTES = 256 * 1024
MAX_SOFTWARE_SEARCH_CANDIDATES = 250
WORKSPACE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
PACKAGE_ID = re.compile(r"^[a-z0-9][a-z0-9+.-]{0,127}$")
SUPPORTED_LANGUAGES = {
    "shell", "python", "uv", "javascript", "typescript", "go", "rust",
    "c", "cpp", "java", "browser", "ffmpeg", "ffprobe",
}


class BrokerFailure(Exception):
    def __init__(self, code: str, message: str, retryable: bool = False) -> None:
        self.code = code
        self.message = message
        self.retryable = retryable
        super().__init__(message)


def canonical_json(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def signed_payload(envelope: dict[str, Any]) -> bytes:
    unsigned = dict(envelope)
    unsigned.pop("mac", None)
    return canonical_json(unsigned)


def sign(envelope: dict[str, Any], key: bytes) -> dict[str, Any]:
    signed = dict(envelope)
    signed["mac"] = base64.b64encode(hmac.new(key, signed_payload(signed), hashlib.sha256).digest()).decode("ascii")
    return signed


def is_valid_signature(envelope: dict[str, Any], key: bytes) -> bool:
    supplied = envelope.get("mac")
    if not isinstance(supplied, str):
        return False
    try:
        actual = base64.b64decode(supplied, validate=True)
    except ValueError:
        return False
    expected = hmac.new(key, signed_payload(envelope), hashlib.sha256).digest()
    return hmac.compare_digest(actual, expected)


def bounded(value: bytes) -> str:
    return value[:MAX_OUTPUT_BYTES].decode("utf-8", errors="replace")


def semantic_version_at_least(value: str, baseline: str = "1.3.9") -> bool:
    def parts(version: str) -> tuple[int, int, int]:
        match = re.match(r"^(\d+)\.(\d+)\.(\d+)", version)
        return tuple(int(part) for part in match.groups()) if match else (0, 0, 0)

    return parts(value) >= parts(baseline)


@dataclass(frozen=True)
class BrokerConfig:
    session_key: bytes
    linux_command_prefix: tuple[str, ...]
    workspace_root: Path
    linux_base_version: str
    distribution: str
    ready_command: tuple[str, ...]
    allow_package_network_refresh: bool

    @classmethod
    def load(cls, path: Path) -> "BrokerConfig":
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
            session_key = base64.b64decode(raw["session_key_b64"], validate=True)
            prefix = tuple(raw["linux_command_prefix"])
            workspace_root = Path(raw["workspace_root"]).expanduser().resolve()
            version = str(raw["linux_base_version"])
            distribution = str(raw.get("distribution", "jailbreak Linux runtime"))
            ready_command = tuple(raw.get("ready_command", ["/bin/sh", "-lc", "test -x /bin/sh"]))
            allow_package_network_refresh = bool(raw.get("allow_package_network_refresh", False))
        except (KeyError, TypeError, ValueError, OSError, json.JSONDecodeError) as error:
            raise BrokerFailure("invalid_broker_configuration", "Runtime broker configuration is invalid") from error
        if len(session_key) < 32:
            raise BrokerFailure("invalid_broker_configuration", "Runtime broker key must be at least 32 bytes")
        if not prefix or not all(isinstance(value, str) and value for value in prefix):
            raise BrokerFailure("invalid_broker_configuration", "A Linux command prefix is required")
        if not semantic_version_at_least(version):
            raise BrokerFailure("linux_base_outdated", "Linux base version must be 1.3.9 or newer")
        workspace_root.mkdir(mode=0o700, parents=True, exist_ok=True)
        return cls(session_key, prefix, workspace_root, version, distribution, ready_command, allow_package_network_refresh)


class ReplayWindow:
    def __init__(self, maximum: int = 8_192) -> None:
        self.maximum = maximum
        self.values: OrderedDict[str, None] = OrderedDict()
        self.lock = threading.Lock()

    def consume(self, request_id: str) -> bool:
        with self.lock:
            if request_id in self.values:
                return False
            self.values[request_id] = None
            if len(self.values) > self.maximum:
                self.values.popitem(last=False)
            return True


class RuntimeBroker:
    def __init__(self, config: BrokerConfig) -> None:
        self.config = config
        self.replay_window = ReplayWindow()

    def handle(self, envelope: dict[str, Any]) -> dict[str, Any]:
        try:
            self.validate_request(envelope)
            operation = envelope["operation"]
            if operation == "status":
                result = self.status()
            elif operation == "execute":
                result = self.execute(envelope.get("input", {}), envelope.get("context", {}))
            elif operation == "software.catalog":
                result = self.software_catalog()
            elif operation == "software.search":
                result = self.software_search(envelope["input"])
            elif operation == "software.inspect":
                result = self.software_inspect(envelope["input"])
            elif operation in {"software.install", "software.remove"}:
                result = self.software_mutate(operation, envelope["input"])
            else:
                raise BrokerFailure("unsupported_runtime_operation", "The iOS runtime broker does not support this operation")
            return self.response(ok=True, result=result)
        except BrokerFailure as error:
            return self.response(ok=False, error={
                "code": error.code,
                "message": error.message,
                "retryable": error.retryable,
            })
        except Exception:
            return self.response(ok=False, error={
                "code": "runtime_broker_internal_error",
                "message": "The iOS runtime broker failed without a safe diagnostic.",
                "retryable": True,
            })

    def validate_request(self, envelope: dict[str, Any]) -> None:
        if envelope.get("protocol_version") != PROTOCOL_VERSION:
            raise BrokerFailure("runtime_broker_protocol_unsupported", "Runtime broker protocol is unsupported")
        request_id = envelope.get("request_id")
        timestamp = envelope.get("timestamp_epoch_ms")
        if not isinstance(request_id, str) or not WORKSPACE_ID.fullmatch(request_id):
            raise BrokerFailure("runtime_broker_request_invalid", "Runtime broker request id is invalid")
        if not isinstance(timestamp, int) or abs(int(time.time() * 1000) - timestamp) > MAX_CLOCK_SKEW_MILLIS:
            raise BrokerFailure("runtime_broker_request_stale", "Runtime broker request is stale")
        if not is_valid_signature(envelope, self.config.session_key):
            raise BrokerFailure("runtime_broker_authentication_failed", "Runtime broker authentication failed")
        if not self.replay_window.consume(request_id):
            raise BrokerFailure("runtime_broker_request_replayed", "Runtime broker request was already processed")
        if not isinstance(envelope.get("operation"), str) or not isinstance(envelope.get("input"), dict):
            raise BrokerFailure("runtime_broker_request_invalid", "Runtime broker request is malformed")

    def response(self, ok: bool, result: dict[str, Any] | None = None, error: dict[str, Any] | None = None) -> dict[str, Any]:
        envelope: dict[str, Any] = {
            "protocol_version": PROTOCOL_VERSION,
            "timestamp_epoch_ms": int(time.time() * 1000),
            "ok": ok,
        }
        if ok:
            envelope["result"] = result or {}
        else:
            envelope["error"] = error or {"code": "runtime_broker_failed", "message": "Runtime broker failed", "retryable": False}
        return sign(envelope, self.config.session_key)

    def status(self) -> dict[str, Any]:
        ready, diagnostic = self.probe()
        return {
            "backend": "ios_jailbreak_runtime_broker",
            "backend_ready": ready,
            "reason": "Local jailbreak Linux runtime is ready" if ready else diagnostic,
            "architecture": "arm64",
            "execution_target": "ios_jailbreak_linux",
            "linux_system": {
                "distribution": self.config.distribution,
                "execution_principal": "configured_jailbreak_linux_prefix",
                "persistent": True,
                "package_managers": ["apt"],
                "package_manager_ready": ready,
                "base_version": self.config.linux_base_version,
                "package_management": "Linux guest package manager",
            },
            "runtime_pack_compatibility": "Requires matching signed iOS packs; Android QEMU packs are not executable on iOS.",
            "observed_at_epoch_ms": int(time.time() * 1000),
        }

    def probe(self) -> tuple[bool, str]:
        try:
            completed = self.run_linux(list(self.config.ready_command), self.config.workspace_root, 15_000)
        except BrokerFailure as error:
            return False, error.message
        if completed.returncode == 0:
            return True, ""
        return False, bounded(completed.stderr).strip() or "Configured Linux runtime health check failed"

    def execute(self, input_value: dict[str, Any], context: dict[str, Any]) -> dict[str, Any]:
        ready, diagnostic = self.probe()
        if not ready:
            raise BrokerFailure("runtime_backend_unavailable", diagnostic, retryable=True)
        language = input_value.get("language")
        source = input_value.get("source", "")
        arguments = input_value.get("arguments", [])
        timeout_ms = input_value.get("timeout_ms", 30_000)
        workspace_id = context.get("workspace_id")
        if language not in SUPPORTED_LANGUAGES or not isinstance(source, str) or not isinstance(arguments, list):
            raise BrokerFailure("runtime_execute_input_invalid", "Runtime execution input is invalid")
        if input_value.get("network_enabled") is True:
            raise BrokerFailure(
                "runtime_network_policy_unavailable",
                "The jailbreak runtime broker currently accepts offline execution only",
            )
        if len(source.encode("utf-8")) > MAX_SOURCE_BYTES or any(not isinstance(item, str) or len(item) > 8_192 for item in arguments):
            raise BrokerFailure("runtime_execute_input_invalid", "Runtime execution input exceeds limits")
        if not isinstance(workspace_id, str) or not WORKSPACE_ID.fullmatch(workspace_id):
            raise BrokerFailure("runtime_workspace_invalid", "Runtime workspace is invalid")
        if not isinstance(timeout_ms, int) or not 100 <= timeout_ms <= 30 * 60_000:
            raise BrokerFailure("runtime_timeout_invalid", "Runtime timeout is invalid")
        workspace = (self.config.workspace_root / workspace_id).resolve()
        if workspace.parent != self.config.workspace_root:
            raise BrokerFailure("runtime_workspace_invalid", "Runtime workspace escaped its root")
        workspace.mkdir(mode=0o700, parents=True, exist_ok=True)
        command = self.execution_command(language, source, arguments, workspace)
        completed = self.run_linux(command, workspace, timeout_ms)
        return {
            "message": "iOS jailbreak Linux execution completed" if completed.returncode == 0 else "iOS jailbreak Linux execution failed",
            "exit_code": completed.returncode,
            "stdout": bounded(completed.stdout),
            "stderr": bounded(completed.stderr),
            "workspace_id": workspace_id,
            "backend": "ios_jailbreak_runtime_broker",
        }

    def software_catalog(self) -> dict[str, Any]:
        ready, diagnostic = self.probe()
        if not ready:
            raise BrokerFailure("runtime_backend_unavailable", diagnostic, retryable=True)
        return {
            "linux_ready": True,
            "sources": [{
                "id": "linux_package", "trusted": False, "searchable": True,
                "install_tool_id": "signalasi.runtime.software.install",
                "network_refresh_allowed": self.config.allow_package_network_refresh,
            }],
            "observed_at_epoch_ms": int(time.time() * 1000),
        }

    def software_search(self, input_value: dict[str, Any]) -> dict[str, Any]:
        query = input_value.get("query")
        if not isinstance(query, str) or not 1 <= len(query.strip()) <= 160 or any(ord(char) < 32 for char in query):
            raise BrokerFailure("runtime_software_input_invalid", "Software search query is invalid")
        query = query.strip()
        limit = input_value.get("limit", 20)
        if not isinstance(limit, int) or not 1 <= limit <= 50:
            raise BrokerFailure("runtime_software_input_invalid", "Software search limit is invalid")
        self.ensure_package_index()
        command = [
            "/bin/sh", "-lc",
            f"apt-cache search --names-only -- {shlex.quote(query)} | head -n {MAX_SOFTWARE_SEARCH_CANDIDATES}",
        ]
        completed = self.run_linux(command, self.config.workspace_root, 10 * 60_000)
        self.require_success(completed, "Linux package search failed")
        results = []
        for line in bounded(completed.stdout).splitlines():
            package, _, description = line.partition(" - ")
            if PACKAGE_ID.fullmatch(package):
                results.append({"software_id": package, "source": "linux_package", "description": description, "installed": False})
        return {
            "query": query,
            "results": self.rank_software_search_results(results, query, limit),
            "source_errors": [],
            "observed_at_epoch_ms": int(time.time() * 1000),
        }

    @staticmethod
    def rank_software_search_results(
        results: list[dict[str, Any]], query: str, limit: int
    ) -> list[dict[str, Any]]:
        normalized = query.strip().lower()
        deduplicated: dict[str, dict[str, Any]] = {}
        for result in results:
            package = result.get("software_id")
            if isinstance(package, str) and PACKAGE_ID.fullmatch(package):
                deduplicated.setdefault(package, result)

        def rank(result: dict[str, Any]) -> tuple[int, str]:
            package = str(result["software_id"]).lower()
            description = str(result.get("description", "")).lower()
            if package == normalized:
                return 0, package
            if package.startswith(normalized):
                return 1, package
            if normalized in package:
                return 2, package
            if normalized in description:
                return 3, package
            return 4, package

        return sorted(deduplicated.values(), key=rank)[:limit]

    def software_inspect(self, input_value: dict[str, Any]) -> dict[str, Any]:
        package = self.package_id(input_value.get("software_id"), "software id")
        self.ensure_package_index()
        script = f"apt-cache policy {package}; dpkg-query -W -f='installed=%{{Status}}\\nversion=%{{Version}}\\n' {package} 2>/dev/null || true"
        completed = self.run_linux(["/bin/sh", "-lc", script], self.config.workspace_root, 10 * 60_000)
        self.require_success(completed, "Linux package inspection failed")
        output = bounded(completed.stdout)
        return {"software_id": package, "source": "linux_package", "details": output, "installed": "install ok installed" in output}

    def software_mutate(self, operation: str, input_value: dict[str, Any]) -> dict[str, Any]:
        package = self.package_id(input_value.get("software_id"), "software id")
        if not self.config.allow_package_network_refresh:
            raise BrokerFailure("runtime_package_network_not_authorized", "Allow package network refresh in the local broker configuration first")
        verb = "install" if operation == "software.install" else "remove"
        refreshed = self.run_linux(["apt-get", "update"], self.config.workspace_root, 10 * 60_000)
        self.require_success(refreshed, "Linux package index refresh failed")
        completed = self.run_linux(
            ["apt-get", "-y", "--no-install-recommends", verb, package],
            self.config.workspace_root,
            30 * 60_000,
        )
        self.require_success(completed, f"Linux package {verb} failed")
        return {"software_id": package, "source": "linux_package", "operation": verb, "installed": verb == "install", "stdout": bounded(completed.stdout)}

    def ensure_package_index(self) -> None:
        check = self.run_linux(["/bin/sh", "-lc", "find /var/lib/apt/lists -maxdepth 1 -type f -name '*_Packages' -print -quit | grep -q ."], self.config.workspace_root, 15_000)
        if check.returncode == 0:
            return
        if not self.config.allow_package_network_refresh:
            raise BrokerFailure("runtime_package_index_missing", "Linux package index is missing and network refresh is not authorized", retryable=True)
        refreshed = self.run_linux(["apt-get", "update"], self.config.workspace_root, 10 * 60_000)
        self.require_success(refreshed, "Linux package index refresh failed")

    @staticmethod
    def package_id(value: Any, label: str) -> str:
        if not isinstance(value, str) or not PACKAGE_ID.fullmatch(value):
            raise BrokerFailure("runtime_software_input_invalid", f"{label} is invalid")
        return value

    def execution_command(self, language: str, source: str, arguments: list[str], workspace: Path) -> list[str]:
        names = {
            "shell": ("main.sh", ["/bin/sh", "main.sh"]),
            "python": ("main.py", ["python3", "main.py"]),
            "uv": ("main.py", ["uv", "run", "python", "main.py"]),
            "javascript": ("main.js", ["node", "main.js"]),
            "typescript": ("main.ts", ["tsx", "main.ts"]),
            "go": ("main.go", ["go", "run", "main.go"]),
            "rust": ("main.rs", ["rustc", "main.rs", "-o", ".signalasi-main"]),
            "c": ("main.c", ["cc", "main.c", "-o", ".signalasi-main"]),
            "cpp": ("main.cpp", ["c++", "main.cpp", "-o", ".signalasi-main"]),
            "java": ("Main.java", ["javac", "Main.java"]),
        }
        if language in {"ffmpeg", "ffprobe", "browser"}:
            executable = {"ffmpeg": "ffmpeg", "ffprobe": "ffprobe", "browser": "signalasi-browser"}[language]
            return [executable, *arguments]
        file_name, command = names[language]
        source_path = workspace / file_name
        source_path.write_text(source, encoding="utf-8")
        os.chmod(source_path, 0o600)
        if language in {"rust", "c", "cpp"}:
            self.require_success(self.run_linux(command, workspace, 120_000), "Runtime compilation failed")
            return ["./.signalasi-main", *arguments]
        if language == "java":
            self.require_success(self.run_linux(command, workspace, 120_000), "Runtime compilation failed")
            return ["java", "-cp", ".", "Main", *arguments]
        return [*command, *arguments]

    def run_linux(self, command: list[str], workspace: Path, timeout_ms: int) -> subprocess.CompletedProcess[bytes]:
        prefix = [part.replace("{workspace}", str(workspace)) for part in self.config.linux_command_prefix]
        if any("{" in part or "}" in part for part in prefix):
            raise BrokerFailure("invalid_broker_configuration", "Linux command prefix has an unsupported placeholder")
        try:
            return subprocess.run(
                [*prefix, *command],
                cwd=workspace,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=timeout_ms / 1_000,
                check=False,
                env={"PATH": "/usr/bin:/bin", "HOME": "/workspace", "LC_ALL": "C.UTF-8"},
            )
        except subprocess.TimeoutExpired as error:
            raise BrokerFailure("runtime_execution_timeout", "Linux execution timed out", retryable=True) from error
        except OSError as error:
            raise BrokerFailure("runtime_backend_unavailable", "Configured Linux runtime could not start", retryable=True) from error

    @staticmethod
    def require_success(completed: subprocess.CompletedProcess[bytes], message: str) -> None:
        if completed.returncode != 0:
            raise BrokerFailure("runtime_compilation_failed", message + ": " + bounded(completed.stderr).strip())


def read_frame(stream: Any) -> dict[str, Any]:
    header = read_exact(stream, 4)
    size = struct.unpack(">I", header)[0]
    if not 1 <= size <= MAX_FRAME_BYTES:
        raise BrokerFailure("runtime_broker_frame_invalid", "Runtime broker frame is invalid")
    payload = read_exact(stream, size)
    try:
        value = json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise BrokerFailure("runtime_broker_frame_invalid", "Runtime broker payload is invalid") from error
    if not isinstance(value, dict):
        raise BrokerFailure("runtime_broker_frame_invalid", "Runtime broker payload must be an object")
    return value


def read_exact(stream: Any, size: int) -> bytes:
    chunks: list[bytes] = []
    remaining = size
    while remaining:
        chunk = stream.read(remaining)
        if not chunk:
            raise EOFError
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


class BrokerHandler(socketserver.StreamRequestHandler):
    def handle(self) -> None:
        try:
            response = self.server.runtime_broker.handle(read_frame(self.rfile))  # type: ignore[attr-defined]
        except EOFError:
            return
        except BrokerFailure as error:
            response = self.server.runtime_broker.response(False, error={  # type: ignore[attr-defined]
                "code": error.code, "message": error.message, "retryable": error.retryable,
            })
        payload = canonical_json(response)
        self.wfile.write(struct.pack(">I", len(payload)) + payload)
        self.wfile.flush()


class LoopbackServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

    def __init__(self, broker: RuntimeBroker, port: int) -> None:
        self.runtime_broker = broker
        super().__init__(("127.0.0.1", port), BrokerHandler)


def main() -> int:
    parser = argparse.ArgumentParser(description="SignalASI jailbroken iOS Linux runtime broker")
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--port", type=int, default=39_761)
    args = parser.parse_args()
    config = BrokerConfig.load(args.config)
    if not 1 <= args.port <= 65_535:
        raise BrokerFailure("invalid_broker_configuration", "Runtime broker port is invalid")
    with LoopbackServer(RuntimeBroker(config), args.port) as server:
        server.serve_forever(poll_interval=0.5)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BrokerFailure as error:
        raise SystemExit(error.message)
