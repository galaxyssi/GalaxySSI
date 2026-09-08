"""Opt-in final-goal review of an isolated campaign using the production evidence path."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys
import time


def final_review_schema():
    from evolution_v2.final_campaign_review import final_review_schema as schema
    return schema()


def parse_final_review(response):
    from evolution_v2.final_campaign_review import parse_final_review as parse
    return parse(response)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--finish", action="store_true", help="Record completion only after a fresh pass")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    state = args.state.resolve()
    saved = json.loads((state / "acceptance.json").read_text(encoding="utf-8"))
    production = (Path(os.environ.get("APPDATA", Path.home())) / "GalaxySSI").resolve()
    source = Path(saved["source"]).resolve()
    if state == production or state.is_relative_to(production) or state == source or state.is_relative_to(source):
        parser.error("Use the existing isolated acceptance state, never production state")
    os.environ["GALAXYSSI_STATE_DIR"] = str(state)
    os.environ["GALAXYSSI_CONFIG_PATH"] = str(state / "agents.json")
    sys.path.insert(0, str(root / "apps/desktop/core/galaxyssi-link/backend"))
    from evolution_v2.campaign_planner import EvolutionCampaignPlanner
    from evolution_v2.common import atomic_write_json, read_json, sha256_text, stable_json
    from evolution_v2.final_campaign_evidence import collect_final_evidence
    from evolution_v2.final_campaign_review import review_final_evidence
    from evolution_v2.final_campaign_verification import finish_verified
    from evolution_v2.legacy import EvolutionStore
    from evolution_v2.local_planning import infer_local_plan, local_plan_endpoint
    from evolution_v2.manager import EvolutionManager

    config = {"url": args.endpoint, "model": args.model}
    local_plan_endpoint(config)
    manager = EvolutionManager(source_root=source, store=EvolutionStore(state / "evolution"))
    planner = EvolutionCampaignPlanner(manager, lambda: {"enabled": False})
    durable = manager.campaigns.durable
    campaign_id = saved["campaign_id"]
    evidence = collect_final_evidence(planner, campaign_id)
    if evidence["graph"]["objective"] != saved["objective"]:
        raise ValueError("The original acceptance goal changed")
    record = {"campaign_id": campaign_id, "contract": "galaxyssi.local-campaign-final-test.v2",
              "evidence": evidence, "status": "reasoning", "finish_requested": args.finish}
    output = state / "completion-verification.json"
    previous = read_json(output, None)
    if previous is not None:
        atomic_write_json(state / "completion-attempts" / (sha256_text(stable_json(previous)) + ".json"), previous)
    def observed(response):
        record["response"] = response
        atomic_write_json(output, record)
    print("Starting fresh local final-goal review", flush=True)
    started = time.monotonic()
    try:
        record.update(review_final_evidence(evidence,
            lambda messages, **kwargs: infer_local_plan(messages, config=config, **kwargs), observed=observed))
    except Exception as error:
        record.update(status="verification_error", error_type=type(error).__name__, error=str(error))
        atomic_write_json(output, record)
        raise
    record.update(seconds=time.monotonic() - started, status="reviewed")
    atomic_write_json(output, record)
    if record["assessment"]["verdict"] != "pass":
        print(json.dumps(record["assessment"], ensure_ascii=True), flush=True)
        return 1
    if collect_final_evidence(planner, campaign_id) != evidence:
        raise ValueError("Evidence changed during final review; no completion recorded")
    proof_id = sha256_text(stable_json(record))
    atomic_write_json(state / "completion-proofs" / (proof_id + ".json"), record)
    if args.finish:
        result = finish_verified(durable, campaign_id, evidence["graph"], proof_id, lambda: True)
        record["campaign_status"] = result.status
        from campaign_acceptance_report import snapshot
        saved.update(snapshot(planner.goal_decomposition.goals.load(campaign_id),
            durable.graph_store.load(durable.identity(campaign_id)), manager.store.get, manager.active_worker_count(), {},
            durable.published_outcome))
        saved["final_verification_proof"] = proof_id
        atomic_write_json(state / "acceptance.json", saved)
    record.update(status="verified", proof_id=proof_id)
    atomic_write_json(output, record)
    print(json.dumps({key: value for key, value in record.items() if key not in {"evidence", "response"}}, ensure_ascii=True), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
