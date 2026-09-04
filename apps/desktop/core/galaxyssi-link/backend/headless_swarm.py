"""Isolated Git workspaces for durable headless Agent swarms."""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import threading
import uuid
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Iterable, Iterator, Mapping, Sequence


PROTOCOL = "galaxyssi.headless-swarm.v1"
WORKFLOW_KINDS = {
    "pr_review",
    "test_repair",
    "documentation_update",
}
MUTATING_WORKFLOWS = {"test_repair", "documentation_update"}
MAX_DIFF_CHARS = 64_000
_SAFE_REF = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/@{}^~:+-]{0,199}$")
_SAFE_COMPONENT = re.compile(r"[^A-Za-z0-9._-]+")
_PROTECTED_PATHS = {
    ".git",
    ".github/workflows",
    ".openai",
    "node_modules",
    "dist",
    "build",
    "runtime-data",
}
_CHECK_EXECUTABLES = {
    "cargo",
    "cmake",
    "dotnet",
    "go",
    "gradle",
    "gradle.bat",
    "gradlew",
    "gradlew.bat",
    "java",
    "make",
    "mvn",
    "mvn.cmd",
    "mvnw",
    "mvnw.cmd",
    "ninja",
    "node",
    "npm",
    "npm.cmd",
    "npx",
    "npx.cmd",
    "pnpm",
    "pnpm.cmd",
    "py",
    "pytest",
    "python",
    "python.exe",
    "uv",
    "uv.exe",
    "yarn",
    "yarn.cmd",
}
_INLINE_EXECUTION_FLAGS = {
    "node": {"-e", "--eval", "-p", "--print"},
    "py": {"-c"},
    "python": {"-c"},
    "python.exe": {"-c"},
}
_REPOSITORY_LOCKS: dict[str, threading.RLock] = {}
_REPOSITORY_LOCKS_GUARD = threading.Lock()


class HeadlessSwarmError(RuntimeError):
    def __init__(self, code: str, message: str, *, retryable: bool = False) -> None:
        super().__init__(message)
        self.code = code
        self.retryable = retryable


@dataclass(frozen=True)
class HeadlessCheck:
    argv: tuple[str, ...]
    cwd: str = ""
    timeout_seconds: int = 600

    @classmethod
    def parse(cls, raw: Any) -> "HeadlessCheck":
        value = dict(raw) if isinstance(raw, Mapping) else {"argv": raw}
        argv_raw = value.get("argv")
        if not isinstance(argv_raw, (list, tuple)) or not argv_raw:
            raise HeadlessSwarmError(
                "headless_check_invalid",
                "Each validation check requires a non-empty argv array",
            )
        if len(argv_raw) > 32:
            raise HeadlessSwarmError(
                "headless_check_invalid",
                "A validation check has too many arguments",
            )
        argv = tuple(str(item) for item in argv_raw)
        if any(not item or len(item) > 1_024 or "\x00" in item for item in argv):
            raise HeadlessSwarmError(
                "headless_check_invalid",
                "A validation check contains an invalid argument",
            )
        executable = Path(argv[0]).name.casefold()
        if executable not in _CHECK_EXECUTABLES:
            raise HeadlessSwarmError(
                "headless_check_not_allowed",
                f"Validation executable is not allowed: {Path(argv[0]).name}",
            )
        forbidden_flags = _INLINE_EXECUTION_FLAGS.get(executable, set())
        if any(value.casefold() in forbidden_flags for value in argv[1:]):
            raise HeadlessSwarmError(
                "headless_check_not_allowed",
                f"Inline code is not allowed in validation checks: {Path(argv[0]).name}",
            )
        cwd = _relative_path(value.get("cwd") or "", "check.cwd", allow_empty=True)
        try:
            timeout_seconds = int(value.get("timeout_seconds") or 600)
        except (TypeError, ValueError) as exc:
            raise HeadlessSwarmError(
                "headless_check_invalid",
                "Validation timeout must be an integer",
            ) from exc
        if not 1 <= timeout_seconds <= 3_600:
            raise HeadlessSwarmError(
                "headless_check_invalid",
                "Validation timeout must be within 1..3600 seconds",
            )
        return cls(argv=argv, cwd=cwd, timeout_seconds=timeout_seconds)


