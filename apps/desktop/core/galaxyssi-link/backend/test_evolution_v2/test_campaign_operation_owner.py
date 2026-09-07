from __future__ import annotations

from pathlib import Path
import tempfile
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from agent_run_kernel import AgentRunEventLedger
from agent_task_dag import TaskDagError
from evolution_v2.campaigns import CampaignManager
from evolution_v2.models import EvolutionProposal
from evolution_v2.storage import EvolutionV2Store
from evolution_v2.campaign_owner import CampaignOperationBusy


class CampaignOperationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.store = EvolutionV2Store(self.root / "v2")
        self.store.save_proposal(EvolutionProposal("proposal", "Improve", "Improve project", ["docs"], ["Pass"]))
        self.tasks = {}
        self.ensure_calls = []
        self.starts = []

    def manager(self, ensure=None):
        def default_ensure(proposal, campaign_id, task_id):
            self.ensure_calls.append(task_id)
            return self.tasks.setdefault(task_id, SimpleNamespace(task_id=task_id, status="proposed", last_error=""))
        def start(task_id):
            self.starts.append(task_id)
            self.tasks[task_id].status = "running"
            return self.tasks[task_id]
        return CampaignManager(self.store, task_factory=lambda *_: self.fail("Legacy factory"),
                               task_getter=lambda key: self.tasks[key], task_starter=start,
                               task_ensurer=ensure or default_ensure,
                               run_ledger=AgentRunEventLedger(self.root / "runs.sqlite3"))

    def campaign(self, manager):
        return manager.create("Campaign", "Finish verified work", [{"node_id": "a", "proposal_id": "proposal"}],
                              auto_start_safe_nodes=True)

    def test_second_executor_cannot_materialize_a_live_reservation(self):
        entered, release = threading.Event(), threading.Event()
        failures = []
        first = self.manager()
        original = first.durable.ensure_task
        def slow_ensure(*args):
            entered.set()
            if not release.wait(10):
                raise RuntimeError("Test release was not signalled")
            return original(*args)
        first.durable.ensure_task = slow_ensure
        second = self.manager()
        campaign = self.campaign(first)
        def advance():
            try:
                first.tick(campaign.campaign_id)
            except Exception as error:
                failures.append(error)
        worker = threading.Thread(target=advance)
        worker.start()
        try:
            self.assertTrue(entered.wait(5))
            with self.assertRaises(TaskDagError):
                second.tick(campaign.campaign_id)
            self.assertEqual([], self.ensure_calls)
        finally:
            release.set()
            worker.join(10)
        self.assertFalse(worker.is_alive())
        self.assertEqual([], failures)
        second.tick(campaign.campaign_id)
        self.assertEqual(1, len(self.ensure_calls))
        self.assertEqual(1, len(self.starts))

    def test_dispatch_fences_pause_and_revision_but_not_read_only_views(self):
        first, second = self.manager(), self.manager()
        campaign = self.campaign(first)
        original = first.durable.ensure_task
        def ensure(*args):
            for operation in (lambda: second.control(campaign.campaign_id, "pause", "pause"),
                              lambda: second.revise(campaign.campaign_id,
                                                    [{"node_id": "b", "proposal_id": "proposal"}], 1, "revise")):
                with self.assertRaises(CampaignOperationBusy):
                    operation()
            self.assertEqual(1, second.get(campaign.campaign_id).revision)
            return original(*args)
        first.durable.ensure_task = ensure
        first.tick(campaign.campaign_id)
        second.control(campaign.campaign_id, "pause", "pause")
        self.assertEqual("paused", first.get(campaign.campaign_id).status)

    def test_independent_campaign_can_advance_while_another_is_dispatching(self):
        first, second = self.manager(), self.manager()
        one, two = self.campaign(first), self.campaign(second)
        original = first.durable.ensure_task
        def ensure(*args):
            self.assertEqual("running", second.tick(two.campaign_id).status)
            return original(*args)
        first.durable.ensure_task = ensure
        first.tick(one.campaign_id)
        self.assertEqual(2, len(self.starts))
        self.assertEqual(2, len(set(self.starts)))

    def test_same_executor_does_not_hold_a_global_campaign_lock(self):
        manager = self.manager()
        one, two = self.campaign(manager), self.campaign(manager)
        entered, release, other_finished = threading.Event(), threading.Event(), threading.Event()
        errors = []
        original = manager.durable.ensure_task
        def ensure(proposal, campaign_id, task_id):
            if campaign_id == one.campaign_id:
                entered.set()
                if not release.wait(10):
                    raise RuntimeError("Test release was not signalled")
            return original(proposal, campaign_id, task_id)
        def tick(campaign_id):
            try:
                manager.tick(campaign_id)
            except Exception as error:
                errors.append(error)
            finally:
                if campaign_id == two.campaign_id:
                    other_finished.set()
        manager.durable.ensure_task = ensure
        first = threading.Thread(target=tick, args=(one.campaign_id,))
        second = threading.Thread(target=tick, args=(two.campaign_id,))
        first.start()
        try:
            self.assertTrue(entered.wait(5))
            second.start()
            self.assertTrue(other_finished.wait(5), "Independent campaign was serialized behind another plan")
        finally:
            release.set()
            first.join(10)
            if second.ident is not None:
                second.join(10)
        self.assertFalse(first.is_alive())
        self.assertFalse(second.is_alive())
        self.assertEqual([], errors)
        self.assertEqual(2, len(self.starts))

    def test_automatic_tick_reports_busy_without_failing_the_graph(self):
        first, second = self.manager(), self.manager()
        campaign = self.campaign(first)
        original = first.durable.ensure_task
        def ensure(*args):
            self.assertEqual([{"campaign_id": campaign.campaign_id, "status": "busy",
                              "code": "campaign_operation_busy"}], second.tick_active())
            return original(*args)
        first.durable.ensure_task = ensure
        first.tick(campaign.campaign_id)
        self.assertEqual("running", second.get(campaign.campaign_id).status)

    def test_exception_releases_operation_for_another_executor(self):
        first, second = self.manager(), self.manager()
        campaign = self.campaign(first)
        with patch.object(first.durable, "ensure_task", side_effect=OSError("disk unavailable")):
            with self.assertRaises(OSError):
                first.tick(campaign.campaign_id)
        reserved = first.get(campaign.campaign_id).nodes[0].task_id
        second.tick(campaign.campaign_id)
        self.assertEqual([reserved], self.ensure_calls)
        self.assertEqual([reserved], self.starts)

    def test_api_preserves_retryable_busy_code(self):
        from evolution_v2.api import CampaignTickReq, tick_campaign
        from test_evolution_v2.test_api import request_from
        from fastapi import HTTPException
        first, second = self.manager(), self.manager()
        campaign = self.campaign(first)
        original = first.durable.ensure_task
        runtime = SimpleNamespace(manager=SimpleNamespace(campaigns=second))
        def ensure(*args):
            with patch("evolution_v2.api.evolution_v2_runtime", return_value=runtime):
                with self.assertRaises(HTTPException) as failure:
                    tick_campaign(campaign.campaign_id, CampaignTickReq(), request_from("127.0.0.1"))
            self.assertEqual(409, failure.exception.status_code)
            self.assertEqual("campaign_operation_busy", failure.exception.detail["error"]["code"])
            return original(*args)
        first.durable.ensure_task = ensure
        first.tick(campaign.campaign_id)


if __name__ == "__main__":
    unittest.main()
