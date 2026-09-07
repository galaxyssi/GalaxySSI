from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

from evolution_v2.campaign_owner import CampaignOperationBusy
from evolution_v2.legacy import EvolutionStore
from evolution_v2.manager import EvolutionManager
from evolution_v2.models import EvolutionProposal


class CampaignProcessRecoveryTests(unittest.TestCase):
    def test_real_process_death_after_child_persistence_reuses_one_child(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            source.mkdir()
            subprocess.run(["git", "init", "-b", "main"], cwd=source, check=True, capture_output=True, timeout=20)
            subprocess.run(["git", "-c", "user.name=Campaign Test", "-c", "user.email=test@example.invalid",
                            "commit", "--allow-empty", "-m", "Seed campaign recovery"],
                           cwd=source, check=True, capture_output=True, timeout=20)
            state = root / "state"
            manager = EvolutionManager(source_root=source, store=EvolutionStore(state))
            manager.v2_store.save_proposal(EvolutionProposal("proposal", "Improve", "Improve docs", ["docs"], ["Pass"]))
            campaign = manager.campaigns.create("Recovery", "Verify durable dispatch", [
                {"node_id": "a", "proposal_id": "proposal"},
                {"node_id": "b", "proposal_id": "proposal", "depends_on": ["a"]},
            ], auto_start_safe_nodes=True)
            checkpoint = root / "persisted-child"
            host_code = """
import os, sys
from pathlib import Path
from evolution_v2.legacy import EvolutionStore
from evolution_v2.manager import EvolutionManager
manager = EvolutionManager(source_root=Path(sys.argv[1]), store=EvolutionStore(Path(sys.argv[2])))
original = manager.campaigns.durable.ensure_task
def stop_after_persist(*args):
    task = original(*args)
    Path(sys.argv[4]).write_text(task.task_id, encoding='ascii')
    sys.stdin.buffer.read(1)
    os._exit(23)
manager.campaigns.durable.ensure_task = stop_after_persist
manager.campaigns.tick(sys.argv[3])
"""
            process = subprocess.Popen([getattr(sys, "_base_executable", sys.executable), "-c", host_code,
                                        str(source), str(state), campaign.campaign_id, str(checkpoint)],
                                       cwd=Path(__file__).resolve().parents[1], stdin=subprocess.PIPE,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                deadline = time.monotonic() + 20
                while not checkpoint.exists() and process.poll() is None and time.monotonic() < deadline:
                    time.sleep(0.02)
                self.assertTrue(checkpoint.exists(), "Child persistence checkpoint was not reached")
                task_id = checkpoint.read_text(encoding="ascii")
                self.assertEqual([task_id], [task.task_id for task in manager.store.iter_tasks()])
                with self.assertRaises(CampaignOperationBusy):
                    manager.campaigns.tick(campaign.campaign_id)
                self.assertEqual("proposed", manager.require(task_id).status)
                _, stderr = process.communicate(b"x", timeout=20)
                self.assertEqual(23, process.returncode, stderr.decode(errors="replace"))

                reopened = EvolutionManager(source_root=source, store=EvolutionStore(state))
                starts = []
                def start(child_id):
                    starts.append(child_id)
                    task = reopened.require(child_id)
                    task.status = "running"
                    reopened.store.save(task)
                    return task
                with patch.object(reopened, "start", side_effect=start):
                    reopened.campaigns.tick(campaign.campaign_id)
                    reopened.campaigns.tick(campaign.campaign_id)
                self.assertEqual([task_id], starts)
                self.assertEqual([task_id], [task.task_id for task in reopened.store.iter_tasks()])
                self.assertEqual(campaign.campaign_id, reopened.v2_store.get_task_metadata(task_id).campaign_id)
                graph = reopened.campaigns.get(campaign.campaign_id)
                self.assertEqual(["running", "pending"], [node.status for node in graph.nodes])
                self.assertEqual(task_id, graph.nodes[0].task_id)
            finally:
                if process.poll() is None:
                    process.communicate(b"x", timeout=20)


if __name__ == "__main__":
    unittest.main()
