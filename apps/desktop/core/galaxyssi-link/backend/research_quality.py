"""Shared research rules and conservative risk lint, not a truth classifier."""
from __future__ import annotations

import json
import re
from functools import lru_cache
from pathlib import Path


@lru_cache(maxsize=1)
def standard() -> dict:
    return json.loads((Path(__file__).with_name("research_contract") / "research-quality.json").read_text(encoding="utf-8"))


def research_quality_prompt() -> str:
    contract = standard()
    return f"GalaxySSI research quality ({contract['version']}):\n" + "\n".join(
        f"- {rule}" for rule in contract["rules"]
    )


def assess_answer(answer: str, *, research_observed: bool = False) -> dict:
    # Quoted examples and code are not assertions made by the assistant.
    prose = re.sub(r"```[\s\S]*?```", "", str(answer or ""))
    prose = "\n".join(line for line in prose.splitlines() if not line.lstrip().startswith(">"))
    observed = research_observed or bool(re.search(r"\]\(https?://", prose))
    risks = [rule["id"] for rule in standard()["risk_rules"]
             if observed and re.search(rule["pattern"], prose)]
    return {
        "contract": standard()["version"],
        "status": "needs_review" if risks else "no_structural_risk_detected" if observed else "not_applicable",
        "risks": risks,
        "semantic_verification": "not_independently_verified",
        "research_observed": observed,
    }


def quality_repair_prompt(report: dict) -> str:
    return (f"GalaxySSI research quality review: {', '.join(report['risks'])}. "
            + standard()["repair"])


def research_stage(stage: str, **details: object) -> dict:
    """Metadata only; task leases, cancellation and delivery keep their owners."""
    if stage not in {"planning", "retrieving", "retrieval_observed", "synthesizing", "quality_checked", "synthesis_completed"}:
        raise ValueError("Unknown research stage")
    return {"contract": standard()["version"], "stage": stage,
            "delivery": "not_confirmed", **details}
