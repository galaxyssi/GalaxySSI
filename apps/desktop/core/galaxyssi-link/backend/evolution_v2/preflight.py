"""Environment readiness checks for Git, GitHub, Desktop, Android and optional signing."""
from __future__ import annotations

import os
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any

from .common import find_repo_root, now_millis
from .runner import SafeRunner


@dataclass
class PreflightCheck:
    check_id: str
    status: str
    summary: str
    required: bool = True
    details: dict[str, Any] | None = None

    def public(self) -> dict[str, Any]:
        return asdict(self)


class PreflightInspector:
    def __init__(self, source_root: Path | None = None, runner: SafeRunner | None = None) -> None:
        self.source_root = (Path(source_root) if source_root else find_repo_root()).resolve()
        self.runner = runner or SafeRunner()

    def inspect(self) -> dict[str, Any]:
        agents = self._implementation_agents()
        checks = [
            self._command("git", ("git", "--version"), required=True),
            self._git_checkout(),
            self._command("python", (os.environ.get("PYTHON", "python"), "--version"), required=True),
            self._command("node", ("node", "--version"), required=True),
            self._command("npm", ("npm", "--version"), required=True),
            self._command("java", ("java", "-version"), required=False),
            self._command("adb", ("adb", "version"), required=False),
            self._command("gh", ("gh", "--version"), required=True),
            self._gh_auth(),
            self._command("cosign", ("cosign", "version"), required=False),
            agents,
        ]
        blocking = [item.check_id for item in checks if item.required and item.status != "passed"]
        return {
            "schema": "galaxyssi.evolution-preflight.v2",
            "ready": not blocking,
            "blocking": blocking,
            "checks": [item.public() for item in checks],
            "source_root": str(self.source_root),
            "timestamp_millis": now_millis(),
        }

    def _implementation_agents(self) -> PreflightCheck:
        try:
            from agent_gateway import evolution_agent_candidates

            snapshot = evolution_agent_candidates("auto")
        except Exception as exc:
            return PreflightCheck(
                "implementation-agents",
                "failed",
                "Implementation Agent readiness could not be inspected.",
                True,
                {"agents": [], "selected_agent_id": "", "error": type(exc).__name__},
            )
        selected = str(snapshot.get("selected_agent_id") or "")
        agents = list(snapshot.get("agents") or [])
        return PreflightCheck(
            "implementation-agents",
            "passed" if selected else "missing",
            f"Selected implementation Agent: {selected}." if selected else "No healthy implementation Agent is available.",
            True,
            {"agents": agents, "selected_agent_id": selected},
        )

    def _command(self, check_id: str, argv: tuple[str, ...], *, required: bool) -> PreflightCheck:
        executable = argv[0]
        resolved = str(Path(executable).resolve()) if Path(executable).is_file() else self.runner.which(executable)
        if not resolved:
            return PreflightCheck(check_id, "missing", f"{executable} was not found on PATH.", required)
        try:
            result = self.runner.run((resolved, *argv[1:]), self.source_root, timeout_seconds=20)
        except Exception as exc:
            return PreflightCheck(check_id, "failed", str(exc)[:500], required)
        first = next((line.strip() for line in result.stdout.splitlines() if line.strip()), "")
        return PreflightCheck(
            check_id,
            "passed" if result.ok else "failed",
            first[:500] or f"Exited with {result.returncode}.",
            required,
        )

    def _git_checkout(self) -> PreflightCheck:
        try:
            inside = self.runner.run(("git", "rev-parse", "--is-inside-work-tree"), self.source_root, timeout_seconds=20)
            origin = self.runner.run(("git", "remote", "get-url", "origin"), self.source_root, timeout_seconds=20)
        except Exception as exc:
            return PreflightCheck("git-checkout", "failed", str(exc)[:500], True)
        ok = inside.ok and inside.stdout.strip() == "true" and origin.ok
        return PreflightCheck(
            "git-checkout",
            "passed" if ok else "failed",
            "Git checkout and origin are available." if ok else "Source root is not a usable Git checkout with origin.",
            True,
            {"origin": origin.stdout.strip()[:500] if origin.ok else ""},
        )

    def _gh_auth(self) -> PreflightCheck:
        if not self.runner.which("gh"):
            return PreflightCheck("github-auth", "missing", "GitHub CLI is not installed.", True)
        try:
            result = self.runner.run(("gh", "auth", "status", "--hostname", "github.com"), self.source_root, timeout_seconds=30)
        except Exception as exc:
            return PreflightCheck("github-auth", "failed", str(exc)[:500], True)
        summary = "GitHub CLI authentication is ready." if result.ok else "Run `gh auth login` on Desktop before publishing PRs."
        return PreflightCheck("github-auth", "passed" if result.ok else "failed", summary, True)
