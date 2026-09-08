"""Real durable DAG transitions with isolated verifier/provider observations."""
from copy import deepcopy
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

from agent_run_kernel import AgentRunEventLedger
from agent_task_dag import TaskDagError
from evolution_v2.campaigns import CampaignManager
from evolution_v2.campaign_planner import EvolutionCampaignPlanner
from evolution_v2.common import atomic_write_json, read_json, sha256_text, stable_json
from evolution_v2.campaign_replanning import observation_id
from evolution_v2.final_campaign_verification import finish_verified
from evolution_v2.models import EvolutionProposal
from evolution_v2.storage import EvolutionV2Store


class FinalCampaignSchedulerTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.store = EvolutionV2Store(self.root / "v2")
        self.store.save_proposal(EvolutionProposal("p", "Work", "Original scope", ["docs"], ["Complete result"]))
        self.tasks, self.starts = {}, []
        def ensure(proposal, campaign_id, task_id):
            return self.tasks.setdefault(task_id, SimpleNamespace(task_id=task_id, status="proposed"))
        def start(task_id):
            self.starts.append(task_id)
            self.tasks[task_id].status = "running"
        self.campaigns = CampaignManager(self.store, task_factory=Mock(), task_ensurer=ensure,
            task_getter=lambda key: self.tasks[key], task_starter=start,
            run_ledger=AgentRunEventLedger(self.root / "runs.sqlite3"))
        self.manager = SimpleNamespace(v2_store=self.store, campaigns=self.campaigns, audit=Mock(),
            policy=SimpleNamespace(decide=lambda *args: SimpleNamespace(allowed=True)))
        self.config = {"enabled": True, "auto_start_tasks": True}
        self.infer = Mock(return_value=self.answer())
        self.planner = EvolutionCampaignPlanner(self.manager, lambda: self.config, self.infer)
        self.key = self.campaigns.create("Campaign", "Preserve the COMPLETE original objective", [
            {"node_id": "done", "proposal_id": "p"}], auto_start_safe_nodes=True).campaign_id
        self.campaigns.tick(self.key)
        self.tasks[self.starts[0]].status = "completed"
        self.campaigns.tick(self.key)
        self.evidence = {"graph": self.graph(), "publications": {"done": {"title": "Actual publication"}},
                         "candidates": {"done": {"files": {"docs/result.md": "Actual contents"}}},
                         "current_integrations": {"done": {"passed": True}}}
        self.install_collector()

    def install_collector(self):
        self.collect = Mock(side_effect=lambda key: deepcopy(self.evidence))
        self.planner.final_verification.collect = self.collect

    def graph(self):
        durable = self.campaigns.durable
        return durable.graph_store.load(durable.identity(self.key))

    def record(self):
        return read_json(self.planner.final_verification.path(self.key))

    @staticmethod
    def answer(verdict="pass"):
        return json.dumps({"assessments": {"original-goal": {"verdict": verdict,
            "evidence": "Observed source, publication and original scope"}}})

    def reopen(self):
        self.planner = EvolutionCampaignPlanner(self.manager, lambda: self.config, self.infer)
        self.install_collector()

    def test_scheduler_verifies_original_goal_and_finishes_without_new_task(self):
        result = self.planner.tick()
        self.assertEqual("completed", result["observations"][0]["status"])
        self.assertEqual("completed", self.graph()["status"])
        self.assertEqual(1, len(self.starts))
        self.assertIn(self.evidence["graph"]["objective"], str(self.infer.call_args.args))
        self.assertEqual(2, self.collect.call_count)
        self.assertEqual(1, len(list((self.planner.root / "final-proofs").glob("*.json"))))

    def test_completed_campaign_restart_does_not_reverify_or_reexecute(self):
        self.planner.tick()
        self.reopen()
        self.planner.tick()
        self.assertEqual(1, self.infer.call_count)
        self.collect.assert_not_called()
        self.assertEqual(1, len(self.starts))

    def test_final_observation_cannot_replan_a_changed_graph(self):
        result = self.planner._plan(self.campaigns.durable, self.key, "changed",
            final_observation={"observation_id": "stale", "assessment": {"verdict": "fail"}})
        self.assertEqual("deferred", result["status"])
        self.infer.assert_not_called()
        self.assertEqual(1, len(self.starts))

    def test_process_death_after_saved_review_resumes_without_another_inference(self):
        with patch("evolution_v2.final_campaign_verification.finish_verified", side_effect=SystemExit("death")):
            with self.assertRaises(SystemExit):
                self.planner.tick()
        self.assertEqual("reviewed", self.record()["status"])
        self.reopen()
        self.planner.tick()
        self.assertEqual("completed", self.graph()["status"])
        self.assertEqual(1, self.infer.call_count)

    def test_process_death_after_finish_does_not_finish_twice(self):
        def crash(*args):
            finish_verified(*args)
            raise SystemExit("after transaction")
        with patch("evolution_v2.final_campaign_verification.finish_verified", side_effect=crash):
            with self.assertRaises(SystemExit):
                self.planner.tick()
        self.reopen()
        self.planner.tick()
        self.assertEqual("completed", self.graph()["status"])
        self.assertEqual(1, self.infer.call_count)

    def test_pause_during_review_prevents_completion(self):
        def infer(*args, **kwargs):
            self.campaigns.durable.control(self.key, "pause", "pause-during-review")
            return self.answer()
        self.infer.side_effect = infer
        self.planner.tick()
        self.assertEqual("paused", self.graph()["status"])
        self.assertEqual("verification_error", self.record()["status"])

    def test_disable_during_review_defers_and_can_resume_saved_observation(self):
        def infer(*args, **kwargs):
            self.config["enabled"] = False
            return self.answer()
        self.infer.side_effect = infer
        self.planner.tick()
        self.assertEqual("active", self.graph()["status"])
        self.config["enabled"] = True
        self.infer.side_effect = None
        self.reopen()
        self.planner.tick()
        self.assertEqual("completed", self.graph()["status"])
        self.assertEqual(1, self.infer.call_count)

    def test_changed_publication_blocks_completion(self):
        changed = deepcopy(self.evidence)
        changed["publications"]["done"]["title"] = "Changed after review"
        self.collect.side_effect = [self.evidence, changed]
        self.planner.tick()
        self.assertEqual("active", self.graph()["status"])
        self.assertIn("Evidence changed", self.record()["error"])

    def test_missing_candidate_evidence_never_calls_model(self):
        self.collect.side_effect = TaskDagError("Missing immutable candidate")
        self.planner.tick()
        self.planner.tick()
        self.infer.assert_not_called()
        self.assertEqual(1, self.collect.call_count)
        self.assertEqual("active", self.graph()["status"])

    def test_malformed_review_is_not_a_candidate_failure_or_completion(self):
        self.infer.return_value = '{"assessments":{}}'
        self.planner.tick()
        self.assertEqual("verification_error", self.record()["status"])
        self.assertEqual(1, self.infer.call_count)
        self.assertEqual("completed", self.graph()["nodes"]["done"]["status"])
        self.assertEqual(self.infer.return_value, self.record()["response"])
        record = self.record()
        record["next_poll"] = 0
        atomic_write_json(self.planner.final_verification.path(self.key), record)
        self.infer.return_value = self.answer()
        self.reopen()
        self.planner.tick()
        self.assertEqual("completed", self.graph()["status"])
        self.assertEqual(2, self.infer.call_count)
        attempts = [read_json(path) for path in (self.planner.root / "final-attempts").glob("*.json")]
        self.assertTrue(any(row.get("response") == '{"assessments":{}}'
                            and row.get("status") == "verification_error" for row in attempts))

    def test_final_failure_can_add_missing_work_without_replacing_completed_nodes(self):
        self.infer.side_effect = [self.answer("fail"), json.dumps({"operation": "revise", "reason": "Complete missing original work",
            "supersede_ids": [], "nodes": [{"node_id": "done", "proposal_id": "p", "depends_on": []},
            {"node_id": "followup", "depends_on": ["done"], "proposal": {"title": "Missing work",
             "problem": "Satisfy original requirement", "scope": ["docs"], "acceptance": ["Verified original result"]}}]})]
        before = deepcopy(self.graph()["nodes"]["done"])
        self.planner.tick()
        self.assertEqual(before, self.graph()["nodes"]["done"])
        self.assertEqual("pending", self.graph()["nodes"]["followup"]["status"])
        self.assertEqual(1, len(self.starts))
        self.assertIn("final_goal_observation", str(self.infer.call_args.args))

    def test_inconclusive_wait_is_persisted_without_repeated_model_calls(self):
        self.infer.side_effect = [self.answer("inconclusive"), json.dumps({"operation": "wait", "reason": "Need better evidence"})]
        self.planner.tick()
        self.assertEqual(2, self.infer.call_count)
        record = self.record()
        record["next_poll"] = 0
        atomic_write_json(self.planner.final_verification.path(self.key), record)
        self.reopen()
        self.planner.tick()
        self.assertEqual(2, self.infer.call_count)
        self.assertEqual("active", self.graph()["status"])

    def test_cached_top_level_pass_does_not_override_failed_raw_assessment(self):
        record = {"contract": "galaxyssi.campaign-final-verification.v1", "status": "reviewed", "next_poll": 0,
                  "reviewer_id": "injected-v1",
                  "observation_id": observation_id(self.graph()), "evidence_hash": sha256_text(stable_json(self.evidence)),
                  "assessment": {"verdict": "pass"}, "response": self.answer("fail")}
        atomic_write_json(self.planner.final_verification.path(self.key), record)
        self.infer.return_value = json.dumps({"operation": "wait", "reason": "Missing work"})
        self.planner.tick()
        self.assertEqual("active", self.graph()["status"])
        self.assertEqual(1, self.infer.call_count)

    def test_replanning_cannot_remove_completed_work_to_claim_success(self):
        self.infer.side_effect = [self.answer("fail"), json.dumps({"operation": "revise", "reason": "Drop completed work",
            "nodes": [], "supersede_ids": ["done"]})]
        before = deepcopy(self.graph())
        result = self.planner.tick()
        self.assertEqual(before, self.graph())
        self.assertEqual("planning_error", result["observations"][-1]["status"])

    def test_manual_campaign_does_not_auto_finish(self):
        self.config["auto_start_tasks"] = False
        self.planner.tick()
        self.infer.assert_not_called()
        self.assertEqual("active", self.graph()["status"])

    def test_changing_verifier_invalidates_cached_failure_and_wait(self):
        self.infer.side_effect = [self.answer("inconclusive"), json.dumps({"operation": "wait", "reason": "Need capable verifier"})]
        self.planner.tick()
        self.config["final_verifier_revision"] = "replacement-local-verifier"
        self.infer.side_effect = None
        self.infer.return_value = self.answer()
        self.reopen()
        self.planner.tick()
        self.assertEqual(3, self.infer.call_count)
        self.assertEqual("completed", self.graph()["status"])

    def test_verifier_changed_during_inference_cannot_complete(self):
        def infer(*args, **kwargs):
            self.config["final_verifier_revision"] = "changed-during-request"
            return self.answer()
        self.infer.side_effect = infer
        self.planner.tick()
        self.assertEqual("active", self.graph()["status"])
        self.assertIn("configuration changed", self.record()["error"])

    def test_production_verifier_never_sends_private_evidence_to_a_cloud_url(self):
        from evolution_v2.local_planning import infer_local_plan
        self.planner.infer = infer_local_plan
        config = {"url": "https://cloud.example/v1/chat/completions", "model": "remote-model"}
        with patch("agent_config.local_model_config", return_value=config), \
                patch("evolution_v2.local_planning.http.client.HTTPSConnection") as connection:
            self.planner.tick()
        connection.assert_not_called()
        self.assertEqual("verification_error", self.record()["status"])
        self.assertEqual("LocalPlannerUnavailable", self.record()["error_type"])
        self.assertEqual("active", self.graph()["status"])
