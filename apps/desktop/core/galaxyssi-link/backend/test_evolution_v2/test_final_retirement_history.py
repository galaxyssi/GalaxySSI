"""Applied SQLite history, including chains of failed replacements and pending pruning."""
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest

from agent_run_kernel import AgentRunEventLedger, AgentRunRootIdentity
from agent_task_dag import TaskDagError
from agent_task_dag_store import DurableTaskDag
from evolution_v2.common import atomic_write_json, sha256_text, stable_json
from evolution_v2.campaign_replanning import observation_id
from evolution_v2.checkpoint_planning import CHECKPOINT_CONTRACT, retirement_command
from evolution_v2.final_retirement_evidence import collect_retirement_evidence
from evolution_v2.replacement_context import persist_replacement_context, with_replacement_context


class FinalRetirementHistoryTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.identity = AgentRunRootIdentity("local", "campaign", "campaign", "campaign", "campaign")
        self.dag = DurableTaskDag(AgentRunEventLedger(self.root / "runs.sqlite3"))
        self.store = SimpleNamespace(root=self.root)
        self.durable = SimpleNamespace(graph_store=self.dag, identity=lambda key: self.identity, proposal_store=self.store)
        self.planner = SimpleNamespace(root=self.root, manager=SimpleNamespace(campaigns=SimpleNamespace(durable=self.durable)))
        self.apply("create", "create", objective="Complete the original scope", nodes=[self.spec("a")])

    @staticmethod
    def spec(key):
        return {"node_id": key, "depends_on": [], "effect": "replayable", "action": {"task_id": "task-" + key}}

    def apply(self, operation, key, **fields):
        return self.dag.apply(self.identity, key, {"operation": operation, **fields}, turn_id="turn")

    def load(self):
        return self.dag.load(self.identity)

    def replace(self, old, new):
        graph = self.load()
        operation = "replace-" + old
        specs, pending = with_replacement_context(graph, [self.spec(new)], [old], "Repair observed failure",
                                                  operation, "campaign")
        persist_replacement_context(self.store, pending)
        return self.apply("revise", operation, expected_revision=graph["revision"], nodes=specs,
                          supersede_ids=[old], evidence="Repair observed failure")

    def terminal(self, key, outcome):
        graph = self.apply("claim", "claim-" + key, node_id=key, owner="worker")
        self.apply(outcome, outcome + "-" + key, node_id=key, token=graph["nodes"][key]["lease"]["token"],
                   data={"evidence": "Observed " + outcome})

    def test_multiple_replaced_failures_are_not_treated_as_satisfied_work(self):
        self.terminal("a", "fail")
        self.replace("a", "b")
        self.terminal("b", "fail")
        self.replace("b", "c")
        self.terminal("c", "complete")
        proofs, history = collect_retirement_evidence(self.planner, "campaign", self.load())
        self.assertEqual({}, proofs)
        self.assertEqual(["failed", "failed"], [next(iter(entry["removed"].values()))["status"] for entry in history])
        self.assertEqual(["replace-a", "replace-b"], [entry["operation_id"] for entry in history])
        self.assertTrue(all("not satisfied" in entry["meaning"] for entry in history))
        self.dag = DurableTaskDag(AgentRunEventLedger(self.root / "runs.sqlite3"))
        self.assertEqual(["a", "b"], self.load()["retired_ids"])
        self.assertEqual(2, len(self.dag.retirement_history(self.identity, self.load())))

    def test_pending_plan_pruning_is_a_revision_not_acceptance(self):
        self.apply("revise", "prune", expected_revision=1, nodes=[self.spec("b")])
        self.terminal("b", "complete")
        proofs, history = collect_retirement_evidence(self.planner, "campaign", self.load())
        self.assertEqual({}, proofs)
        self.assertEqual("pending", history[0]["removed"]["a"]["status"])

    def test_changed_projection_is_rejected(self):
        before = self.load()
        self.replace("a", "b")
        with self.assertRaisesRegex(TaskDagError, "changed before"):
            self.dag.retirement_history(self.identity, before)

    def test_missing_or_modified_recovery_context_is_rejected(self):
        self.terminal("a", "fail")
        self.replace("a", "b")
        self.terminal("b", "complete")
        context = next((self.root / "recovery-contexts").glob("*.json"))
        context.unlink()
        with self.assertRaisesRegex(Exception, "missing or unreadable"):
            collect_retirement_evidence(self.planner, "campaign", self.load())
        atomic_write_json(context, {"campaign_id": "another"})
        with self.assertRaisesRegex(Exception, "identity or content changed"):
            collect_retirement_evidence(self.planner, "campaign", self.load())

    def test_checkpoint_operation_without_its_applied_proof_is_not_replacement(self):
        self.apply("revise", "checkpoint-observed", expected_revision=1, nodes=[self.spec("b")],
                   supersede_ids=["a"], evidence="A proof is required")
        self.terminal("b", "complete")
        with self.assertRaisesRegex(TaskDagError, "applied independent proof"):
            collect_retirement_evidence(self.planner, "campaign", self.load())

    def test_applied_checkpoint_hash_matches_real_ledger_command(self):
        self.apply("revise", "add-b", expected_revision=1, nodes=[self.spec("a"), self.spec("b")])
        self.terminal("a", "complete")
        source = self.load()
        proof = {"campaign_id": "campaign", "review_contract": CHECKPOINT_CONTRACT,
            "observation_id": observation_id(source), "decision": {"node_ids": ["b"]},
            "evidence": {"graph": source, "publications": {}, "proposals": {"b": {"acceptance": []}}},
            "retirement_proof": {"assessments": {"b:task": {"verdict": "pass"}}}}
        proof_id = sha256_text(stable_json(proof))
        atomic_write_json(self.root / "checkpoint-proofs" / (proof_id + ".json"), proof)
        self.apply("revise", "checkpoint-" + observation_id(source), **retirement_command(source, {"b"}, proof_id))
        proofs, history = collect_retirement_evidence(self.planner, "campaign", self.load())
        self.assertEqual([proof_id], list(proofs))
        self.assertEqual("pending", history[0]["removed"]["b"]["status"])
