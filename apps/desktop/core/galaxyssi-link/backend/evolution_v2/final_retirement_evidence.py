"""Verify applied retirement history without claiming replaced failures were satisfied."""
from agent_task_dag import TaskDagError, canonical
from .checkpoint_planning import CHECKPOINT_CONTRACT, retirement_command
from .common import read_json, sha256_text, stable_json
from .replacement_context import read_replacement_context


def collect_retirement_evidence(planner, campaign_id, graph):
    if not graph["retired_ids"]:
        return {}, []
    durable = planner.manager.campaigns.durable
    history = durable.graph_store.retirement_history(durable.identity(campaign_id), graph)
    if {key for entry in history for key in entry["removed"]} != set(graph["retired_ids"]):
        raise TaskDagError("Retired work has no retained independent evidence in the applied history")
    checkpoint_ops = {entry["operation_id"]: entry for entry in history
                      if entry["operation_id"].startswith("checkpoint-")}
    proofs, covered = {}, set()
    for path in (planner.root / "checkpoint-proofs").glob("*.json"):
        proof = read_json(path)
        if not isinstance(proof, dict) or proof.get("campaign_id") != campaign_id:
            continue
        operation = "checkpoint-" + proof.get("observation_id", "")
        entry = checkpoint_ops.get(operation)
        if entry is None:
            continue
        if path.stem != sha256_text(stable_json(proof)):
            raise TaskDagError("Retirement proof content hash does not match")
        source = proof.get("evidence", {}).get("graph")
        ids = proof.get("decision", {}).get("node_ids", [])
        if (sha256_text(canonical(source)) != entry["observation_id"]
                or set(ids) != set(entry["removed"])):
            raise TaskDagError("Retirement proof does not match the applied observation")
        command = {"operation": "revise", **retirement_command(source, set(ids), path.stem)}
        if sha256_text(canonical(command)) != entry["command_sha256"]:
            continue  # Archived before a crash is not necessarily the applied proof.
        review = proof.get("retirement_proof", {})
        rows = review.get("assessments", {})
        proposals = proof["evidence"]["proposals"]
        required = {item for key in ids for item in
                    [key + ":task", *[f"{key}:criterion-{n}" for n in range(1, len(proposals[key]["acceptance"]) + 1)]]}
        if (proof.get("review_contract") != CHECKPOINT_CONTRACT or set(rows) != required
                or any(row.get("verdict") != "pass" for row in rows.values())):
            raise TaskDagError("Retired work requires current independent acceptance, not a legacy passing claim")
        if proof["evidence"].get("publications"):
            scoped = review.get("scoped_evidence", {})
            if (scoped.get("contract") != "galaxyssi.scoped-verification.v3"
                    or set(scoped.get("checks", {})) != required
                    or any(row.get("verdict") != "pass" for row in scoped["checks"].values())):
                raise TaskDagError("Retired publication requirements lack complete scoped verification")
        covered.add(operation)
        proofs[path.stem] = {"decision": proof["decision"], "retirement_proof": review}
    if covered != set(checkpoint_ops):
        raise TaskDagError("Satisfied-work retirement lacks its applied independent proof")
    for entry in history:
        if entry["operation_id"] in checkpoint_ops:
            continue
        entry["meaning"] = "superseded, not satisfied; final review must assess the unchanged original goal"
        for node in entry["introduced"].values():
            reference = node["action"].get("recovery_context")
            if reference is None:
                continue
            record = read_replacement_context(durable.proposal_store, campaign_id, reference)
            if (record["operation_id"] != entry["operation_id"]
                    or record["observed_revision"] != entry["observed_revision"]):
                raise TaskDagError("Replacement evidence does not match the applied revision")
            for source in record["superseded"]:
                removed = entry["removed"].get(source["node_id"])
                if removed is None or source != {"node_id": source["node_id"],
                        "task_id": removed["action"].get("task_id"), "status": removed["status"],
                        "observation": removed["result"], "checkpoint": removed["checkpoint"]}:
                    raise TaskDagError("Replacement evidence does not match the superseded observation")
    return proofs, history
