"""Isolated, checkpointed self-evolution tasks for GalaxySSI Desktop."""
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
from collections import Counter
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Callable, Iterable, Sequence


PROTOCOL = "galaxyssi.evolution-task.v1"
TERMINAL_STATUSES = {
    "published",
    "completed",
    "failed",
    "blocked",
    "cancelled",
    "rolled_back",
}
CANDIDATE_STATUSES = {"waiting_approval", "publishing", "published"}
ACTIVE_EXECUTION_STATUSES = {"preparing", "running", "validating", "publishing"}
SUCCESS_STATUSES = {"published", "completed"}
ATTENTION_STATUSES = {"failed", "blocked"}
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
    "agent_unavailable",
    "gate_dependency_missing",
    "source_fetch_failed",
    "source_pin_invalid",
    "source_root_missing",
    "source_root_invalid",
    "worktree_create_failed",
    "worktree_cleanup_failed",
    "worktree_identity_invalid",
    "worktree_unsafe",
}
NON_RETRYABLE_ATTEMPT_CODES = {
    "active_checkout_changed",
    "active_checkout_check_failed",
    "gate_dependency_failed",
    "gate_dependency_missing",
    "worktree_cleanup_refused",
    "worktree_cleanup_failed",
    "worktree_identity_invalid",
    "worktree_unsafe",
}
EVOLUTION_BRANCH_PATTERN = re.compile(
    r"^evolution/[A-Za-z0-9][A-Za-z0-9._-]{0,95}-a[1-5]$"
)


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
    evidence_sha256: str = ""
    evidence_manifest_path: str = ""
    evidence_manifest_sha256: str = ""


@dataclass
class EvolutionAttempt:
    number: int
    status: str
    branch: str
    worktree: str
    agent_id: str = ""
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
    agent_id: str = "auto"
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
                    gate["evidence_manifest_path"] = ""
        return value


@dataclass(frozen=True)
class EvolutionHealth:
    total_tasks: int
    queued_tasks: int
    active_tasks: int
    waiting_review: int
    successful_tasks: int
    attention_tasks: int
    stale_tasks: int
    total_attempts: int
    failed_attempts: int
    retries: int
    total_gates: int
    passed_gates: int
    failed_gates: int
    gate_pass_percent: int
    success_percent: int
    average_attempt_duration_millis: int
    oldest_review_age_millis: int
    last_activity_at_millis: int
    status_counts: dict[str, int]
    failure_counts: dict[str, int]
    stale_task_ids: list[str]
    generated_at_millis: int
    stale_after_millis: int

    def public(self) -> dict[str, Any]:
        return asdict(self)


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


