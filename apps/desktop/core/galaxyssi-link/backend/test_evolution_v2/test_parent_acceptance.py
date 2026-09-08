from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import Mock, patch
import unittest

from evolution_v2.acceptance_evidence import collect_evidence
from evolution_v2.candidate_acceptance import CandidateAcceptance, review_schema, validate_result
from evolution_v2.legacy import EvolutionError
from test_evolution_v2 import test_candidate_acceptance as fixtures


class ParentAcceptanceTests(unittest.TestCase):
    setUp = fixtures.CandidateAcceptanceTests.setUp
    git = fixtures.CandidateAcceptanceTests.git
    infer = fixtures.CandidateAcceptanceTests.infer
    manager = fixtures.CandidateAcceptanceTests.manager
    task = fixtures.CandidateAcceptanceTests.task
    prepared = fixtures.CandidateAcceptanceTests.prepared

    def test_parent_goal_is_a_required_assessment_not_just_context(self):
        manager, task = self.prepared()
        objective = "Append a section named Recovery checklist. Preserve all original text. Then the host publishes a PR."
        context = {"campaign_id": "campaign", "campaign_objective": objective}
        evidence = collect_evidence(task, Path(task.attempts[-1].worktree), task.candidate_commit, context, manager.runner)
        required = {row["id"]: row["text"] for row in evidence["requirements"]}
        self.assertEqual(objective, required["parent-intent"])
        self.assertEqual(task.problem, required["task"])
        self.assertEqual(task.acceptance[0], required["criterion-1"])
        self.assertIn("parent-intent", review_schema(list(required))["properties"]["assessments"]["required"])

    def test_complete_original_goal_is_preserved_without_excerpting(self):
        manager, task = self.prepared()
        objective = "\u4fdd\u7559\u539f\u6587\u5e76\u8ffd\u52a0\u6307\u5b9a\u6807\u9898\u3002" * 400
        evidence = collect_evidence(task, Path(task.attempts[-1].worktree), task.candidate_commit,
                                    {"campaign_objective": objective}, manager.runner)
        self.assertEqual(objective, next(row["text"] for row in evidence["requirements"] if row["id"] == "parent-intent"))

    def test_invalid_or_missing_owned_parent_goal_cannot_be_omitted(self):
        manager, task = self.prepared()
        for context in ({"campaign_id": "campaign"}, {"campaign_objective": None},
                        {"campaign_objective": " "}, {"campaign_objective": []}):
            with self.subTest(context=context), self.assertRaises(EvolutionError) as caught:
                collect_evidence(task, Path(task.attempts[-1].worktree), task.candidate_commit, context, manager.runner)
            self.assertEqual("acceptance_evidence_incomplete", caught.exception.code)

    def test_reviewer_cannot_omit_parent_assessment_even_when_all_child_rows_pass(self):
        evidence = {"requirements": [{"id": "task"}, {"id": "parent-intent"}, {"id": "criterion-1"}]}
        result = fixtures.assessment(evidence)
        result["assessments"] = [row for row in result["assessments"] if row["id"] != "parent-intent"]
        with self.assertRaises(ValueError):
            validate_result(result, [row["id"] for row in evidence["requirements"]])

    def test_parent_failure_rejects_retained_candidate_despite_passing_child_rows(self):
        manager, task = self.prepared()
        context = {"campaign_id": "campaign", "campaign_objective": "Add the required section heading and preserve original text"}
        def verify(messages, **kwargs):
            evidence = json.loads(messages[-1]["content"])
            result = fixtures.assessment(evidence)
            parent = next(row for row in result["assessments"] if row["id"] == "parent-intent")
            parent.update(verdict="fail", evidence="The requested section heading is missing from the candidate")
            return json.dumps(result)
        manager.acceptance_verifier = CandidateAcceptance(verify, contract_infer=lambda *args, **kwargs: '{"checks":[]}',
            preservation_infer=fixtures.unrestricted)
        with patch.object(manager, "_implementation_context", return_value=context):
            failed = manager.revalidate_candidate(task.task_id)
        self.assertEqual("failed", failed.status)
        self.assertEqual("acceptance_review_failed", failed.last_error_code)
        self.assertIn("parent-intent", failed.last_error)
        self.assertFalse(failed.approval_hash)
        self.assertEqual(task.candidate_commit, failed.candidate_commit)

    def test_manual_task_does_not_gain_an_invented_parent_goal(self):
        manager, task = self.prepared()
        evidence = collect_evidence(task, Path(task.attempts[-1].worktree), task.candidate_commit, {}, manager.runner)
        self.assertNotIn("parent-intent", [row["id"] for row in evidence["requirements"]])

    def test_literal_failure_clears_approval_and_retains_actual_git_candidate(self):
        manager, task = self.prepared()
        worktree = Path(task.attempts[-1].worktree)
        context = {"campaign_id": "campaign", "campaign_objective": "Append a Recovery checklist section"}
        def compile_goal(messages, **kwargs):
            source = json.loads(messages[-1]["content"])
            return json.dumps({"checks": [{"kind": "markdown_heading", "path": source["paths"][0],
                "text": "Recovery checklist", "case_sensitive": False}]})
        reviewer = Mock(side_effect=AssertionError("Host failure must not reach semantic review"))
        manager.acceptance_verifier = CandidateAcceptance(reviewer, compile_goal)
        with patch.object(manager, "_implementation_context", return_value=context):
            failed = manager.revalidate_candidate(task.task_id)
        self.assertEqual("failed", failed.status)
        self.assertEqual("acceptance_review_failed", failed.last_error_code)
        self.assertIn("markdown_heading", failed.last_error)
        self.assertFalse(failed.approval_hash)
        self.assertEqual(task.candidate_commit, failed.candidate_commit)
        self.assertTrue(worktree.is_dir())
        reviewer.assert_not_called()
        proof = manager.v2_store.get_task_metadata(task.task_id).review["acceptance"]
        self.assertFalse(proof["goal_checks"][0]["passed"])
        self.assertEqual("Recovery checklist", proof["goal_contract"]["checks"][0]["text"])


if __name__ == "__main__":
    unittest.main()
