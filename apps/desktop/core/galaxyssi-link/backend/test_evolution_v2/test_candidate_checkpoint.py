from __future__ import annotations

from pathlib import Path
import os
import subprocess
import sys
import time
import unittest
from unittest.mock import Mock

from evolution_v2.candidate_acceptance import CandidateAcceptance
from evolution_v2.campaign_retry_admission import retry_admission
from evolution_v2.legacy import EvolutionError, EvolutionStore, EvolutionGate, GateCommand
from evolution_v2.local_planning import LocalPlannerUnavailable
from evolution_v2.manager import EvolutionManager
from test_evolution_v2 import test_candidate_acceptance as fixtures


def crash_worker(source, state, task_id, phase):
    class Worker(EvolutionManager):
        def _gate_commands(self, changed_files):
            return [GateCommand("git-diff-check", ("git", "diff", "--check"))]

        def _checkpoint_candidate_intent(self, task, attempt):
            super()._checkpoint_candidate_intent(task, attempt)
            if phase == "intent":
                os._exit(73)

    def edit(task, attempt, path, failure):
        marker = Path(state) / (task_id + "-implementation-count")
        marker.write_text(str(int(marker.read_text()) + 1) if marker.exists() else "1")
        (path / "docs/readme.md").write_text("Original documentation\n\n## Checklist\n")
        return "Controlled subprocess edit"

    manager = Worker(source_root=Path(source), store=EvolutionStore(Path(state)), patch_agent=edit,
                     acceptance_infer=lambda *_args, **_kwargs: os._exit(73))
    if phase == "commit":
        original = manager.runner.run
        def run(argv, *args, **kwargs):
            result = original(argv, *args, **kwargs)
            if "commit" in argv and "Prepare evolution candidate " + task_id in argv and result.returncode == 0:
                os._exit(73)
            return result
        manager.runner.run = run
    manager.run_sync(task_id)


class ProcessDeath(BaseException):
    pass


