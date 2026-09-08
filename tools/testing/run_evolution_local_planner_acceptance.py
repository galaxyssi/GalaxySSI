"""Opt-in real local inference against a controlled failed campaign.

Uses the production planner, event ledger and proposal store. Child task outcomes
are controlled; this is not an end-to-end code development or publication test.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys
import time
from types import SimpleNamespace


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--outcome", choices=("transient", "cancelled"), default="transient")
    parser.add_argument("--max-decisions", type=int, default=1, help="Acceptance-run bound, not an Agent action budget")
    parser.add_argument("--allow-inference", action="store_true")
    args = parser.parse_args()
    if not args.allow_inference:
        parser.error("--allow-inference is required")
    if args.max_decisions < 1:
        parser.error("--max-decisions must be positive")
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
    from evolution_v2.models import EvolutionProposal
    from evolution_v2.storage import EvolutionV2Store

    store = EvolutionV2Store(state / "v2")
    store.save_proposal(EvolutionProposal("repair", "Repair documentation validation",
        "Repair documentation and verify the project without losing unfinished work",
        ["docs"], ["Documentation validation passes"]))
    children, started, audits, calls = {}, [], [], []

    def ensure(proposal, campaign_id, task_id):
        return children.setdefault(task_id, SimpleNamespace(task_id=task_id, status="proposed", last_error=""))

    def start(task_id):
        started.append(task_id)
        children[task_id].status = "running"
        return children[task_id]

    campaigns = CampaignManager(store, task_factory=None, task_ensurer=ensure,
        task_starter=start, task_getter=lambda key: children[key],
        run_ledger=AgentRunEventLedger(state / "runs.sqlite3"))
    campaign = campaigns.create("Local planner acceptance", "Repair documentation and pass validation", [
        {"node_id": "repair-docs", "proposal_id": "repair"},
        {"node_id": "verify", "proposal_id": "repair", "depends_on": ["repair-docs"]},
    ], auto_start_safe_nodes=True)
    campaigns.tick(campaign.campaign_id)
    child = children[started[0]]
    child.status = "failed" if args.outcome == "transient" else "cancelled"
    child.last_error = (
        "Validation failed because its dependency was temporarily unavailable. The dependency is now available; retry has not yet been attempted."
        if args.outcome == "transient" else
        "The worker was cancelled during host maintenance and cannot be restarted. Maintenance is complete. Documentation repair and downstream validation remain unfinished.")
    campaigns.tick(campaign.campaign_id)
    durable = campaigns.durable
    graph = lambda: durable.graph_store.load(durable.identity(campaign.campaign_id))
    before = graph()

    def infer(messages, **kwargs):
        began = time.monotonic()
        record = {"messages": messages}
        calls.append(record)
        try:
            record["response"] = infer_local_plan(messages, config={"url": args.endpoint, "model": args.model}, **kwargs)
            return record["response"]
        except Exception as exc:
            record["error_type"] = type(exc).__name__
            raise
        finally:
            record["elapsed_seconds"] = round(time.monotonic() - began, 3)
            atomic_write_json(state / "inference.json", calls)

    manager = SimpleNamespace(v2_store=store, campaigns=campaigns,
        audit=SimpleNamespace(append=lambda *args, **kwargs: audits.append({"args": args, "kwargs": kwargs})),
        policy=SimpleNamespace(decide=lambda *args: SimpleNamespace(allowed=True)))
    config = lambda: {"enabled": True, "auto_start_tasks": True}
    planner = EvolutionCampaignPlanner(manager, config, infer)
    attempts = []
    while True:
        result = planner.tick()
        observations = result.get("observations", [])
        if observations:
            attempts.append(result)
            atomic_write_json(state / "attempts.json", attempts)
            if observations[0].get("status") in {"applied", "waiting"} or len(calls) >= args.max_decisions:
                break
            # Reopen the service to test that validation feedback is durable.
            planner = EvolutionCampaignPlanner(manager, config, infer)
        time.sleep(1)
    after = graph()
    observations = result.get("observations", [])
    applied = bool(observations and observations[0].get("status") == "applied")
    preserved = after["objective"] == before["objective"] and after["status"] == "active"
    if applied:
        campaigns.tick(campaign.campaign_id)
    reopened = EvolutionCampaignPlanner(manager, config, infer)
    before_reopen = len(calls)
    reopened.tick()
    evidence = {"component_only": True, "model": args.model, "outcome": args.outcome, "result": result,
        "before": before, "after": after, "resumed": graph(), "audit": audits, "attempts": attempts,
        "inference_calls": len(calls), "child_starts": started,
        "decision_applied": applied, "objective_preserved": preserved,
        "passed": applied and preserved and len(calls) == before_reopen and len(started) == 2}
    atomic_write_json(state / "acceptance.json", evidence)
    print(json.dumps({key: evidence[key] for key in (
        "model", "result", "inference_calls", "decision_applied", "objective_preserved", "passed")}, indent=2))
    return 0 if evidence["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
