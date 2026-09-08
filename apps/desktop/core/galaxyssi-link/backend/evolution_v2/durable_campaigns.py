"""Evolution adapter for the generic Run-ledger DAG; task creation is idempotent."""
from __future__ import annotations

import hashlib
import uuid
from typing import Callable

from agent_run_kernel import AgentRunRootIdentity
from agent_task_dag import TaskDagError, ready_nodes, reduce_graph
from agent_task_dag_store import DurableTaskDag
from .common import now_millis
from .models import CampaignNode, EvolutionCampaign
from .campaign_owner import campaign_operation, operation_owners
from .campaign_retry_admission import retry_admission, terminal_observation
from .replacement_context import persist_replacement_context, with_replacement_context


class DurableCampaigns:
    def __init__(self, graph_store: DurableTaskDag, proposal_store, *, ensure_task: Callable,
                 task_getter: Callable, task_starter: Callable, published_outcome: Callable | None = None):
        self.graph_store = graph_store
        self.proposal_store = proposal_store
        self.ensure_task = ensure_task
        self.task_getter = task_getter
        self.task_starter = task_starter
        self.published_outcome = published_outcome
        self.dispatch_admission = None
        self.owner = f"campaign-worker-{uuid.uuid4().hex}"
        self.operation_owners = operation_owners(proposal_store.root)

    @staticmethod
    def identity(campaign_id: str) -> AgentRunRootIdentity:
        return AgentRunRootIdentity("desktop-local", campaign_id, campaign_id, campaign_id, campaign_id)

    def _apply(self, campaign_id: str, operation: str, operation_id: str | None = None, **fields) -> dict:
        return self.graph_store.apply(self.identity(campaign_id), operation_id or uuid.uuid4().hex,
                                      {"operation": operation, **fields}, turn_id=campaign_id)

    def _specs(self, campaign_id: str, rows: list[dict]) -> list[dict]:
        specs = []
        for row in rows:
            key = row.get("node_id")
            proposal_id = row.get("proposal_id")
            if not isinstance(proposal_id, str) or self.proposal_store.get_proposal(proposal_id) is None:
                raise TaskDagError("Campaign proposal was not found")
            task_id = "evolve-dag-" + hashlib.sha256(f"{campaign_id}\0{key}".encode()).hexdigest()[:32]
            specs.append({"node_id": key, "depends_on": row.get("depends_on", []), "effect": "replayable",
                          "action": {"proposal_id": proposal_id, "task_id": task_id}})
        return specs

    def create(self, name: str, objective: str, rows: list[dict], *, auto_start: bool) -> EvolutionCampaign:
        campaign_id = f"campaign-{uuid.uuid4().hex[:20]}"
        graph = self._apply(campaign_id, "create", objective=objective or name, nodes=self._specs(campaign_id, rows),
                            context={"domain": "evolution_campaign", "name": name, "auto_start": auto_start,
                                     "created_at_millis": now_millis()})
        return self._public(campaign_id, graph)

    def get(self, campaign_id: str) -> EvolutionCampaign | None:
        graph = self.graph_store.load(self.identity(campaign_id))
        return self._public(campaign_id, graph) if graph else None

    @campaign_operation
    def revise(self, campaign_id: str, rows: list[dict], expected_revision: int, operation_id: str,
               supersede_ids: list[str] | None = None, evidence: str = "") -> EvolutionCampaign:
        replay = self.graph_store.operation_snapshot(self.identity(campaign_id), operation_id)
        previous = replay if replay is not None else self.graph_store.load(self.identity(campaign_id))
        specs, recovery = with_replacement_context(previous, self._specs(campaign_id, rows), supersede_ids or [],
                                                   evidence, operation_id, campaign_id)
        command = {"operation": "revise", "expected_revision": expected_revision, "nodes": specs,
                   "supersede_ids": supersede_ids or [], "evidence": evidence}
        if replay is None:
            reduce_graph(previous, command, run_id=campaign_id, operation_id=operation_id)
            persist_replacement_context(self.proposal_store, recovery)
        graph = self._apply(campaign_id, "revise", operation_id, expected_revision=expected_revision,
                            nodes=specs, supersede_ids=supersede_ids or [], evidence=evidence)
        return self._public(campaign_id, graph)

    @campaign_operation
    def control(self, campaign_id: str, operation: str, operation_id: str, **fields) -> EvolutionCampaign:
        if operation not in {"pause", "resume", "retry", "finish"}:
            raise TaskDagError("Unsupported campaign control operation")
        if operation == "finish":
            graph = self.graph_store.load(self.identity(campaign_id))
            if graph is not None and graph["status"] != "completed":
                for node in graph["nodes"].values():
                    task = self._observe(node) if node["attempt"] else None
                    if node["attempt"] and task is None:
                        raise TaskDagError("Completed task evidence is unavailable")
                    recorded_pr = node["result"].get("pull_request_url", "")
                    if recorded_pr and recorded_pr != getattr(task, "pull_request_url", ""):
                        raise TaskDagError("Published task identity changed after completion")
                    if task is not None and getattr(task, "pull_request_url", ""):
                        outcome = self.published_outcome(task) if self.published_outcome else {}
                        if outcome.get("stage") != "completed":
                            raise TaskDagError(outcome.get("error") or "Published outcome is not verified")
        return self._public(campaign_id, self._apply(campaign_id, operation, operation_id, **fields))

    @campaign_operation
    def tick(self, campaign_id: str, *, start_ready: bool = False) -> EvolutionCampaign:
        graph = self.graph_store.load(self.identity(campaign_id))
        if graph is None:
            raise TaskDagError("Campaign was not found")
        if graph["status"] in {"completed", "cancelled"}:
            return self._public(campaign_id, graph)
        for key, node in list(graph["nodes"].items()):
            if node["status"] == "failed" and node["result"].get("pull_request_url") and graph["status"] == "active":
                task = self._observe(node)
                if (task is not None and getattr(task, "status", "") == "published"
                        and task.pull_request_url == node["result"]["pull_request_url"] and self.published_outcome):
                    outcome = self.published_outcome(task)
                    if outcome.get("stage") == "completed":
                        # Reobserve existing publication only; never restart implementation or push again.
                        self._apply(campaign_id, "retry", node_id=key, evidence="Published integration reverified")
                        claimed = self._apply(campaign_id, "claim", node_id=key, owner=self.owner)
                        self._apply(campaign_id, "complete", node_id=key,
                                    token=claimed["nodes"][key]["lease"]["token"], data=outcome)
                continue
            if node["status"] != "running":
                continue
            task = self._observe(node)
            if task is None:
                # An interrupted reservation uses the same saved task ID, never a new child.
                if graph["status"] == "active" and (start_ready or graph["context"]["auto_start"]):
                    self._dispatch(campaign_id, key, node)
                continue
            status = str(getattr(task, "status", ""))
            if status == "published" or (status == "completed" and getattr(task, "pull_request_url", "")):
                outcome = self.published_outcome(task) if self.published_outcome else {
                    "stage": "awaiting_ci", "error": "Published candidate needs integration verification"}
                stage = outcome.get("stage")
                operation = "complete" if stage == "completed" else "fail" if stage == "failed" else "checkpoint"
                if operation != "checkpoint" or node["checkpoint"] != outcome:
                    self._apply(campaign_id, operation, node_id=key, token=node["lease"]["token"], data=outcome)
            elif status in {"completed", "failed", "blocked", "cancelled", "rolled_back"}:
                self._apply(campaign_id, "complete" if status == "completed" else "fail",
                            node_id=key, token=node["lease"]["token"],
                            data=terminal_observation(task))
            elif status == "proposed" and graph["status"] == "active" and (start_ready or graph["context"]["auto_start"]):
                self._dispatch(campaign_id, key, node)
        graph = self.graph_store.load(self.identity(campaign_id))
        if start_ready or graph["context"]["auto_start"]:
            admission = self.dispatch_admission if not start_ready else None
            if admission is not None and not admission(campaign_id, graph):
                return self.get(campaign_id)
            for key in ready_nodes(graph):
                if admission is not None and not admission(campaign_id, graph, key):
                    continue
                claimed = self._apply(campaign_id, "claim", node_id=key, owner=self.owner)
                self._dispatch(campaign_id, key, claimed["nodes"][key])
        return self.get(campaign_id)

    def _observe(self, node):
        try:
            return self.task_getter(node["action"]["task_id"])
        except Exception as exc:
            if getattr(exc, "code", None) == "task_not_found" or isinstance(exc, KeyError):
                return None
            # A transient store/provider error must not mark a dependency permanently failed.
            raise

    def require_retryable(self, node):
        if node is None:
            raise TaskDagError("Retry node was not found")
        task = self._observe(node)
        if task is None:
            raise TaskDagError("Child retry evidence is unavailable; observe the child before replanning")
        admission = retry_admission(task)
        if not admission["retryable"]:
            raise TaskDagError("Cannot retry this child: " + admission["retry_blocker"] +
                               ". Use an explicit replacement decision if fresh execution is appropriate; preserve the goal and dependencies.")

    def _dispatch(self, campaign_id: str, key: str, node: dict) -> None:
        recorded_pr = node["result"].get("pull_request_url")
        if recorded_pr:
            task = self._observe(node)
            if (task is None or getattr(task, "status", "") not in {"published", "completed"}
                    or getattr(task, "pull_request_url", "") != recorded_pr):
                raise TaskDagError("Recorded publication is unavailable or changed; do not recreate its implementation")
            return
        proposal = self.proposal_store.get_proposal(node["action"]["proposal_id"])
        if proposal is None:
            self._apply(campaign_id, "fail", node_id=key, token=node["lease"]["token"],
                        data={"error": "Campaign proposal was removed"})
            return
        task = self.ensure_task(proposal, campaign_id, node["action"]["task_id"])
        status = str(getattr(task, "status", ""))
        if status == "proposed" or (node["attempt"] > 1 and status in {"failed", "blocked"}):
            admission = retry_admission(task)
            if (admission.get("attempts_remaining") == 0 and not admission.get("candidate_continuation")) or (status != "proposed" and not admission["retryable"]):
                self._apply(campaign_id, "fail", node_id=key, token=node["lease"]["token"],
                            data=terminal_observation(task))
                return
            self.task_starter(task.task_id)

    def list(self, limit: int = 100, *, recoverable_only: bool = False) -> list[EvolutionCampaign]:
        rows = []
        for campaign in self.iter_campaigns(recoverable_only=recoverable_only):
            rows.append(campaign)
            if len(rows) >= limit:
                break
        return rows

    def iter_campaigns(self, *, recoverable_only: bool = False):
        before = None
        while True:
            page = self.graph_store.ledger.checkpoints("dynamic_task_dag_v1", limit=64,
                                                       before=before, recoverable_only=recoverable_only)
            if not page:
                break
            for item in page:
                if item["data"].get("context", {}).get("domain") == "evolution_campaign":
                    campaign = self.get(item["run_id"])
                    if campaign:
                        yield campaign
            last = page[-1]
            before = last["updated_at_millis"], last["run_id"]

    def _public(self, campaign_id: str, graph: dict) -> EvolutionCampaign:
        context = graph["context"]
        ready = set(ready_nodes(graph))
        nodes = [CampaignNode(node_id=key, proposal_id=node["action"]["proposal_id"],
                              task_id=node["action"]["task_id"] if node["attempt"] else "",
                              depends_on=node["depends_on"], status="ready" if key in ready else (
                                  node["checkpoint"].get("stage", "running") if node["status"] == "running" else node["status"]),
                              error=(node["checkpoint"] if node["status"] == "running" else node["result"]).get("error", ""))
                 for key, node in graph["nodes"].items()]
        status = graph["status"]
        if status == "active":
            status = "attention_required" if any(node.status in {"failed", "uncertain"} for node in nodes) else (
                "running" if any(node["status"] == "running" for node in graph["nodes"].values()) else "ready")
            if all(node.status == "completed" for node in nodes):
                status = "awaiting_verification"
        return EvolutionCampaign(campaign_id, context["name"], graph["objective"], nodes, status=status,
                                 auto_start_safe_nodes=context["auto_start"], revision=graph["revision"],
                                 created_at_millis=context["created_at_millis"],
                                 updated_at_millis=self.graph_store.ledger.snapshot(campaign_id)["updated_at_millis"])
