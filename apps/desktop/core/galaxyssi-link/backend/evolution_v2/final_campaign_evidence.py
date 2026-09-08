"""Fresh immutable evidence for original-goal verification, not child completion claims."""
from __future__ import annotations

from agent_task_dag import TaskDagError
from .acceptance_evidence import collect_evidence
from .candidate_acceptance import CONTRACT
from .common import sha256_text, stable_json
from .final_retirement_evidence import collect_retirement_evidence
from .goal_text_contract import evaluate_contract
from .integration_verification import verify_integration
from .preservation_contract import evaluate_preservation


def awaiting_final_review(graph):
    return (isinstance(graph, dict) and graph.get("status") == "active" and bool(graph.get("nodes"))
            and all(node["status"] == "completed" for node in graph["nodes"].values()))


def collect_final_evidence(planner, campaign_id):
    manager = planner.manager
    durable = manager.campaigns.durable
    graph = durable.graph_store.load(durable.identity(campaign_id))
    if not awaiting_final_review(graph):
        raise TaskDagError("The original campaign still has unfinished work or is not active")
    goal = planner.goal_decomposition.goals.load(campaign_id)
    if goal and (goal["objective"] != graph["objective"] or goal["status"] != "materialized"):
        raise TaskDagError("The original goal changed or is no longer active")
    evidence = planner.checkpoints.evidence(graph, durable.proposal_store)
    candidates, integrations = {}, {}
    for key, node in graph["nodes"].items():
        task = manager.require(node["action"]["task_id"])
        if not task.pull_request_url or key not in evidence["publications"]:
            raise TaskDagError("Final publication verification needs observed PR evidence for every retained task")
        candidate = collect_evidence(task, manager.source_root, task.candidate_commit,
                                     manager._implementation_context(task), manager.runner)
        previous = manager.task_metadata(task.task_id)["review"]["acceptance"]
        digest = sha256_text(stable_json({"contract": CONTRACT, "evidence": candidate}))
        if previous.get("contract") != CONTRACT or previous.get("evidence_hash") != digest:
            raise TaskDagError("Candidate acceptance identity changed; retained acceptance must be revalidated")
        checks = evaluate_contract(previous["goal_contract"], candidate["files"])
        preservation = evaluate_preservation(previous["preservation_contract"], candidate["files"])
        if (previous.get("verdict") != "pass" or previous["goal_contract"].get("issues")
                or any(not row["passed"] for row in [*checks, *preservation])):
            raise TaskDagError("Immutable candidate constraints do not pass")
        candidates[key] = {**candidate, "current_literal_checks": checks,
                           "current_preservation_checks": preservation,
                           "previous_acceptance_is_not_final_goal_acceptance": True}
        watch = manager.ci_watches.get(task.task_id)
        if not isinstance(watch, dict) or not isinstance(watch.get("snapshot"), dict):
            raise TaskDagError("Current publication watch is unavailable")
        integrations[key] = verify_integration(manager, task.task_id, watch["snapshot"])
        if not integrations[key]["passed"]:
            raise TaskDagError("Current integration verification did not pass: " + integrations[key]["reason"])
    proofs, history = collect_retirement_evidence(planner, campaign_id, graph)
    return {**evidence, "candidates": candidates, "current_integrations": integrations,
            "retirement_proofs": proofs, "applied_replanning_history": history}
