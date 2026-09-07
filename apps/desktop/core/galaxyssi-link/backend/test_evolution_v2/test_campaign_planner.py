from __future__ import annotations

import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

from agent_run_kernel import AgentRunEventLedger
from evolution_v2.campaigns import CampaignManager
from evolution_v2.campaign_planner import EvolutionCampaignPlanner
from evolution_v2.models import EvolutionProposal
from evolution_v2.storage import EvolutionV2Store


class CampaignPlannerTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.store = EvolutionV2Store(self.root / "v2")
        self.store.save_proposal(EvolutionProposal("proposal", "Improve", "Repair project", ["docs"], ["Pass tests"]))
        self.tasks, self.starts = {}, []
        def ensure(proposal, campaign_id, task_id):
            return self.tasks.setdefault(task_id, SimpleNamespace(task_id=task_id, status="proposed", last_error=""))
        def start(task_id):
            self.starts.append(task_id)
            self.tasks[task_id].status = "running"
            return self.tasks[task_id]
        self.campaigns = CampaignManager(self.store, task_factory=Mock(), task_ensurer=ensure,
                                         task_starter=start, task_getter=lambda key: self.tasks[key],
                                         run_ledger=AgentRunEventLedger(self.root / "runs.sqlite3"))
        self.manager = SimpleNamespace(v2_store=self.store, campaigns=self.campaigns, audit=Mock(),
                                       policy=SimpleNamespace(decide=lambda *args: SimpleNamespace(allowed=True)))
        self.config = {"enabled": True, "auto_start_tasks": True}
        self.infer = Mock(return_value=json.dumps({"operation": "retry", "node_id": "a", "reason": "Retry after corrected transient setup"}))
        self.planner = EvolutionCampaignPlanner(self.manager, lambda: self.config, self.infer)
        self.campaign = self.campaigns.create("Campaign", "Repair and verify", [
            {"node_id": "a", "proposal_id": "proposal"},
            {"node_id": "b", "proposal_id": "proposal", "depends_on": ["a"]},
        ], auto_start_safe_nodes=True)
        self.campaigns.tick(self.campaign.campaign_id)
        self.child = self.starts[0]
        self.tasks[self.child].status = "failed"
        self.tasks[self.child].last_error = "Dependency unavailable"
        self.campaigns.tick(self.campaign.campaign_id)

    def graph(self):
        durable = self.campaigns.durable
        return durable.graph_store.load(durable.identity(self.campaign.campaign_id))

    def revision(self):
        return {"operation": "revise", "reason": "Repair dependency before continuing original verification",
                "supersede_ids": ["a"], "nodes": [
                    {"node_id": "repair", "proposal": {"title": "Repair setup", "problem": "Diagnose dependency setup",
                                                          "scope": ["docs"], "acceptance": ["Dependency check succeeds"]}},
                    {"node_id": "b", "proposal_id": "proposal", "depends_on": ["repair"]}]}

    def test_observation_model_retry_and_next_tick_reuses_child(self):
        result = self.planner.tick()
        self.assertEqual("applied", result["observations"][0]["status"])
        self.assertEqual("pending", self.graph()["nodes"]["a"]["status"])
        self.campaigns.tick(self.campaign.campaign_id)
        self.assertEqual([self.child, self.child], self.starts)
        self.assertEqual(1, len(self.tasks))
        self.assertIn("Dependency unavailable", self.infer.call_args.args[0][1]["content"])
        self.assertEqual("pending", self.graph()["nodes"]["b"]["status"])

    def test_model_creates_new_proposal_and_preserves_goal_and_dependency(self):
        self.infer.return_value = json.dumps(self.revision())
        self.planner.tick()
        graph = self.graph()
        self.assertEqual("Repair and verify", graph["objective"])
        self.assertEqual(2, graph["revision"])
        self.assertEqual(["repair"], graph["nodes"]["b"]["depends_on"])
        self.assertEqual(["a"], graph["retired_ids"])
        proposal = self.store.get_proposal(graph["nodes"]["repair"]["action"]["proposal_id"])
        self.assertEqual("campaign_replanning", proposal.origin)
        self.assertEqual("campaign_reserved", proposal.status)
        from evolution_v2.scheduler import EvolutionScheduler
        original = self.store.get_proposal("proposal")
        original.status = "materialized"
        self.store.save_proposal(original)
        scheduler = object.__new__(EvolutionScheduler)
        scheduler.manager = self.manager
        self.assertIsNone(scheduler._next_proposal())
        self.campaigns.tick(self.campaign.campaign_id)
        self.assertEqual(2, len(self.tasks))

    def test_cycle_or_forbidden_scope_cannot_replace_failed_work(self):
        decision = self.revision()
        decision["nodes"][0]["depends_on"] = ["b"]
        self.infer.return_value = json.dumps(decision)
        before = self.graph()
        self.assertEqual("planning_error", self.planner.tick()["observations"][0]["status"])
        self.assertEqual(before, self.graph())
        self.assertEqual(1, len(self.store.list_proposals()))

    def test_pause_during_inference_discards_stale_model_action(self):
        def infer(messages):
            self.campaigns.control(self.campaign.campaign_id, "pause", "user-pause")
            return json.dumps({"operation": "retry", "node_id": "a", "reason": "Retry"})
        self.planner.infer = infer
        self.planner.tick()
        self.assertEqual("paused", self.graph()["status"])
        self.assertEqual("failed", self.graph()["nodes"]["a"]["status"])

    def test_wait_observation_is_not_sent_to_model_again_after_restart(self):
        self.infer.return_value = json.dumps({"operation": "wait", "reason": "Need new dependency evidence"})
        self.planner.tick()
        reopened = EvolutionCampaignPlanner(self.manager, lambda: self.config, self.infer)
        reopened.tick()
        self.infer.assert_called_once()

    def test_saved_decision_survives_interruption_before_dag_commit(self):
        with patch("evolution_v2.campaign_planner.apply_decision", side_effect=SystemExit(23)):
            with self.assertRaises(SystemExit):
                self.planner.tick()
        reopened = EvolutionCampaignPlanner(self.manager, lambda: self.config, self.infer)
        reopened.tick()
        self.infer.assert_called_once()
        self.assertEqual("pending", self.graph()["nodes"]["a"]["status"])

    def test_disabled_and_stopped_planner_do_not_infer(self):
        self.config["enabled"] = False
        self.assertEqual("disabled", self.planner.tick()["status"])
        self.config["enabled"] = True
        self.planner.stop()
        self.assertEqual("disabled", self.planner.tick()["status"])
        self.infer.assert_not_called()

    def test_bad_response_is_observed_without_marking_goal_complete_or_repeated_calls(self):
        self.infer.return_value = "not a decision"
        self.planner.tick()
        self.planner.tick()
        self.infer.assert_called_once()
        self.assertEqual("active", self.graph()["status"])
        self.assertEqual("failed", self.graph()["nodes"]["a"]["status"])

    def test_model_cannot_finish_the_goal_from_a_failed_observation(self):
        self.infer.return_value = json.dumps({"operation": "finish", "reason": "Pretend all done"})
        self.planner.tick()
        self.assertEqual("active", self.graph()["status"])

    def test_policy_rejection_leaves_original_graph_and_proposals(self):
        self.infer.return_value = json.dumps(self.revision())
        self.manager.policy.decide = lambda *args: SimpleNamespace(allowed=False)
        before = self.graph()
        self.planner.tick()
        self.assertEqual(before, self.graph())
        self.assertEqual(1, len(self.store.list_proposals()))

    def test_missing_local_model_preserves_failed_observation_for_later(self):
        from evolution_v2.local_planning import LocalPlannerUnavailable
        self.infer.side_effect = LocalPlannerUnavailable("Not configured")
        result = self.planner.tick()
        self.assertEqual("local_model_unavailable", result["observations"][0]["status"])
        self.assertEqual("failed", self.graph()["nodes"]["a"]["status"])

    def test_cancelled_child_requires_replacement_instead_of_unstartable_retry(self):
        from evolution_v2.campaign_replanning import apply_decision, observation_id
        from agent_task_dag import TaskDagError
        self.campaigns.control(self.campaign.campaign_id, "retry", "prepare-cancel", node_id="a", evidence="Test another outcome")
        self.campaigns.tick(self.campaign.campaign_id)
        self.tasks[self.child].status = "cancelled"
        self.campaigns.tick(self.campaign.campaign_id)
        before = self.graph()
        with self.assertRaises(TaskDagError):
            apply_decision(self.campaigns.durable, self.campaign.campaign_id, observation_id(before),
                           {"operation": "retry", "node_id": "a", "reason": "Try again"})
        self.assertEqual(before, self.graph())

    def test_evaluator_outage_rejects_replacement_and_returns_observation_for_retry(self):
        self.campaigns.control(self.campaign.campaign_id, "retry", "prepare-evaluation", node_id="a", evidence="Observe review outage")
        self.campaigns.tick(self.campaign.campaign_id)
        task = self.tasks[self.child]
        task.status = "blocked"
        task.last_error_code = "acceptance_review_unavailable"
        task.candidate_checkpoint = {"version": 1}
        task.candidate_commit = "a" * 40
        task.max_attempts, task.attempts = 1, [object()]
        self.campaigns.tick(self.campaign.campaign_id)
        before = self.graph()
        self.infer.return_value = json.dumps({"operation": "replace", "node_id": "a", "reason": "Misdiagnosed review outage"})
        result = self.planner.tick()
        self.assertEqual("planning_error", result["observations"][0]["status"])
        self.assertEqual(before, self.graph())
        self.assertEqual(1, len(self.store.list_proposals()))
        self.infer.return_value = json.dumps({"operation": "retry", "reason": "Resume review but omit identity"})
        with patch("evolution_v2.campaign_planner.now_millis", return_value=10**15):
            result = self.planner.tick()
        self.assertEqual("planning_error", result["observations"][0]["status"])
        self.planner = EvolutionCampaignPlanner(self.manager, lambda: self.config, self.infer)
        self.infer.return_value = json.dumps({"operation": "retry", "node_id": "a", "reason": "Resume review, not implementation"})
        with patch("evolution_v2.campaign_planner.now_millis", return_value=10**15 + 60_001):
            result = self.planner.tick()
        self.assertEqual("applied", result["observations"][0]["status"])
        self.assertIn("no usable verdict", self.infer.call_args.args[0][-1]["content"])
        self.assertIn("require a non-empty node_id", self.infer.call_args.args[0][-1]["content"])
        self.assertEqual("pending", self.graph()["nodes"]["a"]["status"])
        self.assertEqual(self.child, self.graph()["nodes"]["a"]["action"]["task_id"])
        self.assertEqual("pending", self.graph()["nodes"]["b"]["status"])

    def test_missing_retry_identity_is_returned_as_actionable_validation_feedback(self):
        self.infer.return_value = json.dumps({"operation": "retry", "reason": "Resume retained review"})
        before = self.graph()
        self.assertEqual("planning_error", self.planner.tick()["observations"][0]["status"])
        self.assertEqual(before, self.graph())
        self.infer.return_value = json.dumps({"operation": "wait", "reason": "Await evaluator availability"})
        with patch("evolution_v2.campaign_planner.now_millis", return_value=10**15):
            self.planner.tick()
        self.assertIn("require a non-empty node_id", self.infer.call_args.args[0][-1]["content"])


if __name__ == "__main__":
    unittest.main()