class CandidateCheckpointTests(unittest.TestCase):
    setUp = fixtures.CandidateAcceptanceTests.setUp
    git = fixtures.CandidateAcceptanceTests.git
    infer = fixtures.CandidateAcceptanceTests.infer
    manager = fixtures.CandidateAcceptanceTests.manager
    task = fixtures.CandidateAcceptanceTests.task

    def edit(self, task, attempt, path, failure):
        (path / "docs/readme.md").write_text("Original documentation\n\n## Checklist\n", encoding="utf-8")
        return "Controlled edit"

    def interrupted(self, phase="review"):
        agent = Mock(side_effect=self.edit)
        manager = self.manager(agent)
        task = self.task(manager)
        task.max_attempts = 1
        manager.store.save(task)
        if phase == "review":
            manager.acceptance_verifier = CandidateAcceptance(Mock(side_effect=ProcessDeath()))
        elif phase == "intent":
            original = manager._checkpoint_candidate_intent
            def stop(task, attempt):
                original(task, attempt)
                raise ProcessDeath()
            manager._checkpoint_candidate_intent = stop
        elif phase == "commit":
            original = manager.runner.run
            def stop(argv, *args, **kwargs):
                result = original(argv, *args, **kwargs)
                if "commit" in argv and "Prepare evolution candidate " + task.task_id in argv:
                    self.assertEqual(0, result.returncode)
                    raise ProcessDeath()
                return result
            manager.runner.run = stop
        with self.assertRaises(ProcessDeath):
            manager.run_sync(task.task_id)
        saved = manager.require(task.task_id)
        self.assertEqual("validating", saved.status)
        self.assertTrue(saved.candidate_checkpoint)
        self.assertFalse(saved.approval_hash)
        self.assertEqual(1, agent.call_count)
        return manager, saved

    def recover(self, task):
        manager = self.manager(Mock(side_effect=AssertionError("must not implement twice")))
        self.assertIn(task.task_id, manager.recover_interrupted(resume=False))
        saved = manager.require(task.task_id)
        self.assertEqual("proposed", saved.status, saved.last_error)
        return manager

    def test_review_restart_keeps_commit_worktree_and_attempt_at_attempt_limit(self):
        _, task = self.interrupted()
        old = task.candidate_commit
        self.assertTrue(old)
        manager = self.recover(task)
        ready = manager.run_sync(task.task_id)
        self.assertEqual("waiting_approval", ready.status, ready.last_error)
        self.assertEqual(old, ready.candidate_commit)
        self.assertEqual(1, len(ready.attempts))
        self.assertEqual(task.attempts[0].worktree, ready.attempts[0].worktree)
        self.assertTrue(ready.approval_hash)
        self.assertFalse(ready.candidate_checkpoint)
        manager.patch_agent.assert_not_called()

    def test_commit_intent_reconciles_both_sides_of_git_side_effect(self):
        for phase in ("intent", "commit"):
            with self.subTest(phase=phase):
                _, task = self.interrupted(phase)
                self.assertFalse(task.candidate_commit)
                manager = self.recover(task)
                ready = manager.run_sync(task.task_id)
                self.assertEqual("waiting_approval", ready.status, ready.last_error)
                self.assertEqual(1, len(ready.attempts))
                parents = manager._git_text(("rev-list", "--parents", "-n", "1", ready.candidate_commit),
                                           cwd=Path(ready.attempts[-1].worktree)).split()
                self.assertEqual([ready.candidate_commit, ready.base_commit], parents)
                manager.patch_agent.assert_not_called()

    def test_unavailable_initial_review_retains_candidate_until_provider_recovers(self):
        agent = Mock(side_effect=self.edit)
        manager = self.manager(agent)
        manager.acceptance_verifier = CandidateAcceptance(Mock(side_effect=LocalPlannerUnavailable("offline")))
        blocked = manager.run_sync(self.task(manager).task_id)
        self.assertEqual("blocked", blocked.status)
        self.assertEqual("acceptance_review_unavailable", blocked.last_error_code)
        self.assertTrue(Path(blocked.attempts[-1].worktree).is_dir())
        self.assertTrue(blocked.candidate_commit)
        manager = self.manager(Mock(side_effect=AssertionError("unexpected implementation")))
        ready = manager.run_sync(blocked.task_id)
        self.assertEqual("waiting_approval", ready.status, ready.last_error)
        self.assertEqual(blocked.candidate_commit, ready.candidate_commit)
        self.assertEqual(1, len(ready.attempts))
        self.assertEqual(1, agent.call_count)

    def test_changed_workspace_is_blocked_and_never_deleted(self):
        _, task = self.interrupted()
        path = Path(task.attempts[-1].worktree) / "docs/readme.md"
        path.write_text("External user edits\n")
        manager = self.manager(Mock())
        manager.recover_interrupted(resume=False)
        saved = manager.require(task.task_id)
        self.assertEqual("blocked", saved.status)
        self.assertEqual("candidate_checkpoint_invalid", saved.last_error_code)
        self.assertEqual("External user edits\n", path.read_text())
        manager.patch_agent.assert_not_called()

    def test_requirements_changed_after_checkpoint_do_not_authorize_resume(self):
        manager, task = self.interrupted()
        task.acceptance.append("An additional requirement")
        manager.store.save(task)
        manager.recover_interrupted(resume=False)
        saved = manager.require(task.task_id)
        self.assertEqual("blocked", saved.status)
        self.assertTrue(Path(saved.attempts[-1].worktree).is_dir())
        self.assertIn("requirements changed", saved.last_error)

    def test_cancelled_checkpoint_is_not_recovered_or_resurrected(self):
        manager, task = self.interrupted()
        manager.cancel(task.task_id)
        self.assertNotIn(task.task_id, manager.recover_interrupted(resume=False))
        self.assertEqual("cancelled", manager.require(task.task_id).status)

    def test_cancel_during_continued_review_never_grants_approval(self):
        _, task = self.interrupted()
        manager = self.recover(task)
        def cancel(messages, **kwargs):
            manager.cancel(task.task_id)
            return self.infer(messages, **kwargs)
        manager.acceptance_verifier = CandidateAcceptance(cancel)
        result = manager.run_sync(task.task_id)
        self.assertEqual("cancelled", result.status)
        self.assertFalse(result.approval_hash)
        self.assertFalse(result.candidate_checkpoint)

    def test_retry_admission_distinguishes_continuation_from_another_attempt(self):
        manager, task = self.interrupted()
        task.status = "blocked"
        admission = retry_admission(task)
        self.assertEqual(0, admission["attempts_remaining"])
        self.assertTrue(admission["candidate_continuation"])
        self.assertTrue(admission["retryable"])
        task.candidate_checkpoint = {}
        self.assertEqual("child_attempts_exhausted", retry_admission(task)["retry_blocker"])

    def test_checkpoint_is_not_exposed_in_public_task_payloads(self):
        _, task = self.interrupted()
        self.assertNotIn("candidate_checkpoint", task.public())
        self.assertNotIn("candidate_checkpoint", task.public(include_worktree=True))

    def test_invalid_checkpoint_never_falls_through_to_new_implementation(self):
        manager, task = self.interrupted()
        task.candidate_checkpoint["tree"] = "invalid"
        manager.store.save(task)
        agent = Mock(side_effect=AssertionError("must not fall through"))
        manager = self.manager(agent)
        result = manager.run_sync(task.task_id)
        self.assertEqual("blocked", result.status)
        self.assertTrue(Path(result.attempts[-1].worktree).is_dir())
        agent.assert_not_called()

    def test_real_process_exit_reopens_candidate_without_a_second_implementation(self):
        for phase in ("intent", "commit", "review"):
            with self.subTest(phase=phase):
                manager = self.manager()
                task = self.task(manager)
                task.max_attempts = 1
                manager.store.save(task)
                result = subprocess.run([sys.executable, "-c",
                    "import sys; from test_evolution_v2.test_candidate_checkpoint import crash_worker; crash_worker(*sys.argv[1:])",
                    str(self.source), str(self.root / "state"), task.task_id, phase],
                    capture_output=True, text=True, timeout=90)
                self.assertEqual(73, result.returncode, result.stdout + result.stderr)
                saved = manager.require(task.task_id)
                self.assertEqual("validating", saved.status)
                self.assertEqual(1, len(saved.attempts))
                self.assertFalse(saved.approval_hash)
                started = time.perf_counter()
                manager = self.recover(saved)
                print(f"Candidate {phase} process-exit recovery: {(time.perf_counter() - started) * 1000:.3f} ms")
                ready = manager.run_sync(task.task_id)
                self.assertEqual("waiting_approval", ready.status, ready.last_error)
                self.assertEqual(1, len(ready.attempts))
                self.assertEqual(saved.attempts[-1].worktree, ready.attempts[-1].worktree)
                self.assertEqual("1", (self.root / "state" / (task.task_id + "-implementation-count")).read_text())

    def test_continuation_rechecks_dependency_source_before_any_review(self):
        _, task = self.interrupted()
        from unittest.mock import patch
        manager = self.manager(Mock())
        with patch("evolution_v2.campaign_outcomes.verify_dependency_source",
                   side_effect=EvolutionError("campaign_dependency_pending", "Dependency is not complete")):
            result = manager.run_sync(task.task_id)
        self.assertEqual("blocked", result.status)
        self.assertEqual("campaign_dependency_pending", result.last_error_code)
        self.assertTrue(Path(result.attempts[-1].worktree).is_dir())
        manager.patch_agent.assert_not_called()

    def test_current_gate_failure_cannot_reuse_previous_pass(self):
        _, task = self.interrupted()
        manager = self.recover(task)
        manager._run_gates = Mock(return_value=[EvolutionGate("new-gate", "failed", summary="New check failed")])
        manager._review_committed_candidate = Mock(side_effect=AssertionError("must not review failed gates"))
        result = manager.run_sync(task.task_id)
        self.assertEqual("blocked", result.status)
        self.assertEqual("quality_gate_failed", result.last_error_code)
        self.assertFalse(result.approval_hash)
        self.assertFalse(result.candidate_checkpoint)
        manager._run_gates.assert_called_once()
        manager._review_committed_candidate.assert_not_called()

    def test_untracked_files_and_different_head_are_retained_as_conflicts(self):
        for mutation in ("untracked", "new-commit"):
            with self.subTest(mutation=mutation):
                manager, task = self.interrupted()
                worktree = Path(task.attempts[-1].worktree)
                note = worktree / "external.txt"
                note.write_text("External content\n")
                if mutation == "new-commit":
                    manager._git_text(("add", "external.txt"), cwd=worktree)
                    manager._git_text(("commit", "-m", "External modification"), cwd=worktree)
                manager = self.manager(Mock())
                result = manager.run_sync(task.task_id)
                self.assertEqual("blocked", result.status)
                self.assertEqual("candidate_checkpoint_invalid", result.last_error_code)
                self.assertEqual("External content\n", note.read_text())
                manager.patch_agent.assert_not_called()

    def test_explicit_revalidation_retires_checkpoint_after_a_decisive_result(self):
        for verdict in ("pass", "fail"):
            with self.subTest(verdict=verdict):
                manager = self.manager(Mock(side_effect=self.edit))
                manager.acceptance_verifier = CandidateAcceptance(Mock(side_effect=LocalPlannerUnavailable("offline")))
                blocked = manager.run_sync(self.task(manager).task_id)
                self.assertTrue(blocked.candidate_checkpoint)
                manager.acceptance_verifier = CandidateAcceptance(self.infer)
                self.verdicts = [verdict]
                result = manager.revalidate_candidate(blocked.task_id)
                self.assertEqual("waiting_approval" if verdict == "pass" else "failed", result.status)
                self.assertFalse(result.candidate_checkpoint)
                self.assertEqual(blocked.candidate_commit, result.candidate_commit)
                self.assertTrue(Path(result.attempts[-1].worktree).is_dir())

    def test_another_live_owner_fences_checkpoint_recovery_and_continuation(self):
        owner, task = self.interrupted()
        self.assertTrue(owner.task_owners.claim(task.task_id))
        try:
            manager = self.manager(Mock())
            self.assertNotIn(task.task_id, manager.recover_interrupted(resume=False))
            with self.assertRaises(EvolutionError) as caught:
                manager.run_sync(task.task_id)
            self.assertEqual("task_owned_elsewhere", caught.exception.code)
            self.assertEqual("validating", manager.require(task.task_id).status)
            self.assertTrue(Path(task.attempts[-1].worktree).is_dir())
            manager.patch_agent.assert_not_called()
        finally:
            owner.task_owners.release(task.task_id)

    def test_external_edit_during_rejected_review_is_not_cleaned_up(self):
        manager = self.manager(Mock(side_effect=self.edit))
        task = self.task(manager)
        def reject_with_external_edit(messages, **kwargs):
            saved = manager.require(task.task_id)
            (Path(saved.attempts[-1].worktree) / "external.txt").write_text("Keep this content\n")
            self.verdicts = ["fail"]
            return self.infer(messages, **kwargs)
        manager.acceptance_verifier = CandidateAcceptance(reject_with_external_edit)
        result = manager.run_sync(task.task_id)
        self.assertEqual("blocked", result.status)
        self.assertEqual("candidate_checkpoint_invalid", result.last_error_code)
        self.assertEqual("Keep this content\n", (Path(result.attempts[-1].worktree) / "external.txt").read_text())
        self.assertFalse(result.approval_hash)
        self.assertTrue(result.candidate_checkpoint)
        self.assertEqual(1, manager.patch_agent.call_count)

    def test_outcome_save_cannot_overwrite_a_concurrent_cancellation(self):
        from evolution_v2.candidate_checkpoint import save_outcome
        manager, task = self.interrupted()
        manager.cancel(task.task_id)
        task.status = "blocked"
        task.last_error_code = "acceptance_review_unavailable"
        save_outcome(manager, task)
        self.assertEqual("cancelled", manager.require(task.task_id).status)


if __name__ == "__main__":
    unittest.main()
