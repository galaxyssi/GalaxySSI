from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from desktop_memory import DesktopMemoryStore
from desktop_memory_critic import AUDIT_INTERVAL_MS, MUTATION_THRESHOLD


class MutableClock:
    def __init__(self, seconds: float = 100.0) -> None:
        self.seconds = seconds

    def __call__(self) -> float:
        return self.seconds

    def advance_ms(self, milliseconds: int) -> None:
        self.seconds += milliseconds / 1_000


class DesktopMemoryCriticTest(unittest.TestCase):
    def test_initial_audit_is_due_and_persists_completed_run(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db", now=lambda: 100.0)

            before = store.critic_status()
            result = store.run_critic(force=False, trigger="startup")
            after = store.critic_status()

            self.assertTrue(before["due"])
            self.assertEqual(before["due_reason"], "initial")
            self.assertTrue(result["executed"])
            self.assertEqual(result["run"]["status"], "completed")
            self.assertEqual(after["latest"]["id"], result["run"]["id"])
            self.assertFalse(after["due"])

    def test_expired_memory_is_retired_with_graph_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            clock = MutableClock()
            store = DesktopMemoryStore(Path(directory) / "memory.db", now=clock)
            memory = store.remember(
                "GalaxySSI temporary desktop state is active",
                kind="project_state",
                namespace="project:galaxyssi",
                key="temporary-state",
                evidence=[{"source": "runtime"}],
                valid_until_at=99_000,
            )

            result = store.run_critic(trigger="manual")
            retired = store.get(memory["id"])
            graph = store.graph_snapshot()

            self.assertEqual(retired["status"], "retracted")
            self.assertEqual(retired["temporal_state"], "deprecated")
            self.assertEqual(result["run"]["action_count"], 1)
            self.assertEqual(result["run"]["findings"][0]["kind"], "expired")
            self.assertEqual(graph["node_count"], 0)
            self.assertGreater(graph["historical_node_count"], 0)

    def test_equivalent_memory_is_consolidated_without_deleting_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            clock = MutableClock()
            store = DesktopMemoryStore(Path(directory) / "memory.db", now=clock)
            first = store.remember(
                "GalaxySSI Desktop memory audit is enabled",
                kind="fact",
                namespace="project:galaxyssi",
                key="audit-enabled-a",
                confidence=0.8,
                evidence=[{"source": "test-a"}],
            )
            clock.advance_ms(1_000)
            second = store.remember(
                "GalaxySSI desktop memory audit is enabled.",
                kind="fact",
                namespace="project:galaxyssi",
                key="audit-enabled-b",
                confidence=0.9,
                importance=0.8,
                evidence=[{"source": "test-b"}],
            )

            result = store.run_critic(trigger="manual")
            active = store.list(status="active")
            history = store.list(status="history")

            self.assertEqual(result["run"]["action_count"], 1)
            self.assertEqual(result["run"]["actions"][0]["kind"], "consolidate")
            self.assertEqual([item["id"] for item in active], [second["id"]])
            self.assertEqual([item["id"] for item in history], [first["id"]])
            self.assertEqual(
                {item["source"] for item in active[0]["evidence"]},
                {"test-a", "test-b"},
            )

    def test_sensitive_and_cross_namespace_memories_are_never_auto_merged(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db", now=lambda: 100.0)
            store.remember(
                "Use concise responses",
                kind="preference",
                namespace="user",
                key="style-a",
            )
            store.remember(
                "Use concise responses.",
                kind="preference",
                namespace="user",
                key="style-b",
            )
            store.remember(
                "Release status is ready",
                kind="fact",
                namespace="project:alpha",
                key="release-alpha",
            )
            store.remember(
                "Release status is ready.",
                kind="fact",
                namespace="project:beta",
                key="release-beta",
            )

            result = store.run_critic(trigger="manual")

            self.assertEqual(result["run"]["action_count"], 0)
            self.assertEqual(store.stats()["active"], 4)

    def test_conflicts_low_confidence_and_stale_candidates_only_request_review(self):
        with tempfile.TemporaryDirectory() as directory:
            clock = MutableClock()
            store = DesktopMemoryStore(Path(directory) / "memory.db", now=clock)
            low = store.remember(
                "The experimental runtime may be available",
                kind="fact",
                key="runtime-availability",
                confidence=0.4,
            )
            current = store.remember(
                "GalaxySSI release status is ready",
                kind="project_state",
                key="release-status",
            )
            conflict = store.propose(
                "GalaxySSI release status is blocked",
                kind="project_state",
                key="release-status",
            )
            pending = store.propose(
                "My legal name is Memory Critic User",
                kind="identity",
                key="legal-name",
            )
            with store._lock, store._connect() as connection:
                connection.execute(
                    "UPDATE memories SET use_count = 3 WHERE id = ?",
                    (low["id"],),
                )
            clock.advance_ms(31 * 24 * 60 * 60 * 1_000)

            result = store.run_critic(trigger="manual")
            kinds = {finding["kind"] for finding in result["run"]["findings"]}

            self.assertEqual(result["run"]["action_count"], 0)
            self.assertTrue({
                "low_confidence_reused",
                "unresolved_conflict",
                "stale_candidate",
            }.issubset(kinds))
            self.assertEqual(store.get(current["id"])["status"], "active")
            self.assertEqual(store.get_candidate(conflict["id"])["status"], "conflicted")
            self.assertEqual(store.get_candidate(pending["id"])["status"], "pending_review")

    def test_mutation_and_time_thresholds_schedule_audit(self):
        with tempfile.TemporaryDirectory() as directory:
            clock = MutableClock()
            store = DesktopMemoryStore(Path(directory) / "memory.db", now=clock)
            store.run_critic(force=False, trigger="startup")
            for index in range(MUTATION_THRESHOLD - 1):
                store.remember(
                    f"Unique project event number {index}",
                    kind="episode",
                    key=f"event-{index}",
                )
            self.assertFalse(store.critic_status()["due"])

            store.remember(
                "Unique project event reaching the audit threshold",
                kind="episode",
                key="event-threshold",
            )
            status = store.critic_status()
            self.assertTrue(status["due"])
            self.assertEqual(status["due_reason"], "mutation_threshold")

            store.run_critic(force=False, trigger="scheduled")
            clock.advance_ms(AUDIT_INTERVAL_MS)
            status = store.critic_status()
            self.assertTrue(status["due"])
            self.assertEqual(status["due_reason"], "time_interval")

    def test_repeated_audit_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db", now=lambda: 100.0)
            store.remember(
                "GalaxySSI repeated critic audit is enabled",
                key="critic-a",
            )
            store.remember(
                "GalaxySSI repeated Critic audit is enabled.",
                key="critic-b",
            )

            first = store.run_critic(trigger="manual")
            second = store.run_critic(trigger="manual")

            self.assertEqual(first["run"]["action_count"], 1)
            self.assertEqual(second["run"]["action_count"], 0)
            self.assertEqual(len(store.critic_status()["history"]), 2)

    def test_failed_action_rolls_back_memory_and_run_record(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db", now=lambda: 100.0)
            memory = store.remember(
                "GalaxySSI temporary state should expire",
                key="expiring-state",
                valid_until_at=99_000,
            )

            with patch(
                "desktop_memory_critic.retract_memory_graph_evidence",
                side_effect=RuntimeError("graph write failed"),
            ):
                with self.assertRaisesRegex(RuntimeError, "graph write failed"):
                    store.run_critic(trigger="manual")

            self.assertEqual(store.get(memory["id"])["status"], "active")
            history = store.critic_status()["history"]
            self.assertEqual(len(history), 1)
            self.assertEqual(history[0]["status"], "failed")
            self.assertIn("graph write failed", history[0]["error"])

    def test_clear_removes_audit_history_and_resets_schedule(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db", now=lambda: 100.0)
            store.remember("GalaxySSI has durable memory", key="durable-memory")
            store.run_critic(trigger="manual")

            store.clear()
            status = store.critic_status()

            self.assertEqual(status["history"], [])
            self.assertTrue(status["due"])
            self.assertEqual(status["mutations_since_run"], 0)

    def test_audit_history_survives_store_reload(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "memory.db"
            store = DesktopMemoryStore(path, now=lambda: 100.0)
            run = store.run_critic(trigger="manual")

            reloaded = DesktopMemoryStore(path, now=lambda: 101.0)
            latest = reloaded.critic_status()["latest"]

            self.assertEqual(latest["id"], run["run"]["id"])
            self.assertEqual(latest["status"], "completed")


if __name__ == "__main__":
    unittest.main()
