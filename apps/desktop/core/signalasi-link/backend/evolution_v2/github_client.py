"""GitHub integration through the Desktop user's authenticated `gh` CLI."""
from __future__ import annotations

import json
import re
import time
from pathlib import Path
from typing import Any

from .common import redact, safe_identifier
from .runner import SafeRunner

_REPO_PATTERN = re.compile(r"(?:github\.com[:/])([^/\s]+/[^/\s]+?)(?:\.git)?$")


class GitHubClientError(RuntimeError):
    pass


class GitHubClient:
    def __init__(self, source_root: Path, runner: SafeRunner | None = None) -> None:
        self.source_root = Path(source_root).resolve()
        self.runner = runner or SafeRunner()

    def authenticated(self) -> bool:
        if not self.runner.which("gh"):
            return False
        return self.runner.run(
            ("gh", "auth", "status", "--hostname", "github.com"),
            self.source_root,
            timeout_seconds=30,
        ).ok

    def current_repository(self) -> str:
        result = self.runner.run(("git", "remote", "get-url", "origin"), self.source_root, timeout_seconds=30)
        if not result.ok:
            return ""
        match = _REPO_PATTERN.search(result.stdout.strip())
        return match.group(1).rstrip("/") if match else ""

    def repository(self, name_with_owner: str) -> dict[str, Any]:
        repository = _safe_repository(name_with_owner)
        return self._api((f"repos/{repository}",))

    def search_repositories(self, query: str, *, limit: int = 20) -> list[dict[str, Any]]:
        clean_query = str(query or "").strip()[:500]
        if not clean_query:
            return []
        payload = self._api((
            "-X", "GET", "search/repositories",
            "-f", f"q={clean_query}",
            "-f", "sort=updated",
            "-f", "order=desc",
            "-f", f"per_page={max(1, min(int(limit), 100))}",
        ))
        items = payload.get("items") if isinstance(payload, dict) else []
        return [item for item in items or [] if isinstance(item, dict)][:limit]

    def pull_request_checks(self, branch_or_url: str) -> dict[str, Any]:
        target = str(branch_or_url or "").strip()[:500]
        if not target:
            raise GitHubClientError("Pull request branch or URL is required")
        result = self.runner.run(
            (
                "gh", "pr", "checks", target,
                "--json", "name,state,bucket,link,startedAt,completedAt,workflow",
            ),
            self.source_root,
            timeout_seconds=120,
        )
        if result.returncode not in {0, 1, 8}:
            raise GitHubClientError(result.stdout[-2_000:] or "Could not read pull request checks")
        try:
            rows = json.loads(result.stdout or "[]")
        except json.JSONDecodeError as exc:
            raise GitHubClientError("GitHub CLI returned invalid check JSON") from exc
        rows = rows if isinstance(rows, list) else []
        failed = [row for row in rows if str(row.get("bucket") or "").casefold() in {"fail", "cancel"}]
        pending = [row for row in rows if str(row.get("bucket") or "").casefold() in {"pending", "skipping"}]
        return {
            "checks": redact(rows),
            "passed": bool(rows) and not failed and not pending,
            "failed": len(failed),
            "pending": len(pending),
        }

    def wait_for_checks(self, branch_or_url: str, *, timeout_seconds: int = 1800, poll_seconds: int = 20) -> dict[str, Any]:
        deadline = time.monotonic() + max(1, int(timeout_seconds))
        last: dict[str, Any] = {"checks": [], "passed": False, "failed": 0, "pending": 0}
        while time.monotonic() < deadline:
            last = self.pull_request_checks(branch_or_url)
            if last["passed"] or last["failed"]:
                return last
            time.sleep(max(2, int(poll_seconds)))
        return {**last, "timed_out": True}

    def _api(self, arguments: tuple[str, ...]) -> Any:
        if not self.runner.which("gh"):
            raise GitHubClientError("GitHub CLI is not installed")
        result = self.runner.run(("gh", "api", *arguments), self.source_root, timeout_seconds=120)
        if not result.ok:
            raise GitHubClientError(result.stdout[-2_000:] or "GitHub API request failed")
        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError as exc:
            raise GitHubClientError("GitHub API response was not JSON") from exc


def _safe_repository(value: str) -> str:
    text = str(value or "").strip().strip("/")
    parts = text.split("/")
    if len(parts) != 2:
        raise GitHubClientError("Repository must be owner/name")
    for index, part in enumerate(parts):
        safe_identifier(part, label="repository component")
    return text
