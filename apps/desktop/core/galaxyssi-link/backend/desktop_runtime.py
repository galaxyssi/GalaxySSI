"""Verified runtime inventory for the GalaxySSI Desktop super agent."""
from __future__ import annotations

import importlib.util
import json
import os
import platform
import shutil
import subprocess
import sys
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Mapping, Sequence


CONTRACT_VERSION = "galaxyssi.desktop-runtime/1.0"
CACHE_TTL_SECONDS = 30.0
MAX_PROBE_OUTPUT = 4_096


@dataclass(frozen=True)
class RuntimeCommand:
    name: str
    aliases: tuple[str, ...]
    version_args: tuple[str, ...] = ("--version",)
    required: bool = True


@dataclass(frozen=True)
class RuntimeSpec:
    runtime_id: str
    title: str
    category: str
    capabilities: tuple[str, ...]
    commands: tuple[RuntimeCommand, ...]
    setup_kind: str = "managed_package"


@dataclass(frozen=True)
class ProbeResult:
    ok: bool
    output: str = ""
    code: int = 0


def _specs() -> tuple[RuntimeSpec, ...]:
    return (
        RuntimeSpec(
            "python",
            "Python",
            "language",
            ("code.python.run", "package.python.manage"),
            (
                RuntimeCommand("python", ("python", "python3", "py")),
                RuntimeCommand("pip", ("pip", "pip3"), required=False),
            ),
        ),
        RuntimeSpec(
            "uv",
            "uv",
            "package_manager",
            ("package.python.manage", "environment.python.create"),
            (RuntimeCommand("uv", ("uv",)),),
        ),
        RuntimeSpec(
            "node",
            "Node.js",
            "language",
            ("code.javascript.run", "code.typescript.run", "package.node.manage"),
            (
                RuntimeCommand("node", ("node",)),
                RuntimeCommand("npm", ("npm.cmd", "npm"), required=False),
                RuntimeCommand("npx", ("npx.cmd", "npx"), required=False),
            ),
        ),
        RuntimeSpec(
            "git",
            "Git",
            "source_control",
            ("source.git.read", "source.git.write"),
            (RuntimeCommand("git", ("git",)),),
        ),
        RuntimeSpec(
            "ssh",
            "OpenSSH",
            "network",
            ("network.ssh.client", "file.sftp.client"),
            (
                RuntimeCommand("ssh", ("ssh",), version_args=("-V",)),
                RuntimeCommand("scp", ("scp",), version_args=("-V",), required=False),
                RuntimeCommand("sftp", ("sftp",), version_args=("-h",), required=False),
            ),
        ),
        RuntimeSpec(
            "ffmpeg",
            "FFmpeg",
            "media",
            ("media.audio.process", "media.video.process", "media.image.process"),
            (
                RuntimeCommand("ffmpeg", ("ffmpeg",)),
                RuntimeCommand("ffprobe", ("ffprobe",), required=False),
            ),
        ),
        RuntimeSpec(
            "java",
            "Java",
            "language",
            ("code.java.run", "code.java.compile"),
            (
                RuntimeCommand("java", ("java",), version_args=("-version",)),
                RuntimeCommand("javac", ("javac",), required=False),
            ),
        ),
        RuntimeSpec(
            "go",
            "Go",
            "language",
            ("code.go.run", "code.go.compile"),
            (RuntimeCommand("go", ("go",), version_args=("version",)),),
        ),
        RuntimeSpec(
            "rust",
            "Rust",
            "language",
            ("code.rust.run", "code.rust.compile", "package.rust.manage"),
            (
                RuntimeCommand("rustc", ("rustc",)),
                RuntimeCommand("cargo", ("cargo",), required=False),
            ),
        ),
        RuntimeSpec(
            "cpp",
            "C and C++",
            "language",
            ("code.c.compile", "code.cpp.compile"),
            (
                RuntimeCommand("compiler", ("clang++", "clang", "g++", "gcc", "cl.exe", "cl")),
                RuntimeCommand("cmake", ("cmake",), required=False),
                RuntimeCommand("ninja", ("ninja",), required=False),
            ),
        ),
        RuntimeSpec(
            "archive",
            "Archive tools",
            "utility",
            ("archive.create", "archive.extract"),
            (
                RuntimeCommand("archive", ("tar", "7z", "zip")),
                RuntimeCommand("unzip", ("unzip",), required=False),
            ),
        ),
    )


def _bounded(value: str) -> str:
    text = str(value or "").strip()
    return text[:MAX_PROBE_OUTPUT]


def _default_runner(argv: Sequence[str], timeout_seconds: float) -> ProbeResult:
    try:
        completed = subprocess.run(
            list(argv),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            shell=False,
            timeout=timeout_seconds,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
        )
        return ProbeResult(completed.returncode == 0, _bounded(completed.stdout), completed.returncode)
    except (OSError, subprocess.SubprocessError) as exc:
        return ProbeResult(False, _bounded(str(exc)), 1)


