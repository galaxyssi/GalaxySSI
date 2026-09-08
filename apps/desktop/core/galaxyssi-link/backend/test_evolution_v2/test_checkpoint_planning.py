import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

from agent_run_kernel import AgentRunEventLedger
from evolution_v2.campaigns import CampaignManager
from evolution_v2.campaign_planner import EvolutionCampaignPlanner
from evolution_v2.common import read_json
from evolution_v2.models import EvolutionProposal
from evolution_v2.storage import EvolutionV2Store
from agent_task_dag import TaskDagError


class CheckpointPlanningTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.store = EvolutionV2Store(self.root / "v2")
        self.store.save_proposal(EvolutionProposal("p", "Task", "Deliver requested change", ["docs"], ["Verified output"]))
        self.tasks, self.starts = {}, []
        def ensure(proposal, campaign_id, task_id):
            return self.tasks.setdefault(task_id, SimpleNamespace(task_id=task_id, status="proposed"))
        def start(task_id):
            self.starts.append(task_id)
            self.tasks[task_id].status = "running"
        self.campaigns = CampaignManager(self.store, task_factory=Mock(), task_ensurer=ensure,
            task_getter=lambda key: self.tasks[key], task_starter=start,
            run_ledger=AgentRunEventLedger(self.root / "runs.sqlite3"))
        self.manager = SimpleNamespace(v2_store=self.store, campaigns=self.campaigns, audit=Mock(),
                                      policy=SimpleNamespace(decide=lambda *args: SimpleNamespace(allowed=True)))
        self.config = {"enabled": True, "auto_start_tasks": True}
        self.infer = Mock(return_value=self.assessment("needs_work"))
        self.planner = self.reopen()
        self.campaign = self.campaigns.create("Campaign", "Preserve the complete original objective", [
            {"node_id": "a", "proposal_id": "p"}, {"node_id": "b", "proposal_id": "p", "depends_on": ["a"]}],
            auto_start_safe_nodes=True)
        self.key = self.campaign.campaign_id
        self.campaigns.tick(self.key)
        self.tasks[self.starts[0]].status = "completed"
        self.campaigns.tick(self.key)

    def reopen(self):
        return EvolutionCampaignPlanner(self.manager, lambda: self.config, self.infer)

    def graph(self):
        durable = self.campaigns.durable
        return durable.graph_store.load(durable.identity(self.key))

    def decision(self):
        return self.assessment("satisfied")

    @staticmethod
    def assessment(verdict):
        return json.dumps({"assessments": {"b": {"verdict": verdict, "evidence": "Observed result already covers it"}}})

    def proof(self):
        return {"assessments": {key: {"verdict": "pass", "evidence": "Completed node provides the verified output",
            "completed_node_ids": ["a"]} for key in ("b:task", "b:criterion-1")}}

    def test_first_batch_runs_but_next_batch_waits_for_model_observation(self):
        self.assertEqual(1, len(self.starts))
        self.assertEqual("pending", self.graph()["nodes"]["b"]["status"])
        self.planner.tick()
        self.campaigns.tick(self.key)
        self.campaigns.tick(self.key)
        self.assertEqual(2, len(self.starts))
        self.infer.assert_called_once()

    def test_persisted_proceed_survives_planner_restart_without_new_inference(self):
        self.planner.tick()
        self.planner = self.reopen()
        self.planner.tick()
        self.campaigns.tick(self.key)
        self.assertEqual(2, len(self.starts))
        self.infer.assert_called_once()

    def test_old_contract_cannot_dispatch_and_is_reviewed_again(self):
        from evolution_v2.common import atomic_write_json
        path = self.planner.checkpoints.path(self.key)
        self.planner.tick()
        record = read_json(path)
        record.pop("contract")
        atomic_write_json(path, record)
        self.campaigns.tick(self.key)
        self.assertEqual(1, len(self.starts))
        self.planner.tick()
        self.campaigns.tick(self.key)
        self.assertEqual(2, self.infer.call_count)
        self.assertEqual(2, len(self.starts))

    def test_wait_does_not_poll_model_for_unchanged_observation(self):
        self.infer.return_value = self.assessment("inconclusive")
        self.planner.tick()
        for _ in range(4):
            self.campaigns.tick(self.key)
            self.planner.tick()
        self.assertEqual(1, len(self.starts))
        self.infer.assert_called_once()

    def test_independently_satisfied_node_is_retired_not_executed_or_goal_completed(self):
        self.infer.side_effect = [self.decision(), json.dumps(self.proof())]
        self.planner.tick()
        self.campaigns.tick(self.key)
        graph = self.graph()
        self.assertEqual(["b"], graph["retired_ids"])
        self.assertEqual(["a"], list(graph["nodes"]))
        self.assertEqual("active", graph["status"])
        self.assertEqual("Preserve the complete original objective", graph["objective"])
        self.assertEqual(1, len(self.starts))
        self.assertEqual(2, self.infer.call_count)
        self.assertNotIn("Observed result already covers it", str(self.infer.call_args.args[0]))
        proofs = list((self.planner.root / "checkpoint-proofs").glob("*.json"))
        self.assertEqual(1, len(proofs))
        proof = read_json(proofs[0])
        self.assertEqual(graph["objective"], proof["evidence"]["graph"]["objective"])
        self.assertEqual(self.proof(), proof["retirement_proof"])

    def test_missing_requirement_or_unfinished_support_cannot_retire(self):
        for mode in ("missing", "failed", "inconclusive", "unexecuted"):
            proof = self.proof()
            if mode == "missing":
                proof["assessments"].pop("b:criterion-1")
            elif mode == "unexecuted":
                proof["assessments"]["b:task"]["completed_node_ids"] = ["b"]
            else:
                proof["assessments"]["b:task"]["verdict"] = mode
            self.infer.side_effect = [self.decision(), json.dumps(proof)]
            with self.subTest(mode=mode), patch("evolution_v2.checkpoint_planning.read_json", return_value={}):
                self.planner.tick()
            self.assertIn("b", self.graph()["nodes"])
            self.assertEqual(1, len(self.starts))

    def test_disabled_during_inference_does_not_dispatch_or_retire(self):
        def infer(messages, **kwargs):
            self.config["enabled"] = False
            return self.assessment("needs_work")
        self.infer.side_effect = infer
        self.planner.tick()
        self.campaigns.tick(self.key)
        self.assertEqual(1, len(self.starts))

    def test_pause_during_inference_rejects_stale_decision(self):
        def infer(messages, **kwargs):
            self.campaigns.control(self.key, "pause", "during-model")
            return self.assessment("needs_work")
        self.infer.side_effect = infer
        self.planner.tick()
        self.assertEqual("paused", self.graph()["status"])
        self.assertEqual("checkpoint_error", read_json(self.planner.checkpoints.path(self.key))["status"])

    def test_changed_graph_invalidates_previously_approved_batch(self):
        self.planner.tick()
        self.campaigns.revise(self.key, [{"node_id": "a", "proposal_id": "p"},
            {"node_id": "b", "proposal_id": "p", "depends_on": ["a"]}], 1, "new-plan")
        self.campaigns.tick(self.key)
        self.assertEqual(1, len(self.starts))
        self.planner.tick()
        self.campaigns.tick(self.key)
        self.assertEqual(2, self.infer.call_count)
        self.assertEqual(2, len(self.starts))

    def test_model_error_is_observed_and_does_not_start_new_work(self):
        self.infer.return_value = "not JSON"
        self.planner.tick()
        self.planner.tick()
        self.campaigns.tick(self.key)
        record = read_json(self.planner.checkpoints.path(self.key))
        self.assertEqual("checkpoint_error", record["status"])
        self.assertEqual("JSONDecodeError", record["validation_feedback"])
        self.assertEqual(1, len(self.starts))
        self.infer.assert_called_once()

    def publication_fixture(self):
        graph = self.graph()
        graph["nodes"]["a"]["result"] = {"stage": "completed", "pull_request_url": "https://github.com/owner/project/pull/7",
            "head_sha": "a" * 40, "integration_commit": "b" * 40}
        raw = {"number": 7, "head": {"sha": "a" * 40}, "merged": True, "state": "closed",
            "base": {"ref": "main", "repo": {"full_name": "owner/project"}}, "merge_commit_sha": "b" * 40,
            "title": "Verified candidate", "body": "Actual PR body", "changed_files": 1}
        pages = [[{"filename": "docs/change.md", "status": "modified", "sha": "c" * 40}]]
        def api(args):
            if "/files?" in args[-1]:
                return pages
            if "/commits/" in args[-1]:
                return {"sha": "a" * 40, "commit": {"message": "Actual commit"}}
            return raw
        self.manager.github = SimpleNamespace(_api=Mock(side_effect=api))
        return graph, raw, pages

    def test_publication_text_and_files_are_host_facts_not_guessed_from_url(self):
        graph, raw, pages = self.publication_fixture()
        data = self.planner.checkpoints.evidence(graph, self.store)
        published = data["publications"]["a"]
        self.assertEqual(raw["body"], published["body"])
        self.assertEqual("Actual commit", published["commit_message"])
        self.assertEqual("docs/change.md", published["files"][0]["filename"])
        self.assertEqual(3, self.manager.github._api.call_count)

    def test_publication_partial_pages_changed_head_and_merge_are_rejected(self):
        for mode in ("pages", "head", "merge", "duplicate", "oversized", "not_verified"):
            graph, raw, pages = self.publication_fixture()
            if mode == "pages":
                raw["changed_files"] = 2
            elif mode == "duplicate":
                pages[0].append(dict(pages[0][0]))
                raw["changed_files"] = 2
            elif mode == "head":
                raw["head"]["sha"] = "d" * 40
            elif mode == "merge":
                raw["merge_commit_sha"] = "d" * 40
            elif mode == "oversized":
                raw["body"] = "x" * 32769
            else:
                graph["nodes"]["a"]["result"]["stage"] = "awaiting_ci"
            with self.subTest(mode=mode), self.assertRaises(TaskDagError):
                self.planner.checkpoints.evidence(graph, self.store)

    def test_started_or_foreign_node_cannot_be_retired(self):
        for keys in (["a"], ["absent"], ["b", "b"], []):
            with self.subTest(keys=keys), self.assertRaises(TaskDagError):
                self.planner.checkpoints.verify_retirement(self.graph(), {}, {"node_ids": keys})
            self.assertEqual(["a", "b"], list(self.graph()["nodes"]))

    def test_crash_after_graph_revision_does_not_repeat_retirement_or_execution(self):
        from evolution_v2.common import atomic_write_json
        path = self.planner.checkpoints.path(self.key)
        def write(destination, value):
            if destination == path and value.get("status") == "applied":
                raise OSError("Crash after graph transaction")
            return atomic_write_json(destination, value)
        self.infer.side_effect = [self.decision(), json.dumps(self.proof())]
        with patch("evolution_v2.checkpoint_planning.atomic_write_json", side_effect=write), self.assertRaises(OSError):
            self.planner.tick()
        self.planner = self.reopen()
        self.planner.tick()
        self.campaigns.tick(self.key)
        self.assertEqual(["b"], self.graph()["retired_ids"])
        self.assertEqual(1, len(self.starts))
        self.assertEqual(2, self.infer.call_count)

    def test_rejected_decision_returns_actual_constraint_to_next_model_observation(self):
        self.infer.return_value = self.decision()
        self.planner.tick()
        self.infer.return_value = self.assessment("inconclusive")
        with patch("evolution_v2.checkpoint_planning.now_millis", return_value=9999999999999):
            self.planner.tick()
        self.assertIn("Independent checkpoint review did not assess every requirement", str(self.infer.call_args.args[0]))

    def test_retirement_keeps_transitive_dependency_for_unfinished_successor(self):
        self.campaigns.revise(self.key, [{"node_id": "a", "proposal_id": "p"},
            {"node_id": "b", "proposal_id": "p", "depends_on": ["a"]},
            {"node_id": "c", "proposal_id": "p", "depends_on": ["b"]}], 1, "third-step")
        self.infer.side_effect = [self.decision(), json.dumps(self.proof())]
        self.planner.tick()
        self.assertEqual(["a"], self.graph()["nodes"]["c"]["depends_on"])
        self.assertEqual(["b"], self.graph()["retired_ids"])
        self.campaigns.tick(self.key)
        self.assertEqual(1, len(self.starts))

    def test_typed_ready_assessments_reject_missing_foreign_and_invalid_verdicts(self):
        from evolution_v2.checkpoint_decision import parse_assessments
        for value in ({"operation": "proceed", "reason": "Already done"}, {"assessments": {}},
                {"assessments": {"a": {"verdict": "satisfied", "evidence": "Done"}}},
                {"assessments": {"b": {"verdict": "pass", "evidence": "Done"}}},
                {"assessments": {"b": {"verdict": "needs_work", "evidence": ""}}}):
            with self.subTest(value=value), self.assertRaises(TaskDagError):
                parse_assessments(value, self.graph())

    def test_independent_review_rejects_extra_fields_and_missing_support(self):
        for mode in ("extra", "empty", "nonstring"):
            proof = self.proof()
            row = proof["assessments"]["b:task"]
            if mode == "extra":
                row["claim"] = "Pass anyway"
            elif mode == "empty":
                row["completed_node_ids"] = []
            else:
                row["completed_node_ids"] = [1]
            self.infer.return_value = json.dumps(proof)
            with self.subTest(mode=mode), self.assertRaises(TaskDagError):
                self.planner.checkpoints.verify_retirement(self.graph(),
                    self.planner.checkpoints.evidence(self.graph(), self.store), {"node_ids": ["b"]})

    def test_inconclusive_node_does_not_block_independent_ready_work(self):
        self.campaigns.revise(self.key, [{"node_id": "a", "proposal_id": "p"},
            {"node_id": "b", "proposal_id": "p", "depends_on": ["a"]},
            {"node_id": "c", "proposal_id": "p", "depends_on": ["a"]}], 1, "independent-step")
        self.infer.return_value = json.dumps({"assessments": {
            "b": {"verdict": "needs_work", "evidence": "Required output is not implemented"},
            "c": {"verdict": "inconclusive", "evidence": "Evidence is unavailable"}}})
        self.planner.tick()
        self.campaigns.tick(self.key)
        self.assertEqual("running", self.graph()["nodes"]["b"]["status"])
        self.assertEqual("pending", self.graph()["nodes"]["c"]["status"])
        self.assertEqual(2, len(self.starts))

    def test_explicit_manual_dispatch_keeps_existing_behavior_when_planner_is_disabled(self):
        self.config["enabled"] = False
        self.campaigns.tick(self.key, start_ready=True)
        self.assertEqual(2, len(self.starts))
        self.infer.assert_not_called()

    def test_manual_campaign_does_not_need_automatic_planning(self):
        from evolution_v2.checkpoint_planning import needs_checkpoint
        graph = self.graph()
        graph["context"]["auto_start"] = False
        self.assertFalse(needs_checkpoint(graph))

    def scoped_responses(self, verdict="pass"):
        field = "/publications/a/commit_message"
        scopes = json.dumps({"scopes": {key: {"field_ids": [field], "reason": "Review the requested field"}
                                       for key in ("b:task", "b:criterion-1")}})
        review = json.dumps({"verdict": verdict, "evidence": "Observed commit message",
                             "quotes": [{"field_id": field, "quote": "Actual commit"}]})
        return [self.decision(), scopes, review, review, json.dumps(self.proof())]

    def scoped_fixture(self):
        graph, _, _ = self.publication_fixture()
        return self.planner.checkpoints.evidence(graph, self.store)

    def test_scoped_failure_prevents_broad_review_and_retirement_and_survives_restart(self):
        evidence = self.scoped_fixture()
        self.infer.side_effect = self.scoped_responses("fail")
        with patch.object(self.planner.checkpoints, "evidence", return_value=evidence):
            self.planner.tick()
        record = read_json(self.planner.checkpoints.path(self.key))
        self.assertEqual("checkpoint_error", record["status"])
        self.assertEqual("fail", record["scoped_evidence_review"]["checks"]["b:task"]["verdict"])
        self.assertEqual(3, self.infer.call_count)
        self.assertIn("b:task", record["validation_feedback"])
        self.assertIn("campaign_checkpoint_field_reviewed", str(self.manager.audit.append.call_args_list))
        self.planner = self.reopen()
        self.planner.tick()
        self.campaigns.tick(self.key)
        self.assertEqual("pending", self.graph()["nodes"]["b"]["status"])
        self.assertEqual(1, len(self.starts))
        self.assertEqual(3, self.infer.call_count)

    def test_scoped_success_still_requires_broad_independent_pass(self):
        evidence = self.scoped_fixture()
        responses = self.scoped_responses()
        broad = self.proof()
        broad["assessments"]["b:criterion-1"]["verdict"] = "fail"
        responses[-1] = json.dumps(broad)
        self.infer.side_effect = responses
        with patch.object(self.planner.checkpoints, "evidence", return_value=evidence):
            self.planner.tick()
        self.assertEqual(5, self.infer.call_count)
        self.assertIn("b", self.graph()["nodes"])
        record = read_json(self.planner.checkpoints.path(self.key))
        self.assertEqual("checkpoint_error", record["status"])
        self.assertEqual(2, len(record["scoped_evidence_review"]["checks"]))

    def test_both_reviews_archive_scoped_proof_without_completing_goal(self):
        evidence = self.scoped_fixture()
        self.infer.side_effect = self.scoped_responses()
        with patch.object(self.planner.checkpoints, "evidence", return_value=evidence):
            self.planner.tick()
        self.assertEqual(["b"], self.graph()["retired_ids"])
        self.assertEqual("active", self.graph()["status"])
        archived = read_json(next((self.planner.root / "checkpoint-proofs").glob("*.json")))
        self.assertEqual(2, len(archived["retirement_proof"]["scoped_evidence"]["checks"]))
        self.assertEqual(5, self.infer.call_count)

    def test_changed_publication_after_both_reviews_cannot_retire(self):
        from copy import deepcopy
        evidence = self.scoped_fixture()
        changed = deepcopy(evidence)
        changed["publications"]["a"]["body"] = "Changed during verification"
        self.infer.side_effect = self.scoped_responses()
        with patch.object(self.planner.checkpoints, "evidence", side_effect=[evidence, changed]):
            self.planner.tick()
        record = read_json(self.planner.checkpoints.path(self.key))
        self.assertEqual("checkpoint_error", record["status"])
        self.assertIn("changed while", record["validation_feedback"])
        self.assertIn("b", self.graph()["nodes"])

    def test_disabling_after_scope_selection_stops_all_remaining_reviews(self):
        evidence = self.scoped_fixture()
        responses = iter(self.scoped_responses())
        def infer(*args, **kwargs):
            response = next(responses)
            if "scopes" in json.loads(response):
                self.config["enabled"] = False
            return response
        self.infer.side_effect = infer
        with patch.object(self.planner.checkpoints, "evidence", return_value=evidence):
            self.planner.tick()
        self.assertEqual(2, self.infer.call_count)
        self.assertIn("b", self.graph()["nodes"])

    def test_disabling_in_last_field_review_does_not_invoke_broad_review(self):
        evidence = self.scoped_fixture()
        responses = iter(self.scoped_responses())
        def infer(*args, **kwargs):
            response = next(responses)
            if self.infer.call_count == 4:
                self.config["enabled"] = False
            return response
        self.infer.side_effect = infer
        with patch.object(self.planner.checkpoints, "evidence", return_value=evidence):
            self.planner.tick()
        self.assertEqual(4, self.infer.call_count)
        self.assertIn("b", self.graph()["nodes"])

    def test_duplicate_broad_verdict_cannot_overwrite_failure(self):
        proof = json.dumps(self.proof()).replace('"verdict": "pass"', '"verdict": "fail", "verdict": "pass"', 1)
        self.infer.side_effect = [self.decision(), proof]
        self.planner.tick()
        self.assertIn("b", self.graph()["nodes"])
        record = read_json(self.planner.checkpoints.path(self.key))
        self.assertEqual("checkpoint_error", record["status"])
        self.assertIn("duplicate", record["validation_feedback"])

    def test_duplicate_planning_assessment_cannot_grant_dispatch(self):
        self.infer.return_value = ('{"assessments":{"b":{"verdict":"inconclusive",'
                                  '"verdict":"needs_work","evidence":"Do it anyway"}}}')
        self.planner.tick()
        self.campaigns.tick(self.key)
        self.assertEqual(1, len(self.starts))
        self.assertEqual("checkpoint_error", read_json(self.planner.checkpoints.path(self.key))["status"])


if __name__ == "__main__":
    unittest.main()
