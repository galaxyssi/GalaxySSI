from __future__ import annotations

from copy import deepcopy
import json
import unittest

from agent_task_dag import TaskDagError
from evolution_v2.campaign_planner import EvolutionCampaignPlanner
from evolution_v2.campaign_replanning import apply_decision, observation_id
from evolution_v2.planning_replacement import replacement_revision
from test_evolution_v2 import test_campaign_planner as fixtures


class PlanningReplacementTests(unittest.TestCase):
    setUp = fixtures.CampaignPlannerTests.setUp
    graph = fixtures.CampaignPlannerTests.graph

    def decision(self, **extra):
        return {"operation": "replace", "node_id": "a", "reason": "A fresh worker must finish the original objective", **extra}

    def test_cancelled_child_gets_fresh_identity_without_losing_dependents(self):
        self.campaigns.control(self.campaign.campaign_id, "retry", "prepare-cancel", node_id="a", evidence="Observe cancellation")
        self.campaigns.tick(self.campaign.campaign_id)
        self.tasks[self.child].status = "cancelled"
        self.campaigns.tick(self.campaign.campaign_id)
        before = self.graph()
        self.infer.return_value = json.dumps(self.decision())
        result = self.planner.tick()["observations"][0]
        fresh = result["replacement_node_id"]
        after = self.graph()
        self.assertEqual("replace", result["operation"])
        self.assertNotIn("a", after["nodes"])
        self.assertEqual(["a"], after["retired_ids"])
        self.assertEqual([fresh], after["nodes"]["b"]["depends_on"])
        self.assertEqual(before["objective"], after["objective"])
        self.assertEqual("proposal", after["nodes"][fresh]["action"]["proposal_id"])
        self.campaigns.tick(self.campaign.campaign_id)
        new_task = self.starts[-1]
        self.assertNotEqual(self.child, new_task)
        self.assertEqual("cancelled", self.tasks[self.child].status)
        self.assertEqual("pending", self.graph()["nodes"]["b"]["status"])
        reopened = EvolutionCampaignPlanner(self.manager, lambda: self.config, self.infer)
        reopened.tick()
        self.campaigns.tick(self.campaign.campaign_id)
        self.infer.assert_called_once()
        self.assertEqual(1, self.starts.count(new_task))

    def test_model_can_supply_new_scoped_work(self):
        proposal = {"title": "Repair setup", "problem": "Restore prerequisites", "scope": ["docs"], "acceptance": ["Validation succeeds"]}
        self.infer.return_value = json.dumps(self.decision(proposal=proposal))
        fresh = self.planner.tick()["observations"][0]["replacement_node_id"]
        saved = self.store.get_proposal(self.graph()["nodes"][fresh]["action"]["proposal_id"])
        self.assertEqual("campaign_reserved", saved.status)
        self.assertEqual(proposal["scope"], saved.scope)

    def test_replacement_is_still_subject_to_existing_source_policy(self):
        self.manager.policy.decide = lambda *args: type("Denied", (), {"allowed": False})()
        self.infer.return_value = json.dumps(self.decision(proposal={"title": "Change", "problem": "Work", "scope": ["outside"], "acceptance": ["Pass"]}))
        before = self.graph()
        self.assertEqual("planning_error", self.planner.tick()["observations"][0]["status"])
        self.assertEqual(before, self.graph())
        self.assertEqual(1, len(self.store.list_proposals()))

    def test_ids_are_deterministic_and_other_dependency_edges_survive(self):
        graph = self.graph()
        source = deepcopy(graph["nodes"]["b"])
        source.update(node_id="upstream", position=2, depends_on=[], status="completed")
        graph["nodes"]["upstream"] = source
        graph["nodes"]["a"]["depends_on"] = ["upstream"]
        graph["nodes"]["b"]["depends_on"] = ["a", "upstream"]
        before = deepcopy(graph)
        first = replacement_revision(graph, self.decision(), "campaign", "observation")
        self.assertEqual(first, replacement_revision(graph, self.decision(), "campaign", "observation"))
        rows = {row["node_id"]: row for row in first[0]["nodes"]}
        self.assertEqual(["upstream"], rows[first[1]]["depends_on"])
        self.assertEqual([first[1], "upstream"], rows["b"]["depends_on"])
        self.assertEqual(before, graph)

    def test_active_completed_uncertain_or_missing_nodes_cannot_be_replaced(self):
        for status in ("running", "completed", "uncertain", "pending"):
            graph = self.graph()
            graph["nodes"]["a"]["status"] = status
            with self.subTest(status=status), self.assertRaises(TaskDagError):
                replacement_revision(graph, self.decision(), "c", "o")
        with self.assertRaises(TaskDagError):
            replacement_revision(self.graph(), self.decision(node_id="missing"), "c", "o")

    def test_extra_fields_are_rejected_not_silently_ignored(self):
        with self.assertRaises(TaskDagError):
            replacement_revision(self.graph(), self.decision(nodes=[]), "c", "o")

    def test_replay_cannot_replace_a_second_time(self):
        before = self.graph()
        apply_decision(self.campaigns.durable, self.campaign.campaign_id, observation_id(before), self.decision())
        after = self.graph()
        with self.assertRaises(TaskDagError):
            apply_decision(self.campaigns.durable, self.campaign.campaign_id, observation_id(before), self.decision())
        self.assertEqual(after, self.graph())


if __name__ == "__main__":
    unittest.main()