@dataclass(frozen=True)
class HeadlessSwarmSpec:
    workflow: str
    prompt: str
    repository_root: Path
    base_ref: str
    review_ref: str
    scope: tuple[str, ...]
    acceptance: tuple[str, ...]
    checks: tuple[HeadlessCheck, ...]
    max_changed_files: int

    @classmethod
    def parse(
        cls,
        workflow: str,
        prompt: str,
        arguments: Mapping[str, Any] | None,
    ) -> "HeadlessSwarmSpec":
        clean_workflow = str(workflow or "").strip().casefold()
        if clean_workflow not in WORKFLOW_KINDS:
            raise HeadlessSwarmError(
                "headless_workflow_invalid",
                f"Unsupported headless swarm workflow: {clean_workflow}",
            )
        clean_prompt = str(prompt or "").strip()
        if not clean_prompt or len(clean_prompt) > 65_536:
            raise HeadlessSwarmError(
                "headless_prompt_invalid",
                "Headless swarm instructions are required",
            )
        value = dict(arguments or {})
        repository_text = str(value.get("repository_root") or "").strip()
        if not repository_text or "\x00" in repository_text:
            raise HeadlessSwarmError(
                "headless_repository_missing",
                "Headless swarm actions require repository_root",
            )
        repository_root = Path(repository_text).expanduser().resolve()
        base_ref = _git_ref(value.get("base_ref") or "HEAD", "base_ref")
        review_ref = _git_ref(
            value.get("review_ref") or "HEAD",
            "review_ref",
        )
        scope_raw = value.get("scope") or []
        if not isinstance(scope_raw, (list, tuple)):
            raise HeadlessSwarmError(
                "headless_scope_invalid",
                "Headless swarm scope must be an array",
            )
        scope = tuple(
            _relative_path(item, "scope")
            for item in scope_raw
            if str(item or "").strip()
        )
        if clean_workflow in MUTATING_WORKFLOWS and not scope:
            raise HeadlessSwarmError(
                "headless_scope_missing",
                "Mutating headless swarm workflows require an explicit repository scope",
            )
        acceptance_raw = value.get("acceptance") or []
        if not isinstance(acceptance_raw, (list, tuple)):
            raise HeadlessSwarmError(
                "headless_acceptance_invalid",
                "Headless swarm acceptance criteria must be an array",
            )
        acceptance = tuple(
            str(item).strip()[:1_000]
            for item in acceptance_raw
            if str(item or "").strip()
        )[:40]
        checks_raw = value.get("checks") or []
        if not isinstance(checks_raw, (list, tuple)) or len(checks_raw) > 12:
            raise HeadlessSwarmError(
                "headless_check_invalid",
                "Headless swarm checks must contain no more than 12 entries",
            )
        checks = tuple(HeadlessCheck.parse(item) for item in checks_raw)
        if clean_workflow == "test_repair" and not checks:
            raise HeadlessSwarmError(
                "headless_checks_missing",
                "Test repair requires at least one independent validation check",
            )
        try:
            max_changed_files = int(value.get("max_changed_files") or 200)
        except (TypeError, ValueError) as exc:
            raise HeadlessSwarmError(
                "headless_limit_invalid",
                "max_changed_files must be an integer",
            ) from exc
        if not 1 <= max_changed_files <= 500:
            raise HeadlessSwarmError(
                "headless_limit_invalid",
                "max_changed_files must be within 1..500",
            )
        return cls(
            workflow=clean_workflow,
            prompt=clean_prompt,
            repository_root=repository_root,
            base_ref=base_ref,
            review_ref=review_ref,
            scope=scope,
            acceptance=acceptance,
            checks=checks,
            max_changed_files=max_changed_files,
        )

    @property
    def mutating(self) -> bool:
        return self.workflow in MUTATING_WORKFLOWS


