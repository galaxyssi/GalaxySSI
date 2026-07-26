"""Isolated, checkpointed self-evolution tasks for SignalASI Desktop."""
from __future__ import annotations

import hashlib
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import threading
import time
import uuid
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Callable, Iterable, Sequence


PROTOCOL = "signalasi.evolution-task.v1"
TERMINAL_STATUSES = {
    "published",
    "completed",
    "failed",
    "blocked",
    "cancelled",
    "rolled_back",
}
CANDIDATE_STATUSES = {"waiting_approval", "publishing", "published"}
RISK_LEVELS = {"low", "medium", "high", "critical"}
TASK_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$")
SAFE_SCOPE_COMPONENT = re.compile(r"^[A-Za-z0-9._+@() -]+$")
PROTECTED_SCOPE_ROOTS = {
    ".git",
    ".github/workflows",
    ".openai",
    "node_modules",
    "dist",
    "build",
    "runtime-data",
}
MAX_LOG_BYTES = 2 * 1024 * 1024
PREPARATION_BLOCKER_CODES = {
    "source_root_missing",
    "source_root_invalid",
    "worktree_create_failed",
}


class EvolutionError(RuntimeError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


@dataclass
class EvolutionGate:
    id: str
    status: str = "pending"
    duration_millis: int = 0
    exit_code: int = 0
    summary: str = ""
    log_path: str = ""


@dataclass
class EvolutionAttempt:
    number: int
    status: str
    branch: str
    worktree: str
    changed_files: list[str] = field(default_factory=list)
    gates: list[EvolutionGate] = field(default_factory=list)
    failure_code: str = ""
    failure_summary: str = ""
    agent_summary: str = ""
    started_at_millis: int = 0
    completed_at_millis: int = 0


@dataclass
class EvolutionTask:
    task_id: str
    problem: str
    reproduction_steps: list[str]
    scope: list[str]
    acceptance: list[str]
    risk_level: str
    max_attempts: int
    execution_target: str = "desktop"
    protocol: str = PROTOCOL
    status: str = "proposed"
    agent_id: str = "codex"
    client_route_id: str = ""
    base_commit: str = ""
    candidate_commit: str = ""
    candidate_branch: str = ""
    approval_hash: str = ""
    pull_request_url: str = ""
    attempts: list[EvolutionAttempt] = field(default_factory=list)
    last_error_code: str = ""
    last_error: str = ""
    created_at_millis: int = 0
    updated_at_millis: int = 0

    def public(
        self,
        include_worktree: bool = False,
        include_route: bool = False,
    ) -> dict[str, Any]:
        value = asdict(self)
        if not include_route:
            value.pop("client_route_id", None)
        if not include_worktree:
            for attempt in value["attempts"]:
                attempt["worktree"] = ""
                for gate in attempt["gates"]:
                    gate["log_path"] = ""
        return value


@dataclass(frozen=True)
class GateCommand:
    id: str
    argv: tuple[str, ...]
    cwd: str = "."
    timeout_seconds: int = 900


PatchAgent = Callable[[EvolutionTask, EvolutionAttempt, Path, str], str]
EventSink = Callable[[dict[str, Any]], None]


def _now_millis() -> int:
    return int(time.time() * 1_000)


def _state_root() -> Path:
    configured = str(os.environ.get("SIGNALASI_STATE_DIR") or "").strip()
    return Path(configured).expanduser() if configured else Path(
        os.environ.get("APPDATA") or Path.home()
    ) / "SignalASI"


def _source_root() -> Path:
    configured = str(os.environ.get("SIGNALASI_SOURCE_ROOT") or "").strip()
    if configured:
        return Path(configured).expanduser().resolve()
    candidate = Path(__file__).resolve()
    for parent in candidate.parents:
        if (parent / ".git").exists() and (parent / "apps").is_dir():
            return parent
    raise EvolutionError(
        "source_root_missing",
        "Set SIGNALASI_SOURCE_ROOT to a SignalASI Git checkout.",
    )


def _safe_task_id(value: str) -> str:
    clean = str(value or "").strip()
    if not TASK_ID_PATTERN.fullmatch(clean):
        raise EvolutionError("task_id_invalid", "Evolution task id is invalid.")
    return clean


def _normalized_scope(values: Iterable[str]) -> list[str]:
    normalized: list[str] = []
    for raw in values:
        value = str(raw or "").replace("\\", "/").strip().strip("/")
        parts = value.split("/")
        if (
            not value
            or len(value) > 512
            or any(part in {"", ".", ".."} or not SAFE_SCOPE_COMPONENT.fullmatch(part) for part in parts)
        ):
            raise EvolutionError("scope_invalid", f"Unsafe evolution scope: {raw!r}")
        lowered = value.casefold()
        protected_component = any(
            part.casefold() in {".git", "node_modules", "dist", "build", "runtime-data"}
            for part in parts
        )
        if protected_component or any(
            lowered == root or lowered.startswith(f"{root}/")
            for root in PROTECTED_SCOPE_ROOTS
        ):
            raise EvolutionError("scope_protected", f"Protected evolution scope: {value}")
        if value not in normalized:
            normalized.append(value)
    if not normalized or len(normalized) > 64:
        raise EvolutionError("scope_invalid", "Evolution tasks require 1 to 64 scoped paths.")
    return normalized


def _bounded_strings(values: Iterable[str], *, maximum: int, count: int) -> list[str]:
    result = [str(value or "").strip()[:maximum] for value in values]
    return [value for value in result if value][:count]


def _inside(candidate: Path, parent: Path) -> bool:
    try:
        candidate.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


def _discover_android_sdk(environment: dict[str, str]) -> Path | None:
    candidates = [
        environment.get("ANDROID_HOME"),
        environment.get("ANDROID_SDK_ROOT"),
        str(Path(environment["LOCALAPPDATA"]) / "Android" / "Sdk")
        if environment.get("LOCALAPPDATA")
        else "",
        str(Path(environment["USERPROFILE"]) / "AppData" / "Local" / "Android" / "Sdk")
        if environment.get("USERPROFILE")
        else "",
        str(Path.home() / "Library" / "Android" / "sdk"),
        str(Path.home() / "Android" / "Sdk"),
    ]
    for raw in candidates:
        if not raw:
            continue
        candidate = Path(raw).expanduser()
        if candidate.is_dir():
            return candidate.resolve()
    return None


class EvolutionStore:
    def __init__(self, root: Path | None = None) -> None:
        self.root = (Path(root) if root else _state_root() / "evolution").resolve()
        self.tasks_root = self.root / "tasks"
        self.worktrees_root = self.root / "worktrees"
        self.logs_root = self.root / "logs"
        self._lock = threading.RLock()
        for directory in (self.tasks_root, self.worktrees_root, self.logs_root):
            directory.mkdir(parents=True, exist_ok=True)

    def save(self, task: EvolutionTask) -> None:
        task.updated_at_millis = _now_millis()
        target = self.tasks_root / f"{_safe_task_id(task.task_id)}.json"
        temporary = target.with_suffix(".tmp")
        payload = json.dumps(asdict(task), ensure_ascii=True, indent=2, sort_keys=True)
        with self._lock:
            temporary.write_text(payload, encoding="utf-8")
            os.replace(temporary, target)

    def get(self, task_id: str) -> EvolutionTask | None:
        target = self.tasks_root / f"{_safe_task_id(task_id)}.json"
        with self._lock:
            if not target.is_file():
                return None
            return self._decode(json.loads(target.read_text(encoding="utf-8")))

    def list(self, limit: int = 100) -> list[EvolutionTask]:
        rows: list[EvolutionTask] = []
        with self._lock:
            for target in self.tasks_root.glob("*.json"):
                try:
                    rows.append(self._decode(json.loads(target.read_text(encoding="utf-8"))))
                except (OSError, ValueError, TypeError, json.JSONDecodeError):
                    continue
        return sorted(rows, key=lambda item: item.updated_at_millis, reverse=True)[:max(1, min(limit, 500))]

    @staticmethod
    def _decode(value: dict[str, Any]) -> EvolutionTask:
        attempts = []
        for row in value.get("attempts") or []:
            gates = [EvolutionGate(**gate) for gate in row.get("gates") or []]
            attempts.append(EvolutionAttempt(**{**row, "gates": gates}))
        fields = {
            key: item
            for key, item in value.items()
            if key in EvolutionTask.__dataclass_fields__ and key != "attempts"
        }
        return EvolutionTask(**fields, attempts=attempts)


class EvolutionCommandRunner:
    def run(
        self,
        argv: Sequence[str],
        cwd: Path,
        *,
        timeout_seconds: int = 120,
        log_path: Path | None = None,
    ) -> subprocess.CompletedProcess[str]:
        if not argv or any("\x00" in str(value) for value in argv):
            raise EvolutionError("command_invalid", "Evolution command is invalid.")
        environment = {**os.environ, "GIT_TERMINAL_PROMPT": "0", "CI": "1"}
        android_sdk = _discover_android_sdk(environment)
        if android_sdk is not None:
            environment.setdefault("ANDROID_HOME", str(android_sdk))
            environment.setdefault("ANDROID_SDK_ROOT", str(android_sdk))
        completed = subprocess.run(
            [str(value) for value in argv],
            cwd=str(cwd),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=max(1, int(timeout_seconds)),
            shell=False,
            check=False,
            env=environment,
        )
        if log_path is not None:
            log_path.parent.mkdir(parents=True, exist_ok=True)
            log_path.write_text(completed.stdout[-MAX_LOG_BYTES:], encoding="utf-8")
        return completed


class EvolutionManager:
    """Owns candidate worktrees without mutating the active checkout."""

    def __init__(
        self,
        *,
        source_root: Path | None = None,
        store: EvolutionStore | None = None,
        runner: EvolutionCommandRunner | None = None,
        patch_agent: PatchAgent | None = None,
        event_sink: EventSink | None = None,
    ) -> None:
        self.source_root = (Path(source_root) if source_root else _source_root()).resolve()
        self.store = store or EvolutionStore()
        self.runner = runner or EvolutionCommandRunner()
        self.patch_agent = patch_agent
        self.event_sink = event_sink or (lambda _event: None)
        self._cancellations: dict[str, threading.Event] = {}
        self._threads: dict[str, threading.Thread] = {}
        self._lock = threading.RLock()
        self._validate_repository()

    def create(
        self,
        *,
        problem: str,
        scope: Iterable[str],
        acceptance: Iterable[str],
        reproduction_steps: Iterable[str] = (),
        risk_level: str = "medium",
        max_attempts: int = 3,
        agent_id: str = "codex",
        client_route_id: str = "",
        task_id: str = "",
    ) -> EvolutionTask:
        clean_problem = str(problem or "").strip()[:4_000]
        if len(clean_problem) < 4:
            raise EvolutionError("problem_invalid", "Evolution task problem is too short.")
        clean_acceptance = _bounded_strings(acceptance, maximum=1_000, count=40)
        if not clean_acceptance:
            raise EvolutionError("acceptance_missing", "Evolution task acceptance criteria are required.")
        clean_risk = str(risk_level or "medium").strip().casefold()
        if clean_risk not in RISK_LEVELS:
            raise EvolutionError("risk_invalid", "Evolution task risk level is invalid.")
        attempts = max(1, min(int(max_attempts), 5))
        identifier = _safe_task_id(task_id) if task_id else f"evolve-{uuid.uuid4().hex[:20]}"
        now = _now_millis()
        task = EvolutionTask(
            task_id=identifier,
            problem=clean_problem,
            reproduction_steps=_bounded_strings(reproduction_steps, maximum=1_000, count=20),
            scope=_normalized_scope(scope),
            acceptance=clean_acceptance,
            risk_level=clean_risk,
            max_attempts=attempts,
            agent_id=re.sub(r"[^a-z0-9._-]", "", str(agent_id).casefold())[:64] or "codex",
            client_route_id=re.sub(r"[^A-Za-z0-9_-]", "", str(client_route_id or ""))[:64],
            base_commit=self._git_text(("rev-parse", "HEAD")),
            created_at_millis=now,
            updated_at_millis=now,
        )
        self.store.save(task)
        self._emit(task, "created")
        return task

    def start(self, task_id: str) -> EvolutionTask:
        task = self.require(task_id)
        with self._lock:
            running = self._threads.get(task.task_id)
            if running and running.is_alive():
                return task
            if task.status in CANDIDATE_STATUSES:
                raise EvolutionError("candidate_already_ready", "Evolution candidate is already ready.")
            cancellation = threading.Event()
            self._cancellations[task.task_id] = cancellation
            thread = threading.Thread(
                target=self._run_background,
                args=(task.task_id, cancellation),
                daemon=True,
                name=f"evolution-{task.task_id[-12:]}",
            )
            self._threads[task.task_id] = thread
            thread.start()
        return self.require(task.task_id)

    def run_sync(self, task_id: str) -> EvolutionTask:
        cancellation = threading.Event()
        with self._lock:
            self._cancellations[task_id] = cancellation
        self._run_task(task_id, cancellation)
        return self.require(task_id)

    def cancel(self, task_id: str) -> EvolutionTask:
        task = self.require(task_id)
        with self._lock:
            self._cancellations.setdefault(task.task_id, threading.Event()).set()
        if task.status not in TERMINAL_STATUSES and task.status not in CANDIDATE_STATUSES:
            task.status = "cancelled"
            task.last_error_code = "cancelled"
            task.last_error = "Evolution task was cancelled."
            self.store.save(task)
            self._emit(task, "cancel_requested")
        return task

    def discard(self, task_id: str) -> EvolutionTask:
        task = self.require(task_id)
        self.cancel(task_id)
        for attempt in task.attempts:
            self._remove_worktree(attempt, delete_branch=True)
        task.status = "rolled_back"
        task.candidate_commit = ""
        task.candidate_branch = ""
        task.approval_hash = ""
        self.store.save(task)
        self._emit(task, "rolled_back")
        return task

    def publish(self, task_id: str, approval_hash: str, *, base_branch: str = "main") -> EvolutionTask:
        task = self.require(task_id)
        if task.status != "waiting_approval" or not task.candidate_branch or not task.candidate_commit:
            raise EvolutionError("candidate_not_ready", "Evolution candidate is not ready to publish.")
        if not task.approval_hash or not secrets.compare_digest(
            task.approval_hash,
            str(approval_hash or "").strip().casefold(),
        ):
            raise EvolutionError("approval_hash_invalid", "Evolution approval hash does not match the candidate.")
        attempt = task.attempts[-1]
        if any(gate.status != "passed" for gate in attempt.gates):
            raise EvolutionError("quality_gate_incomplete", "All quality gates must pass before publishing.")
        clean_base = re.sub(r"[^A-Za-z0-9._/-]", "", str(base_branch or "main"))[:120]
        if not clean_base or clean_base.startswith(("-", "/")) or ".." in clean_base:
            raise EvolutionError("base_branch_invalid", "Pull request base branch is invalid.")
        worktree = Path(attempt.worktree)
        task.status = "publishing"
        self.store.save(task)
        self._emit(task, "publishing")
        try:
            pushed = self.runner.run(
                ("git", "push", "--set-upstream", "origin", task.candidate_branch),
                worktree,
                timeout_seconds=600,
            )
            if pushed.returncode != 0:
                raise EvolutionError("candidate_push_failed", pushed.stdout[-4_000:])
            title = f"Prepare self-evolution candidate: {task.problem[:72]}"
            body = self._pull_request_body(task, attempt)
            created = self.runner.run(
                (
                    "gh",
                    "pr",
                    "create",
                    "--base",
                    clean_base,
                    "--head",
                    task.candidate_branch,
                    "--title",
                    title,
                    "--body",
                    body,
                ),
                worktree,
                timeout_seconds=300,
            )
            if created.returncode != 0:
                raise EvolutionError("pull_request_create_failed", created.stdout[-4_000:])
            task.pull_request_url = next(
                (
                    line.strip()
                    for line in reversed(created.stdout.splitlines())
                    if line.strip().startswith(("https://", "http://"))
                ),
                "",
            )
            task.status = "published"
            task.last_error = ""
            task.last_error_code = ""
            self.store.save(task)
            self._emit(task, "published")
            return task
        except Exception as exc:
            task.status = "waiting_approval"
            task.last_error_code = exc.code if isinstance(exc, EvolutionError) else "publish_failed"
            task.last_error = str(exc)[:4_000]
            self.store.save(task)
            self._emit(task, "publish_failed")
            raise

    def require(self, task_id: str) -> EvolutionTask:
        task = self.store.get(task_id)
        if task is None:
            raise EvolutionError("task_not_found", "Evolution task was not found.")
        return task

    def _run_background(self, task_id: str, cancellation: threading.Event) -> None:
        try:
            self._run_task(task_id, cancellation)
        finally:
            with self._lock:
                self._threads.pop(task_id, None)

    def _run_task(self, task_id: str, cancellation: threading.Event) -> None:
        task = self.require(task_id)
        failure_context = task.last_error
        for number in range(len(task.attempts) + 1, task.max_attempts + 1):
            if cancellation.is_set():
                self._mark_cancelled(task)
                return
            try:
                attempt = self._prepare_attempt(task, number)
            except EvolutionError as exc:
                task.status = "blocked" if exc.code in PREPARATION_BLOCKER_CODES else "failed"
                task.last_error_code = exc.code
                task.last_error = str(exc)[:4_000]
                self.store.save(task)
                self._emit(task, "blocked" if task.status == "blocked" else "failed")
                return
            try:
                task.status = "running"
                self.store.save(task)
                self._emit(task, "agent_started", attempt=number)
                if self.patch_agent is None:
                    raise EvolutionError(
                        "patch_agent_unavailable",
                        "No evolution patch Agent is configured.",
                    )
                attempt.agent_summary = str(
                    self.patch_agent(task, attempt, Path(attempt.worktree), failure_context)
                    or ""
                )[:8_000]
                if cancellation.is_set():
                    raise EvolutionError("cancelled", "Evolution task was cancelled.")
                attempt.changed_files = self._changed_files(Path(attempt.worktree))
                self._validate_changed_scope(task.scope, attempt.changed_files)
                if not attempt.changed_files:
                    raise EvolutionError("no_changes", "The Agent did not modify the candidate.")
                self._attach_gate_dependencies(Path(attempt.worktree))
                task.status = "validating"
                attempt.status = "validating"
                self.store.save(task)
                self._emit(task, "validation_started", attempt=number)
                gates = self._run_gates(task, attempt, cancellation)
                attempt.gates = gates
                failed = next((gate for gate in gates if gate.status != "passed"), None)
                if failed is not None:
                    raise EvolutionError(
                        "quality_gate_failed",
                        f"Quality gate {failed.id} failed: {failed.summary}",
                    )
                candidate_commit = self._commit_candidate(task, attempt)
                attempt.status = "passed"
                attempt.completed_at_millis = _now_millis()
                task.status = "waiting_approval"
                task.candidate_commit = candidate_commit
                task.candidate_branch = attempt.branch
                task.last_error = ""
                task.last_error_code = ""
                task.approval_hash = self._approval_hash(task, attempt)
                self.store.save(task)
                self._emit(task, "candidate_ready", attempt=number)
                return
            except EvolutionError as exc:
                attempt.status = "cancelled" if exc.code == "cancelled" else "failed"
                attempt.failure_code = exc.code
                attempt.failure_summary = str(exc)[:4_000]
                attempt.completed_at_millis = _now_millis()
                task.last_error_code = exc.code
                task.last_error = str(exc)[:4_000]
                failure_context = task.last_error
                self.store.save(task)
                self._emit(task, "attempt_failed", attempt=number)
                self._remove_worktree(attempt, delete_branch=True)
                if exc.code == "cancelled" or cancellation.is_set():
                    self._mark_cancelled(task)
                    return
            except Exception as exc:
                attempt.status = "failed"
                attempt.failure_code = "unexpected_failure"
                attempt.failure_summary = str(exc)[:4_000]
                attempt.completed_at_millis = _now_millis()
                task.last_error_code = attempt.failure_code
                task.last_error = attempt.failure_summary
                failure_context = task.last_error
                self.store.save(task)
                self._emit(task, "attempt_failed", attempt=number)
                self._remove_worktree(attempt, delete_branch=True)
        task.status = "failed"
        self.store.save(task)
        self._emit(task, "failed")

    def _prepare_attempt(self, task: EvolutionTask, number: int) -> EvolutionAttempt:
        task.status = "preparing"
        branch = f"evolution/{task.task_id}-a{number}"
        worktree = (self.store.worktrees_root / task.task_id / f"attempt-{number}").resolve()
        if _inside(worktree, self.source_root):
            raise EvolutionError("worktree_unsafe", "Evolution worktree must be outside the active checkout.")
        if worktree.exists():
            shutil.rmtree(worktree, ignore_errors=True)
        worktree.parent.mkdir(parents=True, exist_ok=True)
        completed = self.runner.run(
            ("git", "worktree", "add", "-b", branch, str(worktree), task.base_commit),
            self.source_root,
            timeout_seconds=120,
        )
        if completed.returncode != 0:
            raise EvolutionError("worktree_create_failed", completed.stdout[-2_000:])
        attempt = EvolutionAttempt(
            number=number,
            status="preparing",
            branch=branch,
            worktree=str(worktree),
            started_at_millis=_now_millis(),
        )
        task.attempts.append(attempt)
        self.store.save(task)
        self._emit(task, "worktree_ready", attempt=number)
        return attempt

    def _run_gates(
        self,
        task: EvolutionTask,
        attempt: EvolutionAttempt,
        cancellation: threading.Event,
    ) -> list[EvolutionGate]:
        worktree = Path(attempt.worktree)
        gates: list[EvolutionGate] = []
        for command in self._gate_commands(attempt.changed_files):
            gate = EvolutionGate(id=command.id, status="running")
            gates.append(gate)
            attempt.gates = gates
            self.store.save(task)
            self._emit(task, "gate_started", attempt=attempt.number, gate=gate.id)
            if cancellation.is_set():
                gate.status = "cancelled"
                break
            started = time.monotonic()
            log_path = self.store.logs_root / task.task_id / f"attempt-{attempt.number}-{gate.id}.log"
            try:
                completed = self.runner.run(
                    command.argv,
                    (worktree / command.cwd).resolve(),
                    timeout_seconds=command.timeout_seconds,
                    log_path=log_path,
                )
                gate.exit_code = completed.returncode
                gate.status = "passed" if completed.returncode == 0 else "failed"
                gate.summary = self._gate_summary(completed.stdout, completed.returncode)
            except subprocess.TimeoutExpired:
                gate.status = "failed"
                gate.exit_code = -1
                gate.summary = "Quality gate timed out."
            except Exception as exc:
                gate.status = "failed"
                gate.exit_code = -1
                gate.summary = str(exc)[:4_000]
            gate.duration_millis = int((time.monotonic() - started) * 1_000)
            gate.log_path = str(log_path)
            self.store.save(task)
            self._emit(task, "gate_finished", attempt=attempt.number, gate=gate.id)
            if gate.status != "passed":
                break
        return gates

    def _gate_commands(self, changed_files: Iterable[str]) -> list[GateCommand]:
        changed = list(changed_files)
        gates = [
            GateCommand("git-diff-check", ("git", "diff", "--check"), timeout_seconds=60),
        ]
        desktop_changed = any(value.startswith("apps/desktop/") or value.startswith("core/") for value in changed)
        android_changed = any(value.startswith("apps/android/") or value.startswith("core/") for value in changed)
        if desktop_changed:
            gates.extend([
                GateCommand(
                    "desktop-backend-tests",
                    (
                        sys.executable,
                        "-m",
                        "unittest",
                        "discover",
                        "-s",
                        "core/signalasi-link/backend",
                        "-p",
                        "test_*.py",
                    ),
                    cwd="apps/desktop",
                    timeout_seconds=1_800,
                ),
                GateCommand(
                    "desktop-source-check",
                    ("node", "scripts/check.js"),
                    cwd="apps/desktop",
                    timeout_seconds=600,
                ),
                GateCommand(
                    "desktop-package",
                    ("node", "scripts/package-win.js"),
                    cwd="apps/desktop",
                    timeout_seconds=3_600,
                ),
                GateCommand(
                    "desktop-ui-smoke",
                    ("node", "scripts/smoke-ui.js"),
                    cwd="apps/desktop",
                    timeout_seconds=900,
                ),
            ])
        if android_changed:
            wrapper = "gradlew.bat" if os.name == "nt" else "./gradlew"
            gates.append(GateCommand(
                "android-unit-build",
                (wrapper, ":app:testDebugUnitTest", ":app:assembleDebug", "--no-daemon"),
                cwd="apps/android",
                timeout_seconds=3_600,
            ))
        return gates

    def _changed_files(self, worktree: Path) -> list[str]:
        completed = self.runner.run(
            ("git", "status", "--porcelain=v1", "-z", "--untracked-files=all"),
            worktree,
            timeout_seconds=60,
        )
        if completed.returncode != 0:
            raise EvolutionError("git_status_failed", completed.stdout[-2_000:])
        values: list[str] = []
        chunks = completed.stdout.split("\x00")
        index = 0
        while index < len(chunks):
            row = chunks[index]
            index += 1
            if len(row) < 4:
                continue
            path = row[3:].replace("\\", "/")
            if " -> " in path:
                path = path.split(" -> ", 1)[1]
            if row[:2][0] in {"R", "C"} and index < len(chunks):
                path = chunks[index].replace("\\", "/")
                index += 1
            if path and path not in values:
                values.append(path)
        return sorted(values)

    def _attach_gate_dependencies(self, worktree: Path) -> None:
        """Expose ignored build runtimes only after the Agent has finished editing."""
        for relative in ("apps/desktop/.electron-runtime", "apps/desktop/.runtime-python"):
            source = self.source_root / relative
            target = worktree / relative
            if not source.is_dir():
                continue
            self._remove_gate_dependency_target(target)
            target.parent.mkdir(parents=True, exist_ok=True)
            try:
                if os.name == "nt":
                    linked = self.runner.run(
                        ("cmd.exe", "/d", "/c", "mklink", "/J", str(target), str(source)),
                        worktree,
                        timeout_seconds=30,
                    )
                    if linked.returncode != 0:
                        raise EvolutionError("gate_dependency_failed", linked.stdout[-2_000:])
                else:
                    target.symlink_to(source, target_is_directory=True)
            except OSError as exc:
                raise EvolutionError(
                    "gate_dependency_failed",
                    f"Could not attach trusted build runtime {relative}: {exc}",
                ) from exc

    @staticmethod
    def _remove_gate_dependency_target(target: Path) -> None:
        if not target.exists() and not target.is_symlink():
            return
        is_junction = getattr(os.path, "isjunction", lambda _value: False)(target)
        if target.is_symlink() or is_junction:
            target.unlink() if target.is_symlink() else target.rmdir()
        elif target.is_dir():
            shutil.rmtree(target)
        else:
            target.unlink()

    @staticmethod
    def _validate_changed_scope(scope: Iterable[str], changed: Iterable[str]) -> None:
        allowed = list(scope)
        violations = [
            value
            for value in changed
            if not any(value == root or value.startswith(f"{root.rstrip('/')}/") for root in allowed)
        ]
        if violations:
            raise EvolutionError(
                "scope_violation",
                "Agent changed files outside the declared scope: " + ", ".join(violations[:20]),
            )

    def _commit_candidate(self, task: EvolutionTask, attempt: EvolutionAttempt) -> str:
        worktree = Path(attempt.worktree)
        add = self.runner.run(("git", "add", "--all"), worktree, timeout_seconds=60)
        if add.returncode != 0:
            raise EvolutionError("candidate_stage_failed", add.stdout[-2_000:])
        commit = self.runner.run(
            (
                "git",
                "-c",
                "user.name=SignalASI Evolution",
                "-c",
                "user.email=signalasi@hotmail.com",
                "commit",
                "-m",
                f"Prepare evolution candidate {task.task_id}",
            ),
            worktree,
            timeout_seconds=120,
        )
        if commit.returncode != 0:
            raise EvolutionError("candidate_commit_failed", commit.stdout[-2_000:])
        return self._git_text(("rev-parse", "HEAD"), cwd=worktree)

    def _remove_worktree(self, attempt: EvolutionAttempt, *, delete_branch: bool) -> None:
        worktree = Path(attempt.worktree)
        self.runner.run(
            ("git", "worktree", "remove", "--force", str(worktree)),
            self.source_root,
            timeout_seconds=120,
        )
        if worktree.exists():
            shutil.rmtree(worktree, ignore_errors=True)
        if delete_branch and attempt.branch:
            self.runner.run(
                ("git", "branch", "-D", attempt.branch),
                self.source_root,
                timeout_seconds=60,
            )

    def _validate_repository(self) -> None:
        if not self.source_root.is_dir():
            raise EvolutionError("source_root_missing", "SignalASI source checkout does not exist.")
        completed = self.runner.run(("git", "rev-parse", "--is-inside-work-tree"), self.source_root)
        if completed.returncode != 0 or completed.stdout.strip() != "true":
            raise EvolutionError("source_root_invalid", "SignalASI source root is not a Git checkout.")
        if _inside(self.store.worktrees_root, self.source_root):
            raise EvolutionError("state_root_unsafe", "Evolution worktrees must not be stored inside the source checkout.")

    def _git_text(self, arguments: Sequence[str], cwd: Path | None = None) -> str:
        completed = self.runner.run(("git", *arguments), cwd or self.source_root, timeout_seconds=60)
        if completed.returncode != 0:
            raise EvolutionError("git_command_failed", completed.stdout[-2_000:])
        return completed.stdout.strip()

    @staticmethod
    def _gate_summary(output: str, exit_code: int) -> str:
        clean = "\n".join(line.rstrip() for line in str(output or "").splitlines() if line.strip())
        if not clean:
            return "Passed." if exit_code == 0 else f"Exited with code {exit_code}."
        return clean[-4_000:]

    @staticmethod
    def _approval_hash(task: EvolutionTask, attempt: EvolutionAttempt) -> str:
        gate_digest = [
            {"id": gate.id, "status": gate.status, "exit_code": gate.exit_code}
            for gate in attempt.gates
        ]
        payload = json.dumps(
            {
                "protocol": task.protocol,
                "task_id": task.task_id,
                "base_commit": task.base_commit,
                "candidate_commit": task.candidate_commit,
                "scope": task.scope,
                "risk_level": task.risk_level,
                "gates": gate_digest,
            },
            ensure_ascii=True,
            separators=(",", ":"),
            sort_keys=True,
        )
        return hashlib.sha256(payload.encode("utf-8")).hexdigest()

    @staticmethod
    def _pull_request_body(task: EvolutionTask, attempt: EvolutionAttempt) -> str:
        acceptance = "\n".join(f"- {value}" for value in task.acceptance)
        gates = "\n".join(
            f"- `{gate.id}`: {gate.status} ({gate.duration_millis} ms)"
            for gate in attempt.gates
        )
        return (
            "## Evolution Task\n\n"
            f"{task.problem}\n\n"
            "## Acceptance\n\n"
            f"{acceptance}\n\n"
            "## Quality Gates\n\n"
            f"{gates}\n\n"
            f"Approval hash: `{task.approval_hash}`"
        )[:20_000]

    def _mark_cancelled(self, task: EvolutionTask) -> None:
        task.status = "cancelled"
        task.last_error_code = "cancelled"
        task.last_error = "Evolution task was cancelled."
        self.store.save(task)
        self._emit(task, "cancelled")

    def _emit(self, task: EvolutionTask, event: str, **metadata: Any) -> None:
        self.event_sink({
            "type": "evolution_task_event",
            "event": event,
            "task": task.public(),
            "_client_route_id": task.client_route_id,
            "metadata": metadata,
            "timestamp_millis": _now_millis(),
        })


_manager: EvolutionManager | None = None
_manager_lock = threading.Lock()


def evolution_manager(
    *,
    patch_agent: PatchAgent | None = None,
    event_sink: EventSink | None = None,
) -> EvolutionManager:
    global _manager
    with _manager_lock:
        if _manager is None:
            _manager = EvolutionManager(patch_agent=patch_agent, event_sink=event_sink)
        else:
            if patch_agent is not None:
                _manager.patch_agent = patch_agent
            if event_sink is not None:
                _manager.event_sink = event_sink
        return _manager


def default_evolution_patch_agent(
    task: EvolutionTask,
    attempt: EvolutionAttempt,
    worktree: Path,
    previous_failure: str,
) -> str:
    from agent_gateway import ask_evolution_agent

    scope = "\n".join(f"- {value}" for value in task.scope)
    acceptance = "\n".join(f"- {value}" for value in task.acceptance)
    reproduction = "\n".join(f"- {value}" for value in task.reproduction_steps) or "- Not supplied"
    retry_context = (
        "\nThe previous isolated attempt failed. Correct the cause without repeating it:\n"
        f"{previous_failure[:4_000]}\n"
        if previous_failure else ""
    )
    prompt = f"""
You are repairing SignalASI inside a disposable Git worktree.

Problem:
{task.problem}

Reproduction:
{reproduction}

Allowed source scope:
{scope}

Acceptance criteria:
{acceptance}
{retry_context}
Inspect the existing code before editing. Modify only the allowed scope. Add focused tests for the
behavioral change. Do not push, create a pull request, change Git configuration, modify generated
output, or touch files outside the worktree. Run only focused checks needed to validate your patch;
the host will run the complete immutable quality-gate suite afterward. Leave the candidate source
changes in the current worktree and finish with a concise summary.
""".strip()
    return ask_evolution_agent(
        task.agent_id,
        prompt,
        task_id=f"{task.task_id}-a{attempt.number}",
        working_directory=worktree,
    )
