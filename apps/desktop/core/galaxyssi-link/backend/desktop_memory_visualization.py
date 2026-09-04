"""Visualization contract for Desktop long-term memory."""
from __future__ import annotations

import hashlib
import json
import sqlite3
from typing import Any


ACTIVE_STATES = {"current", "planned", "pending", "conflicted"}


def _json_list(raw: Any) -> list[Any]:
    try:
        value = json.loads(str(raw or "[]"))
    except (TypeError, ValueError, json.JSONDecodeError):
        return []
    return value if isinstance(value, list) else []


def _safe_int(value: Any, default: int = 0) -> int:
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return default


def _memory_summary(row: sqlite3.Row) -> dict[str, Any]:
    evidence = _json_list(row["evidence_json"])
    return {
        "id": str(row["id"]),
        "memory_key": str(row["memory_key"]),
        "namespace": str(row["namespace"]),
        "kind": str(row["kind"]),
        "content": str(row["content"]),
        "status": str(row["status"]),
        "temporal_state": str(row["temporal_state"]),
        "confidence": float(row["confidence"]),
        "importance": float(row["importance"]),
        "evidence_count": len(evidence),
        "created_at": int(row["created_at"]),
        "updated_at": int(row["updated_at"]),
        "valid_from_at": int(row["valid_from_at"]),
        "valid_until_at": int(row["valid_until_at"]),
        "supersedes_id": str(row["supersedes_id"]),
        "superseded_by_id": str(row["superseded_by_id"]),
    }


def _evidence_entry(memory_id: str, index: int, raw: Any) -> dict[str, Any]:
    payload = raw if isinstance(raw, dict) else {"value": raw}
    serialized = json.dumps(payload, ensure_ascii=False, sort_keys=True)
    evidence_id = hashlib.sha256(
        f"{memory_id}:{index}:{serialized}".encode("utf-8")
    ).hexdigest()[:24]
    source = str(
        payload.get("source")
        or payload.get("agent_id")
        or payload.get("provider")
        or payload.get("kind")
        or "memory"
    )[:120]
    return {
        "id": evidence_id,
        "memory_id": memory_id,
        "source": source,
        "kind": str(payload.get("kind") or "observation")[:80],
        "conversation_id": str(payload.get("conversation_id") or "")[:160],
        "task_id": str(payload.get("task_id") or "")[:160],
        "observed_at": _safe_int(
            payload.get("observed_at") or payload.get("created_at")
        ),
        "payload": payload,
    }


def _current_state(
    connection: sqlite3.Connection,
    *,
    highlight_limit: int,
) -> dict[str, Any]:
    count_rows = connection.execute(
        "SELECT status, temporal_state, COUNT(*) AS count FROM memories "
        "GROUP BY status, temporal_state"
    ).fetchall()
    counts = {
        "current": 0,
        "planned": 0,
        "historical": 0,
        "deprecated": 0,
        "pending": 0,
        "conflicted": 0,
        "active": 0,
        "total": 0,
    }
    for row in count_rows:
        count = int(row["count"])
        counts["total"] += count
        if str(row["status"]) == "active":
            counts["active"] += count
        temporal_state = str(row["temporal_state"])
        if temporal_state in counts:
            counts[temporal_state] += count
    candidate_rows = connection.execute(
        "SELECT status, COUNT(*) AS count FROM memory_candidates GROUP BY status"
    ).fetchall()
    candidate_counts = {str(row["status"]): int(row["count"]) for row in candidate_rows}
    counts["pending"] += candidate_counts.get("pending_review", 0)
    counts["conflicted"] += candidate_counts.get("conflicted", 0)

    namespace_rows = connection.execute(
        "SELECT namespace, COUNT(*) AS count, MAX(updated_at) AS latest_at "
        "FROM memories WHERE status = 'active' GROUP BY namespace "
        "ORDER BY count DESC, namespace"
    ).fetchall()
    highlights = connection.execute(
        "SELECT * FROM memories WHERE status = 'active' "
        "ORDER BY importance DESC, updated_at DESC LIMIT ?",
        (highlight_limit,),
    ).fetchall()
    return {
        "counts": counts,
        "last_updated_at": max(
            [int(row["latest_at"] or 0) for row in namespace_rows],
            default=0,
        ),
        "namespaces": [
            {
                "namespace": str(row["namespace"]),
                "count": int(row["count"]),
                "latest_at": int(row["latest_at"] or 0),
            }
            for row in namespace_rows
        ],
        "highlights": [_memory_summary(row) for row in highlights],
    }


