from __future__ import annotations

import copy
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

from evolution_v2.campaign_outcomes import published_outcome
from evolution_v2.ci_snapshot import CiObservationError
from evolution_v2.integration_verification import accepted_integration, verify_integration
from evolution_v2.legacy import EvolutionCommandRunner


class IntegrationVerificationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git("init", "-b", "main")
        self.git("config", "user.email", "test@galaxyssi.local")
        self.git("config", "user.name", "Integration test")
        self.git("config", "core.autocrlf", "false")
        (self.root / "candidate.txt").write_text("original\n")
        (self.root / "removed.txt").write_text("remove me\n")
        self.source = self.commit("Base")
        (self.root / "candidate.txt").write_text("original\nrequested addition\n")
        (self.root / "removed.txt").unlink()
        (self.root / "new [file].txt").write_text("new file\n")
        self.head = self.commit("Candidate")
        (self.root / "independent-fix.txt").write_text("Fix inherited CI failure\n")
        self.integrated = self.commit("Integrated base fix")
        self.git("remote", "add", "origin", str(self.root))
        self.snapshot = {"url": "https://github.com/owner/project/pull/7", "number": 7,
            "repository": "owner/project", "head_repository": "owner/project", "base_repository": "owner/project",
            "head_sha": self.head, "head_ref": "candidate", "base_ref": "main", "state": "closed",
            "merged": True, "merge_commit_sha": self.head, "passed": False, "failed": 1, "pending": 0}
        self.task = SimpleNamespace(task_id="task", status="published", candidate_commit=self.head,
                                    pull_request_url=self.snapshot["url"])
        self.github = Mock()
        self.github.current_repository.return_value = "owner/project"
        self.github.pull_request_head.side_effect = lambda url: {key: value for key, value in self.snapshot.items()
            if key not in {"passed", "failed", "pending"}}
        self.github._api.side_effect = lambda args: {"ref": "refs/heads/main", "object": {
            "type": "commit", "sha": self.integrated}}
        self.metadata = SimpleNamespace(source_commit=self.source)
        self.manager = SimpleNamespace(require=lambda key: self.task, source_root=self.root, runner=EvolutionCommandRunner(),
            github=self.github, v2_store=SimpleNamespace(get_task_metadata=lambda key: self.metadata))
        self.ci = {"repository": "owner/project", "head_sha": self.integrated, "passed": True,
                   "failed": 0, "pending": 0, "fingerprint": "green", "checks": [{"outcome": "passed"}]}

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.root, capture_output=True, text=True,
                              check=True, timeout=20).stdout.strip()

    def commit(self, message):
        self.git("add", "-A")
        self.git("commit", "-m", message)
        return self.git("rev-parse", "HEAD")

    def verify(self):
        with patch("evolution_v2.integration_verification.observe_commit", return_value=self.ci) as checks:
            result = verify_integration(self.manager, "task", self.snapshot)
        return result, checks

    def test_green_descendant_preserves_candidate_additions_and_deletions(self):
        (self.root / "user-uncommitted.txt").write_text("Do not touch\n")
        before = self.git("status", "--porcelain")
        result, checks = self.verify()
        self.assertTrue(result["passed"])
        self.assertEqual(3, result["retained_paths"])
        self.assertEqual(self.integrated, accepted_integration(result, self.snapshot, "task"))
        checks.assert_called_once_with(self.github, "owner/project", self.integrated)
        self.assertEqual(before, self.git("status", "--porcelain"))
        self.assertFalse(self.snapshot["passed"])

    def test_thousand_candidate_paths_use_two_tree_diffs_not_per_file_processes(self):
        for index in range(1000):
            (self.root / f"new-{index:04d}.txt").write_text("candidate\n")
        self.head = self.commit("Large candidate")
        self.task.candidate_commit = self.head
        self.snapshot.update(head_sha=self.head, merge_commit_sha=self.head)
        (self.root / "independent-fix.txt").write_text("Follow-up base fix\n")
        self.integrated = self.commit("Repair outside candidate")
        # The fixture's previous base fix is part of this new candidate; retain it too.
        (self.root / "independent-fix.txt").write_text("Fix inherited CI failure\n")
        self.integrated = self.commit("Retain all candidate bytes")
        self.ci["head_sha"] = self.integrated
        runner = self.manager.runner
        with patch.object(runner, "run", wraps=runner.run) as calls:
            result, _ = self.verify()
        self.assertTrue(result["passed"])
        self.assertEqual(1004, result["retained_paths"])
        self.assertEqual(2, sum(call.args[0][1] == "diff" for call in calls.call_args_list))
        self.assertEqual(4, calls.call_count)

    def test_changed_candidate_path_requires_new_acceptance_even_with_green_ci(self):
        (self.root / "candidate.txt").write_text("reverted or changed\n")
        self.integrated = self.commit("Change candidate")
        result, checks = self.verify()
        self.assertFalse(result["passed"])
        self.assertIn("fresh semantic acceptance", result["reason"])
        checks.assert_not_called()

    def test_restored_deleted_file_is_not_retained_candidate(self):
        (self.root / "removed.txt").write_text("restored\n")
        self.integrated = self.commit("Undo deletion")
        self.assertFalse(self.verify()[0]["passed"])

    def test_mode_change_and_rename_are_not_silently_accepted(self):
        self.git("update-index", "--chmod=+x", "candidate.txt")
        self.git("commit", "-m", "Change mode")
        self.integrated = self.git("rev-parse", "HEAD")
        self.assertFalse(self.verify()[0]["passed"])
        self.git("mv", "new [file].txt", "renamed.txt")
        self.integrated = self.commit("Rename candidate path")
        self.assertFalse(self.verify()[0]["passed"])

    def test_unrelated_green_commit_cannot_prove_integration(self):
        self.integrated = self.source
        result, checks = self.verify()
        self.assertFalse(result["passed"])
        self.assertIn("no longer contains", result["reason"])
        checks.assert_not_called()

    def test_failed_pending_or_absent_ci_never_grants_acceptance(self):
        for ci in ({"passed": False, "failed": 1}, {"passed": False, "pending": 1}, {}):
            with self.subTest(ci=ci):
                self.ci = ci
                self.assertFalse(self.verify()[0]["passed"])

    def test_candidate_and_repository_identity_must_match(self):
        for change in ({"head_sha": "a" * 40}, {"base_ref": "other"}, {"merged": False},
                       {"head_repository": "fork/project"}, {"base_repository": "other/project"}):
            original = copy.deepcopy(self.snapshot)
            with self.subTest(change=change):
                self.snapshot.update(change)
                self.assertFalse(self.verify()[0]["passed"])
            self.snapshot = original
        self.github.current_repository.return_value = "wrong/project"
        self.assertFalse(self.verify()[0]["passed"])

    def test_no_accepted_source_or_changed_published_candidate_cannot_verify(self):
        self.metadata.source_commit = ""
        self.assertFalse(self.verify()[0]["passed"])
        self.metadata.source_commit = self.source
        self.task.candidate_commit = "b" * 40
        self.assertFalse(self.verify()[0]["passed"])

    def test_main_or_pr_changes_during_observation_reject_evidence(self):
        first = self.github._api(("ref",))
        self.github._api.side_effect = [first, {**first, "object": {"sha": "c" * 40}}]
        with self.assertRaisesRegex(CiObservationError, "Main changed"):
            self.verify()
        self.github._api.side_effect = None
        self.github._api.return_value = first
        self.github.pull_request_head.side_effect = lambda url: {}
        with self.assertRaisesRegex(CiObservationError, "candidate changed"):
            self.verify()

    def test_invalid_main_ref_is_not_used_as_a_git_argument(self):
        for value in ({}, {"ref": "refs/heads/main", "object": {"type": "commit", "sha": "--all"}},
                      {"ref": "refs/heads/other", "object": {"type": "commit", "sha": self.integrated}}):
            self.github._api.side_effect = None
            self.github._api.return_value = value
            with self.assertRaises(CiObservationError):
                self.verify()

    def test_proof_cannot_be_rebound_or_reuse_incomplete_ci(self):
        proof, _ = self.verify()
        for change in ({"task_id": "other"}, {"head_sha": "a" * 40}, {"integration_commit": "a" * 40},
                       {"retained_paths": 0}, {"retention_fingerprint": ""},
                       {"ci": {**proof["ci"], "checks": []}},
                       {"ci": {**proof["ci"], "checks": [{"outcome": "unknown"}]}}):
            with self.subTest(change=change):
                self.assertIsNone(accepted_integration({**proof, **change}, self.snapshot, "task"))

    def test_published_outcome_records_new_green_evidence_without_erasing_old_failure(self):
        proof, _ = self.verify()
        watch = {"url": self.snapshot["url"], "status": "merged", "snapshot": self.snapshot, "integration": proof}
        self.manager.ci_watches = SimpleNamespace(get=lambda task_id: watch)
        outcome = published_outcome(self.manager, self.task)
        self.assertEqual("completed", outcome["stage"])
        self.assertEqual(self.integrated, outcome["integration_commit"])
        self.assertTrue(outcome["historical_ci_failed"])
        self.assertFalse(watch["snapshot"]["passed"])
        watch["integration"] = {"passed": False, "reason": "Candidate path changed; fresh acceptance required"}
        self.assertIn("fresh acceptance required", published_outcome(self.manager, self.task)["error"])
        watch["status"] = "observation_error"
        self.assertEqual("awaiting_ci", published_outcome(self.manager, self.task)["stage"])


if __name__ == "__main__":
    unittest.main()
