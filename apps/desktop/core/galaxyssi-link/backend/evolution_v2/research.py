"""Trusted technology radar for agents, MCP, skills and orchestration projects.

The radar only collects metadata and produces proposals. It never clones, imports,
installs or executes code from a discovered repository.
"""
from __future__ import annotations

import math
import uuid
from pathlib import Path
from typing import Any, Iterable

from .common import bounded_strings, days_since, now_millis, read_json, sha256_text
from .github_client import GitHubClient, GitHubClientError
from .models import EvolutionProposal, RadarItem, ResearchRun
from .storage import EvolutionV2Store

DEFAULT_SOURCES: dict[str, Any] = {
    "schema": "galaxyssi.evolution-sources.v2",
    "trusted_organizations": [
        "modelcontextprotocol", "a2aproject", "openai", "anthropics", "agentskills",
        "google", "google-gemini", "microsoft", "All-Hands-AI", "SWE-agent",
        "langchain-ai", "zed-industries", "block",
    ],
    "known_repositories": [
        "modelcontextprotocol/modelcontextprotocol",
        "modelcontextprotocol/registry",
        "a2aproject/A2A",
        "openai/codex",
        "openai/openai-agents-python",
        "agentskills/agentskills",
        "anthropics/claude-code",
        "zed-industries/agent-client-protocol",
        "google/adk-python",
        "google-gemini/gemini-cli",
        "microsoft/agent-framework",
        "microsoft/autogen",
        "All-Hands-AI/OpenHands",
        "SWE-agent/SWE-agent",
        "langchain-ai/langgraph",
        "block/goose",
    ],
    "discovery_queries": [
        "topic:ai-agents stars:>500 archived:false",
        "topic:model-context-protocol stars:>100 archived:false",
        "agent skills coding agent stars:>100 archived:false",
        "multi agent orchestration stars:>500 archived:false",
    ],
    "fit_keywords": [
        "agent", "multi-agent", "orchestration", "mcp", "model context protocol", "skills",
        "coding agent", "computer use", "android", "desktop", "workflow", "durable",
        "memory", "evaluation", "sandbox", "a2a", "acp",
    ],
    "allowed_licenses": ["apache-2.0", "mit", "bsd-3-clause", "bsd-2-clause", "mpl-2.0"],
}


