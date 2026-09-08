from __future__ import annotations

import copy
import tempfile
import threading
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

from agent_run_kernel import AgentRunEventLedger
from evolution_v2 import ci_tasks, legacy
from evolution_v2.ci_store import CiWatchStore
from evolution_v2.ci_supervisor import EvolutionCiSupervisor
from evolution_v2.models import TaskMetadata
from evolution_v2.storage import EvolutionV2Store
from test_evolution_v2.test_ci_snapshot import Client, SHA, URL, check, observe


class Manager:
    def __init__(self, root):
        self.store = legacy.EvolutionStore(root / "tasks")
        self.v2_store = EvolutionV2Store(root / "v2")
        self.audit = Mock()
        self.github = Mock()
        self._lock = threading.RLock()
        self.created = []
        self.started = []
        self.published = []
        self.cancelled = []
        self.worker_count = 0
        self.after_create = None

    def require(self, task_id):
        task = self.store.get(task_id)
        if task is None:
            raise legacy.EvolutionError("task_not_found", "Missing task")
        return task

    def create(self, **kwargs):
        origin, objective = kwargs.pop("origin", "manual"), kwargs.pop("objective", "repair")
        task = legacy.EvolutionTask(**kwargs)
        self.store.save(task)
        self.created.append(task.task_id)
        if self.after_create:
            self.after_create()
        self.v2_store.save_task_metadata(TaskMetadata(task_id=task.task_id, origin=origin, objective=objective))
        return task

    def ensure_ci_repair(self, repair, snapshot):
        return ci_tasks.ensure_repair(self, repair, snapshot)

    def start_ci_repair(self, task_id, config):
        return ci_tasks.start_repair(self, task_id, config)

    def active_worker_count(self):
        return self.worker_count

    def start(self, task_id):
        task = self.require(task_id)
        task.status = "running"
        self.started.append(task_id)
        self.store.save(task)
        return task

    def cancel(self, task_id):
        task = self.require(task_id)
        task.status = "cancelled"
        self.cancelled.append(task_id)
        self.store.save(task)

    def publish(self, task_id, approval_hash, **kwargs):
        task = self.require(task_id)
        task.status = "published"
        task.pull_request_url = URL
        self.published.append((task_id, approval_hash))
        self.store.save(task)
        return task


class CiSupervisorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.manager = Manager(root)
        self.parent = self.manager.create(task_id="parent", problem="Improve parser", reproduction_steps=[], scope=["src"],
            acceptance=["Tests pass"], risk_level="low", max_attempts=3, agent_id="claude")
        self.parent.status = "published"
        self.parent.pull_request_url = URL
        self.manager.store.save(self.parent)
        self.manager.created.clear()
        self.store = CiWatchStore(AgentRunEventLedger(root / "runs.sqlite3"))
        self.config = {"enabled": True, "auto_start_tasks": True, "auto_publish": True}
        self.supervisor = EvolutionCiSupervisor(self.manager, self.store, lambda: self.config)
        self.now = 1000000
        self.snapshot = observe(Client([check(conclusion="failure")]), URL)
        self.manager.github.pull_request_ci_snapshot.side_effect = lambda _: copy.deepcopy(self.snapshot)

    def tick(self, supervisor=None):
        self.now += 600000
        with patch("evolution_v2.ci_supervisor.now_millis", return_value=self.now):
            return (supervisor or self.supervisor).tick()

    def child(self):
        return self.manager.require(self.store.get("parent")["repair"]["task_id"])

    def test_disabled_does_not_query_or_create(self):
        self.config["enabled"] = False
        self.assertEqual("disabled", self.tick()["status"])
        self.manager.github.pull_request_ci_snapshot.assert_not_called()
        self.assertEqual([], self.manager.created)

    def test_repair_prompt_uses_small_index_not_bulk_ci_log_payloads(self):
        self.snapshot["checks"] = [{"id": i, "kind": "check_run", "outcome": "failed", "name": "job" * 500,
                                    "conclusion": "failure", "summary": "private-log-content" * 5000}
                                   for i in range(1000)]
        self.tick()
        problem = self.child().problem
        self.assertLess(len(problem), 5000)
        self.assertIn("ci_log", problem)
        self.assertIn('"failed_count":1000', problem)
        self.assertNotIn("private-log-content", problem)

    def test_merged_pending_checks_are_observed_until_verified_without_repair(self):
        client = Client([check(status="in_progress")])
        client.pr.update(state="closed", merged=True, merge_commit_sha="b" * 40)
        self.snapshot = observe(client, URL)
        self.tick()
        self.assertFalse(self.store.get("parent")["snapshot"]["passed"])
        self.assertEqual([], self.manager.created)
        client.runs[0]["check_runs"][0] = check()
        self.snapshot = observe(client, URL)
        self.tick()
        self.assertTrue(self.store.get("parent")["snapshot"]["passed"])
        calls = self.manager.github.pull_request_ci_snapshot.call_count
        self.tick()
        self.assertEqual(calls, self.manager.github.pull_request_ci_snapshot.call_count)

    def test_merged_failed_checks_do_not_create_an_unpushable_repair(self):
        client = Client([check(conclusion="failure")])
        client.pr.update(state="closed", merged=True, merge_commit_sha="b" * 40)
        self.snapshot = observe(client, URL)
        self.tick()
        self.assertEqual([], self.manager.created)
        self.assertFalse(self.store.get("parent")["snapshot"]["passed"])

    def test_failed_head_creates_one_isolated_task_across_restarts(self):
        self.tick()
        child = self.child()
        self.assertEqual(("running", "claude", ["src"]), (child.status, child.agent_id, child.scope))
        restarted = EvolutionCiSupervisor(self.manager, self.store, lambda: self.config)
        self.tick(restarted)
        self.assertEqual([child.task_id], self.manager.created)
        self.assertEqual([child.task_id], self.manager.started)

    def test_reservation_precedes_task_creation(self):
        def interrupt():
            self.assertIsNotNone(self.store.get("parent")["repair"])
            raise RuntimeError("process interrupted before metadata")
        self.manager.after_create = interrupt
        self.tick()
        self.assertEqual("observation_error", self.store.get("parent")["status"])
        self.manager.after_create = None
        self.tick()
        self.assertEqual(1, len(self.manager.created))
        self.assertEqual("running", self.child().status)

    def test_waiting_candidate_publishes_original_pr_once(self):
        self.tick()
        task = self.child()
        task.status, task.approval_hash = "waiting_approval", "reviewed-digest"
        self.manager.store.save(task)
        self.tick()
        self.tick()
        self.assertEqual([(task.task_id, "reviewed-digest")], self.manager.published)
        self.assertEqual("awaiting_repaired_head", self.store.get("parent")["status"])

    def test_new_head_has_its_own_repair_identity(self):
        self.tick()
        old = self.child().task_id
        self.snapshot["head_sha"] = "b" * 40
        self.tick()
        self.assertEqual([old], self.manager.cancelled)
        self.assertNotEqual(old, self.child().task_id)

    def test_missing_reserved_child_does_not_block_new_head(self):
        self.store.register("parent", URL)
        data = self.store.claim_due(self.now, "old")[0]
        data.update(snapshot=self.snapshot, repair={"task_id": "not-created"})
        self.store.save(data, "old", self.now, next_poll=0)
        self.snapshot["head_sha"] = "c" * 40
        self.tick()
        self.assertEqual("running", self.child().status)

    def test_pending_checks_do_not_invoke_agent(self):
        self.snapshot["status"] = "pending"
        self.tick()
        self.assertEqual([], self.manager.created)

    def test_closed_pr_cancels_active_repair_and_stops_polling(self):
        self.tick()
        child = self.child().task_id
        self.snapshot.update(status="closed", state="closed")
        self.tick()
        self.assertEqual([child], self.manager.cancelled)
        calls = self.manager.github.pull_request_ci_snapshot.call_count
        self.tick()
        self.assertEqual(calls, self.manager.github.pull_request_ci_snapshot.call_count)

    def test_green_head_records_observation_not_merge(self):
        self.snapshot.update(status="passed", passed=True)
        self.tick()
        metadata = self.manager.v2_store.get_task_metadata("parent")
        self.assertEqual("passed", metadata.ci["watch_status"])
        self.assertEqual([], self.manager.published)

    def test_fork_branch_is_not_mutated(self):
        self.snapshot["head_repository"] = "other/repo"
        self.tick()
        self.assertEqual("attention_required", self.store.get("parent")["status"])
        self.assertEqual([], self.manager.created)

    def test_terminal_child_failure_is_visible_not_recreated(self):
        self.tick()
        task = self.child()
        task.status, task.last_error = "failed", "compiler could not resolve symbol"
        self.manager.store.save(task)
        self.tick()
        self.assertEqual("attention_required", self.store.get("parent")["status"])
        self.assertIn("symbol", self.store.get("parent")["error"])
        self.assertEqual(1, len(self.manager.created))

    def test_capacity_defers_start_but_preserves_reserved_child(self):
        self.manager.worker_count = 1
        self.tick()
        self.assertEqual("proposed", self.child().status)
        self.manager.worker_count = 0
        self.tick()
        self.assertEqual("running", self.child().status)
        self.assertEqual(1, len(self.manager.created))

    def test_auto_start_and_publish_settings_are_respected(self):
        self.config["auto_start_tasks"] = False
        self.tick()
        self.assertEqual("proposed", self.child().status)
        task = self.child()
        task.status = "waiting_approval"
        self.manager.store.save(task)
        self.config["auto_publish"] = False
        self.tick()
        self.assertEqual([], self.manager.published)

    def test_disabled_during_observation_does_not_start_agent(self):
        def observe_and_disable(_):
            self.config["enabled"] = False
            return copy.deepcopy(self.snapshot)
        self.manager.github.pull_request_ci_snapshot.side_effect = observe_and_disable
        self.tick()
        self.assertEqual([], self.manager.created)

    def test_network_error_is_persisted_and_retried(self):
        self.manager.github.pull_request_ci_snapshot.side_effect = RuntimeError("offline")
        self.tick()
        self.assertEqual("offline", self.store.get("parent")["error"])
        self.manager.github.pull_request_ci_snapshot.side_effect = lambda _: copy.deepcopy(self.snapshot)
        self.tick()
        self.assertEqual("running", self.child().status)

    def test_overlapping_tick_does_not_duplicate_work(self):
        self.supervisor._tick_lock.acquire()
        try:
            self.assertEqual("busy", self.tick()["status"])
        finally:
            self.supervisor._tick_lock.release()
        self.assertEqual([], self.manager.created)

    def test_restart_does_not_index_child_as_separate_watch(self):
        self.tick()
        task = self.child()
        task.status, task.pull_request_url = "published", URL
        self.manager.store.save(task)
        restarted = EvolutionCiSupervisor(self.manager, self.store, lambda: self.config)
        self.tick(restarted)
        self.assertIsNone(self.store.get(task.task_id))
