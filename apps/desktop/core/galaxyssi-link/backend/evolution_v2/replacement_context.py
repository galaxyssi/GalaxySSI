"""Carry observed recovery evidence into new DAG children without recursive history copies."""
from __future__ import annotations

from copy import deepcopy
import re

from .common import atomic_write_json, read_json, sha256_text, stable_json
from .legacy import EvolutionError


def with_replacement_context(graph, specs, supersede_ids, reason, operation_id, campaign_id):
    if graph is None or not isinstance(supersede_ids, list):
        return specs, None
    sources = []
    for key in supersede_ids:
        node = graph["nodes"].get(key) if isinstance(key, str) else None
        if node is not None:
            sources.append({"node_id": key, "task_id": node["action"].get("task_id"),
                            "status": node["status"], "observation": deepcopy(node["result"]),
                            "checkpoint": deepcopy(node["checkpoint"])})
    record = {"campaign_id": campaign_id, "operation_id": operation_id,
              "observed_revision": graph["revision"], "decision_reason": reason, "superseded": sources}
    reference = {"context_id": sha256_text(stable_json([campaign_id, operation_id])),
                 "evidence_hash": sha256_text(stable_json(record))}
    added = False
    for spec in specs:
        previous = graph["nodes"].get(spec["node_id"])
        if previous is not None:
            if "recovery_context" in previous["action"]:
                spec["action"]["recovery_context"] = deepcopy(previous["action"]["recovery_context"])
        else:
            spec["action"]["recovery_context"] = dict(reference)
            added = True
    return specs, (reference, record) if added else None


def _path(store, reference):
    if (not isinstance(reference, dict) or set(reference) != {"context_id", "evidence_hash"}
            or any(not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{64}", value) for value in reference.values())):
        raise EvolutionError("campaign_context_conflict", "Invalid recovery evidence reference")
    return store.root / "recovery-contexts" / (reference["context_id"] + ".json")


def persist_replacement_context(store, pending):
    if pending is None:
        return
    reference, record = pending
    path = _path(store, reference)
    if path.exists():
        read_replacement_context(store, record["campaign_id"], reference)
        return
    atomic_write_json(path, record)


def read_replacement_context(store, campaign_id, reference):
    record = read_json(_path(store, reference), None)
    if not isinstance(record, dict):
        raise EvolutionError("campaign_context_unavailable", "Recovery evidence is missing or unreadable")
    if (record.get("campaign_id") != campaign_id
            or reference["context_id"] != sha256_text(stable_json([campaign_id, record.get("operation_id")]))
            or reference["evidence_hash"] != sha256_text(stable_json(record))):
        raise EvolutionError("campaign_context_conflict", "Recovery evidence identity or content changed")
    return record
