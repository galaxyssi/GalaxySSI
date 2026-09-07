from __future__ import annotations

import json
import unittest
from unittest.mock import patch

from agent_task_dag import TaskDagError
from evolution_v2.campaign_planner import EvolutionCampaignPlanner
from evolution_v2.common import now_millis
from evolution_v2.local_planning import LocalPlannerUnavailable
from evolution_v2.planning_feedback import rejected_decision
from test_evolution_v2 import test_campaign_planner as fixtures


class PlanningFeedbackTests(unittest.TestCase):
    setUp = fixtures.CampaignPlannerTests.setUp
    graph = fixtures.CampaignPlannerTests.graph
    revision = fixtures.CampaignPlannerTests.revision

    def next_tick(self):
        with patch("evolution_v2.campaign_planner.now_millis", return_value=now_millis() + 61_000):
            return self.planner.tick()

    def feedback(self):
        return json.loads(self.infer.call_args.args[0][-1]["content"])["validation_observation"]

    def test_invalid_shape_is_observed_after_restart_then_model_corrects(self):
        bad = json.dumps({"nodes": {}, "status": "active"})
        self.infer.return_value = bad
        before = self.graph()
        self.planner.tick()
        self.assertEqual(before, self.graph())
        self.planner = EvolutionCampaignPlanner(self.manager, lambda: self.config, self.infer)
        self.infer.return_value = json.dumps(self.revision())
        result = self.next_tick()
        self.assertEqual(bad, self.feedback()["previous_response"])
        self.assertIn("top-level 'operation' must be a string", self.feedback()["detail"])
        self.assertEqual("applied", result["observations"][0]["status"])
        self.assertEqual(["repair"], self.graph()["nodes"]["b"]["depends_on"])
        self.assertEqual("Repair and verify", self.graph()["objective"])

    def test_invalid_json_includes_location_not_a_generic_error_type(self):
        self.infer.return_value = "{broken"
        self.planner.tick()
        self.infer.return_value = '{"operation":"wait","reason":"Need evidence"}'
        self.next_tick()
        self.assertEqual("parse", self.feedback()["stage"])
        self.assertIn("line 1, column 2", self.feedback()["detail"])

    def test_exhausted_child_feedback_survives_restart_and_model_replaces_it(self):
        task = self.tasks[self.child]
        task.attempts, task.max_attempts = [object()] * 5, 5
        before = self.graph()
        result = self.planner.tick()
        self.assertEqual("planning_error", result["observations"][0]["status"])
        self.assertEqual(before, self.graph())
        self.assertEqual([self.child], self.starts)
        self.planner = EvolutionCampaignPlanner(self.manager, lambda: self.config, self.infer)
        self.infer.return_value = json.dumps({"operation": "replace", "node_id": "a", "reason": "Fresh work after local provider recovery"})
        result = self.next_tick()
        self.assertIn("child_attempts_exhausted", self.feedback()["detail"])
        self.assertEqual("applied", result["observations"][0]["status"])
        self.assertEqual("Repair and verify", self.graph()["objective"])
        self.campaigns.tick(self.campaign.campaign_id)
        self.assertEqual(2, len(self.starts))
        self.assertNotEqual(self.child, self.starts[-1])
        self.assertEqual(5, len(task.attempts))

    def test_cycle_validation_feedback_is_not_lost_across_transport_failure(self):
        cyclic = self.revision()
        cyclic["nodes"][0]["depends_on"] = ["b"]
        self.infer.return_value = json.dumps(cyclic)
        self.planner.tick()
        self.infer.side_effect = LocalPlannerUnavailable("offline")
        self.next_tick()
        self.infer.side_effect = None
        self.infer.return_value = json.dumps(self.revision())
        with patch("evolution_v2.campaign_planner.now_millis", return_value=now_millis() + 122_000):
            self.planner.tick()
        self.assertIn("cycle", self.feedback()["detail"])
        self.assertEqual(3, self.infer.call_count)
        self.assertEqual(2, self.graph()["revision"])

    def test_changed_graph_drops_old_feedback(self):
        self.infer.return_value = "not JSON"
        self.planner.tick()
        self.campaigns.revise(self.campaign.campaign_id, [
            {"node_id": "a", "proposal_id": "proposal"},
            {"node_id": "b", "proposal_id": "proposal", "depends_on": []},
        ], 1, "external-revision")
        self.infer.return_value = '{"operation":"wait","reason":"New evidence"}'
        self.planner.tick()
        self.assertEqual(2, self.infer.call_count)
        self.assertEqual(2, len(self.infer.call_args.args[0]))

    def test_infrastructure_exceptions_are_not_model_validation_observations(self):
        for error in (OSError("private path"), LocalPlannerUnavailable("private body")):
            self.assertIsNone(rejected_decision(error, stage="validate", response="{}", decision={}))
        self.assertIsNone(rejected_decision(TaskDagError("source failure"), stage="infer", response=None, decision=None))

    def test_large_invalid_reply_is_bounded_and_marked_truncated(self):
        value = rejected_decision(TaskDagError("x" * 5000), stage="validate", response="y" * 20000, decision=None)
        self.assertEqual(2048, len(value["detail"]))
        self.assertEqual(8192, len(value["previous_response"]))
        self.assertTrue(value["response_truncated"])

    def test_nested_operation_reports_the_wrong_field_before_missing_reason(self):
        for operation in ({"retry": {"node_id": "a"}}, ["retry"], None):
            self.infer.return_value = json.dumps({"operation": operation})
            with patch("evolution_v2.campaign_planner.now_millis", return_value=now_millis() + (self.infer.call_count + 1) * 61_000):
                self.planner.tick()
            record = next(self.planner.root.glob("*.json"))
            feedback = json.loads(record.read_text())["validation_feedback"]
            self.assertIn("top-level 'operation'", feedback["detail"])
            self.assertEqual("failed", self.graph()["nodes"]["a"]["status"])


if __name__ == "__main__":
    unittest.main()