class TechnologyRadar:
    def __init__(
        self,
        source_root: Path,
        store: EvolutionV2Store,
        github: GitHubClient | None = None,
        config_path: Path | None = None,
    ) -> None:
        self.source_root = Path(source_root).resolve()
        self.store = store
        self.github = github or GitHubClient(self.source_root)
        configured = config_path or self.source_root / "config" / "evolution-sources.json"
        loaded = read_json(Path(configured), {})
        self.config = _merge(DEFAULT_SOURCES, loaded if isinstance(loaded, dict) else {})

    def run(self, query: str = "", *, trusted_only: bool = False, limit: int = 30) -> ResearchRun:
        run = ResearchRun(
            run_id=f"research-{uuid.uuid4().hex[:20]}",
            query=str(query or "").strip()[:500] or "GalaxySSI agent ecosystem radar",
            trusted_only=bool(trusted_only),
        )
        self.store.save_research(run)
        candidates: dict[str, dict[str, Any]] = {}
        errors: list[str] = []
        known = self.config.get("known_repositories") or []
        for repository in known:
            if len(candidates) >= max(limit, len(known)):
                break
            try:
                metadata = self.github.repository(str(repository))
                candidates[str(metadata.get("full_name") or repository).casefold()] = metadata
            except Exception as exc:
                errors.append(f"{repository}: {str(exc)[:300]}")
        queries = [str(query).strip()] if str(query or "").strip() else list(self.config.get("discovery_queries") or [])
        for search_query in queries[:6]:
            try:
                for metadata in self.github.search_repositories(search_query, limit=min(limit, 30)):
                    full_name = str(metadata.get("full_name") or "")
                    if full_name:
                        candidates.setdefault(full_name.casefold(), metadata)
            except Exception as exc:
                errors.append(f"search {search_query!r}: {str(exc)[:300]}")
        items = [self._score(metadata, trusted_only=trusted_only) for metadata in candidates.values()]
        items = [item for item in items if item is not None]
        items.sort(key=lambda item: (item.total_score, item.stars), reverse=True)
        run.items = items[: max(1, min(int(limit), 100))]
        run.errors = errors[:50]
        run.status = "completed" if run.items else "failed"
        run.completed_at_millis = now_millis()
        self.store.save_research(run)
        return run

    def proposals(self, run: ResearchRun, *, maximum: int = 8) -> list[EvolutionProposal]:
        proposals: list[EvolutionProposal] = []
        for item in run.items:
            if item.recommendation not in {"adopt", "evaluate"}:
                continue
            scope, acceptance = _integration_shape(item)
            proposal = EvolutionProposal(
                proposal_id=f"proposal-{uuid.uuid4().hex[:20]}",
                title=f"Evaluate {item.name} for GalaxySSI",
                problem=(
                    f"Assess {item.repository} as a {', '.join(item.integration_targets[:3]) or 'capability'} "
                    "and integrate only the minimal interoperable ideas that improve GalaxySSI without importing untrusted runtime code."
                ),
                scope=scope,
                acceptance=acceptance,
                risk_level="high" if "runtime" in " ".join(item.integration_targets) else "medium",
                objective="capability",
                origin="research",
                research_run_ids=[run.run_id],
            )
            self.store.save_proposal(proposal)
            proposals.append(proposal)
            if len(proposals) >= maximum:
                break
        return proposals

    def _score(self, metadata: dict[str, Any], *, trusted_only: bool) -> RadarItem | None:
        full_name = str(metadata.get("full_name") or "").strip()
        if not full_name or "/" not in full_name:
            return None
        owner = full_name.split("/", 1)[0]
        trusted_orgs = {str(value).casefold() for value in self.config.get("trusted_organizations") or []}
        known = {str(value).casefold() for value in self.config.get("known_repositories") or []}
        trusted = owner.casefold() in trusted_orgs or full_name.casefold() in known
        if trusted_only and not trusted:
            return None
        description = str(metadata.get("description") or "")[:1_000]
        topics = [str(value)[:80] for value in metadata.get("topics") or []]
        haystack = " ".join([full_name, description, *topics]).casefold()
        keywords = [str(value).casefold() for value in self.config.get("fit_keywords") or []]
        matches = sorted({keyword for keyword in keywords if keyword and keyword in haystack})
        stars = max(0, int(metadata.get("stargazers_count") or 0))
        forks = max(0, int(metadata.get("forks_count") or 0))
        issues = max(0, int(metadata.get("open_issues_count") or 0))
        age = days_since(str(metadata.get("pushed_at") or ""))
        archived = bool(metadata.get("archived"))
        license_id = str((metadata.get("license") or {}).get("spdx_id") or "").casefold()
        allowed_licenses = {str(value).casefold() for value in self.config.get("allowed_licenses") or []}

        trust_score = 25.0 if trusted else 8.0
        fit_score = min(25.0, 4.0 + len(matches) * 4.2)
        maturity_score = min(15.0, 2.0 + math.log10(stars + 1) * 3.2 + math.log10(forks + 1) * 1.5)
        momentum_score = 15.0 if age <= 14 else 12.0 if age <= 60 else 8.0 if age <= 180 else 3.0
        maintenance_score = max(0.0, 15.0 - min(10.0, issues / max(stars, 100) * 500.0))
        license_score = 5.0 if license_id in allowed_licenses else 2.0 if license_id else 0.0
        if archived:
            maintenance_score = 0.0
            momentum_score = 0.0
        total = round(trust_score + fit_score + maturity_score + momentum_score + maintenance_score + license_score, 2)
        recommendation = "adopt" if trusted and total >= 78 else "evaluate" if total >= 60 else "watch"
        risks: list[str] = []
        if not trusted:
            risks.append("Repository owner is not on the trusted organization list.")
        if archived:
            risks.append("Repository is archived.")
        if not license_id:
            risks.append("No machine-readable license was reported.")
        elif license_id not in allowed_licenses:
            risks.append(f"License {license_id} requires legal review before code reuse.")
        if age > 180:
            risks.append(f"Repository has not been pushed for {age} days.")
        integration_targets = _targets(haystack)
        rationale = [
            f"Trusted source: {'yes' if trusted else 'no'}.",
            f"Matched GalaxySSI fit terms: {', '.join(matches[:8]) or 'none'}.",
            f"Last push age: {age} days; stars: {stars}; forks: {forks}.",
            "Discovery produces metadata and proposals only; external code is not executed.",
        ]
        return RadarItem(
            item_id=f"radar-{sha256_text(full_name.casefold())[:20]}",
            repository=full_name,
            name=str(metadata.get("name") or full_name.split("/", 1)[1])[:200],
            description=description,
            homepage=str(metadata.get("html_url") or metadata.get("homepage") or "")[:1_000],
            license=license_id,
            stars=stars,
            forks=forks,
            open_issues=issues,
            pushed_at=str(metadata.get("pushed_at") or ""),
            archived=archived,
            topics=topics[:30],
            trust_score=trust_score,
            fit_score=round(fit_score, 2),
            maturity_score=round(maturity_score, 2),
            momentum_score=round(momentum_score, 2),
            maintenance_score=round(maintenance_score, 2),
            license_score=license_score,
            total_score=total,
            recommendation=recommendation,
            rationale=rationale,
            risks=risks,
            integration_targets=integration_targets,
        )


def _targets(haystack: str) -> list[str]:
    targets: list[str] = []
    rules = [
        (("mcp", "model context protocol"), "MCP interoperability"),
        (("a2a", "agent-to-agent"), "external Agent interoperability"),
        (("agent client protocol", "acp"), "Agent client protocol"),
        (("skill",), "portable Agent skills"),
        (("coding agent", "software engineering agent"), "self-evolution coding runtime"),
        (("workflow", "durable", "orchestration"), "durable multi-Agent runtime"),
        (("memory",), "cross-session memory"),
        (("evaluation", "benchmark", "eval"), "evaluation and verification"),
        (("android", "computer use", "device"), "device control"),
    ]
    for terms, label in rules:
        if any(term in haystack for term in terms):
            targets.append(label)
    return targets or ["technology watch"]


def _integration_shape(item: RadarItem) -> tuple[list[str], list[str]]:
    scope = [
        "apps/desktop/core/galaxyssi-link/backend/evolution_v2",
        "config",
        "docs",
    ]
    acceptance = [
        f"Document the interoperable concepts from {item.repository} and their license constraints.",
        "Do not vendor, install or execute third-party repository code during discovery.",
        "Add a narrow adapter behind a feature flag only when an existing GalaxySSI abstraction cannot satisfy the use case.",
        "Add unit tests, failure isolation and an explicit rollback path.",
        "Keep Android and Desktop existing protocols backward compatible.",
    ]
    return scope, acceptance


def _merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    result = {**base}
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = _merge(result[key], value)
        else:
            result[key] = value
    return result
