"""Dependency-aware evolution campaigns built from individually approvable tasks."""
from __future__ import annotations

import uuid
from typing import Any, Callable, Iterable

from .common import now_millis
from .models import CampaignNode, EvolutionCampaign, EvolutionProposal
from .storage import EvolutionV2Store


class CampaignError(RuntimeError):
    pass


class CampaignManager:
    def __init__(
        self,
        store: EvolutionV2Store,
        *,
        task_factory: Callable[[EvolutionProposal, str], Any],
        task_getter: Callable[[str], Any],
        task_starter: Callable[[str], Any],
    ) -> None:
        self.store = store
        self.task_factory = task_factory
        self.task_getter = task_getter
        self.task_starter = task_starter

    def create(
        self,
        name: str,
        objective: str,
        nodes: Iterable[dict[str, Any]],
        *,
        auto_start_safe_nodes: bool = False,
    ) -> EvolutionCampaign:
        parsed: list[CampaignNode] = []
        for index, row in enumerate(nodes):
            node_id = str(row.get("node_id") or f"node-{index + 1}").strip()[:128]
            if not node_id or any(item.node_id == node_id for item in parsed):
                raise CampaignError(f"Duplicate or invalid campaign node: {node_id!r}")
            parsed.append(CampaignNode(
                node_id=node_id,
                proposal_id=str(row.get("proposal_id") or "")[:128],
                depends_on=[str(value)[:128] for value in row.get("depends_on") or []],
            ))
        if not parsed:
            raise CampaignError("Campaign requires at least one node")
        _validate_dag(parsed)
        campaign = EvolutionCampaign(
            campaign_id=f"campaign-{uuid.uuid4().hex[:20]}",
            name=str(name or "Evolution campaign")[:300],
            objective=str(objective or "")[:2_000],
            nodes=parsed,
            auto_start_safe_nodes=bool(auto_start_safe_nodes),
        )
        self.store.save_campaign(campaign)
        return campaign

    def tick(self, campaign_id: str, *, start_ready: bool = False) -> EvolutionCampaign:
        campaign = self.store.get_campaign(campaign_id)
        if campaign is None:
            raise CampaignError("Campaign was not found")
        node_map = {node.node_id: node for node in campaign.nodes}
        for node in campaign.nodes:
            if node.task_id:
                try:
                    task = self.task_getter(node.task_id)
                    node.status = _task_status(str(getattr(task, "status", "")))
                except Exception as exc:
                    node.status = "failed"
                    node.error = str(exc)[:1_000]
        for node in campaign.nodes:
            if node.status not in {"pending", "ready"}:
                continue
            dependencies = [node_map[item].status for item in node.depends_on]
            if any(status in {"failed", "cancelled", "rolled_back", "blocked"} for status in dependencies):
                node.status = "blocked"
                node.error = "A dependency did not complete successfully."
                continue
            if all(status in {"completed", "published"} for status in dependencies):
                node.status = "ready"
                if start_ready or campaign.auto_start_safe_nodes:
                    proposal = self.store.get_proposal(node.proposal_id)
                    if proposal is None:
                        node.status = "failed"
                        node.error = "Proposal was not found."
                        continue
                    try:
                        task = self.task_factory(proposal, campaign.campaign_id)
                        node.task_id = str(getattr(task, "task_id", ""))
                        node.status = "running"
                        self.task_starter(node.task_id)
                    except Exception as exc:
                        node.status = "failed"
                        node.error = str(exc)[:1_000]
        statuses = {node.status for node in campaign.nodes}
        if statuses <= {"completed", "published"}:
            campaign.status = "completed"
        elif statuses & {"failed", "blocked"}:
            campaign.status = "attention_required"
        elif statuses & {"waiting_approval"}:
            campaign.status = "waiting_approval"
        elif statuses & {"running", "validating", "publishing"}:
            campaign.status = "running"
        else:
            campaign.status = "ready"
        campaign.updated_at_millis = now_millis()
        self.store.save_campaign(campaign)
        return campaign


def _task_status(status: str) -> str:
    mapping = {
        "proposed": "pending",
        "preparing": "running",
        "running": "running",
        "validating": "validating",
        "waiting_approval": "waiting_approval",
        "publishing": "publishing",
        "published": "published",
        "completed": "completed",
        "failed": "failed",
        "blocked": "blocked",
        "cancelled": "cancelled",
        "rolled_back": "rolled_back",
    }
    return mapping.get(status, status or "pending")


def _validate_dag(nodes: list[CampaignNode]) -> None:
    node_ids = {node.node_id for node in nodes}
    for node in nodes:
        missing = [item for item in node.depends_on if item not in node_ids]
        if missing:
            raise CampaignError(f"Node {node.node_id} has missing dependencies: {', '.join(missing)}")
        if node.node_id in node.depends_on:
            raise CampaignError(f"Node {node.node_id} depends on itself")
    temporary: set[str] = set()
    permanent: set[str] = set()
    mapping = {node.node_id: node for node in nodes}

    def visit(node_id: str) -> None:
        if node_id in permanent:
            return
        if node_id in temporary:
            raise CampaignError("Campaign dependencies contain a cycle")
        temporary.add(node_id)
        for dependency in mapping[node_id].depends_on:
            visit(dependency)
        temporary.remove(node_id)
        permanent.add(node_id)

    for node in nodes:
        visit(node.node_id)
