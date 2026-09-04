"""V2 manager that extends the repository's existing worktree/compile/retry/PR loop."""
from __future__ import annotations

import os
import re
import sys
import threading
from pathlib import Path
from typing import Any, Iterable

from . import legacy
from .agent_adapters import default_evolution_patch_agent
from .audit import AuditLedger
from .campaigns import CampaignManager
from .common import read_json
from .github_client import GitHubClient
from .issues import IssueSignalScanner
from .models import EvolutionProposal, TaskMetadata
from .policy import EvolutionPolicy
from .provenance import ProvenanceWriter
from .research import TechnologyRadar
from .review import CandidateReviewer
from .roadmap import RoadmapPlanner
from .storage import EvolutionV2Store


class EvolutionManager(legacy.EvolutionManager):
    """Backward-compatible V1 manager plus policy, research, review and provenance."""

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        configured_dependencies = str(
            os.environ.get("GALAXYSSI_EVOLUTION_DEPENDENCY_ROOT") or ""
        ).strip()
        self.dependency_root = self._discover_dependency_root(configured_dependencies)
        self.v2_store = EvolutionV2Store(Path(self.store.root) / "v2")
        self.policy = EvolutionPolicy(self.source_root)
        loaded_gates = read_json(
            self.source_root / "config" / "evolution-gates.json",
            {},
        )
        self.gate_config = loaded_gates if isinstance(loaded_gates, dict) else {}
        self.audit = AuditLedger(self.v2_store.root / "audit" / "events.jsonl")
        self.github = GitHubClient(self.source_root)
        self.radar = TechnologyRadar(self.source_root, self.v2_store, self.github)
        self.roadmaps = RoadmapPlanner(self.v2_store)
        self.issue_scanner = IssueSignalScanner(self.v2_store)
        self.reviewer = CandidateReviewer(self.policy)
        self.provenance = ProvenanceWriter(self.v2_store.paths["provenance"])
        self.campaigns = CampaignManager(
            self.v2_store,
            task_factory=self._campaign_task_factory,
            task_getter=self.require,
            task_starter=self.start,
        )

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
        origin: str = "manual",
        objective: str = "repair",
        research_run_ids: Iterable[str] = (),
        roadmap_item_ids: Iterable[str] = (),
        issue_signal_ids: Iterable[str] = (),
        campaign_id: str = "",
    ):
        scope_rows = list(scope)
        decision = self.policy.decide(scope_rows, str(risk_level or "medium").casefold())
        if not decision.allowed:
            raise legacy.EvolutionError("policy_denied", " ".join(decision.reasons))
        task = super().create(
            problem=problem,
            scope=scope_rows,
            acceptance=acceptance,
            reproduction_steps=reproduction_steps,
            risk_level=decision.effective_risk,
            max_attempts=max_attempts,
            agent_id=agent_id,
            client_route_id=client_route_id,
            task_id=task_id,
        )
        if self.patch_agent is default_evolution_patch_agent:
            # Desktop V2 pins a freshly fetched remote main only when execution starts.
            task.base_commit = ""
            self.store.save(task)
        metadata = TaskMetadata(
            task_id=task.task_id,
            origin=str(origin or "manual")[:120],
            objective=str(objective or "repair")[:120],
            policy=decision.public(),
            research_run_ids=[str(value)[:128] for value in research_run_ids][:20],
            roadmap_item_ids=[str(value)[:128] for value in roadmap_item_ids][:50],
            issue_signal_ids=[str(value)[:128] for value in issue_signal_ids][:50],
            campaign_id=str(campaign_id or "")[:128],
        )
        self.v2_store.save_task_metadata(metadata)
        self.audit.append(
            "task_created",
            task_id=task.task_id,
            payload={"problem": task.problem, "scope": task.scope, "policy": decision.public(), "origin": origin},
        )
        return task

    def create_from_proposal(
        self,
        proposal: EvolutionProposal,
        *,
        campaign_id: str = "",
        agent_id: str = "auto",
        max_attempts: int = 5,
        start: bool = False,
    ):
        task = self.create(
            problem=proposal.problem,
            scope=proposal.scope,
            acceptance=proposal.acceptance,
            reproduction_steps=proposal.reproduction_steps,
            risk_level=proposal.risk_level,
            max_attempts=max_attempts,
            agent_id=agent_id,
            origin=proposal.origin,
            objective=proposal.objective,
            research_run_ids=proposal.research_run_ids,
            roadmap_item_ids=proposal.roadmap_item_ids,
            issue_signal_ids=proposal.issue_signal_ids,
            campaign_id=campaign_id,
        )
        proposal.task_id = task.task_id
        proposal.status = "materialized"
        self.v2_store.save_proposal(proposal)
        return self.start(task.task_id) if start else task

    def start(self, task_id: str):
        self.audit.append("task_start_requested", task_id=task_id)
        return super().start(task_id)

    def cancel(self, task_id: str):
        self.audit.append("task_cancel_requested", task_id=task_id)
        return super().cancel(task_id)

    def discard(self, task_id: str):
        self.audit.append("task_rollback_requested", task_id=task_id)
        task = super().discard(task_id)
        self.audit.append("task_rolled_back", task_id=task_id)
        return task

    def publish(self, task_id: str, approval_hash: str, *, base_branch: str = "main"):
        task = self.require(task_id)
        publish_policy = self.policy.config.get("publish") or {}
        if task.risk_level == "critical" and not bool(publish_policy.get("allow_critical_pr", True)):
            raise legacy.EvolutionError("critical_publish_blocked", "Policy forbids publishing critical candidates.")
        self.audit.append(
            "candidate_publish_requested",
            task_id=task_id,
            payload={"base_branch": base_branch, "approval_hash": approval_hash},
        )
        published = super().publish(task_id, approval_hash, base_branch=base_branch)
        metadata = self.v2_store.get_task_metadata(task_id)
        if metadata is not None and published.pull_request_url:
            try:
                metadata.ci = self.github.pull_request_checks(published.pull_request_url)
            except Exception as exc:
                metadata.ci = {"passed": False, "pending": 1, "error": str(exc)[:1_000]}
            self.v2_store.save_task_metadata(metadata)
        self.audit.append(
            "candidate_published",
            task_id=task_id,
            payload={"pull_request_url": published.pull_request_url, "candidate_commit": published.candidate_commit},
        )
        return published

    def _before_publish(
        self,
        task: legacy.EvolutionTask,
        worktree: Path,
        base_branch: str,
    ) -> None:
        del task, worktree, base_branch
        if not self.github.authenticated():
            raise legacy.EvolutionError(
                "github_auth_missing",
                "Desktop GitHub CLI is not authenticated. Run `gh auth login` on Desktop; the App must not store a write token.",
            )

    def _gate_commands(self, changed_files: Iterable[str]) -> list[legacy.GateCommand]:
        changed = list(changed_files)
        base = super()._gate_commands(changed)
        if not self._embedded_android_runtime_available():
            base = [
                legacy.GateCommand(
                    command.id,
                    (
                        *command.argv,
                        "-Pgalaxyssi.requireEmbeddedRuntime=false",
                    ),
                    cwd=command.cwd,
                    timeout_seconds=command.timeout_seconds,
                )
                if command.id == "android-unit-build"
                else command
                for command in base
            ]
        guard_script = str(
            (
                self.source_root
                / "apps/desktop/core/galaxyssi-link/backend/evolution_v2/gate_cli.py"
            ).resolve()
        )
        policy_config = str(self.policy.config_path.resolve())
        guard = legacy.GateCommand(
            "evolution-v2-policy-guard",
            (
                sys.executable,
                guard_script,
                "guard",
                "--repo-root", ".",
                "--config", policy_config,
            ),
            timeout_seconds=300,
        )
        commands = [base[0], guard, *base[1:]] if base else [guard]
        desktop_changed = any(value.startswith("apps/desktop/") or value.startswith("core/") for value in changed)
        android_changed = any(value.startswith("apps/android/") or value.startswith("core/") for value in changed)
        if (
            desktop_changed
            and self.policy.quality("desktop_runtime_smoke", True)
            and self._gate_setting("desktop", "isolated_backend_health", True)
        ):
            commands.append(legacy.GateCommand(
                "desktop-isolated-runtime",
                (
                    sys.executable,
                    guard_script,
                    "desktop-runtime",
                    "--backend-dir", "core/galaxyssi-link/backend",
                    "--timeout", "75",
                    "--reload-cycles", "2",
                ),
                cwd="apps/desktop",
                timeout_seconds=120,
            ))
        if android_changed:
            commands.append(legacy.GateCommand(
                "android-device-install-restore",
                (
                    sys.executable,
                    guard_script,
                    "android-device",
                    "--candidate", "apps/android/app/build/outputs/apk/debug/app-debug.apk",
                    "--snapshot-root", str(self.v2_store.paths["snapshots"] / "android"),
                    "--package", "com.galaxyssi.chat",
                ),
                timeout_seconds=900,
            ))
        return commands

    def _attach_gate_dependencies(self, worktree: Path) -> None:
        super()._attach_gate_dependencies(worktree)
        if not self._embedded_android_runtime_available():
            return
        source = self._gate_dependency_source("build/runtime")
        target = Path(worktree) / "build" / "runtime"
        self._remove_gate_dependency_target(target)
        target.parent.mkdir(parents=True, exist_ok=True)
        try:
            if os.name == "nt":
                linked = self.runner.run(
                    ("cmd.exe", "/d", "/c", "mklink", "/J", str(target), str(source)),
                    Path(worktree),
                    timeout_seconds=30,
                )
                if linked.returncode != 0:
                    raise legacy.EvolutionError(
                        "gate_dependency_failed",
                        linked.stdout[-2_000:],
                    )
            else:
                target.symlink_to(source, target_is_directory=True)
        except OSError as exc:
            raise legacy.EvolutionError(
                "gate_dependency_failed",
                f"Could not attach the trusted Android runtime bundle: {exc}",
            ) from exc

    def _detach_gate_dependencies(self, worktree: Path) -> None:
        super()._detach_gate_dependencies(worktree)
        if self._embedded_android_runtime_available():
            self._remove_gate_dependency_target(Path(worktree) / "build" / "runtime")

    def _gate_dependency_source(self, relative: str) -> Path:
        root = getattr(self, "dependency_root", None) or self.source_root
        return root / relative

    def _discover_dependency_root(self, configured: str = "") -> Path:
        if configured:
            return Path(configured).expanduser().resolve()
        candidates: list[Path] = [self._standard_dependency_root(), self.source_root]
        common = self.runner.run(
            ("git", "rev-parse", "--git-common-dir"),
            self.source_root,
            timeout_seconds=30,
        )
        if common.returncode == 0 and common.stdout.strip():
            common_path = Path(common.stdout.strip())
            if not common_path.is_absolute():
                common_path = self.source_root / common_path
            common_path = common_path.resolve()
            if common_path.name.casefold() == ".git":
                candidates.append(common_path.parent)
        worktrees = self.runner.run(
            ("git", "worktree", "list", "--porcelain"),
            self.source_root,
            timeout_seconds=30,
        )
        if worktrees.returncode == 0:
            candidates.extend(
                Path(line[9:]).resolve()
                for line in worktrees.stdout.splitlines()
                if line.startswith("worktree ") and line[9:].strip()
            )
        unique: list[Path] = []
        for candidate in candidates:
            resolved = candidate.resolve()
            if resolved not in unique:
                unique.append(resolved)
        return max(unique, key=self._dependency_score, default=self.source_root)

    @staticmethod
    def _standard_dependency_root() -> Path:
        root = Path.home() / "GalaxySSI_Workspace" / "GalaxySSI"
        root.mkdir(parents=True, exist_ok=True)
        return root.resolve()

    @staticmethod
    def _dependency_score(root: Path) -> int:
        markers = (
            root / "apps/desktop/.electron-runtime/node_modules/electron/dist",
            root / "apps/desktop/.runtime-python/venv",
            root / "build/runtime/android-jni-libs/galaxyssi-qemu-bundle.json",
            root / "build/runtime/android-assets/runtime/qemu/bundle.json",
        )
        return sum(path.exists() for path in markers)

    def _require_gate_dependencies(self, task) -> None:
        desktop_changed = any(
            value == "apps/desktop"
            or value.startswith("apps/desktop/")
            or value == "core"
            or value.startswith("core/")
            for value in task.scope
        )
        if not desktop_changed or not self._gate_setting("desktop", "package_windows", True):
            return
        electron_dist = self._gate_dependency_source(
            "apps/desktop/.electron-runtime/node_modules/electron/dist"
        )
        if electron_dist.is_dir():
            return
        raise legacy.EvolutionError(
            "gate_dependency_missing",
            "Desktop candidate validation needs the trusted Electron runtime, but it was not "
            f"found under {self.dependency_root}. Install the Desktop runtime in a registered "
            "GalaxySSI Git worktree or set GALAXYSSI_EVOLUTION_DEPENDENCY_ROOT to that checkout. "
            "No Agent attempt was consumed.",
        )

    def _gate_setting(self, section: str, key: str, default: bool) -> bool:
        values = self.gate_config.get(section)
        if not isinstance(values, dict):
            return default
        return bool(values.get(key, default))

    def _embedded_android_runtime_available(self) -> bool:
        runtime = self._gate_dependency_source("build/runtime")
        return (
            (runtime / "android-jni-libs" / "galaxyssi-qemu-bundle.json").is_file()
            and (runtime / "android-assets" / "runtime" / "qemu" / "bundle.json").is_file()
        )

    def _prepare_task_execution(self, task) -> None:
        if self.patch_agent is not default_evolution_patch_agent:
            return
        self._pin_source_commit(task)
        self._require_gate_dependencies(task)
        # Availability is checked before attempt one so no disposable worktree is consumed.
        self._select_implementation_agent(task)

    @staticmethod
    def _gate_failure_error(gate: legacy.EvolutionGate) -> legacy.EvolutionError:
        summary = str(gate.summary or "")
        dependency_failure = gate.id == "desktop-package" and any(
            marker in summary.casefold()
            for marker in (
                "electron runtime not found",
                "galaxyssi link sidecar runtime not found",
            )
        )
        if dependency_failure:
            return legacy.EvolutionError(
                "gate_dependency_missing",
                f"Trusted build dependency was unavailable during {gate.id}: {summary}",
            )
        return legacy.EvolutionManager._gate_failure_error(gate)

    def _pin_source_commit(self, task) -> str:
        metadata = self.v2_store.get_task_metadata(task.task_id)
        pinned = str(metadata.source_commit if metadata is not None else "").strip().casefold()
        if not pinned and task.attempts:
            pinned = str(task.base_commit or "").strip().casefold()
        if pinned:
            if not re.fullmatch(r"[0-9a-f]{40}", pinned):
                raise legacy.EvolutionError("source_pin_invalid", "Pinned evolution source commit is invalid.")
        else:
            fetched = self.runner.run(
                ("git", "fetch", "--no-tags", "origin", "main"),
                self.source_root,
                timeout_seconds=180,
            )
            if fetched.returncode != 0:
                raise legacy.EvolutionError("source_fetch_failed", fetched.stdout[-2_000:])
            resolved = self.runner.run(
                ("git", "rev-parse", "--verify", "origin/main^{commit}"),
                self.source_root,
                timeout_seconds=30,
            )
            pinned = resolved.stdout.strip().casefold() if resolved.returncode == 0 else ""
            if not re.fullmatch(r"[0-9a-f]{40}", pinned):
                raise legacy.EvolutionError(
                    "source_pin_invalid",
                    "Freshly fetched origin/main did not resolve to a 40-character commit.",
                )
        task.base_commit = pinned
        self.store.save(task)
        if metadata is not None and metadata.source_commit != pinned:
            metadata.source_commit = pinned
            self.v2_store.save_task_metadata(metadata)
        return pinned

    def _select_implementation_agent(self, task) -> str:
        if self.patch_agent is not default_evolution_patch_agent:
            return task.agent_id
        from agent_gateway import select_evolution_agent

        excluded = {
            attempt.agent_id
            for attempt in task.attempts
            if attempt.agent_id and attempt.failure_code == "implementation_channel_failed"
        }
        try:
            return select_evolution_agent(task.agent_id, excluded_agent_ids=excluded)
        except RuntimeError as exc:
            raise legacy.EvolutionError("agent_unavailable", str(exc)[:2_000]) from exc

    def _commit_candidate(self, task, attempt) -> str:
        candidate_commit = super()._commit_candidate(task, attempt)
        static = self.reviewer.static_review(
            Path(attempt.worktree), task.base_commit, candidate_commit, task.risk_level
        )
        review_payload: dict[str, Any] = {"static": static.public()}
        if static.verdict != "pass":
            self._save_review(task.task_id, review_payload)
            raise legacy.EvolutionError(
                "candidate_review_failed",
                "Independent static review failed: " + "; ".join(static.findings[:20]),
            )
        if self.policy.quality("agent_review", False):
            try:
                from agent_gateway import ask_evolution_agent

                agent_result = self.reviewer.agent_review(
                    Path(attempt.worktree),
                    base_commit=task.base_commit,
                    candidate_commit=candidate_commit,
                    risk_level=task.risk_level,
                    agent_id=attempt.agent_id or task.agent_id,
                    invoke=lambda agent_id, text, review_task_id, worktree: ask_evolution_agent(
                        agent_id,
                        text,
                        task_id=review_task_id,
                        working_directory=worktree,
                    ),
                    task_id=task.task_id,
                )
                review_payload["agent"] = agent_result.public()
                if agent_result.verdict != "pass" and self.reviewer.fail_closed(task.risk_level):
                    self._save_review(task.task_id, review_payload)
                    raise legacy.EvolutionError(
                        "agent_review_failed",
                        "Independent Agent review failed: " + "; ".join(agent_result.findings[:20]),
                    )
            except legacy.EvolutionError:
                raise
            except Exception as exc:
                review_payload["agent"] = {"verdict": "unavailable", "error": str(exc)[:2_000]}
                if self.reviewer.fail_closed(task.risk_level):
                    self._save_review(task.task_id, review_payload)
                    raise legacy.EvolutionError("agent_review_unavailable", str(exc)[:2_000]) from exc
        self._save_review(task.task_id, review_payload)
        return candidate_commit

    def _emit(self, task, event: str, **metadata: Any) -> None:
        super()._emit(task, event, **metadata)
        self.audit.append(event, task_id=task.task_id, payload=metadata)
        if event == "candidate_ready" and task.attempts:
            attempt = task.attempts[-1]
            try:
                path = self.provenance.write(
                    task=task,
                    attempt=attempt,
                    candidate_commit=task.candidate_commit,
                    source_root=self.source_root,
                )
                task_metadata = self.v2_store.get_task_metadata(task.task_id)
                if task_metadata is not None:
                    task_metadata.provenance_path = str(path)
                    self.v2_store.save_task_metadata(task_metadata)
            except Exception as exc:
                self.audit.append(
                    "provenance_write_failed",
                    task_id=task.task_id,
                    payload={"error": str(exc)[:2_000]},
                )

    def recover_interrupted(self, *, resume: bool = True) -> list[str]:
        recovered: list[str] = []
        for task in self.store.list(limit=500):
            if task.status == "publishing":
                task.status = "waiting_approval"
                task.last_error_code = "publish_interrupted"
                task.last_error = "Desktop restarted while publishing. Recheck GitHub and approve publish again."
                self.store.save(task)
                recovered.append(task.task_id)
                continue
            if task.status not in {"preparing", "running", "validating"}:
                continue
            if task.attempts:
                if not self._cleanup_failed_attempt(task, task.attempts[-1]):
                    recovered.append(task.task_id)
                    continue
            task.last_error_code = "desktop_restart"
            task.last_error = "Desktop restarted during an isolated attempt; the attempt was rolled back."
            task.status = "proposed" if len(task.attempts) < task.max_attempts else "failed"
            self.store.save(task)
            recovered.append(task.task_id)
            if resume and task.status == "proposed":
                super().start(task.task_id)
        return recovered

    def task_metadata(self, task_id: str) -> dict[str, Any]:
        metadata = self.v2_store.get_task_metadata(task_id)
        return metadata.public() if metadata is not None else {}

    def _save_review(self, task_id: str, payload: dict[str, Any]) -> None:
        metadata = self.v2_store.get_task_metadata(task_id)
        if metadata is not None:
            metadata.review = payload
            self.v2_store.save_task_metadata(metadata)

    def _campaign_task_factory(self, proposal: EvolutionProposal, campaign_id: str):
        return self.create_from_proposal(proposal, campaign_id=campaign_id, start=False)


_manager: EvolutionManager | None = None
_manager_lock = threading.Lock()


def evolution_manager(*, patch_agent=None, event_sink=None) -> EvolutionManager:
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