class HeadlessSwarmWorkspace:
    """Own one candidate worktree and any temporary read-only observers."""

    def __init__(
        self,
        spec: HeadlessSwarmSpec,
        run_id: str,
        state_root: Path,
        *,
        cancelled: Callable[[], bool] | None = None,
    ) -> None:
        self.spec = spec
        self.run_id = _component(run_id, "run")
        self.state_root = Path(state_root).expanduser().resolve()
        self.cancelled = cancelled or (lambda: False)
        self.repository_root = spec.repository_root
        self.run_root = (self.state_root / self.run_id).resolve()
        self.worktree = self.run_root / "candidate"
        self.base_commit = ""
        self.review_commit = ""
        self.branch = ""
        self.candidate_commit = ""
        self._prepared = False
        self._retain_branch = False

    def __enter__(self) -> "HeadlessSwarmWorkspace":
        self.prepare()
        return self

    def __exit__(self, _kind, _value, _traceback) -> None:
        self.close()

    def prepare(self) -> None:
        self._check_cancelled()
        self._validate_repository()
        self.state_root.mkdir(parents=True, exist_ok=True)
        if _inside(self.state_root, self.repository_root):
            raise HeadlessSwarmError(
                "headless_state_root_unsafe",
                "Headless swarm worktrees must be outside the source checkout",
            )
        self.base_commit = self._git_text(
            ("rev-parse", "--verify", f"{self.spec.base_ref}^{{commit}}"),
            self.repository_root,
        )
        self.review_commit = self._git_text(
            ("rev-parse", "--verify", f"{self.spec.review_ref}^{{commit}}"),
            self.repository_root,
        )
        if self.run_root.exists():
            self._git(
                ("worktree", "remove", "--force", str(self.worktree)),
                self.repository_root,
                timeout_seconds=120,
            )
            shutil.rmtree(self.run_root, ignore_errors=True)
            self._git(
                ("worktree", "prune"),
                self.repository_root,
                timeout_seconds=60,
            )
        self.run_root.mkdir(parents=True, exist_ok=True)
        arguments: tuple[str, ...]
        if self.spec.mutating:
            self.branch = (
                f"galaxyssi/headless/{self.spec.workflow}-"
                f"{self.run_id[:24]}-{uuid.uuid4().hex[:8]}"
            )
            arguments = (
                "worktree",
                "add",
                "-b",
                self.branch,
                str(self.worktree),
                self.base_commit,
            )
        else:
            arguments = (
                "worktree",
                "add",
                "--detach",
                str(self.worktree),
                self.review_commit,
            )
        completed = self._git(arguments, self.repository_root, timeout_seconds=120)
        if completed.returncode != 0:
            raise HeadlessSwarmError(
                "headless_worktree_failed",
                _tail(completed.stdout, 2_000) or "Could not create headless worktree",
                retryable=True,
            )
        self._prepared = True

    @contextmanager
    def observer(self, label: str, commit: str | None = None) -> Iterator[Path]:
        self._check_cancelled()
        identifier = f"{_component(label, 'observer')}-{uuid.uuid4().hex[:8]}"
        target = (self.run_root / "observers" / identifier).resolve()
        target.parent.mkdir(parents=True, exist_ok=True)
        completed = self._git(
            (
                "worktree",
                "add",
                "--detach",
                str(target),
                commit or self.base_commit,
            ),
            self.repository_root,
            timeout_seconds=120,
        )
        if completed.returncode != 0:
            raise HeadlessSwarmError(
                "headless_observer_failed",
                _tail(completed.stdout, 2_000) or "Could not create observer worktree",
                retryable=True,
            )
        try:
            yield target
        finally:
            self._remove_worktree(target)

    def review_context(self) -> dict[str, Any]:
        changed = self._git_lines(
            (
                "diff",
                "--name-only",
                f"{self.base_commit}..{self.review_commit}",
            ),
            self.worktree,
        )
        diff = self._git_text(
            (
                "diff",
                "--no-ext-diff",
                "--unified=2",
                f"{self.base_commit}..{self.review_commit}",
            ),
            self.worktree,
            maximum=MAX_DIFF_CHARS,
        )
        return {
            "base_commit": self.base_commit,
            "review_commit": self.review_commit,
            "changed_files": changed[: self.spec.max_changed_files],
            "diff": diff,
            "truncated": len(diff) >= MAX_DIFF_CHARS,
        }

    def changed_files(self) -> list[str]:
        return [
            path
            for status, path in self._status_entries(include_ignored=False)
            if status != "!!"
        ]

    def _status_entries(
        self,
        *,
        include_ignored: bool,
    ) -> list[tuple[str, str]]:
        arguments = [
            "status",
            "--porcelain=v1",
            "-z",
            "--untracked-files=all",
        ]
        if include_ignored:
            arguments.append("--ignored=matching")
        completed = self._git(
            tuple(arguments),
            self.worktree,
            timeout_seconds=60,
        )
        if completed.returncode != 0:
            raise HeadlessSwarmError(
                "headless_status_failed",
                _tail(completed.stdout, 2_000),
                retryable=True,
            )
        values: list[tuple[str, str]] = []
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
            entry = (row[:2], path)
            if path and entry not in values:
                values.append(entry)
        return sorted(values, key=lambda item: (item[1], item[0]))

    def assert_read_only(self) -> None:
        entries = self._status_entries(include_ignored=True)
        if not entries:
            return
        self._git(("reset", "--hard", self.review_commit), self.worktree)
        self._git(("clean", "-fdx"), self.worktree)
        raise HeadlessSwarmError(
            "headless_read_only_violation",
            "A review Agent attempted to modify the read-only review workspace",
        )

    def validate_candidate(self) -> tuple[list[str], list[dict[str, Any]]]:
        self._check_cancelled()
        self._assert_no_ignored_artifacts()
        changed = self.changed_files()
        if not changed:
            raise HeadlessSwarmError(
                "headless_no_changes",
                "The headless swarm did not produce a candidate change",
            )
        if len(changed) > self.spec.max_changed_files:
            raise HeadlessSwarmError(
                "headless_change_limit",
                f"Candidate changed {len(changed)} files; limit is {self.spec.max_changed_files}",
            )
        violations = [
            path
            for path in changed
            if not any(
                path == root or path.startswith(f"{root.rstrip('/')}/")
                for root in self.spec.scope
            )
        ]
        if violations:
            raise HeadlessSwarmError(
                "headless_scope_violation",
                "Candidate changed files outside the declared scope: "
                + ", ".join(violations[:20]),
            )
        if self.spec.workflow == "documentation_update":
            invalid_docs = [path for path in changed if not _documentation_path(path)]
            if invalid_docs:
                raise HeadlessSwarmError(
                    "headless_documentation_scope",
                    "Documentation workflow changed non-documentation files: "
                    + ", ".join(invalid_docs[:20]),
                )
        checks = [self._run_diff_check()]
        checks.extend(self._run_check(value) for value in self.spec.checks)
        self._clean_ignored_artifacts()
        return changed, checks

    def _assert_no_ignored_artifacts(self) -> None:
        entries = self._status_entries(include_ignored=True)
        ignored = [path for status, path in entries if status == "!!"]
        if ignored:
            raise HeadlessSwarmError(
                "headless_ignored_artifact",
                "Candidate created ignored artifacts: " + ", ".join(ignored[:20]),
            )

    def _clean_ignored_artifacts(self) -> None:
        ignored = [
            path
            for status, path in self._status_entries(include_ignored=True)
            if status == "!!"
        ]
        if not ignored:
            return
        cleaned = self._git(("clean", "-fdX"), self.worktree, timeout_seconds=120)
        if cleaned.returncode != 0:
            raise HeadlessSwarmError(
                "headless_artifact_cleanup_failed",
                _tail(cleaned.stdout, 2_000),
                retryable=True,
            )
        self._assert_no_ignored_artifacts()

    def commit_candidate(self, changed_files: Sequence[str]) -> str:
        self._check_cancelled()
        staged = self._git(("add", "--all"), self.worktree, timeout_seconds=60)
        if staged.returncode != 0:
            raise HeadlessSwarmError(
                "headless_stage_failed",
                _tail(staged.stdout, 2_000),
                retryable=True,
            )
        message = (
            f"Prepare headless {self.spec.workflow.replace('_', ' ')} candidate "
            f"{self.run_id[:24]}"
        )
        committed = self._git(
            (
                "-c",
                "user.name=GalaxySSI Headless Swarm",
                "-c",
                "user.email=galaxyssi@hotmail.com",
                "commit",
                "-m",
                message,
            ),
            self.worktree,
            timeout_seconds=120,
        )
        if committed.returncode != 0:
            raise HeadlessSwarmError(
                "headless_commit_failed",
                _tail(committed.stdout, 2_000),
                retryable=True,
            )
        self.candidate_commit = self._git_text(
            ("rev-parse", "HEAD"),
            self.worktree,
        )
        if not changed_files or self.changed_files():
            raise HeadlessSwarmError(
                "headless_candidate_dirty",
                "Candidate commit did not produce a clean worktree",
            )
        self._retain_branch = True
        return self.candidate_commit

    def candidate_context(self) -> dict[str, Any]:
        target = self.candidate_commit or "HEAD"
        changed = self._git_lines(
            ("diff", "--name-only", f"{self.base_commit}..{target}"),
            self.worktree,
        )
        diff = self._git_text(
            (
                "diff",
                "--no-ext-diff",
                "--unified=2",
                f"{self.base_commit}..{target}",
            ),
            self.worktree,
            maximum=MAX_DIFF_CHARS,
        )
        return {
            "base_commit": self.base_commit,
            "candidate_commit": self.candidate_commit,
            "candidate_branch": self.branch,
            "changed_files": changed,
            "diff": diff,
            "truncated": len(diff) >= MAX_DIFF_CHARS,
        }

    def close(self) -> None:
        if self._prepared:
            self._remove_worktree(self.worktree)
            self._prepared = False
        if self.branch and not self._retain_branch:
            self._git(("branch", "-D", self.branch), self.repository_root)
        if self.run_root.exists():
            shutil.rmtree(self.run_root, ignore_errors=True)

    def _run_diff_check(self) -> dict[str, Any]:
        completed = self._git(("diff", "--check"), self.worktree, timeout_seconds=60)
        result = {
            "argv": ["git", "diff", "--check"],
            "cwd": "",
            "exit_code": completed.returncode,
            "output": _tail(completed.stdout, 4_000),
        }
        if completed.returncode != 0:
            raise HeadlessSwarmError(
                "headless_diff_check_failed",
                result["output"] or "git diff --check failed",
                retryable=True,
            )
        return result

    def _run_check(self, check: HeadlessCheck) -> dict[str, Any]:
        self._check_cancelled()
        cwd = (self.worktree / check.cwd).resolve()
        if not _inside(cwd, self.worktree) or not cwd.is_dir():
            raise HeadlessSwarmError(
                "headless_check_cwd_invalid",
                f"Validation directory is unavailable: {check.cwd or '.'}",
            )
        completed = _run(
            check.argv,
            cwd,
            timeout_seconds=check.timeout_seconds,
        )
        result = {
            "argv": list(check.argv),
            "cwd": check.cwd,
            "exit_code": completed.returncode,
            "output": _tail(completed.stdout, 4_000),
        }
        if completed.returncode != 0:
            raise HeadlessSwarmError(
                "headless_check_failed",
                (
                    f"Validation failed ({Path(check.argv[0]).name}): "
                    f"{result['output'] or f'exit {completed.returncode}'}"
                ),
                retryable=True,
            )
        return result

    def _validate_repository(self) -> None:
        if not self.repository_root.is_dir():
            raise HeadlessSwarmError(
                "headless_repository_missing",
                "Headless swarm repository does not exist",
            )
        completed = self._git(
            ("rev-parse", "--show-toplevel"),
            self.repository_root,
            timeout_seconds=60,
        )
        if completed.returncode != 0:
            raise HeadlessSwarmError(
                "headless_repository_invalid",
                "Headless swarm repository is not a Git checkout",
            )
        actual = Path(completed.stdout.strip()).resolve()
        if actual != self.repository_root:
            raise HeadlessSwarmError(
                "headless_repository_invalid",
                "repository_root must identify the Git checkout root",
            )

    def _remove_worktree(self, target: Path) -> None:
        self._git(
            ("worktree", "remove", "--force", str(target)),
            self.repository_root,
            timeout_seconds=120,
        )
        if target.exists():
            shutil.rmtree(target, ignore_errors=True)
        self._git(("worktree", "prune"), self.repository_root, timeout_seconds=60)

    def _git(
        self,
        arguments: Sequence[str],
        cwd: Path,
        *,
        timeout_seconds: int = 60,
    ) -> subprocess.CompletedProcess[str]:
        with _repository_lock(self.repository_root):
            return _run(
                ("git", *arguments),
                cwd,
                timeout_seconds=timeout_seconds,
            )

    def _git_text(
        self,
        arguments: Sequence[str],
        cwd: Path,
        *,
        maximum: int = 8_000,
    ) -> str:
        completed = self._git(arguments, cwd)
        if completed.returncode != 0:
            raise HeadlessSwarmError(
                "headless_git_failed",
                _tail(completed.stdout, 2_000),
                retryable=True,
            )
        return str(completed.stdout or "")[:maximum].strip()

    def _git_lines(self, arguments: Sequence[str], cwd: Path) -> list[str]:
        return [
            line.strip().replace("\\", "/")
            for line in self._git_text(arguments, cwd, maximum=MAX_DIFF_CHARS).splitlines()
            if line.strip()
        ]

    def _check_cancelled(self) -> None:
        if self.cancelled():
            raise HeadlessSwarmError(
                "headless_cancelled",
                "Headless swarm run was cancelled",
            )


