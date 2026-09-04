"""Deterministic command handlers implemented in the first command-plane slice."""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import shlex
import socket
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import smtplib
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
import zipfile
from collections import Counter
from pathlib import Path
from uuid import uuid4

from .capabilities import EXTERNAL_HISTORY_ACTIONS, probe_command_capability
from .protocol import CommandDefinition, CommandRequest, CommandResult, new_run_id, now_iso
from .registry import CommandRegistry
from .security import resolve_workspace_path, workspace_root
from .store import CommandStore

PROCESS_LOCK = threading.RLock()
PROCESS_REGISTRY: dict[str, dict] = {}


def _result(
    definition: CommandDefinition,
    request: CommandRequest,
    status: str,
    data: dict,
    *,
    display: dict | None = None,
    error_code: str = "",
    message: str = "",
) -> CommandResult:
    completed = now_iso()
    return CommandResult(
        status=status,  # type: ignore[arg-type]
        command_id=definition.command_id,
        run_id=request.run_id or new_run_id(),
        data=data,
        display=display or {},
        error_code=error_code,
        message=message,
        started_at=completed,
        completed_at=completed,
    )


def commands_list(registry: CommandRegistry):
    def handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
        root = str(request.args.get("root") or "").strip().lower()
        commands = registry.list(root=root)
        return _result(
            definition,
            request,
            "completed",
            {
                "catalog_size": len(registry.list()),
                "roots": registry.roots(),
                "commands": commands,
            },
            display={"type": "command_list"},
        )

    return handler


def capabilities_list(registry: CommandRegistry):
    def handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
        commands = registry.list()
        capabilities = [
            probe_command_capability(
                registry.definition(command["command_id"]),
                handler_bound=bool(command["handler"]),
                workspace=request.workspace,
            )
            for command in commands
        ]
        counts = Counter(capability.status for capability in capabilities)
        runnable_count = counts["ready"] + counts["needs_input"]
        unavailable_count = (
            counts["needs_configuration"]
            + counts["missing_runtime"]
            + counts["unsupported"]
        )
        return _result(
            definition,
            request,
            "completed",
            {
                "registered_count": len(commands),
                "handler_bound_count": sum(1 for command in commands if command["handler"]),
                "ready_count": counts["ready"],
                "runnable_count": runnable_count,
                "needs_input_count": counts["needs_input"],
                "needs_configuration_count": counts["needs_configuration"],
                "missing_runtime_count": counts["missing_runtime"],
                "unsupported_count": counts["unsupported"],
                "unavailable_count": unavailable_count,
                "status_counts": dict(sorted(counts.items())),
                "capabilities": [capability.public() for capability in capabilities],
            },
            display={"type": "capability_matrix"},
        )

    return handler


def help_show(registry: CommandRegistry):
    def handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
        query = str(request.args.get("command") or "").strip().removeprefix("/")
        if not query:
            return _result(
                definition,
                request,
                "completed",
                {"roots": registry.roots(), "usage": "/<root> <action> [--key value] [--approve]"},
                display={"type": "command_help"},
            )
        command_id = query.replace(" ", ".")
        found = registry.definition(command_id)
        if found is None:
            matches = [command for command in registry.list() if command["root"] == query]
            if not matches:
                return _result(definition, request, "not_found", {}, error_code="command_not_found")
            return _result(definition, request, "completed", {"commands": matches}, display={"type": "command_help"})
        return _result(definition, request, "completed", {"command": found.public()}, display={"type": "command_help"})

    return handler


