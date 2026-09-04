#!/usr/bin/env python3
"""GalaxySSI Linux guest execution service."""

from __future__ import annotations

import base64
import hashlib
import hmac
import ipaddress
import json
import os
import re
import secrets
import shlex
import shutil
import signal
import stat
import struct
import subprocess
import threading
import time
import uuid
from collections import OrderedDict
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, BinaryIO

from galaxyssi_network_proxy import AllowlistedHttpProxy


PROTOCOL_VERSION = 1
MAX_FRAME_BYTES = 1024 * 1024
MAX_CLOCK_SKEW_MILLIS = 5 * 60_000
CHANNEL_NAME = "org.galaxyssi.runtime"
VIRTIO_PORT_CLASS_ROOT = Path("/sys/class/virtio-ports")
DEVICE_ROOT = Path("/dev")
SESSION_PATH = Path("/sys/firmware/qemu_fw_cfg/by_name/opt/com.galaxyssi/runtime-session/raw")
CONFIG_PATH = Path("/sys/firmware/qemu_fw_cfg/by_name/opt/com.galaxyssi/runtime-config/raw")
WORKSPACE_ROOT = Path("/workspace")
ISOLATED_WORKSPACE_ROOT = Path("/work")
RUNTIME_CONTROL_DIRECTORY = ".galaxyssi-runtime"
PERSISTENT_SYSTEM_ROOT = Path("/var/lib/galaxyssi")
PERSISTENT_USERSPACE_ROOT = PERSISTENT_SYSTEM_ROOT / "rootfs"
PERSISTENT_USERSPACE_ARCHIVE = Path("/usr/share/galaxyssi/debian-13-slim-arm64-rootfs.tar.gz")
PERSISTENT_USERSPACE_DIGEST = "1b7200988f192e72703c70486d494e2457935ac9b0f031ac09eb115b01a12d45"
HOST_RUNTIME_LIBRARY_DIRECTORIES = (Path("/lib"), Path("/usr/lib"))
PERSISTENT_RUNTIME_LIBRARY_NAMES = ("libstdc++.so.6", "libgcc_s.so.1")
PERSISTENT_HOST_ROOT = PurePosixPath("/run/galaxyssi-host")
PERSISTENT_HOST_TOOL_NAMES = ("git", "ssh", "curl", "wget")
PERSISTENT_HOST_DYNAMIC_LOADER = PERSISTENT_HOST_ROOT / "lib" / "ld-linux-aarch64.so.1"
PERSISTENT_HOST_LIBRARY_PATH = (
    PERSISTENT_HOST_ROOT / "lib",
    PERSISTENT_HOST_ROOT / "usr" / "lib",
)
PERSISTENT_GIT_EXEC_WRAPPER_ROOT = PurePosixPath("/usr/local/libexec/galaxyssi-git-core")
PERSISTENT_HOST_BINDINGS = (
    Path("/usr"),
    Path("/lib"),
    Path("/bin"),
    Path("/etc/ssl"),
    Path("/etc/ssh"),
)
PACK_ROOT = Path("/opt/galaxyssi/packs")
PACK_NAMESPACE_ROOT = PACK_ROOT.parent
PACK_DESCRIPTOR_NAME = "galaxyssi-pack.json"
LAUNCHER_PATH = Path("/usr/libexec/galaxyssi-runtime-launcher")
REQUEST_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
MAX_SEQUENCE_WINDOWS = 8192
MAX_CONCURRENT_EXECUTIONS = 16
MIN_TRUSTED_EPOCH_MILLIS = 1_577_836_800_000
MAX_TRUSTED_EPOCH_MILLIS = 4_102_444_800_000
PACK_ENTRYPOINTS = {
    "python-uv": ("bin/python3", "bin/uv"),
    "node-js": ("bin/node", "bin/tsx"),
    "go": ("bin/go",),
    "rust": ("bin/rustc",),
    "cpp": ("bin/cc", "bin/c++"),
    "java": ("bin/java", "bin/javac"),
    "gradle": ("bin/gradle",),
    "android-sdk": ("bin/aapt2", "bin/aidl", "bin/zipalign", "bin/apksigner", "bin/d8"),
    "browser-automation": ("bin/galaxyssi-browser", "bin/playwright"),
    "ffmpeg": ("bin/ffmpeg", "bin/ffprobe"),
}
PACK_REQUIRED_CAPABILITIES = {
    "python-uv": {"python.execute", "uv.sync"},
    "node-js": {"javascript.execute", "typescript.execute"},
    "go": {"go.execute"},
    "rust": {"rust.execute"},
    "cpp": {"c.execute", "cpp.execute"},
    "java": {"java.execute"},
    "gradle": {"gradle.execute"},
    "android-sdk": {"android.build", "android.package", "android.sign"},
    "browser-automation": {"browser.automation.execute"},
    "ffmpeg": {"ffmpeg.execute", "ffprobe.inspect"},
}


def canonical_json(value: Any) -> str:
    validate_canonical_value(value)
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def validate_canonical_value(value: Any) -> None:
    if value is None or isinstance(value, bool):
        return
    if isinstance(value, str):
        try:
            value.encode("utf-8")
        except UnicodeEncodeError as error:
            raise ValueError("Runtime payload contains invalid Unicode") from error
        return
    if isinstance(value, int):
        if not -(2**63) <= value <= 2**63 - 1:
            raise ValueError("Runtime payload integer is outside the signed 64-bit range")
        return
    if isinstance(value, float):
        raise ValueError("Runtime payload numbers must be signed 64-bit integers")
    if isinstance(value, list):
        for item in value:
            validate_canonical_value(item)
        return
    if isinstance(value, dict):
        for key, item in value.items():
            if not isinstance(key, str):
                raise ValueError("Runtime payload key must be a string")
            validate_canonical_value(item)
        return
    raise ValueError("Runtime payload value is unsupported")


def unsigned_payload(envelope: dict[str, Any]) -> bytes:
    values = (
        str(envelope["protocol_version"]),
        envelope["message_id"],
        envelope["request_id"],
        envelope["type"],
        str(envelope["sequence"]),
        str(envelope["timestamp_millis"]),
        canonical_json(envelope.get("payload", {})),
    )
    return "\n".join(values).encode("utf-8")


def sign_envelope(envelope: dict[str, Any], session_key: bytes) -> dict[str, Any]:
    if len(session_key) < 32:
        raise ValueError("Runtime session key is too short")
    signed = dict(envelope)
    signed["mac"] = base64.b64encode(
        hmac.new(session_key, unsigned_payload(signed), hashlib.sha256).digest()
    ).decode("ascii")
    return signed


