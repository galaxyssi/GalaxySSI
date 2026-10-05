"""Read-only, all-assigned Desktop capture for one explicitly scoped Android trial."""
from __future__ import annotations

import argparse
from contextlib import closing
import hashlib
import json
from pathlib import Path
import sqlite3
import time

from agent_provider_usage import AgentProviderUsage
from agent_task_recovery_query import IDENTITY_FIELDS
from agent_tool_evidence import canonical, task_identity, valid_identity
from codex_provider_usage import MAX_COUNTER, identifier
from codex_usage_export import collect

FORMAT = "galaxyssi.codex-trial-scope.v1"
TERMINAL = frozenset({"completed", "failed", "cancelled", "timed_out"})
TIMES = ("created_at", "started_at", "completed_at", "updated_at", "elapsed_ms", "first_output_at")


def validate_scope(scope):
    expected = {"format", "trial_id", "client_route_id", "conversation_id", "turn_id", "contact_id",
                "agent_id", "requested_model", "requested_reasoning_effort", "expected_nodes"}
    if not isinstance(scope, dict) or set(scope) != expected or scope["format"] != FORMAT:
        raise ValueError("Exact trial scope fields required")
    if any(not identifier(scope[key]) for key in expected - {"format", "expected_nodes"}):
        raise ValueError("Invalid trial scope identifier")
    if scope["agent_id"] != "codex" or scope["requested_reasoning_effort"] not in {"low", "medium", "high", "xhigh"}:
        raise ValueError("Explicit Codex model and reasoning controls required")
    if scope["requested_model"].lower() in {"auto", "default", "latest"}:
        raise ValueError("Automatic model selection is not an experiment control")
    nodes = scope["expected_nodes"]
    if not isinstance(nodes, list) or not nodes or any(not identifier(node) for node in nodes) or len(set(nodes)) != len(nodes):
        raise ValueError("Unique, nonempty planned node identities required")


def read_tasks(database: Path, scope: dict) -> list[dict]:
    # Do not construct AgentTaskManager/AgentTaskStore: their constructors may write or recover work.
    with closing(sqlite3.connect(Path(database).resolve().as_uri() + "?mode=ro", uri=True, timeout=2)) as db:
        db.execute("BEGIN")
        rows = db.execute("SELECT payload FROM agent_tasks WHERE "
                          "json_extract(payload,'$.client_route_id')=? AND "
                          "json_extract(payload,'$.client_conversation_id')=? AND "
                          "json_extract(payload,'$.client_turn_id')=? AND "
                          "json_extract(payload,'$.contact_id')=? AND "
                          "json_extract(payload,'$.agent_id')=? ORDER BY created_at,task_id",
                          tuple(scope[key] for key in ("client_route_id", "conversation_id", "turn_id", "contact_id", "agent_id"))).fetchall()
        tasks = []
        for row, in rows:
            value = json.loads(row)
            fields = task_identity(value)
            generation = value.get("execution_generation", 1)
            if not valid_identity(fields) or type(generation) is not int or not 1 <= generation <= MAX_COUNTER:
                raise ValueError("Invalid stored task identity or generation")
            options = (value.get("request_snapshot") or {}).get("options") or {}
            invocation = options.get("agent_invocation") or {}
            tasks.append({**fields, "node_id": options.get("agent_instance_id"),
                          "execution_generation": generation, "status": value.get("status"),
                          "storage_revision": value.get("_storage_revision"),
                          "requested_model": invocation.get("model_id"),
                          "requested_reasoning_effort": invocation.get("reasoning_effort"),
                          "retry_of": value.get("retry_of"),
                          "times": {key: value.get(key) for key in TIMES}})
        return tasks


