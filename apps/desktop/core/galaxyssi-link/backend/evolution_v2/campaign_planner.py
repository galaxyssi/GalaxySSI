"""Observe failed DAGs, ask a private local model, then apply a fresh decision."""
from __future__ import annotations

import re
import threading

from .campaign_replanning import apply_decision, observation_id, parse_decision, planning_messages
from .common import atomic_write_json, now_millis, read_json, sha256_text
from .local_planning import LocalPlannerUnavailable, infer_local_plan
from .os_owner import OwnerLocks
from .planning_feedback import feedback_message, rejected_decision


class EvolutionCampaignPlanner:
    def __init__(self, manager, config, infer=None):
        self.manager = manager
        self.config = config
        self.infer = infer or infer_local_plan
        self.root = manager.v2_store.root / "campaign-planning"
        self.owners = OwnerLocks(self.root / "owners", re.compile(r"plan-v1-[0-9a-f]{64}"))
        self._stop = threading.Event()
        self._wake = threading.Event()
        self._tick_lock = threading.Lock()
        self._thread = None

    def start(self):
        self._stop.clear()
        if self._thread is not None and self._thread.is_alive():
            self._wake.set()
            return
        self._thread = threading.Thread(target=self._loop, name="evolution-campaign-planner", daemon=True)
        self._thread.start()

    def stop(self):
        self._stop.set()
        self._wake.set()
        if self._thread is not None and self._thread is not threading.current_thread():
            self._thread.join(timeout=2)

    def _enabled(self):
        config = self.config()
        return config.get("enabled", False) and config.get("auto_start_tasks", True) and not self._stop.is_set()

    def tick(self):
        if not self._enabled():
            return {"status": "disabled", "observations": []}
        if not self._tick_lock.acquire(blocking=False):
            return {"status": "busy", "observations": []}
        results = []
        try:
            durable = self.manager.campaigns.durable
            if durable is None:
                return {"status": "unavailable", "observations": []}
            for campaign in durable.iter_campaigns(recoverable_only=True):
                if not self._enabled():
                    break
                if campaign.status != "attention_required" or not campaign.auto_start_safe_nodes:
                    continue
                key = sha256_text(campaign.campaign_id)
                with self.owners.hold("plan-v1-" + key, create=True) as owned:
                    if not owned:
                        continue
                    result = self._plan(durable, campaign.campaign_id, key)
                    if result is not None:
                        results.append(result)
            return {"status": "observed", "observations": results}
        finally:
            self._tick_lock.release()

    def _plan(self, durable, campaign_id, key):
        graph = durable.graph_store.load(durable.identity(campaign_id))
        if graph is None or graph["status"] != "active" or not any(n["status"] == "failed" for n in graph["nodes"].values()):
            return None
        observed = observation_id(graph)
        path = self.root / (key + ".json")
        previous = read_json(path, {})
        previous = previous if isinstance(previous, dict) else {}
        same = previous.get("observation_id") == observed
        if same and (previous.get("status") in {"waiting", "applied"} or previous.get("next_poll", 0) > now_millis()):
            return None
        record = {"campaign_id": campaign_id, "observation_id": observed, "status": "reasoning", "next_poll": 0}
        if same and isinstance(previous.get("validation_feedback"), dict):
            record["validation_feedback"] = previous["validation_feedback"]
        stage, response, decision = "prepare", None, None
        try:
            # A saved decision survives process death before its DAG transaction commits.
            decision = previous.get("decision") if same else None
            if decision is None:
                atomic_write_json(path, record)
                self.manager.audit.append("campaign_planning_started", payload={"campaign_id": campaign_id})
                messages = planning_messages(graph, durable.proposal_store)
                if record.get("validation_feedback"):
                    messages.append(feedback_message(record["validation_feedback"]))
                stage = "infer"
                response = self.infer(messages)
                stage = "parse"
                decision = parse_decision(response)
                record["decision"] = decision
                stage = "persist"
                atomic_write_json(path, record)
            else:
                record["decision"] = decision
            if not self._enabled():
                return {"campaign_id": campaign_id, "status": "deferred"}
            stage = "validate"
            result = apply_decision(durable, campaign_id, observed, decision, validate_proposal=self._validate_proposal)
            stage = "persist"
            record.pop("validation_feedback", None)
            record.update(result)
            atomic_write_json(path, record)
            self.manager.audit.append("campaign_plan_observed", payload={"campaign_id": campaign_id, **result})
            return {"campaign_id": campaign_id, **result}
        except Exception as error:
            # Invalid decisions are re-requested; transport errors are observations, not task failures.
            feedback = rejected_decision(error, stage=stage, response=response, decision=decision)
            if feedback is not None:
                record["validation_feedback"] = feedback
            record.pop("decision", None)
            status = "local_model_unavailable" if isinstance(error, LocalPlannerUnavailable) else "planning_error"
            record.update(status=status, error_type=type(error).__name__, next_poll=now_millis() + 60_000)
            atomic_write_json(path, record)
            self.manager.audit.append("campaign_planning_error", payload={"campaign_id": campaign_id,
                                                                         "error_type": type(error).__name__})
            return {"campaign_id": campaign_id, "status": status, "error_type": type(error).__name__}

    def _validate_proposal(self, proposal):
        from agent_task_dag import TaskDagError
        decision = self.manager.policy.decide(proposal.scope, proposal.risk_level)
        if not decision.allowed:
            raise TaskDagError("Model proposal does not satisfy the existing source policy")

    def _loop(self):
        while not self._stop.is_set():
            try:
                self.tick()
            except Exception as error:
                self.manager.audit.append("campaign_planner_error", payload={"error_type": type(error).__name__})
            self._wake.wait(timeout=30)
            self._wake.clear()
