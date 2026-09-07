from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
import threading
from unittest.mock import Mock, patch

from agent_run_kernel import AgentRunEventLedger
from agent_task_dag import TaskDagError
from evolution_v2.campaigns import CampaignManager
from evolution_v2.models import EvolutionProposal
from evolution_v2.storage import EvolutionV2Store
from evolution_v2.manager import EvolutionManager
from evolution_v2.legacy import EvolutionStore, EvolutionTask, EvolutionError
from evolution_v2.models import TaskMetadata


def row(key="a", dependencies=()):
    return {"node_id": key, "proposal_id": "proposal", "depends_on": list(dependencies)}


class DurableCampaignTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.store = EvolutionV2Store(self.root / "v2")
        self.store.save_proposal(EvolutionProposal("proposal", "Improve", "Improve a project", ["docs"], ["Tests pass"]))
        self.tasks = {}
        self.starts = []
        self.created = []
        self.crash_after_create = False
        self.manager = self.build_manager()

    def build_manager(self):
        def ensure(proposal, campaign_id, task_id):
            if task_id not in self.tasks:
                self.created.append(task_id)
                self.tasks[task_id] = SimpleNamespace(task_id=task_id, status="proposed", last_error="")
                if self.crash_after_create:
                    raise RuntimeError("simulated process death after child persistence")
            return self.tasks[task_id]
        def start(task_id):
            self.starts.append(task_id)
            self.tasks[task_id].status = "running"
            return self.tasks[task_id]
        return CampaignManager(self.store, task_factory=lambda *_: self.fail("Legacy factory must not run"),
                               task_getter=lambda key: self.tasks[key], task_starter=start, task_ensurer=ensure,
                               run_ledger=AgentRunEventLedger(self.root / "runs.sqlite3"))

    def create(self, rows=None, auto=False):
        return self.manager.create("Campaign", "Improve and verify", rows or [row()], auto_start_safe_nodes=auto)

    def test_created_campaign_is_readable_after_store_reopen(self):
        campaign = self.create([row(), row("b", ["a"])])
        self.manager = self.build_manager()
        loaded = self.manager.get(campaign.campaign_id)
        self.assertEqual(campaign.campaign_id, loaded.campaign_id)
        self.assertEqual(1, loaded.revision)
        self.assertEqual(["ready", "pending"], [node.status for node in loaded.nodes])
        self.assertEqual([campaign.campaign_id], [item.campaign_id for item in self.manager.list()])

    def test_crash_after_child_creation_does_not_duplicate_child(self):
        campaign = self.create()
        self.crash_after_create = True
        with self.assertRaises(RuntimeError):
            self.manager.tick(campaign.campaign_id, start_ready=True)
        reserved = self.manager.get(campaign.campaign_id).nodes[0].task_id
        self.assertEqual([reserved], self.created)
        self.crash_after_create = False
        self.manager = self.build_manager()
        self.manager.tick(campaign.campaign_id, start_ready=True)
        self.assertEqual([reserved], self.created)
        self.assertEqual([reserved], self.starts)
        self.manager.tick(campaign.campaign_id, start_ready=True)
        self.assertEqual([reserved], self.starts)

    def test_recovered_reservation_without_child_uses_same_reserved_id(self):
        campaign = self.create()
        graph = self.manager.durable._apply(campaign.campaign_id, "claim", node_id="a", owner="dead")
        task_id = graph["nodes"]["a"]["action"]["task_id"]
        self.manager = self.build_manager()
        self.manager.tick(campaign.campaign_id, start_ready=True)
        self.assertEqual([task_id], self.created)
        self.assertEqual([task_id], self.starts)

    def test_pause_revision_resume_and_dependency_unlock(self):
        campaign = self.create([row(), row("b", ["a"])], auto=True)
        self.manager.control(campaign.campaign_id, "pause", "pause")
        self.manager.tick_active()
        self.assertEqual([], self.created)
        self.manager.revise(campaign.campaign_id, [row(), row("b", ["c"]), row("c", ["a"])], 1, "revise")
        self.manager.control(campaign.campaign_id, "resume", "resume")
        self.manager.tick_active()
        first = self.manager.get(campaign.campaign_id).nodes[0]
        self.tasks[first.task_id].status = "completed"
        self.manager.tick_active()
        states = {node.node_id: node.status for node in self.manager.get(campaign.campaign_id).nodes}
        self.assertEqual({"a": "completed", "b": "pending", "c": "running"}, states)
        self.assertEqual(2, len(self.created))

    def test_task_lookup_error_does_not_create_or_fail_another_task(self):
        campaign = self.create()
        self.manager.tick(campaign.campaign_id, start_ready=True)
        def unavailable(_):
            raise OSError("temporary read failure")
        self.manager.durable.task_getter = unavailable
        with self.assertRaises(OSError):
            self.manager.tick(campaign.campaign_id, start_ready=True)
        self.assertEqual(1, len(self.created))
        self.assertEqual("running", self.manager.get(campaign.campaign_id).nodes[0].status)

    def test_model_retry_reuses_task_after_observed_failure(self):
        campaign = self.create()
        self.manager.tick(campaign.campaign_id, start_ready=True)
        task_id = self.created[0]
        self.tasks[task_id].status = "failed"
        self.tasks[task_id].last_error = "Observed gate failure"
        self.manager.tick(campaign.campaign_id)
        self.assertEqual("failed", self.manager.get(campaign.campaign_id).nodes[0].status)
        self.manager.control(campaign.campaign_id, "retry", "retry", node_id="a", evidence="Model corrected dependency configuration")
        self.manager.tick(campaign.campaign_id, start_ready=True)
        self.assertEqual(1, len(self.created))
        self.assertEqual([task_id, task_id], self.starts)

    def test_published_child_does_not_complete_entire_goal_without_verification(self):
        campaign = self.create()
        self.manager.tick(campaign.campaign_id, start_ready=True)
        self.tasks[self.created[0]].status = "published"
        observed = self.manager.tick(campaign.campaign_id)
        self.assertEqual("awaiting_ci", observed.nodes[0].status)
        with self.assertRaises(TaskDagError):
            self.manager.control(campaign.campaign_id, "finish", "premature", evidence="PR was published")
        self.manager.durable.published_outcome = lambda task: {"stage": "completed", "integration_commit": "a" * 40}
        observed = self.manager.tick(campaign.campaign_id)
        self.assertEqual("awaiting_verification", observed.status)
        with self.assertRaises(TaskDagError):
            self.manager.control(campaign.campaign_id, "finish", "finish", evidence="")
        finished = self.manager.control(campaign.campaign_id, "finish", "finish", evidence="CI and acceptance verified")
        self.assertEqual("completed", finished.status)

    def test_exhausted_child_is_observed_without_starting_an_empty_attempt(self):
        campaign = self.create(auto=True)
        self.manager.tick(campaign.campaign_id)
        task = self.tasks[self.created[0]]
        task.status, task.attempts, task.max_attempts = "failed", [object()] * 5, 5
        task.last_error_code = "implementation_channel_failed"
        self.manager.tick(campaign.campaign_id)
        graph = self.manager.durable.graph_store.load(self.manager.durable.identity(campaign.campaign_id))
        result = graph["nodes"]["a"]["result"]
        self.assertFalse(result["retryable"])
        self.assertEqual(0, result["attempts_remaining"])
        self.assertEqual("child_attempts_exhausted", result["retry_blocker"])
        self.assertEqual("implementation_channel_failed", result["error_code"])
        self.manager.control(campaign.campaign_id, "retry", "old-retry", node_id="a", evidence="Persisted decision")
        self.manager = self.build_manager()
        for _ in range(3):
            self.manager.tick(campaign.campaign_id)
        self.assertEqual([task.task_id], self.starts)
        self.assertEqual("failed", self.manager.get(campaign.campaign_id).nodes[0].status)

    def test_retry_admission_rechecks_current_child_not_only_stale_graph(self):
        from evolution_v2.campaign_replanning import apply_decision, observation_id
        campaign = self.create(auto=True)
        self.manager.tick(campaign.campaign_id)
        task = self.tasks[self.created[0]]
        task.status, task.attempts, task.max_attempts = "failed", [object()] * 4, 5
        self.manager.tick(campaign.campaign_id)
        durable = self.manager.durable
        graph = durable.graph_store.load(durable.identity(campaign.campaign_id))
        self.assertTrue(graph["nodes"]["a"]["result"]["retryable"])
        task.attempts.append(object())
        with self.assertRaisesRegex(TaskDagError, "child_attempts_exhausted"):
            apply_decision(durable, campaign.campaign_id, observation_id(graph),
                           {"operation": "retry", "node_id": "a", "reason": "Retry after reconnect"})
        self.assertEqual(graph, durable.graph_store.load(durable.identity(campaign.campaign_id)))
        self.assertEqual([task.task_id], self.starts)

    def test_explicit_replacement_retains_goal_dependencies_and_exhausted_history(self):
        from evolution_v2.campaign_replanning import apply_decision, observation_id
        campaign = self.create([row(), row("b", ["a"])], auto=True)
        self.manager.tick(campaign.campaign_id)
        task = self.tasks[self.created[0]]
        task.status, task.attempts, task.max_attempts = "failed", [object()] * 5, 5
        self.manager.tick(campaign.campaign_id)
        durable = self.manager.durable
        before = durable.graph_store.load(durable.identity(campaign.campaign_id))
        apply_decision(durable, campaign.campaign_id, observation_id(before),
                       {"operation": "replace", "node_id": "a", "reason": "Fresh attempt after provider recovered"})
        self.manager.tick(campaign.campaign_id)
        after = durable.graph_store.load(durable.identity(campaign.campaign_id))
        self.assertEqual(before["objective"], after["objective"])
        self.assertIn("a", after["retired_ids"])
        replacement = after["nodes"]["b"]["depends_on"][0]
        self.assertEqual("running", after["nodes"][replacement]["status"])
        self.assertEqual("pending", after["nodes"]["b"]["status"])
        self.assertEqual(5, len(task.attempts))
        self.assertEqual("failed", task.status)
        self.assertEqual(2, len(self.tasks))

    def test_recovered_proposed_exhausted_child_does_not_start(self):
        campaign = self.create(auto=True)
        self.manager.tick(campaign.campaign_id)
        task = self.tasks[self.created[0]]
        task.status, task.attempts, task.max_attempts = "proposed", [object()] * 5, 5
        self.manager.tick(campaign.campaign_id)
        self.assertEqual([task.task_id], self.starts)
        graph = self.manager.durable.graph_store.load(self.manager.durable.identity(campaign.campaign_id))
        self.assertEqual("failed", graph["nodes"]["a"]["status"])
        self.assertEqual("child_attempts_exhausted", graph["nodes"]["a"]["result"]["retry_blocker"])

    def test_recovered_candidate_continues_at_attempt_limit_without_unlocking_dependents(self):
        campaign = self.create([row(), row("b", ["a"])], auto=True)
        self.manager.tick(campaign.campaign_id)
        task = self.tasks[self.created[0]]
        task.status, task.attempts, task.max_attempts = "proposed", [object()], 1
        task.candidate_checkpoint = {"version": 1}
        self.manager.tick(campaign.campaign_id)
        self.assertEqual([task.task_id, task.task_id], self.starts)
        self.assertEqual([task.task_id], self.created)
        states = {node.node_id: node.status for node in self.manager.get(campaign.campaign_id).nodes}
        self.assertEqual("pending", states["b"])

    def test_waiting_pr_blocks_only_its_dependents_and_deduplicates_checkpoints(self):
        campaign = self.create([row(), row("dependent", ["a"]), row("independent")], auto=True)
        self.manager.tick(campaign.campaign_id)
        first = self.manager.get(campaign.campaign_id).nodes[0].task_id
        self.tasks[first].status = "published"
        self.manager.durable.published_outcome = lambda task: {"stage": "awaiting_integration", "error": "Awaiting merge"}
        observed = self.manager.tick(campaign.campaign_id)
        self.assertEqual(["awaiting_integration", "pending", "running"], [n.status for n in observed.nodes])
        ledger = self.manager.durable.graph_store.ledger
        sequence = ledger.snapshot(campaign.campaign_id)["last_sequence"]
        self.manager.tick(campaign.campaign_id)
        self.assertEqual(sequence, ledger.snapshot(campaign.campaign_id)["last_sequence"])
        self.manager = self.build_manager()
        self.assertEqual("awaiting_integration", self.manager.get(campaign.campaign_id).nodes[0].status)
        self.manager.durable.published_outcome = lambda task: {"stage": "completed", "integration_commit": "b" * 40}
        self.manager.tick(campaign.campaign_id)
        self.assertEqual(["completed", "running", "running"], [n.status for n in self.manager.get(campaign.campaign_id).nodes])

    def test_closed_pr_failure_is_observed_before_replanning(self):
        campaign = self.create([row(), row("dependent", ["a"])], auto=True)
        self.manager.tick(campaign.campaign_id)
        self.tasks[self.created[0]].status = "published"
        self.manager.durable.published_outcome = lambda task: {"stage": "failed", "error": "PR closed without merge"}
        observed = self.manager.tick(campaign.campaign_id)
        self.assertEqual("attention_required", observed.status)
        self.assertEqual(["failed", "pending"], [n.status for n in observed.nodes])
        self.assertEqual("PR closed without merge", observed.nodes[0].error)

    def test_goal_finish_rechecks_published_evidence_instead_of_trusting_old_completion(self):
        campaign = self.create(auto=True)
        self.manager.tick(campaign.campaign_id)
        task = self.tasks[self.created[0]]
        task.status = "completed"
        task.pull_request_url = "https://github.com/galaxyssi/GalaxySSI/pull/42"
        waiting = self.manager.tick(campaign.campaign_id)
        self.assertEqual("awaiting_ci", waiting.nodes[0].status)
        self.manager.durable.published_outcome = lambda task: {"stage": "completed"}
        self.manager.tick(campaign.campaign_id)
        self.manager.durable.published_outcome = lambda task: {"stage": "awaiting_ci", "error": "New CI run is pending"}
        with self.assertRaisesRegex(TaskDagError, "New CI run is pending"):
            self.manager.control(campaign.campaign_id, "finish", "finish", evidence="Old CI was green")

    def test_goal_finish_requires_the_completed_task_record(self):
        campaign = self.create(auto=True)
        self.manager.tick(campaign.campaign_id)
        self.tasks[self.created[0]].status = "completed"
        self.manager.tick(campaign.campaign_id)
        self.tasks.clear()
        with self.assertRaisesRegex(TaskDagError, "evidence is unavailable"):
            self.manager.control(campaign.campaign_id, "finish", "finish", evidence="Task used to be complete")

    def test_manual_campaign_is_not_started_by_automatic_tick(self):
        campaign = self.create()
        self.assertEqual([], self.manager.tick_active())
        self.assertEqual([], self.created)
        self.assertEqual("ready", self.manager.get(campaign.campaign_id).status)

    def test_revision_conflict_is_reported_and_no_started_work_is_rewritten(self):
        campaign = self.create([row(), row("b")])
        self.manager.revise(campaign.campaign_id, [row(), row("c")], 1, "revision")
        with self.assertRaises(TaskDagError):
            self.manager.revise(campaign.campaign_id, [row()], 1, "stale")
        self.manager.tick(campaign.campaign_id, start_ready=True)
        with self.assertRaises(TaskDagError):
            self.manager.revise(campaign.campaign_id, [row()], 2, "remove-started")

    def test_production_ensurer_recovers_metadata_without_recreating_child(self):
        manager = object.__new__(EvolutionManager)
        manager._lock = threading.RLock()
        manager.store = EvolutionStore(self.root / "tasks")
        manager.v2_store = self.store
        task = EvolutionTask("child", "Improve project", [], ["docs"], ["Pass"], "low", 3, status="running")
        manager.store.save(task)
        manager.create_from_proposal = Mock(side_effect=AssertionError("Must not create again"))
        proposal = self.store.get_proposal("proposal")
        recovered = manager._ensure_campaign_task(proposal, "campaign", "child")
        self.assertEqual("running", recovered.status)
        self.assertEqual("campaign", self.store.get_task_metadata("child").campaign_id)
        manager.create_from_proposal.assert_not_called()

    def test_production_ensurer_rejects_foreign_campaign(self):
        manager = object.__new__(EvolutionManager)
        manager._lock = threading.RLock()
        manager.store = EvolutionStore(self.root / "tasks")
        manager.v2_store = self.store
        manager.store.save(EvolutionTask("child", "Improve project", [], ["docs"], ["Pass"], "low", 3))
        self.store.save_task_metadata(TaskMetadata(task_id="child", campaign_id="other"))
        with self.assertRaises(EvolutionError):
            manager._ensure_campaign_task(self.store.get_proposal("proposal"), "campaign", "child")

    def test_actual_api_revises_and_controls_the_persisted_graph(self):
        from evolution_v2.api import CampaignRevisionReq, CampaignControlReq, revise_campaign, control_campaign, get_campaign
        from test_evolution_v2.test_api import request_from
        campaign = self.create()
        runtime = SimpleNamespace(manager=SimpleNamespace(campaigns=self.manager))
        request = request_from("127.0.0.1")
        with patch("evolution_v2.api.evolution_v2_runtime", return_value=runtime):
            revised = revise_campaign(campaign.campaign_id, CampaignRevisionReq(
                operation_id="api-revise", expected_revision=1, nodes=[row(), row("b", ["a"])]), request)
            self.assertEqual(2, revised["revision"])
            paused = control_campaign(campaign.campaign_id, CampaignControlReq(operation_id="pause", operation="pause"), request)
            self.assertEqual("paused", paused["status"])
            self.assertEqual("paused", get_campaign(campaign.campaign_id, request)["status"])

    def test_campaign_api_retains_loopback_boundary(self):
        from fastapi import HTTPException
        from evolution_v2.api import CampaignControlReq, control_campaign
        from test_evolution_v2.test_api import request_from
        with patch("evolution_v2.api.evolution_v2_runtime") as runtime:
            with self.assertRaises(HTTPException) as failure:
                control_campaign("campaign", CampaignControlReq(operation_id="pause", operation="pause"), request_from("203.0.113.7"))
            self.assertEqual(403, failure.exception.status_code)
            runtime.assert_not_called()

    def test_production_starter_obeys_existing_evolution_capacity(self):
        manager = object.__new__(EvolutionManager)
        manager._lock = threading.RLock()
        manager._threads = {"other": SimpleNamespace(is_alive=lambda: True)}
        manager.v2_store = self.store
        manager.start = Mock(return_value="started")
        manager.require = Mock(return_value="queued")
        self.assertEqual("queued", manager._start_campaign_task("child"))
        manager.start.assert_not_called()
        manager._threads.clear()
        self.assertEqual("started", manager._start_campaign_task("child"))
        manager.start.assert_called_once_with("child")

    def test_disabled_scheduler_does_not_tick_campaigns(self):
        from evolution_v2.scheduler import EvolutionScheduler
        from test_evolution_v2.test_scheduler import FakeManager
        manager = FakeManager(self.root)
        manager.campaigns = SimpleNamespace(tick_active=Mock(return_value=[]))
        scheduler = EvolutionScheduler(manager)
        scheduler.run_due(force=True)
        manager.campaigns.tick_active.assert_not_called()
        scheduler.config["enabled"] = True
        scheduler.run_due(evolution_only=True)
        manager.campaigns.tick_active.assert_called_once()

    def test_scheduled_proposals_count_campaign_workers_toward_capacity(self):
        from evolution_v2.scheduler import EvolutionScheduler
        from test_evolution_v2.test_scheduler import FakeManager
        manager = FakeManager(self.root)
        manager.active_worker_count = lambda: 1
        scheduler = EvolutionScheduler(manager)
        self.assertEqual(0, scheduler._available_capacity({"active_evolutions": []}))
        scheduler.config.update(execution_mode="parallel", max_parallel_evolutions=2)
        self.assertEqual(1, scheduler._available_capacity({"active_evolutions": []}))

    def test_one_campaign_lookup_failure_does_not_stop_other_campaigns(self):
        bad = self.create(auto=True)
        self.manager.tick(bad.campaign_id)
        broken_id = self.created[0]
        good = self.create(auto=True)
        def get(task_id):
            if task_id == broken_id:
                raise OSError("temporary task lookup failure")
            return self.tasks[task_id]
        self.manager.durable.task_getter = get
        results = self.manager.tick_active()
        self.assertEqual(2, len(results))
        errors = [item for item in results if "error" in item]
        self.assertEqual(bad.campaign_id, errors[0]["campaign_id"])
        self.assertEqual("running", self.manager.get(good.campaign_id).nodes[0].status)

    def test_read_only_campaign_view_does_not_manufacture_update_time(self):
        campaign = self.create()
        with patch("evolution_v2.models.now_millis", return_value=9999999999999):
            loaded = self.manager.get(campaign.campaign_id)
        self.assertEqual(campaign.updated_at_millis, loaded.updated_at_millis)
        self.assertEqual(self.manager.durable.graph_store.ledger.snapshot(campaign.campaign_id)["updated_at_millis"], loaded.updated_at_millis)


if __name__ == "__main__":
    unittest.main()
