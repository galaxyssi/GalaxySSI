"""Evidence-linked 0–3 month, 3–12 month, 1–2 year and 3–5 year roadmap."""
from __future__ import annotations

import uuid
from pathlib import Path
from typing import Iterable

from .common import now_millis
from .models import RadarItem, ResearchRun, RoadmapItem, RoadmapPlan
from .storage import EvolutionV2Store


class RoadmapPlanner:
    def __init__(self, store: EvolutionV2Store) -> None:
        self.store = store

    def create(self, goal: str, research_runs: Iterable[ResearchRun] = ()) -> RoadmapPlan:
        runs = list(research_runs)
        radar = [item for run in runs for item in run.items]
        by_target = _by_target(radar)
        roadmap_id = f"roadmap-{uuid.uuid4().hex[:20]}"
        plan = RoadmapPlan(
            roadmap_id=roadmap_id,
            title="GalaxySSI Super Agent Evolution Roadmap",
            goal=str(goal or "Evolve GalaxySSI into a safe, interoperable, durable personal super Agent.")[:2_000],
            research_run_ids=[run.run_id for run in runs],
            items=[
                _item(
                    "h0-safe-harness", "Production-safe self-evolution harness", "0-3-months", "verification",
                    "Every Desktop and Android candidate is built and tested in isolation; failures restore the stable runtime.",
                    "A self-modifying system must prove rollback and auditability before adding autonomy.",
                    ["V1 Git worktree loop"], by_target.get("evaluation and verification", []),
                    ["Immutable gates pass", "Android device test restores the stable APK", "PR creation requires an approval hash"],
                    "high", 100,
                ),
                _item(
                    "h0-radar", "Trusted technology radar and proposal pipeline", "0-3-months", "research",
                    "Weekly official-source scans produce scored, reviewable proposals without executing discovered code.",
                    "Fast-moving Agent ecosystems require continuous research, but popularity cannot be treated as trust.",
                    ["GitHub CLI authentication"], _top_repos(radar, 8),
                    ["Official and allowlisted sources are labeled", "License and maintenance risks are recorded", "No external code executes during discovery"],
                    "medium", 95,
                ),
                _item(
                    "h1-open-protocols", "Unified MCP, A2A, ACP and Agent Skills interoperability", "3-12-months", "interoperability",
                    "GalaxySSI can discover, authorize and route tools, Agents and portable skills through versioned adapters.",
                    "Open protocols reduce lock-in and let GalaxySSI remain the neutral control plane.",
                    ["Trusted radar", "capability registry", "permission broker"],
                    _combine(by_target, "MCP interoperability", "external Agent interoperability", "Agent client protocol", "portable Agent skills"),
                    ["Protocol version negotiation", "per-capability permissions", "remote content remains untrusted by default", "adapter conformance tests"],
                    "high", 90,
                ),
                _item(
                    "h1-durable-runs", "Durable multi-Agent task graph runtime", "3-12-months", "orchestration",
                    "Long-running tasks survive Desktop restarts and resume from deterministic checkpoints with human approval nodes.",
                    "Self-evolution and cross-device work cannot depend on one in-memory thread.",
                    ["persistent run model", "idempotent tools", "event journal"], by_target.get("durable multi-Agent runtime", []),
                    ["Crash/restart recovery tests", "idempotency keys on external effects", "100+ local runtime simulation", "10,000+ registered Agent metadata load test"],
                    "critical", 88,
                ),
                _item(
                    "h1-evals", "Continuous Agent evaluation and regression laboratory", "3-12-months", "verification",
                    "Every capability has behavior, security, latency, resource and visual regression benchmarks.",
                    "Build success alone cannot prove an autonomous Agent is better.",
                    ["stable benchmark fixtures", "telemetry schema"], by_target.get("evaluation and verification", []),
                    ["Golden task suites", "Android screenshot/behavior baselines", "prompt-injection tests", "cost and latency budgets"],
                    "high", 86,
                ),
                _item(
                    "h2-learning", "Evidence-based lifelong personalization", "1-2-years", "learning",
                    "GalaxySSI learns durable user preferences and skills from outcomes while preserving provenance, correction and deletion.",
                    "Long-term learning must distinguish raw history, extracted memory, knowledge and executable skill.",
                    ["memory provenance", "evaluation laboratory", "privacy policy"], by_target.get("cross-session memory", []),
                    ["Every memory has source and confidence", "User can inspect/correct/delete", "No silent promotion of untrusted instructions to skills"],
                    "critical", 82,
                ),
                _item(
                    "h2-federation", "Federated cross-device Agent mesh", "1-2-years", "distributed-agents",
                    "Phones, PCs, servers and smart devices negotiate capabilities and run tasks with local-first privacy and revocable trust.",
                    "GalaxySSI's advantage is persistent coordination across models, Agents, compute nodes and devices.",
                    ["open protocols", "device identity", "durable runs", "policy engine"],
                    _combine(by_target, "external Agent interoperability", "device control"),
                    ["Offline queueing", "capability attestation", "route-scoped authorization", "network partition recovery"],
                    "critical", 80,
                ),
                _item(
                    "h3-verifiable-autonomy", "Verifiable autonomous capability synthesis", "3-5-years", "autonomy",
                    "GalaxySSI can propose and implement new capabilities, but promotion requires formal policies, adversarial evaluation and reversible deployment.",
                    "The long-term target is not unrestricted self-modification; it is progressively stronger autonomy with progressively stronger evidence.",
                    ["all earlier horizons", "signed provenance", "sandboxed capability marketplace"], _top_repos(radar, 12),
                    ["Machine-verifiable policy receipts", "reproducible builds", "signed provenance", "automatic canary rollback", "independent reviewer quorum"],
                    "critical", 75,
                ),
            ],
        )
        plan.updated_at_millis = now_millis()
        self.store.save_roadmap(plan)
        return plan


def _item(
    item_id: str,
    title: str,
    horizon: str,
    pillar: str,
    outcome: str,
    rationale: str,
    dependencies: list[str],
    candidates: list[str],
    acceptance: list[str],
    risk: str,
    priority: int,
) -> RoadmapItem:
    return RoadmapItem(
        item_id=item_id,
        title=title,
        horizon=horizon,
        strategic_pillar=pillar,
        outcome=outcome,
        rationale=rationale,
        dependencies=dependencies,
        candidate_sources=candidates[:20],
        acceptance=acceptance,
        risk_level=risk,
        priority=priority,
    )


def _by_target(items: Iterable[RadarItem]) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    for item in sorted(items, key=lambda row: row.total_score, reverse=True):
        for target in item.integration_targets:
            rows = result.setdefault(target, [])
            if item.repository not in rows:
                rows.append(item.repository)
    return result


def _combine(mapping: dict[str, list[str]], *keys: str) -> list[str]:
    rows: list[str] = []
    for key in keys:
        for value in mapping.get(key, []):
            if value not in rows:
                rows.append(value)
    return rows[:20]


def _top_repos(items: Iterable[RadarItem], count: int) -> list[str]:
    return [item.repository for item in sorted(items, key=lambda row: row.total_score, reverse=True)[:count]]
