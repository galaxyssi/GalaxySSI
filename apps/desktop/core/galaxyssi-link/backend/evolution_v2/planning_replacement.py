"""Compile an explicit model replacement into a complete identity-safe revision."""
from __future__ import annotations

from agent_task_dag import TaskDagError, canonical
from .common import sha256_text


def replacement_revision(graph: dict, decision: dict, campaign_id: str, observed_id: str) -> tuple[dict, str]:
    if set(decision) - {"operation", "node_id", "reason", "proposal"}:
        raise TaskDagError("replace accepts only operation, node_id, reason and optional proposal; use revise for other dependency changes")
    target = decision.get("node_id")
    node = graph["nodes"].get(target) if isinstance(target, str) else None
    if node is None or node["status"] != "failed":
        raise TaskDagError("replace requires an observed-failed node; running, completed and uncertain effects cannot be replaced")
    fresh = "replacement-" + sha256_text(canonical([campaign_id, observed_id, target]))[:32]
    if fresh in graph["nodes"] or fresh in graph.get("retired_ids", []):
        raise TaskDagError("Replacement identity already exists")
    rows = []
    for current in sorted(graph["nodes"].values(), key=lambda item: item["position"]):
        key = current["node_id"]
        row = {"node_id": fresh if key == target else key,
               "depends_on": [fresh if dependency == target else dependency for dependency in current["depends_on"]]}
        if key == target and "proposal" in decision:
            row["proposal"] = decision["proposal"]
        else:
            row["proposal_id"] = current["action"]["proposal_id"]
        rows.append(row)
    return {"operation": "revise", "reason": decision["reason"], "nodes": rows,
            "supersede_ids": [target]}, fresh
