"""Separate a research publication's public deliverables from its evidence body."""
from __future__ import annotations

import json


FORMAT = "galaxyssi.research-artifact.v1"
DELIVERY_INSTRUCTIONS = (
    "In a final galaxyssi.research-artifact.v1 reply, only local Markdown file links in summary "
    "select phone-downloadable deliverables, for example [Report](outputs/final-report.pdf). "
    "Select exact intended versions; file modification or arrival time does not choose a version. "
    "No local summary links means no phone file attachments. Workspace bodies and milestone references "
    "are research evidence, not a request to send every output file. Use immutable peer file handoff "
    "for shared evidence; retain full originals and report any missing required deliverable. "
    "Ordinary final Markdown delivery remains supported."
)


def research_summary(content: str) -> str | None:
    """None means ordinary output; an empty summary still forbids inventory fallback."""
    text = str(content or "").strip()
    if text.startswith("```") and text.endswith("```"):
        text = text.partition("\n")[2][:-3].strip()
    if not text.startswith("{"):
        return None
    try:
        value = json.loads(text)
    except (ValueError, RecursionError):
        return None
    if not isinstance(value, dict) or value.get("format") != FORMAT:
        return None
    summary = value.get("summary")
    return summary if isinstance(summary, str) else ""
