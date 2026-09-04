"""Protect host-owned and automatically executed configuration from Agents."""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import stat
import threading
import time
import uuid
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Iterable


PROTOCOL = "galaxyssi.host-execution-config-guard/1.0"
MAX_PROTECTED_FILE_BYTES = 2 * 1024 * 1024
MAX_PROTECTED_TOTAL_BYTES = 16 * 1024 * 1024
MAX_PROTECTED_ENTRIES = 2_048
MAX_AUDIT_BYTES = 2 * 1024 * 1024

_EXACT_RULES = {
    ".galaxyssi-task.json": (
        "galaxyssi_host_metadata",
        "GalaxySSI task metadata is owned by the host",
    ),
    ".mcp.json": (
        "agent_tool_configuration",
        "MCP configuration can grant an Agent additional host capabilities",
    ),
    "mcp.json": (
        "agent_tool_configuration",
        "MCP configuration can grant an Agent additional host capabilities",
    ),
    ".vscode/tasks.json": (
        "ide_automatic_execution",
        "IDE task configuration can execute host commands",
    ),
    ".vscode/launch.json": (
        "ide_automatic_execution",
        "IDE launch configuration can execute host commands",
    ),
    ".vscode/settings.json": (
        "ide_automatic_execution",
        "IDE workspace settings can activate host-side execution",
    ),
    ".git/config": (
        "git_host_configuration",
        "Git configuration can redirect hooks and credential helpers",
    ),
    ".gitlab-ci.yml": (
        "ci_automatic_execution",
        "CI configuration can execute with repository credentials",
    ),
    "azure-pipelines.yml": (
        "ci_automatic_execution",
        "CI configuration can execute with repository credentials",
    ),
    "jenkinsfile": (
        "ci_automatic_execution",
        "CI configuration can execute with repository credentials",
    ),
    ".pre-commit-config.yaml": (
        "git_hook_configuration",
        "Pre-commit configuration can execute host commands",
    ),
    ".pre-commit-config.yml": (
        "git_hook_configuration",
        "Pre-commit configuration can execute host commands",
    ),
    ".npmrc": (
        "runtime_automatic_configuration",
        "Package-manager configuration can redirect host execution",
    ),
    ".yarnrc": (
        "runtime_automatic_configuration",
        "Package-manager configuration can load host-side extensions",
    ),
    ".yarnrc.yml": (
        "runtime_automatic_configuration",
        "Package-manager configuration can load host-side extensions",
    ),
    ".pnpmfile.cjs": (
        "runtime_automatic_configuration",
        "Package-manager hooks execute on the host",
    ),
    ".pythonrc.py": (
        "runtime_automatic_configuration",
        "Python startup configuration executes on the host",
    ),
    "sitecustomize.py": (
        "runtime_automatic_configuration",
        "Python automatically imports sitecustomize on startup",
    ),
    "usercustomize.py": (
        "runtime_automatic_configuration",
        "Python automatically imports usercustomize on startup",
    ),
}

_TREE_RULES = {
    ".galaxyssi": (
        "galaxyssi_host_control",
        "GalaxySSI execution checkpoints and control state are host-owned",
    ),
    ".github/workflows": (
        "ci_automatic_execution",
        "GitHub Actions workflows can execute with repository credentials",
    ),
    ".github/actions": (
        "ci_automatic_execution",
        "Local GitHub Actions code is loaded by privileged workflows",
    ),
    ".circleci": (
        "ci_automatic_execution",
        "CI configuration can execute with repository credentials",
    ),
    ".openai": (
        "agent_host_configuration",
        "OpenAI host configuration is outside Agent write authority",
    ),
    ".codex": (
        "agent_host_configuration",
        "Codex host configuration is outside Agent write authority",
    ),
    ".claude": (
        "agent_host_configuration",
        "Claude host configuration is outside Agent write authority",
    ),
    ".cursor": (
        "agent_host_configuration",
        "Editor Agent configuration is outside Agent write authority",
    ),
    ".devcontainer": (
        "container_automatic_execution",
        "Development-container configuration can execute host commands",
    ),
    ".git/hooks": (
        "git_hook_configuration",
        "Git hooks execute automatically on the host",
    ),
    ".idea/runconfigurations": (
        "ide_automatic_execution",
        "IDE run configurations can execute host commands",
    ),
}

