from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

from evolution_v2.campaigns import CampaignError, CampaignManager
from evolution_v2.models import EvolutionProposal
from evolution_v2.storage import EvolutionV2Store


class CampaignTests(unittest.TestCase):
    def manager(self, root):
        store = EvolutionV2Store(Path(root))
        proposal = EvolutionProposal("proposal-1", "p", "problem", ["docs"], ["done"], risk_level="low")
        store.save_proposal(proposal)
        tasks = {}

        def create(value, campaign_id):
            task = SimpleNamespace(task_id=f"task-{len(tasks) + 1}", status="proposed")
            tasks[task.task_id] = task
            return task

        def get(task_id):
            return tasks[task_id]

        def start(task_id):
            tasks[task_id].status = "running"
            return tasks[task_id]

        return CampaignManager(store, task_factory=create, task_getter=get, task_starter=start), store, tasks

    def test_cycle_is_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            manager, _, _ = self.manager(root)
            with self.assertRaises(CampaignError):
                manager.create("bad", "", [
                    {"node_id": "a", "proposal_id": "proposal-1", "depends_on": ["b"]},
                    {"node_id": "b", "proposal_id": "proposal-1", "depends_on": ["a"]},
                ])

    def test_ready_node_materializes_and_starts(self):
        with tempfile.TemporaryDirectory() as root:
            manager, _, tasks = self.manager(root)
            campaign = manager.create("good", "", [{"node_id": "a", "proposal_id": "proposal-1"}])
            campaign = manager.tick(campaign.campaign_id, start_ready=True)
            self.assertEqual("running", campaign.nodes[0].status)
            self.assertTrue(campaign.nodes[0].task_id)
            self.assertEqual("running", tasks[campaign.nodes[0].task_id].status)


if __name__ == "__main__":
    unittest.main()
