from __future__ import annotations

import json
from types import SimpleNamespace
import unittest

from evolution_v2.campaign_replanning import planning_messages
from evolution_v2.campaign_retry_admission import terminal_observation, require_replacement_evidence
from agent_task_dag import TaskDagError


class CandidateRecoveryObservationTests(unittest.TestCase):
    def task(self, code="acceptance_review_unavailable", checkpoint=True):
        return SimpleNamespace(task_id="child", status="blocked", attempts=[object()], max_attempts=1,
            last_error_code=code, last_error="Evaluator cannot compile original-goal constraints",
            candidate_checkpoint={"version": 1} if checkpoint else {}, candidate_commit="a" * 40,
            pull_request_url="")

    def test_unavailable_evaluator_is_not_reported_as_a_candidate_failure(self):
        for code in ("acceptance_review_unavailable", "acceptance_evidence_incomplete", "agent_review_unavailable"):
            with self.subTest(code=code):
                evidence = terminal_observation(self.task(code))
                self.assertEqual("candidate_evaluation", evidence["failure_phase"])
                self.assertEqual("unavailable", evidence["candidate_verdict"])
                self.assertFalse(evidence["candidate_failure_established"])
                self.assertTrue(evidence["retryable"])
                self.assertEqual(0, evidence["attempts_remaining"])
                self.assertEqual("resume_candidate_validation_without_reimplementation", evidence["retry_effect"])

    def test_definite_candidate_failure_does_not_inherit_unavailable_verdict(self):
        evidence = terminal_observation(self.task("acceptance_review_failed", checkpoint=False))
        self.assertNotIn("candidate_failure_established", evidence)
        self.assertNotIn("candidate_verdict", evidence)
        self.assertFalse(evidence["retryable"])
        self.assertEqual("child_attempts_exhausted", evidence["retry_blocker"])

    def test_identity_conflict_does_not_claim_an_evaluator_fault(self):
        evidence = terminal_observation(self.task("candidate_checkpoint_invalid"))
        self.assertNotIn("failure_phase", evidence)
        self.assertNotIn("candidate_failure_established", evidence)

    def test_planner_receives_structured_phase_and_continuation_semantics(self):
        graph = {"nodes": {"n": {"action": {"proposal_id": "p"}, "result": terminal_observation(self.task())}}}
        messages = planning_messages(graph, SimpleNamespace(get_proposal=lambda _: None))
        self.assertEqual(graph, json.loads(messages[1]["content"])["graph"])
        instruction = messages[0]["content"]
        self.assertIn("even if attempts_remaining is zero", instruction)
        self.assertIn("without candidate_continuation", instruction)
        self.assertIn("Do not replace or rewrite implementation merely to fix evaluator", instruction)
        self.assertIn("an evaluator's invented literal is not a new output requirement", instruction)

    def test_unassessed_candidate_cannot_be_superseded_by_replace_or_revise(self):
        graph = {"nodes": {"n": {"result": terminal_observation(self.task())}}}
        for decision in ({"operation": "replace", "node_id": "n"},
                         {"operation": "revise", "supersede_ids": ["n"]}):
            with self.subTest(operation=decision["operation"]):
                with self.assertRaisesRegex(TaskDagError, "no usable verdict"):
                    require_replacement_evidence(graph, decision)

    def test_candidate_continuation_still_allows_retry_wait_and_diagnostic_work(self):
        graph = {"nodes": {"n": {"result": terminal_observation(self.task())}}}
        for decision in ({"operation": "retry", "node_id": "n"}, {"operation": "wait"},
                         {"operation": "revise", "supersede_ids": []}):
            require_replacement_evidence(graph, decision)

    def test_definite_rejection_can_be_replanned(self):
        graph = {"nodes": {"n": {"result": terminal_observation(self.task("acceptance_review_failed", checkpoint=False))}}}
        require_replacement_evidence(graph, {"operation": "replace", "node_id": "n"})

    def test_validation_constraints_deduplicate_without_carrying_old_responses(self):
        from evolution_v2.planning_feedback import retain_validation_constraints
        first = {"stage": "validate", "error_type": "TaskDagError", "detail": "First condition", "previous_response": "old output"}
        second = {**first, "detail": "Second condition", "previous_response": "new output"}
        saved = retain_validation_constraints(second, first)
        repeated = retain_validation_constraints(second, saved)
        repeated = retain_validation_constraints(second, repeated)
        self.assertEqual(2, len(repeated["prior_validation_constraints"]))
        self.assertNotIn("old output", json.dumps(repeated))


if __name__ == "__main__":
    unittest.main()