_TREE_SCAN_PATHS = {
    ".galaxyssi": ".galaxyssi",
    ".github/workflows": ".github/workflows",
    ".github/actions": ".github/actions",
    ".circleci": ".circleci",
    ".openai": ".openai",
    ".codex": ".codex",
    ".claude": ".claude",
    ".cursor": ".cursor",
    ".devcontainer": ".devcontainer",
    ".git/hooks": ".git/hooks",
    ".idea/runconfigurations": ".idea/runConfigurations",
}
_DYNAMIC_SCAN_ROOTS = (".git/modules",)
_ENV_TEMPLATE_SUFFIXES = (".example", ".sample", ".template")
_AUDIT_LOCK = threading.RLock()


class HostExecutionConfigGuardError(RuntimeError):
    """Base error for host execution configuration protection."""


class HostExecutionConfigViolation(HostExecutionConfigGuardError):
    def __init__(self, violations: Iterable[dict]) -> None:
        self.violations = tuple(dict(item) for item in violations)
        paths = ", ".join(
            str(item.get("path") or "")
            for item in self.violations[:4]
        )
        if len(self.violations) > 4:
            paths += f", +{len(self.violations) - 4} more"
        super().__init__(
            "Agent write to host execution configuration was blocked and "
            f"rolled back: {paths or 'protected configuration'}"
        )


@dataclass(frozen=True)
class ProtectedPathRule:
    code: str
    reason: str


@dataclass(frozen=True)
class _PathState:
    kind: str
    mode: int
    size_bytes: int
    sha256: str
    content: bytes | None = None

    def comparable(self) -> tuple[str, int, int, str]:
        return self.kind, self.mode, self.size_bytes, self.sha256


def classify_host_execution_path(value: str | Path) -> ProtectedPathRule | None:
    relative = _normalized_relative(value)
    lowered = relative.casefold()
    exact = _EXACT_RULES.get(lowered)
    if exact is not None:
        return ProtectedPathRule(*exact)
    for prefix, rule in _TREE_RULES.items():
        if lowered == prefix or lowered.startswith(f"{prefix}/"):
            return ProtectedPathRule(*rule)
    if (
        lowered.startswith(".git/modules/")
        and lowered.endswith("/config")
    ):
        return ProtectedPathRule(
            "git_host_configuration",
            "Submodule Git configuration can redirect host execution",
        )
    name = PurePosixPath(lowered).name
    if name == ".env" or (
        name.startswith(".env.")
        and not name.endswith(_ENV_TEMPLATE_SUFFIXES)
    ):
        return ProtectedPathRule(
            "environment_automatic_configuration",
            "Environment files can alter privileged host execution",
        )
    parts = PurePosixPath(lowered).parts
    if "site-packages" in parts and (
        name.endswith(".pth")
        or name in {"sitecustomize.py", "usercustomize.py"}
    ):
        return ProtectedPathRule(
            "runtime_automatic_configuration",
            "Python automatically loads this file on host startup",
        )
    return None


def assert_host_execution_path_writable(
    root: Path,
    target: Path,
    *,
    agent_id: str = "agent",
    capture_id: str = "",
) -> None:
    resolved_root = Path(root).expanduser().resolve()
    resolved_target = Path(target).expanduser().resolve(strict=False)
    try:
        relative = resolved_target.relative_to(resolved_root).as_posix()
    except ValueError as exc:
        raise HostExecutionConfigGuardError(
            "Write target is outside the guarded workspace"
        ) from exc
    rule = classify_host_execution_path(relative)
    if rule is None:
        return
    violation = {
        "path": relative,
        "operation": "blocked_before_write",
        "reason_code": rule.code,
        "reason": rule.reason,
    }
    _append_audit(
        resolved_root,
        agent_id=agent_id,
        capture_id=capture_id,
        violations=(violation,),
    )
    raise HostExecutionConfigViolation((violation,))


