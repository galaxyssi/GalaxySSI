"""Loopback-only FastAPI API for the Desktop evolution control plane."""
from __future__ import annotations

import ipaddress
from typing import Any

from fastapi import APIRouter, HTTPException, Query, Request
from pydantic import BaseModel, ConfigDict, Field

from .preflight import PreflightInspector
from .runtime import evolution_v2_runtime

router = APIRouter(prefix="/api/evolution/v2", tags=["self-evolution-v2"])
_LOOPBACK_HOSTNAMES = {"localhost", "testclient"}


class EvolutionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class ResearchReq(EvolutionRequest):
    query: str = Field(default="", max_length=1_000)
    trusted_only: bool = False
    limit: int = Field(default=40, ge=1, le=100)
    create_proposals: bool = True


class RoadmapReq(EvolutionRequest):
    goal: str = Field(
        default="Evolve GalaxySSI into a safe, interoperable, durable personal super Agent.",
        min_length=1,
        max_length=4_000,
    )
    research_run_ids: list[str] = Field(default_factory=list, max_length=100)


class MaterializeReq(EvolutionRequest):
    agent_id: str = Field(default="auto", pattern=r"^[A-Za-z0-9._-]{1,64}$")
    max_attempts: int = Field(default=5, ge=1, le=10)
    start: bool = False


class IssueIngestReq(EvolutionRequest):
    text: str = Field(min_length=1, max_length=262_144)
    source: str = Field(default="manual", min_length=1, max_length=128)
    create_proposals: bool = True


class CampaignReq(EvolutionRequest):
    name: str = Field(min_length=1, max_length=200)
    objective: str = Field(default="", max_length=4_000)
    nodes: list[dict[str, Any]] = Field(default_factory=list, max_length=100)
    auto_start_safe_nodes: bool = False


class CampaignTickReq(EvolutionRequest):
    start_ready: bool = False


class SchedulerConfigReq(EvolutionRequest):
    enabled: bool
    evolutions_per_day: int = Field(ge=1, le=96)
    execution_mode: str = Field(pattern=r"^(serial|parallel)$")
    max_parallel_evolutions: int = Field(ge=2, le=4)


def _is_loopback_host(host: str) -> bool:
    normalized = str(host or "").strip().casefold().strip("[]")
    if normalized in _LOOPBACK_HOSTNAMES:
        return True
    with_zone_removed = normalized.split("%", 1)[0]
    try:
        return ipaddress.ip_address(with_zone_removed).is_loopback
    except ValueError:
        return False


def _runtime(request: Request):
    host = str(request.client.host if request.client else "")
    if not _is_loopback_host(host):
        raise HTTPException(status_code=403, detail={"error": {"code": "loopback_required", "message": "Evolution V2 API is Desktop-loopback only."}})
    return evolution_v2_runtime()


@router.get("/health")
def health(request: Request):
    return _runtime(request).health()


@router.get("/preflight")
def preflight(request: Request):
    runtime = _runtime(request)
    return PreflightInspector(runtime.manager.source_root).inspect()


@router.get("/policy")
def policy(request: Request):
    return _runtime(request).manager.policy.public()


@router.get("/tasks/{task_id}/metadata")
def task_metadata(task_id: str, request: Request):
    runtime = _runtime(request)
    runtime.manager.require(task_id)
    return runtime.manager.task_metadata(task_id)


@router.post("/research/runs")
def run_research(req: ResearchReq, request: Request):
    runtime = _runtime(request)
    try:
        run = runtime.manager.radar.run(req.query, trusted_only=req.trusted_only, limit=req.limit)
        proposals = runtime.manager.radar.proposals(run) if req.create_proposals else []
        runtime.manager.audit.append(
            "research_completed",
            payload={"run_id": run.run_id, "items": len(run.items), "proposals": len(proposals)},
        )
        return {"run": run.public(), "proposals": [proposal.public() for proposal in proposals]}
    except Exception as exc:
        raise HTTPException(status_code=409, detail={"error": {"code": "research_failed", "message": str(exc)[:2_000]}}) from exc


@router.get("/research/runs")
def list_research(request: Request, limit: int = Query(50, ge=1, le=500)):
    runtime = _runtime(request)
    return {"runs": [run.public() for run in runtime.manager.v2_store.list_research(limit)]}


@router.get("/research/runs/{run_id}")
def get_research(run_id: str, request: Request):
    run = _runtime(request).manager.v2_store.get_research(run_id)
    if run is None:
        raise HTTPException(status_code=404, detail={"error": {"code": "research_not_found", "message": "Research run was not found."}})
    return run.public()


@router.post("/roadmaps")
def create_roadmap(req: RoadmapReq, request: Request):
    runtime = _runtime(request)
    runs = []
    for run_id in req.research_run_ids:
        run = runtime.manager.v2_store.get_research(run_id)
        if run is not None:
            runs.append(run)
    plan = runtime.manager.roadmaps.create(req.goal, runs)
    runtime.manager.audit.append("roadmap_created", payload={"roadmap_id": plan.roadmap_id, "research_runs": req.research_run_ids})
    return plan.public()


