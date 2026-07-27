"""Immutable static guard applied after the coding Agent stops editing."""
from __future__ import annotations

import json
import re
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any

from .policy import EvolutionPolicy
from .runner import SafeRunner


@dataclass
class GuardResult:
    passed: bool
    changed_files: list[str]
    total_diff_lines: int
    binary_files: list[str]
    findings: list[str]
    warnings: list[str]

    def public(self) -> dict[str, Any]:
        return asdict(self)


class StaticEvolutionGuard:
    def __init__(self, repo_root: Path, policy: EvolutionPolicy | None = None, runner: SafeRunner | None = None) -> None:
        self.repo_root = Path(repo_root).resolve()
        self.policy = policy or EvolutionPolicy(self.repo_root)
        self.runner = runner or SafeRunner()

    def inspect(self) -> GuardResult:
        changed = self._changed_files()
        findings: list[str] = []
        warnings: list[str] = []
        decision = self.policy.validate_changed_files(changed)
        if not decision.allowed:
            findings.extend(decision.reasons)
        max_files = self.policy.limit("max_changed_files", 96)
        if len(changed) > max_files:
            findings.append(f"Candidate changes {len(changed)} files; policy limit is {max_files}.")
        total_lines, binary = self._numstat()
        max_lines = self.policy.limit("max_total_diff_lines", 12_000)
        if total_lines > max_lines:
            findings.append(f"Candidate diff has {total_lines} changed lines; policy limit is {max_lines}.")
        max_binaries = self.policy.limit("max_binary_files", 0)
        if len(binary) > max_binaries:
            findings.append(f"Candidate adds or changes binary files: {', '.join(binary[:20])}")
        maximum_file_bytes = self.policy.limit("max_new_file_bytes", 2_097_152)
        for path in changed:
            candidate = self.repo_root / path
            try:
                if candidate.is_file() and candidate.stat().st_size > maximum_file_bytes:
                    findings.append(f"Changed file exceeds {maximum_file_bytes} bytes: {path}")
            except OSError:
                continue
        added_lines = self._added_lines()
        for pattern in self.policy.config.get("secret_patterns") or []:
            if str(pattern) and str(pattern) in added_lines:
                findings.append(f"Potential secret material matched forbidden marker: {pattern}")
        if re.search(r"(?i)(authorization|api[_-]?key|token|password|secret)\s*[:=]\s*['\"][^'\"]{8,}", added_lines):
            findings.append("Potential hard-coded credential was added to the diff.")
        code = [path for path in changed if _is_production_code(path)]
        tests = [path for path in changed if _is_test(path)]
        if code and not tests and self.policy.quality("require_tests_for_code", True):
            findings.append("Production code changed without a focused test file.")
        dependency_files = set(self.policy.config.get("dependency_files") or [])
        if dependency_files.intersection(changed):
            warnings.append("Dependency/build files changed; human supply-chain review is required.")
        return GuardResult(
            passed=not findings,
            changed_files=changed,
            total_diff_lines=total_lines,
            binary_files=binary,
            findings=findings,
            warnings=warnings,
        )

    def _changed_files(self) -> list[str]:
        result = self.runner.run(("git", "status", "--porcelain=v1", "-z", "--untracked-files=all"), self.repo_root, timeout_seconds=60)
        if not result.ok:
            raise RuntimeError(result.stdout[-2_000:])
        rows: list[str] = []
        chunks = result.stdout.split("\x00")
        index = 0
        while index < len(chunks):
            row = chunks[index]
            index += 1
            if len(row) < 4:
                continue
            path = row[3:].replace("\\", "/")
            if row[:1] in {"R", "C"} and index < len(chunks):
                path = chunks[index].replace("\\", "/")
                index += 1
            if path and path not in rows:
                rows.append(path)
        return sorted(rows)

    def _numstat(self) -> tuple[int, list[str]]:
        result = self.runner.run(("git", "diff", "--numstat", "--no-renames", "HEAD"), self.repo_root, timeout_seconds=60)
        total = 0
        binary: list[str] = []
        for line in result.stdout.splitlines():
            columns = line.split("\t")
            if len(columns) < 3:
                continue
            if columns[0] == "-" or columns[1] == "-":
                binary.append(columns[2])
                continue
            try:
                total += int(columns[0]) + int(columns[1])
            except ValueError:
                continue
        for path in self._changed_files():
            candidate = self.repo_root / path
            if candidate.is_file() and path not in {row.split("\t")[-1] for row in result.stdout.splitlines()}:
                try:
                    total += len(candidate.read_text(encoding="utf-8").splitlines())
                except (OSError, UnicodeDecodeError):
                    binary.append(path)
        return total, sorted(set(binary))

    def _added_lines(self) -> str:
        result = self.runner.run(("git", "diff", "--unified=0", "--no-ext-diff", "HEAD"), self.repo_root, timeout_seconds=120)
        rows = []
        for line in result.stdout.splitlines():
            if line.startswith("+") and not line.startswith("+++"):
                rows.append(line[1:])
        for path in self._changed_files():
            candidate = self.repo_root / path
            if candidate.is_file() and not self.runner.run(("git", "ls-files", "--error-unmatch", path), self.repo_root, timeout_seconds=20).ok:
                try:
                    rows.append(candidate.read_text(encoding="utf-8"))
                except (OSError, UnicodeDecodeError):
                    continue
        return "\n".join(rows)[:5_000_000]


def _is_production_code(path: str) -> bool:
    lowered = path.casefold()
    if _is_test(path):
        return False
    if any(lowered.startswith(prefix) for prefix in ("docs/", ".github/")):
        return False
    return Path(path).suffix.casefold() in {".py", ".js", ".mjs", ".cjs", ".ts", ".tsx", ".kt", ".kts", ".java", ".cpp", ".c", ".h"}


def _is_test(path: str) -> bool:
    lowered = path.casefold()
    return any(token in lowered for token in ("/test", "test_", "_test.", ".test.", ".spec.", "/androidtest/"))