class HostExecutionConfigGuard:
    """Snapshots protected paths and rolls back Agent changes."""

    def __init__(
        self,
        root: Path,
        before: dict[str, _PathState],
        *,
        agent_id: str,
        capture_id: str,
    ) -> None:
        self.root = Path(root)
        self.before = dict(before)
        self.agent_id = str(agent_id or "agent")[:160]
        self.capture_id = str(capture_id or "")[:240]
        self._finished = False

    @classmethod
    def begin(
        cls,
        root: Path,
        *,
        agent_id: str = "agent",
        capture_id: str = "",
    ) -> "HostExecutionConfigGuard":
        resolved_root = Path(root).expanduser().resolve()
        if not resolved_root.is_dir():
            raise HostExecutionConfigGuardError(
                "Guarded Agent workspace is unavailable"
            )
        before = _capture_protected_paths(resolved_root, retain_content=True)
        return cls(
            resolved_root,
            before,
            agent_id=agent_id,
            capture_id=capture_id,
        )

    def finish(self) -> tuple[dict, ...]:
        if self._finished:
            return ()
        self._finished = True
        after = _capture_protected_paths(self.root, retain_content=False)
        violations = _describe_changes(self.before, after)
        if not violations:
            return ()
        _restore_snapshot(self.root, self.before, after)
        _append_audit(
            self.root,
            agent_id=self.agent_id,
            capture_id=self.capture_id,
            violations=violations,
        )
        return tuple(violations)


def _normalized_relative(value: str | Path) -> str:
    raw = str(value or "").replace("\\", "/").strip("/")
    pure = PurePosixPath(raw)
    if (
        not raw
        or pure.is_absolute()
        or pure.drive
        or any(part in {"", ".", ".."} for part in pure.parts)
    ):
        raise HostExecutionConfigGuardError(
            "Protected path must be normalized and workspace-relative"
        )
    return "/".join(pure.parts)


def _candidate_paths(root: Path) -> list[Path]:
    values: dict[str, Path] = {}

    def add(path: Path) -> None:
        try:
            relative = path.relative_to(root).as_posix()
        except ValueError:
            return
        values[relative.casefold()] = path

    for relative in _EXACT_RULES:
        add(root / Path(*PurePosixPath(relative).parts))
    add(root / "Jenkinsfile")
    try:
        for path in root.iterdir():
            if path.name.casefold() == ".env" or (
                path.name.casefold().startswith(".env.")
                and not path.name.casefold().endswith(_ENV_TEMPLATE_SUFFIXES)
            ):
                add(path)
    except OSError:
        pass
    for relative in _TREE_SCAN_PATHS.values():
        base = root / Path(*PurePosixPath(relative).parts)
        for path in _walk_tree(base):
            add(path)
    for relative in _DYNAMIC_SCAN_ROOTS:
        base = root / Path(*PurePosixPath(relative).parts)
        for path in _walk_tree(base):
            try:
                candidate = path.relative_to(root).as_posix()
            except ValueError:
                continue
            if classify_host_execution_path(candidate) is not None:
                add(path)
    for base in _site_packages_roots(root):
        for path in _walk_tree(base):
            try:
                candidate = path.relative_to(root).as_posix()
            except ValueError:
                continue
            if classify_host_execution_path(candidate) is not None:
                add(path)
    return [values[key] for key in sorted(values)]


def _walk_tree(base: Path) -> Iterable[Path]:
    if not os.path.lexists(base):
        return ()
    pending = [base]
    discovered: list[Path] = []
    while pending:
        current = pending.pop()
        discovered.append(current)
        if _is_link(current) or not current.is_dir():
            continue
        try:
            children = sorted(current.iterdir(), key=lambda item: item.name)
        except OSError:
            continue
        pending.extend(reversed(children))
        if len(discovered) + len(pending) > MAX_PROTECTED_ENTRIES:
            raise HostExecutionConfigGuardError(
                "Protected configuration exceeds the bounded entry limit"
            )
    return tuple(discovered)


