from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from dataclasses import replace
from pathlib import Path
import json
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from agent_run_kernel import AgentRunEventLedger, AgentRunRootIdentity, AgentRunIdentityConflict
from agent_task_dag import TaskDagError, specifications
from agent_task_dag_store import DurableTaskDag


def node(key="a", depends=(), effect="read_only"):
    return {"node_id": key, "depends_on": list(depends), "effect": effect,
            "action": {"tool": "tool-selected-by-model", "arguments": {"label": key}}}


class DurableDagTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "run.sqlite3"
        self.ledger = AgentRunEventLedger(self.path)
        self.store = DurableTaskDag(self.ledger)
        self.root = AgentRunRootIdentity("route", "conversation", "goal", "task", "run")
        self.counter = 0

    def apply(self, operation, operation_id=None, **kwargs):
        self.counter += 1
        return self.store.apply(self.root, operation_id or f"op-{self.counter}",
                                {"operation": operation, **kwargs}, turn_id="turn")

    def create(self, nodes=None):
        return self.apply("create", objective="Model-authored long-running goal", nodes=nodes or [node()])

    def claim(self, key="a", owner="worker"):
        graph = self.apply("claim", node_id=key, owner=owner)
        return graph["nodes"][key]["lease"]["token"]

    def test_dynamic_branch_and_dependency_revision(self):
        self.create([node(), node("b", ["a"])])
        self.assertEqual(["a"], self.store.ready(self.root))
        token = self.claim()
        self.apply("complete", node_id="a", token=token, data={"observation": "done"})
        revised = self.apply("revise", expected_revision=1,
                             nodes=[node(), node("b", ["c"]), node("c", ["a"])])
        self.assertEqual(2, revised["revision"])
        self.assertEqual("completed", revised["nodes"]["a"]["status"])
        self.assertEqual(["c"], self.store.ready(self.root))

    def test_cycles_missing_and_duplicate_nodes_are_rejected_atomically(self):
        original = self.create()
        for rows in ([node(), node()], [node("a", ["b"])], [node("a", ["a"])],
                     [node("a", ["b"]), node("b", ["a"])], [node(), node("b", ["a", "a"])]):
            with self.subTest(rows=rows), self.assertRaises(TaskDagError):
                self.apply("revise", expected_revision=1, nodes=rows)
            self.assertEqual(original, self.store.load(self.root))
        self.assertEqual(1, self.ledger.event_count())

    def test_long_graph_does_not_use_recursive_validation(self):
        rows = [node(str(index), [str(index - 1)] if index else []) for index in range(3000)]
        self.assertEqual(3000, len(specifications(rows)))
        rows[0]["depends_on"] = ["2999"]
        with self.assertRaises(TaskDagError):
            specifications(rows)

    def test_stale_revision_and_bool_revision_are_not_accepted(self):
        self.create()
        self.apply("revise", expected_revision=1, nodes=[node(), node("b")])
        for revision in (1, True, "2"):
            with self.assertRaises(TaskDagError):
                self.apply("revise", expected_revision=revision, nodes=[node()])

    def test_started_nodes_cannot_be_removed_or_rewritten(self):
        self.create([node(), node("b")])
        self.claim()
        for rows in ([node("b")], [node("a", ["b"]), node("b")], [node("a", effect="external"), node("b")]):
            with self.assertRaises(TaskDagError):
                self.apply("revise", expected_revision=1, nodes=rows)

    def test_retired_ids_cannot_represent_new_effects(self):
        self.create([node(), node("b")])
        self.apply("revise", expected_revision=1, nodes=[node()])
        with self.assertRaises(TaskDagError):
            self.apply("revise", expected_revision=2, nodes=[node(), node("b")])

    def test_operation_replay_returns_original_result_without_new_event(self):
        first = self.apply("create", operation_id="create", objective="goal", nodes=[node()])
        self.claim()
        replay = self.apply("create", operation_id="create", objective="goal", nodes=[node()])
        self.assertEqual(first, replay)
        self.assertEqual(2, self.ledger.event_count())
        with self.assertRaises(AgentRunIdentityConflict):
            self.apply("create", operation_id="create", objective="different", nodes=[node()])

    def test_cross_scope_and_turn_replays_are_rejected(self):
        self.apply("create", operation_id="create", objective="goal", nodes=[node()])
        for key in ("client_route_id", "conversation_id", "goal_id", "task_id"):
            other = replace(self.root, **{key: "other"})
            with self.assertRaises(AgentRunIdentityConflict):
                self.store.load(other)
            with self.assertRaises(AgentRunIdentityConflict):
                self.store.apply(other, "pause", {"operation": "pause"}, turn_id="turn")
        with self.assertRaises(AgentRunIdentityConflict):
            self.store.apply(self.root, "create", {"operation": "create", "objective": "goal", "nodes": [node()]}, turn_id="other")

    def test_only_one_concurrent_worker_can_claim_node(self):
        self.create()
        def claim(index):
            store = DurableTaskDag(AgentRunEventLedger(self.path))
            try:
                store.apply(self.root, f"claim-{index}", {"operation": "claim", "node_id": "a", "owner": str(index)}, turn_id="turn")
                return True
            except TaskDagError:
                return False
        with ThreadPoolExecutor(max_workers=8) as pool:
            self.assertEqual(1, sum(pool.map(claim, range(16))))
        self.assertEqual(2, self.ledger.event_count())

    def test_atomic_ledger_failure_rolls_back_graph_and_event(self):
        previous = self.create()
        append = self.ledger.append
        def crash(*args, **kwargs):
            append(*args, **kwargs)
            raise RuntimeError("injected transaction failure")
        with patch.object(self.ledger, "append", side_effect=crash), self.assertRaises(RuntimeError):
            self.apply("revise", expected_revision=1, nodes=[node(), node("b")])
        self.assertEqual(previous, self.store.load(self.root))
        self.assertEqual(1, self.ledger.event_count())

    def test_restart_preserves_checkpoint_and_fences_stale_callback(self):
        self.create()
        old = self.claim()
        self.apply("checkpoint", node_id="a", token=old, data={"offset": 4096, "source": "content-hash"})
        self.store = DurableTaskDag(AgentRunEventLedger(self.path))
        recovered = self.apply("recover_owner", owner="worker")
        self.assertEqual(4096, recovered["nodes"]["a"]["checkpoint"]["offset"])
        new = self.claim(owner="new-worker")
        self.assertNotEqual(old, new)
        with self.assertRaises(TaskDagError):
            self.apply("complete", node_id="a", token=old, data={"late": True})
        self.apply("complete", node_id="a", token=new, data={"done": True})

    def test_recovery_does_not_touch_other_live_workers(self):
        self.create([node(), node("b")])
        self.claim(owner="dead")
        self.claim("b", owner="live")
        graph = self.apply("recover_owner", owner="dead")
        self.assertEqual("pending", graph["nodes"]["a"]["status"])
        self.assertEqual("running", graph["nodes"]["b"]["status"])

    def test_external_effect_requires_reconciliation_after_restart(self):
        self.create([node(effect="external")])
        old = self.claim()
        graph = self.apply("recover_owner", owner="worker")
        self.assertEqual("uncertain", graph["nodes"]["a"]["status"])
        self.assertEqual([], self.store.ready(self.root))
        for operation in ("claim", "retry"):
            with self.assertRaises(TaskDagError):
                self.apply(operation, node_id="a", owner="new", evidence="try again")
        with self.assertRaises(TaskDagError):
            self.apply("reconcile", node_id="a", outcome="completed", evidence="")
        graph = self.apply("reconcile", node_id="a", outcome="completed", evidence="Remote PR found by stable effect key")
        self.assertEqual("completed", graph["nodes"]["a"]["status"])
        with self.assertRaises(TaskDagError):
            self.apply("complete", node_id="a", token=old, data={})

    def test_uncertain_external_network_failure_is_not_blindly_retried(self):
        self.create([node(effect="external")])
        token = self.claim()
        graph = self.apply("fail", node_id="a", token=token, data={"error": "connection lost after send"})
        self.assertEqual("uncertain", graph["nodes"]["a"]["status"])
        self.apply("reconcile", node_id="a", outcome="not_applied", evidence="Remote read confirms operation absent")
        self.assertEqual(["a"], self.store.ready(self.root))

    def test_replayable_effect_keeps_idempotency_key_across_attempts(self):
        self.create([node(effect="replayable")])
        self.claim()
        before = self.store.load(self.root)["nodes"]["a"]["effect_key"]
        self.apply("recover_owner", owner="worker")
        self.claim(owner="new")
        self.assertEqual(before, self.store.load(self.root)["nodes"]["a"]["effect_key"])
        with self.assertRaises(TaskDagError):
            self.apply("revise", expected_revision=1, nodes=[node(effect="external")])

    def test_pause_persists_and_no_claim_is_possible_until_resume(self):
        self.create()
        self.apply("pause")
        self.store = DurableTaskDag(AgentRunEventLedger(self.path))
        self.assertEqual([], self.store.ready(self.root))
        with self.assertRaises(TaskDagError):
            self.claim()
        self.apply("resume")
        self.assertEqual(["a"], self.store.ready(self.root))

    def test_completion_requires_all_nodes_and_explicit_evidence(self):
        self.create()
        with self.assertRaises(TaskDagError):
            self.apply("finish", evidence="not enough")
        token = self.claim()
        self.apply("complete", node_id="a", token=token, data={"artifact": "hash"})
        with self.assertRaises(TaskDagError):
            self.apply("finish", evidence="")
        self.apply("finish", evidence="Artifact and acceptance checks verified")
        self.assertEqual("completed", self.ledger.snapshot("run")["state"])
        self.assertEqual([], self.store.recovery_page())
        with self.assertRaises(TaskDagError):
            self.apply("resume")

    def test_cancel_fences_results_and_is_durable(self):
        self.create()
        token = self.claim()
        self.apply("cancel")
        with self.assertRaises(TaskDagError):
            self.apply("complete", node_id="a", token=token, data={})
        self.assertEqual("cancelled", self.store.load(self.root)["status"])

    def test_no_cumulative_eight_action_budget(self):
        self.create()
        for attempt in range(24):
            token = self.claim()
            self.apply("fail", node_id="a", token=token, data={"attempt": attempt})
            self.apply("retry", node_id="a", evidence=f"Model selected a retry after observation {attempt}")
        self.assertEqual(24, self.store.load(self.root)["nodes"]["a"]["attempt"])
        self.assertEqual(["a"], self.store.ready(self.root))

    def test_invalid_json_and_injected_runtime_state_are_rejected(self):
        for nodes in ([{**node(), "status": "completed"}], [{**node(), "action": {"bad": float("nan")}}]):
            with self.assertRaises(TaskDagError):
                self.create(nodes)
        self.assertEqual(0, self.ledger.event_count())

    def test_started_pending_node_cannot_be_removed_after_recovery(self):
        self.create([node(), node("b")])
        self.claim()
        self.apply("recover_owner", owner="worker")
        with self.assertRaises(TaskDagError):
            self.apply("revise", expected_revision=1, nodes=[node("b")])

    def test_ordinary_steps_journal_only_changed_nodes(self):
        self.create([node(f"n-{index:04d}") for index in range(1000)])
        self.claim("n-0001")
        event = self.ledger.events("run")[-1]
        self.assertEqual(["n-0001"], list(event.payload["dag_patch"]["nodes"]))
        self.assertNotIn("nodes", event.payload["projection_checkpoint"]["data"])
        self.assertNotIn("dag_command", event.payload)
        self.assertLess(len(json.dumps(event.payload)), 1600)

    def test_duplicate_old_claim_never_returns_new_workers_token(self):
        self.create()
        command = {"operation": "claim", "node_id": "a", "owner": "old"}
        first = self.store.apply(self.root, "claim-old", command, turn_id="turn")
        self.apply("recover_owner", owner="old")
        new_token = self.claim(owner="new")
        replay = self.store.apply(self.root, "claim-old", command, turn_id="turn")
        self.assertEqual(first, replay)
        self.assertNotEqual(new_token, replay["nodes"]["a"]["lease"]["token"])
        self.assertEqual(new_token, self.store.load(self.root)["nodes"]["a"]["lease"]["token"])

    def test_recovery_index_is_paged_without_full_graphs(self):
        for index in range(7):
            root = replace(self.root, run_id=f"run-{index}")
            self.store.apply(root, "create", {"operation": "create", "objective": "goal", "nodes": [node()]}, turn_id="turn")
        found = []
        before = None
        while page := self.store.recovery_page(limit=2, before=before):
            self.assertLessEqual(len(page), 2)
            self.assertTrue(all("nodes" not in item["data"] for item in page))
            found.extend(item["run_id"] for item in page)
            last = page[-1]
            before = (last["updated_at_millis"], last["run_id"])
        self.assertEqual(7, len(set(found)))
        self.assertEqual(7, len(found))

    def test_node_projection_failure_rolls_back_run_event(self):
        original = self.create()
        with closing(sqlite3.connect(self.path)) as connection:
            connection.execute("""CREATE TRIGGER reject_dag_update BEFORE UPDATE ON agent_task_dag_nodes
                BEGIN SELECT RAISE(ABORT, 'injected node storage failure'); END""")
            connection.commit()
        with self.assertRaises(sqlite3.IntegrityError):
            self.claim()
        self.assertEqual(original, self.store.load(self.root))
        self.assertEqual(1, self.ledger.event_count())

    def test_replay_keeps_revision_and_retirement_history(self):
        first = self.create([node(), node("b")])
        revised = self.apply("revise", operation_id="revision", expected_revision=1, nodes=[node(), node("c", ["a"])])
        self.claim()
        replay = self.apply("revise", operation_id="revision", expected_revision=1, nodes=[node(), node("c", ["a"])])
        self.assertEqual(revised, replay)
        self.assertEqual(["b"], replay["retired_ids"])
        self.assertEqual(1, first["revision"])

    def test_real_process_exit_preserves_committed_checkpoint(self):
        self.create()
        code = """
import os, sys
from pathlib import Path
from agent_run_kernel import AgentRunEventLedger, AgentRunRootIdentity
from agent_task_dag_store import DurableTaskDag
store = DurableTaskDag(AgentRunEventLedger(Path(sys.argv[1])))
root = AgentRunRootIdentity('route', 'conversation', 'goal', 'task', 'run')
graph = store.apply(root, 'child-claim', {'operation':'claim', 'node_id':'a', 'owner':'child'}, turn_id='turn')
token = graph['nodes']['a']['lease']['token']
store.apply(root, 'child-checkpoint', {'operation':'checkpoint', 'node_id':'a', 'token':token, 'data':{'offset':8192}}, turn_id='turn')
os._exit(73)
"""
        result = subprocess.run([sys.executable, "-c", code, str(self.path)], cwd=Path(__file__).parent,
                                capture_output=True, timeout=30)
        self.assertEqual(73, result.returncode, result.stderr.decode(errors="replace"))
        self.store = DurableTaskDag(AgentRunEventLedger(self.path))
        graph = self.apply("recover_owner", owner="child")
        self.assertEqual(8192, graph["nodes"]["a"]["checkpoint"]["offset"])
        self.assertEqual(["a"], self.store.ready(self.root))

    def test_real_process_exit_during_transaction_leaves_no_partial_claim(self):
        original = self.create()
        code = """
import os, sys
from pathlib import Path
from agent_run_kernel import AgentRunEventLedger, AgentRunRootIdentity
from agent_task_dag_store import DurableTaskDag
ledger = AgentRunEventLedger(Path(sys.argv[1]))
store = DurableTaskDag(ledger)
append = ledger.append
def crash(*args, **kwargs):
    append(*args, **kwargs)
    os._exit(74)
ledger.append = crash
store.apply(AgentRunRootIdentity('route','conversation','goal','task','run'), 'child-claim',
    {'operation':'claim','node_id':'a','owner':'child'}, turn_id='turn')
"""
        result = subprocess.run([sys.executable, "-c", code, str(self.path)], cwd=Path(__file__).parent,
                                capture_output=True, timeout=30)
        self.assertEqual(74, result.returncode, result.stderr.decode(errors="replace"))
        self.assertEqual(original, self.store.load(self.root))
        self.assertEqual(1, self.ledger.event_count())

    def test_model_can_replace_observed_failed_branch_without_erasing_history(self):
        self.create([node(), node("b", ["a"])])
        token = self.claim()
        self.apply("fail", node_id="a", token=token, data={"error": "Source permanently unavailable"})
        replacement = [node("c"), node("b", ["c"])]
        with self.assertRaises(TaskDagError):
            self.apply("revise", expected_revision=1, nodes=replacement)
        graph = self.apply("revise", expected_revision=1, nodes=replacement, supersede_ids=["a"],
                           evidence="Model selected another data source after the failed observation")
        self.assertEqual(["a"], graph["retired_ids"])
        self.assertEqual(["c"], self.store.ready(self.root))
        failure = self.ledger.events("run")[2].payload["dag_patch"]["nodes"]["a"]
        self.assertEqual("Source permanently unavailable", failure["result"]["error"])

    def test_running_or_uncertain_effect_cannot_be_superseded(self):
        self.create([node(effect="external"), node("b")])
        self.claim()
        for recovered in (False, True):
            if recovered:
                self.apply("recover_owner", owner="worker")
            with self.assertRaises(TaskDagError):
                self.apply("revise", expected_revision=1, nodes=[node("b")], supersede_ids=["a"], evidence="Drop it")

    def test_model_node_order_survives_reopen_and_revision(self):
        self.create([node("z"), node("a"), node("m")])
        self.store = DurableTaskDag(AgentRunEventLedger(self.path))
        self.assertEqual(["z", "a", "m"], self.store.ready(self.root))
        self.apply("revise", expected_revision=1, nodes=[node("m"), node("z"), node("a")])
        self.store = DurableTaskDag(AgentRunEventLedger(self.path))
        self.assertEqual(["m", "z", "a"], self.store.ready(self.root))


if __name__ == "__main__":
    unittest.main()