def _timeline(
    connection: sqlite3.Connection,
    *,
    limit: int,
) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    memory_rows = connection.execute(
        "SELECT * FROM memories ORDER BY updated_at DESC LIMIT ?",
        (min(limit * 3, 600),),
    ).fetchall()
    for row in memory_rows:
        memory = _memory_summary(row)
        events.append({
            "id": f"memory-created:{memory['id']}",
            "event_type": "memory_recorded",
            "occurred_at": memory["created_at"],
            "memory_id": memory["id"],
            "candidate_id": "",
            "namespace": memory["namespace"],
            "kind": memory["kind"],
            "status": "active",
            "temporal_state": (
                "current"
                if memory["temporal_state"] == "deprecated"
                else memory["temporal_state"]
            ),
            "content": memory["content"],
            "evidence_count": memory["evidence_count"],
        })
        if memory["status"] != "active":
            events.append({
                "id": f"memory-lifecycle:{memory['id']}:{memory['status']}",
                "event_type": (
                    "memory_superseded"
                    if memory["status"] == "superseded"
                    else "memory_retracted"
                ),
                "occurred_at": memory["updated_at"],
                "memory_id": memory["id"],
                "candidate_id": "",
                "namespace": memory["namespace"],
                "kind": memory["kind"],
                "status": memory["status"],
                "temporal_state": memory["temporal_state"],
                "content": memory["content"],
                "evidence_count": memory["evidence_count"],
            })

    candidate_rows = connection.execute(
        "SELECT * FROM memory_candidates ORDER BY created_at DESC LIMIT ?",
        (min(limit * 2, 400),),
    ).fetchall()
    for row in candidate_rows:
        candidate_id = str(row["id"])
        events.append({
            "id": f"candidate-created:{candidate_id}",
            "event_type": "candidate_created",
            "occurred_at": int(row["created_at"]),
            "memory_id": str(row["resulting_memory_id"]),
            "candidate_id": candidate_id,
            "namespace": str(row["namespace"]),
            "kind": str(row["kind"]),
            "status": str(row["status"]),
            "temporal_state": str(row["intended_temporal_state"]),
            "content": str(row["content"]),
            "evidence_count": len(_json_list(row["evidence_json"])),
        })
        if int(row["reviewed_at"]) > 0:
            events.append({
                "id": f"candidate-reviewed:{candidate_id}",
                "event_type": (
                    "candidate_approved"
                    if str(row["status"]) in {"approved", "auto_merged"}
                    else "candidate_rejected"
                ),
                "occurred_at": int(row["reviewed_at"]),
                "memory_id": str(row["resulting_memory_id"]),
                "candidate_id": candidate_id,
                "namespace": str(row["namespace"]),
                "kind": str(row["kind"]),
                "status": str(row["status"]),
                "temporal_state": str(row["intended_temporal_state"]),
                "content": str(row["content"]),
                "evidence_count": len(_json_list(row["evidence_json"])),
            })

    critic_rows = connection.execute(
        "SELECT * FROM memory_critic_runs ORDER BY started_at DESC LIMIT ?",
        (min(limit, 100),),
    ).fetchall()
    for row in critic_rows:
        events.append({
            "id": f"critic:{row['id']}",
            "event_type": "critic_completed" if str(row["status"]) == "completed" else "critic_failed",
            "occurred_at": int(row["completed_at"] or row["started_at"]),
            "memory_id": "",
            "candidate_id": "",
            "namespace": "general",
            "kind": "audit",
            "status": str(row["status"]),
            "temporal_state": "historical",
            "content": str(row["trigger"]),
            "evidence_count": int(row["finding_count"]),
            "action_count": int(row["action_count"]),
        })
    return sorted(
        events,
        key=lambda event: (int(event["occurred_at"]), str(event["id"])),
        reverse=True,
    )[:limit]


def _graph(
    connection: sqlite3.Connection,
    *,
    node_limit: int,
) -> dict[str, Any]:
    nodes = connection.execute(
        "SELECT * FROM memory_graph_nodes "
        "ORDER BY CASE WHEN temporal_state IN ('current', 'planned', 'pending', 'conflicted') "
        "THEN 0 ELSE 1 END, updated_at DESC LIMIT ?",
        (node_limit,),
    ).fetchall()
    node_ids = {str(row["id"]) for row in nodes}
    relation_rows = connection.execute(
        "SELECT * FROM memory_graph_relations ORDER BY updated_at DESC LIMIT ?",
        (min(node_limit * 6, 600),),
    ).fetchall()
    relations = [
        row for row in relation_rows
        if str(row["from_node_id"]) in node_ids and str(row["to_node_id"]) in node_ids
    ][: node_limit * 2]
    return {
        "nodes": [
            {
                "id": str(row["id"]),
                "label": str(row["label"]),
                "kind": str(row["kind"]),
                "namespace": str(row["namespace"]),
                "temporal_state": str(row["temporal_state"]),
                "confidence": float(row["confidence"]),
                "evidence_memory_ids": _json_list(row["evidence_memory_ids_json"]),
                "evidence_count": len(_json_list(row["evidence_memory_ids_json"])),
                "created_at": int(row["created_at"]),
                "updated_at": int(row["updated_at"]),
            }
            for row in nodes
        ],
        "relations": [
            {
                "id": str(row["id"]),
                "from_node_id": str(row["from_node_id"]),
                "to_node_id": str(row["to_node_id"]),
                "kind": str(row["relation_kind"]),
                "namespace": str(row["namespace"]),
                "temporal_state": str(row["temporal_state"]),
                "confidence": float(row["confidence"]),
                "evidence_memory_ids": _json_list(row["evidence_memory_ids_json"]),
                "evidence_count": len(_json_list(row["evidence_memory_ids_json"])),
                "valid_from_at": int(row["valid_from_at"]),
                "valid_until_at": int(row["valid_until_at"]),
                "updated_at": int(row["updated_at"]),
            }
            for row in relations
        ],
        "active_node_count": sum(
            1 for row in nodes if str(row["temporal_state"]) in ACTIVE_STATES
        ),
        "historical_node_count": sum(
            1 for row in nodes if str(row["temporal_state"]) not in ACTIVE_STATES
        ),
    }


