from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

from fastapi import HTTPException
from evolution_v2.api import task_ci_watch
from evolution_v2.runtime import EvolutionV2Runtime
from evolution_v2.scheduler import EvolutionScheduler
from test_evolution_v2.test_api import request_from
from test_evolution_v2.test_scheduler import FakeManager


class CiRuntimeTests(unittest.TestCase):
    def test_manager_restores_both_dag_and_ci_state_without_starting_workers(self):
        from evolution_v2.legacy import EvolutionStore
        from evolution_v2.manager import EvolutionManager
        from evolution_v2.models import EvolutionProposal
        from test_evolution_v2.test_ci_snapshot import URL

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            source.mkdir()
            subprocess.run(["git", "init", "-b", "main"], cwd=source,
                           capture_output=True, check=True, timeout=20)
            def create_manager():
                return EvolutionManager(source_root=source, store=EvolutionStore(root / "state"))
            manager = create_manager()
            manager.v2_store.save_proposal(EvolutionProposal(
                "proposal", "Improve", "Improve a project", ["docs"], ["Tests pass"]))
            campaign = manager.campaigns.create("Campaign", "Keep progress", [
                {"node_id": "first", "proposal_id": "proposal"}])
            manager.ci_watches.register("published-task", URL)
            restored = create_manager()
            self.assertEqual(campaign.campaign_id, restored.campaigns.get(campaign.campaign_id).campaign_id)
            self.assertEqual(URL, restored.ci_watches.get("published-task")["url"])
            self.assertEqual(0, restored.active_worker_count())

    def test_runtime_attaches_and_stops_observer_without_enabling_evolution(self):
        manager = Mock()
        manager.recover_interrupted.return_value = []
        scheduler = Mock(config={"enabled": False})
        observer = Mock()
        with patch("evolution_v2.runtime.evolution_manager", return_value=manager), \
                patch("evolution_v2.runtime.EvolutionScheduler", return_value=scheduler), \
                patch("evolution_v2.runtime.EvolutionCiSupervisor", return_value=observer):
            runtime = EvolutionV2Runtime()
            runtime.start()
            runtime.stop()
        manager.recover_interrupted.assert_called_once_with(resume=False)
        observer.start.assert_called_once()
        observer.stop.assert_called_once()
        self.assertFalse(scheduler.config["enabled"])

    def test_ci_watch_endpoint_returns_persisted_state_without_network(self):
        manager = Mock()
        manager.ci_watches.get.return_value = {"status": "repairing", "head_sha": "a" * 40}
        with patch("evolution_v2.api.evolution_v2_runtime", return_value=SimpleNamespace(manager=manager)):
            result = task_ci_watch("parent", request_from("127.0.0.1"))
        self.assertEqual("repairing", result["status"])
        manager.github.assert_not_called()
        manager.require.assert_called_once_with("parent")

    def test_ci_watch_endpoint_rejects_remote_before_runtime_creation(self):
        with patch("evolution_v2.api.evolution_v2_runtime") as runtime:
            with self.assertRaises(HTTPException) as raised:
                task_ci_watch("parent", request_from("203.0.113.8"))
        self.assertEqual(403, raised.exception.status_code)
        runtime.assert_not_called()

    def test_proposal_scheduler_counts_ci_workers(self):
        with tempfile.TemporaryDirectory() as directory:
            manager = FakeManager(Path(directory))
            manager.active_worker_count = lambda: 1
            scheduler = EvolutionScheduler(manager)
            self.assertEqual(0, scheduler._available_capacity({"active_evolutions": []}))

    def test_proposal_admission_rechecks_capacity_inside_manager_lock(self):
        with tempfile.TemporaryDirectory() as directory:
            manager = FakeManager(Path(directory))
            manager.active_worker_count = lambda: 1
            scheduler = EvolutionScheduler(manager)
            result = {}
            manager.create_from_proposal = Mock()
            scheduler._start_evolution({"active_evolutions": []}, result, Mock(), 100, 100)
            manager.create_from_proposal.assert_not_called()
            self.assertEqual("deferred", result["evolution"]["status"])
