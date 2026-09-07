from __future__ import annotations

from copy import deepcopy
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

from evolution_v2 import legacy
from evolution_v2.manager import EvolutionManager
from evolution_v2.models import TaskMetadata
from evolution_v2.publication import _intent, find_published_candidate, publish_candidate


REPO = "galaxyssi/GalaxySSI"
URL = f"https://github.com/{REPO}/pull/42"
SHA = "a" * 40


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        source = self.root / "source"
        source.mkdir()
        subprocess.run(["git", "init", "-b", "main"], cwd=source, check=True, capture_output=True, timeout=20)
        self.manager = EvolutionManager(source_root=source, store=legacy.EvolutionStore(self.root / "state"))
        self.task = legacy.EvolutionTask("publish", "Repair", [], ["docs"], ["Pass"], "low", 3,
            status="publishing", candidate_branch="evolution/publish-a1", candidate_commit=SHA)
        self.manager.store.save(self.task)
        self.intent = {"repository": REPO, "head_ref": self.task.candidate_branch, "head_sha": SHA, "base_ref": "main"}
        self.current = {**self.intent, "head_repository": REPO, "base_repository": REPO,
                        "state": "open", "merged": False, "url": URL}
        self.pages = [[]]
        self.calls = []
        self.manager.github = SimpleNamespace(current_repository=lambda: REPO,
            _api=lambda args: deepcopy(self.pages), pull_request_head=lambda url: deepcopy(self.current))
        def command(argv, cwd, **kwargs):
            self.calls.append(tuple(argv))
            if argv[:3] == ("gh", "pr", "create"):
                self.pages = [[{"number": 42}]]
                return SimpleNamespace(returncode=0, stdout=URL)
            return SimpleNamespace(returncode=0, stdout="")
        self.manager.runner = SimpleNamespace(run=Mock(side_effect=command))

    def publish(self):
        return publish_candidate(self.manager, self.task, SimpleNamespace(), self.root, "main")

    def save_intent(self):
        self.manager.v2_store.save_task_metadata(TaskMetadata(task_id="publish", publication_intent=self.intent))

    def test_first_publication_persists_intent_and_verifies_remote_identity(self):
        with patch.object(self.manager, "_pull_request_body", return_value="body"):
            self.assertEqual(URL, self.publish())
        self.assertEqual(self.intent, self.manager.v2_store.get_task_metadata("publish").publication_intent)
        self.assertEqual(2, len(self.calls))
        self.assertIn(f"{SHA}:refs/heads/{self.task.candidate_branch}", self.calls[0])
        self.assertIn("--repo", self.calls[1])

    def test_existing_verified_pr_does_not_push_or_create_again(self):
        self.pages = [[{"number": 42}]]
        self.assertEqual(URL, self.publish())
        self.manager.runner.run.assert_not_called()

    def test_lost_create_response_is_reconciled_without_duplicate_creation(self):
        original = self.manager.runner.run.side_effect
        def lost(argv, *args, **kwargs):
            result = original(argv, *args, **kwargs)
            if argv[:3] == ("gh", "pr", "create"):
                raise subprocess.TimeoutExpired(argv, 300)
            return result
        self.manager.runner.run.side_effect = lost
        with patch.object(self.manager, "_pull_request_body", return_value="body"):
            self.assertEqual(URL, self.publish())
            self.assertEqual(URL, self.publish())
        self.assertEqual(1, sum(call[:3] == ("gh", "pr", "create") for call in self.calls))

    def test_failed_create_response_can_still_have_succeeded_remotely(self):
        original = self.manager.runner.run.side_effect
        def failed(argv, *args, **kwargs):
            result = original(argv, *args, **kwargs)
            return SimpleNamespace(returncode=1, stdout="connection closed") if argv[0] == "gh" else result
        self.manager.runner.run.side_effect = failed
        with patch.object(self.manager, "_pull_request_body", return_value="body"):
            self.assertEqual(URL, self.publish())

    def test_unconfirmed_success_never_marks_a_pr_published(self):
        self.manager.runner.run.side_effect = lambda *args, **kwargs: SimpleNamespace(returncode=0, stdout=URL)
        with patch.object(self.manager, "_pull_request_body", return_value="body"), self.assertRaises(legacy.EvolutionError) as error:
            self.publish()
        self.assertEqual("publication_unconfirmed", error.exception.code)

    def test_changed_head_repository_branch_or_base_is_rejected(self):
        self.pages = [[{"number": 42}]]
        for field, value in (("head_sha", "b" * 40), ("head_repository", "other/repo"),
                             ("head_ref", "other"), ("base_ref", "other"), ("base_repository", "other/repo")):
            before = self.current.copy()
            self.current[field] = value
            with self.subTest(field=field), self.assertRaises(legacy.EvolutionError):
                self.publish()
            self.current = before
        self.manager.runner.run.assert_not_called()

    def test_closed_unmerged_pr_does_not_create_a_replacement(self):
        self.pages = [[{"number": 42}]]
        self.current["state"] = "closed"
        with self.assertRaises(legacy.EvolutionError) as error:
            self.publish()
        self.assertEqual("publication_closed", error.exception.code)
        self.manager.runner.run.assert_not_called()

    def test_merged_matching_candidate_is_recognized_without_republishing(self):
        self.pages = [[{"number": 42}]]
        self.current.update(state="closed", merged=True)
        self.assertEqual(URL, self.publish())
        self.manager.runner.run.assert_not_called()

    def test_ambiguous_duplicate_and_malformed_pages_never_authorize_creation(self):
        for pages in ([], {}, [None], [[{"number": 42}], [{"number": 42}]], [[{"number": True}]], [[{"number": -1}]]):
            self.pages = pages
            with self.subTest(pages=pages), self.assertRaises(legacy.EvolutionError):
                find_published_candidate(self.manager, self.intent)
        self.manager.runner.run.assert_not_called()

    def test_persisted_intent_cannot_silently_change_candidate_or_repository(self):
        self.save_intent()
        self.task.candidate_commit = "b" * 40
        with self.assertRaises(legacy.EvolutionError) as error:
            self.publish()
        self.assertEqual("publication_intent_changed", error.exception.code)
        self.manager.runner.run.assert_not_called()

    def test_intent_is_persisted_before_any_network_side_effect(self):
        def observe(args):
            self.assertEqual(self.intent, self.manager.v2_store.get_task_metadata("publish").publication_intent)
            raise OSError("network offline")
        self.manager.github._api = observe
        with self.assertRaises(OSError):
            self.publish()
        self.manager.runner.run.assert_not_called()

    def test_interrupted_publication_recovers_and_rejoins_ci_observation(self):
        self.save_intent()
        self.pages = [[{"number": 42}]]
        self.assertEqual(["publish"], self.manager.recover_interrupted(resume=False))
        current = self.manager.require("publish")
        self.assertEqual("published", current.status)
        self.assertEqual(URL, current.pull_request_url)
        self.assertEqual(URL, self.manager.ci_watches.get("publish")["url"])
        self.manager.runner.run.assert_not_called()

    def test_network_error_stays_uncertain_then_enabled_tick_reconciles(self):
        self.save_intent()
        original = self.manager.github._api
        self.manager.github._api = Mock(side_effect=OSError("network offline"))
        self.assertEqual([], self.manager.recover_interrupted(resume=False))
        current = self.manager.require("publish")
        self.assertEqual("publishing", current.status)
        self.assertEqual("publication_observation_failed", current.last_error_code)
        self.manager.github._api = original
        self.pages = [[{"number": 42}]]
        self.manager.resume_recovered_tasks({"enabled": True})
        self.assertEqual("published", self.manager.require("publish").status)
        self.manager.runner.run.assert_not_called()

    def test_disabled_scheduler_does_not_query_uncertain_publication(self):
        self.save_intent()
        self.manager.github._api = Mock()
        self.assertEqual([], self.manager.resume_recovered_tasks({"enabled": False}))
        self.manager.github._api.assert_not_called()

    def test_recovery_without_intent_retains_legacy_reconciliation_state(self):
        self.assertEqual(["publish"], self.manager.recover_interrupted(resume=False))
        self.assertEqual("waiting_approval", self.manager.require("publish").status)
        self.manager.runner.run.assert_not_called()

    def test_pr_created_during_push_is_reused(self):
        def pushed(*args, **kwargs):
            self.pages = [[{"number": 42}]]
            return SimpleNamespace(returncode=0, stdout="")
        self.manager.runner.run.side_effect = pushed
        self.assertEqual(URL, self.publish())
        self.assertEqual(1, self.manager.runner.run.call_count)

    def test_failed_push_never_attempts_pr_creation(self):
        self.manager.runner.run.side_effect = lambda *args, **kwargs: SimpleNamespace(returncode=1, stdout="push failed")
        with self.assertRaises(legacy.EvolutionError) as error:
            self.publish()
        self.assertEqual("candidate_push_failed", error.exception.code)
        self.assertEqual(1, self.manager.runner.run.call_count)

    def test_manager_recreation_uses_persisted_publication_identity(self):
        self.save_intent()
        self.pages = [[{"number": 42}]]
        restored = EvolutionManager(source_root=self.manager.source_root, store=self.manager.store)
        restored.github = self.manager.github
        restored.runner = self.manager.runner
        self.assertEqual(["publish"], restored.recover_interrupted(resume=False))
        self.assertEqual("published", restored.require("publish").status)
        self.manager.runner.run.assert_not_called()

    def test_ci_index_failure_keeps_publication_and_requests_index_repair(self):
        self.save_intent()
        self.pages = [[{"number": 42}]]
        with patch.object(self.manager.ci_watches, "register", side_effect=OSError("index unavailable")):
            self.manager.recover_interrupted(resume=False)
        self.assertEqual("published", self.manager.require("publish").status)
        self.assertTrue(self.manager.ci_watch_index_needed.is_set())

    def test_real_git_push_uses_reviewed_commit_not_a_later_branch_tip(self):
        source = self.manager.source_root
        remote = self.root / "remote.git"
        def git(*args, cwd=source):
            return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True, timeout=20).stdout.strip()
        git("init", "--bare", str(remote))
        git("-c", "user.name=Acceptance", "-c", "user.email=acceptance@example.invalid", "commit", "--allow-empty", "-m", "Reviewed")
        reviewed = git("rev-parse", "HEAD")
        git("-c", "user.name=Acceptance", "-c", "user.email=acceptance@example.invalid", "commit", "--allow-empty", "-m", "Later unrelated commit")
        git("remote", "add", "origin", str(remote))
        self.task.candidate_commit = reviewed
        self.current["head_sha"] = reviewed
        original = self.manager.runner.run.side_effect
        def run(argv, cwd, **kwargs):
            if argv[0] == "git":
                return subprocess.run(argv, cwd=source, capture_output=True, text=True, timeout=20)
            return original(argv, cwd, **kwargs)
        self.manager.runner.run.side_effect = run
        with patch.object(self.manager, "_pull_request_body", return_value="body"):
            self.assertEqual(URL, self.publish())
        self.assertEqual(reviewed, git("--git-dir", str(remote), "rev-parse", f"refs/heads/{self.task.candidate_branch}"))
