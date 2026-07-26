from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from evolution_manager import (
    EvolutionError,
    EvolutionManager,
    EvolutionStore,
    GateCommand,
    _discover_android_sdk,
)


class FocusedEvolutionManager(EvolutionManager):
    def _gate_commands(self, changed_files):
        return [
            GateCommand("git-diff-check", ("git", "diff", "--check"), timeout_seconds=30),
        ]


class EvolutionManagerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"
        self.state = self.root / "state"
        self.source.mkdir()
        self._git("init", "-b", "main")
        self._git("config", "user.name", "SignalASI Test")
        self._git("config", "user.email", "test@signalasi.local")
        (self.source / "src").mkdir()
        (self.source / "src" / "value.txt").write_text("stable\n", encoding="utf-8")
        (self.source / "outside.txt").write_text("protected\n", encoding="utf-8")
        self._git("add", "--all")
        self._git("commit", "-m", "Initial")
        self.base_commit = self._git("rev-parse", "HEAD").stdout.strip()

    def tearDown(self) -> None:
        subprocess.run(
            ["git", "worktree", "prune"],
            cwd=self.source,
            capture_output=True,
            check=False,
        )
        self.temporary.cleanup()

    def manager(self, patch_agent, manager_type=FocusedEvolutionManager):
        return manager_type(
            source_root=self.source,
            store=EvolutionStore(self.state),
            patch_agent=patch_agent,
        )

    def task(self, manager: EvolutionManager, **overrides):
        values = {
            "problem": "Update the isolated test value",
            "scope": ["src"],
            "acceptance": ["The candidate contains the updated value"],
            "max_attempts": 2,
        }
        values.update(overrides)
        return manager.create(**values)

    def test_candidate_does_not_mutate_active_checkout(self):
        def patch(_task, _attempt, worktree, _failure):
            (worktree / "src" / "value.txt").write_text("candidate\n", encoding="utf-8")
            return "Updated the candidate."

        manager = self.manager(patch)
        task = self.task(manager)
        result = manager.run_sync(task.task_id)

        self.assertEqual("waiting_approval", result.status)
        self.assertEqual(self.base_commit, self._git("rev-parse", "HEAD").stdout.strip())
        self.assertEqual("stable\n", (self.source / "src" / "value.txt").read_text(encoding="utf-8"))
        candidate = Path(result.attempts[-1].worktree)
        self.assertEqual("candidate\n", (candidate / "src" / "value.txt").read_text(encoding="utf-8"))
        self.assertEqual(["src/value.txt"], result.attempts[-1].changed_files)
        self.assertEqual("passed", result.attempts[-1].gates[0].status)
        self.assertEqual(64, len(result.approval_hash))
        self.assertNotEqual(self.base_commit, result.candidate_commit)

        rolled_back = manager.discard(task.task_id)
        self.assertEqual("rolled_back", rolled_back.status)
        self.assertFalse(candidate.exists())

    def test_scope_violation_discards_every_candidate(self):
        def patch(_task, _attempt, worktree, _failure):
            (worktree / "outside.txt").write_text("escaped\n", encoding="utf-8")
            return "Changed an out-of-scope file."

        manager = self.manager(patch)
        task = self.task(manager)
        result = manager.run_sync(task.task_id)

        self.assertEqual("failed", result.status)
        self.assertEqual(2, len(result.attempts))
        self.assertTrue(all(item.failure_code == "scope_violation" for item in result.attempts))
        self.assertTrue(all(not Path(item.worktree).exists() for item in result.attempts))
        self.assertEqual("protected\n", (self.source / "outside.txt").read_text(encoding="utf-8"))

    def test_failed_gate_is_replanned_in_a_fresh_worktree(self):
        class RetryManager(FocusedEvolutionManager):
            def _gate_commands(self, changed_files):
                return [
                    GateCommand(
                        "candidate-content",
                        (
                            "python",
                            "-c",
                            "import pathlib,sys;"
                            "sys.exit(0 if pathlib.Path('src/value.txt').read_text() == 'good\\n' else 7)",
                        ),
                        timeout_seconds=30,
                    ),
                ]

        failures = []

        def patch(_task, attempt, worktree, failure):
            failures.append(failure)
            value = "bad\n" if attempt.number == 1 else "good\n"
            (worktree / "src" / "value.txt").write_text(value, encoding="utf-8")
            return f"Wrote {value.strip()}."

        manager = self.manager(patch, RetryManager)
        task = self.task(manager)
        result = manager.run_sync(task.task_id)

        self.assertEqual("waiting_approval", result.status)
        self.assertEqual(2, len(result.attempts))
        self.assertEqual("quality_gate_failed", result.attempts[0].failure_code)
        self.assertEqual("failed", result.attempts[0].gates[0].status)
        self.assertEqual("passed", result.attempts[1].gates[0].status)
        self.assertEqual("", failures[0])
        self.assertIn("Quality gate candidate-content failed", failures[1])
        manager.discard(task.task_id)

    def test_store_restores_attempts_and_hides_local_paths(self):
        def patch(_task, _attempt, worktree, _failure):
            (worktree / "src" / "value.txt").write_text("persisted\n", encoding="utf-8")
            return "Persisted."

        manager = self.manager(patch)
        task = self.task(manager)
        manager.run_sync(task.task_id)
        restored = EvolutionStore(self.state).get(task.task_id)

        self.assertIsNotNone(restored)
        self.assertEqual("waiting_approval", restored.status)
        self.assertTrue(restored.attempts[0].worktree)
        public = restored.public()
        self.assertEqual("", public["attempts"][0]["worktree"])
        self.assertEqual("", public["attempts"][0]["gates"][0]["log_path"])
        manager.discard(task.task_id)

    def test_invalid_approval_hash_cannot_publish(self):
        def patch(_task, _attempt, worktree, _failure):
            (worktree / "src" / "value.txt").write_text("candidate\n", encoding="utf-8")
            return "Candidate."

        manager = self.manager(patch)
        task = self.task(manager)
        result = manager.run_sync(task.task_id)

        with self.assertRaises(EvolutionError) as raised:
            manager.publish(task.task_id, "0" * 64)
        self.assertEqual("approval_hash_invalid", raised.exception.code)
        self.assertEqual("waiting_approval", manager.require(task.task_id).status)
        manager.discard(task.task_id)

    def test_protected_and_traversal_scopes_are_rejected(self):
        manager = self.manager(lambda *_args: "")
        for scope in (["../outside"], [".git/config"], ["apps/android/build"]):
            with self.subTest(scope=scope), self.assertRaises(EvolutionError):
                self.task(manager, scope=scope)

    def test_worktree_preparation_failure_becomes_recoverable_blocker(self):
        class BlockedManager(FocusedEvolutionManager):
            def _prepare_attempt(self, task, number):
                raise EvolutionError("worktree_create_failed", "Git worktree is temporarily unavailable.")

        manager = self.manager(lambda *_args: "", BlockedManager)
        task = self.task(manager)
        result = manager.run_sync(task.task_id)

        self.assertEqual("blocked", result.status)
        self.assertEqual("worktree_create_failed", result.last_error_code)
        self.assertEqual([], result.attempts)

    def test_standard_windows_android_sdk_is_discovered_without_environment_override(self):
        local_app_data = self.root / "local-app-data"
        sdk = local_app_data / "Android" / "Sdk"
        sdk.mkdir(parents=True)

        with patch("evolution_manager.Path.home", return_value=self.root / "home"):
            discovered = _discover_android_sdk({
                "LOCALAPPDATA": str(local_app_data),
                "USERPROFILE": str(self.root / "profile"),
            })

        self.assertEqual(sdk.resolve(), discovered)

    def _git(self, *arguments):
        return subprocess.run(
            ["git", *arguments],
            cwd=self.source,
            text=True,
            encoding="utf-8",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=True,
        )


if __name__ == "__main__":
    unittest.main()
