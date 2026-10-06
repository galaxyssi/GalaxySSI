"""Offline audit of captured Codex counters, never a billing or request ledger."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from agent_task_recovery_query import IDENTITY_FIELDS
from agent_tool_evidence import canonical, valid_identity
from codex_provider_usage import CONTRACT, COUNTERS, KINDS, MAX_COUNTER, identifier, normalize


FORMAT = "galaxyssi.codex-trial-usage-audit.v1"
COUNT_FIELDS = tuple(COUNTERS.values())
OPTIONAL = "cache_write_input_tokens"


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def _require(condition, message):
    if not condition:
        raise ValueError(message)


def _integer(value, minimum=0):
    return type(value) is int and minimum <= value <= MAX_COUNTER


def _object_pairs(pairs):
    result = {}
    for key, value in pairs:
        _require(key not in result, "Duplicate JSON key")
        result[key] = value
    return result


def _nonfinite(_value):
    raise ValueError("Non-finite JSON number")


def read_capture(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"),
                      object_pairs_hook=_object_pairs, parse_constant=_nonfinite)


def _entries(capture):
    _require(isinstance(capture, dict) and capture.get("format") == "galaxyssi.codex-trial-capture.v1",
             "Unsupported capture")
    _require(capture.get("capture_sha256") == digest({k: v for k, v in capture.items() if k != "capture_sha256"}),
             "Capture digest mismatch")
    scope = capture.get("scope")
    _require(isinstance(scope, dict) and identifier(scope.get("trial_id")) and
             capture.get("scope_sha256") == digest(scope), "Invalid capture scope")
    tasks = capture.get("tasks")
    _require(isinstance(tasks, list) and isinstance(capture.get("issues"), list), "Missing task capture")
    planned, assignments = scope.get("expected_nodes"), capture.get("assignments")
    _require(isinstance(planned, list) and planned and all(identifier(node) for node in planned) and
             len(set(planned)) == len(planned) and isinstance(assignments, list) and
             all(isinstance(row, dict) for row in assignments) and
             [row.get("node_id") for row in assignments] == planned, "Invalid planned assignments")
    task_ids, entries = set(), []
    for task in tasks:
        _require(isinstance(task, dict) and valid_identity(task) and task.get("agent_id") == "codex",
                 "Invalid task identity")
        _require(task["task_id"] not in task_ids, "Duplicate task identity")
        task_ids.add(task["task_id"])
        for key in ("client_route_id", "conversation_id", "turn_id", "contact_id", "agent_id"):
            _require(task[key] == scope.get(key), "Task escaped capture scope")
        _require(_integer(task.get("execution_generation"), 1), "Invalid task generation")
        journals = task.get("usage_journals")
        _require(isinstance(journals, list), "Missing usage journals")
        generations = set()
        for journal in journals:
            _require(isinstance(journal, dict) and journal.get("contract") == CONTRACT and
                     journal.get("status") == "ready", "Invalid usage journal")
            generation = journal.get("execution_generation")
            _require(_integer(generation, 1) and generation <= task["execution_generation"] and
                     generation not in generations, "Invalid or duplicate journal generation")
            generations.add(generation)
            _require(all(journal.get(key) == task[key] for key in IDENTITY_FIELDS), "Journal identity mismatch")
            rows, upper = journal.get("entries"), journal.get("observed_through_sequence")
            _require(isinstance(rows, list) and _integer(upper) and len(rows) == upper and
                     journal.get("entries_sha256") == digest(rows), "Incomplete or changed usage journal")
            event_ids = set()
            for sequence, entry in enumerate(rows, 1):
                _require(isinstance(entry, dict) and entry.get("contract") == CONTRACT and
                         _integer(entry.get("sequence"), 1) and entry["sequence"] == sequence and
                         _integer(entry.get("execution_generation"), 1) and entry["execution_generation"] == generation and
                         all(entry.get(key) == task[key] for key in IDENTITY_FIELDS) and
                         _integer(entry.get("recorded_at_ms")), "Invalid journal entry binding")
                content = {key: entry[key] for key in ("contract", *IDENTITY_FIELDS, "execution_generation")}
                observation = entry.get("observation")
                content["observation"] = observation
                _require(entry.get("event_id") == digest(content) and entry["event_id"] not in event_ids,
                         "Invalid or duplicate journal event")
                event_ids.add(entry["event_id"])
                _require(isinstance(observation, dict) and observation.get("contract") == CONTRACT and
                         observation.get("provider") == "codex" and
                         identifier(observation.get("provider_thread_id")) and
                         identifier(observation.get("provider_turn_id")) and
                         observation.get("kind") in KINDS,
                         "Invalid provider observation")
                entries.append(entry)
    for row in assignments:
        expected = [task["task_id"] for task in tasks if task.get("node_id") == row["node_id"]]
        _require(row.get("task_ids") == expected and row.get("observation") == (
            "observed" if expected else "unobserved"), "Assignment/task binding mismatch")
    return entries


def _counters(observation):
    problems = []
    for label in ("total", "last"):
        counts = observation.get(label)
        if not isinstance(counts, dict) or set(counts) != set(COUNT_FIELDS):
            problems.append(label + "_counter_schema")
            continue
        if any(not _integer(counts[field]) and not (field == OPTIONAL and counts[field] is None)
               for field in COUNT_FIELDS):
            problems.append(label + "_invalid_counter")
            continue
        if (counts["cached_input_tokens"] > counts["input_tokens"] or
                counts["reasoning_output_tokens"] > counts["output_tokens"] or
                counts["input_tokens"] + counts["output_tokens"] != counts["total_tokens"]):
            problems.append(label + "_inconsistent_counter")
    if observation.get("issues") != []:
        problems.append("provider_schema_issues")
    if (observation.get("total_scope") != "provider_thread_cumulative_not_task_total" or
            observation.get("last_scope") != "provider_last_usage_snapshot_not_unique_response"):
        problems.append("unknown_counter_scope")
    if not problems and any(observation["last"][field] is not None and observation["total"][field] is not None and
                            observation["last"][field] > observation["total"][field] for field in COUNT_FIELDS):
        problems.append("last_exceeds_cumulative_counter")
    return problems


def _thread(thread_id, entries, scope):
    issues, turns, snapshots, reroutes = set(), {}, [], []
    for entry in entries:
        value = entry["observation"]
        turn = turns.setdefault(value["provider_turn_id"], {"owners": set(), "kinds": set(), "statuses": set()})
        turn["owners"].add((entry["task_id"], entry["execution_generation"]))
        turn["kinds"].add(value["kind"])
        if any(value.get(key) != scope.get(key) for key in ("requested_model", "requested_reasoning_effort")):
            issues.add("requested_controls_mismatch")
        if value["kind"] == "turn_terminal":
            turn["statuses"].add(value.get("provider_status"))
        if value["kind"] == "usage_snapshot":
            snapshots.append(entry)
            issues.update(_counters(value))
        if value["kind"] == "model_rerouted":
            normalized = normalize(dict(threadId=thread_id, turnId=value["provider_turn_id"],
                                        fromModel=value.get("reported_from_model"), toModel=value.get("reported_to_model")),
                                   model=value.get("requested_model"), effort=value.get("requested_reasoning_effort"),
                                   kind="model_rerouted")
            if normalized != value or value.get("issues"):
                issues.add("provider_model_reroute_schema_issues")
            reroutes.append({"event_id": entry["event_id"], "provider_turn_id": value["provider_turn_id"],
                             "reported_from_model": normalized.get("reported_from_model") if normalized else None,
                             "reported_to_model": normalized.get("reported_to_model") if normalized else None})
            issues.add("provider_model_reroute_observed")
    for turn in turns.values():
        if len(turn["owners"]) != 1:
            issues.add("provider_turn_has_multiple_owners")
        if not {"turn_started", "usage_snapshot", "turn_terminal"}.issubset(turn["kinds"]):
            issues.add("incomplete_turn_observations")
        if len(turn["statuses"]) != 1 or not turn["statuses"].issubset({"completed", "failed", "interrupted"}):
            issues.add("unknown_or_conflicting_terminal_status")
    # Receipt time is not provider sequence. Ambiguous or regressing order must
    # remain explicit; taking a maximum would hide resets and late old events.
    snapshots.sort(key=lambda row: (row["recorded_at_ms"], row["task_id"],
                                   row["execution_generation"], row["sequence"]))
    if not snapshots:
        issues.add("usage_snapshot_missing")
    if not issues:
        for previous, current in zip(snapshots, snapshots[1:]):
            old, new = previous["observation"]["total"], current["observation"]["total"]
            if previous["recorded_at_ms"] == current["recorded_at_ms"] and old != new and (
                    previous["task_id"], previous["execution_generation"]) != (
                    current["task_id"], current["execution_generation"]):
                issues.add("ambiguous_cross_execution_snapshot_order")
            if any(old[field] is not None and new[field] is not None and new[field] < old[field]
                   for field in COUNT_FIELDS):
                issues.add("cumulative_counter_regressed")
    endpoint = dict(snapshots[-1]["observation"]["total"]) if snapshots and not issues else None
    if endpoint is not None:
        endpoint["uncached_input_tokens"] = endpoint["input_tokens"] - endpoint["cached_input_tokens"]
    return {"provider_thread_id": thread_id, "observed_turn_count": len(turns),
            "observed_usage_snapshot_count": len(snapshots),
            "task_ids": sorted({entry["task_id"] for entry in entries}),
            "observed_cumulative_endpoint": endpoint,
            "endpoint_event_id": snapshots[-1]["event_id"] if endpoint else None,
            "pre_trial_baseline_observed": False, "trial_attributable_tokens": None,
            "model_control_status": "reroute_observed" if reroutes else "not_attested",
            "reported_model_reroutes": reroutes,
            "issues": sorted(issues)}


def audit(captures):
    _require(isinstance(captures, list) and captures, "At least one capture required")
    trials, ids, thread_trials = [], set(), {}
    for capture in captures:
        entries = _entries(capture)
        scope, issues = capture["scope"], set()
        trial_id = scope["trial_id"]
        _require(trial_id not in ids, "Use one frozen capture per trial, not repeated snapshots")
        ids.add(trial_id)
        if capture["issues"]:
            issues.add("capture_has_issues")
        grouped = {}
        for entry in entries:
            thread_id = entry["observation"]["provider_thread_id"]
            grouped.setdefault(thread_id, []).append(entry)
            thread_trials.setdefault(thread_id, set()).add(trial_id)
        if not grouped:
            issues.add("no_provider_threads_observed")
        tasks = capture["tasks"]
        if any(not row["task_ids"] for row in capture["assignments"]):
            issues.add("planned_assignment_unobserved")
        if any(task.get("status") not in {"completed", "failed", "cancelled", "timed_out"} for task in tasks):
            issues.add("task_not_terminal")
        if any(task.get("node_id") not in scope["expected_nodes"] for task in tasks):
            issues.add("unexpected_assignment")
        if any(task.get(key) != scope.get(key) for task in tasks
               for key in ("requested_model", "requested_reasoning_effort")):
            issues.add("task_requested_controls_mismatch")
        if any(not task["usage_journals"] or type(task.get("unobserved_generation_count")) is not int or
               task["unobserved_generation_count"] != 0 for task in tasks):
            issues.add("task_usage_coverage_incomplete")
        threads = [_thread(thread_id, rows, scope) for thread_id, rows in sorted(grouped.items())]
        if any(thread["issues"] for thread in threads):
            issues.add("thread_usage_issues")
        if any(thread["reported_model_reroutes"] for thread in threads):
            issues.add("provider_model_reroute_observed")
        trials.append({"trial_id": trial_id, "capture_sha256": capture["capture_sha256"],
                       "observed_task_count": len(tasks), "threads": threads, "issues": sorted(issues),
                       "model_control_status": "reroute_observed" if "provider_model_reroute_observed" in issues else "not_attested"})
    for trial in trials:
        shared = [row["provider_thread_id"] for row in trial["threads"]
                  if len(thread_trials[row["provider_thread_id"]]) > 1]
        trial["cross_trial_shared_threads"] = shared
        if shared:
            trial["issues"].append("cross_trial_thread_reuse")
        endpoints = [row["observed_cumulative_endpoint"] for row in trial["threads"]]
        counts = None
        if endpoints and not trial["issues"]:
            counts = {field: sum(row[field] for row in endpoints) if all(row[field] is not None for row in endpoints)
                      else None for field in (*COUNT_FIELDS, "uncached_input_tokens")}
        trial.update(observed_thread_cumulative_endpoint_sum=counts,
                     trial_token_total=None, provider_request_count=None, billed_cost=None,
                     ready_for_equal_budget_comparison=False)
    report = {"format": FORMAT, "trials": trials, "provider_history_complete": False,
              "limitations": [
                  "Cumulative endpoints include any pre-trial history; they are not trial-attributable token totals.",
                  "One last observed endpoint per thread is counted; snapshots, turns and tasks are not API requests.",
                  "Cached input is part of input; reasoning output is part of output. Neither is added twice.",
                  "Missing observations, baselines, requests, billing and actual served models remain unknown.",
                  "A reported model reroute is a fixed-model control violation; no notice does not attest the served model.",
                  "A terminal notification does not certify that the final usage notification was received.",
                  "Local capture hashes detect accidental changes, not independent provider authenticity.",
                  "Thread separation is not filesystem, tool, memory, evaluator or provider-state isolation.",
                  "This offline audit cannot establish equal budget, quality, novelty or causal superiority."]}
    return {**report, "audit_sha256": digest(report)}


def export(capture_paths, output):
    output = Path(output).resolve()
    _require(not any((parent / ".git").exists() for parent in (output.parent, *output.parents)),
             "Private usage audits must remain outside Git repositories")
    if output.exists():
        raise FileExistsError("Refusing to overwrite an audit")
    result = audit([read_capture(path) for path in capture_paths])
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("x", encoding="utf-8", newline="\n") as file:
        file.write(json.dumps(result, ensure_ascii=True, indent=2, allow_nan=False) + "\n")
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture", type=Path, action="append", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        result = export(args.capture, args.output)
    except (ValueError, TypeError, KeyError, OSError) as error:
        parser.exit(1, f"Usage audit failed ({type(error).__name__}); no model or task was invoked.\n")
    issues = sum(bool(trial["issues"]) for trial in result["trials"])
    print(json.dumps({"status": "audited", "trials": len(result["trials"]),
                      "trials_with_issues": issues, "ready_for_equal_budget_comparison": False}))
    return 2 if issues else 0


if __name__ == "__main__":
    raise SystemExit(main())
