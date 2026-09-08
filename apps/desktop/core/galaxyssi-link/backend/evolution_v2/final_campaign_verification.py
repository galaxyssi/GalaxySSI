"""Durable final-goal observation and completion in the existing campaign scheduler."""
from agent_task_dag import TaskDagError
from .campaign_owner import campaign_operation
from .campaign_replanning import observation_id
from .common import atomic_write_json, now_millis, read_json, sha256_text, stable_json
from .final_campaign_evidence import awaiting_final_review, collect_final_evidence
from .final_campaign_review import parse_final_review, review_final_evidence
from .local_planning import infer_local_plan


CONTRACT = "galaxyssi.campaign-final-verification.v1"


@campaign_operation
def finish_verified(durable, campaign_id, graph, proof_id, enabled):
    if not enabled() or durable.graph_store.load(durable.identity(campaign_id)) != graph:
        raise TaskDagError("Campaign changed or verification was disabled before completion")
    return durable.control.__wrapped__(durable, campaign_id, "finish", "final-" + proof_id,
                                      evidence="Fresh original-goal and integration verification: " + proof_id)


class FinalCampaignVerification:
    def __init__(self, planner):
        self.planner = planner

    def path(self, campaign_id):
        return self.planner.root / ("final-" + sha256_text(campaign_id) + ".json")

    def collect(self, campaign_id):
        return collect_final_evidence(self.planner, campaign_id)

    def retain_attempt(self, record):
        attempt = {key: value for key, value in record.items() if key != "next_poll"}
        identity = sha256_text(stable_json(attempt))
        atomic_write_json(self.planner.root / "final-attempts" / (identity + ".json"), attempt)

    def reviewer(self):
        if self.planner.infer is infer_local_plan:
            from agent_config import local_model_config
            config = dict(local_model_config())
            identity = sha256_text(stable_json({key: config.get(key) for key in ("url", "model")}))
            return identity, lambda messages, **kwargs: infer_local_plan(messages, config=config, **kwargs)
        return self.planner.config().get("final_verifier_revision", "injected-v1"), self.planner.infer

    def observe(self, campaign_id, graph):
        if not awaiting_final_review(graph) or not self.planner._enabled():
            return None
        reviewer_id, infer = self.reviewer()
        path = self.path(campaign_id)
        observed = observation_id(graph)
        previous = read_json(path, {})
        if not isinstance(previous, dict):
            previous = {}
        same = (previous.get("contract") == CONTRACT and previous.get("observation_id") == observed
                and previous.get("reviewer_id") == reviewer_id)
        if same and previous.get("next_poll", 0) > now_millis():
            return None
        record = {"contract": CONTRACT, "campaign_id": campaign_id, "observation_id": observed,
                  "reviewer_id": reviewer_id, "status": "collecting", "next_poll": 0}
        try:
            evidence = self.collect(campaign_id)
            if evidence["graph"] != graph:
                raise TaskDagError("Campaign changed during final evidence collection")
            digest = sha256_text(stable_json(evidence))
            record.update(evidence=evidence, evidence_hash=digest)
            if not self.planner._enabled():
                return {"campaign_id": campaign_id, "status": "deferred"}
            if (same and previous.get("evidence_hash") == digest and previous.get("response")
                    and previous.get("status") in {"reviewed", "rejected"}):
                # Reparse persisted output; a cached top-level pass alone is never completion proof.
                assessment = parse_final_review(previous["response"])
                record.update(response=previous["response"], assessment=assessment)
            else:
                record["status"] = "reasoning"
                atomic_write_json(path, record)
                self.planner.manager.audit.append("campaign_final_verification_started", payload={"campaign_id": campaign_id})
                def observed_response(response):
                    record["response"] = response
                    self.retain_attempt(record)
                    atomic_write_json(path, record)
                record.update(review_final_evidence(evidence, infer, observed=observed_response))
            record["status"] = "reviewed"
            atomic_write_json(path, record)
            if not self.planner._enabled():
                return {"campaign_id": campaign_id, "status": "deferred"}
            if self.collect(campaign_id) != evidence:
                raise TaskDagError("Evidence changed during final review; no completion recorded")
            if self.reviewer()[0] != reviewer_id:
                raise TaskDagError("Final verifier configuration changed during review")
            proof = {key: value for key, value in record.items() if key not in {"status", "next_poll"}}
            proof_id = sha256_text(stable_json(proof))
            atomic_write_json(self.planner.root / "final-proofs" / (proof_id + ".json"), proof)
            verdict = record["assessment"]["verdict"]
            record.update(proof_id=proof_id, next_poll=now_millis() + 60000)
            if verdict == "pass":
                result = finish_verified(self.planner.manager.campaigns.durable, campaign_id, graph,
                                         proof_id, self.planner._enabled)
                record["status"] = result.status
            else:
                record["status"] = "rejected"
            atomic_write_json(path, record)
            self.planner.manager.audit.append("campaign_final_verification_observed", payload={
                "campaign_id": campaign_id, "verdict": verdict, "proof_id": proof_id, "status": record["status"]})
            result = {"campaign_id": campaign_id, "status": record["status"], "proof_id": proof_id}
            if verdict != "pass":
                result["final_observation"] = {"proof_id": proof_id, "assessment": record["assessment"],
                    "observation_id": observed, "original_goal": graph["objective"],
                    "completed_children_are_preserved": True}
            return result
        except Exception as error:
            record.update(status="verification_error", error_type=type(error).__name__,
                          error=str(error), next_poll=now_millis() + 60000)
            self.retain_attempt(record)
            atomic_write_json(path, record)
            self.planner.manager.audit.append("campaign_final_verification_error", payload={
                "campaign_id": campaign_id, "error_type": type(error).__name__})
            return {"campaign_id": campaign_id, "status": "verification_error", "error_type": type(error).__name__}