def _site_packages_roots(root: Path) -> tuple[Path, ...]:
    values = []
    for parent_name in (".venv", "venv"):
        parent = root / parent_name
        if not parent.is_dir() or _is_link(parent):
            continue
        try:
            for path in parent.rglob("site-packages"):
                if path.is_dir() and not _is_link(path):
                    values.append(path)
                    if len(values) >= 8:
                        return tuple(values)
        except OSError:
            continue
    return tuple(values)


def _capture_protected_paths(
    root: Path,
    *,
    retain_content: bool,
) -> dict[str, _PathState]:
    states: dict[str, _PathState] = {}
    total_bytes = 0
    for path in _candidate_paths(root):
        if not os.path.lexists(path):
            continue
        relative = path.relative_to(root).as_posix()
        rule = classify_host_execution_path(relative)
        if rule is None:
            continue
        if _is_link(path):
            if retain_content:
                raise HostExecutionConfigGuardError(
                    f"Protected host configuration is a link: {relative}"
                )
            target = os.readlink(path)
            states[relative] = _PathState(
                "link",
                0,
                len(target.encode("utf-8", errors="replace")),
                hashlib.sha256(
                    target.encode("utf-8", errors="replace")
                ).hexdigest(),
            )
            continue
        stat_result = path.stat()
        mode = stat.S_IMODE(stat_result.st_mode)
        if path.is_dir():
            states[relative] = _PathState("directory", mode, 0, "")
            continue
        if not path.is_file():
            if retain_content:
                raise HostExecutionConfigGuardError(
                    f"Protected host configuration has an unsupported type: {relative}"
                )
            states[relative] = _PathState("special", mode, 0, "")
            continue
        size = int(stat_result.st_size)
        if retain_content and (
            size > MAX_PROTECTED_FILE_BYTES
            or total_bytes + size > MAX_PROTECTED_TOTAL_BYTES
        ):
            raise HostExecutionConfigGuardError(
                "Protected host configuration exceeds the rollback size limit"
            )
        content = path.read_bytes() if retain_content else None
        if content is not None:
            sha256 = hashlib.sha256(content).hexdigest()
        elif size <= MAX_PROTECTED_FILE_BYTES:
            sha256 = _sha256_file(path)
        else:
            sha256 = hashlib.sha256(
                f"bounded:{size}:{stat_result.st_mtime_ns}".encode("utf-8")
            ).hexdigest()
        total_bytes += size if retain_content else 0
        states[relative] = _PathState(
            "file",
            mode,
            size,
            sha256,
            content,
        )
        if len(states) > MAX_PROTECTED_ENTRIES:
            raise HostExecutionConfigGuardError(
                "Protected configuration exceeds the bounded entry limit"
            )
    return states


def _describe_changes(
    before: dict[str, _PathState],
    after: dict[str, _PathState],
) -> list[dict]:
    violations = []
    for path in sorted(set(before).union(after)):
        previous = before.get(path)
        current = after.get(path)
        if (
            previous is not None
            and current is not None
            and previous.comparable() == current.comparable()
        ):
            continue
        operation = (
            "created"
            if previous is None
            else "deleted"
            if current is None
            else "type_changed"
            if previous.kind != current.kind
            else "modified"
        )
        rule = classify_host_execution_path(path)
        violations.append({
            "path": path,
            "operation": operation,
            "reason_code": (
                rule.code if rule is not None else "host_execution_configuration"
            ),
            "reason": (
                rule.reason
                if rule is not None
                else "Host execution configuration is protected"
            ),
            "before_sha256": previous.sha256 if previous is not None else "",
            "after_sha256": current.sha256 if current is not None else "",
            "before_size_bytes": (
                previous.size_bytes if previous is not None else 0
            ),
            "after_size_bytes": current.size_bytes if current is not None else 0,
        })
    return violations


