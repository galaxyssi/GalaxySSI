from __future__ import annotations

from copy import deepcopy
import json
from types import SimpleNamespace
import threading
import unittest
from unittest.mock import patch

from evolution_v2.agent_adapters import default_evolution_patch_agent
from evolution_v2.campaign_replanning import apply_decision, observation_id
from evolution_v2.local_implementation import implementation_observer
from evolution_v2.manager import EvolutionManager
from evolution_v2.models import TaskMetadata
from evolution_v2.replacement_context import read_replacement_context, with_replacement_context
from evolution_v2.legacy import EvolutionError
from test_evolution_v2 import test_campaign_planner as fixtures


class ReplacementContextTests(unittest.TestCase):
    setUp = fixtures.CampaignPlannerTests.setUp
    graph = fixtures.CampaignPlannerTests.graph
    revision = fixtures.CampaignPlannerTests.revision

    def context(self, node):
        return read_replacement_context(self.store, self.campaign.campaign_id, node["action"]["recovery_context"])

    def replace(self):
        before = self.graph()
        decision = {"operation": "replace", "node_id": "a", "reason": "Preserve the original file instead of overwriting it"}
        result = apply_decision(self.campaigns.durable, self.campaign.campaign_id, observation_id(before), decision)
        return before, result["replacement_node_id"]

    def test_replacement_records_actual_observation_and_reason_atomically_in_dag(self):
        before, fresh = self.replace()
        graph = self.graph()
        context = self.context(graph["nodes"][fresh])
        self.assertEqual(before["revision"], context["observed_revision"])
        self.assertEqual("model-plan-" + observation_id(before), context["operation_id"])
        self.assertEqual(before["nodes"]["a"]["result"], context["superseded"][0]["observation"])
        self.assertEqual(self.child, context["superseded"][0]["task_id"])
        self.assertIn("instead of overwriting", context["decision_reason"])
        self.assertNotIn("recovery_context", graph["nodes"]["b"]["action"])
        self.assertEqual(before["objective"], graph["objective"])

    def test_model_revise_and_manual_revise_both_carry_recovery_evidence(self):
        before = self.graph()
        decision = self.revision()
        apply_decision(self.campaigns.durable, self.campaign.campaign_id, observation_id(before), decision)
        graph = self.graph()
        self.assertEqual("Dependency unavailable", self.context(graph["nodes"]["repair"])["superseded"][0]["observation"]["error"])
        rows = [{"node_id": "manual-repair", "proposal_id": "proposal"},
                {"node_id": "b", "proposal_id": "proposal", "depends_on": ["manual-repair"]}]
        self.campaigns.durable.revise(self.campaign.campaign_id, rows, graph["revision"], "manual-change",
                                     supersede_ids=["repair"], evidence="Use a smaller repair step")
        updated = self.context(self.graph()["nodes"]["manual-repair"])
        self.assertEqual("repair", updated["superseded"][0]["node_id"])
        self.assertEqual("Use a smaller repair step", updated["decision_reason"])
        self.assertNotIn("recovery_context", updated["superseded"][0])

    def test_later_revision_preserves_existing_started_node_context(self):
        _, fresh = self.replace()
        self.campaigns.tick(self.campaign.campaign_id)
        before = self.graph()
        original = deepcopy(before["nodes"][fresh]["action"])
        self.campaigns.durable.revise(self.campaign.campaign_id, [
            {"node_id": fresh, "proposal_id": "proposal"},
            {"node_id": "b", "proposal_id": "proposal", "depends_on": [fresh]},
            {"node_id": "extra", "proposal_id": "proposal", "depends_on": ["b"]}],
            before["revision"], "extend", evidence="Add follow-up validation")
        self.assertEqual(original, self.graph()["nodes"][fresh]["action"])

    def test_context_is_independent_of_retired_task_mutation_and_no_recursive_copy(self):
        _, fresh = self.replace()
        before = self.graph()
        original = deepcopy(before["nodes"][fresh]["action"]["recovery_context"])
        self.tasks[self.child].last_error = "Later unrelated update"
        self.assertEqual(original, self.graph()["nodes"][fresh]["action"]["recovery_context"])
        specs = [{"node_id": "new-child", "action": {"task_id": "new-task", "proposal_id": "proposal"}}]
        _, pending = with_replacement_context(before, specs, [fresh], "Next observed repair", "op-2", self.campaign.campaign_id)
        self.assertNotIn("recovery_context", pending[1]["superseded"][0])
        self.assertEqual(before, self.graph())

    def test_reopened_indexed_context_reaches_implementation_prompt(self):
        from agent_task_dag_store import DurableTaskDag
        _, fresh = self.replace()
        self.campaigns.tick(self.campaign.campaign_id)
        node = self.graph()["nodes"][fresh]
        task = self.tasks[node["action"]["task_id"]]
        self.store.save_task_metadata(TaskMetadata(task.task_id, campaign_id=self.campaign.campaign_id))
        manager = object.__new__(EvolutionManager)
        manager.v2_store, manager.campaigns = self.store, self.campaigns
        durable = self.campaigns.durable
        durable.graph_store = DurableTaskDag(durable.graph_store.ledger)
        with patch.object(durable.graph_store, "_read", side_effect=AssertionError("Must not load entire graph")):
            context = manager._implementation_context(task)
        task.attempts, task.scope, task.acceptance = [], ["docs"], ["Preserve original"]
        task.reproduction_steps, task.problem, task.agent_id = [], "Append", "auto"
        with patch("evolution_v2.agent_adapters.EvolutionV2Store", return_value=self.store), patch(
            "evolution_v2.local_implementation.implement_locally", return_value="observed") as local:
            with implementation_observer(threading.Event(), lambda *a, **k: None, context=context):
                default_evolution_patch_agent(task, SimpleNamespace(number=1, agent_id="local-llm"), self.root, "")
        prompt = local.call_args.args[0]
        self.assertIn("Dependency unavailable", prompt)
        self.assertIn("Preserve the original file instead of overwriting it", prompt)
        self.assertIn(self.child, prompt)
        self.assertIn(self.campaign.objective, prompt)

    def test_model_cannot_inject_its_own_recovery_observation(self):
        before = self.graph()
        decision = self.revision()
        decision["nodes"][0]["recovery_context"] = {"superseded": [{"observation": "Invented successful tests"}]}
        apply_decision(self.campaigns.durable, self.campaign.campaign_id, observation_id(before), decision)
        context = self.context(self.graph()["nodes"]["repair"])
        self.assertNotIn("Invented successful tests", json.dumps(context))
        self.assertIn("Dependency unavailable", json.dumps(context))

    def test_missing_foreign_or_modified_evidence_is_not_silently_ignored(self):
        _, fresh = self.replace()
        reference = self.graph()["nodes"][fresh]["action"]["recovery_context"]
        with self.assertRaises(EvolutionError):
            read_replacement_context(self.store, "another-campaign", reference)
        with self.assertRaises(EvolutionError):
            read_replacement_context(self.store, self.campaign.campaign_id, {**reference, "evidence_hash": "0" * 64})
        with self.assertRaises(EvolutionError) as caught:
            read_replacement_context(self.store, self.campaign.campaign_id, {**reference, "context_id": "0" * 64})
        self.assertEqual("campaign_context_unavailable", caught.exception.code)

    def test_many_replacements_share_one_evidence_record_not_repeated_log_copies(self):
        graph = self.graph()
        graph["nodes"]["a"]["result"]["error"] = "x" * 10000
        specs = [{"node_id": f"fresh-{index}", "action": {"task_id": f"task-{index}"}} for index in range(1000)]
        specs, pending = with_replacement_context(graph, specs, ["a"], "Split work", "mass-replan", self.campaign.campaign_id)
        self.assertLess(len(json.dumps(specs)), 300000)
        self.assertEqual(10000, len(pending[1]["superseded"][0]["observation"]["error"]))
        self.assertEqual(specs[0]["action"]["recovery_context"], specs[-1]["action"]["recovery_context"])

    def test_manual_revision_replay_after_later_replacement_keeps_original_command_identity(self):
        durable = self.campaigns.durable
        before = self.graph()
        rows = [{"node_id": "new", "proposal_id": "proposal"},
                {"node_id": "b", "proposal_id": "proposal", "depends_on": ["new"]}]
        durable.revise(self.campaign.campaign_id, rows, before["revision"], "first-revision",
                       supersede_ids=["a"], evidence="Repair first failure")
        middle = self.graph()
        next_rows = [{"node_id": "newer", "proposal_id": "proposal"},
                     {"node_id": "b", "proposal_id": "proposal", "depends_on": ["newer"]}]
        durable.revise(self.campaign.campaign_id, next_rows, middle["revision"], "second-revision",
                       supersede_ids=["new"], evidence="Refine plan")
        latest = self.graph()
        replay = durable.revise(self.campaign.campaign_id, rows, before["revision"], "first-revision",
                                supersede_ids=["a"], evidence="Repair first failure")
        self.assertEqual(middle["revision"], replay.revision)
        self.assertEqual(latest, self.graph())

    def test_operation_snapshot_rejects_foreign_root_identity(self):
        from dataclasses import replace
        from agent_run_kernel import AgentRunIdentityConflict
        _, _ = self.replace()
        durable = self.campaigns.durable
        identity = durable.identity(self.campaign.campaign_id)
        with self.assertRaises(AgentRunIdentityConflict):
            durable.graph_store.operation_snapshot(replace(identity, client_route_id="foreign"), "not-found")

    def test_interruption_after_evidence_write_before_dag_commit_is_replayable(self):
        before = self.graph()
        decision = self.revision()
        durable = self.campaigns.durable
        with patch.object(durable.graph_store, "apply", side_effect=SystemExit(23)), self.assertRaises(SystemExit):
            apply_decision(durable, self.campaign.campaign_id, observation_id(before), decision)
        self.assertEqual(before, self.graph())
        self.assertEqual(1, len(list((self.store.root / "recovery-contexts").glob("*.json"))))
        apply_decision(durable, self.campaign.campaign_id, observation_id(before), decision)
        self.assertIn("Dependency unavailable", json.dumps(self.context(self.graph()["nodes"]["repair"])))
        self.assertEqual(1, len(list((self.store.root / "recovery-contexts").glob("*.json"))))


if __name__ == "__main__":
    unittest.main()
