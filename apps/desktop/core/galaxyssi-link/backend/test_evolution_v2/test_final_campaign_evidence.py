"""Final evidence must bind actual candidates, source contracts, integration and retired work."""
from copy import deepcopy
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

from agent_task_dag import TaskDagError, canonical
from evolution_v2.candidate_acceptance import CONTRACT
from evolution_v2.checkpoint_planning import CHECKPOINT_CONTRACT, retirement_command
from evolution_v2.common import atomic_write_json, sha256_text, stable_json
from evolution_v2.final_campaign_evidence import collect_final_evidence


class FinalCampaignEvidenceTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.graph = {"status": "active", "objective": "Original goal", "retired_ids": [],
                      "nodes": {"done": {"status": "completed", "action": {"task_id": "task"}}}}
        self.candidate = {"files": {"docs/result.md": {"before": "original", "after": "original and new"}}}
        self.acceptance = {"contract": CONTRACT, "verdict": "pass",
            "evidence_hash": sha256_text(stable_json({"contract": CONTRACT, "evidence": self.candidate})),
            "goal_contract": {"issues": []}, "preservation_contract": {}}
        self.task = SimpleNamespace(task_id="task", pull_request_url="https://github.com/example/project/pull/1", candidate_commit="a" * 40)
        self.manager = SimpleNamespace(source_root=self.root, runner=Mock(), require=Mock(return_value=self.task),
            _implementation_context=Mock(return_value="source-bound context"),
            task_metadata=Mock(return_value={"review": {"acceptance": self.acceptance}}),
            ci_watches=SimpleNamespace(get=Mock(return_value={"snapshot": {"head_sha": "a" * 40}})),
            campaigns=SimpleNamespace(durable=SimpleNamespace(identity=lambda key: key, proposal_store=Mock(),
                graph_store=SimpleNamespace(load=Mock(return_value=self.graph), retirement_history=Mock(return_value=[])))))
        self.planner = SimpleNamespace(manager=self.manager, root=self.root,
            checkpoints=SimpleNamespace(evidence=Mock(return_value={"graph": self.graph,
                "publications": {"done": {"url": self.task.pull_request_url}}})),
            goal_decomposition=SimpleNamespace(goals=SimpleNamespace(load=Mock(return_value=None))))
        self.patches = {}
        for name, value in {"collect_evidence": self.candidate, "evaluate_contract": [{"passed": True}],
                            "evaluate_preservation": [{"passed": True}], "verify_integration": {"passed": True}}.items():
            patcher = patch("evolution_v2.final_campaign_evidence." + name, return_value=value)
            self.patches[name] = patcher.start()
            self.addCleanup(patcher.stop)

    def collect(self):
        return collect_final_evidence(self.planner, "campaign")

    def test_complete_evidence_rechecks_constraints_and_current_integration(self):
        result = self.collect()
        self.assertEqual(self.graph, result["graph"])
        self.assertTrue(result["current_integrations"]["done"]["passed"])
        for call in self.patches.values():
            call.assert_called_once()

    def test_unfinished_paused_empty_and_completed_graphs_cannot_start_final_review(self):
        for graph in (None, {**self.graph, "status": "paused"}, {**self.graph, "status": "completed"},
                      {**self.graph, "nodes": {}}, {**self.graph, "nodes": {"x": {"status": "pending"}}}):
            self.manager.campaigns.durable.graph_store.load.return_value = graph
            with self.subTest(graph=graph), self.assertRaises(TaskDagError):
                self.collect()
        self.patches["collect_evidence"].assert_not_called()

    def test_goal_identity_and_pause_are_checked(self):
        for goal in ({"objective": "Different goal", "status": "materialized"},
                     {"objective": "Original goal", "status": "paused"}):
            self.planner.goal_decomposition.goals.load.return_value = goal
            with self.subTest(goal=goal), self.assertRaises(TaskDagError):
                self.collect()

    def test_url_without_observed_publication_is_not_accepted(self):
        self.planner.checkpoints.evidence.return_value["publications"].clear()
        with self.assertRaisesRegex(TaskDagError, "observed PR evidence"):
            self.collect()

    def test_stale_candidate_hash_or_contract_is_rejected(self):
        for key in ("evidence_hash", "contract"):
            original = self.acceptance[key]
            self.acceptance[key] = "stale"
            with self.subTest(key=key), self.assertRaisesRegex(TaskDagError, "identity changed"):
                self.collect()
            self.acceptance[key] = original

    def test_current_literal_or_preservation_failure_overrides_previous_pass(self):
        for name in ("evaluate_contract", "evaluate_preservation"):
            self.patches[name].return_value = [{"passed": False}]
            with self.subTest(name=name), self.assertRaisesRegex(TaskDagError, "constraints do not pass"):
                self.collect()
            self.patches[name].return_value = [{"passed": True}]

    def test_current_ci_failure_cannot_reuse_historical_integration(self):
        self.patches["verify_integration"].return_value = {"passed": False, "reason": "Current CI is red"}
        with self.assertRaisesRegex(TaskDagError, "Current CI is red"):
            self.collect()

    def test_missing_watch_blocks_final_verification(self):
        self.manager.ci_watches.get.return_value = None
        with self.assertRaisesRegex(TaskDagError, "watch is unavailable"):
            self.collect()

    def retirement(self):
        source = {**deepcopy(self.graph), "revision": 1, "retired_ids": [], "nodes": {
            "done": {"node_id": "done", "depends_on": [], "action": {"task_id": "task"}, "effect": "replayable"},
            "retired": {"node_id": "retired", "depends_on": ["done"], "action": {"task_id": "retired-task"}, "effect": "replayable"}}}
        return {"campaign_id": "campaign", "review_contract": CHECKPOINT_CONTRACT,
                "observation_id": sha256_text(canonical(source)),
                "decision": {"node_ids": ["retired"]}, "evidence": {"graph": source,
                    "proposals": {"retired": {"acceptance": []}}, "publications": {"done": {"title": "Published"}}},
                "retirement_proof": {"assessments": {"retired:task": {"verdict": "pass"}},
                    "scoped_evidence": {"contract": "galaxyssi.scoped-verification.v3",
                        "checks": {"retired:task": {"verdict": "pass"}}}}}

    def save_proof(self, proof, name=None):
        path = self.root / "checkpoint-proofs" / ((name or sha256_text(stable_json(proof))) + ".json")
        atomic_write_json(path, proof)
        source = proof["evidence"]["graph"]
        command = {"operation": "revise", **retirement_command(source, {"retired"}, path.stem)}
        self.manager.campaigns.durable.graph_store.retirement_history.return_value = [{
            "operation_id": "checkpoint-" + proof["observation_id"], "observation_id": proof["observation_id"],
            "command_sha256": sha256_text(canonical(command)), "removed": {"retired": source["nodes"]["retired"]},
            "introduced": {}, "observed_revision": 1}]
        return path

    def test_retired_work_needs_current_complete_and_hash_bound_review(self):
        self.graph["retired_ids"] = ["retired"]
        with self.assertRaisesRegex(TaskDagError, "no retained independent evidence"):
            self.collect()
        path = self.save_proof(self.retirement())
        self.assertEqual(1, len(self.collect()["retirement_proofs"]))
        corrupted = self.retirement()
        corrupted["decision"]["node_ids"] = ["another"]
        atomic_write_json(path, corrupted)
        with self.assertRaisesRegex(TaskDagError, "content hash"):
            self.collect()

    def test_legacy_or_failed_scoped_retirement_cannot_complete_original_goal(self):
        self.graph["retired_ids"] = ["retired"]
        for mode in ("legacy", "failed", "missing"):
            proof = deepcopy(self.retirement())
            if mode == "legacy":
                proof["review_contract"] = "old"
            elif mode == "failed":
                proof["retirement_proof"]["scoped_evidence"]["checks"]["retired:task"]["verdict"] = "fail"
            else:
                proof["retirement_proof"]["scoped_evidence"]["checks"] = {}
            path = self.save_proof(proof)
            with self.subTest(mode=mode), self.assertRaises(TaskDagError):
                self.collect()
            path.unlink()

    def test_unapplied_archived_proof_does_not_complete_retirement(self):
        self.graph["retired_ids"] = ["retired"]
        self.save_proof(self.retirement())
        self.manager.campaigns.durable.graph_store.retirement_history.return_value[0]["command_sha256"] = "0" * 64
        with self.assertRaisesRegex(TaskDagError, "applied independent proof"):
            self.collect()

    def test_unrelated_stale_checkpoint_does_not_block_replaced_failure(self):
        self.graph["retired_ids"] = ["failed"]
        self.save_proof(self.retirement())
        self.manager.campaigns.durable.graph_store.retirement_history.return_value = [{
            "operation_id": "replace-failed", "removed": {"failed": {"status": "failed"}}, "introduced": {}}]
        result = self.collect()
        self.assertEqual({}, result["retirement_proofs"])
        self.assertIn("not satisfied", result["applied_replanning_history"][0]["meaning"])
