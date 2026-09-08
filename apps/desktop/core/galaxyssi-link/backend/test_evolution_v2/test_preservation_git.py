from types import SimpleNamespace
import unittest
from unittest.mock import Mock

from evolution_v2.acceptance_evidence import collect_evidence
from evolution_v2.candidate_acceptance import CandidateAcceptance
from evolution_v2.legacy import EvolutionCommandRunner
from test_evolution_v2 import test_candidate_acceptance as fixtures
from test_evolution_v2.test_preservation_contract import compiler, reviewer


class PreservationGitTests(unittest.TestCase):
    setUp = fixtures.CandidateAcceptanceTests.setUp
    git = fixtures.CandidateAcceptanceTests.git
    manager = fixtures.CandidateAcceptanceTests.manager
    infer = fixtures.CandidateAcceptanceTests.infer

    def test_real_git_prepend_and_delete_fail_while_append_passes_with_one_source_contract(self):
        task = SimpleNamespace(task_id="preservation-git", base_commit=self.base,
            problem="Append new material at the end of docs/readme.md without changing original text.",
            acceptance=[], scope=["docs"])
        infer = compiler()
        verifier = CandidateAcceptance(reviewer(), preservation_infer=infer)
        previous = None
        path = self.source / "docs/readme.md"
        for content, expected in (("New\nOriginal documentation\n", "fail"),
                                  ("Original documentation\nNew\n", "pass"), (None, "fail")):
            with self.subTest(content=content):
                if content is None:
                    path.unlink()
                else:
                    path.write_text(content, encoding="utf-8")
                self.git("add", "docs/readme.md")
                self.git("commit", "-m", "Controlled candidate")
                head = self.git("rev-parse", "HEAD")
                data = collect_evidence(task, self.source, head, {}, EvolutionCommandRunner())
                result = verifier.verify(data, previous)
                self.assertEqual(expected, result["verdict"])
                self.assertEqual(head, result["candidate_commit"])
                previous = result
        self.assertEqual(1, infer.call_count)
        self.assertEqual(1, verifier.infer.call_count)

    def test_manager_restart_keeps_contract_after_transport_failure_and_forced_revalidation(self):
        def edit(task, attempt, worktree, failure):
            (worktree / "docs/readme.md").write_text("Original documentation\nAdded\n", encoding="utf-8")
            return "Controlled append"
        manager = self.manager(edit)
        manager.acceptance_verifier = CandidateAcceptance(Mock(side_effect=TimeoutError("offline")),
                                                          preservation_infer=compiler())
        task = manager.create(problem="Append while preserving original text", scope=["docs"],
                              acceptance=["Keep original text at the beginning"], risk_level="low")
        blocked = manager.run_sync(task.task_id)
        self.assertEqual("blocked", blocked.status)
        proof = manager.v2_store.get_task_metadata(task.task_id).review["acceptance"]
        self.assertEqual("append_only", proof["preservation_contract"]["files"]["docs/readme.md"]["preservation"])
        restored = self.manager(Mock(side_effect=AssertionError("Do not reimplement")))
        restored.acceptance_verifier = CandidateAcceptance(reviewer(),
            preservation_infer=Mock(side_effect=AssertionError("Do not weaken persisted source contract")))
        result = restored.revalidate_candidate(task.task_id)
        self.assertEqual("waiting_approval", result.status, result.last_error)
        self.assertEqual(blocked.candidate_commit, result.candidate_commit)
        self.assertEqual(1, len(result.attempts))
