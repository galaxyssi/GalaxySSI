"""Candidate-blind, lossless source partitions for original-goal evidence review."""
from agent_task_dag import TaskDagError
from .common import model_context_json, sha256_text, stable_json
from .evidence_scope import compile_scopes, scope_source, strict_json, validate_scopes
from .original_goal_partition import parse_partition, partition_goal
from .original_goal_scope_audit import audit_scopes, validate_audit

CONTRACT = "galaxyssi.original-goal-requirements.v3"


def validate_requirements(value, goal, catalog):
    parts = value.get("parts") if isinstance(value, dict) else None
    if not isinstance(goal, str) or not goal.strip() or not isinstance(parts, list) or not parts or set(value) != {"parts"}:
        raise TaskDagError("Original-goal review requires a complete source partition")
    for part in parts:
        if (not isinstance(part, dict) or set(part) != {"source_quote", "field_ids"}
                or not isinstance(part["source_quote"], str) or not part["source_quote"].strip()
                or not isinstance(part["field_ids"], list)
                or any(not isinstance(key, str) or key not in catalog for key in part["field_ids"])
                or len(set(part["field_ids"])) != len(part["field_ids"])):
            raise TaskDagError("Original-goal partition contains invalid source or evidence references")
    if "".join(part["source_quote"] for part in parts) != goal:
        raise TaskDagError("Source quotes must reproduce the complete original goal exactly, in order")
    return parts


def compile_requirements(goal, catalog, infer, *, previous=None, observed=None):
    source = scope_source({"original_goal": goal}, catalog)
    digest = sha256_text(stable_json({"contract": CONTRACT, "source": source}))
    feedback = None
    clauses = None
    if isinstance(previous, dict) and previous.get("source_hash") == digest and "parts" in previous:
        clauses = parse_partition(previous["partition_response"], goal)
        requirements = {"part-" + str(index + 1): clause for index, clause in enumerate(clauses)}
        scopes = validate_scopes(strict_json(previous["scope_response"]), requirements, catalog)
        parts = validate_requirements(strict_json(previous["response"]), goal, catalog)
        if parts != [{"source_quote": quote, "field_ids": scopes[key]["field_ids"]} for key, quote in requirements.items()]:
            raise TaskDagError("Cached requirements differ from their original model observations")
        audit = validate_audit(previous["audit_response"], requirements, scopes, catalog)
        if all(row["sufficient"] for row in audit.values()) or not catalog:
            return {**previous, "parts": parts, "audit": audit}
        feedback = {"selected_fields": {key: row["field_ids"] for key, row in scopes.items()}, "sufficiency": audit}
    if len(model_context_json(source).encode("utf-8")) > 131072:
        raise TaskDagError("Complete original-goal source requires a larger planning path")
    record = {"contract": CONTRACT, "source_hash": digest}
    def retain(key, response):
        record[key] = response
        if observed:
            observed(dict(record))
    if clauses is None:
        clauses = partition_goal(goal, infer, lambda response: retain("partition_response", response))
    else:
        retain("partition_response", previous["partition_response"])
    requirements = {"part-" + str(index + 1): clause for index, clause in enumerate(clauses)}
    def scoped_infer(messages, **kwargs):
        if feedback:
            messages = [dict(message) for message in messages]
            payload = strict_json(messages[-1]["content"])
            payload["previous_insufficient_selection"] = feedback
            payload["original_goal"] = goal
            messages[-1]["content"] = model_context_json(payload)
            messages[0]["content"] += " Revise the prior insufficient selection using the original goal and independent sufficiency feedback; never weaken the goal."
        response = infer(messages, **kwargs)
        retain("scope_response", response)
        return response
    scopes = compile_scopes(requirements, catalog, scoped_infer)["scopes"]
    if not catalog:
        retain("scope_response", stable_json({"scopes": scopes}))
        audit = {key: {"sufficient": False, "missing_field_ids": [], "evidence": "No observed evidence fields are available"}
                 for key in requirements}
        retain("audit_response", stable_json({"clauses": audit}))
    else:
        audit = audit_scopes(goal, requirements, scopes, catalog, infer, lambda response: retain("audit_response", response))
    parts = [{"source_quote": quote, "field_ids": scopes[key]["field_ids"]} for key, quote in requirements.items()]
    response = stable_json({"parts": parts})
    return {**record, "response": response, "parts": validate_requirements({"parts": parts}, goal, catalog), "audit": audit}
