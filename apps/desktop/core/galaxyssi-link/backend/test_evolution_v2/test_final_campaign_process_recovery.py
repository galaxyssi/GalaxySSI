"""Kill a real verifier process on both sides of the durable finish transaction."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from agent_run_kernel import AgentRunEventLedger
from evolution_v2.campaigns import CampaignManager
from evolution_v2.campaign_planner import EvolutionCampaignPlanner
from evolution_v2.common import atomic_write_json, read_json
from evolution_v2.models import EvolutionProposal
from evolution_v2.storage import EvolutionV2Store


def run_process(root, phase):
    store = EvolutionV2Store(root / "v2")
    tasks_path = root / "tasks.json"
    tasks = read_json(tasks_path, {})
    def ensure(proposal, campaign_id, task_id):
        tasks.setdefault(task_id, {"task_id": task_id, "status": "proposed"})
        atomic_write_json(tasks_path, tasks)
        return SimpleNamespace(**tasks[task_id])
    def start(task_id):
        tasks[task_id]["status"] = "completed"
        atomic_write_json(tasks_path, tasks)
    campaigns = CampaignManager(store, task_factory=Mock(), task_ensurer=ensure,
        task_getter=lambda key: SimpleNamespace(**tasks[key]), task_starter=start,
        run_ledger=AgentRunEventLedger(root / "runs.sqlite3"))
    saved = read_json(root / "identity.json", None)
    if saved is None:
        store.save_proposal(EvolutionProposal("p", "Work", "Original work", ["docs"], ["Verified result"]))
        campaign = campaigns.create("Recovery test", "\u4fdd\u7559\u539f\u59cb\u76ee\u6807\uff0c\u5b8c\u6210\u540e\u9a8c\u8bc1\u5e76\u4fdd\u5b58\u7ed3\u679c", [
            {"node_id": "done", "proposal_id": "p"}], auto_start_safe_nodes=True)
        saved = {"campaign_id": campaign.campaign_id}
        atomic_write_json(root / "identity.json", saved)
        campaigns.tick(campaign.campaign_id)
        campaigns.tick(campaign.campaign_id)
    key = saved["campaign_id"]
    manager = SimpleNamespace(v2_store=store, campaigns=campaigns, audit=Mock())
    def infer(*args, **kwargs):
        calls = read_json(root / "calls.json", {"count": 0})
        calls["count"] += 1
        atomic_write_json(root / "calls.json", calls)
        return json.dumps({"assessments": {"original-goal": {"verdict": "pass", "evidence": "Controlled fixture evidence"}}})
    planner = EvolutionCampaignPlanner(manager, lambda: {"enabled": True, "auto_start_tasks": True}, infer)
    planner.final_verification.collect = lambda campaign_id: {
        "graph": campaigns.durable.graph_store.load(campaigns.durable.identity(campaign_id)),
        "publications": {}, "candidates": {}, "current_integrations": {}}
    from evolution_v2 import final_campaign_verification
    original = final_campaign_verification.finish_verified
    if phase != "resume":
        def terminate(*args):
            if phase == "after_finish":
                original(*args)
            os._exit(83)
        final_campaign_verification.finish_verified = terminate
    planner.tick()
    atomic_write_json(root / "result.json", {"status": campaigns.get(key).status,
        "calls": read_json(root / "calls.json")["count"], "tasks": len(tasks),
        "proofs": len(list((planner.root / "final-proofs").glob("*.json")))})


class FinalCampaignProcessRecoveryTests(unittest.TestCase):
    def test_process_death_before_and_after_finish_preserves_one_completion(self):
        for phase in ("before_finish", "after_finish"):
            with self.subTest(phase=phase), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                args = [sys.executable, str(Path(__file__).resolve()), str(root)]
                dead = subprocess.run([*args, phase], capture_output=True, text=True, timeout=90)
                self.assertEqual(83, dead.returncode, dead.stdout + dead.stderr)
                resumed = subprocess.run([*args, "resume"], capture_output=True, text=True, timeout=90)
                self.assertEqual(0, resumed.returncode, resumed.stdout + resumed.stderr)
                self.assertEqual({"status": "completed", "calls": 1, "tasks": 1, "proofs": 1}, read_json(root / "result.json"))


if __name__ == "__main__":
    run_process(Path(sys.argv[1]), sys.argv[2])