def verify_envelope(envelope: dict[str, Any], session_key: bytes, now_millis: int | None = None) -> bool:
    try:
        if int(envelope["protocol_version"]) != PROTOCOL_VERSION:
            return False
        if not envelope["message_id"] or not envelope["request_id"] or int(envelope["sequence"]) < 1:
            return False
        now = int(time.time() * 1000) if now_millis is None else now_millis
        if abs(now - int(envelope["timestamp_millis"])) > MAX_CLOCK_SKEW_MILLIS:
            return False
        supplied = base64.b64decode(envelope["mac"], validate=True)
        expected = hmac.new(session_key, unsigned_payload(envelope), hashlib.sha256).digest()
        return hmac.compare_digest(supplied, expected)
    except (KeyError, TypeError, ValueError):
        return False


def read_exact(stream: BinaryIO, size: int) -> bytes:
    output = bytearray()
    while len(output) < size:
        chunk = stream.read(size - len(output))
        if not chunk:
            raise EOFError("Runtime channel closed")
        output.extend(chunk)
    return bytes(output)


def read_frame(stream: BinaryIO) -> dict[str, Any]:
    size = struct.unpack(">I", read_exact(stream, 4))[0]
    if size < 1 or size > MAX_FRAME_BYTES:
        raise ValueError("Runtime protocol frame size is invalid")
    value = json.loads(read_exact(stream, size).decode("utf-8"))
    if not isinstance(value, dict):
        raise ValueError("Runtime protocol frame is invalid")
    return value


def write_frame(stream: BinaryIO, envelope: dict[str, Any]) -> None:
    payload = canonical_json(envelope).encode("utf-8")
    if len(payload) > MAX_FRAME_BYTES:
        raise ValueError("Runtime protocol frame is too large")
    stream.write(struct.pack(">I", len(payload)))
    stream.write(payload)
    stream.flush()


@dataclass(frozen=True)
class ExecutionLimits:
    wall_clock_ms: int
    cpu_ms: int
    memory_bytes: int
    disk_bytes: int
    max_processes: int
    max_output_bytes: int
    max_artifact_bytes: int

    @classmethod
    def from_payload(cls, payload: dict[str, Any]) -> "ExecutionLimits":
        value = payload.get("limits") or {}
        limits = cls(
            wall_clock_ms=int(value.get("wall_clock_ms", 60_000)),
            cpu_ms=int(value.get("cpu_ms", 45_000)),
            memory_bytes=int(value.get("memory_bytes", 512 * 1024 * 1024)),
            disk_bytes=int(value.get("disk_bytes", 512 * 1024 * 1024)),
            max_processes=int(value.get("max_processes", 64)),
            max_output_bytes=int(value.get("max_output_bytes", 512 * 1024)),
            max_artifact_bytes=int(value.get("max_artifact_bytes", 256 * 1024 * 1024)),
        )
        if not 100 <= limits.wall_clock_ms <= 30 * 60_000:
            raise ValueError("Runtime wall-clock limit is invalid")
        if not 100 <= limits.cpu_ms <= limits.wall_clock_ms:
            raise ValueError("Runtime CPU limit is invalid")
        if not 32 * 1024 * 1024 <= limits.memory_bytes <= 4 * 1024 * 1024 * 1024:
            raise ValueError("Runtime memory limit is invalid")
        if not 8 * 1024 * 1024 <= limits.disk_bytes <= 8 * 1024 * 1024 * 1024:
            raise ValueError("Runtime disk limit is invalid")
        if not 1 <= limits.max_processes <= 512:
            raise ValueError("Runtime process limit is invalid")
        if not 1024 <= limits.max_output_bytes <= 4 * 1024 * 1024:
            raise ValueError("Runtime output limit is invalid")
        if not 1024 <= limits.max_artifact_bytes <= 2 * 1024 * 1024 * 1024:
            raise ValueError("Runtime artifact limit is invalid")
        return limits


def resolve_workspace(raw_path: str) -> Path:
    candidate = Path(raw_path)
    if not candidate.is_absolute():
        raise ValueError("Runtime workspace path is invalid")
    resolved_root = WORKSPACE_ROOT.resolve()
    resolved = candidate.resolve()
    if resolved == resolved_root or resolved_root not in resolved.parents:
        raise ValueError("Runtime workspace path escapes the shared root")
    if not resolved.is_dir():
        raise ValueError("Runtime workspace is unavailable")
    return resolved


def executable(name: str, search_path: str | None = None) -> str:
    for directory in (search_path if search_path is not None else os.environ.get("PATH", "")).split(os.pathsep):
        if not directory:
            continue
        candidate = Path(directory) / name
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    raise FileNotFoundError(f"Runtime executable is unavailable: {name}")


def command_plan(
    language: str,
    workspace: Path,
    arguments: list[str],
    search_path: str | None = None,
) -> list[list[str]]:
    if any("\x00" in item or len(item.encode("utf-8")) > 8192 for item in arguments):
        raise ValueError("Runtime argument is invalid")
    control = workspace / RUNTIME_CONTROL_DIRECTORY
    if language == "shell":
        return [[executable("sh", search_path), str(control / "main.sh"), *arguments]]
    if language == "python":
        return [[executable("python3", search_path), str(control / "main.py"), *arguments]]
    if language == "uv":
        return [[executable("uv", search_path), "run", "--no-cache", "--offline", str(control / "main.py"), *arguments]]
    if language == "javascript":
        return [[executable("node", search_path), str(control / "main.js"), *arguments]]
    if language == "typescript":
        return [[executable("tsx", search_path), str(control / "main.ts"), *arguments]]
    if language == "go":
        return [[executable("go", search_path), "run", str(control / "main.go"), *arguments]]
    if language == "rust":
        return [
            [executable("rustc", search_path), str(control / "main.rs"), "-o", str(control / "main")],
            [str(control / "main"), *arguments],
        ]
    if language == "c":
        return [
            [executable("cc", search_path), str(control / "main.c"), "-O2", "-o", str(control / "main")],
            [str(control / "main"), *arguments],
        ]
    if language == "cpp":
        return [
            [executable("c++", search_path), str(control / "main.cpp"), "-O2", "-o", str(control / "main")],
            [str(control / "main"), *arguments],
        ]
    if language == "java":
        return [
            [executable("javac", search_path), "-d", str(control), str(control / "Main.java")],
            [executable("java", search_path), "-cp", str(control), "Main", *arguments],
        ]
    if language == "browser":
        return [[executable("galaxyssi-browser", search_path), str(control / "main.browser.js"), *arguments]]
    if language == "ffmpeg":
        return [[executable("ffmpeg", search_path), "-nostdin", *arguments]]
    if language == "ffprobe":
        return [[executable("ffprobe", search_path), *arguments]]
    raise ValueError("Runtime language is invalid")