def _evidence_chains(
    connection: sqlite3.Connection,
    *,
    limit: int,
) -> list[dict[str, Any]]:
    key_rows = connection.execute(
        "SELECT namespace, memory_key, MAX(updated_at) AS latest_at "
        "FROM memories GROUP BY namespace, memory_key "
        "ORDER BY latest_at DESC LIMIT ?",
        (limit,),
    ).fetchall()
    node_rows = connection.execute(
        "SELECT id, evidence_memory_ids_json FROM memory_graph_nodes "
        "ORDER BY updated_at DESC LIMIT 2000"
    ).fetchall()
    relation_rows = connection.execute(
        "SELECT id, evidence_memory_ids_json FROM memory_graph_relations "
        "ORDER BY updated_at DESC LIMIT 4000"
    ).fetchall()
    node_evidence = {
        str(row["id"]): set(str(value) for value in _json_list(row["evidence_memory_ids_json"]))
        for row in node_rows
    }
    relation_evidence = {
        str(row["id"]): set(str(value) for value in _json_list(row["evidence_memory_ids_json"]))
        for row in relation_rows
    }
    chains: list[dict[str, Any]] = []
    for key_row in key_rows:
        namespace = str(key_row["namespace"])
        memory_key = str(key_row["memory_key"])
        rows = connection.execute(
            "SELECT * FROM memories WHERE namespace = ? AND memory_key = ? "
            "ORDER BY created_at, id",
            (namespace, memory_key),
        ).fetchall()
        versions = [_memory_summary(row) for row in rows]
        memory_ids = {version["id"] for version in versions}
        evidence: list[dict[str, Any]] = []
        seen_evidence: set[str] = set()
        for row in rows:
            memory_id = str(row["id"])
            for index, raw in enumerate(_json_list(row["evidence_json"])):
                entry = _evidence_entry(memory_id, index, raw)
                if entry["id"] in seen_evidence:
                    continue
                seen_evidence.add(entry["id"])
                evidence.append(entry)
        current = next(
            (version for version in reversed(versions) if version["status"] == "active"),
            versions[-1] if versions else None,
        )
        chain_id = hashlib.sha256(
            f"{namespace}:{memory_key}".encode("utf-8")
        ).hexdigest()[:24]
        chains.append({
            "id": chain_id,
            "memory_key": memory_key,
            "namespace": namespace,
            "kind": str(current["kind"] if current else ""),
            "current_memory_id": str(current["id"] if current else ""),
            "current_status": str(current["status"] if current else ""),
            "current_temporal_state": str(current["temporal_state"] if current else ""),
            "latest_at": int(key_row["latest_at"] or 0),
            "versions": versions,
            "evidence": sorted(
                evidence,
                key=lambda item: (int(item["observed_at"]), str(item["id"])),
                reverse=True,
            ),
            "graph_node_ids": [
                node_id for node_id, references in node_evidence.items()
                if memory_ids & references
            ],
            "graph_relation_ids": [
                relation_id for relation_id, references in relation_evidence.items()
                if memory_ids & references
            ],
        })
    return chains


def build_memory_visualization(
    connection: sqlite3.Connection,
    now_ms: int,
    *,
    limit: int = 100,
) -> dict[str, Any]:
    bounded_limit = max(10, min(int(limit or 100), 200))
    return {
        "contract_version": 1,
        "generated_at": int(now_ms),
        "current_state": _current_state(
            connection,
            highlight_limit=min(12, bounded_limit),
        ),
        "timeline": _timeline(connection, limit=bounded_limit),
        "graph": _graph(connection, node_limit=min(60, bounded_limit)),
        "evidence_chains": _evidence_chains(
            connection,
            limit=min(60, bounded_limit),
        ),
    }
