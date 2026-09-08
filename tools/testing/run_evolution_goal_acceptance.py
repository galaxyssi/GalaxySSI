"""Real local goal decomposition with controlled child task dispatch, not coding."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys
import time
from types import SimpleNamespace


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--objective", required=True)
    parser.add_argument("--allow-inference", action="store_true")
    args = parser.parse_args()
    if not args.allow_inference:
        parser.error("--allow-inference is required")
    source, state = args.source.resolve(), args.state.resolve()
    production = (Path(os.environ.get("APPDATA", Path.home() / ".local/share")) / "GalaxySSI").resolve()
    if state.exists() or state == production or production in state.parents:
        parser.error("Use a new isolated state directory")
    state.mkdir(parents=True)
    os.environ["GALAXYSSI_STATE_DIR"] = str(state)
    sys.path.insert(0, str(source / "apps/desktop/core/galaxyssi-link/backend"))
    from agent_run_kernel import AgentRunEventLedger
    from evolution_v2.campaigns import CampaignManager
    from evolution_v2.campaign_planner import EvolutionCampaignPlanner
    from evolution_v2.common import atomic_write_json
    from evolution_v2.local_planning import infer_local_plan
    from evolution_v2.storage import EvolutionV2Store

    store = EvolutionV2Store(state / "v2")
    children, starts, calls, audit = {}, [], [], []
    def ensure(proposal, campaign_id, task_id):
        return children.setdefault(task_id, SimpleNamespace(task_id=task_id, status="proposed", last_error=""))
    def start(task_id):
        starts.append(task_id)
        children[task_id].status = "running"
        return children[task_id]
    campaigns = CampaignManager(store, task_factory=None, task_ensurer=ensure, task_starter=start,
        task_getter=lambda key: children[key], run_ledger=AgentRunEventLedger(state / "runs.sqlite3"))
    manager = SimpleNamespace(v2_store=store, campaigns=campaigns,
        audit=SimpleNamespace(append=lambda *args, **kwargs: audit.append({"args": args, "kwargs": kwargs})),
        policy=SimpleNamespace(decide=lambda *args: SimpleNamespace(allowed=True)))
    def infer(messages, **kwargs):
        began = time.monotonic()
        record = {"messages": messages}
        calls.append(record)
        try:
            record["response"] = infer_local_plan(messages, config={"url": args.endpoint, "model": args.model}, **kwargs)
            return record["response"]
        except Exception as error:
            record["error_type"] = type(error).__name__
            raise
        finally:
            record["elapsed_seconds"] = round(time.monotonic() - began, 3)
            atomic_write_json(state / "inference.json", calls)
    config = lambda: {"enabled": True, "auto_start_tasks": True}
    planner = EvolutionCampaignPlanner(manager, config, infer)
    goals = planner.goal_decomposition.goals
    goal = goals.create("acceptance-request", "Real local goal planning", args.objective, auto_start=True)
    key = goal["campaign_id"]
    result = planner.tick()
    graph = campaigns.durable.graph_store.load(campaigns.durable.identity(key))
    if graph:
        campaigns.tick(key)
    reopened = EvolutionCampaignPlanner(manager, config, infer)
    reopened.tick()
    after = campaigns.durable.graph_store.load(campaigns.durable.identity(key))
    evidence = {"component_only": True, "model": args.model, "goal": goals.public(goals.load(key)),
        "result": result, "graph": graph, "after_dispatch": after, "inference_calls": len(calls),
        "child_starts": starts, "audit": audit,
        "passed": bool(graph and graph["objective"] == args.objective and len(calls) == 1 and starts)}
    atomic_write_json(state / "acceptance.json", evidence)
    print(json.dumps({key: evidence[key] for key in ("model", "goal", "inference_calls", "passed")}, ensure_ascii=True, indent=2))
    return 0 if evidence["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
