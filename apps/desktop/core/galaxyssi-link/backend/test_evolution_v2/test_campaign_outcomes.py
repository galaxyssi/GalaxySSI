from __future__ import annotations

import copy
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest

from evolution_v2.campaign_outcomes import published_outcome, verify_dependency_source
from evolution_v2.legacy import EvolutionCommandRunner, EvolutionError
from test_evolution_v2.test_ci_snapshot import URL


class PublishedOutcomeTests(unittest.TestCase):
    def setUp(self):
        self.task = SimpleNamespace(task_id="task", pull_request_url=URL)
        self.snapshot = {"url": URL, "head_sha": "a" * 40, "state": "closed", "merged": True,
                         "passed": True, "merge_commit_sha": "b" * 40, "base_ref": "main",
                         "repository": "galaxyssi/GalaxySSI", "base_repository": "galaxyssi/GalaxySSI",
                         "fingerprint": "checks", "failed": 0, "pending": 0}
        self.watch = {"url": URL, "status": "merged", "snapshot": self.snapshot}
        self.manager = SimpleNamespace(ci_watches=SimpleNamespace(get=lambda key: self.watch))

    def test_verified_merge_completes_with_exact_commit_evidence(self):
        result = published_outcome(self.manager, self.task)
        self.assertEqual("completed", result["stage"])
        self.assertEqual("b" * 40, result["integration_commit"])
        self.assertEqual("a" * 40, result["head_sha"])

    def test_no_observation_or_wrong_pr_never_completes(self):
        for watch in (None, {}, {"url": URL + "1"}, {"url": URL, "snapshot": {"url": URL + "1"}}):
            with self.subTest(watch=watch):
                self.watch = watch
                self.assertEqual("awaiting_ci", published_outcome(self.manager, self.task)["stage"])

    def test_observation_error_cannot_reuse_stale_green(self):
        self.watch.update(status="observation_error", error="Network disconnected")
        result = published_outcome(self.manager, self.task)
        self.assertEqual("awaiting_ci", result["stage"])
        self.assertEqual("Network disconnected", result["error"])

    def test_passed_but_unmerged_waits_for_integration(self):
        self.snapshot.update(state="open", merged=False)
        self.assertEqual("awaiting_integration", published_outcome(self.manager, self.task)["stage"])

    def test_repair_and_pending_jobs_do_not_permanently_fail_node(self):
        for stage in ("pending", "repairing", "awaiting_repaired_head", "attention_required"):
            with self.subTest(stage=stage):
                self.watch["status"] = stage
                self.snapshot.update(state="open", merged=False, passed=False, failed=1)
                self.assertEqual("awaiting_ci", published_outcome(self.manager, self.task)["stage"])

    def test_closed_without_merge_reports_actual_failure(self):
        self.snapshot.update(merged=False, passed=False)
        self.assertEqual("failed", published_outcome(self.manager, self.task)["stage"])

    def test_merged_failed_ci_is_not_completion(self):
        self.snapshot.update(passed=False, failed=1)
        self.assertEqual("failed", published_outcome(self.manager, self.task)["stage"])
        self.snapshot["pending"] = 1
        self.assertEqual("awaiting_ci", published_outcome(self.manager, self.task)["stage"])

    def test_wrong_base_or_missing_merge_commit_cannot_complete(self):
        original = copy.deepcopy(self.snapshot)
        for change in ({"base_ref": "other"}, {"base_repository": "other/repo"},
                       {"merge_commit_sha": ""}, {"merge_commit_sha": "--all"}):
            with self.subTest(change=change):
                self.snapshot.clear()
                self.snapshot.update(original, **change)
                self.assertEqual("awaiting_integration", published_outcome(self.manager, self.task)["stage"])


class DependencySourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Campaign test")
        self.git("config", "user.email", "test@galaxyssi.local")
        self.git("commit", "--allow-empty", "-m", "Base")
        self.base = self.git("rev-parse", "HEAD")
        self.git("commit", "--allow-empty", "-m", "Dependency integrated")
        self.integrated = self.git("rev-parse", "HEAD")
        self.git("commit", "--allow-empty", "-m", "Later main")
        self.latest = self.git("rev-parse", "HEAD")
        self.node = {"status": "completed", "action": {"task_id": "parent"}, "depends_on": [],
                     "result": {"pull_request_url": URL, "integration_commit": self.integrated}}
        self.graph = {"nodes": {"dependency": self.node, "child": {
            "action": {"task_id": "child"}, "depends_on": ["dependency"]}}}
        durable = SimpleNamespace(identity=lambda key: key, graph_store=SimpleNamespace(load=lambda key: self.graph))
        self.metadata = SimpleNamespace(campaign_id="campaign", ci_repair_target={})
        self.manager = SimpleNamespace(source_root=self.root, runner=EvolutionCommandRunner(),
            campaigns=SimpleNamespace(durable=durable),
            v2_store=SimpleNamespace(get_task_metadata=lambda key: self.metadata))
        self.task = SimpleNamespace(task_id="child")

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.root, capture_output=True, text=True,
                              check=True, timeout=20).stdout.strip()

    def test_real_git_accepts_exact_or_later_integrated_base(self):
        for pinned in (self.integrated, self.latest):
            verify_dependency_source(self.manager, self.task, pinned)

    def test_real_git_rejects_old_base_even_when_ci_is_green(self):
        with self.assertRaises(EvolutionError) as error:
            verify_dependency_source(self.manager, self.task, self.base)
        self.assertEqual("campaign_dependency_not_in_source", error.exception.code)

    def test_transitive_dependency_cannot_be_lost_through_an_intermediate_merge(self):
        self.graph["nodes"]["earlier"] = copy.deepcopy(self.node)
        self.graph["nodes"]["earlier"]["action"]["task_id"] = "earlier-task"
        self.node["depends_on"] = ["earlier"]
        self.node["result"]["integration_commit"] = self.base
        with self.assertRaises(EvolutionError) as error:
            verify_dependency_source(self.manager, self.task, self.base)
        self.assertEqual("campaign_dependency_not_in_source", error.exception.code)

    def test_missing_commit_and_incomplete_parent_are_not_dispatched(self):
        for mutation in ({"status": "running"}, {"result": {"pull_request_url": URL}}):
            with self.subTest(mutation=mutation):
                original = copy.deepcopy(self.node)
                self.node.update(mutation)
                with self.assertRaises(EvolutionError):
                    verify_dependency_source(self.manager, self.task, self.latest)
                self.node.clear()
                self.node.update(original)

    def test_manual_task_and_ci_repair_keep_their_existing_source_policy(self):
        self.metadata.campaign_id = ""
        verify_dependency_source(self.manager, self.task, self.base)
        self.metadata.campaign_id = "campaign"
        self.metadata.ci_repair_target = {"head_sha": "a" * 40}
        verify_dependency_source(self.manager, self.task, self.base)

    def test_missing_campaign_or_ambiguous_child_fails_closed(self):
        self.graph["nodes"]["duplicate"] = copy.deepcopy(self.graph["nodes"]["child"])
        with self.assertRaises(EvolutionError):
            verify_dependency_source(self.manager, self.task, self.latest)
        self.graph = None
        with self.assertRaises(EvolutionError):
            verify_dependency_source(self.manager, self.task, self.latest)