class DesktopRuntimeManager:
    """Discovers verified host runtimes without invoking a command shell."""

    def __init__(
        self,
        *,
        which: Callable[[str], str | None] = shutil.which,
        runner: Callable[[Sequence[str], float], ProbeResult] = _default_runner,
        environment: Mapping[str, str] | None = None,
        python_executable: str = sys.executable,
        platform_name: str = platform.system(),
        home: Path | None = None,
        now: Callable[[], float] = time.monotonic,
    ) -> None:
        self.which = which
        self.runner = runner
        self.environment = dict(os.environ if environment is None else environment)
        self.python_executable = str(python_executable or "")
        self.platform_name = str(platform_name or "")
        self.home = Path(home or Path.home())
        self.now = now
        self._lock = threading.RLock()
        self._cached_at = 0.0
        self._cached: dict | None = None

    def snapshot(self, *, refresh: bool = False) -> dict:
        with self._lock:
            current = self.now()
            if (
                not refresh
                and self._cached is not None
                and current - self._cached_at < CACHE_TTL_SECONDS
            ):
                return json.loads(json.dumps(self._cached))
            runtimes = [self._probe_runtime(spec) for spec in _specs()]
            runtimes.extend((self._probe_browser_automation(), self._probe_asr(), self._probe_tts()))
            ready = sum(1 for runtime in runtimes if runtime["status"] == "ready")
            partial = sum(1 for runtime in runtimes if runtime["status"] == "partial")
            capabilities = sorted({
                capability
                for runtime in runtimes
                if runtime["status"] in {"ready", "partial"}
                for capability in runtime["capabilities"]
            })
            self._cached = {
                "contract_version": CONTRACT_VERSION,
                "checked_at_epoch_ms": int(time.time() * 1_000),
                "platform": self.platform_name,
                "summary": {
                    "ready": ready,
                    "partial": partial,
                    "missing": len(runtimes) - ready - partial,
                    "total": len(runtimes),
                },
                "capabilities": capabilities,
                "runtimes": runtimes,
            }
            self._cached_at = current
            return json.loads(json.dumps(self._cached))

    def resolve_executable(self, value: str, *, refresh_if_missing: bool = True) -> str | None:
        token = Path(str(value or "").strip()).name.casefold()
        if not token:
            return None
        snapshot = self.snapshot()
        resolved = self._resolve_from_snapshot(snapshot, token)
        if resolved or not refresh_if_missing:
            return resolved
        return self._resolve_from_snapshot(self.snapshot(refresh=True), token)

    def capability_status(self, capability: str) -> list[dict]:
        requested = str(capability or "").strip()
        if not requested:
            return []
        return [
            runtime
            for runtime in self.snapshot()["runtimes"]
            if requested in runtime.get("capabilities", ())
        ]

    @staticmethod
    def _resolve_from_snapshot(snapshot: Mapping, token: str) -> str | None:
        for runtime in snapshot.get("runtimes", ()):
            aliases = {
                str(name).casefold(): str(command)
                for name, command in dict(runtime.get("aliases") or {}).items()
                if command
            }
            if token in aliases:
                return aliases[token]
            for name, command in dict(runtime.get("commands") or {}).items():
                candidates = {Path(str(command)).name.casefold(), str(name).casefold()}
                if token in candidates and command:
                    return str(command)
        return None

    def _probe_runtime(self, spec: RuntimeSpec) -> dict:
        commands: dict[str, str] = {}
        aliases: dict[str, str] = {}
        versions: dict[str, str] = {}
        missing_required: list[str] = []
        missing_optional: list[str] = []
        for command in spec.commands:
            resolved = self._resolve_command(spec.runtime_id, command)
            if not resolved:
                (missing_required if command.required else missing_optional).append(command.name)
                continue
            commands[command.name] = resolved
            aliases.update({alias.casefold(): resolved for alias in command.aliases})
            probe_args = command.version_args
            if Path(resolved).name.casefold() in {"cl", "cl.exe"}:
                probe_args = ()
            result = self.runner((resolved, *probe_args), 4.0)
            if result.output:
                versions[command.name] = result.output.splitlines()[0][:300]
            if not result.ok and command.required and not result.output:
                missing_required.append(command.name)
        if missing_required:
            status = "missing"
        elif missing_optional:
            status = "partial"
        else:
            status = "ready"
        primary = next(iter(commands.values()), "")
        return {
            "id": spec.runtime_id,
            "title": spec.title,
            "category": spec.category,
            "status": status,
            "source": self._source(primary, spec.runtime_id) if primary else "missing",
            "command": primary,
            "commands": commands,
            "aliases": aliases,
            "version": next(iter(versions.values()), ""),
            "versions": versions,
            "capabilities": list(spec.capabilities),
            "missing_components": missing_required + missing_optional,
            "setup": {
                "kind": spec.setup_kind,
                "available": False,
                "reason": "Managed installation is not enabled in this release",
            },
        }

    def _probe_browser_automation(self) -> dict:
        python = self._python_command()
        node = self._resolve_aliases(("node",))
        commands: dict[str, str] = {}
        details: list[str] = []
        browser_ready = False
        if python:
            package = self.runner(
                (
                    python,
                    "-c",
                    "import importlib.util; raise SystemExit(0 if importlib.util.find_spec('playwright') else 1)",
                ),
                4.0,
            )
            if package.ok:
                commands["python"] = python
                browser = self.runner(
                    (
                        python,
                        "-c",
                        (
                            "from pathlib import Path; from playwright.sync_api import sync_playwright; "
                            "p=sync_playwright().start(); paths=[p.chromium.executable_path,p.firefox.executable_path,p.webkit.executable_path]; "
                            "p.stop(); print(next((x for x in paths if Path(x).is_file()),'')); "
                            "raise SystemExit(0 if any(Path(x).is_file() for x in paths) else 1)"
                        ),
                    ),
                    8.0,
                )
                browser_ready = browser_ready or browser.ok
                details.append("Python Playwright")
        if node:
            package = self.runner(
                (node, "-e", "try{require.resolve('playwright');process.exit(0)}catch(_){process.exit(1)}"),
                4.0,
            )
            if package.ok:
                commands["node"] = node
                browser = self.runner(
                    (
                        node,
                        "-e",
                        (
                            "const fs=require('fs');const p=require('playwright');"
                            "const paths=[p.chromium.executablePath(),p.firefox.executablePath(),p.webkit.executablePath()];"
                            "const found=paths.find(x=>fs.existsSync(x))||'';console.log(found);process.exit(found?0:1)"
                        ),
                    ),
                    8.0,
                )
                browser_ready = browser_ready or browser.ok
                details.append("Node Playwright")
        status = "ready" if browser_ready else "partial" if commands else "missing"
        return {
            "id": "browser_automation",
            "title": "Browser automation",
            "category": "automation",
            "status": status,
            "source": self._source(next(iter(commands.values()), ""), "browser_automation") if commands else "missing",
            "command": next(iter(commands.values()), ""),
            "commands": commands,
            "aliases": {},
            "version": ", ".join(details),
            "versions": {},
            "capabilities": ["browser.automate", "browser.screenshot"],
            "missing_components": [] if browser_ready else ["browser_binary"] if commands else ["playwright"],
            "setup": {
                "kind": "managed_package",
                "available": False,
                "reason": "Managed installation is not enabled in this release",
            },
        }

    def _probe_asr(self) -> dict:
        python = self._python_command()
        installed = bool(python and self._python_module_available(python, "faster_whisper"))
        model = self.environment.get("GALAXYSSI_WHISPER_MODEL", "").strip() or "medium"
        model_ready = installed and self._whisper_model_available(model)
        status = "ready" if model_ready else "partial" if installed else "missing"
        missing = []
        if not installed:
            missing.append("faster-whisper")
        elif not model_ready:
            missing.append(f"model:{model}")
        return {
            "id": "asr",
            "title": "Speech recognition",
            "category": "voice",
            "status": status,
            "source": self._source(python, "asr") if installed else "missing",
            "command": python if installed else "",
            "commands": {"python": python} if installed else {},
            "aliases": {"python": python, "python.exe": python} if installed else {},
            "version": f"faster-whisper / {model}" if installed else "",
            "versions": {"model": model} if installed else {},
            "capabilities": ["speech.transcribe"],
            "missing_components": missing,
            "setup": {
                "kind": "managed_model",
                "available": False,
                "reason": "Managed installation is not enabled in this release",
            },
        }

    def _probe_tts(self) -> dict:
        powershell = self._resolve_aliases(("powershell.exe", "powershell", "pwsh"))
        edge = self._resolve_aliases(("edge-tts", "edge-tts.exe"))
        commands = {}
        providers = []
        if self.platform_name.casefold() == "windows" and powershell:
            commands["system"] = powershell
            providers.append("Windows system voice")
        if edge:
            commands["edge"] = edge
            providers.append("Microsoft Edge TTS")
        return {
            "id": "tts",
            "title": "Speech synthesis",
            "category": "voice",
            "status": "ready" if commands else "missing",
            "source": self._source(next(iter(commands.values()), ""), "tts") if commands else "missing",
            "command": next(iter(commands.values()), ""),
            "commands": commands,
            "aliases": {
                **({"powershell.exe": powershell, "powershell": powershell} if powershell else {}),
                **({"edge-tts": edge, "edge-tts.exe": edge} if edge else {}),
            },
            "version": ", ".join(providers),
            "versions": {},
            "capabilities": ["speech.synthesize"],
            "missing_components": [] if commands else ["system_tts"],
            "setup": {
                "kind": "system_or_managed_package",
                "available": False,
                "reason": "Managed installation is not enabled in this release",
            },
        }

    def _resolve_command(self, runtime_id: str, command: RuntimeCommand) -> str | None:
        env_key = f"GALAXYSSI_RUNTIME_{runtime_id.upper()}_{command.name.upper()}"
        primary_env = {
            ("python", "python"): "GALAXYSSI_PYTHON",
            ("uv", "uv"): "GALAXYSSI_UV",
            ("node", "node"): "GALAXYSSI_NODE",
        }.get((runtime_id, command.name), "")
        configured = (
            self.environment.get(env_key, "").strip()
            or (self.environment.get(primary_env, "").strip() if primary_env else "")
        )
        if configured:
            return self._resolve_candidate(configured)
        if runtime_id == "python" and command.name == "python" and self.python_executable:
            candidate = self._resolve_candidate(self.python_executable)
            if candidate:
                return candidate
        return self._resolve_aliases(command.aliases)

    def _python_command(self) -> str | None:
        configured = self.environment.get("GALAXYSSI_PYTHON", "").strip()
        return (
            self._resolve_candidate(configured)
            if configured
            else self._resolve_candidate(self.python_executable)
        ) or self._resolve_aliases(("python", "python3", "py"))

    def _resolve_aliases(self, aliases: Sequence[str]) -> str | None:
        for alias in aliases:
            resolved = self._resolve_candidate(alias)
            if resolved:
                return resolved
        return None

    def _resolve_candidate(self, candidate: str) -> str | None:
        token = str(candidate or "").strip().strip('"')
        if not token:
            return None
        if any(separator in token for separator in ("/", "\\")):
            path = Path(token).expanduser()
            return str(path.resolve()) if path.is_file() else None
        return self.which(token)

    def _python_module_available(self, python: str, module: str) -> bool:
        if Path(python).resolve() == Path(sys.executable).resolve():
            return importlib.util.find_spec(module) is not None
        result = self.runner(
            (
                python,
                "-c",
                f"import importlib.util; raise SystemExit(0 if importlib.util.find_spec({module!r}) else 1)",
            ),
            4.0,
        )
        return result.ok

    def _whisper_model_available(self, model: str) -> bool:
        model_path = Path(model).expanduser()
        if self._valid_whisper_snapshot(model_path):
            return True
        normalized = model.replace("/", "--")
        candidates = (
            self.home / ".cache" / "huggingface" / "hub" / f"models--Systran--faster-whisper-{normalized}",
            self.home / ".cache" / "huggingface" / "hub" / f"models--{normalized}",
        )
        return any(
            (candidate / "snapshots").is_dir()
            and any(self._valid_whisper_snapshot(path) for path in (candidate / "snapshots").iterdir())
            for candidate in candidates
        )

    @staticmethod
    def _valid_whisper_snapshot(path: Path) -> bool:
        return (
            path.is_dir()
            and (path / "config.json").is_file()
            and any((path / filename).is_file() for filename in ("model.bin", "model.safetensors"))
        )

    def _source(self, command: str, runtime_id: str) -> str:
        if not command:
            return "missing"
        configured_values = [
            self._resolve_candidate(value)
            for key, value in self.environment.items()
            if (key.startswith("GALAXYSSI_RUNTIME_") or key in {"GALAXYSSI_PYTHON", "GALAXYSSI_UV", "GALAXYSSI_NODE"})
            and value.strip()
        ]
        if command in configured_values:
            return "configured"
        normalized = str(Path(command)).replace("\\", "/").casefold()
        data_root = self.environment.get("GALAXYSSI_DATA_DIR", "").strip()
        if data_root and normalized.startswith(str(Path(data_root)).replace("\\", "/").casefold()):
            return "managed"
        if "/resources/" in normalized or "/.runtime-" in normalized:
            return "bundled"
        if runtime_id in {"asr", "browser_automation"} and Path(command).resolve() == Path(sys.executable).resolve():
            return "backend"
        return "system"


_RUNTIME_MANAGER: DesktopRuntimeManager | None = None
_RUNTIME_MANAGER_LOCK = threading.Lock()


def desktop_runtime_manager() -> DesktopRuntimeManager:
    global _RUNTIME_MANAGER
    with _RUNTIME_MANAGER_LOCK:
        if _RUNTIME_MANAGER is None:
            _RUNTIME_MANAGER = DesktopRuntimeManager()
        return _RUNTIME_MANAGER
