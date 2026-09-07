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
        acceptance_infer = kwargs.pop("acceptance_infer", None)
        isolated_store = kwargs.get("store") is not None
        super().__init__(*args, **kwargs)
        from .task_owner import TaskOwners
        self.task_owners = TaskOwners(self.store.root / "task-owners")
        self._active_publications: set[str] = set()
        self._recovering_tasks: set[str] = set()
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
        from .candidate_acceptance import CandidateAcceptance
        self.acceptance_verifier = CandidateAcceptance(acceptance_infer)
        self.provenance = ProvenanceWriter(self.v2_store.paths["provenance"])
        from agent_run_kernel import AgentRunEventLedger
        from agent_run_storage import run_kernel_database_path
        from .ci_store import CiWatchStore
        ci_path = self.store.root / "ci-run-events.sqlite3" if isolated_store else run_kernel_database_path()
        self.ci_watches = CiWatchStore(AgentRunEventLedger(ci_path))
        self.ci_watch_index_needed = threading.Event()
        ledger_path = self.store.root / "campaign-run-events.sqlite3" if isolated_store else run_kernel_database_path()
        from .campaign_outcomes import published_outcome
        self.campaigns = CampaignManager(
            self.v2_store,
            task_factory=self._campaign_task_factory,
            task_getter=self.require,
            task_starter=self._start_campaign_task,
            task_ensurer=self._ensure_campaign_task,
            run_ledger=AgentRunEventLedger(ledger_path),
            published_outcome=lambda task: published_outcome(self, task),
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
        task_id: str = "",
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
            task_id=task_id,
        )
        proposal.task_id = task.task_id
        proposal.status = "materialized"
        self.v2_store.save_proposal(proposal)
        return self.start(task.task_id) if start else task

    def start(self, task_id: str):
        self.audit.append("task_start_requested", task_id=task_id)
        with self._lock:
            if task_id in self._recovering_tasks:
                raise legacy.EvolutionError("recovery_in_progress", "Task recovery is in progress")
            if task_id in self._active_publications:
                raise legacy.EvolutionError("publication_in_progress", "Task publication is in progress")
            running = self._threads.get(task_id)
            if running is not None and (running.is_alive() or getattr(running, "ident", None) is None):
                return self.require(task_id)
            self._claim_task_operation(task_id)
            try:
                return super().start(task_id)
            except Exception:
                thread = self._threads.get(task_id)
                if thread is None or not thread.is_alive():
                    self._threads.pop(task_id, None)
                    self.task_owners.release(task_id)
                raise

    def _claim_task_operation(self, task_id: str) -> None:
        if not self.task_owners.claim(task_id):
            raise legacy.EvolutionError("task_owned_elsewhere", "Another executor owns this task operation")
        try:
            self._verify_process_termination(task_id)
        except Exception:
            self.task_owners.release(task_id)
            raise

    def _process_journal(self, task_id: str) -> Path:
        from process_recovery_journal import task_journal
        return task_journal(self.store.root, task_id)

    def _verify_process_termination(self, task_id: str) -> None:
        from process_recovery_journal import assert_quiescent, ProcessTerminationPending
        try:
            assert_quiescent(self._process_journal(task_id))
        except ProcessTerminationPending as error:
            raise legacy.EvolutionError("process_termination_pending", str(error)) from error

    def _run_background(self, task_id: str, cancellation: threading.Event) -> None:
        try:
            from owned_process import owned_process_scope
            with owned_process_scope(self._process_journal(task_id)):
                self._run_task(task_id, cancellation)
        finally:
            with self._lock:
                self.task_owners.release(task_id)
                self._threads.pop(task_id, None)

    def run_sync(self, task_id: str):
        current = threading.current_thread()
        with self._lock:
            if (task_id in self._recovering_tasks or task_id in self._threads
                    or task_id in self._active_publications):
                raise legacy.EvolutionError("task_execution_active", "Task already has an execution owner")
            if self.require(task_id).status in legacy.CANDIDATE_STATUSES:
                raise legacy.EvolutionError("candidate_already_ready", "Evolution candidate is already ready")
            self._claim_task_operation(task_id)
            self._threads[task_id] = current
        try:
            from owned_process import owned_process_scope
            with owned_process_scope(self._process_journal(task_id)):
                return super().run_sync(task_id)
        finally:
            with self._lock:
                if self._threads.get(task_id) is current:
                    self.task_owners.release(task_id)
                    self._threads.pop(task_id, None)

    def cancel(self, task_id: str):
        self.audit.append("task_cancel_requested", task_id=task_id)
        with self._lock:
            if self.task_owners.locally_owned(task_id):
                return super().cancel(task_id)
            self._claim_task_operation(task_id)
            try:
                return super().cancel(task_id)
            finally:
                self.task_owners.release(task_id)

    def discard(self, task_id: str):
        with self._lock:
            if task_id in self._recovering_tasks:
                raise legacy.EvolutionError("recovery_in_progress", "Task recovery is in progress")
            if task_id in self._threads or task_id in self._active_publications:
                raise legacy.EvolutionError("task_execution_active", "Task execution or publication is still active")
            self._claim_task_operation(task_id)
            self._recovering_tasks.add(task_id)
        try:
            self.audit.append("task_rollback_requested", task_id=task_id)
            from owned_process import owned_process_scope
            with owned_process_scope(self._process_journal(task_id)):
                task = super().discard(task_id)
            self.audit.append("task_rolled_back", task_id=task_id)
            return task
        finally:
            with self._lock:
                self._recovering_tasks.discard(task_id)
                self.task_owners.release(task_id)

    def publish(self, task_id: str, approval_hash: str, *, base_branch: str = "main"):
        with self._lock:
            if (task_id in self._recovering_tasks or task_id in self._active_publications
                    or task_id in self._threads):
                raise legacy.EvolutionError("publication_in_progress", "Task recovery or publication is in progress")
            self._claim_task_operation(task_id)
            self._active_publications.add(task_id)
        try:
            from owned_process import owned_process_scope
            with owned_process_scope(self._process_journal(task_id)):
                return self._publish_owned(task_id, approval_hash, base_branch=base_branch)
        finally:
            with self._lock:
                self._active_publications.discard(task_id)
                self.task_owners.release(task_id)

    def _publish_owned(self, task_id: str, approval_hash: str, *, base_branch: str):
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
        if published.pull_request_url and (metadata is None or not metadata.ci_repair_target):
            try:
                self.ci_watches.register(task_id, published.pull_request_url)
            except Exception:
                self.ci_watch_index_needed.set()
                raise
        self.audit.append(
            "candidate_published",
            task_id=task_id,
            payload={"pull_request_url": published.pull_request_url, "candidate_commit": published.candidate_commit},
        )
        return published

    def ensure_ci_repair(self, repair: dict, snapshot: dict):
        from .ci_tasks import ensure_repair
        return ensure_repair(self, repair, snapshot)

    def start_ci_repair(self, task_id: str, config: dict):
        from .ci_tasks import start_repair
        return start_repair(self, task_id, config)

    def _publish_remote_candidate(self, task, attempt, worktree, base_branch: str) -> str:
        metadata = self.v2_store.get_task_metadata(task.task_id)
        if metadata is not None and metadata.ci_repair_target:
            from .ci_repair import publish_candidate
            return publish_candidate(self, task, worktree, metadata.ci_repair_target)
        from .publication import publish_candidate
        return publish_candidate(self, task, attempt, worktree, base_branch)

    def _before_publish(
        self,
        task: legacy.EvolutionTask,
        worktree: Path,
        base_branch: str,
    ) -> None:
        del base_branch
        try:
            self._require_candidate_acceptance(task, worktree, task.candidate_commit)
        except legacy.EvolutionError as error:
            from .candidate_revalidation import record_rejection
            record_rejection(self, task, error)
            raise
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
        if metadata is not None and metadata.ci_repair_target:
            from .ci_repair import prepare_source
            pinned = prepare_source(self, task, metadata.ci_repair_target)
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
        from .campaign_outcomes import verify_dependency_source
        verify_dependency_source(self, task, pinned)
        task.base_commit = pinned
        self.store.save(task)
        if metadata is not None and metadata.source_commit != pinned:
            metadata.source_commit = pinned
            self.v2_store.save_task_metadata(metadata)
        return pinned

    def _implementation_context(self, task) -> dict:
        metadata = self.v2_store.get_task_metadata(task.task_id)
        if metadata is None or not metadata.campaign_id:
            return {}
        from agent_task_dag import TaskDagError
        from agent_run_kernel import AgentRunIdentityConflict
        durable = self.campaigns.durable
        if durable is not None:
            try:
                context = durable.graph_store.task_context(durable.identity(metadata.campaign_id), task.task_id)
            except (TaskDagError, AgentRunIdentityConflict) as exc:
                raise legacy.EvolutionError("campaign_context_conflict", str(exc)) from exc
            if context is not None:
                node = context["node"]
                proposal = self.v2_store.get_proposal(node["action"]["proposal_id"])
                if proposal is None:
                    raise legacy.EvolutionError("campaign_context_unavailable", "The task's planned proposal is unavailable")
                return {"campaign_id": metadata.campaign_id, "campaign_objective": context["objective"],
                        "node_id": node["node_id"], "proposal_title": proposal.title}
        campaign = self.v2_store.get_campaign(metadata.campaign_id)
        if campaign is None:
            raise legacy.EvolutionError("campaign_context_unavailable", "The task's campaign goal is unavailable")
        nodes = [node for node in campaign.nodes if node.task_id == task.task_id]
        if len(nodes) != 1:
            raise legacy.EvolutionError("campaign_context_conflict", "The campaign does not uniquely own this task")
        proposal = self.v2_store.get_proposal(nodes[0].proposal_id)
        if proposal is None:
            raise legacy.EvolutionError("campaign_context_unavailable", "The task's planned proposal is unavailable")
        return {"campaign_id": campaign.campaign_id, "campaign_objective": campaign.objective,
                "node_id": nodes[0].node_id, "proposal_title": proposal.title}

    def _select_implementation_agent(self, task) -> str:
        if self.patch_agent is not default_evolution_patch_agent:
            return task.agent_id
        if task.agent_id in {"auto", "local-llm"}:
            from .local_planning import LocalPlannerUnavailable, local_plan_endpoint
            try:
                local_plan_endpoint()
            except LocalPlannerUnavailable as exc:
                raise legacy.EvolutionError("agent_unavailable", str(exc)) from exc
            return "local-llm"
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
        self._save_review(task.task_id, review_payload)
        review_payload["acceptance"] = self._require_candidate_acceptance(task, Path(attempt.worktree), candidate_commit)
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

    def _require_candidate_acceptance(self, task, worktree, candidate_commit, *, force=False):
        from .acceptance_evidence import collect_evidence
        evidence = collect_evidence(task, worktree, candidate_commit, self._implementation_context(task), self.runner)
        metadata = self.v2_store.get_task_metadata(task.task_id)
        reviews = dict(metadata.review) if metadata is not None and isinstance(metadata.review, dict) else {}
        try:
            result = self.acceptance_verifier.verify(evidence, None if force else reviews.get("acceptance"))
        except legacy.EvolutionError as exc:
            reviews["acceptance"] = {"verdict": "inconclusive", "error_code": exc.code,
                                     "candidate_commit": candidate_commit}
            self._save_review(task.task_id, reviews)
            raise
        reviews["acceptance"] = result
        self._save_review(task.task_id, reviews)
        if result["verdict"] != "pass":
            code = "acceptance_review_failed" if result["verdict"] == "fail" else "acceptance_review_inconclusive"
            raise legacy.EvolutionError(code, "Candidate does not satisfy the task: " + "; ".join(result["findings"])[:3500])
        return result

    def revalidate_candidate(self, task_id):
        from .candidate_revalidation import revalidate_candidate
        return revalidate_candidate(self, task_id)

    def _emit(self, task, event: str, **metadata: Any) -> None:
        if event == "local_tool_observed":
            self.audit.append(event, task_id=task.task_id, payload=metadata)
            try:
                super()._emit(task, event, **metadata)
            except Exception as exc:
                self.audit.append("local_tool_delivery_failed", task_id=task.task_id,
                                  payload={"error_type": type(exc).__name__})
            return
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
        from .recovery import recover_interrupted
        return recover_interrupted(self, resume=resume)

    def resume_recovered_tasks(self, config: dict | None = None) -> list[str]:
        from .recovery import resume_recovered_tasks
        if config is None:
            config = read_json(self.v2_store.paths["scheduler"] / "settings.json", {})
        return resume_recovered_tasks(self, config if isinstance(config, dict) else {})

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

    def _ensure_campaign_task(self, proposal: EvolutionProposal, campaign_id: str, task_id: str):
        with self._lock:
            existing = self.store.get(task_id)
            if existing is not None:
                metadata = self.v2_store.get_task_metadata(task_id)
                if metadata is not None and metadata.campaign_id != campaign_id:
                    raise legacy.EvolutionError("campaign_identity_conflict", "Task belongs to another campaign")
                if metadata is None:
                    self.v2_store.save_task_metadata(TaskMetadata(task_id=task_id, origin=proposal.origin,
                                                                  objective=proposal.objective, campaign_id=campaign_id))
                return existing
            return self.create_from_proposal(proposal, campaign_id=campaign_id, task_id=task_id, start=False)

    def active_worker_count(self) -> int:
        with self._lock:
            return sum(thread.is_alive() or getattr(thread, "ident", None) is None for thread in self._threads.values())

    def _start_campaign_task(self, task_id: str):
        settings = read_json(self.v2_store.paths["scheduler"] / "settings.json", {})
        settings = settings if isinstance(settings, dict) else {}
        from .scheduler import _normalized_config
        config = _normalized_config(settings)
        capacity = 1 if config["execution_mode"] == "serial" else config["max_parallel_evolutions"]
        with self._lock:
            if self.active_worker_count() >= capacity:
                return self.require(task_id)
            return self.start(task_id)


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