def evolution_health(
    tasks: Iterable[EvolutionTask],
    *,
    now_millis: int | None = None,
    stale_after_millis: int = 30 * 60 * 1_000,
) -> EvolutionHealth:
    rows = list(tasks)
    now = _now_millis() if now_millis is None else max(0, int(now_millis))
    stale_after = max(60_000, int(stale_after_millis))
    statuses = Counter(task.status for task in rows)
    attempts = [attempt for task in rows for attempt in task.attempts]
    gates = [gate for attempt in attempts for gate in attempt.gates]
    failure_counts: Counter[str] = Counter(
        attempt.failure_code for attempt in attempts if attempt.failure_code
    )
    for task in rows:
        last_attempt_code = task.attempts[-1].failure_code if task.attempts else ""
        if task.last_error_code and task.last_error_code != last_attempt_code:
            failure_counts[task.last_error_code] += 1
    stale_ids = sorted(
        task.task_id
        for task in rows
        if task.status in ACTIVE_EXECUTION_STATUSES
        and task.updated_at_millis > 0
        and now - task.updated_at_millis >= stale_after
    )
    overdue_reviews = [
        task
        for task in rows
        if task.status == "waiting_approval"
        and task.updated_at_millis > 0
        and now - task.updated_at_millis >= stale_after
    ]
    durations = [
        attempt.completed_at_millis - attempt.started_at_millis
        for attempt in attempts
        if attempt.started_at_millis > 0
        and attempt.completed_at_millis >= attempt.started_at_millis
    ]
    passed_gates = sum(gate.status == "passed" for gate in gates)
    failed_gates = sum(gate.status in {"failed", "cancelled"} for gate in gates)
    decided_gates = passed_gates + failed_gates
    successful = sum(task.status in SUCCESS_STATUSES for task in rows)
    unsuccessful = sum(task.status in ATTENTION_STATUSES for task in rows)
    decided_tasks = successful + unsuccessful
    attention_ids = {
        task.task_id for task in rows if task.status in ATTENTION_STATUSES
    } | set(stale_ids) | {task.task_id for task in overdue_reviews}
    review_ages = [
        now - task.updated_at_millis
        for task in rows
        if task.status == "waiting_approval" and task.updated_at_millis > 0
    ]
    return EvolutionHealth(
        total_tasks=len(rows),
        queued_tasks=statuses["proposed"],
        active_tasks=sum(statuses[status] for status in ACTIVE_EXECUTION_STATUSES),
        waiting_review=statuses["waiting_approval"],
        successful_tasks=successful,
        attention_tasks=len(attention_ids),
        stale_tasks=len(stale_ids),
        total_attempts=len(attempts),
        failed_attempts=sum(attempt.status == "failed" for attempt in attempts),
        retries=sum(max(0, len(task.attempts) - 1) for task in rows),
        total_gates=len(gates),
        passed_gates=passed_gates,
        failed_gates=failed_gates,
        gate_pass_percent=(passed_gates * 100 + decided_gates // 2) // decided_gates
        if decided_gates else 0,
        success_percent=(successful * 100 + decided_tasks // 2) // decided_tasks
        if decided_tasks else 0,
        average_attempt_duration_millis=round(sum(durations) / len(durations)) if durations else 0,
        oldest_review_age_millis=max(review_ages, default=0),
        last_activity_at_millis=max((task.updated_at_millis for task in rows), default=0),
        status_counts=dict(sorted(statuses.items())),
        failure_counts=dict(sorted(failure_counts.items())),
        stale_task_ids=stale_ids,
        generated_at_millis=now,
        stale_after_millis=stale_after,
    )


def _state_root() -> Path:
    configured = str(os.environ.get("GALAXYSSI_STATE_DIR") or "").strip()
    return Path(configured).expanduser() if configured else Path(
        os.environ.get("APPDATA") or Path.home()
    ) / "GalaxySSI"


def _source_root() -> Path:
    configured = str(os.environ.get("GALAXYSSI_SOURCE_ROOT") or "").strip()
    if configured:
        return Path(configured).expanduser().resolve()
    candidate = Path(__file__).resolve()
    for parent in candidate.parents:
        if (parent / ".git").exists() and (parent / "apps").is_dir():
            return parent
    raise EvolutionError(
        "source_root_missing",
        "Set GALAXYSSI_SOURCE_ROOT to a GalaxySSI Git checkout.",
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
    except (OSError, RuntimeError, ValueError):
        return False


def _overlaps(first: Path, second: Path) -> bool:
    return _inside(first, second) or _inside(second, first)


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
        self._listeners: dict[str, EventSink] = {}
        self._lock = threading.RLock()
        self._validate_repository()

    def subscribe(self, listener: EventSink) -> str:
        if not callable(listener):
            raise TypeError("Evolution listener must be callable")
        subscription_id = str(uuid.uuid4())
        with self._lock:
            self._listeners[subscription_id] = listener
        return subscription_id

    def unsubscribe(self, subscription_id: str) -> bool:
        with self._lock:
            return self._listeners.pop(str(subscription_id or ""), None) is not None

    def create(
        self,
        *,
        problem: str,
        scope: Iterable[str],
        acceptance: Iterable[str],
        reproduction_steps: Iterable[str] = (),
        risk_level: str = "medium",
        max_attempts: int = 3,
        agent_id: str = "auto",
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
            agent_id=re.sub(r"[^a-z0-9._-]", "", str(agent_id).casefold())[:64] or "auto",
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
            task.status = "preparing"
            self.store.save(task)
        self._emit(task, "start_requested")
        thread.start()
        return self.require(task.task_id)

    def run_sync(self, task_id: str) -> EvolutionTask:
        task = self.require(task_id)
        cancellation = threading.Event()
        with self._lock:
            self._cancellations[task_id] = cancellation
            task.status = "preparing"
            self.store.save(task)
        self._emit(task, "start_requested")
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
        for attempt in task.attempts:
            self._validated_cleanup_target(attempt)
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

    def health(
        self,
        *,
        limit: int = 500,
        now_millis: int | None = None,
        stale_after_millis: int = 30 * 60 * 1_000,
    ) -> EvolutionHealth:
        return evolution_health(
            self.store.list(limit=limit),
            now_millis=now_millis,
            stale_after_millis=stale_after_millis,
        )

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
        try:
            self._validate_gate_evidence(attempt)
        except EvolutionError as exc:
            self._reject_publish(task, exc.code, str(exc))
        clean_base = re.sub(r"[^A-Za-z0-9._/-]", "", str(base_branch or "main"))[:120]
        if not clean_base or clean_base.startswith(("-", "/")) or ".." in clean_base:
            raise EvolutionError("base_branch_invalid", "Pull request base branch is invalid.")
        try:
            worktree = self._managed_worktree_path(attempt.worktree)
        except EvolutionError:
            self._reject_publish(
                task,
                "candidate_workspace_invalid",
                "Evolution candidate workspace is missing or outside managed storage.",
            )
        if not worktree.is_dir():
            self._reject_publish(
                task,
                "candidate_workspace_invalid",
                "Evolution candidate workspace is missing or outside managed storage.",
            )
        try:
            self._validate_worktree_identity(
                worktree,
                branch=attempt.branch,
                expected_commit=None,
            )
        except EvolutionError as exc:
            self._reject_publish(
                task,
                "candidate_workspace_invalid",
                str(exc),
            )
        current_commit = self._git_text(("rev-parse", "HEAD"), cwd=worktree)
        if not secrets.compare_digest(current_commit.casefold(), task.candidate_commit.casefold()):
            self._reject_publish(
                task,
                "candidate_changed_after_review",
                "Evolution candidate changed after review. Validate a new candidate before publishing.",
            )
        current_branch = self._git_text(("branch", "--show-current"), cwd=worktree)
        if current_branch != task.candidate_branch or current_branch != attempt.branch:
            self._reject_publish(
                task,
                "candidate_branch_changed_after_review",
                "Evolution candidate branch changed after review.",
            )
        dirty = self._git_text(("status", "--porcelain=v1"), cwd=worktree)
        if dirty:
            self._reject_publish(
                task,
                "candidate_dirty_after_review",
                "Evolution candidate has unreviewed changes. Validate a new candidate before publishing.",
            )
        self._before_publish(task, worktree, clean_base)
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
            title = self._pull_request_title(task)
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
            if task.pull_request_url:
                labeled = self.runner.run(
                    (
                        "gh",
                        "pr",
                        "edit",
                        task.pull_request_url,
                        "--add-label",
                        "self-evolution",
                    ),
                    worktree,
                    timeout_seconds=120,
                )
                if labeled.returncode != 0:
                    self._emit(
                        task,
                        "publish_label_skipped",
                        label="self-evolution",
                        reason=labeled.stdout[-1_000:],
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

    def _before_publish(
        self,
        task: EvolutionTask,
        worktree: Path,
        base_branch: str,
    ) -> None:
        del task, worktree, base_branch

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
        try:
            self._prepare_task_execution(task)
        except EvolutionError as exc:
            task.status = "blocked"
            task.last_error_code = exc.code
            task.last_error = str(exc)[:4_000]
            self.store.save(task)
            self._emit(task, "blocked")
            return
        for number in range(len(task.attempts) + 1, task.max_attempts + 1):
            if cancellation.is_set():
                self._mark_cancelled(task)
                return
            try:
                selected_agent = self._select_implementation_agent(task)
                attempt = self._prepare_attempt(task, number)
                attempt.agent_id = selected_agent
                self.store.save(task)
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
                active_checkout_before = self._active_checkout_fingerprint()
                try:
                    attempt.agent_summary = str(
                        self.patch_agent(task, attempt, Path(attempt.worktree), failure_context)
                        or ""
                    )[:8_000]
                except Exception as exc:
                    self._assert_active_checkout_unchanged(active_checkout_before)
                    if isinstance(exc, EvolutionError):
                        raise
                    raise EvolutionError(
                        "implementation_channel_failed",
                        f"Implementation Agent {attempt.agent_id or task.agent_id} failed: {exc}",
                    ) from exc
                self._assert_active_checkout_unchanged(active_checkout_before)
                self._validate_worktree_identity(
                    Path(attempt.worktree),
                    branch=attempt.branch,
                    expected_commit=task.base_commit,
                )
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
                self._detach_gate_dependencies(Path(attempt.worktree))
                failed = next((gate for gate in gates if gate.status != "passed"), None)
                if failed is not None:
                    raise self._gate_failure_error(failed)
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
                if not self._cleanup_failed_attempt(task, attempt):
                    return
                if exc.code == "cancelled" or cancellation.is_set():
                    self._mark_cancelled(task)
                    return
                if exc.code in NON_RETRYABLE_ATTEMPT_CODES:
                    task.status = "blocked"
                    self.store.save(task)
                    self._emit(task, "blocked")
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
                if not self._cleanup_failed_attempt(task, attempt):
                    return
        task.status = "failed"
        self.store.save(task)
        self._emit(task, "failed")

    def _prepare_task_execution(self, task: EvolutionTask) -> None:
        """Hook for readiness checks that must run before a worktree is consumed."""

    @staticmethod
    def _gate_failure_error(gate: EvolutionGate) -> EvolutionError:
        return EvolutionError(
            "quality_gate_failed",
            f"Quality gate {gate.id} failed: {gate.summary}",
        )

    def _select_implementation_agent(self, task: EvolutionTask) -> str:
        return task.agent_id

    def _prepare_attempt(self, task: EvolutionTask, number: int) -> EvolutionAttempt:
        task.status = "preparing"
        branch = f"evolution/{task.task_id}-a{number}"
        worktree = self._managed_worktree_path(
            self.store.worktrees_root / task.task_id / f"attempt-{number}"
        )
        if worktree.exists():
            shutil.rmtree(worktree, ignore_errors=True)
        worktree.parent.mkdir(parents=True, exist_ok=True)
        completed = self.runner.run(
            ("git", "worktree", "add", "-b", branch, str(worktree), task.base_commit),
            self.source_root,
            timeout_seconds=120,
        )
        if completed.returncode != 0:
            self._remove_worktree(
                EvolutionAttempt(
                    number=number,
                    status="failed",
                    branch=branch,
                    worktree=str(worktree),
                ),
                delete_branch=True,
            )
            raise EvolutionError("worktree_create_failed", completed.stdout[-2_000:])
        provisional_attempt = EvolutionAttempt(
            number=number,
            status="preparing",
            branch=branch,
            worktree=str(worktree),
            started_at_millis=_now_millis(),
        )
        try:
            self._validate_worktree_identity(
                worktree,
                branch=branch,
                expected_commit=task.base_commit,
            )
        except EvolutionError:
            self._remove_worktree(provisional_attempt, delete_branch=True)
            raise
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
            if not log_path.is_file():
                log_path.parent.mkdir(parents=True, exist_ok=True)
                log_path.write_text(gate.summary, encoding="utf-8")
            gate.log_path = str(log_path)
            gate.evidence_sha256 = self._sha256_path(log_path)
            if gate.status == "passed" and gate.id == "android-device-install-restore":
                try:
                    self._capture_android_gate_evidence(
                        gate,
                        log_path,
                        worktree=worktree,
                    )
                except EvolutionError as exc:
                    gate.status = "failed"
                    gate.exit_code = -1
                    gate.summary = str(exc)[:4_000]
            gate.duration_millis = int((time.monotonic() - started) * 1_000)
            self.store.save(task)
            self._emit(task, "gate_finished", attempt=attempt.number, gate=gate.id)
            if gate.status != "passed":
                break
        return gates

    @staticmethod
    def _sha256_path(path: Path) -> str:
        digest = hashlib.sha256()
        with Path(path).open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        return digest.hexdigest()

    def _capture_android_gate_evidence(
        self,
        gate: EvolutionGate,
        log_path: Path,
        *,
        worktree: Path,
    ) -> None:
        try:
            payload = json.loads(log_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise EvolutionError(
                "gate_evidence_invalid",
                "Android device gate did not return valid JSON evidence.",
            ) from exc
        if not isinstance(payload, dict):
            raise EvolutionError(
                "gate_evidence_invalid",
                "Android device gate evidence must be an object.",
            )
        manifest_raw = str(payload.get("evidence_manifest") or "").strip()
        manifest_sha256 = str(payload.get("evidence_sha256") or "").strip().casefold()
        if not manifest_raw or not re.fullmatch(r"[0-9a-f]{64}", manifest_sha256):
            raise EvolutionError(
                "gate_evidence_invalid",
                "Android device gate did not provide a signed evidence manifest.",
            )
        manifest = Path(manifest_raw).resolve()
        self._validate_android_evidence_manifest(
            manifest,
            manifest_sha256,
            worktree=worktree,
        )
        gate.evidence_manifest_path = str(manifest)
        gate.evidence_manifest_sha256 = manifest_sha256

    def _validate_gate_evidence(self, attempt: EvolutionAttempt) -> None:
        if not attempt.gates:
            raise EvolutionError(
                "gate_evidence_invalid",
                "Evolution candidate has no quality-gate evidence.",
            )
        for gate in attempt.gates:
            log_path = Path(gate.log_path).resolve() if gate.log_path else None
            if (
                log_path is None
                or not log_path.is_file()
                or not _inside(log_path, self.store.logs_root)
                or not re.fullmatch(r"[0-9a-f]{64}", gate.evidence_sha256)
                or not secrets.compare_digest(
                    self._sha256_path(log_path),
                    gate.evidence_sha256,
                )
            ):
                raise EvolutionError(
                    "gate_evidence_invalid",
                    f"Quality-gate evidence is missing or changed: {gate.id}",
                )
            if gate.id == "android-device-install-restore":
                manifest = (
                    Path(gate.evidence_manifest_path).resolve()
                    if gate.evidence_manifest_path
                    else None
                )
                if manifest is None:
                    raise EvolutionError(
                        "gate_evidence_invalid",
                        "Android device evidence manifest is missing.",
                    )
                self._validate_android_evidence_manifest(
                    manifest,
                    gate.evidence_manifest_sha256,
                    worktree=Path(attempt.worktree),
                )

    def _validate_android_evidence_manifest(
        self,
        manifest: Path,
        expected_sha256: str,
        *,
        worktree: Path,
    ) -> None:
        manifest = Path(manifest).resolve()
        if (
            not manifest.is_file()
            or not _inside(manifest, self.store.root)
            or not re.fullmatch(r"[0-9a-f]{64}", str(expected_sha256 or "").casefold())
            or not secrets.compare_digest(
                self._sha256_path(manifest),
                str(expected_sha256).casefold(),
            )
        ):
            raise EvolutionError(
                "gate_evidence_invalid",
                "Android device evidence manifest is missing, unmanaged, or changed.",
            )
        try:
            payload = json.loads(manifest.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise EvolutionError(
                "gate_evidence_invalid",
                "Android device evidence manifest is not valid JSON.",
            ) from exc
        if (
            not isinstance(payload, dict)
            or payload.get("protocol") != "galaxyssi.evolution.android-evidence.v1"
            or payload.get("passed") is not True
            or payload.get("stable_restored") is not True
            or payload.get("fatal_lines")
        ):
            raise EvolutionError(
                "gate_evidence_invalid",
                "Android device evidence does not prove a clean candidate run and stable restore.",
            )
        artifacts = payload.get("artifacts")
        if not isinstance(artifacts, dict):
            raise EvolutionError(
                "gate_evidence_invalid",
                "Android device evidence artifacts are missing.",
            )
        required = {
            "candidate_apk",
            "candidate_screenshot",
            "candidate_logcat",
        }
        if not required.issubset(artifacts):
            raise EvolutionError(
                "gate_evidence_invalid",
                "Android device evidence is missing the APK, screenshot, or logcat artifact.",
            )
        expected_apk = (
            Path(worktree)
            / "apps/android/app/build/outputs/apk/debug/app-debug.apk"
        ).resolve()
        for name, value in artifacts.items():
            if not isinstance(value, dict):
                raise EvolutionError(
                    "gate_evidence_invalid",
                    f"Android evidence artifact is invalid: {name}",
                )
            raw_path = str(value.get("path") or "").strip()
            expected = str(value.get("sha256") or "").strip().casefold()
            path = Path(raw_path).resolve() if raw_path else None
            if (
                path is None
                or not path.is_file()
                or not re.fullmatch(r"[0-9a-f]{64}", expected)
                or not secrets.compare_digest(self._sha256_path(path), expected)
            ):
                raise EvolutionError(
                    "gate_evidence_invalid",
                    f"Android evidence artifact is missing or changed: {name}",
                )
            if name == "candidate_apk" and path != expected_apk:
                raise EvolutionError(
                    "gate_evidence_invalid",
                    "Android evidence refers to an unexpected candidate APK.",
                )
            if name in {"candidate_screenshot", "candidate_logcat"} and not _inside(
                path,
                self.store.root,
            ):
                raise EvolutionError(
                    "gate_evidence_invalid",
                    f"Android evidence artifact is outside managed storage: {name}",
                )
            if name == "candidate_screenshot" and not path.read_bytes().startswith(
                b"\x89PNG\r\n\x1a\n"
            ):
                raise EvolutionError(
                    "gate_evidence_invalid",
                    "Android candidate screenshot is not a PNG image.",
                )

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
                        "core/galaxyssi-link/backend",
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
            source = self._gate_dependency_source(relative)
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

    def _gate_dependency_source(self, relative: str) -> Path:
        return self.source_root / relative

    def _detach_gate_dependencies(self, worktree: Path) -> None:
        for relative in ("apps/desktop/.electron-runtime", "apps/desktop/.runtime-python"):
            if self._gate_dependency_source(relative).is_dir():
                self._remove_gate_dependency_target(worktree / relative)

    @staticmethod
    def _remove_gate_dependency_target(target: Path) -> None:
        if not target.exists() and not target.is_symlink():
            return
        is_junction = getattr(os.path, "isjunction", lambda _value: False)(target)
        if os.name == "nt" and not is_junction:
            try:
                is_junction = bool(target.lstat().st_file_attributes & 0x400)
            except (AttributeError, OSError):
                is_junction = False
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
                "user.name=GalaxySSI Evolution",
                "-c",
                "user.email=galaxyssi@hotmail.com",
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

    def _managed_worktree_path(self, raw_path: str | Path) -> Path:
        raw = str(raw_path or "").strip()
        if not raw:
            raise EvolutionError(
                "worktree_unsafe",
                "Evolution worktree path is missing.",
            )
        try:
            worktree = Path(raw).expanduser().resolve()
            managed_root = self.store.worktrees_root.resolve()
            source_root = self.source_root.resolve()
        except (OSError, RuntimeError) as exc:
            raise EvolutionError(
                "worktree_unsafe",
                f"Evolution worktree path cannot be resolved safely: {exc}",
            ) from exc
        if (
            worktree == managed_root
            or not _inside(worktree, managed_root)
            or _overlaps(worktree, source_root)
        ):
            raise EvolutionError(
                "worktree_unsafe",
                "Evolution worktree must be a child of managed storage and separate from the active checkout.",
            )
        return worktree

    def _validated_cleanup_target(self, attempt: EvolutionAttempt) -> Path:
        worktree = self._managed_worktree_path(attempt.worktree)
        if not EVOLUTION_BRANCH_PATTERN.fullmatch(attempt.branch):
            raise EvolutionError(
                "worktree_cleanup_refused",
                "Evolution cleanup refused an unexpected branch name.",
            )
        suffix = f"-a{attempt.number}"
        task_id = attempt.branch[len("evolution/") : -len(suffix)]
        expected = self._managed_worktree_path(
            self.store.worktrees_root / task_id / f"attempt-{attempt.number}"
        )
        if worktree != expected:
            raise EvolutionError(
                "worktree_cleanup_refused",
                "Evolution cleanup target does not match its task and attempt identity.",
            )
        return worktree

    def _validate_worktree_identity(
        self,
        worktree: Path,
        *,
        branch: str,
        expected_commit: str | None,
    ) -> None:
        managed_worktree = self._managed_worktree_path(worktree)
        if not managed_worktree.is_dir():
            raise EvolutionError(
                "worktree_identity_invalid",
                "Evolution candidate worktree is missing.",
            )
        top_level = Path(
            self._git_text(("rev-parse", "--show-toplevel"), cwd=managed_worktree)
        ).resolve()
        if top_level != managed_worktree:
            raise EvolutionError(
                "worktree_identity_invalid",
                "Evolution candidate does not resolve to its managed worktree root.",
            )
        source_common = self._git_common_directory(self.source_root)
        candidate_common = self._git_common_directory(managed_worktree)
        if source_common != candidate_common:
            raise EvolutionError(
                "worktree_identity_invalid",
                "Evolution candidate belongs to a different Git repository.",
            )
        current_branch = self._git_text(
            ("branch", "--show-current"),
            cwd=managed_worktree,
        )
        if not branch or current_branch != branch:
            raise EvolutionError(
                "worktree_identity_invalid",
                "Evolution candidate branch does not match the managed attempt.",
            )
        if expected_commit is not None:
            current_commit = self._git_text(("rev-parse", "HEAD"), cwd=managed_worktree)
            if (
                not expected_commit
                or not secrets.compare_digest(
                    current_commit.casefold(),
                    expected_commit.casefold(),
                )
            ):
                raise EvolutionError(
                    "worktree_identity_invalid",
                    "Evolution candidate is not pinned to the expected source commit.",
                )

    def _git_common_directory(self, cwd: Path) -> Path:
        raw = self._git_text(("rev-parse", "--git-common-dir"), cwd=cwd)
        common = Path(raw)
        if not common.is_absolute():
            common = cwd / common
        return common.resolve()

    def _active_checkout_fingerprint(self) -> str:
        digest = hashlib.sha256()
        for arguments in (
            ("rev-parse", "HEAD"),
            ("branch", "--show-current"),
            ("diff", "--binary", "--no-ext-diff", "HEAD", "--"),
        ):
            completed = self.runner.run(
                ("git", *arguments),
                self.source_root,
                timeout_seconds=120,
            )
            if completed.returncode != 0:
                raise EvolutionError(
                    "active_checkout_check_failed",
                    "Could not verify that the active checkout remained unchanged.",
                )
            digest.update("\0".join(arguments).encode("utf-8"))
            digest.update(b"\0")
            digest.update(completed.stdout.encode("utf-8", errors="replace"))
            digest.update(b"\0")
        untracked = self.runner.run(
            ("git", "ls-files", "--others", "--exclude-standard", "-z"),
            self.source_root,
            timeout_seconds=120,
        )
        if untracked.returncode != 0:
            raise EvolutionError(
                "active_checkout_check_failed",
                "Could not inspect untracked files in the active checkout.",
            )
        for relative in sorted(value for value in untracked.stdout.split("\0") if value):
            path = self.source_root / relative
            digest.update(relative.encode("utf-8", errors="replace"))
            digest.update(b"\0")
            try:
                if path.is_symlink():
                    digest.update(os.readlink(path).encode("utf-8", errors="replace"))
                elif path.is_file():
                    with path.open("rb") as stream:
                        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                            digest.update(chunk)
                else:
                    digest.update(b"<missing-or-unsupported>")
            except OSError as exc:
                raise EvolutionError(
                    "active_checkout_check_failed",
                    f"Could not inspect active checkout path {relative}: {exc}",
                ) from exc
            digest.update(b"\0")
        return digest.hexdigest()

    def _assert_active_checkout_unchanged(self, expected_fingerprint: str) -> None:
        current_fingerprint = self._active_checkout_fingerprint()
        if not secrets.compare_digest(expected_fingerprint, current_fingerprint):
            raise EvolutionError(
                "active_checkout_changed",
                "The implementation Agent changed the active checkout. The candidate was blocked without reverting user files.",
            )

    def _cleanup_failed_attempt(
        self,
        task: EvolutionTask,
        attempt: EvolutionAttempt,
    ) -> bool:
        try:
            self._remove_worktree(attempt, delete_branch=True)
            return True
        except EvolutionError as exc:
            task.status = "blocked"
            task.last_error_code = exc.code
            task.last_error = str(exc)[:4_000]
            self.store.save(task)
            self._emit(task, "cleanup_refused", attempt=attempt.number)
            return False

    def _remove_worktree(self, attempt: EvolutionAttempt, *, delete_branch: bool) -> None:
        worktree = self._validated_cleanup_target(attempt)
        removed = self.runner.run(
            ("git", "worktree", "remove", "--force", str(worktree)),
            self.source_root,
            timeout_seconds=120,
        )
        if worktree.exists():
            try:
                shutil.rmtree(worktree)
            except OSError as exc:
                raise EvolutionError(
                    "worktree_cleanup_failed",
                    f"Evolution candidate directory could not be removed: {exc}",
                ) from exc
        pruned = self.runner.run(
            ("git", "worktree", "prune", "--expire", "now"),
            self.source_root,
            timeout_seconds=60,
        )
        if pruned.returncode != 0:
            raise EvolutionError(
                "worktree_cleanup_failed",
                f"Git worktree metadata cleanup failed: {pruned.stdout[-2_000:]}",
            )
        if worktree.exists() or worktree in self._registered_worktrees():
            detail = removed.stdout[-2_000:] if removed.returncode != 0 else ""
            raise EvolutionError(
                "worktree_cleanup_failed",
                f"Evolution candidate worktree remains registered after rollback. {detail}".strip(),
            )
        if delete_branch and attempt.branch:
            deleted = self.runner.run(
                ("git", "branch", "-D", "--", attempt.branch),
                self.source_root,
                timeout_seconds=60,
            )
            if deleted.returncode != 0 and self._local_branch_exists(attempt.branch):
                raise EvolutionError(
                    "worktree_cleanup_failed",
                    f"Evolution candidate branch could not be removed: {deleted.stdout[-2_000:]}",
                )
            if self._local_branch_exists(attempt.branch):
                raise EvolutionError(
                    "worktree_cleanup_failed",
                    "Evolution candidate branch remains after rollback.",
                )

    def _registered_worktrees(self) -> set[Path]:
        completed = self.runner.run(
            ("git", "worktree", "list", "--porcelain"),
            self.source_root,
            timeout_seconds=60,
        )
        if completed.returncode != 0:
            raise EvolutionError(
                "worktree_cleanup_failed",
                f"Could not verify Git worktree rollback: {completed.stdout[-2_000:]}",
            )
        return {
            Path(line[9:].strip()).resolve()
            for line in completed.stdout.splitlines()
            if line.startswith("worktree ") and line[9:].strip()
        }

    def _local_branch_exists(self, branch: str) -> bool:
        completed = self.runner.run(
            ("git", "show-ref", "--verify", "--quiet", f"refs/heads/{branch}"),
            self.source_root,
            timeout_seconds=30,
        )
        if completed.returncode not in {0, 1}:
            raise EvolutionError(
                "worktree_cleanup_failed",
                f"Could not verify candidate branch rollback: {completed.stdout[-2_000:]}",
            )
        return completed.returncode == 0

    def _validate_repository(self) -> None:
        if not self.source_root.is_dir():
            raise EvolutionError("source_root_missing", "GalaxySSI source checkout does not exist.")
        completed = self.runner.run(("git", "rev-parse", "--is-inside-work-tree"), self.source_root)
        if completed.returncode != 0 or completed.stdout.strip() != "true":
            raise EvolutionError("source_root_invalid", "GalaxySSI source root is not a Git checkout.")
        if _overlaps(self.store.worktrees_root, self.source_root):
            raise EvolutionError(
                "state_root_unsafe",
                "Evolution worktree storage and the active checkout must not overlap.",
            )

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
            {
                "id": gate.id,
                "status": gate.status,
                "exit_code": gate.exit_code,
                "evidence_sha256": gate.evidence_sha256,
                "evidence_manifest_sha256": gate.evidence_manifest_sha256,
            }
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
    def _pull_request_title(task: EvolutionTask) -> str:
        summary = " ".join(task.problem.split())
        return f"[Self-Evolution] {summary[:96]}"

    @staticmethod
    def _pull_request_body(task: EvolutionTask, attempt: EvolutionAttempt) -> str:
        acceptance = "\n".join(f"- {value}" for value in task.acceptance)
        gates = "\n".join(
            (
                f"- `{gate.id}`: {gate.status} ({gate.duration_millis} ms), "
                f"evidence `{(gate.evidence_manifest_sha256 or gate.evidence_sha256)[:16]}...`"
            )
            for gate in attempt.gates
        )
        return (
            "## Self-Evolution Provenance\n\n"
            "- Type: `self-evolution`\n"
            f"- Task ID: `{task.task_id}`\n"
            f"- Base commit: `{task.base_commit}`\n"
            f"- Implementer: `{task.agent_id}`\n"
            f"- Attempt: `{attempt.number}` of `{task.max_attempts}`\n\n"
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

    def _reject_publish(self, task: EvolutionTask, code: str, message: str) -> None:
        task.last_error_code = code
        task.last_error = message[:4_000]
        self.store.save(task)
        self._emit(task, "publish_rejected", reason=code)
        raise EvolutionError(code, message)

    def _emit(self, task: EvolutionTask, event: str, **metadata: Any) -> None:
        payload = {
            "type": "evolution_task_event",
            "event": event,
            "task": task.public(),
            "_client_route_id": task.client_route_id,
            "metadata": metadata,
            "timestamp_millis": _now_millis(),
        }
        self.event_sink(payload)
        with self._lock:
            listeners = list(self._listeners.values())
        for listener in listeners:
            try:
                listener(dict(payload))
            except Exception:
                continue


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
You are repairing GalaxySSI inside a disposable Git worktree.

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
