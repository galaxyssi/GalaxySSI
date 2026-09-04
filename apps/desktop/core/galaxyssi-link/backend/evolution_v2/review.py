"""Static and optional Agent-based independent candidate review."""
from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Callable

from .common import redact_text
from .models import ReviewResult
from .policy import EvolutionPolicy, RISK_ORDER
from .runner import SafeRunner


class CandidateReviewer:
    def __init__(self, policy: EvolutionPolicy, runner: SafeRunner | None = None) -> None:
        self.policy = policy
        self.runner = runner or SafeRunner()

    def static_review(self, worktree: Path, base_commit: str, candidate_commit: str, risk_level: str) -> ReviewResult:
        findings: list[str] = []
        recommendations: list[str] = []
        changed = self._lines(worktree, ("git", "diff", "--name-only", f"{base_commit}..{candidate_commit}"))
        decision = self.policy.validate_changed_files(changed)
        if not decision.allowed:
            findings.extend(decision.reasons)
        code_files = [path for path in changed if _is_code(path) and not _is_test(path)]
        test_files = [path for path in changed if _is_test(path)]
        if code_files and not test_files and self.policy.quality("require_tests_for_code", True):
            findings.append("Production code changed without a focused test file in the candidate diff.")
        dependency_files = set(self.policy.config.get("dependency_files") or [])
        if dependency_files.intersection(changed):
            recommendations.append("Review dependency lockfile, license and supply-chain provenance before merge.")
        diff = self._text(worktree, ("git", "diff", "--unified=1", f"{base_commit}..{candidate_commit}"))
        if re.search(r"(?i)\b(TODO|FIXME|HACK)\b", diff):
            recommendations.append("Candidate introduced TODO/FIXME/HACK markers; confirm they are intentional.")
        if re.search(r"(?i)(verify\s*=\s*false|rejectUnauthorized\s*:\s*false|check_hostname\s*=\s*False)", diff):
            findings.append("Candidate appears to disable transport security verification.")
        verdict = "fail" if findings else "pass"
        return ReviewResult(
            verdict=verdict,
            risk_level=risk_level,
            findings=findings,
            recommendations=recommendations,
            reviewer="static-v2",
            raw_summary=f"Reviewed {len(changed)} changed files; {len(code_files)} production code files; {len(test_files)} test files.",
        )

    def agent_review(
        self,
        worktree: Path,
        *,
        base_commit: str,
        candidate_commit: str,
        risk_level: str,
        agent_id: str,
        invoke: Callable[[str, str, str, Path], str],
        task_id: str,
    ) -> ReviewResult:
        prompt = f"""
You are the independent security and regression reviewer for GalaxySSI.
Review commit {candidate_commit} against base {base_commit} in the current worktree.
Do not edit any file, do not run network commands, do not push, and do not create commits.
Focus on correctness, route isolation, authentication, prompt injection, rollback, Android lifecycle,
Desktop process management, data loss, secret leakage, and missing tests.
Return exactly one JSON object:
{{"verdict":"pass|fail","findings":["..."],"recommendations":["..."]}}
Risk level: {risk_level}
""".strip()
        before = self._text(worktree, ("git", "status", "--porcelain=v1", "--untracked-files=all"))
        summary = invoke(agent_id, prompt, f"{task_id}-review", worktree)
        after = self._text(worktree, ("git", "status", "--porcelain=v1", "--untracked-files=all"))
        if after != before:
            self.runner.run(("git", "reset", "--hard", candidate_commit), worktree, timeout_seconds=60)
            self.runner.run(("git", "clean", "-fd"), worktree, timeout_seconds=60)
        payload = _extract_json(summary)
        verdict = str(payload.get("verdict") or "fail").casefold()
        if verdict not in {"pass", "fail"}:
            verdict = "fail"
        findings = [str(value)[:1_000] for value in payload.get("findings") or []][:30]
        recommendations = [str(value)[:1_000] for value in payload.get("recommendations") or []][:30]
        return ReviewResult(
            verdict=verdict,
            risk_level=risk_level,
            findings=findings,
            recommendations=recommendations,
            reviewer=f"agent:{agent_id}",
            raw_summary=redact_text(summary, maximum=8_000),
        )

    def fail_closed(self, risk_level: str) -> bool:
        threshold = str(self.policy.quality("agent_review_fail_closed_from", "high"))
        return RISK_ORDER.get(risk_level, 1) >= RISK_ORDER.get(threshold, 2)

    def _lines(self, cwd: Path, argv: tuple[str, ...]) -> list[str]:
        return [line.strip().replace("\\", "/") for line in self._text(cwd, argv).splitlines() if line.strip()]

    def _text(self, cwd: Path, argv: tuple[str, ...]) -> str:
        result = self.runner.run(argv, cwd, timeout_seconds=120)
        return result.stdout if result.ok else ""


def _is_code(path: str) -> bool:
    return Path(path).suffix.casefold() in {".py", ".js", ".mjs", ".cjs", ".ts", ".tsx", ".kt", ".kts", ".java", ".cpp", ".c", ".h"}


def _is_test(path: str) -> bool:
    lowered = path.casefold()
    return any(token in lowered for token in ("/test", "_test.", "test_", ".spec.", ".test.", "/androidtest/"))


def _extract_json(text: str) -> dict:
    raw = str(text or "").strip()
    try:
        value = json.loads(raw)
        return value if isinstance(value, dict) else {}
    except json.JSONDecodeError:
        pass
    match = re.search(r"\{.*\}", raw, flags=re.DOTALL)
    if not match:
        return {}
    try:
        value = json.loads(match.group(0))
        return value if isinstance(value, dict) else {}
    except json.JSONDecodeError:
        return {}