def file_list(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    target = resolve_workspace_path(request, str(request.args.get("path") or "."))
    if not target.exists():
        return _result(definition, request, "not_found", {"path": str(target)}, error_code="path_not_found")
    if not target.is_dir():
        return _result(definition, request, "failed", {"path": str(target)}, error_code="not_a_directory")
    limit = max(1, min(int(request.args.get("limit") or 100), 500))
    entries = []
    root = workspace_root(request)
    for entry in sorted(target.iterdir(), key=lambda item: item.name.lower())[:limit]:
        entries.append({
            "path": str(entry.relative_to(root)).replace("\\", "/"),
            "type": "directory" if entry.is_dir() else "file",
            "size": entry.stat().st_size if entry.is_file() else None,
        })
    return _result(definition, request, "completed", {"path": str(target), "entries": entries}, display={"type": "file_list"})


def file_read(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    target = resolve_workspace_path(request, str(request.args.get("path") or ""))
    if not target.exists():
        return _result(definition, request, "not_found", {"path": str(target)}, error_code="path_not_found")
    if not target.is_file():
        return _result(definition, request, "failed", {"path": str(target)}, error_code="not_a_file")
    max_bytes = max(1, min(int(request.args.get("max_bytes") or 65536), 1024 * 1024))
    raw = target.read_bytes()[:max_bytes]
    text = raw.decode("utf-8", errors="replace")
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    return _result(
        definition,
        request,
        "completed",
        {"path": str(target), "content": text, "sha256": digest, "truncated": target.stat().st_size > max_bytes},
        display={"type": "file_text"},
    )


def file_write(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    target = resolve_workspace_path(request, str(request.args.get("path") or ""))
    if target.exists() and target.is_dir():
        return _result(definition, request, "failed", {"path": str(target)}, error_code="target_is_directory")
    content = str(request.args.get("content") if "content" in request.args else "")
    root = workspace_root(request)
    snapshot_path = ""
    if target.exists() and target.is_file():
        snapshot_dir = root / ".galaxyssi_command_snapshots"
        snapshot_dir.mkdir(parents=True, exist_ok=True)
        snapshot = snapshot_dir / f"{target.name}.{hashlib.sha256(str(target).encode('utf-8')).hexdigest()[:10]}.bak"
        snapshot.write_bytes(target.read_bytes())
        snapshot_path = str(snapshot)
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=f".{target.name}.", dir=str(target.parent))
    with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
        handle.write(content)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temp_name, target)
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    return _result(
        definition,
        request,
        "completed",
        {
            "path": str(target),
            "size": target.stat().st_size,
            "sha256": digest,
            "snapshot_path": snapshot_path,
        },
        display={"type": "file_write"},
    )


def _bool_arg(value) -> bool:
    if isinstance(value, bool):
        return value
    return str(value or "").strip().lower() in {"1", "true", "yes", "y", "on"}


def file_mkdir(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    path = str(request.args.get("path") or "").strip()
    if not path:
        return _result(definition, request, "failed", {}, error_code="path_required")
    target = resolve_workspace_path(request, path)
    target.mkdir(parents=True, exist_ok=True)
    return _result(definition, request, "completed", {"path": str(target), "exists": target.is_dir()}, display={"type": "file_write"})


def file_move(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    source_arg = str(request.args.get("source") or request.args.get("path") or "").strip()
    destination_arg = str(request.args.get("destination") or request.args.get("to") or "").strip()
    if not source_arg or not destination_arg:
        return _result(definition, request, "failed", {}, error_code="source_destination_required")
    source = resolve_workspace_path(request, source_arg)
    destination = resolve_workspace_path(request, destination_arg)
    overwrite = _bool_arg(request.args.get("overwrite"))
    if not source.exists():
        return _result(definition, request, "not_found", {"source": str(source)}, error_code="source_not_found")
    if destination.exists() and not overwrite:
        return _result(definition, request, "failed", {"destination": str(destination)}, error_code="destination_exists")
    destination.parent.mkdir(parents=True, exist_ok=True)
    snapshot_path = ""
    if destination.exists():
        snapshot_dir = workspace_root(request) / ".galaxyssi_command_snapshots"
        snapshot_dir.mkdir(parents=True, exist_ok=True)
        snapshot_path = str(snapshot_dir / f"overwrite-{uuid4().hex[:12]}-{destination.name}")
        shutil.move(str(destination), snapshot_path)
    shutil.move(str(source), str(destination))
    return _result(
        definition,
        request,
        "completed",
        {"source": str(source), "destination": str(destination), "snapshot_path": snapshot_path},
        display={"type": "file_move"},
    )


def file_copy(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    source_arg = str(request.args.get("source") or request.args.get("path") or "").strip()
    destination_arg = str(request.args.get("destination") or request.args.get("to") or "").strip()
    if not source_arg or not destination_arg:
        return _result(definition, request, "failed", {}, error_code="source_destination_required")
    source = resolve_workspace_path(request, source_arg)
    destination = resolve_workspace_path(request, destination_arg)
    overwrite = _bool_arg(request.args.get("overwrite"))
    if not source.exists():
        return _result(definition, request, "not_found", {"source": str(source)}, error_code="source_not_found")
    if destination.exists() and not overwrite:
        return _result(definition, request, "failed", {"destination": str(destination)}, error_code="destination_exists")
    if destination.exists():
        if destination.is_dir():
            shutil.rmtree(destination)
        else:
            destination.unlink()
    destination.parent.mkdir(parents=True, exist_ok=True)
    if source.is_dir():
        shutil.copytree(source, destination)
    else:
        shutil.copy2(source, destination)
    return _result(definition, request, "completed", {"source": str(source), "destination": str(destination)}, display={"type": "file_copy"})


def file_delete(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    path = str(request.args.get("path") or "").strip()
    if not path:
        return _result(definition, request, "failed", {}, error_code="path_required")
    target = resolve_workspace_path(request, path)
    if not target.exists():
        return _result(definition, request, "not_found", {"path": str(target)}, error_code="path_not_found")
    snapshot_dir = workspace_root(request) / ".galaxyssi_command_snapshots" / "deleted"
    snapshot_dir.mkdir(parents=True, exist_ok=True)
    deleted_path = snapshot_dir / f"{uuid4().hex[:12]}-{target.name}"
    shutil.move(str(target), str(deleted_path))
    return _result(definition, request, "completed", {"path": str(target), "deleted_path": str(deleted_path)}, display={"type": "file_delete"})


def _git_repo(request: CommandRequest) -> Path:
    return resolve_workspace_path(request, str(request.args.get("path") or "."))


def _git_run(definition: CommandDefinition, request: CommandRequest, args: list[str], timeout: int = 20) -> CommandResult:
    repo = _git_repo(request)
    if not (repo / ".git").exists():
        return _result(definition, request, "failed", {"path": str(repo)}, error_code="not_a_git_repository")
    completed = subprocess.run(
        ["git", *args],
        cwd=repo,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
        shell=False,
    )
    max_bytes = max(1, min(int(request.args.get("max_bytes") or 65536), 1024 * 1024))
    status = "completed" if completed.returncode == 0 else "failed"
    return _result(
        definition,
        request,
        status,
        {
            "path": str(repo),
            "exit_code": completed.returncode,
            "stdout": completed.stdout[-max_bytes:],
            "stderr": completed.stderr[-max_bytes:],
        },
        error_code="" if completed.returncode == 0 else "git_command_failed",
        display={"type": "command_output"},
    )


def git_status(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    return _git_run(definition, request, ["status", "--short", "--branch"], timeout=15)


def git_diff(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    return _git_run(definition, request, ["diff", "--", str(request.args.get("file") or ".")], timeout=20)


def git_log(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    limit = max(1, min(int(request.args.get("limit") or 20), 100))
    return _git_run(definition, request, ["log", "--oneline", f"-{limit}"], timeout=20)


def git_branch(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    return _git_run(definition, request, ["branch", "--list", "--all"], timeout=20)


def _coerce_argv(value) -> list[str]:
    if isinstance(value, list):
        return [str(item) for item in value if str(item)]
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return []
        try:
            parsed = json.loads(text)
            if isinstance(parsed, list):
                return [str(item) for item in parsed if str(item)]
        except json.JSONDecodeError:
            pass
        return shlex.split(text, posix=os.name != "nt")
    return []


def _run_argv(definition: CommandDefinition, request: CommandRequest, argv: list[str], cwd: Path, timeout: int = 60) -> CommandResult:
    if not argv:
        return _result(definition, request, "failed", {}, error_code="argv_required")
    executable = shutil.which(argv[0]) if not os.path.isabs(argv[0]) else argv[0]
    if not executable or not Path(executable).exists():
        return _result(
            definition,
            request,
            "unavailable",
            {"argv": argv},
            error_code="executable_not_found",
            message=f"Executable not found: {argv[0]}",
        )
    completed = subprocess.run(
        [executable, *argv[1:]],
        cwd=cwd,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=max(1, min(int(timeout), 600)),
        shell=False,
    )
    return _result(
        definition,
        request,
        "completed" if completed.returncode == 0 else "failed",
        {
            "argv": [executable, *argv[1:]],
            "cwd": str(cwd),
            "exit_code": completed.returncode,
            "stdout": completed.stdout[-20000:],
            "stderr": completed.stderr[-20000:],
        },
        error_code="" if completed.returncode == 0 else "process_exit_nonzero",
        display={"type": "command_output"},
    )


def _load_package_scripts(root: Path) -> dict[str, str]:
    package_json = root / "package.json"
    if not package_json.is_file():
        return {}
    try:
        data = json.loads(package_json.read_text(encoding="utf-8"))
    except Exception:
        return {}
    scripts = data.get("scripts")
    return scripts if isinstance(scripts, dict) else {}


def _npm_command() -> str:
    return "npm.cmd" if os.name == "nt" else "npm"


def _limit(request: CommandRequest, default: int = 100) -> int:
    return max(1, min(int(request.args.get("limit") or default), 500))


def _project_handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    root = resolve_workspace_path(request, str(request.args.get("path") or "."))
    if definition.action in {"status", "report", "validate"}:
        scripts = _load_package_scripts(root)
        git_root = (root / ".git").exists()
        return _result(
            definition,
            request,
            "completed",
            {
                "path": str(root),
                "exists": root.exists(),
                "git_repository": git_root,
                "package_scripts": sorted(scripts.keys()),
            },
            display={"type": "project_status"},
        )
    if definition.action == "list":
        if not root.is_dir():
            return _result(definition, request, "failed", {"path": str(root)}, error_code="not_a_directory")
        entries = []
        for entry in sorted(root.iterdir(), key=lambda item: item.name.lower())[:200]:
            entries.append({
                "name": entry.name,
                "type": "directory" if entry.is_dir() else "file",
                "size": entry.stat().st_size if entry.is_file() else None,
            })
        return _result(definition, request, "completed", {"path": str(root), "entries": entries}, display={"type": "file_list"})
    return _result(definition, request, "unavailable", {"action": definition.action}, error_code="project_action_unavailable")


def _script_handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    root = workspace_root(request)
    scripts = _load_package_scripts(root)
    default_scripts = {
        "test": "check",
        "lint": "check",
        "build": "check:android",
        "format": "format",
        "deploy": "deploy",
        "release": "release",
        "rollback": "rollback",
    }
    script = str(request.args.get("script") or default_scripts.get(definition.root) or "").strip()
    if definition.action in {"status", "list", "validate", "report"}:
        return _result(
            definition,
            request,
            "completed",
            {
                "root": definition.root,
                "available": script in scripts,
                "selected_script": script,
                "scripts": sorted(scripts.keys()),
            },
            display={"type": "script_status"},
        )
    if definition.action != "run":
        return _result(definition, request, "unavailable", {"action": definition.action}, error_code="script_action_unavailable")
    if script not in scripts:
        return _result(
            definition,
            request,
            "unavailable",
            {"selected_script": script, "scripts": sorted(scripts.keys())},
            error_code="npm_script_unavailable",
        )
    timeout = int(request.args.get("timeout") or 300)
    return _run_argv(definition, request, [_npm_command(), "run", script], root, timeout=timeout)


def _deployment_handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    if definition.action in {"run", "start"}:
        return _script_handler(
            CommandDefinition(
                definition.command_id,
                definition.root,
                "run",
                definition.summary,
                risk=definition.risk,
                requires_approval=definition.requires_approval,
                required_permission=definition.required_permission,
            ),
            request,
        )
    if definition.action in {"status", "list", "validate", "report"}:
        return _script_handler(definition, request)
    return _result(
        definition,
        request,
        "unavailable",
        {"action": definition.action, "reason": f"{definition.root} is executed as a foreground package script."},
        error_code="deployment_action_unavailable",
    )


def _shell_handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    root = workspace_root(request)
    if definition.action == "list":
        candidates = (
            ("PowerShell", "pwsh"),
            ("Windows PowerShell", "powershell"),
            ("Command Prompt", "cmd"),
            ("Bash", "bash"),
            ("POSIX shell", "sh"),
            ("Z shell", "zsh"),
            ("Fish", "fish"),
        )
        shells = [
            {"name": name, "command": command, "executable": executable}
            for name, command in candidates
            if (executable := shutil.which(command))
        ]
        return _result(
            definition,
            request,
            "completed",
            {"mode": "argv_only", "cwd": str(root), "shells": shells},
            display={"type": "shell_list"},
        )
    if definition.action in {"status", "validate", "report"}:
        return _result(
            definition,
            request,
            "completed",
            {"shell": False, "mode": "argv_only", "cwd": str(root)},
            display={"type": "capability_status"},
        )
    if definition.action != "run":
        return _result(definition, request, "unavailable", {"action": definition.action}, error_code="shell_action_unavailable")
    argv = _coerce_argv(request.args.get("argv") or request.args.get("command"))
    timeout = int(request.args.get("timeout") or 60)
    return _run_argv(definition, request, argv, root, timeout=timeout)


def _process_status(item: dict) -> dict:
    process = item["process"]
    exit_code = process.poll()
    return {
        "id": item["id"],
        "argv": item["argv"],
        "cwd": item["cwd"],
        "started_at": item["started_at"],
        "status": "running" if exit_code is None else "exited",
        "exit_code": exit_code,
        "stdout_path": item["stdout_path"],
        "stderr_path": item["stderr_path"],
    }


def _close_process_stdin(item: dict) -> None:
    stdin = getattr(item.get("process"), "stdin", None)
    if stdin is not None and not stdin.closed:
        try:
            stdin.close()
        except OSError:
            pass


def _start_process(
    definition: CommandDefinition,
    request: CommandRequest,
    argv: list[str],
    process_id: str,
    root: Path,
) -> CommandResult:
    if not argv:
        return _result(definition, request, "failed", {}, error_code="argv_required")
    executable = shutil.which(argv[0]) if not os.path.isabs(argv[0]) else argv[0]
    if not executable or not Path(executable).exists():
        return _result(definition, request, "unavailable", {"argv": argv}, error_code="executable_not_found")
    process_id = process_id or f"proc-{uuid4().hex[:12]}"
    output_dir = root / ".galaxyssi_command_processes"
    output_dir.mkdir(parents=True, exist_ok=True)
    stdout_path = output_dir / f"{process_id}.stdout.log"
    stderr_path = output_dir / f"{process_id}.stderr.log"
    stdout_handle = stdout_path.open("ab")
    stderr_handle = stderr_path.open("ab")
    try:
        process = subprocess.Popen(
            [executable, *argv[1:]],
            cwd=root,
            stdout=stdout_handle,
            stderr=stderr_handle,
            stdin=subprocess.PIPE,
            shell=False,
        )
    finally:
        stdout_handle.close()
        stderr_handle.close()
    with PROCESS_LOCK:
        PROCESS_REGISTRY[process_id] = {
            "id": process_id,
            "process": process,
            "argv": [executable, *argv[1:]],
            "cwd": str(root),
            "started_at": now_iso(),
            "stdout_path": str(stdout_path),
            "stderr_path": str(stderr_path),
        }
        item = PROCESS_REGISTRY[process_id]
    return _result(definition, request, "completed", {"process": _process_status(item)}, display={"type": "process_status"})


def _process_handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    root = workspace_root(request)
    action = definition.action
    if action in {"status", "list", "report", "validate"}:
        with PROCESS_LOCK:
            processes = [_process_status(item) for item in PROCESS_REGISTRY.values()]
        return _result(definition, request, "completed", {"processes": processes}, display={"type": "process_list"})
    process_id = str(request.args.get("id") or "").strip()
    if action == "start":
        argv = _coerce_argv(request.args.get("argv") or request.args.get("command"))
        return _start_process(definition, request, argv, process_id, root)
    with PROCESS_LOCK:
        item = PROCESS_REGISTRY.get(process_id)
    if item is None:
        return _result(definition, request, "not_found", {"id": process_id}, error_code="process_not_found")
    process = item["process"]
    if action == "stop":
        if process.poll() is None:
            _close_process_stdin(item)
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
        return _result(definition, request, "completed", {"process": _process_status(item)}, display={"type": "process_status"})
    if action == "kill":
        if process.poll() is None:
            _close_process_stdin(item)
            process.kill()
            process.wait(timeout=5)
        return _result(definition, request, "completed", {"process": _process_status(item)}, display={"type": "process_status"})
    if action == "restart":
        if process.poll() is None:
            _close_process_stdin(item)
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
        return _start_process(definition, request, item["argv"], process_id, root)
    if action == "run":
        return _run_argv(definition, request, item["argv"], root, timeout=int(request.args.get("timeout") or 60))
    if action == "output":
        max_bytes = max(1, min(int(request.args.get("max_bytes") or 65536), 1024 * 1024))
        stdout_path = Path(item["stdout_path"])
        stderr_path = Path(item["stderr_path"])
        stdout = stdout_path.read_bytes()[-max_bytes:].decode("utf-8", errors="replace") if stdout_path.exists() else ""
        stderr = stderr_path.read_bytes()[-max_bytes:].decode("utf-8", errors="replace") if stderr_path.exists() else ""
        return _result(
            definition,
            request,
            "completed",
            {"process": _process_status(item), "stdout": stdout, "stderr": stderr},
            display={"type": "command_output"},
        )
    if action == "stdin":
        text = str(request.args.get("text") or request.args.get("content") or "")
        stdin = process.stdin
        if process.poll() is not None or stdin is None or stdin.closed:
            return _result(definition, request, "failed", {"id": process_id}, error_code="process_stdin_closed")
        stdin.write(text.encode("utf-8"))
        if not text.endswith("\n"):
            stdin.write(b"\n")
        stdin.flush()
        return _result(definition, request, "completed", {"id": process_id, "bytes_written": len(text.encode("utf-8"))})
    return _result(definition, request, "unavailable", {"action": action}, error_code="process_action_unavailable")


def _service_handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    if definition.action in {"status", "list", "report", "validate", "start", "stop", "restart", "run", "output", "stdin", "kill"}:
        return _process_handler(definition, request)
    return _result(definition, request, "unavailable", {"action": definition.action}, error_code="service_action_unavailable")


def _port_handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    action = definition.action
    port_value = request.args.get("port") or request.args.get("id")
    if action in {"status", "validate", "report"}:
        if not port_value:
            return _result(definition, request, "failed", {}, error_code="port_required")
        try:
            port = int(port_value)
        except (TypeError, ValueError):
            return _result(definition, request, "failed", {"port": str(port_value)}, error_code="port_invalid")
        host = str(request.args.get("host") or "127.0.0.1")
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(1)
            open_state = sock.connect_ex((host, port)) == 0
        return _result(
            definition,
            request,
            "completed",
            {"host": host, "port": port, "open": open_state},
            display={"type": "port_status"},
        )
    if action == "list":
        command = ["netstat", "-ano"] if os.name == "nt" else (["ss", "-tuln"] if shutil.which("ss") else ["netstat", "-tuln"])
        result = _run_argv(definition, request, command, workspace_root(request), timeout=15)
        if result.status == "completed":
            result.data["parser"] = "netstat" if command[0] == "netstat" else "ss"
        return result
    return _result(definition, request, "unavailable", {"action": action}, error_code="port_action_unavailable")


def _relative_files(root: Path, suffixes: tuple[str, ...], limit: int = 100) -> list[dict]:
    items = []
    ignored = {".git", "node_modules", ".gradle", "build", "dist", ".electron-runtime"}
    for path in root.rglob("*"):
        if len(items) >= limit:
            break
        if any(part in ignored for part in path.parts):
            continue
        if path.is_file() and path.suffix.lower() in suffixes:
            items.append({"path": str(path.relative_to(root)).replace("\\", "/"), "size": path.stat().st_size})
    return items


def _document_handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    if definition.action in {"status", "list", "validate", "report"}:
        root = workspace_root(request)
        documents = _relative_files(root, (".md", ".txt", ".pdf", ".docx", ".pptx", ".xlsx", ".csv"), _limit(request))
        return _result(definition, request, "completed", {"documents": documents}, display={"type": "document_list"})
    return _result(
        definition,
        request,
        "unavailable",
        {"action": definition.action, "reason": "Document mutation requires a selected document adapter and schema."},
        error_code="document_action_unavailable",
    )


def _inventory_handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    root = workspace_root(request)
    home = Path.home()
    inventories = {
        "mcp": [root / ".mcp.json", root / ".codex" / "mcp.json", home / ".codex" / "config.toml"],
        "skill": [home / ".codex" / "skills", root / ".codex" / "skills"],
        "plugin": [home / ".codex" / "plugins", root / ".codex" / "plugins"],
        "tool": [root / "tools", root / "scripts", root / "apps" / "desktop" / "scripts"],
    }
    if definition.action in {"status", "list", "validate", "report"}:
        entries = []
        for candidate in inventories.get(definition.root, []):
            if candidate.is_dir():
                entries.extend({"path": str(item), "type": "directory" if item.is_dir() else "file"} for item in sorted(candidate.iterdir())[:_limit(request)])
            elif candidate.exists():
                entries.append({"path": str(candidate), "type": "file"})
        return _result(
            definition,
            request,
            "completed",
            {"root": definition.root, "entries": entries, "available": bool(entries)},
            display={"type": "inventory_list"},
        )
    return _result(
        definition,
        request,
        "unavailable",
        {"action": definition.action, "reason": f"{definition.root} execution requires an explicit adapter selection."},
        error_code="inventory_action_unavailable",
    )


def _github_item_handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    if definition.action not in {"status", "list", "validate", "report"}:
        return _result(
            definition,
            request,
            "unavailable",
            {"action": definition.action, "reason": "PR and issue writes require an explicit GitHub workflow adapter."},
            error_code="github_write_adapter_required",
        )
    root = workspace_root(request)
    if not (root / ".git").exists():
        return _result(definition, request, "unavailable", {"path": str(root)}, error_code="git_repository_required")
    gh = shutil.which("gh")
    if not gh:
        return _result(definition, request, "unavailable", {}, error_code="prerequisite_unavailable", message="GitHub CLI is not installed.")
    item = "pr" if definition.root == "pr" else "issue"
    args = [gh, item, "list", "--limit", str(_limit(request, 30)), "--json", "number,title,state,url"]
    completed = subprocess.run(
        args,
        cwd=root,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=30,
        shell=False,
    )
    if completed.returncode != 0:
        stderr = completed.stderr[-4000:]
        unavailable = any(text in stderr.lower() for text in ("not logged", "authentication", "could not resolve", "no github remotes"))
        return _result(
            definition,
            request,
            "unavailable" if unavailable else "failed",
            {"exit_code": completed.returncode, "stderr": stderr},
            error_code="prerequisite_unavailable" if unavailable else "github_cli_failed",
        )
    try:
        items = json.loads(completed.stdout or "[]")
    except json.JSONDecodeError:
        items = []
    return _result(definition, request, "completed", {f"{item}s": items}, display={"type": f"{item}_list"})


def _env_handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    names = sorted(os.environ)
    if definition.action in {"status", "list", "validate", "report"}:
        prefix = str(request.args.get("prefix") or "").upper()
        selected = [name for name in names if not prefix or name.upper().startswith(prefix)][:_limit(request)]
        return _result(
            definition,
            request,
            "completed",
            {"count": len(names), "names": selected, "values_redacted": True},
            display={"type": "env_list"},
        )
    if definition.action == "run":
        key = str(request.args.get("key") or request.args.get("name") or "").strip()
        if not key:
            return _result(definition, request, "failed", {}, error_code="env_key_required")
        exists = key in os.environ
        reveal = bool(request.args.get("reveal"))
        value = os.environ.get(key, "") if reveal else ("***" if exists else "")
        return _result(definition, request, "completed", {"key": key, "exists": exists, "value": value, "redacted": not reveal})
    return _result(definition, request, "unavailable", {"action": definition.action}, error_code="env_action_unavailable")


def _checksum_handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    if definition.action in {"status", "list"}:
        return _result(definition, request, "completed", {"algorithms": ["sha256"]}, display={"type": "capability_status"})
    if definition.action not in {"run", "validate", "report"}:
        return _result(definition, request, "unavailable", {"action": definition.action}, error_code="checksum_action_unavailable")
    target = resolve_workspace_path(request, str(request.args.get("path") or ""))
    if not target.is_file():
        return _result(definition, request, "not_found", {"path": str(target)}, error_code="file_not_found")
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    return _result(definition, request, "completed", {"path": str(target), "sha256": digest, "size": target.stat().st_size}, display={"type": "checksum"})


def _archive_handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    root = workspace_root(request)
    if definition.action in {"status", "list", "validate", "report"}:
        archives = _relative_files(root, (".zip", ".tar", ".gz"), _limit(request))
        return _result(definition, request, "completed", {"archives": archives}, display={"type": "document_list"})
    if definition.action not in {"run", "start"}:
        return _result(definition, request, "unavailable", {"action": definition.action}, error_code="archive_action_unavailable")
    source = resolve_workspace_path(request, str(request.args.get("path") or "."))
    output = resolve_workspace_path(request, str(request.args.get("output") or "galaxyssi-command-archive.zip"))
    if not source.exists():
        return _result(definition, request, "not_found", {"path": str(source)}, error_code="path_not_found")
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        if source.is_file():
            archive.write(source, source.relative_to(root).as_posix())
        else:
            for path in source.rglob("*"):
                if path.is_file() and ".git" not in path.parts and "node_modules" not in path.parts:
                    archive.write(path, path.relative_to(root).as_posix())
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    return _result(definition, request, "completed", {"path": str(output), "size": output.stat().st_size, "sha256": digest}, display={"type": "archive"})


def _python_handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    if definition.action in {"status", "list"}:
        return _result(definition, request, "completed", {"executable": sys.executable}, display={"type": "adapter_status"})
    if definition.action in {"run", "validate", "report"}:
        code = str(request.args.get("code") or request.args.get("script") or "").strip()
        argv = _coerce_argv(request.args.get("argv") or request.args.get("command"))
        if code:
            return _run_argv(definition, request, [sys.executable, "-c", code], workspace_root(request), timeout=int(request.args.get("timeout") or 30))
        if argv:
            return _run_argv(definition, request, [sys.executable, *argv], workspace_root(request), timeout=int(request.args.get("timeout") or 30))
        return _result(definition, request, "failed", {}, error_code="python_code_required")
    return _result(definition, request, "unavailable", {"action": definition.action}, error_code="python_action_unavailable")


def _package_handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    root = workspace_root(request)
    scripts = _load_package_scripts(root)
    package_json = root / "package.json"
    data = {}
    if package_json.is_file():
        try:
            data = json.loads(package_json.read_text(encoding="utf-8"))
        except Exception:
            data = {}
    if definition.action in {"status", "list", "validate", "report"}:
        return _result(
            definition,
            request,
            "completed",
            {
                "package_json": package_json.is_file(),
                "name": data.get("name", ""),
                "version": data.get("version", ""),
                "scripts": sorted(scripts),
                "dependencies": sorted((data.get("dependencies") or {}).keys()),
                "dev_dependencies": sorted((data.get("devDependencies") or {}).keys()),
            },
            display={"type": "package_status"},
        )
    if definition.action == "run":
        script = str(request.args.get("script") or "").strip()
        if not script:
            return _result(definition, request, "failed", {}, error_code="package_script_required")
        return _script_handler(CommandDefinition(definition.command_id, "test", "run", definition.summary), request)
    return _result(definition, request, "unavailable", {"action": definition.action}, error_code="package_action_unavailable")


def _database_handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    if definition.action in {"status", "list", "validate", "report"}:
        db_path = request.args.get("path")
        if not db_path:
            return _result(definition, request, "completed", {"sqlite": True, "path_required_for_tables": True}, display={"type": "adapter_status"})
        target = resolve_workspace_path(request, str(db_path))
        if not target.is_file():
            return _result(definition, request, "not_found", {"path": str(target)}, error_code="database_not_found")
        conn = None
        try:
            conn = sqlite3.connect(target)
            rows = conn.execute("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name").fetchall()
            return _result(definition, request, "completed", {"path": str(target), "tables": [row[0] for row in rows]}, display={"type": "database_tables"})
        except sqlite3.DatabaseError as exc:
            return _result(definition, request, "failed", {"path": str(target)}, error_code="database_invalid", message=str(exc)[:300])
        finally:
            if conn is not None:
                conn.close()
    return _result(definition, request, "unavailable", {"action": definition.action}, error_code="database_action_unavailable")


KV_ROOTS = {"config", "profile", "permission", "approval", "sandbox", "model", "cache", "policy", "template"}
TEXT_ROOTS = {"memory", "knowledge", "artifact", "dataset", "index", "workspace"}
SCHEDULE_ROOTS = {"schedule", "cron", "watch", "trigger", "queue"}
EVENT_ROOTS = {"audit", "log", "heartbeat", "event"}


def _entity_status(action: str, request: CommandRequest) -> str:
    return {
        "pause": "paused",
        "resume": "active",
        "cancel": "cancelled",
        "retry": "retrying",
        "checkpoint": "checkpointed",
        "restore": "restored",
        "export": "exported",
    }.get(action, str(request.args.get("status") or "active"))


def _native_id(root: str, name: str, timestamp: str) -> str:
    return f"{root}-{hashlib.sha256((name + timestamp).encode('utf-8')).hexdigest()[:12]}"


def native_state_handler(store: CommandStore):
    def handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
        action = definition.action
        root = definition.root
        entity_id = str(request.args.get("id") or request.args.get(f"{root}_id") or "").strip()
        name = str(request.args.get("name") or entity_id or f"{root}-{new_run_id()}").strip()
        value = request.args.get("value")
        if isinstance(value, str):
            try:
                value = json.loads(value)
            except json.JSONDecodeError:
                value = {"text": value}
        if not isinstance(value, dict):
            value = {"value": value} if value not in (None, "") else {}

        if action == "list":
            if root in KV_ROOTS:
                return _result(definition, request, "completed", {"root": root, "items": store.list_kv(root, _limit(request))}, display={"type": "entity_list"})
            if root in TEXT_ROOTS:
                return _result(definition, request, "completed", {"root": root, "items": store.list_text_records(root, _limit(request))}, display={"type": "entity_list"})
            if root in SCHEDULE_ROOTS:
                return _result(definition, request, "completed", {"root": root, "items": store.list_schedules(root, _limit(request))}, display={"type": "entity_list"})
            if root == "usage":
                return _result(definition, request, "completed", {"root": root, "items": store.list_usage(root, _limit(request))}, display={"type": "entity_list"})
            if root in EVENT_ROOTS:
                return _result(definition, request, "completed", {"root": root, "items": store.list_events(root, _limit(request))}, display={"type": "entity_list"})
            return _result(
                definition,
                request,
                "completed",
                {"root": root, "items": store.list_entities(root, _limit(request))},
                display={"type": "entity_list"},
            )
        if action == "get":
            if not entity_id:
                return _result(definition, request, "failed", {}, error_code="id_required")
            if root in KV_ROOTS:
                entity = store.get_kv(root, entity_id)
            elif root in TEXT_ROOTS:
                entity = store.get_text_record(entity_id)
            elif root in SCHEDULE_ROOTS:
                entity = store.get_schedule(entity_id)
            elif root == "usage":
                entity = store.get_usage(entity_id)
            elif root in EVENT_ROOTS:
                entity = store.get_event(entity_id)
            else:
                entity = store.get_entity(entity_id)
            if entity is None:
                return _result(definition, request, "not_found", {"id": entity_id}, error_code="entity_not_found")
            return _result(definition, request, "completed", {"entity": entity}, display={"type": "entity_detail"})
        if action in {"create", "update", "status", "pause", "resume", "cancel", "retry", "checkpoint", "restore", "export"}:
            timestamp = now_iso()
            if not entity_id:
                entity_id = _native_id(root, name, timestamp)
            status = _entity_status(action, request)
            if root in KV_ROOTS:
                entity = store.set_kv(root, entity_id, {"action": action, **value}, status, timestamp)
            elif root in TEXT_ROOTS:
                body = str(request.args.get("body") or request.args.get("content") or value.get("body") or value.get("text") or "")
                entity = store.upsert_text_record(entity_id, root, name, body, {"action": action, **value}, status, timestamp)
            elif root in SCHEDULE_ROOTS:
                command = request.args.get("command")
                if isinstance(command, str):
                    try:
                        command = json.loads(command)
                    except json.JSONDecodeError:
                        command = {"raw": command}
                if not isinstance(command, dict):
                    command = {"raw": str(command or "")}
                schedule = {
                    "cron": request.args.get("cron") or value.get("cron") or "",
                    "interval_seconds": request.args.get("interval_seconds") or value.get("interval_seconds") or "",
                    "next_run_at": request.args.get("next_run_at") or value.get("next_run_at") or "",
                    "trigger": request.args.get("trigger") or value.get("trigger") or root,
                    **value,
                }
                entity = store.upsert_schedule(entity_id, root, name, command, schedule, status, timestamp)
            elif root == "usage":
                amount = float(request.args.get("amount") or value.get("amount") or 1)
                metric = str(request.args.get("metric") or value.get("metric") or name)
                unit = str(request.args.get("unit") or value.get("unit") or "count")
                entity = store.record_usage_item(entity_id, root, metric, amount, unit, {"action": action, **value}, timestamp)
            elif root in EVENT_ROOTS:
                entity = store.append_event(entity_id, root, str(request.args.get("event_type") or action), {"name": name, **value}, status, timestamp)
            else:
                entity = store.upsert_entity(entity_id, root, name, {"action": action, **value}, status, timestamp)
            return _result(definition, request, "completed", {"entity": entity}, display={"type": "entity_detail"})
        if action == "delete":
            if not entity_id:
                return _result(definition, request, "failed", {}, error_code="id_required")
            if root in KV_ROOTS:
                deleted = store.delete_kv(root, entity_id)
            elif root in TEXT_ROOTS:
                deleted = store.delete_text_record(entity_id)
            elif root in SCHEDULE_ROOTS:
                deleted = store.delete_schedule(entity_id)
            else:
                deleted = store.delete_entity(entity_id)
            return _result(
                definition,
                request,
                "completed" if deleted else "not_found",
                {"id": entity_id, "deleted": deleted},
                error_code="" if deleted else "entity_not_found",
            )
        if action == "clear":
            if root in KV_ROOTS:
                deleted = store.clear_kv(root)
            elif root in TEXT_ROOTS:
                deleted = store.clear_text_records(root)
            elif root in SCHEDULE_ROOTS:
                deleted = store.clear_schedules(root)
            elif root == "usage":
                deleted = store.clear_usage(root)
            elif root in EVENT_ROOTS:
                deleted = store.clear_events(root)
            else:
                items = store.list_entities(root, 500)
                deleted = 0
                for item in items:
                    if store.delete_entity(item["id"]):
                        deleted += 1
            return _result(definition, request, "completed", {"root": root, "deleted": deleted})
        return _result(definition, request, "failed", {}, error_code="unsupported_native_action")

    return handler


def local_tool_handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    tool = definition.root
    action = definition.action
    if tool == "project":
        return _project_handler(definition, request)
    if tool in {"test", "build", "lint", "format"}:
        return _script_handler(definition, request)
    if tool in {"deploy", "release", "rollback"}:
        return _deployment_handler(definition, request)
    if tool == "shell":
        return _shell_handler(definition, request)
    if tool == "process":
        return _process_handler(definition, request)
    if tool in {"service", "gateway"}:
        return _service_handler(definition, request)
    if tool == "env":
        return _env_handler(definition, request)
    if tool == "checksum":
        return _checksum_handler(definition, request)
    if tool == "archive":
        return _archive_handler(definition, request)
    if tool == "python":
        return _python_handler(definition, request)
    if tool == "package":
        return _package_handler(definition, request)
    if tool == "database":
        return _database_handler(definition, request)
    if tool == "port":
        return _port_handler(definition, request)
    if tool == "document":
        return _document_handler(definition, request)
    if tool in {"tool", "mcp", "skill", "plugin"}:
        return _inventory_handler(definition, request)
    if tool in {"pr", "issue"}:
        return _github_item_handler(definition, request)
    if action in {"status", "list", "validate", "report"}:
        detected = shutil.which(tool) is not None
        return _result(
            definition,
            request,
            "completed",
            {
                "tool": tool,
                "action": action,
                "detected": detected,
                "executable": shutil.which(tool) or "",
                "note": "Command is available for deterministic dispatch." if detected else "No matching local executable was found.",
            },
            display={"type": "capability_status"},
        )
    return _result(
        definition,
        request,
        "unavailable",
        {
            "tool": tool,
            "action": action,
            "required": f"Install or configure a deterministic {tool} adapter before execution.",
        },
        error_code="prerequisite_unavailable",
        message=f"{tool}.{action} is registered but no configured deterministic adapter is available.",
    )


EXTERNAL_EXECUTABLES = {
    "codex": "codex",
    "claude": "claude",
    "hermes": "hermes",
    "openclaw": "openclaw",
    "device": "adb",
    "android": "adb",
    "browser": "npx",
    "web": "curl",
    "http": "curl",
    "ssh": "ssh",
    "scp": "scp",
    "smtp": "",
    "webhook": "curl",
}


def _external_status(definition: CommandDefinition, request: CommandRequest, executable: str = "") -> CommandResult:
    executable = executable or EXTERNAL_EXECUTABLES.get(definition.root, definition.root)
    detected = bool(executable and shutil.which(executable))
    return _result(
        definition,
        request,
        "completed",
        {
            "adapter": definition.root,
            "action": definition.action,
            "detected": detected,
            "executable": shutil.which(executable) if executable else "",
        },
        display={"type": "adapter_status"},
    )


def _url_from_request(request: CommandRequest) -> str:
    return str(request.args.get("url") or request.args.get("uri") or request.args.get("target") or "").strip()


def _valid_http_url(url: str) -> bool:
    parsed = urllib.parse.urlparse(url)
    return parsed.scheme in {"http", "https"} and bool(parsed.netloc)


def _http_request(definition: CommandDefinition, request: CommandRequest, *, method: str = "GET") -> CommandResult:
    url = _url_from_request(request)
    if not url:
        return _result(definition, request, "failed", {}, error_code="url_required")
    if not _valid_http_url(url):
        return _result(definition, request, "failed", {"url": url}, error_code="url_invalid")
    timeout = max(1, min(int(request.args.get("timeout") or 15), 120))
    max_bytes = max(1, min(int(request.args.get("max_bytes") or 65536), 1024 * 1024))
    body = request.args.get("body") or request.args.get("content") or ""
    data = None
    if method not in {"GET", "HEAD"}:
        data = str(body).encode("utf-8")
    headers = {"User-Agent": "GalaxySSI-Command-Adapter/1.0"}
    if data is not None:
        headers["Content-Type"] = str(request.args.get("content_type") or "text/plain; charset=utf-8")
    try:
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        with urllib.request.urlopen(req, timeout=timeout) as response:
            raw = response.read(max_bytes)
            return _result(
                definition,
                request,
                "completed",
                {
                    "url": url,
                    "method": method,
                    "status_code": response.status,
                    "headers": dict(response.headers.items()),
                    "body": raw.decode("utf-8", errors="replace"),
                    "truncated": response.length is not None and response.length > len(raw),
                },
                display={"type": "http_response"},
            )
    except urllib.error.HTTPError as exc:
        raw = exc.read(max_bytes)
        return _result(
            definition,
            request,
            "failed",
            {"url": url, "method": method, "status_code": exc.code, "body": raw.decode("utf-8", errors="replace")},
            error_code="http_error",
        )
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        return _result(
            definition,
            request,
            "unavailable",
            {"url": url, "method": method},
            error_code="network_unavailable",
            message=str(exc)[:300],
        )


def _web_http_handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    if definition.action in {"status", "list"}:
        return _result(definition, request, "completed", {"adapter": definition.root, "network": True}, display={"type": "adapter_status"})
    if definition.action in {"inspect", "search", "run", "receive"}:
        return _http_request(definition, request, method=str(request.args.get("method") or "GET").upper())
    if definition.action in {"send", "sync"}:
        return _http_request(definition, request, method=str(request.args.get("method") or "POST").upper())
    return _result(definition, request, "unavailable", {"action": definition.action}, error_code="web_action_unavailable")


def _dns_handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    if definition.action in {"status", "list"}:
        return _result(definition, request, "completed", {"adapter": "dns", "resolver": "system"}, display={"type": "adapter_status"})
    hostname = str(request.args.get("host") or request.args.get("hostname") or request.args.get("name") or "").strip()
    if not hostname:
        return _result(definition, request, "failed", {}, error_code="dns_hostname_required")
    try:
        rows = socket.getaddrinfo(hostname, None)
        addresses = sorted({row[4][0] for row in rows})
        return _result(definition, request, "completed", {"hostname": hostname, "addresses": addresses}, display={"type": "dns_result"})
    except socket.gaierror as exc:
        return _result(definition, request, "unavailable", {"hostname": hostname}, error_code="dns_unavailable", message=str(exc)[:300])


def _browser_handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    if definition.action in {"status", "list"}:
        return _result(
            definition,
            request,
            "completed",
            {"adapter": "browser", "playwright_detected": shutil.which("npx") is not None, "system_browser": True},
            display={"type": "adapter_status"},
        )
    if definition.action in {"inspect", "search"}:
        return _http_request(definition, request, method="GET")
    if definition.action in {"run", "send"}:
        url = _url_from_request(request)
        if not url:
            return _result(definition, request, "failed", {}, error_code="url_required")
        if not _valid_http_url(url):
            return _result(definition, request, "failed", {"url": url}, error_code="url_invalid")
        opened = webbrowser.open(url)
        return _result(definition, request, "completed" if opened else "unavailable", {"url": url, "opened": opened}, error_code="" if opened else "browser_unavailable")
    return _result(definition, request, "unavailable", {"action": definition.action}, error_code="browser_action_unavailable")


def _phone_permission_handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    root = definition.root
    if definition.action in {"status", "list", "inspect"}:
        return _result(
            definition,
            request,
            "completed",
            {
                "capability": root,
                "phone_tool_broker_required": True,
                "adb_fallback_available": shutil.which("adb") is not None,
                "configured": False,
            },
            display={"type": "adapter_status"},
        )
    return _result(
        definition,
        request,
        "unavailable",
        {
            "capability": root,
            "action": definition.action,
            "required": "A deterministic Phone Tool Broker action contract.",
        },
        error_code="phone_action_unavailable",
        message=f"{root}.{definition.action} is registered but has no deterministic execution contract.",
    )


def _adb_devices(adb: str) -> tuple[list[str], str]:
    try:
        completed = subprocess.run(
            [adb, "devices"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=10,
            check=False,
            shell=False,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return [], str(exc)[:300]
    if completed.returncode != 0:
        return [], (completed.stderr or completed.stdout or "").strip()[:300]
    devices = []
    for line in completed.stdout.splitlines()[1:]:
        fields = line.strip().split()
        if len(fields) >= 2 and fields[1] == "device":
            devices.append(fields[0])
    return devices, ""


def _adb_handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    if definition.action not in {"status", "list", "inspect", "run", "send", "sync"}:
        return _result(definition, request, "unavailable", {"action": definition.action}, error_code="adb_action_unavailable")
    adb = shutil.which("adb")
    if not adb:
        return _result(definition, request, "unavailable", {"required_executable": "adb"}, error_code="prerequisite_unavailable", message="ADB is not installed or not on PATH.")
    if definition.action in {"status", "list"}:
        return _run_argv(definition, request, [adb, "devices", "-l"], workspace_root(request), timeout=20)
    devices, probe_error = _adb_devices(adb)
    requested_serial = str(request.args.get("serial") or "").strip()
    if not devices:
        return _result(
            definition,
            request,
            "unavailable",
            {"devices": [], "probe_error": probe_error},
            error_code="adb_device_unavailable",
            message="ADB is available, but no authorized Android device is connected.",
        )
    if requested_serial and requested_serial not in devices:
        return _result(
            definition,
            request,
            "unavailable",
            {"devices": devices, "requested_serial": requested_serial},
            error_code="adb_device_unavailable",
            message="The requested Android device is not connected or authorized.",
        )
    if len(devices) > 1 and not requested_serial:
        return _result(
            definition,
            request,
            "unavailable",
            {"devices": devices},
            error_code="adb_device_selection_required",
            message="Multiple Android devices are connected; select a device serial.",
        )
    adb_target = [adb, "-s", requested_serial or devices[0]]
    if definition.action == "inspect":
        return _run_argv(definition, request, [*adb_target, "shell", "getprop"], workspace_root(request), timeout=30)
    if definition.action == "run":
        argv = _coerce_argv(request.args.get("argv") or request.args.get("command"))
        if not argv:
            return _result(definition, request, "failed", {}, error_code="adb_command_required")
        return _run_argv(definition, request, [*adb_target, *argv], workspace_root(request), timeout=int(request.args.get("timeout") or 60))
    if definition.action == "send":
        text = str(request.args.get("text") or request.args.get("content") or "").strip()
        if not text:
            return _result(definition, request, "failed", {}, error_code="adb_text_required")
        return _run_argv(definition, request, [*adb_target, "shell", "input", "text", text], workspace_root(request), timeout=15)
    if definition.action == "sync":
        return _run_argv(definition, request, [*adb_target, "sync"], workspace_root(request), timeout=int(request.args.get("timeout") or 120))
    return _result(definition, request, "unavailable", {"action": definition.action}, error_code="adb_action_unavailable")


def _ssh_handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    if definition.action in {"status", "list"}:
        return _external_status(definition, request, "ssh")
    if definition.action not in {"run", "inspect"}:
        return _result(definition, request, "unavailable", {"action": definition.action}, error_code="ssh_action_unavailable")
    ssh = shutil.which("ssh")
    if not ssh:
        return _result(definition, request, "unavailable", {"required_executable": "ssh"}, error_code="prerequisite_unavailable")
    host = str(request.args.get("host") or request.args.get("target") or "").strip()
    if not host:
        return _result(definition, request, "failed", {}, error_code="ssh_host_required")
    argv = _coerce_argv(request.args.get("argv") or request.args.get("command"))
    if not argv:
        return _result(definition, request, "failed", {}, error_code="ssh_command_required")
    return _run_argv(definition, request, [ssh, host, *argv], workspace_root(request), timeout=int(request.args.get("timeout") or 60))


def _scp_handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    if definition.action in {"status", "list"}:
        return _external_status(definition, request, "scp")
    if definition.action not in {"run", "send", "receive", "sync"}:
        return _result(definition, request, "unavailable", {"action": definition.action}, error_code="scp_action_unavailable")
    scp = shutil.which("scp")
    if not scp:
        return _result(definition, request, "unavailable", {"required_executable": "scp"}, error_code="prerequisite_unavailable")
    source = str(request.args.get("source") or request.args.get("from") or "").strip()
    destination = str(request.args.get("destination") or request.args.get("to") or "").strip()
    if not source or not destination:
        return _result(definition, request, "failed", {}, error_code="scp_source_destination_required")
    return _run_argv(definition, request, [scp, source, destination], workspace_root(request), timeout=int(request.args.get("timeout") or 120))


def _node_handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    if definition.action in {"status", "list"}:
        return _external_status(definition, request, "node")
    if definition.action not in {"run", "inspect"}:
        return _result(definition, request, "unavailable", {"action": definition.action}, error_code="node_action_unavailable")
    node = shutil.which("node")
    if not node:
        return _result(definition, request, "unavailable", {"required_executable": "node"}, error_code="prerequisite_unavailable")
    code = str(request.args.get("code") or request.args.get("script") or "").strip()
    argv = _coerce_argv(request.args.get("argv") or request.args.get("command"))
    if code:
        return _run_argv(definition, request, [node, "-e", code], workspace_root(request), timeout=int(request.args.get("timeout") or 30))
    if argv:
        return _run_argv(definition, request, [node, *argv], workspace_root(request), timeout=int(request.args.get("timeout") or 30))
    return _result(definition, request, "failed", {}, error_code="node_code_required")


def _webhook_handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    if definition.action in {"status", "list"}:
        return _external_status(definition, request, "curl")
    if definition.action in {"send", "sync", "run"}:
        return _http_request(definition, request, method=str(request.args.get("method") or "POST").upper())
    return _result(definition, request, "unavailable", {"action": definition.action}, error_code="webhook_action_unavailable")


def _smtp_handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    if definition.action in {"status", "list"}:
        return _result(definition, request, "completed", {"adapter": "smtp", "configured": bool(request.args.get("host"))}, display={"type": "adapter_status"})
    if definition.action != "send":
        return _result(definition, request, "unavailable", {"action": definition.action}, error_code="smtp_action_unavailable")
    host = str(request.args.get("host") or "").strip()
    sender = str(request.args.get("from") or request.args.get("sender") or "").strip()
    recipient = str(request.args.get("to") or request.args.get("recipient") or "").strip()
    if not host or not sender or not recipient:
        return _result(definition, request, "failed", {}, error_code="smtp_required_fields_missing")
    port = int(request.args.get("port") or 587)
    subject = str(request.args.get("subject") or "GalaxySSI command message")
    body = str(request.args.get("body") or request.args.get("content") or "")
    message = f"From: {sender}\r\nTo: {recipient}\r\nSubject: {subject}\r\n\r\n{body}"
    try:
        with smtplib.SMTP(host, port, timeout=max(1, min(int(request.args.get("timeout") or 15), 120))) as client:
            if bool(request.args.get("starttls") if "starttls" in request.args else True):
                client.starttls()
            username = str(request.args.get("username") or "")
            password = str(request.args.get("password") or "")
            if username and password:
                client.login(username, password)
            client.sendmail(sender, [recipient], message.encode("utf-8"))
        return _result(definition, request, "completed", {"host": host, "port": port, "from": sender, "to": recipient}, display={"type": "smtp_send"})
    except (OSError, smtplib.SMTPException) as exc:
        return _result(definition, request, "unavailable", {"host": host, "port": port}, error_code="smtp_unavailable", message=str(exc)[:300])


def _communication_handler(store: CommandStore, definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    root = definition.root
    action = definition.action
    timestamp = now_iso()
    item_id = str(request.args.get("id") or f"{root}-{new_run_id()}").strip()
    if action in {"status", "list", "receive", "search", "inspect"}:
        items = store.list_text_records(root, _limit(request)) if root == "message" else store.list_entities(root, _limit(request))
        query = str(request.args.get("query") or "").lower()
        if query:
            items = [item for item in items if query in json.dumps(item, ensure_ascii=False).lower()]
        return _result(definition, request, "completed", {"root": root, "items": items}, display={"type": "entity_list"})
    if action in {"send", "sync", "run"}:
        name = str(request.args.get("name") or request.args.get("title") or item_id)
        value = request.args.get("value")
        if isinstance(value, str):
            try:
                value = json.loads(value)
            except json.JSONDecodeError:
                value = {"text": value}
        if not isinstance(value, dict):
            value = {}
        if root == "message":
            body = str(request.args.get("body") or request.args.get("content") or value.get("body") or value.get("text") or "")
            item = store.upsert_text_record(item_id, root, name, body, {"action": action, **value}, "queued", timestamp)
        else:
            item = store.upsert_entity(item_id, root, name, {"action": action, **value}, "active", timestamp)
        return _result(definition, request, "completed", {"entity": item}, display={"type": "entity_detail"})
    return _result(definition, request, "unavailable", {"action": action}, error_code="communication_action_unavailable")


def _worker_automation_handler(store: CommandStore, definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    root = definition.root
    action = definition.action
    timestamp = now_iso()
    item_id = str(request.args.get("id") or f"{root}-{new_run_id()}").strip()
    if action in {"status", "list", "inspect", "receive", "search"}:
        return _result(definition, request, "completed", {"root": root, "items": store.list_schedules(root, _limit(request))}, display={"type": "entity_list"})
    if action in {"sync", "send", "run"}:
        command = request.args.get("command")
        if isinstance(command, str):
            command_payload = {"raw": command}
        elif isinstance(command, dict):
            command_payload = command
        else:
            command_payload = {}
        schedule = {
            "cron": request.args.get("cron") or "",
            "interval_seconds": request.args.get("interval_seconds") or "",
            "next_run_at": request.args.get("next_run_at") or "",
            "trigger": request.args.get("trigger") or action,
        }
        item = store.upsert_schedule(item_id, root, str(request.args.get("name") or item_id), command_payload, schedule, "active", timestamp)
        return _result(definition, request, "completed", {"entity": item}, display={"type": "entity_detail"})
    return _result(definition, request, "unavailable", {"action": action}, error_code="worker_action_unavailable")


def external_adapter_handler(store: CommandStore):
    def handler(definition: CommandDefinition, request: CommandRequest) -> CommandResult:
        return _external_adapter_handler(store, definition, request)

    return handler


def _adapter_history_handler(
    store: CommandStore,
    definition: CommandDefinition,
    request: CommandRequest,
) -> CommandResult:
    query = str(request.args.get("query") or "").strip()
    run_id = str(request.args.get("run_id") or "").strip()
    history = store.search_runs(
        definition.root,
        query=query,
        run_id=run_id,
        limit=min(_limit(request, 20), 200),
        excluded_actions=("inspect", "receive", "search"),
    )
    runtime_name = EXTERNAL_EXECUTABLES.get(definition.root)
    if runtime_name is None:
        runtime_name = definition.root
    runtime_path = shutil.which(runtime_name) if runtime_name else ""
    common = {
        "adapter": definition.root,
        "action": definition.action,
        "runtime": runtime_name,
        "runtime_detected": bool(runtime_path),
        "runtime_path": runtime_path or "",
        "count": len(history),
    }
    if definition.action == "inspect":
        return _result(
            definition,
            request,
            "completed",
            {
                **common,
                "run_id": run_id,
                "latest": history[0] if history else None,
            },
            display={"type": "adapter_inspection"},
        )
    return _result(
        definition,
        request,
        "completed",
        {
            **common,
            "query": query,
            "items": history,
        },
        display={
            "type": (
                "adapter_search_results"
                if definition.action == "search"
                else "adapter_received_results"
            )
        },
    )


def _external_adapter_handler(store: CommandStore, definition: CommandDefinition, request: CommandRequest) -> CommandResult:
    if definition.action in EXTERNAL_HISTORY_ACTIONS.get(definition.root, ()):
        return _adapter_history_handler(store, definition, request)
    if definition.root in {"web", "http"}:
        return _web_http_handler(definition, request)
    if definition.root == "url":
        return _web_http_handler(definition, request)
    if definition.root == "dns":
        return _dns_handler(definition, request)
    if definition.root in {"browser", "playwright", "chromium"}:
        return _browser_handler(definition, request)
    if definition.root in {"device", "android"}:
        return _adb_handler(definition, request)
    if definition.root in {"camera", "microphone", "accessibility", "sensor", "notification", "location"}:
        return _phone_permission_handler(definition, request)
    if definition.root == "ssh":
        return _ssh_handler(definition, request)
    if definition.root == "scp":
        return _scp_handler(definition, request)
    if definition.root == "node":
        return _node_handler(definition, request)
    if definition.root == "webhook":
        return _webhook_handler(definition, request)
    if definition.root == "smtp":
        return _smtp_handler(definition, request)
    if definition.root in {"channel", "message", "contact"}:
        return _communication_handler(store, definition, request)
    if definition.root in {"worker", "automation"}:
        return _worker_automation_handler(store, definition, request)
    executable = EXTERNAL_EXECUTABLES.get(definition.root, definition.root)
    detected = bool(executable and shutil.which(executable))
    if definition.action in {"status", "list"}:
        return _external_status(definition, request, executable)
    if not detected:
        return _result(
            definition,
            request,
            "unavailable",
            {
                "adapter": definition.root,
                "action": definition.action,
                "required_executable": executable,
            },
            error_code="prerequisite_unavailable",
            message=f"{definition.root}.{definition.action} requires a configured runtime or external service.",
        )
    return _result(
        definition,
        request,
        "unavailable",
        {
            "adapter": definition.root,
            "action": definition.action,
            "detected": True,
            "reason": "Adapter execution contract exists; provider-specific execution is intentionally gated until configured.",
        },
        error_code="adapter_not_configured",
    )


def bind_handlers(registry: CommandRegistry, store: CommandStore | None = None) -> None:
    store = store or CommandStore()
    registry.register("commands.list", commands_list(registry))
    registry.register("capabilities.list", capabilities_list(registry))
    registry.register("help.show", help_show(registry))
    registry.register("file.list", file_list)
    registry.register("file.read", file_read)
    registry.register("file.write", file_write)
    registry.register("file.move", file_move)
    registry.register("file.copy", file_copy)
    registry.register("file.delete", file_delete)
    registry.register("file.mkdir", file_mkdir)
    registry.register("git.status", git_status)
    registry.register("git.diff", git_diff)
    registry.register("git.log", git_log)
    registry.register("git.branch", git_branch)
    native_roots = {
        "session", "context", "checkpoint", "task", "run", "goal", "plan",
        "agent", "memory", "knowledge", "config", "profile", "permission",
        "approval", "sandbox", "audit", "log", "usage", "backup", "reset",
        "migrate", "model", "schedule", "cron", "heartbeat", "watch", "trigger",
        "event", "queue", "artifact", "cache", "index", "policy", "template",
        "dataset", "workspace",
    }
    tool_roots = {
        "project", "test", "build", "lint", "format", "deploy", "release",
        "rollback", "shell", "process", "port", "service", "gateway", "tool",
        "mcp", "skill", "plugin", "document", "pr", "issue",
        "env", "archive", "checksum", "database", "python", "package",
    }
    state_handler = native_state_handler(store)
    adapter_handler = external_adapter_handler(store)
    for command in registry.list():
        command_id = command["command_id"]
        if registry.handler(command_id) is not None:
            continue
        root = command["root"]
        if root in native_roots:
            registry.register(command_id, state_handler)
        elif root in tool_roots:
            registry.register(command_id, local_tool_handler)
        else:
            registry.register(command_id, adapter_handler)
