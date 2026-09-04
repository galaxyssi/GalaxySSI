from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from evolution_v2.common import atomic_write_json, sha256_file
from evolution_manager import (
    EvolutionAttempt,
    EvolutionCommandRunner,
    EvolutionError,
    EvolutionGate,
    EvolutionManager,
    EvolutionStore,
    EvolutionTask,
    GateCommand,
    _discover_android_sdk,
    evolution_health,
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
        self._git("config", "user.name", "GalaxySSI Test")
        self._git("config", "user.email", "test@galaxyssi.local")
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
        self.assertEqual(64, len(result.attempts[-1].gates[0].evidence_sha256))
        self.assertEqual(64, len(result.approval_hash))
        self.assertNotEqual(self.base_commit, result.candidate_commit)

        rolled_back = manager.discard(task.task_id)
        self.assertEqual("rolled_back", rolled_back.status)
        self.assertFalse(candidate.exists())

    def test_agent_change_to_active_checkout_blocks_candidate_without_reverting_user_files(self):
        def patch(_task, _attempt, worktree, _failure):
            (worktree / "src" / "value.txt").write_text("candidate\n", encoding="utf-8")
            (self.source / "src" / "value.txt").write_text("unexpected\n", encoding="utf-8")
            return "Attempted an out-of-worktree edit."

        manager = self.manager(patch)
        task = self.task(manager)
        result = manager.run_sync(task.task_id)

        self.assertEqual("blocked", result.status)
        self.assertEqual("active_checkout_changed", result.last_error_code)
        self.assertEqual(1, len(result.attempts))
        self.assertEqual("active_checkout_changed", result.attempts[0].failure_code)
        self.assertFalse(Path(result.attempts[0].worktree).exists())
        self.assertEqual(
            "unexpected\n",
            (self.source / "src" / "value.txt").read_text(encoding="utf-8"),
        )
        self.assertEqual("", result.candidate_commit)

    def test_cleanup_refuses_active_checkout_and_external_paths(self):
        manager = self.manager(lambda *_args: "")
        external = self.root / "external"
        external.mkdir()
        (external / "sentinel.txt").write_text("keep\n", encoding="utf-8")
        cases = (
            (self.source, self.source / "src" / "value.txt"),
            (external, external / "sentinel.txt"),
        )

        for path, sentinel in cases:
            with self.subTest(path=path):
                attempt = EvolutionAttempt(
                    number=1,
                    status="failed",
                    branch="evolution/evolve-safe-cleanup-a1",
                    worktree=str(path),
                )
                with self.assertRaises(EvolutionError) as raised:
                    manager._remove_worktree(attempt, delete_branch=True)
                self.assertIn(
                    raised.exception.code,
                    {"worktree_cleanup_refused", "worktree_unsafe"},
                )
                self.assertTrue(sentinel.exists())

    def test_cleanup_target_is_bound_to_task_and_attempt_identity(self):
        manager = self.manager(lambda *_args: "")
        wrong = manager.store.worktrees_root / "another-task" / "attempt-1"
        wrong.mkdir(parents=True)
        sentinel = wrong / "sentinel.txt"
        sentinel.write_text("keep\n", encoding="utf-8")
        attempt = EvolutionAttempt(
            number=1,
            status="failed",
            branch="evolution/evolve-expected-task-a1",
            worktree=str(wrong),
        )

        with self.assertRaises(EvolutionError) as raised:
            manager._remove_worktree(attempt, delete_branch=True)

        self.assertEqual("worktree_cleanup_refused", raised.exception.code)
        self.assertTrue(sentinel.exists())

    def test_candidate_from_another_repository_is_rejected(self):
        manager = self.manager(lambda *_args: "")
        task_id = "evolve-foreign-repository"
        branch = f"evolution/{task_id}-a1"
        foreign = manager.store.worktrees_root / task_id / "attempt-1"
        foreign.mkdir(parents=True)
        for arguments in (
            ("init", "-b", branch),
            ("config", "user.name", "GalaxySSI Test"),
            ("config", "user.email", "test@galaxyssi.local"),
        ):
            subprocess.run(
                ["git", *arguments],
                cwd=foreign,
                text=True,
                check=True,
                capture_output=True,
            )
        (foreign / "value.txt").write_text("foreign\n", encoding="utf-8")
        subprocess.run(
            ["git", "add", "--all"],
            cwd=foreign,
            text=True,
            check=True,
            capture_output=True,
        )
        subprocess.run(
            ["git", "commit", "-m", "Foreign"],
            cwd=foreign,
            text=True,
            check=True,
            capture_output=True,
        )
        foreign_commit = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=foreign,
            text=True,
            check=True,
            capture_output=True,
        ).stdout.strip()

        with self.assertRaises(EvolutionError) as raised:
            manager._validate_worktree_identity(
                foreign,
                branch=branch,
                expected_commit=foreign_commit,
            )

        self.assertEqual("worktree_identity_invalid", raised.exception.code)

    def test_worktree_storage_cannot_overlap_active_checkout(self):
        with self.assertRaises(EvolutionError) as inside:
            FocusedEvolutionManager(
                source_root=self.source,
                store=EvolutionStore(self.source / "evolution-state"),
                patch_agent=lambda *_args: "",
            )
        self.assertEqual("state_root_unsafe", inside.exception.code)

        outer_store = EvolutionStore(self.root / "outer-state")
        nested_source = outer_store.worktrees_root / "nested-source"
        nested_source.mkdir(parents=True)
        subprocess.run(
            ["git", "init", "-b", "main"],
            cwd=nested_source,
            text=True,
            check=True,
            capture_output=True,
        )
        with self.assertRaises(EvolutionError) as outside:
            FocusedEvolutionManager(
                source_root=nested_source,
                store=outer_store,
                patch_agent=lambda *_args: "",
            )
        self.assertEqual("state_root_unsafe", outside.exception.code)

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
        registered = self._git("worktree", "list", "--porcelain").stdout
        for item in result.attempts:
            self.assertEqual(
                "",
                self._git("branch", "--list", item.branch).stdout.strip(),
            )
            self.assertNotIn(str(Path(item.worktree).resolve()), registered)
        self.assertEqual("protected\n", (self.source / "outside.txt").read_text(encoding="utf-8"))

    def test_incomplete_candidate_rollback_blocks_task(self):
        def patch_candidate(_task, _attempt, worktree, _failure):
            (worktree / "src" / "value.txt").write_text("candidate\n", encoding="utf-8")
            return "Candidate."

        manager = self.manager(patch_candidate)
        task = self.task(manager)
        result = manager.run_sync(task.task_id)
        attempt = result.attempts[-1]
        delegate = manager.runner

        class RefuseBranchDeletionRunner(EvolutionCommandRunner):
            def run(self, argv, cwd, **kwargs):
                if tuple(argv[:4]) == ("git", "branch", "-D", "--"):
                    return subprocess.CompletedProcess(
                        list(argv),
                        1,
                        "simulated branch deletion failure",
                        "",
                    )
                return delegate.run(argv, cwd, **kwargs)

        manager.runner = RefuseBranchDeletionRunner()
        cleaned = manager._cleanup_failed_attempt(result, attempt)

        self.assertFalse(cleaned)
        self.assertEqual("blocked", result.status)
        self.assertEqual("worktree_cleanup_failed", result.last_error_code)
        self.assertFalse(Path(attempt.worktree).exists())
        self.assertNotEqual(
            "",
            self._git("branch", "--list", attempt.branch).stdout.strip(),
        )
        self.assertEqual(self.base_commit, self._git("rev-parse", "HEAD").stdout.strip())

        manager.runner = delegate
        manager._remove_worktree(attempt, delete_branch=True)

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

    def test_valid_candidate_checks_github_auth_after_local_integrity(self):
        def patch_candidate(_task, _attempt, worktree, _failure):
            (worktree / "src" / "value.txt").write_text("candidate\n", encoding="utf-8")
            return "Candidate."

        manager = self.manager(patch_candidate)
        task = self.task(manager)
        result = manager.run_sync(task.task_id)

        with (
            patch.object(manager.github, "authenticated", return_value=False),
            self.assertRaises(EvolutionError) as raised,
        ):
            manager.publish(task.task_id, result.approval_hash)

        self.assertEqual("github_auth_missing", raised.exception.code)
        self.assertEqual("waiting_approval", manager.require(task.task_id).status)
        manager.discard(task.task_id)

    def test_changed_gate_log_invalidates_candidate_publish(self):
        def patch_candidate(_task, _attempt, worktree, _failure):
            (worktree / "src" / "value.txt").write_text("candidate\n", encoding="utf-8")
            return "Candidate."

        manager = self.manager(patch_candidate)
        task = self.task(manager)
        result = manager.run_sync(task.task_id)
        gate = result.attempts[-1].gates[0]
        Path(gate.log_path).write_text("tampered\n", encoding="utf-8")

        with self.assertRaises(EvolutionError) as raised:
            manager.publish(task.task_id, result.approval_hash)

        self.assertEqual("gate_evidence_invalid", raised.exception.code)
        self.assertEqual("waiting_approval", manager.require(task.task_id).status)
        manager.discard(task.task_id)

    def test_android_evidence_artifact_tampering_is_detected(self):
        manager = self.manager(lambda *_args: "")
        task_id = "evolve-android-evidence"
        worktree = manager.store.worktrees_root / task_id / "attempt-1"
        candidate = (
            worktree
            / "apps/android/app/build/outputs/apk/debug/app-debug.apk"
        )
        candidate.parent.mkdir(parents=True)
        candidate.write_bytes(b"candidate-apk")
        evidence_root = manager.store.root / "v2" / "snapshots" / "android-test"
        evidence_root.mkdir(parents=True)
        screenshot = evidence_root / "candidate.png"
        screenshot.write_bytes(b"\x89PNG\r\n\x1a\ncandidate")
        logcat = evidence_root / "candidate-logcat.txt"
        logcat.write_text("clean\n", encoding="utf-8")
        manifest = evidence_root / "candidate-evidence.json"
        atomic_write_json(
            manifest,
            {
                "protocol": "galaxyssi.evolution.android-evidence.v1",
                "passed": True,
                "stable_restored": True,
                "fatal_lines": [],
                "artifacts": {
                    "candidate_apk": {
                        "path": str(candidate.resolve()),
                        "sha256": sha256_file(candidate),
                    },
                    "candidate_screenshot": {
                        "path": str(screenshot.resolve()),
                        "sha256": sha256_file(screenshot),
                    },
                    "candidate_logcat": {
                        "path": str(logcat.resolve()),
                        "sha256": sha256_file(logcat),
                    },
                },
            },
        )
        gate_log = manager.store.logs_root / task_id / "attempt-1-android.log"
        gate_log.parent.mkdir(parents=True)
        gate_log.write_text(
            json.dumps(
                {
                    "passed": True,
                    "evidence_manifest": str(manifest.resolve()),
                    "evidence_sha256": sha256_file(manifest),
                }
            ),
            encoding="utf-8",
        )
        gate = EvolutionGate(
            id="android-device-install-restore",
            status="passed",
            log_path=str(gate_log),
            evidence_sha256=sha256_file(gate_log),
        )
        manager._capture_android_gate_evidence(
            gate,
            gate_log,
            worktree=worktree,
        )
        attempt = EvolutionAttempt(
            number=1,
            status="passed",
            branch=f"evolution/{task_id}-a1",
            worktree=str(worktree),
            gates=[gate],
        )

        manager._validate_gate_evidence(attempt)
        screenshot.write_bytes(b"\x89PNG\r\n\x1a\ntampered")

        with self.assertRaises(EvolutionError) as raised:
            manager._validate_gate_evidence(attempt)

        self.assertEqual("gate_evidence_invalid", raised.exception.code)

    def test_candidate_commit_cannot_change_after_review(self):
        def patch_candidate(_task, _attempt, worktree, _failure):
            (worktree / "src" / "value.txt").write_text("candidate\n", encoding="utf-8")
            return "Candidate."

        manager = self.manager(patch_candidate)
        task = self.task(manager)
        result = manager.run_sync(task.task_id)
        candidate = Path(result.attempts[-1].worktree)
        (candidate / "src" / "value.txt").write_text("unreviewed\n", encoding="utf-8")
        subprocess.run(["git", "add", "--all"], cwd=candidate, check=True, capture_output=True)
        subprocess.run(
            [
                "git",
                "-c",
                "user.name=GalaxySSI Test",
                "-c",
                "user.email=test@galaxyssi.local",
                "commit",
                "-m",
                "Unreviewed change",
            ],
            cwd=candidate,
            check=True,
            capture_output=True,
        )

        with self.assertRaises(EvolutionError) as raised:
            manager.publish(task.task_id, result.approval_hash)

        self.assertEqual("candidate_changed_after_review", raised.exception.code)
        persisted = manager.require(task.task_id)
        self.assertEqual("waiting_approval", persisted.status)
        self.assertEqual("candidate_changed_after_review", persisted.last_error_code)
        self.assertEqual(
            1,
            manager.health().failure_counts["candidate_changed_after_review"],
        )
        manager.discard(task.task_id)

    def test_uncommitted_candidate_changes_cannot_publish(self):
        def patch_candidate(_task, _attempt, worktree, _failure):
            (worktree / "src" / "value.txt").write_text("candidate\n", encoding="utf-8")
            return "Candidate."

        manager = self.manager(patch_candidate)
        task = self.task(manager)
        result = manager.run_sync(task.task_id)
        candidate = Path(result.attempts[-1].worktree)
        (candidate / "src" / "value.txt").write_text("dirty\n", encoding="utf-8")

        with self.assertRaises(EvolutionError) as raised:
            manager.publish(task.task_id, result.approval_hash)

        self.assertEqual("candidate_dirty_after_review", raised.exception.code)
        self.assertEqual(
            "candidate_dirty_after_review",
            manager.require(task.task_id).last_error_code,
        )
        manager.discard(task.task_id)

    def test_health_uses_persisted_task_attempt_and_gate_facts(self):
        now = 1_000_000
        tasks = [
            EvolutionTask(
                task_id="published",
                problem="Published candidate",
                reproduction_steps=[],
                scope=["src"],
                acceptance=["Pass"],
                risk_level="medium",
                max_attempts=3,
                status="published",
                attempts=[
                    EvolutionAttempt(
                        number=1,
                        status="failed",
                        branch="evolution/published-a1",
                        worktree="private-path-one",
                        failure_code="quality_gate_failed",
                        started_at_millis=100,
                        completed_at_millis=1_100,
                        gates=[EvolutionGate(id="unit", status="failed")],
                    ),
                    EvolutionAttempt(
                        number=2,
                        status="passed",
                        branch="evolution/published-a2",
                        worktree="private-path-two",
                        started_at_millis=2_000,
                        completed_at_millis=4_000,
                        gates=[EvolutionGate(id="unit", status="passed")],
                    ),
                ],
                updated_at_millis=now - 1_000,
            ),
            EvolutionTask(
                task_id="stale-running",
                problem="Stale task",
                reproduction_steps=[],
                scope=["src"],
                acceptance=["Pass"],
                risk_level="low",
                max_attempts=2,
                status="running",
                updated_at_millis=now - 360_000,
            ),
            EvolutionTask(
                task_id="old-review",
                problem="Old review",
                reproduction_steps=[],
                scope=["src"],
                acceptance=["Pass"],
                risk_level="medium",
                max_attempts=2,
                status="waiting_approval",
                updated_at_millis=now - 420_000,
            ),
            EvolutionTask(
                task_id="blocked",
                problem="Blocked task",
                reproduction_steps=[],
                scope=["src"],
                acceptance=["Pass"],
                risk_level="medium",
                max_attempts=2,
                status="blocked",
                last_error_code="runtime_unavailable",
                updated_at_millis=now - 5_000,
            ),
        ]

        health = evolution_health(
            tasks,
            now_millis=now,
            stale_after_millis=300_000,
        )

        self.assertEqual(4, health.total_tasks)
        self.assertEqual(1, health.active_tasks)
        self.assertEqual(1, health.waiting_review)
        self.assertEqual(1, health.successful_tasks)
        self.assertEqual(3, health.attention_tasks)
        self.assertEqual(["stale-running"], health.stale_task_ids)
        self.assertEqual(2, health.total_attempts)
        self.assertEqual(1, health.failed_attempts)
        self.assertEqual(1, health.retries)
        self.assertEqual(50, health.gate_pass_percent)
        self.assertEqual(50, health.success_percent)
        self.assertEqual(1_500, health.average_attempt_duration_millis)
        self.assertEqual(420_000, health.oldest_review_age_millis)
        self.assertEqual(1, health.failure_counts["quality_gate_failed"])
        self.assertEqual(1, health.failure_counts["runtime_unavailable"])
        self.assertNotIn("private-path", str(health.public()))

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

    def test_evolution_subscribers_receive_events_until_unsubscribed(self):
        manager = self.manager(lambda *_args: "")
        events: list[dict] = []
        subscription_id = manager.subscribe(lambda event: events.append(dict(event)))

        task = self.task(manager)

        self.assertEqual("created", events[-1]["event"])
        self.assertEqual(task.task_id, events[-1]["task"]["task_id"])
        self.assertTrue(manager.unsubscribe(subscription_id))
        self.assertFalse(manager.unsubscribe(subscription_id))
        self.task(manager, problem="Create another isolated candidate")
        self.assertEqual(1, len(events))

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
