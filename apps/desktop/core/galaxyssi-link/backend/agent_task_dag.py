"""Model-authored dynamic DAG reducer; no provider, project, or tool is hard-coded."""
from __future__ import annotations

from collections import deque
from copy import deepcopy
import hashlib
import json
from typing import Any


class TaskDagError(ValueError):
    pass


def canonical(value: Any) -> str:
    try:
        return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)
    except (TypeError, ValueError) as exc:
        raise TaskDagError("DAG commands and checkpoints must be finite JSON values") from exc


def identifier(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip() or value != value.strip() or len(value) > 200:
        raise TaskDagError(f"{label} must be a nonempty identifier of at most 200 characters")
    return value


def specifications(rows: Any) -> dict[str, dict]:
    if not isinstance(rows, list) or not rows:
        raise TaskDagError("A task graph requires a nonempty node array")
    nodes = {}
    for row in rows:
        if not isinstance(row, dict) or set(row) - {"node_id", "depends_on", "action", "effect"}:
            raise TaskDagError("Invalid node specification")
        key = identifier(row.get("node_id"), "node_id")
        if key in nodes:
            raise TaskDagError(f"Duplicate node: {key}")
        dependencies = row.get("depends_on", [])
        if not isinstance(dependencies, list):
            raise TaskDagError("depends_on must be an array")
        dependencies = [identifier(item, "dependency") for item in dependencies]
        if len(set(dependencies)) != len(dependencies):
            raise TaskDagError("Duplicate dependency")
        effect = row.get("effect", "external")
        if effect not in {"read_only", "replayable", "external"}:
            raise TaskDagError("Effect must be read_only, replayable, or external")
        action = row.get("action")
        if not isinstance(action, dict) or not action:
            raise TaskDagError("An action descriptor is required")
        nodes[key] = {"node_id": key, "depends_on": dependencies, "action": deepcopy(action), "effect": effect}
    # Iterative validation supports long chains without the Python recursion limit.
    remaining = {key: len(node["depends_on"]) for key, node in nodes.items()}
    children: dict[str, list[str]] = {key: [] for key in nodes}
    for key, node in nodes.items():
        for dependency in node["depends_on"]:
            if dependency not in nodes or dependency == key:
                raise TaskDagError(f"Missing or self dependency: {key} -> {dependency}")
            children[dependency].append(key)
    ready = deque(key for key, count in remaining.items() if count == 0)
    visited = 0
    while ready:
        key = ready.popleft()
        visited += 1
        for child in children[key]:
            remaining[child] -= 1
            if remaining[child] == 0:
                ready.append(child)
    if visited != len(nodes):
        raise TaskDagError("Task dependencies contain a cycle")
    return nodes


def ready_nodes(graph: dict) -> list[str]:
    if graph["status"] != "active":
        return []
    nodes = graph["nodes"]
    ordered = sorted(nodes.items(), key=lambda item: item[1]["position"])
    return [key for key, node in ordered if node["status"] == "pending" and
            all(nodes[dependency]["status"] == "completed" for dependency in node["depends_on"])]


def reduce_graph(previous: dict | None, command: dict, *, run_id: str, operation_id: str) -> dict:
    canonical(command)
    operation = command.get("operation")
    if operation not in {"create", "revise", "pause", "resume", "cancel", "recover_owner", "finish",
                         "claim", "retry", "reconcile", "checkpoint", "complete", "fail"}:
        raise TaskDagError("Unknown task graph operation")
    if previous is None:
        if operation != "create":
            raise TaskDagError("Task graph does not exist")
        objective = command.get("objective")
        if not isinstance(objective, str) or not objective.strip():
            raise TaskDagError("A goal objective is required")
        context = command.get("context", {})
        if not isinstance(context, dict):
            raise TaskDagError("Goal context must be an object")
        graph = {"objective": objective, "context": deepcopy(context), "revision": 1,
                 "status": "active", "nodes": {}, "retired_ids": []}
        _replace_nodes(graph, command.get("nodes"))
        return graph
    if operation == "create":
        raise TaskDagError("Task graph already exists")
    graph = deepcopy(previous)
    if graph["status"] in {"completed", "cancelled"}:
        raise TaskDagError("A terminal task graph cannot execute or replan")
    if operation == "revise":
        revision = command.get("expected_revision")
        if type(revision) is not int or revision != graph["revision"]:
            raise TaskDagError("Stale plan revision")
        supersede = command.get("supersede_ids", [])
        if not isinstance(supersede, list):
            raise TaskDagError("supersede_ids must contain unique node IDs")
        values = [identifier(key, "superseded node") for key in supersede]
        supersede = set(values)
        if len(supersede) != len(values):
            raise TaskDagError("supersede_ids must contain unique node IDs")
        if supersede:
            _evidence(command)
        _replace_nodes(graph, command.get("nodes"), supersede=supersede)
        graph["revision"] += 1
    elif operation in {"pause", "resume", "cancel"}:
        graph["status"] = {"pause": "paused", "resume": "active", "cancel": "cancelled"}[operation]
        if operation == "cancel":
            for node in graph["nodes"].values():
                if node["status"] not in {"completed", "failed"}:
                    node["status"] = "cancelled"
                    node["lease"] = None
    elif operation == "recover_owner":
        owner = identifier(command.get("owner"), "owner")
        for node in graph["nodes"].values():
            lease = node.get("lease")
            if node["status"] == "running" and lease and lease["owner"] == owner:
                node["status"] = "uncertain" if node["effect"] == "external" else "pending"
                node["lease"] = None
    elif operation == "finish":
        _evidence(command)
        if not all(node["status"] == "completed" for node in graph["nodes"].values()):
            raise TaskDagError("The goal still has unfinished nodes")
        graph["status"] = "completed"
        graph["evidence"] = command["evidence"]
    else:
        _node_command(graph, command, run_id, operation_id)
    return graph


def _replace_nodes(graph: dict, rows: Any, *, supersede: set[str] | None = None) -> None:
    specs = specifications(rows)
    old = graph["nodes"]
    retired = set(graph["retired_ids"])
    removed = set(old) - set(specs)
    supersede = supersede or set()
    if not supersede <= removed or any(old[key]["status"] not in {"pending", "failed"} for key in supersede):
        raise TaskDagError("Only pending or observed-failed nodes can be explicitly superseded")
    if any((old[key]["status"] != "pending" or old[key]["attempt"] > 0) and key not in supersede for key in removed):
        raise TaskDagError("Started nodes require an explicit, evidenced supersession")
    if set(specs) & retired:
        raise TaskDagError("Retired node IDs cannot be reused")
    updated = {}
    for position, (key, spec) in enumerate(specs.items()):
        if key in old:
            if old[key]["status"] != "pending" and any(old[key][field] != value for field, value in spec.items()):
                raise TaskDagError("Started node specifications are immutable")
            if old[key]["attempt"] > 0 and any(old[key][field] != value for field, value in spec.items()):
                raise TaskDagError("Retried nodes retain their original side-effect identity")
            updated[key] = {**old[key], **spec}
        else:
            updated[key] = {**spec, "status": "pending", "attempt": 0, "lease": None, "checkpoint": {}, "result": {}}
        updated[key]["position"] = position
    graph["nodes"] = updated
    graph["retired_ids"] = sorted(retired | removed)


def _evidence(command: dict) -> None:
    if not isinstance(command.get("evidence"), str) or not command["evidence"].strip():
        raise TaskDagError("Reconciliation or goal completion requires evidence")


def _node_command(graph: dict, command: dict, run_id: str, operation_id: str) -> None:
    key = identifier(command.get("node_id"), "node_id")
    node = graph["nodes"].get(key)
    if node is None:
        raise TaskDagError("Node was not found")
    operation = command["operation"]
    if operation == "claim":
        if key not in ready_nodes(graph):
            raise TaskDagError("Node is not ready")
        owner = identifier(command.get("owner"), "owner")
        node["attempt"] += 1
        node["status"] = "running"
        node["lease"] = {"owner": owner, "token": hashlib.sha256(canonical([run_id, operation_id, key]).encode()).hexdigest()}
        node["effect_key"] = hashlib.sha256(canonical([run_id, key]).encode()).hexdigest()
    elif operation == "retry":
        if node["status"] != "failed":
            raise TaskDagError("Only an observed failure can be retried; reconcile uncertain effects first")
        _evidence(command)
        node["status"] = "pending"
    elif operation == "reconcile":
        if node["status"] != "uncertain":
            raise TaskDagError("Node does not need side-effect reconciliation")
        _evidence(command)
        outcome = command.get("outcome")
        if outcome not in {"completed", "failed", "not_applied"}:
            raise TaskDagError("Invalid reconciliation outcome")
        node["status"] = "pending" if outcome == "not_applied" else outcome
        node["result"] = {"evidence": command["evidence"], "outcome": outcome}
    elif operation in {"checkpoint", "complete", "fail"}:
        lease = node.get("lease")
        if node["status"] != "running" or not lease or command.get("token") != lease["token"]:
            raise TaskDagError("Stale or missing execution token")
        value = command.get("data")
        if not isinstance(value, dict):
            raise TaskDagError("Node observation must be an object")
        if operation == "checkpoint":
            node["checkpoint"] = deepcopy(value)
        else:
            node["result"] = deepcopy(value)
            node["status"] = "completed" if operation == "complete" else "failed"
            if operation == "fail" and node["effect"] == "external" and not (
                value.get("effect_outcome") == "not_applied" and
                isinstance(value.get("evidence"), str) and value["evidence"].strip()
            ):
                node["status"] = "uncertain"
            node["lease"] = None
    else:
        raise TaskDagError("Unknown task graph operation")
