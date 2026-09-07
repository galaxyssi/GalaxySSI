from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import tempfile
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from agent_run_kernel import AgentRunEventLedger
from evolution_v2.agent_adapters import default_evolution_patch_agent
from evolution_v2.campaigns import CampaignManager
from evolution_v2.legacy import EvolutionError
from evolution_v2.local_implementation import implementation_context, implementation_observer
from evolution_v2.manager import EvolutionManager
from evolution_v2.models import EvolutionProposal, TaskMetadata
from evolution_v2.storage import EvolutionV2Store


class ImplementationContextTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.store = EvolutionV2Store(self.root / "v2")
        self.store.save_proposal(EvolutionProposal("proposal", "Preserve the requested heading", "Append checklist", ["docs"], ["Pass"]))
        self.tasks = {}
        self.campaigns = self.build_campaigns()
        self.manager = object.__new__(EvolutionManager)
        self.manager.v2_store = self.store
        self.manager.campaigns = self.campaigns

    def build_campaigns(self):
        def ensure(proposal, campaign_id, task_id):
            task = self.tasks.setdefault(task_id, SimpleNamespace(task_id=task_id, status="proposed", last_error=""))
            self.store.save_task_metadata(TaskMetadata(task_id, campaign_id=campaign_id))
            return task
        return CampaignManager(self.store, task_factory=None, task_getter=lambda key: self.tasks[key],
                               task_starter=lambda key: self.tasks[key], task_ensurer=ensure,
                               run_ledger=AgentRunEventLedger(self.root / "runs.sqlite3"))

    def create_task(self, objective="Keep every original requirement and all existing content"):
        campaign = self.campaigns.create("Campaign", objective,
            [{"node_id": "one", "proposal_id": "proposal", "depends_on": []}], auto_start_safe_nodes=True)
        self.campaigns.tick(campaign.campaign_id)
        return campaign, self.tasks[self.campaigns.get(campaign.campaign_id).nodes[0].task_id]

    def test_parent_goal_and_title_survive_real_ledger_reopen(self):
        campaign, task = self.create_task()
        self.manager.campaigns = self.build_campaigns()
        context = self.manager._implementation_context(task)
        self.assertEqual(campaign.objective, context["campaign_objective"])
        self.assertEqual("Preserve the requested heading", context["proposal_title"])
        self.assertEqual("one", context["node_id"])

    def test_foreign_task_is_rejected_without_parent_context_leak(self):
        campaign, task = self.create_task()
        self.store.save_task_metadata(TaskMetadata("foreign", campaign_id=campaign.campaign_id))
        with self.assertRaises(EvolutionError) as caught:
            self.manager._implementation_context(SimpleNamespace(task_id="foreign"))
        self.assertEqual("campaign_context_conflict", caught.exception.code)
        self.assertNotIn(campaign.objective, str(caught.exception))

    def test_missing_campaign_or_proposal_is_not_silently_ignored(self):
        _, task = self.create_task()
        with patch.object(self.campaigns.durable.graph_store, "task_context", return_value=None), self.assertRaises(EvolutionError) as caught:
            self.manager._implementation_context(task)
        self.assertEqual("campaign_context_unavailable", caught.exception.code)
        with patch.object(self.store, "get_proposal", return_value=None), self.assertRaises(EvolutionError):
            self.manager._implementation_context(task)

    def test_manual_task_has_no_unrelated_goal(self):
        self.create_task()
        self.assertEqual({}, self.manager._implementation_context(SimpleNamespace(task_id="manual")))

    def test_context_is_nested_and_thread_isolated(self):
        barrier = threading.Barrier(2)
        def observe(value):
            with implementation_observer(threading.Event(), lambda *a, **k: None, context={"campaign_objective": value}):
                barrier.wait()
                self.assertEqual(value, implementation_context()["campaign_objective"])
                with implementation_observer(threading.Event(), lambda *a, **k: None):
                    self.assertEqual({}, implementation_context())
                return implementation_context()["campaign_objective"]
        with ThreadPoolExecutor(2) as pool:
            self.assertEqual(["first", "second"], list(pool.map(observe, ["first", "second"])))
        self.assertEqual({}, implementation_context())

    def test_default_adapter_delivers_full_goal_to_local_model_without_expanding_scope(self):
        campaign, task = self.create_task()
        task.attempts, task.scope, task.acceptance = [], ["docs"], ["Pass"]
        task.reproduction_steps, task.problem, task.agent_id = [], "Append checklist", "auto"
        context = self.manager._implementation_context(task)
        with patch("evolution_v2.agent_adapters.EvolutionV2Store", return_value=self.store), patch(
            "evolution_v2.local_implementation.implement_locally", return_value="done") as local:
            with implementation_observer(threading.Event(), lambda *a, **k: None, context=context):
                result = default_evolution_patch_agent(task, SimpleNamespace(number=1, agent_id="local-llm"), self.root, "")
        self.assertEqual("done", result)
        self.assertIn(campaign.objective, local.call_args.args[0])
        self.assertIn("Preserve the requested heading", local.call_args.args[0])
        self.assertIn("binding requirements applicable to this child task", local.call_args.args[0])
        self.assertIn("do not replace the original goal", local.call_args.args[0])
        self.assertNotIn("context only", local.call_args.args[0])
        self.assertEqual(["docs"], local.call_args.kwargs["scope"])

    def test_external_implementers_receive_the_same_binding_parent_constraints(self):
        campaign, task = self.create_task("Add a Named section while preserving all original content")
        task.attempts, task.scope, task.acceptance = [], ["docs"], ["Pass"]
        task.reproduction_steps, task.problem = [], "A weaker child proposal"
        context = self.manager._implementation_context(task)
        for provider in ("codex", "hermes", "claude", "openclaw"):
            task.agent_id = provider
            with self.subTest(provider=provider), patch("evolution_v2.agent_adapters.EvolutionV2Store", return_value=self.store), patch(
                    "agent_gateway.ask_evolution_agent", return_value="done") as remote:
                with implementation_observer(threading.Event(), lambda *a, **k: None, context=context):
                    default_evolution_patch_agent(task, SimpleNamespace(number=1, agent_id=provider), self.root, "")
                prompt = remote.call_args.args[1]
                self.assertIn(campaign.objective, prompt)
                self.assertIn("binding requirements applicable to this child task", prompt)
                self.assertIn("report that conflict", prompt)
                self.assertNotIn("context only", prompt)
                self.assertEqual(self.root, remote.call_args.kwargs["working_directory"])

    def test_context_lookup_does_not_load_all_nodes(self):
        _, task = self.create_task()
        with patch.object(self.campaigns.durable.graph_store, "_read", side_effect=AssertionError("Full graph read")):
            self.assertEqual("one", self.manager._implementation_context(task)["node_id"])
        with self.campaigns.durable.graph_store.ledger.transaction(write=False) as connection:
            from agent_task_dag_store import _TASK_ID_SQL
            plan = connection.execute(f"""EXPLAIN QUERY PLAN SELECT data_json FROM agent_task_dag_nodes
                WHERE run_id=? AND {_TASK_ID_SQL}=? LIMIT 2""",
                ("campaign", task.task_id)).fetchall()
        self.assertIn("agent_task_dag_task_context", str(plan))

    def test_thousand_node_campaign_reads_only_the_requested_task(self):
        campaign = self.campaigns.create("Large campaign", "Preserve the full objective",
            [{"node_id": f"node-{index}", "proposal_id": "proposal", "depends_on": []} for index in range(1000)])
        identity = self.campaigns.durable.identity(campaign.campaign_id)
        task_id = self.campaigns.durable.graph_store.load(identity)["nodes"]["node-731"]["action"]["task_id"]
        self.store.save_task_metadata(TaskMetadata(task_id, campaign_id=campaign.campaign_id))
        with patch.object(self.campaigns.durable.graph_store, "_read", side_effect=AssertionError("Full graph read")):
            context = self.manager._implementation_context(SimpleNamespace(task_id=task_id))
        self.assertEqual("node-731", context["node_id"])
        self.assertEqual("Preserve the full objective", context["campaign_objective"])

    def test_indexed_lookup_checks_complete_root_identity(self):
        from dataclasses import replace
        from agent_run_kernel import AgentRunIdentityConflict
        campaign, task = self.create_task()
        identity = self.campaigns.durable.identity(campaign.campaign_id)
        with self.assertRaises(AgentRunIdentityConflict):
            self.campaigns.durable.graph_store.task_context(replace(identity, client_route_id="foreign"), task.task_id)

    def test_unrelated_corrupt_node_does_not_block_context_or_index_creation(self):
        from agent_task_dag_store import DurableTaskDag
        campaign, task = self.create_task()
        store = self.campaigns.durable.graph_store
        with store.ledger.transaction() as connection:
            connection.execute("DROP INDEX agent_task_dag_task_context")
            connection.execute("INSERT INTO agent_task_dag_nodes VALUES (?, ?, ?)",
                               (campaign.campaign_id, "corrupt", "not json"))
        reopened = DurableTaskDag(store.ledger)
        context = reopened.task_context(self.campaigns.durable.identity(campaign.campaign_id), task.task_id)
        self.assertEqual("one", context["node"]["node_id"])


if __name__ == "__main__":
    unittest.main()