def capture(database: Path, scope: dict) -> dict:
    validate_scope(scope)
    started = time.time_ns() // 1_000_000
    before = read_tasks(database, scope)
    archive = AgentProviderUsage(database)
    tasks, issues = [], []
    for source in before:
        task = dict(source)
        identity = {key: source[key] for key in IDENTITY_FIELDS}
        task_issues = []
        if source["status"] not in TERMINAL:
            task_issues.append("task_not_terminal")
        for field in ("requested_model", "requested_reasoning_effort"):
            if source[field] != scope[field]:
                task_issues.append(field + "_mismatch")
        generations = archive.observed_generations(identity, client_route_id=scope["client_route_id"])
        task["unobserved_generation_count"] = source["execution_generation"] - sum(
            generation <= source["execution_generation"] for generation in generations)
        if any(generation > source["execution_generation"] for generation in generations):
            task_issues.append("execution_generation_changed_during_capture")
        if task["unobserved_generation_count"]:
            task_issues.append("unobserved_execution_generations")
        journals = []
        for generation in generations:
            journal = collect(database, {**identity, "execution_generation": generation})
            observations = [entry["observation"] for entry in journal["entries"]]
            turns = sorted({(item["provider_thread_id"], item["provider_turn_id"]) for item in observations})
            coverage = []
            for thread, turn in turns:
                values = [item for item in observations
                          if (item["provider_thread_id"], item["provider_turn_id"]) == (thread, turn)]
                kinds = {item["kind"] for item in values}
                coverage.append({"provider_thread_id": thread, "provider_turn_id": turn,
                                 "start_observed": "turn_started" in kinds,
                                 "usage_observed": "usage_snapshot" in kinds,
                                 "terminal_observed": "turn_terminal" in kinds})
                for kind, code in (("turn_started", "provider_start_unobserved"),
                                   ("usage_snapshot", "usage_snapshot_missing"),
                                   ("turn_terminal", "provider_terminal_unobserved")):
                    if kind not in kinds:
                        task_issues.append(code)
            journal["observed_turn_coverage"] = coverage
            if any(item.get("issues") for item in observations):
                task_issues.append("provider_usage_schema_issues")
            if any(item[field] != scope[field] for item in observations
                   for field in ("requested_model", "requested_reasoning_effort")):
                task_issues.append("provider_requested_controls_mismatch")
            journals.append(journal)
        task.update(usage_journals=journals, issues=sorted(set(task_issues)))
        tasks.append(task)
        issues.extend({"node_id": source["node_id"], "task_id": source["task_id"], "code": code} for code in task["issues"])
    assignments = []
    for node in scope["expected_nodes"]:
        matches = [item["task_id"] for item in tasks if item["node_id"] == node]
        assignments.append({"node_id": node, "task_ids": matches, "observation": "observed" if matches else "unobserved"})
        if not matches:
            issues.append({"node_id": node, "code": "planned_assignment_unobserved"})
        if len(matches) > 1:
            issues.append({"node_id": node, "code": "multiple_tasks_retained_not_best_of"})
    for task in tasks:
        if task["node_id"] not in scope["expected_nodes"]:
            issues.append({"task_id": task["task_id"], "code": "unexpected_assignment"})
    after = read_tasks(database, scope)
    if before != after:
        issues.append({"code": "task_snapshot_changed_during_capture"})
    report = {"format": "galaxyssi.codex-trial-capture.v1", "scope": scope,
              "scope_sha256": hashlib.sha256(canonical(scope)).hexdigest(),
              "started_at_ms": started, "ended_at_ms": time.time_ns() // 1_000_000,
              "assignments": assignments, "tasks": tasks, "issues": issues,
              "task_snapshot_sha256": hashlib.sha256(canonical(before)).hexdigest(),
              "task_snapshot_after_sha256": hashlib.sha256(canonical(after)).hexdigest(),
              "provider_history_complete": False, "request_count": None, "trial_token_total": None,
              "billed_cost": None, "actual_model": None, "actual_reasoning_effort": None,
              "ready_for_equal_budget_comparison": False,
              "limitations": ["A planned assignment without a task observation is unobserved, not proven unattempted.",
                              "All matching tasks and observed execution generations are retained, including failures and retries.",
                              "Usage snapshots are not unique model requests; cumulative thread totals are not summed.",
                              "Late provider notifications may arrive after each journal watermark; missing observations are not zero.",
                              "Scope is an operator declaration; this capture does not prove Android delivery, answer quality or budget enforcement.",
                              "Local hashes detect changes, not an independent attestation of execution."]}
    return {**report, "capture_sha256": hashlib.sha256(canonical(report)).hexdigest()}


def export(database: Path, scope: dict, output: Path) -> dict:
    output = Path(output).resolve()
    if any((parent / ".git").exists() for parent in (output.parent, *output.parents)):
        raise ValueError("Trial captures must remain outside Git repositories")
    if output.exists():
        raise FileExistsError("Existing trial capture must not be overwritten")
    report = capture(database, scope)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("x", encoding="utf-8", newline="\n") as file:
        file.write(json.dumps(report, ensure_ascii=True, indent=2, allow_nan=False) + "\n")
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", type=Path, required=True)
    parser.add_argument("--scope", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        report = export(args.database, json.loads(args.scope.read_text(encoding="utf-8-sig")), args.output)
    except Exception as error:
        parser.exit(1, f"Capture failed ({type(error).__name__}); no model or task was started.\n")
    print(json.dumps({"status": "captured", "planned_nodes": len(report["assignments"]),
                      "observed_tasks": len(report["tasks"]), "issues": len(report["issues"]),
                      "ready_for_equal_budget_comparison": False}))
    return 2 if report["issues"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
