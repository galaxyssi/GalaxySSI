from __future__ import annotations

import copy
import subprocess
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

from evolution_v2 import ci_repair, legacy
from evolution_v2.manager import EvolutionManager
from test_evolution_v2.test_ci_snapshot import URL


class CiRepairGitTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        self.origin = self.root / "origin.git"
        self.source.mkdir()
        self.git("init", "-b", "main")
        self.git("config", "user.name", "CI Repair Test")
        self.git("config", "user.email", "test@galaxyssi.local")
        (self.source / "src").mkdir()
        (self.source / "src/value.txt").write_text("initial\n", encoding="utf-8")
        self.git("add", ".")
        self.git("commit", "-m", "Initial")
        self.base = self.git("rev-parse", "HEAD")
        self.git("init", "--bare", str(self.origin))
        self.git("remote", "add", "origin", str(self.origin))
        self.git("push", "origin", "main")
        self.git("switch", "-c", "evolution/original")
        self.head = self.commit("failed implementation")
        self.git("push", "origin", "evolution/original")
        self.current = {"repository": "galaxyssi/GalaxySSI", "head_repository": "galaxyssi/GalaxySSI",
                        "base_repository": "galaxyssi/GalaxySSI", "state": "open", "head_ref": "evolution/original"}
        self.manager = SimpleNamespace(source_root=self.source, runner=legacy.EvolutionCommandRunner(),
            github=SimpleNamespace(pull_request_head=self.pr_head, current_repository=lambda: "galaxyssi/GalaxySSI"))
        self.repair = {"url": URL, "head_sha": self.head, "head_ref": "evolution/original"}

    def git(self, *args, cwd=None):
        result = subprocess.run(["git", *args], cwd=cwd or self.source, capture_output=True, text=True, timeout=30)
        if result.returncode:
            raise AssertionError(result.stderr)
        return result.stdout.strip()

    def commit(self, text):
        (self.source / "src/value.txt").write_text(text + "\n", encoding="utf-8")
        self.git("add", ".")
        self.git("commit", "-m", text)
        return self.git("rev-parse", "HEAD")

    def pr_head(self, _url):
        return {**self.current, "head_sha": self.git("rev-parse", "refs/heads/evolution/original", cwd=self.origin)}

    def test_prepare_source_uses_failed_pr_not_main(self):
        self.git("switch", "main")
        self.assertEqual(self.head, ci_repair.prepare_source(self.manager, None, self.repair))
        self.assertEqual(self.base, self.git("rev-parse", "HEAD"))

    def test_fast_forward_updates_same_branch_and_is_idempotent(self):
        candidate = self.commit("repair compiler failure")
        task = SimpleNamespace(candidate_commit=candidate)
        self.assertEqual(URL, ci_repair.publish_candidate(self.manager, task, self.source, self.repair))
        self.assertEqual(candidate, self.pr_head(URL)["head_sha"])
        self.assertEqual(URL, ci_repair.publish_candidate(self.manager, task, self.source, self.repair))
        self.assertEqual(self.base, self.git("rev-parse", "refs/heads/main", cwd=self.origin))

    def test_changed_remote_head_rejects_old_repair(self):
        candidate = self.commit("old repair")
        self.git("switch", "-c", "other-work", self.head)
        newer = self.commit("someone elses change")
        self.git("push", "origin", "HEAD:refs/heads/evolution/original")
        with self.assertRaises(legacy.EvolutionError) as raised:
            ci_repair.publish_candidate(self.manager, SimpleNamespace(candidate_commit=candidate), self.source, self.repair)
        self.assertEqual("ci_head_changed", raised.exception.code)
        self.assertEqual(newer, self.pr_head(URL)["head_sha"])

    def test_unrelated_candidate_cannot_replace_pr_history(self):
        self.git("switch", "main")
        candidate = self.commit("unrelated main change")
        with self.assertRaises(legacy.EvolutionError) as raised:
            ci_repair.publish_candidate(self.manager, SimpleNamespace(candidate_commit=candidate), self.source, self.repair)
        self.assertEqual("ci_repair_ancestry_invalid", raised.exception.code)
        self.assertEqual(self.head, self.pr_head(URL)["head_sha"])

    def test_closed_pr_and_fork_are_rejected(self):
        for updates in ({"state": "closed"}, {"head_repository": "fork/repo"}):
            with self.subTest(updates=updates):
                old = dict(self.current)
                self.current.update(updates)
                with self.assertRaises(legacy.EvolutionError):
                    ci_repair.prepare_source(self.manager, None, self.repair)
                self.current = old

    def test_real_manager_runs_gates_then_updates_original_pr(self):
        class FocusedManager(EvolutionManager):
            def _gate_commands(self, changed_files):
                return [legacy.GateCommand("git-diff-check", ("git", "diff", "--check"), timeout_seconds=30)]

        def patch_agent(_task, _attempt, worktree, _failure):
            (worktree / "src/value.txt").write_text("repaired\n", encoding="utf-8")
            return "Repaired the implementation."

        manager = FocusedManager(source_root=self.source, store=legacy.EvolutionStore(self.root / "state"), patch_agent=patch_agent)
        manager.github = SimpleNamespace(pull_request_head=self.pr_head, current_repository=lambda: "galaxyssi/GalaxySSI",
                                         authenticated=lambda: True)
        parent = manager.create(problem="Improve source parser", scope=["src"], acceptance=["Preserve behavior"], risk_level="low")
        parent.status, parent.pull_request_url = "published", URL
        manager.store.save(parent)
        from evolution_v2.common import sha256_text
        repair = {**self.repair, "parent_task_id": parent.task_id,
                  "task_id": "evolve-ci-" + sha256_text(f"{parent.task_id}\0{self.head}")[:32]}
        child = manager.ensure_ci_repair(repair, {"status": "failed", "head_sha": self.head, "checks": []})
        manager._pin_source_commit(child)
        candidate = manager.run_sync(child.task_id)
        self.assertEqual("waiting_approval", candidate.status, candidate.last_error)
        self.assertTrue(all(g.status == "passed" for g in candidate.attempts[-1].gates))
        # Labeling is orthogonal; this local Git test must not contact GitHub.
        original_runner = manager.runner
        class Runner:
            def run(self, argv, cwd, **kwargs):
                if argv[0] == "gh":
                    self_test.assertEqual(("gh", "pr", "edit"), argv[:3])
                    return SimpleNamespace(returncode=0, stdout="")
                return original_runner.run(argv, cwd, **kwargs)
        self_test = self
        manager.runner = Runner()
        published = manager.publish(candidate.task_id, candidate.approval_hash)
        self.assertEqual("published", published.status)
        self.assertEqual(URL, published.pull_request_url)
        self.assertEqual(candidate.candidate_commit, self.pr_head(URL)["head_sha"])
        self.assertIsNone(manager.ci_watches.get(child.task_id))
        self.assertEqual("failed implementation\n", (self.source / "src/value.txt").read_text(encoding="utf-8"))
