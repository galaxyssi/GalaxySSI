from __future__ import annotations

import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock

from evolution_v2.acceptance_evidence import collect_evidence, EVIDENCE_LIMIT
from evolution_v2.candidate_acceptance import CandidateAcceptance, validate_result
from evolution_v2.legacy import EvolutionError, EvolutionStore, GateCommand
from evolution_v2.local_planning import LocalPlannerUnavailable
from evolution_v2.manager import EvolutionManager


def assessment(evidence, verdict="pass", reason="Controlled test evidence"):
    return {"verdict": verdict, "findings": [] if verdict == "pass" else [reason], "assessments": [
        {"id": item["id"], "verdict": verdict, "evidence": reason} for item in evidence["requirements"]],
        "file_requirements": {path: {"preservation": "none", "reason": "Controlled fixture"} for path in evidence.get("files", {})}}


class CandidateAcceptanceTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = self.root / "source"
        self.source.mkdir()
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Acceptance Test")
        self.git("config", "user.email", "test@galaxyssi.local")
        (self.source / "docs").mkdir()
        (self.source / "docs/readme.md").write_text("Original documentation\n", encoding="utf-8")
        self.git("add", ".")
        self.git("commit", "-m", "Initial")
        self.base = self.git("rev-parse", "HEAD")
        self.origin = self.root / "origin.git"
        self.git("init", "--bare", str(self.origin))
        self.git("remote", "add", "origin", str(self.origin))
        self.git("push", "origin", "main")
        self.seen = []
        self.verdicts = []

    def git(self, *args):
        result = subprocess.run(["git", *args], cwd=self.source, capture_output=True, text=True, timeout=30)
        self.assertEqual(0, result.returncode, result.stderr)
        return result.stdout.strip()

    def infer(self, messages, **kwargs):
        self.assertIn("response_schema", kwargs)
        evidence = json.loads(messages[-1]["content"])
        self.seen.append(evidence)
        verdict = self.verdicts.pop(0) if self.verdicts else "pass"
        return json.dumps(assessment(evidence, verdict, "Preserve the original text and append the requested section"))

    def manager(self, patch_agent=None):
        class FocusedManager(EvolutionManager):
            def _gate_commands(self, changed_files):
                return [GateCommand("git-diff-check", ("git", "diff", "--check"))]
        return FocusedManager(source_root=self.source, store=EvolutionStore(self.root / "state"),
                              patch_agent=patch_agent, acceptance_infer=self.infer)

    def task(self, manager):
        return manager.create(problem="Append a checklist", scope=["docs"],
                              acceptance=["Preserve original documentation", "Append the new section"],
                              risk_level="low", max_attempts=2)

    def prepared(self):
        def edit(task, attempt, path, failure):
            (path / "docs/readme.md").write_text("Wrong replacement\n", encoding="utf-8")
            return "Controlled candidate"
        manager = self.manager(edit)
        task = manager.run_sync(self.task(manager).task_id)
        self.assertEqual("waiting_approval", task.status, task.last_error)
        return manager, task

    def test_semantic_failure_returns_to_implementation_with_real_diff_and_requirements(self):
        self.verdicts = ["fail", "pass"]
        failures = []
        def edit(task, attempt, path, failure):
            failures.append(failure)
            content = "Wrong replacement\n" if attempt.number == 1 else "Original documentation\n\nChecklist\n"
            (path / "docs/readme.md").write_text(content, encoding="utf-8")
            return "Candidate edited"
        manager = self.manager(edit)
        self.assertFalse(manager.policy.quality("agent_review", False))
        result = manager.run_sync(self.task(manager).task_id)
        self.assertEqual("waiting_approval", result.status, result.last_error)
        self.assertEqual(2, len(result.attempts))
        self.assertEqual("acceptance_review_failed", result.attempts[0].failure_code)
        self.assertIn("Preserve the original", failures[1])
        self.assertIn("-Original documentation", self.seen[0]["diff"])
        snapshot = self.seen[0]["files"]["docs/readme.md"]
        self.assertEqual("Original documentation\n", snapshot["before"])
        self.assertEqual("Wrong replacement\n", snapshot["after"])
        self.assertFalse(snapshot["original_text_present"])
        self.assertTrue(self.seen[1]["files"]["docs/readme.md"]["original_text_is_prefix"])
        self.assertEqual(3, len(self.seen[0]["requirements"]))
        self.assertEqual("Original documentation\n", (self.source / "docs/readme.md").read_text())

    def test_revalidation_preserves_wrong_candidate_and_invalidates_old_approval(self):
        manager, task = self.prepared()
        worktree = Path(task.attempts[-1].worktree)
        old_commit = task.candidate_commit
        self.verdicts = ["fail"]
        result = manager.revalidate_candidate(task.task_id)
        self.assertEqual("failed", result.status)
        self.assertEqual("acceptance_review_failed", result.last_error_code)
        self.assertEqual("", result.approval_hash)
        self.assertEqual(old_commit, result.candidate_commit)
        self.assertTrue(worktree.is_dir())
        self.assertEqual("Wrong replacement\n", (worktree / "docs/readme.md").read_text())
        self.assertEqual(0, manager.active_worker_count())

    def test_publication_rechecks_legacy_candidate_before_any_remote_push(self):
        manager, task = self.prepared()
        metadata = manager.v2_store.get_task_metadata(task.task_id)
        metadata.review = {}
        manager.v2_store.save_task_metadata(metadata)
        manager.github.authenticated = Mock(return_value=True)
        manager._publish_remote_candidate = Mock(side_effect=AssertionError("must not push"))
        self.verdicts = ["fail"]
        with self.assertRaises(EvolutionError) as caught:
            manager.publish(task.task_id, task.approval_hash)
        self.assertEqual("acceptance_review_failed", caught.exception.code)
        self.assertEqual("failed", manager.require(task.task_id).status)
        manager._publish_remote_candidate.assert_not_called()

    def test_unavailable_revalidation_can_resume_without_reimplementing_candidate(self):
        manager, task = self.prepared()
        manager.acceptance_verifier = CandidateAcceptance(Mock(side_effect=LocalPlannerUnavailable("HTTP 503")))
        blocked = manager.revalidate_candidate(task.task_id)
        self.assertEqual("blocked", blocked.status)
        self.assertEqual("", blocked.approval_hash)
        manager.acceptance_verifier = CandidateAcceptance(self.infer)
        ready = manager.revalidate_candidate(task.task_id)
        self.assertEqual("waiting_approval", ready.status)
        self.assertEqual(task.candidate_commit, ready.candidate_commit)
        self.assertEqual(len(task.attempts), len(ready.attempts))
        self.assertTrue(ready.approval_hash)

    def test_revalidation_cannot_resurrect_cancelled_candidate(self):
        manager, task = self.prepared()
        def cancel_during_review(messages, **kwargs):
            saved = manager.require(task.task_id)
            saved.status = "cancelled"
            saved.approval_hash = ""
            manager.store.save(saved)
            return self.infer(messages, **kwargs)
        manager.acceptance_verifier = CandidateAcceptance(cancel_during_review)
        result = manager.revalidate_candidate(task.task_id)
        self.assertEqual("cancelled", result.status)
        self.assertEqual("", result.approval_hash)

    def test_cancel_during_initial_acceptance_never_makes_candidate_ready(self):
        def edit(task, attempt, path, failure):
            (path / "docs/readme.md").write_text("Original documentation\nChecklist\n")
            return "Edited"
        manager = self.manager(edit)
        task = self.task(manager)
        def cancel_during_review(messages, **kwargs):
            manager.cancel(task.task_id)
            return self.infer(messages, **kwargs)
        manager.acceptance_verifier = CandidateAcceptance(cancel_during_review)
        result = manager.run_sync(task.task_id)
        self.assertEqual("cancelled", result.status)
        self.assertFalse(result.approval_hash)

    def test_cached_proof_is_bound_to_goal_and_candidate(self):
        manager, task = self.prepared()
        worktree = Path(task.attempts[-1].worktree)
        manager._require_candidate_acceptance(task, worktree, task.candidate_commit)
        self.assertEqual(1, len(self.seen))
        task.acceptance.append("An additional requirement")
        manager._require_candidate_acceptance(task, worktree, task.candidate_commit)
        self.assertEqual(2, len(self.seen))

    def test_unavailable_review_blocks_without_exhausting_more_attempts(self):
        def edit(task, attempt, path, failure):
            (path / "docs/readme.md").write_text("Original documentation\nChecklist\n")
            return "Edited"
        manager = self.manager(edit)
        manager.acceptance_verifier = CandidateAcceptance(Mock(side_effect=LocalPlannerUnavailable("HTTP 503")))
        task = manager.run_sync(self.task(manager).task_id)
        self.assertEqual("blocked", task.status)
        self.assertEqual(1, len(task.attempts))
        self.assertIn("HTTP 503", task.last_error)

    def test_all_requirements_are_required_and_top_level_pass_cannot_override_failure(self):
        evidence = {"requirements": [{"id": "task"}, {"id": "criterion-1"}]}
        good = assessment(evidence)
        for mutation in ([], [good["assessments"][0]], [good["assessments"][0]] * 2):
            with self.assertRaises(ValueError):
                validate_result({**good, "assessments": mutation}, ["task", "criterion-1"])
        failed = copy.deepcopy(good)
        failed["assessments"][1]["verdict"] = "fail"
        self.assertEqual("fail", validate_result(failed, ["task", "criterion-1"])["verdict"])

    def test_large_evidence_is_not_truncated_and_does_not_reach_model(self):
        manager, task = self.prepared()
        task.problem = "x" * EVIDENCE_LIMIT
        with self.assertRaises(EvolutionError) as caught:
            manager._require_candidate_acceptance(task, Path(task.attempts[-1].worktree), task.candidate_commit)
        self.assertEqual("acceptance_evidence_incomplete", caught.exception.code)
        self.assertEqual(1, len(self.seen))

    def test_missing_commit_cannot_be_treated_as_empty_passing_diff(self):
        manager, task = self.prepared()
        with self.assertRaises(EvolutionError) as caught:
            collect_evidence(task, Path(task.attempts[-1].worktree), "f" * 40, {}, manager.runner)
        self.assertEqual("acceptance_evidence_incomplete", caught.exception.code)


if __name__ == "__main__":
    unittest.main()