def positive_config_id(config: dict[str, Any], name: str) -> int:
    value = int(config.get(name, 0))
    if not 1 <= value <= 2_147_483_646:
        raise ValueError(f"Runtime {name} is invalid")
    return value


def launcher_plan(
    config: dict[str, Any],
    workspace: Path,
    limits: ExecutionLimits,
    command: list[str],
    allow_network_proxy: bool = False,
) -> list[str]:
    if not LAUNCHER_PATH.is_file() or not os.access(LAUNCHER_PATH, os.X_OK):
        raise FileNotFoundError("Runtime sandbox launcher is unavailable")
    return [
        str(LAUNCHER_PATH),
        "--workspace",
        str(workspace),
        "--uid",
        str(positive_config_id(config, "workspace_uid")),
        "--gid",
        str(positive_config_id(config, "workspace_gid")),
        "--cpu-seconds",
        str(max(1, (limits.cpu_ms + 999) // 1000)),
        "--memory-bytes",
        str(limits.memory_bytes),
        "--max-processes",
        str(limits.max_processes),
        "--file-size-bytes",
        str(limits.disk_bytes),
        "--network-mode",
        "proxy" if allow_network_proxy else "isolated",
        "--",
        *command,
    ]


def full_access_enabled(config: dict[str, Any]) -> bool:
    return (
        config.get("execution_mode") == "full_access"
        and config.get("execution_principal") == "root"
    )


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def execution_plan(
    config: dict[str, Any],
    workspace: Path,
    limits: ExecutionLimits,
    command: list[str],
    allow_network_proxy: bool = False,
) -> list[str]:
    if full_access_enabled(config):
        return [
            "chroot",
            str(PERSISTENT_USERSPACE_ROOT),
            "/bin/sh",
            "-c",
            'cd "$1" && shift && exec "$@"',
            "galaxyssi",
            str(workspace),
            *command,
        ]
    return launcher_plan(config, workspace, limits, command, allow_network_proxy)


def prepare_private_directory(path: Path) -> None:
    try:
        path.mkdir(mode=0o700)
    except FileExistsError:
        pass
    metadata = path.lstat()
    if not stat.S_ISDIR(metadata.st_mode) or path.is_symlink():
        raise ValueError("Runtime private directory is unsafe")
    path.chmod(0o700)


def prepare_runtime_temp_directories(environment: dict[str, str], full_access: bool) -> None:
    if not full_access:
        return
    task_temp = Path(environment["TMPDIR"])
    prepare_private_directory(task_temp.parent)
    prepare_private_directory(task_temp)


def open_private_output(path: Path) -> BinaryIO:
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags, 0o600)
    return os.fdopen(descriptor, "wb")


def stop_process(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=1)
        return
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def bounded_read(path: Path, limit: int) -> tuple[str, bool]:
    with path.open("rb") as stream:
        data = stream.read(limit + 1)
    truncated = len(data) > limit
    return data[:limit].decode("utf-8", errors="replace"), truncated


def capture_repository_fingerprint(
    config: dict[str, Any],
    workspace: Path,
    environment: dict[str, str],
    limits: ExecutionLimits,
) -> tuple[str, bool]:
    """Return the Git working-tree digest from the same trusted guest execution."""
    script = r'''
git() { command git -c safe.directory="$PWD" "$@"; }
if ! command -v git >/dev/null 2>&1 || ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi
{
  printf '%s\n' '__GALAXYSSI_HEAD__'
  git rev-parse --verify HEAD 2>/dev/null || true
  printf '%s\n' '__GALAXYSSI_STATUS__'
  git status --porcelain=v2 --untracked-files=all
  printf '%s\n' '__GALAXYSSI_TRACKED_DIFF__'
  if git rev-parse --verify HEAD >/dev/null 2>&1; then
    git diff --no-ext-diff --binary HEAD --
  else
    git diff --cached --no-ext-diff --binary --
  fi
  printf '%s\n' '__GALAXYSSI_UNTRACKED_CONTENT__'
  git ls-files --others --exclude-standard -z |
    xargs -0 -r git -c safe.directory="$PWD" hash-object --no-filters --
} | sha256sum | awk '{ print $1 }'
'''.strip()
    try:
        result = subprocess.run(
            execution_plan(
                config,
                workspace,
                limits,
                ["/bin/sh", "-c", script],
            ),
            cwd=workspace,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=environment,
            timeout=max(1.0, min(30.0, limits.wall_clock_ms / 1000.0)),
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return "", False
    fingerprint = result.stdout.decode("ascii", errors="ignore").strip()
    if result.returncode != 0:
        return "", False
    if not fingerprint:
        return "", True
    if re.fullmatch(r"[0-9a-f]{64}", fingerprint) is None:
        return "", False
    return fingerprint, True


def bounded_directory_size(path: Path, limit: int) -> int:
    total = 0
    for root, directories, files in os.walk(path, followlinks=False):
        directories[:] = [name for name in directories if not (Path(root) / name).is_symlink()]
        for name in files:
            candidate = Path(root) / name
            if candidate.is_symlink():
                continue
            total += candidate.stat().st_size
            if total > limit:
                return total
    return total


class GuestService:
    def __init__(self, stream: BinaryIO, session_key: bytes, config: dict[str, Any]):
        self.stream = stream
        self.session_key = session_key
        self.config = config
        self.write_lock = threading.Lock()
        self.state_lock = threading.Lock()
        self.inbound_sequences: OrderedDict[str, int] = OrderedDict()
        self.outbound_sequences: OrderedDict[str, int] = OrderedDict()
        self.cancellations: dict[str, threading.Event] = {}

    def send(self, request_id: str, message_type: str, payload: dict[str, Any] | None = None) -> None:
        with self.write_lock:
            sequence = self.outbound_sequences.get(request_id, 0) + 1
            self.outbound_sequences[request_id] = sequence
            self.outbound_sequences.move_to_end(request_id)
            while len(self.outbound_sequences) > MAX_SEQUENCE_WINDOWS:
                self.outbound_sequences.popitem(last=False)
            envelope = sign_envelope(
                {
                    "protocol_version": PROTOCOL_VERSION,
                    "message_id": str(uuid.uuid4()),
                    "request_id": request_id,
                    "type": message_type,
                    "sequence": sequence,
                    "timestamp_millis": int(time.time() * 1000),
                    "payload": payload or {},
                    "mac": "",
                },
                self.session_key,
            )
            write_frame(self.stream, envelope)

    def serve(self) -> None:
        while True:
            envelope = read_frame(self.stream)
            if not verify_envelope(envelope, self.session_key):
                raise ValueError("Runtime protocol authentication failed")
            request_id = str(envelope["request_id"])
            if not REQUEST_ID_PATTERN.fullmatch(request_id):
                raise ValueError("Runtime request id is invalid")
            sequence = int(envelope["sequence"])
            if sequence <= self.inbound_sequences.get(request_id, 0):
                raise ValueError("Runtime protocol frame is replayed or out of order")
            self.inbound_sequences[request_id] = sequence
            self.inbound_sequences.move_to_end(request_id)
            while len(self.inbound_sequences) > MAX_SEQUENCE_WINDOWS:
                oldest_request_id = next(iter(self.inbound_sequences))
                with self.state_lock:
                    is_active = oldest_request_id in self.cancellations
                if is_active:
                    self.inbound_sequences.move_to_end(oldest_request_id)
                    continue
                self.inbound_sequences.popitem(last=False)
            message_type = envelope["type"]
            if message_type == "hello":
                ready, reason = runtime_readiness(self.config)
                self.send(
                    request_id,
                    "hello_ack",
                    {
                        "guest_api_version": PROTOCOL_VERSION,
                        "guest_version": "1.3.9",
                        "ready": ready,
                        "reason": reason,
                        "capabilities": [
                            "runtime.execute",
                            "runtime.cancel",
                            "runtime.progress",
                            "runtime.concurrent",
                            "runtime.secret_environment",
                            "runtime.full_access",
                            "runtime.persistent_system",
                        ],
                        "execution_mode": "full_access" if full_access_enabled(self.config) else "restricted",
                        "execution_principal": "root" if full_access_enabled(self.config) else "workspace",
                    },
                )
            elif message_type == "heartbeat":
                ready, reason = runtime_readiness(self.config)
                self.send(request_id, "heartbeat_ack", {"ready": ready, "reason": reason})
            elif message_type == "execute":
                self.start_execution(request_id, envelope.get("payload") or {})
            elif message_type == "cancel":
                with self.state_lock:
                    event = self.cancellations.get(request_id)
                if event is not None:
                    event.set()
            else:
                self.send(request_id, "error", {"message": "Unsupported runtime request"})

    def start_execution(self, request_id: str, payload: dict[str, Any]) -> None:
        with self.state_lock:
            if request_id in self.cancellations:
                self.send(request_id, "error", {"message": "Runtime request is already active"})
                return
            if len(self.cancellations) >= MAX_CONCURRENT_EXECUTIONS:
                self.send(request_id, "error", {"message": "Runtime concurrency limit reached"})
                return
            cancellation = threading.Event()
            self.cancellations[request_id] = cancellation
        threading.Thread(
            target=self.execute,
            args=(request_id, payload, cancellation),
            name=f"galaxyssi-exec-{request_id[:12]}",
            daemon=True,
        ).start()

    def execute(self, request_id: str, payload: dict[str, Any], cancellation: threading.Event) -> None:
        started = time.monotonic()
        network_proxy: AllowlistedHttpProxy | None = None
        try:
            workspace = resolve_workspace(str(payload.get("workspace_path", "")))
            language = str(payload.get("language", ""))
            arguments = payload.get("arguments") or []
            if not isinstance(arguments, list) or len(arguments) > 256:
                raise ValueError("Runtime arguments are invalid")
            limits = ExecutionLimits.from_payload(payload)
            network = payload.get("network") or {}
            full_access = full_access_enabled(self.config)
            command_workspace = workspace if full_access else ISOLATED_WORKSPACE_ROOT
            environment = runtime_environment(command_workspace, full_access=full_access)
            if bool(network.get("enabled")) and not full_access:
                allowed_domains = network.get("allowed_domains") or []
                if not isinstance(allowed_domains, list) or any(not isinstance(value, str) for value in allowed_domains):
                    raise ValueError("Runtime network allowlist is invalid")
                network_proxy = AllowlistedHttpProxy(
                    allowed_domains=allowed_domains,
                    token=secrets.token_urlsafe(32),
                    max_transfer_bytes=limits.disk_bytes,
                )
                proxy_environment = network_proxy.start().values
                proxy_gradle_options = proxy_environment.pop("GRADLE_OPTS", "")
                environment.update(proxy_environment)
                environment["GRADLE_OPTS"] = " ".join(
                    value for value in (environment.get("GRADLE_OPTS", ""), proxy_gradle_options) if value
                )
            inject_secret_environment(environment, payload.get("secret_environment"))
            commands = command_plan(
                language,
                command_workspace,
                [str(value) for value in arguments],
                environment["PATH"],
            )
            stdout_path = workspace / ".galaxyssi-stdout"
            stderr_path = workspace / ".galaxyssi-stderr"
            prepare_private_directory(workspace / ".tmp")
            prepare_runtime_temp_directories(environment, full_access)
            self.send(request_id, "progress", {"stage": "starting", "message": "Runtime started", "percent": 5})
            exit_code = 0
            with open_private_output(stdout_path) as stdout, open_private_output(stderr_path) as stderr:
                for index, command in enumerate(commands):
                    if cancellation.is_set():
                        self.send(request_id, "cancelled")
                        return
                    process = subprocess.Popen(
                        execution_plan(
                            self.config,
                            workspace,
                            limits,
                            command,
                            allow_network_proxy=network_proxy is not None,
                        ),
                        cwd=workspace,
                        stdin=subprocess.DEVNULL,
                        stdout=stdout,
                        stderr=stderr,
                        env=environment,
                        start_new_session=True,
                        umask=0o077,
                    )
                    next_quota_check = 0.0
                    while process.poll() is None:
                        now = time.monotonic()
                        elapsed_ms = int((now - started) * 1000)
                        if cancellation.is_set():
                            stop_process(process)
                            self.send(request_id, "cancelled")
                            return
                        if not full_access and elapsed_ms > limits.wall_clock_ms:
                            stop_process(process)
                            raise TimeoutError("Runtime wall-clock limit exceeded")
                        output_size = stdout_path.stat().st_size + stderr_path.stat().st_size
                        if not full_access and output_size > limits.max_output_bytes:
                            stop_process(process)
                            raise ValueError("Runtime output limit exceeded")
                        if not full_access and now >= next_quota_check:
                            if bounded_directory_size(workspace, limits.disk_bytes) > limits.disk_bytes:
                                stop_process(process)
                                raise ValueError("Runtime workspace limit exceeded")
                            next_quota_check = now + 0.25
                        time.sleep(0.05)
                    exit_code = int(process.returncode or 0)
                    if exit_code != 0:
                        break
                    percent = 10 + int(((index + 1) / len(commands)) * 80)
                    self.send(request_id, "progress", {"stage": "running", "message": "Runtime step completed", "percent": percent})
            stdout_value, stdout_truncated = bounded_read(stdout_path, limits.max_output_bytes)
            stderr_value, stderr_truncated = bounded_read(stderr_path, limits.max_output_bytes)
            project_fingerprint = ""
            project_fingerprint_checked = False
            if exit_code == 0 and bool(payload.get("capture_project_fingerprint")):
                project_fingerprint, project_fingerprint_checked = capture_repository_fingerprint(
                    self.config,
                    workspace,
                    environment,
                    limits,
                )
            self.send(
                request_id,
                "result",
                {
                    "exit_code": exit_code,
                    "stdout": stdout_value,
                    "stderr": stderr_value,
                    "output_truncated": stdout_truncated or stderr_truncated,
                    "duration_ms": int((time.monotonic() - started) * 1000),
                    "artifacts": [],
                    "project_fingerprint": project_fingerprint,
                    "project_fingerprint_checked": project_fingerprint_checked,
                },
            )
        except Exception as error:
            self.send(request_id, "error", {"message": str(error) or "Runtime execution failed"})
        finally:
            if network_proxy is not None:
                network_proxy.close()
            with self.state_lock:
                self.cancellations.pop(request_id, None)


def runtime_environment(
    workspace: Path = ISOLATED_WORKSPACE_ROOT,
    full_access: bool = False,
) -> dict[str, str]:
    pack_bins = [str(path) for path in sorted(PACK_ROOT.glob("*/bin")) if path.is_dir()]
    persistent_home = Path("/root") if full_access else workspace
    task_temp = persistent_home / ".cache" / "tmp" if full_access else workspace / ".tmp"
    android_sdk = PACK_ROOT / "android-sdk" / "sdk"
    environment = {
        "HOME": str(persistent_home),
        "GALAXYSSI_SYSTEM_ROOT": str(PERSISTENT_SYSTEM_ROOT),
        "TMPDIR": str(task_temp),
        "PATH": os.pathsep.join(pack_bins + ["/usr/local/sbin", "/usr/local/bin", "/usr/sbin", "/usr/bin", "/sbin", "/bin"]),
        "LANG": "C.UTF-8",
        "LC_ALL": "C.UTF-8",
        "UV_NO_MODIFY_PATH": "1",
        "UV_PYTHON": str(PACK_ROOT / "python-uv" / "bin" / "python3"),
        "UV_CACHE_DIR": str(task_temp / "uv-cache"),
        "CARGO_HOME": str(task_temp / "cargo"),
        "ZIG_GLOBAL_CACHE_DIR": str(task_temp / "zig-global-cache"),
        "ZIG_LOCAL_CACHE_DIR": str(task_temp / "zig-local-cache"),
        "JAVA_HOME": str(PACK_ROOT / "java"),
        "GRADLE_HOME": str(PACK_ROOT / "gradle"),
        "GRADLE_USER_HOME": str(task_temp / "gradle"),
        "GRADLE_OPTS": (
            "-Dorg.gradle.daemon=false "
            f"-Dorg.gradle.project.android.aapt2FromMavenOverride={PACK_ROOT / 'android-sdk' / 'bin' / 'aapt2'}"
        ),
        "ANDROID_HOME": str(android_sdk),
        "ANDROID_SDK_ROOT": str(android_sdk),
    }
    if full_access:
        environment.update(
            {
                "DEBIAN_FRONTEND": "noninteractive",
                "APT_LISTCHANGES_FRONTEND": "none",
                "UV_PYTHON_DOWNLOADS": "automatic",
                "CARGO_NET_OFFLINE": "false",
            }
        )
    else:
        environment.update(
            {
                "PYTHONNOUSERSITE": "1",
                "UV_NO_CACHE": "1",
                "UV_PYTHON_DOWNLOADS": "never",
                "UV_OFFLINE": "1",
                "CARGO_NET_OFFLINE": "true",
            }
        )
    return environment


def inject_secret_environment(environment: dict[str, str], raw_values: Any) -> None:
    values = raw_values or {}
    if not isinstance(values, dict) or len(values) > 32:
        raise ValueError("Runtime secret environment is invalid")
    for raw_name, raw_value in values.items():
        name = str(raw_name)
        value = str(raw_value)
        if not re.fullmatch(r"[A-Z_][A-Z0-9_]{0,63}", name):
            raise ValueError("Runtime secret environment key is invalid")
        if "\x00" in value or len(value.encode("utf-8")) > 4096:
            raise ValueError("Runtime secret environment value is invalid")
        environment[name] = value


def runtime_readiness(config: dict[str, Any]) -> tuple[bool, str]:
    if full_access_enabled(config):
        return True, ""
    if not LAUNCHER_PATH.is_file() or not os.access(LAUNCHER_PATH, os.X_OK):
        return False, "Runtime sandbox launcher is unavailable"
    try:
        positive_config_id(config, "workspace_uid")
        positive_config_id(config, "workspace_gid")
    except (TypeError, ValueError) as error:
        return False, str(error)
    return True, ""


def configure_guest_dns(config: dict[str, Any], target: Path = Path("/etc/resolv.conf")) -> None:
    raw_servers = config.get("dns_servers")
    if not isinstance(raw_servers, list) or not 1 <= len(raw_servers) <= 4:
        raise ValueError("Runtime DNS server list is invalid")
    servers: list[str] = []
    for raw_server in raw_servers:
        if not isinstance(raw_server, str):
            raise ValueError("Runtime DNS server must be an IPv4 address")
        try:
            address = ipaddress.IPv4Address(raw_server)
        except ipaddress.AddressValueError as error:
            raise ValueError("Runtime DNS server must be an IPv4 address") from error
        if not address.is_global:
            raise ValueError("Runtime DNS server must be globally routable")
        rendered = str(address)
        if rendered not in servers:
            servers.append(rendered)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(
        "".join(f"nameserver {server}\n" for server in servers)
        + "options timeout:1 attempts:2 rotate\n",
        encoding="utf-8",
    )


def install_task_network_firewall(config: dict[str, Any]) -> None:
    workspace_uid = positive_config_id(config, "workspace_uid")
    commands = (
        ["iptables", "-w", "-N", "GALAXYSSI_TASK_OUT"],
        ["iptables", "-w", "-F", "GALAXYSSI_TASK_OUT"],
        ["iptables", "-w", "-A", "GALAXYSSI_TASK_OUT", "-d", "127.0.0.0/8", "-j", "ACCEPT"],
        ["iptables", "-w", "-A", "GALAXYSSI_TASK_OUT", "-j", "REJECT"],
    )
    for index, command in enumerate(commands):
        result = run_firewall_command(command)
        if result.returncode != 0 and index != 0:
            raise RuntimeError(firewall_command_failure(command, result))
    check_command = [
        "iptables", "-w", "-C", "OUTPUT", "-m", "owner", "--uid-owner", str(workspace_uid),
        "-j", "GALAXYSSI_TASK_OUT",
    ]
    check = run_firewall_command(check_command)
    if check.returncode != 0:
        insert_command = [
            "iptables", "-w", "-I", "OUTPUT", "1", "-m", "owner", "--uid-owner", str(workspace_uid),
            "-j", "GALAXYSSI_TASK_OUT",
        ]
        inserted = run_firewall_command(insert_command)
        if inserted.returncode != 0:
            raise RuntimeError(firewall_command_failure(insert_command, inserted))


def run_firewall_command(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )


def firewall_command_failure(
    command: list[str],
    result: subprocess.CompletedProcess[str],
) -> str:
    diagnostic = (result.stderr or result.stdout or "no diagnostic output").strip()
    diagnostic = re.sub(r"\s+", " ", diagnostic)[:512]
    rendered_command = " ".join(command)
    return (
        "Runtime task network firewall is unavailable: "
        f"{rendered_command} failed with exit {result.returncode}: {diagnostic}"
    )


def mount_runtime(config: dict[str, Any]) -> None:
    WORKSPACE_ROOT.mkdir(parents=True, exist_ok=True)
    if not os.path.ismount(WORKSPACE_ROOT):
        subprocess.run(
            ["mount", "-t", "9p", "-o", "trans=virtio,version=9p2000.L,msize=262144", "galaxyssi_workspaces", str(WORKSPACE_ROOT)],
            check=True,
        )
    PACK_NAMESPACE_ROOT.mkdir(mode=0o755, parents=True, exist_ok=True)
    PACK_NAMESPACE_ROOT.chmod(0o755)
    PACK_ROOT.mkdir(mode=0o755, parents=True, exist_ok=True)
    PACK_ROOT.chmod(0o755)
    for pack in config.get("packs") or []:
        pack_id = str(pack.get("id", ""))
        serial = str(pack.get("serial", ""))
        if not re.fullmatch(r"[a-z0-9][a-z0-9._-]{0,79}", pack_id):
            raise ValueError("Runtime pack id is invalid")
        target = PACK_ROOT / pack_id
        target.mkdir(mode=0o755, parents=True, exist_ok=True)
        if os.path.ismount(target):
            validate_mounted_pack(target, pack)
            continue
        device = wait_for_block_device(serial)
        subprocess.run(["mount", "-t", "squashfs", "-o", "ro,nodev,nosuid", str(device), str(target)], check=True)
        validate_mounted_pack(target, pack)


def mount_persistent_system(config: dict[str, Any]) -> None:
    disk = config.get("system_disk") or {}
    if not isinstance(disk, dict):
        raise ValueError("Persistent Linux disk configuration is invalid")
    serial = str(disk.get("serial", ""))
    filesystem = str(disk.get("filesystem", ""))
    mount_path = str(disk.get("mount_path", ""))
    logical_bytes = int(disk.get("logical_bytes", 0))
    if (
        serial != "sa-system"
        or filesystem != "ext4"
        or mount_path != str(PERSISTENT_SYSTEM_ROOT)
        or logical_bytes < 1024 * 1024 * 1024
    ):
        raise ValueError("Persistent Linux disk configuration is incompatible")
    PERSISTENT_SYSTEM_ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
    if os.path.ismount(PERSISTENT_SYSTEM_ROOT):
        return
    device = wait_for_block_device(serial)
    probe = subprocess.run(
        ["blkid", "-p", "-s", "TYPE", "-o", "value", str(device)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    detected = probe.stdout.strip()
    if probe.returncode != 0 or not detected:
        subprocess.run(
            [
                "mke2fs", "-q", "-t", "ext4", "-F", "-L", "galaxyssi-system",
                "-E", "lazy_itable_init=1,lazy_journal_init=1", str(device),
            ],
            check=True,
        )
    elif detected != "ext4":
        raise ValueError(f"Persistent Linux disk uses unsupported filesystem: {detected}")
    repaired = subprocess.run(["e2fsck", "-p", str(device)], check=False)
    if repaired.returncode not in {0, 1}:
        raise RuntimeError("Persistent Linux disk check failed")
    mounted = subprocess.run(
        ["mount", "-t", "ext4", "-o", "rw,noatime", str(device), str(PERSISTENT_SYSTEM_ROOT)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if mounted.returncode != 0:
        subprocess.run(
            ["mount", "-t", "ext4", "-o", "rw,noatime", str(device), str(PERSISTENT_SYSTEM_ROOT)],
            check=True,
        )
    for directory in (PERSISTENT_SYSTEM_ROOT / "root", PERSISTENT_SYSTEM_ROOT / "cache"):
        directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        directory.chmod(0o700)


def prepare_persistent_userspace(config: dict[str, Any]) -> None:
    if not full_access_enabled(config):
        return
    if not os.path.ismount(PERSISTENT_SYSTEM_ROOT):
        raise RuntimeError("Persistent Linux system disk is not mounted")
    if not PERSISTENT_USERSPACE_ARCHIVE.is_file():
        raise FileNotFoundError("Persistent Linux userspace seed is unavailable")
    marker = PERSISTENT_SYSTEM_ROOT / ".userspace-sha256"
    installed_digest = marker.read_text(encoding="utf-8").strip() if marker.is_file() else ""
    if installed_digest != PERSISTENT_USERSPACE_DIGEST:
        archive_digest = sha256_file(PERSISTENT_USERSPACE_ARCHIVE)
        if archive_digest != PERSISTENT_USERSPACE_DIGEST:
            raise ValueError("Persistent Linux userspace seed failed integrity verification")
        shutil.rmtree(PERSISTENT_USERSPACE_ROOT, ignore_errors=True)
        PERSISTENT_USERSPACE_ROOT.mkdir(mode=0o755, parents=True, exist_ok=True)
        subprocess.run(
            ["tar", "-xzf", str(PERSISTENT_USERSPACE_ARCHIVE), "-C", str(PERSISTENT_USERSPACE_ROOT)],
            check=True,
        )
        temporary_marker = PERSISTENT_SYSTEM_ROOT / ".userspace-sha256.tmp"
        temporary_marker.write_text(PERSISTENT_USERSPACE_DIGEST + "\n", encoding="utf-8")
        temporary_marker.replace(marker)
    install_persistent_runtime_libraries()
    bind_persistent_userspace()
    install_persistent_host_tool_wrappers()


def install_persistent_runtime_libraries() -> None:
    target_directory = PERSISTENT_USERSPACE_ROOT / "usr" / "lib"
    target_directory.mkdir(mode=0o755, parents=True, exist_ok=True)
    for name in PERSISTENT_RUNTIME_LIBRARY_NAMES:
        source = next(
            (directory / name for directory in HOST_RUNTIME_LIBRARY_DIRECTORIES if (directory / name).is_file()),
            None,
        )
        if source is None:
            raise FileNotFoundError(f"Persistent Linux runtime library is unavailable: {name}")
        target = target_directory / name
        if target.is_file() and sha256_file(target) == sha256_file(source):
            continue
        temporary = target_directory / f".{name}.tmp"
        shutil.copyfile(source, temporary)
        temporary.chmod(0o755)
        temporary.replace(target)


def bind_persistent_userspace() -> None:
    resolv_source = Path("/etc/resolv.conf")
    resolv_target = PERSISTENT_USERSPACE_ROOT / "etc" / "resolv.conf"
    if resolv_source.is_file():
        resolv_target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(resolv_source, resolv_target)
    persistent_home = PERSISTENT_SYSTEM_ROOT / "root"
    persistent_home.mkdir(mode=0o700, parents=True, exist_ok=True)
    bindings = (
        (persistent_home, Path("/root")),
        (Path("/dev"), PERSISTENT_USERSPACE_ROOT / "dev"),
        (Path("/proc"), PERSISTENT_USERSPACE_ROOT / "proc"),
        (Path("/sys"), PERSISTENT_USERSPACE_ROOT / "sys"),
        (WORKSPACE_ROOT, PERSISTENT_USERSPACE_ROOT / "workspace"),
        (PACK_ROOT, PERSISTENT_USERSPACE_ROOT / "opt" / "galaxyssi" / "packs"),
        (Path("/root"), PERSISTENT_USERSPACE_ROOT / "root"),
        *(
            (source, PERSISTENT_USERSPACE_ROOT / PERSISTENT_HOST_ROOT.relative_to("/") / source.relative_to("/"))
            for source in PERSISTENT_HOST_BINDINGS
            if source.is_dir()
        ),
    )
    for source, target in bindings:
        target.mkdir(parents=True, exist_ok=True)
        if os.path.ismount(target):
            continue
        subprocess.run(["mount", "--rbind", str(source), str(target)], check=True)
        if source in PERSISTENT_HOST_BINDINGS:
            subprocess.run(["mount", "-o", "remount,bind,ro", str(target)], check=True)


def install_persistent_host_tool_wrappers() -> None:
    wrapper_directory = PERSISTENT_USERSPACE_ROOT / "usr" / "local" / "bin"
    wrapper_directory.mkdir(mode=0o755, parents=True, exist_ok=True)
    host_search_path = "/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"
    git_exec_path = subprocess.run(
        ["git", "--exec-path"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    ).stdout.strip()
    if not Path(git_exec_path).is_absolute():
        raise RuntimeError("Host Git execution path is invalid")
    host_git_exec_directory = Path(git_exec_path)
    git_wrapper_directory = PERSISTENT_USERSPACE_ROOT.joinpath(
        *PERSISTENT_GIT_EXEC_WRAPPER_ROOT.relative_to("/").parts
    )
    git_wrapper_directory.mkdir(mode=0o755, parents=True, exist_ok=True)
    for source in host_git_exec_directory.iterdir():
        if not source.is_file() or not os.access(source, os.X_OK):
            continue
        write_persistent_host_wrapper(
            git_wrapper_directory / source.name,
            source,
        )
    if not any(git_wrapper_directory.iterdir()):
        raise FileNotFoundError("Persistent Linux Git helpers are unavailable")

    host_certificate_path = PERSISTENT_HOST_ROOT / "etc" / "ssl" / "certs" / "ca-certificates.crt"
    git_environment = {
        "GIT_EXEC_PATH": str(PERSISTENT_GIT_EXEC_WRAPPER_ROOT),
        "GIT_TEMPLATE_DIR": str(PERSISTENT_HOST_ROOT / "usr" / "share" / "git-core" / "templates"),
        "SSL_CERT_FILE": str(host_certificate_path),
        "GIT_SSL_CAINFO": str(host_certificate_path),
    }
    for name in PERSISTENT_HOST_TOOL_NAMES:
        source_value = shutil.which(name, path=host_search_path)
        if not source_value:
            raise FileNotFoundError(f"Persistent Linux host tool is unavailable: {name}")
        source = Path(source_value)
        arguments: list[str] = []
        environment = git_environment if name == "git" else {"SSL_CERT_FILE": str(host_certificate_path)}
        if name == "ssh" and (Path("/etc/ssh") / "ssh_config").is_file():
            host_config = PERSISTENT_HOST_ROOT / "etc" / "ssh" / "ssh_config"
            arguments = ["-F", str(host_config)]
        write_persistent_host_wrapper(
            wrapper_directory / name,
            source,
            environment=environment,
            arguments=arguments,
        )


def persistent_host_path(source: Path) -> PurePosixPath:
    if not source.is_absolute() or ".." in source.parts:
        raise ValueError("Persistent host tool path is invalid")
    return PERSISTENT_HOST_ROOT.joinpath(*(part.strip("/\\") for part in source.parts[1:]))


def write_persistent_host_wrapper(
    target: Path,
    source: Path,
    environment: dict[str, str] | None = None,
    arguments: list[str] | None = None,
) -> None:
    host_source = persistent_host_path(source)
    library_path = ":".join(map(str, PERSISTENT_HOST_LIBRARY_PATH))
    exports = "".join(
        f"export {name}={shlex.quote(value)}\n"
        for name, value in sorted((environment or {}).items())
    )
    fixed_arguments = "".join(f" {shlex.quote(value)}" for value in (arguments or []))
    target.write_text(
        "#!/bin/sh\n"
        f"{exports}"
        f"exec {shlex.quote(str(PERSISTENT_HOST_DYNAMIC_LOADER))} "
        f"--library-path {shlex.quote(library_path)} "
        f"{shlex.quote(str(host_source))}{fixed_arguments} "
        '"$@"\n',
        encoding="utf-8",
    )
    target.chmod(0o755)


def validate_mounted_pack(target: Path, pack: dict[str, Any]) -> None:
    pack_id = str(pack.get("id", ""))
    version = str(pack.get("version", ""))
    capabilities_value = pack.get("capabilities") or []
    if not isinstance(capabilities_value, list) or any(not isinstance(value, str) for value in capabilities_value):
        raise ValueError(f"Runtime pack capabilities are invalid: {pack_id}")
    capabilities = set(capabilities_value)
    if len(capabilities) != len(capabilities_value):
        raise ValueError(f"Runtime pack capabilities are duplicated: {pack_id}")
    missing_capabilities = PACK_REQUIRED_CAPABILITIES.get(pack_id, set()) - capabilities
    if pack_id not in PACK_ENTRYPOINTS or missing_capabilities:
        raise ValueError(f"Runtime pack capabilities are incomplete: {pack_id}")

    descriptor_path = target / PACK_DESCRIPTOR_NAME
    if not descriptor_path.is_file() or descriptor_path.stat().st_size > 64 * 1024:
        raise ValueError(f"Runtime pack descriptor is unavailable: {pack_id}")
    descriptor = json.loads(descriptor_path.read_text(encoding="utf-8"))
    if (
        int(descriptor.get("format_version", 0)) != 1
        or descriptor.get("id") != pack_id
        or descriptor.get("version") != version
        or set(descriptor.get("capabilities") or []) != capabilities
    ):
        raise ValueError(f"Runtime pack descriptor does not match its signed manifest: {pack_id}")

    resolved_target = target.resolve()
    for relative in PACK_ENTRYPOINTS[pack_id]:
        executable_path = target / relative
        resolved_executable = executable_path.resolve()
        if (
            resolved_target not in resolved_executable.parents
            or not resolved_executable.is_file()
            or not os.access(resolved_executable, os.X_OK)
        ):
            raise ValueError(f"Runtime pack entrypoint is unavailable: {pack_id}/{relative}")


def wait_for_block_device(serial: str, timeout_seconds: float = 10.0) -> Path:
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        for entry in Path("/sys/block").glob("vd*"):
            for serial_file in (entry / "serial", entry / "device" / "serial"):
                try:
                    matches = serial_file.is_file() and serial_file.read_text(encoding="utf-8").strip() == serial
                except OSError:
                    matches = False
                if matches:
                    device = Path("/dev") / entry.name
                    if device.exists():
                        return device
        time.sleep(0.1)
    raise FileNotFoundError(f"Runtime pack device is unavailable: {serial}")


def wait_for_runtime_channel(
    timeout_seconds: float = 10.0,
    class_root: Path = VIRTIO_PORT_CLASS_ROOT,
    device_root: Path = DEVICE_ROOT,
) -> Path:
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        for entry in sorted(class_root.glob("*")):
            try:
                if (entry / "name").read_text(encoding="utf-8").strip() != CHANNEL_NAME:
                    continue
            except OSError:
                continue

            device_names = [entry.name]
            try:
                for line in (entry / "uevent").read_text(encoding="utf-8").splitlines():
                    if line.startswith("DEVNAME="):
                        device_names.insert(0, line.removeprefix("DEVNAME="))
            except OSError:
                pass

            for device_name in device_names:
                relative_device = Path(device_name)
                if relative_device.is_absolute() or ".." in relative_device.parts:
                    continue
                candidate = device_root / relative_device
                if candidate.exists() and not candidate.is_dir():
                    return candidate
        time.sleep(0.1)
    raise FileNotFoundError(f"Runtime API channel is unavailable: {CHANNEL_NAME}")


def synchronize_guest_clock(config: dict[str, Any]) -> None:
    host_epoch_millis = int(config.get("host_epoch_millis", 0))
    if not MIN_TRUSTED_EPOCH_MILLIS <= host_epoch_millis <= MAX_TRUSTED_EPOCH_MILLIS:
        raise ValueError("Runtime host clock is invalid")
    current_epoch_millis = int(time.time() * 1000)
    if abs(current_epoch_millis - host_epoch_millis) > MAX_CLOCK_SKEW_MILLIS:
        try:
            time.clock_settime(time.CLOCK_REALTIME, host_epoch_millis / 1000)
        except (AttributeError, OSError) as error:
            raise RuntimeError("Runtime guest clock synchronization failed") from error
    if abs(int(time.time() * 1000) - host_epoch_millis) > MAX_CLOCK_SKEW_MILLIS:
        raise RuntimeError("Runtime guest clock remains outside the trusted window")


def run_service() -> None:
    session_key = SESSION_PATH.read_bytes()
    if len(session_key) < 32:
        raise ValueError("Runtime session key is invalid")
    config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    if int(config.get("guest_api_version", 0)) != PROTOCOL_VERSION:
        raise ValueError("Runtime guest API is incompatible")
    synchronize_guest_clock(config)
    mount_persistent_system(config)
    mount_runtime(config)
    configure_guest_dns(config)
    prepare_persistent_userspace(config)
    if not full_access_enabled(config):
        install_task_network_firewall(config)
    while True:
        try:
            channel_path = wait_for_runtime_channel()
            with channel_path.open("r+b", buffering=0) as stream:
                GuestService(stream, session_key, config).serve()
        except (EOFError, OSError, ValueError):
            time.sleep(0.2)


def report_fatal_startup(error: BaseException) -> None:
    try:
        with Path("/dev/console").open("a", encoding="utf-8") as console:
            print(
                f"GalaxySSI guest startup failed: {type(error).__name__}: {error}",
                file=console,
                flush=True,
            )
    except OSError:
        pass


if __name__ == "__main__":
    try:
        run_service()
    except BaseException as error:
        report_fatal_startup(error)
        raise