def _restore_snapshot(
    root: Path,
    before: dict[str, _PathState],
    after: dict[str, _PathState],
) -> None:
    changed = {
        path
        for path in set(before).union(after)
        if (
            before.get(path) is None
            or after.get(path) is None
            or before[path].comparable() != after[path].comparable()
        )
    }
    for relative in sorted(
        changed,
        key=lambda value: (len(PurePosixPath(value).parts), value),
        reverse=True,
    ):
        target = root / Path(*PurePosixPath(relative).parts)
        if os.path.lexists(target):
            _remove_path(target)
    for relative in sorted(
        (path for path in changed if path in before),
        key=lambda value: (len(PurePosixPath(value).parts), value),
    ):
        target = root / Path(*PurePosixPath(relative).parts)
        state = before[relative]
        _ensure_safe_parent(root, target.parent)
        if state.kind == "directory":
            target.mkdir(parents=True, exist_ok=True)
            _chmod_best_effort(target, state.mode)
            continue
        if state.kind != "file" or state.content is None:
            raise HostExecutionConfigGuardError(
                f"Protected configuration could not be restored: {relative}"
            )
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.with_name(
            f".{target.name}.galaxyssi-restore-{uuid.uuid4().hex}.tmp"
        )
        try:
            temporary.write_bytes(state.content)
            _chmod_best_effort(temporary, state.mode)
            os.replace(temporary, target)
        finally:
            temporary.unlink(missing_ok=True)


def _ensure_safe_parent(root: Path, parent: Path) -> None:
    relative = parent.relative_to(root)
    current = root
    for part in relative.parts:
        current = current / part
        if os.path.lexists(current) and (
            _is_link(current) or not current.is_dir()
        ):
            _remove_path(current)
        current.mkdir(exist_ok=True)


def _remove_path(path: Path) -> None:
    if _is_link(path) or path.is_file():
        path.unlink(missing_ok=True)
        return
    if path.is_dir():
        shutil.rmtree(path)
        return
    if os.path.lexists(path):
        path.unlink(missing_ok=True)


def _is_link(path: Path) -> bool:
    if path.is_symlink():
        return True
    is_junction = getattr(path, "is_junction", None)
    return bool(is_junction and is_junction())


def _chmod_best_effort(path: Path, mode: int) -> None:
    try:
        path.chmod(mode)
    except OSError:
        pass


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _append_audit(
    root: Path,
    *,
    agent_id: str,
    capture_id: str,
    violations: Iterable[dict],
) -> None:
    configured_state_root = str(os.environ.get("GALAXYSSI_STATE_DIR") or "").strip()
    state_root = (
        Path(configured_state_root)
        if configured_state_root
        else Path(os.environ.get("APPDATA") or Path.home()) / "GalaxySSI"
    ).expanduser()
    audit_path = state_root / "security" / "host-config-write-audit.jsonl"
    record = {
        "protocol": PROTOCOL,
        "recorded_at_epoch_ms": int(time.time() * 1_000),
        "workspace_id": hashlib.sha256(
            os.path.normcase(str(root)).encode("utf-8", errors="replace")
        ).hexdigest()[:32],
        "agent_id": str(agent_id or "agent")[:160],
        "capture_id": str(capture_id or "")[:240],
        "violations": [dict(item) for item in violations],
    }
    payload = json.dumps(
        record,
        ensure_ascii=True,
        separators=(",", ":"),
    )
    with _AUDIT_LOCK:
        audit_path.parent.mkdir(parents=True, exist_ok=True)
        if audit_path.exists() and audit_path.stat().st_size > MAX_AUDIT_BYTES:
            rotated = audit_path.with_suffix(".jsonl.1")
            rotated.unlink(missing_ok=True)
            audit_path.replace(rotated)
        with audit_path.open("a", encoding="utf-8", newline="\n") as handle:
            handle.write(payload)
            handle.write("\n")
