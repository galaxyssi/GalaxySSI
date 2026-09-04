"""Serializable models for technology research, roadmaps, policies and campaigns."""
from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any

from .common import now_millis


@dataclass
class PolicyDecision:
    requested_risk: str
    effective_risk: str
    allowed: bool
    approval_required: bool = True
    auto_publish: bool = False
    auto_merge: bool = False
    reasons: list[str] = field(default_factory=list)
    matched_rules: list[str] = field(default_factory=list)

    def public(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class TaskMetadata:
    task_id: str
    protocol: str = "galaxyssi.evolution-task.v2"
    origin: str = "manual"
    objective: str = "repair"
    policy: dict[str, Any] = field(default_factory=dict)
    research_run_ids: list[str] = field(default_factory=list)
    roadmap_item_ids: list[str] = field(default_factory=list)
    issue_signal_ids: list[str] = field(default_factory=list)
    campaign_id: str = ""
    source_commit: str = ""
    review: dict[str, Any] = field(default_factory=dict)
    provenance_path: str = ""
    ci: dict[str, Any] = field(default_factory=dict)
    created_at_millis: int = field(default_factory=now_millis)
    updated_at_millis: int = field(default_factory=now_millis)

    def public(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class RadarItem:
    item_id: str
    repository: str
    name: str
    description: str
    homepage: str = ""
    license: str = ""
    stars: int = 0
    forks: int = 0
    open_issues: int = 0
    pushed_at: str = ""
    archived: bool = False
    topics: list[str] = field(default_factory=list)
    source_kind: str = "github"
    trust_score: float = 0.0
    fit_score: float = 0.0
    maturity_score: float = 0.0
    momentum_score: float = 0.0
    maintenance_score: float = 0.0
    license_score: float = 0.0
    total_score: float = 0.0
    recommendation: str = "watch"
    rationale: list[str] = field(default_factory=list)
    risks: list[str] = field(default_factory=list)
    integration_targets: list[str] = field(default_factory=list)
    collected_at_millis: int = field(default_factory=now_millis)

    def public(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class ResearchRun:
    run_id: str
    query: str
    status: str = "running"
    trusted_only: bool = True
    items: list[RadarItem] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)
    created_at_millis: int = field(default_factory=now_millis)
    completed_at_millis: int = 0

    def public(self) -> dict[str, Any]:
        value = asdict(self)
        value["items"] = [item.public() for item in self.items]
        return value


@dataclass
class RoadmapItem:
    item_id: str
    title: str
    horizon: str
    strategic_pillar: str
    outcome: str
    rationale: str
    dependencies: list[str] = field(default_factory=list)
    candidate_sources: list[str] = field(default_factory=list)
    acceptance: list[str] = field(default_factory=list)
    risk_level: str = "medium"
    status: str = "proposed"
    priority: int = 50

    def public(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class RoadmapPlan:
    roadmap_id: str
    title: str
    goal: str
    status: str = "proposed"
    research_run_ids: list[str] = field(default_factory=list)
    items: list[RoadmapItem] = field(default_factory=list)
    created_at_millis: int = field(default_factory=now_millis)
    updated_at_millis: int = field(default_factory=now_millis)

    def public(self) -> dict[str, Any]:
        value = asdict(self)
        value["items"] = [item.public() for item in self.items]
        return value


@dataclass
class EvolutionProposal:
    proposal_id: str
    title: str
    problem: str
    scope: list[str]
    acceptance: list[str]
    reproduction_steps: list[str] = field(default_factory=list)
    risk_level: str = "medium"
    objective: str = "capability"
    origin: str = "research"
    research_run_ids: list[str] = field(default_factory=list)
    roadmap_item_ids: list[str] = field(default_factory=list)
    issue_signal_ids: list[str] = field(default_factory=list)
    status: str = "proposed"
    task_id: str = ""
    created_at_millis: int = field(default_factory=now_millis)
    updated_at_millis: int = field(default_factory=now_millis)

    def public(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class IssueSignal:
    signal_id: str
    kind: str
    title: str
    evidence: str
    severity: str
    fingerprint: str
    suggested_scope: list[str] = field(default_factory=list)
    suggested_acceptance: list[str] = field(default_factory=list)
    source: str = "runtime-log"
    status: str = "open"
    first_seen_millis: int = field(default_factory=now_millis)
    last_seen_millis: int = field(default_factory=now_millis)
    occurrences: int = 1

    def public(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class CampaignNode:
    node_id: str
    proposal_id: str = ""
    task_id: str = ""
    depends_on: list[str] = field(default_factory=list)
    status: str = "pending"
    error: str = ""

    def public(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class EvolutionCampaign:
    campaign_id: str
    name: str
    objective: str
    nodes: list[CampaignNode]
    status: str = "proposed"
    auto_start_safe_nodes: bool = False
    created_at_millis: int = field(default_factory=now_millis)
    updated_at_millis: int = field(default_factory=now_millis)

    def public(self) -> dict[str, Any]:
        value = asdict(self)
        value["nodes"] = [node.public() for node in self.nodes]
        return value


@dataclass
class ReviewResult:
    verdict: str
    risk_level: str
    findings: list[str] = field(default_factory=list)
    recommendations: list[str] = field(default_factory=list)
    reviewer: str = "static"
    raw_summary: str = ""
    completed_at_millis: int = field(default_factory=now_millis)

    def public(self) -> dict[str, Any]:
        return asdict(self)
