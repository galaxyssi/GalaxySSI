"""Opt-in real local goal planning, candidate execution and publication acceptance."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys
import threading
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--objective", required=True)
    parser.add_argument("--allow-execution", action="store_true")
    parser.add_argument("--publish-task")
    parser.add_argument("--inspect-task")
    parser.add_argument("--revalidate-task")
    parser.add_argument("--recover-only", action="store_true")
    args = parser.parse_args()
    if not args.allow_execution:
        parser.error("Explicit --allow-execution is required")
    source, state = args.source.resolve(), args.state.resolve()
    production = (Path(os.environ.get("APPDATA", Path.home())) / "GalaxySSI").resolve()
    manifest = state / "acceptance.json"
    if (state == source or state.is_relative_to(source) or state == production
            or state.is_relative_to(production) or source.is_relative_to(state)):
        parser.error("Use separate source and isolated state directories")
    if state.exists() and not manifest.exists():
        parser.error("Existing state is not owned by this acceptance harness")
    os.environ["GALAXYSSI_STATE_DIR"] = str(state)
    os.environ["GALAXYSSI_CONFIG_PATH"] = str(state / "agents.json")
    sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "apps/desktop/core/galaxyssi-link/backend"))
    from evolution_v2.agent_adapters import default_evolution_patch_agent
    from evolution_v2.campaign_planner import EvolutionCampaignPlanner
    from evolution_v2.common import atomic_write_json, read_json
    from evolution_v2.legacy import EvolutionStore
    from evolution_v2.local_planning import local_plan_endpoint
    from evolution_v2.manager import EvolutionManager
    config = {"url": args.endpoint, "model": args.model}
    local_plan_endpoint(config)
    saved = read_json(manifest, {})
    expected = {"source": str(source), "objective": args.objective, "endpoint": args.endpoint, "model": args.model}
    if saved and any(saved.get(key) != value for key, value in expected.items()):
        parser.error("Saved acceptance identity differs from this invocation")
    record = saved or {**expected, "events": [], "tasks": [], "published": [], "scope": "real-local-campaign"}
    atomic_write_json(manifest, record)
    atomic_write_json(state / "agents.json", {"local_model": config})
    event_lock = threading.Lock()
    def event_sink(event):
        row = {"event": event.get("event"), "time_millis": event.get("timestamp_millis"),
               **{key: event.get("task", {})[key] for key in ("task_id", "status") if key in event.get("task", {})},
               **{key: event.get("metadata", {})[key] for key in
                  ("gate", "operation", "ok", "stage", "error_code", "effect", "tool_step", "attempt")
                  if key in event.get("metadata", {})}}
        with event_lock, (state / "task-events.jsonl").open("a", encoding="utf-8") as stream:
            stream.write(json.dumps(row, ensure_ascii=True) + "\n")
        print(json.dumps(row, ensure_ascii=True), flush=True)
    manager = EvolutionManager(source_root=source, store=EvolutionStore(state / "evolution"),
                               patch_agent=default_evolution_patch_agent, event_sink=event_sink)
    settings = {"enabled": True, "auto_start_tasks": True, "execution_mode": "serial"}
    atomic_write_json(manager.v2_store.paths["scheduler"] / "settings.json", settings)
    planner = EvolutionCampaignPlanner(manager, lambda: settings)
    goals = planner.goal_decomposition.goals
    goal = goals.create("real-local-campaign", "Local candidate workflow acceptance", args.objective, auto_start=True)
    campaign_id = goal["campaign_id"]
    record["campaign_id"] = campaign_id
    atomic_write_json(manifest, record)
    if args.revalidate_task:
        task = manager.require(args.revalidate_task)
        metadata = manager.v2_store.get_task_metadata(task.task_id)
        if metadata is None or metadata.campaign_id != campaign_id:
            parser.error("Revalidation task is outside this acceptance campaign")
        result = manager.revalidate_candidate(task.task_id)
        evidence = {"task_id": task.task_id, "status": result.status,
                    "error_code": result.last_error_code, "error": result.last_error,
                    "review": manager.task_metadata(task.task_id).get("review", {})}
        atomic_write_json(state / "semantic-revalidation.json", evidence)
        print(json.dumps(evidence, ensure_ascii=True))
        return 0 if result.status == "waiting_approval" else 1
    if args.inspect_task:
        task = manager.require(args.inspect_task)
        context = manager._implementation_context(task)
        evidence = {"task_id": task.task_id, "task_status": task.status,
                    "campaign_matches": context.get("campaign_id") == campaign_id,
                    "objective_matches": context.get("campaign_objective") == args.objective,
                    "node_id": context.get("node_id"), "proposal_title": context.get("proposal_title"),
                    "inference_calls": 0}
        atomic_write_json(state / "context-acceptance.json", evidence)
        print(json.dumps(evidence, ensure_ascii=True))
        return 0 if evidence["campaign_matches"] and evidence["objective_matches"] else 1
    if args.publish_task:
        task = manager.require(args.publish_task)
        metadata = manager.v2_store.get_task_metadata(task.task_id)
        if metadata is None or metadata.campaign_id != campaign_id:
            parser.error("Publication task is outside this acceptance campaign")
        result = manager.publish(task.task_id, task.approval_hash)
        record["published"] = [*record["published"], {"task_id": task.task_id, "url": result.pull_request_url, "head": result.candidate_commit}]
        record["tasks"] = [manager.require(row["task_id"]).public() for row in record["tasks"]]
        atomic_write_json(manifest, record)
        print(json.dumps(record["published"][-1], ensure_ascii=True))
        return 0
    recovered = manager.recover_interrupted(resume=False)
    if args.recover_only:
        evidence = {"recovered": recovered, "active_workers": manager.active_worker_count(),
                    "tasks": [{"task_id": task_id, "status": manager.require(task_id).status,
                               "error_code": manager.require(task_id).last_error_code,
                               "attempt_errors": [row.failure_code for row in manager.require(task_id).attempts]}
                              for task_id in recovered]}
        atomic_write_json(state / "controller-recovery.json", evidence)
        print(json.dumps(evidence, ensure_ascii=True))
        return 0 if evidence["active_workers"] == 0 else 1
    previous = None
    while True:
        planning = planner.tick()
        graph = manager.campaigns.durable.graph_store.load(manager.campaigns.durable.identity(campaign_id))
        if graph:
            manager.campaigns.tick(campaign_id)
            graph = manager.campaigns.durable.graph_store.load(manager.campaigns.durable.identity(campaign_id))
        tasks = []
        for node in (graph or {}).get("nodes", {}).values():
            task = manager.store.get(node["action"]["task_id"])
            if task:
                tasks.append(task)
        status = {"goal_status": goals.load(campaign_id)["status"],
                  "campaign_status": (graph or {}).get("status"),
                  "tasks": [{"task_id": task.task_id, "status": task.status, "error": task.last_error_code,
                             "attempts": len(task.attempts)} for task in tasks]}
        if status != previous:
            record.update(goal=goals.load(campaign_id), graph=graph, tasks=[task.public() for task in tasks])
            record["events"].append({"time_millis": int(time.time() * 1000), **status})
            atomic_write_json(manifest, record)
            print(json.dumps(status, ensure_ascii=True), flush=True)
            previous = status
        if not manager.active_worker_count():
            ready = [task for task in tasks if task.status == "waiting_approval"]
            if ready or record["published"]:
                record.update(candidate_ready=bool(ready), full_campaign_complete=False,
                              tasks=[task.public() for task in tasks], graph=graph)
                atomic_write_json(manifest, record)
                return 0
            if goals.load(campaign_id)["status"] in {"waiting", "local_model_unavailable"}:
                return 1
            if any(row.get("status") in {"waiting", "local_model_unavailable"} for row in planning.get("observations", [])):
                record["needs_observation"] = True
                atomic_write_json(manifest, record)
                return 1
        time.sleep(1)


if __name__ == "__main__":
    raise SystemExit(main())