@router.get("/roadmaps")
def list_roadmaps(request: Request, limit: int = Query(50, ge=1, le=500)):
    runtime = _runtime(request)
    return {"roadmaps": [plan.public() for plan in runtime.manager.v2_store.list_roadmaps(limit)]}


@router.get("/roadmaps/{roadmap_id}")
def get_roadmap(roadmap_id: str, request: Request):
    plan = _runtime(request).manager.v2_store.get_roadmap(roadmap_id)
    if plan is None:
        raise HTTPException(status_code=404, detail={"error": {"code": "roadmap_not_found", "message": "Roadmap was not found."}})
    return plan.public()


@router.get("/proposals")
def list_proposals(request: Request, limit: int = Query(100, ge=1, le=500)):
    runtime = _runtime(request)
    return {"proposals": [proposal.public() for proposal in runtime.manager.v2_store.list_proposals(limit)]}


@router.post("/proposals/{proposal_id}/materialize")
def materialize_proposal(proposal_id: str, req: MaterializeReq, request: Request):
    runtime = _runtime(request)
    proposal = runtime.manager.v2_store.get_proposal(proposal_id)
    if proposal is None:
        raise HTTPException(status_code=404, detail={"error": {"code": "proposal_not_found", "message": "Proposal was not found."}})
    try:
        task = runtime.manager.create_from_proposal(
            proposal,
            agent_id=req.agent_id,
            max_attempts=req.max_attempts,
            start=req.start,
        )
        return {"proposal": proposal.public(), "task": task.public()}
    except Exception as exc:
        raise HTTPException(status_code=409, detail={"error": {"code": getattr(exc, "code", "materialize_failed"), "message": str(exc)[:2_000]}}) from exc


@router.post("/issues/scan")
def scan_issues(request: Request, create_proposals: bool = True):
    runtime = _runtime(request)
    signals = runtime.manager.issue_scanner.scan()
    proposals = [runtime.manager.issue_scanner.proposal(signal) for signal in signals if signal.status == "open"] if create_proposals else []
    return {"signals": [signal.public() for signal in signals], "proposals": [proposal.public() for proposal in proposals]}


@router.post("/issues/ingest")
def ingest_issue(req: IssueIngestReq, request: Request):
    runtime = _runtime(request)
    signals = runtime.manager.issue_scanner.ingest_text(req.text, source=req.source)
    proposals = [runtime.manager.issue_scanner.proposal(signal) for signal in signals if signal.status == "open"] if req.create_proposals else []
    return {"signals": [signal.public() for signal in signals], "proposals": [proposal.public() for proposal in proposals]}


@router.get("/issues")
def list_issues(request: Request, limit: int = Query(200, ge=1, le=500)):
    runtime = _runtime(request)
    return {"signals": [signal.public() for signal in runtime.manager.v2_store.list_issues(limit)]}


@router.post("/campaigns")
def create_campaign(req: CampaignReq, request: Request):
    runtime = _runtime(request)
    try:
        campaign = runtime.manager.campaigns.create(
            req.name,
            req.objective,
            req.nodes,
            auto_start_safe_nodes=req.auto_start_safe_nodes,
        )
        return campaign.public()
    except Exception as exc:
        raise HTTPException(status_code=400, detail={"error": {"code": "campaign_invalid", "message": str(exc)[:2_000]}}) from exc


@router.get("/campaigns")
def list_campaigns(request: Request, limit: int = Query(100, ge=1, le=500)):
    runtime = _runtime(request)
    return {"campaigns": [campaign.public() for campaign in runtime.manager.v2_store.list_campaigns(limit)]}


@router.post("/campaigns/{campaign_id}/tick")
def tick_campaign(campaign_id: str, req: CampaignTickReq, request: Request):
    runtime = _runtime(request)
    try:
        return runtime.manager.campaigns.tick(campaign_id, start_ready=req.start_ready).public()
    except Exception as exc:
        raise HTTPException(status_code=409, detail={"error": {"code": "campaign_tick_failed", "message": str(exc)[:2_000]}}) from exc


@router.get("/audit")
def audit_events(request: Request, limit: int = Query(200, ge=1, le=1_000)):
    runtime = _runtime(request)
    return {"events": runtime.manager.audit.list(limit=limit), "integrity": runtime.manager.audit.verify()}


@router.get("/audit/verify")
def audit_verify(request: Request):
    return _runtime(request).manager.audit.verify()


@router.get("/scheduler")
def scheduler_status(request: Request):
    return _runtime(request).scheduler.status()


@router.post("/scheduler/config")
def scheduler_config(request: Request, req: SchedulerConfigReq):
    return _runtime(request).scheduler.update_config(req.model_dump())


@router.post("/scheduler/tick")
def scheduler_tick(
    request: Request,
    force: bool = False,
    evolution_only: bool = False,
):
    return _runtime(request).scheduler.run_due(
        force=force,
        evolution_only=evolution_only,
    )


@router.get("/github/checks")
def github_checks(request: Request, target: str = Query(..., min_length=1, max_length=1_000)):
    runtime = _runtime(request)
    try:
        return runtime.manager.github.pull_request_checks(target)
    except Exception as exc:
        raise HTTPException(status_code=409, detail={"error": {"code": "github_checks_failed", "message": str(exc)[:2_000]}}) from exc