def _run(
    argv: Sequence[str],
    cwd: Path,
    *,
    timeout_seconds: int,
) -> subprocess.CompletedProcess[str]:
    if not argv or any("\x00" in str(value) for value in argv):
        raise HeadlessSwarmError(
            "headless_command_invalid",
            "Headless swarm command is invalid",
        )
    environment = {
        **os.environ,
        "CI": "1",
        "GIT_TERMINAL_PROMPT": "0",
    }
    try:
        return subprocess.run(
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
    except subprocess.TimeoutExpired as exc:
        raise HeadlessSwarmError(
            "headless_command_timeout",
            f"Command timed out: {Path(str(argv[0])).name}",
            retryable=True,
        ) from exc
    except OSError as exc:
        raise HeadlessSwarmError(
            "headless_command_unavailable",
            f"Command could not start: {Path(str(argv[0])).name}",
        ) from exc


def _repository_lock(repository_root: Path) -> threading.RLock:
    key = os.path.normcase(str(repository_root.resolve()))
    with _REPOSITORY_LOCKS_GUARD:
        return _REPOSITORY_LOCKS.setdefault(key, threading.RLock())


def _git_ref(value: Any, name: str) -> str:
    text = str(value or "").strip()
    if not _SAFE_REF.fullmatch(text) or text.startswith("-") or ".." in text:
        raise HeadlessSwarmError(
            "headless_ref_invalid",
            f"{name} is not a safe Git reference",
        )
    return text


def _relative_path(value: Any, name: str, *, allow_empty: bool = False) -> str:
    text = str(value or "").strip().replace("\\", "/").strip("/")
    if not text and allow_empty:
        return ""
    candidate = Path(text)
    if (
        not text
        or candidate.is_absolute()
        or any(part in {"", ".", ".."} for part in candidate.parts)
    ):
        raise HeadlessSwarmError(
            "headless_path_invalid",
            f"{name} must be a safe repository-relative path",
        )
    lowered = text.casefold()
    if any(
        lowered == root or lowered.startswith(f"{root}/")
        for root in _PROTECTED_PATHS
    ):
        raise HeadlessSwarmError(
            "headless_path_protected",
            f"{name} targets a protected repository path",
        )
    return text


def _documentation_path(path: str) -> bool:
    normalized = str(path or "").replace("\\", "/").strip("/")
    lowered = normalized.casefold()
    first = lowered.split("/", 1)[0]
    if first in {"docs", "doc", "documentation"}:
        return True
    name = Path(lowered).name
    if name.startswith(("readme", "changelog", "contributing", "license", "notice")):
        return True
    return Path(lowered).suffix in {".md", ".mdx", ".rst", ".adoc"}


def _component(value: str, fallback: str) -> str:
    cleaned = _SAFE_COMPONENT.sub("-", str(value or "").strip()).strip(".-_")
    return cleaned[:64] or fallback


def _inside(path: Path, parent: Path) -> bool:
    try:
        path.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


def _tail(value: Any, maximum: int) -> str:
    text = str(value or "").strip()
    return text[-maximum:]
