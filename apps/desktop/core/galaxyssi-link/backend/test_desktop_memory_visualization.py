from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from desktop_memory import DesktopMemoryStore


class MutableClock:
    def __init__(self, seconds: float = 100.0) -> None:
        self.seconds = seconds

    def __call__(self) -> float:
        return self.seconds

    def advance(self, seconds: float = 1.0) -> None:
        self.seconds += seconds


class DesktopMemoryVisualizationTest(unittest.TestCase):
    def test_empty_snapshot_has_complete_visualization_contract(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db", now=lambda: 100.0)

            snapshot = store.visualization_snapshot()

            self.assertEqual(snapshot["contract_version"], 1)
            self.assertEqual(snapshot["generated_at"], 100_000)
            self.assertEqual(snapshot["current_state"]["counts"]["total"], 0)
            self.assertEqual(snapshot["timeline"], [])
            self.assertEqual(snapshot["graph"]["nodes"], [])
            self.assertEqual(snapshot["evidence_chains"], [])

    def test_current_state_summarizes_temporal_and_namespace_boundaries(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db", now=lambda: 100.0)
            current = store.remember(
                "GalaxySSI phone battery status is available",
                kind="device_state",
                namespace="device:phone",
                key="battery-status",
                importance=0.9,
            )
            store.remember(
                "Plan the next GalaxySSI release",
                kind="goal",
                namespace="project:galaxyssi",
                key="next-release",
            )

            state = store.visualization_snapshot()["current_state"]

            self.assertEqual(state["counts"]["active"], 2)
            self.assertEqual(state["counts"]["current"], 1)
            self.assertEqual(state["counts"]["planned"], 1)
            self.assertEqual(
                {item["namespace"] for item in state["namespaces"]},
                {"device:phone", "project:galaxyssi"},
            )
            self.assertEqual(state["highlights"][0]["id"], current["id"])

    def test_timeline_orders_memory_candidate_review_and_audit_events(self):
        with tempfile.TemporaryDirectory() as directory:
            clock = MutableClock()
            store = DesktopMemoryStore(Path(directory) / "memory.db", now=clock)
            store.remember(
                "GalaxySSI release status is ready",
                kind="project_state",
                key="release-status",
            )
            clock.advance()
            candidate = store.propose(
                "My display name is Timeline User",
                kind="identity",
                key="display-name",
            )
            clock.advance()
            store.approve_candidate(candidate["id"])
            clock.advance()
            store.run_critic(trigger="manual")

            timeline = store.visualization_snapshot()["timeline"]
            event_types = {event["event_type"] for event in timeline}
            occurred_at = [event["occurred_at"] for event in timeline]

            self.assertTrue({
                "memory_recorded",
                "candidate_created",
                "candidate_approved",
                "critic_completed",
            }.issubset(event_types))
            self.assertEqual(occurred_at, sorted(occurred_at, reverse=True))

    def test_graph_returns_real_nodes_relations_and_evidence_links(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db")
            memory = store.remember(
                "GalaxySSI phone uses Qwen model",
                kind="device_state",
                namespace="device:phone",
                key="phone-model",
                evidence=[{"source": "device-inspection"}],
            )

            graph = store.visualization_snapshot()["graph"]

            self.assertGreaterEqual(len(graph["nodes"]), 2)
            self.assertGreaterEqual(len(graph["relations"]), 1)
            self.assertTrue(any(
                memory["id"] in node["evidence_memory_ids"]
                for node in graph["nodes"]
            ))
            self.assertTrue(any(
                memory["id"] in relation["evidence_memory_ids"]
                for relation in graph["relations"]
            ))
            self.assertGreater(graph["active_node_count"], 0)

    def test_evidence_chain_preserves_versions_sources_and_graph_references(self):
        with tempfile.TemporaryDirectory() as directory:
            clock = MutableClock()
            store = DesktopMemoryStore(Path(directory) / "memory.db", now=clock)
            first = store.remember(
                "GalaxySSI phone uses Qwen model",
                kind="device_state",
                namespace="device:phone",
                key="phone-model",
                evidence=[
                    {"source": "first-probe", "task_id": "task-1"},
                    {"source": "legacy-probe", "observed_at": "unknown"},
                ],
            )
            clock.advance()
            second = store.remember(
                "GalaxySSI phone uses Gemma model",
                kind="device_state",
                namespace="device:phone",
                key="phone-model",
                evidence=[{"source": "second-probe", "task_id": "task-2"}],
            )

            chains = store.visualization_snapshot()["evidence_chains"]
            chain = next(item for item in chains if item["memory_key"] == "phone-model")

            self.assertEqual(
                [version["id"] for version in chain["versions"]],
                [first["id"], second["id"]],
            )
            self.assertEqual(chain["current_memory_id"], second["id"])
            self.assertEqual(
                {item["source"] for item in chain["evidence"]},
                {"first-probe", "legacy-probe", "second-probe"},
            )
            self.assertEqual(
                next(item for item in chain["evidence"] if item["source"] == "legacy-probe")["observed_at"],
                0,
            )
            self.assertTrue(chain["graph_node_ids"])
            self.assertTrue(chain["graph_relation_ids"])

    def test_lifecycle_events_distinguish_superseded_and_retracted_memory(self):
        with tempfile.TemporaryDirectory() as directory:
            clock = MutableClock()
            store = DesktopMemoryStore(Path(directory) / "memory.db", now=clock)
            first = store.remember(
                "GalaxySSI status is preparing",
                key="runtime-status",
            )
            clock.advance()
            store.remember(
                "GalaxySSI status is ready",
                key="runtime-status",
            )
            clock.advance()
            removed = store.remember(
                "GalaxySSI temporary notice remains visible",
                key="temporary-notice",
            )
            clock.advance()
            store.forget(removed["id"])

            timeline = store.visualization_snapshot()["timeline"]
            lifecycle = {
                event["memory_id"]: event["event_type"]
                for event in timeline
                if event["event_type"] in {"memory_superseded", "memory_retracted"}
            }

            self.assertEqual(lifecycle[first["id"]], "memory_superseded")
            self.assertEqual(lifecycle[removed["id"]], "memory_retracted")

    def test_visualization_limits_bound_every_large_collection(self):
        with tempfile.TemporaryDirectory() as directory:
            clock = MutableClock()
            store = DesktopMemoryStore(Path(directory) / "memory.db", now=clock)
            for index in range(25):
                store.remember(
                    f"Project visualization fact number {index}",
                    key=f"visualization-{index}",
                    namespace="project:visualization",
                )
                clock.advance()

            snapshot = store.visualization_snapshot(limit=10)

            self.assertLessEqual(len(snapshot["timeline"]), 10)
            self.assertLessEqual(len(snapshot["graph"]["nodes"]), 10)
            self.assertLessEqual(len(snapshot["graph"]["relations"]), 20)
            self.assertLessEqual(len(snapshot["evidence_chains"]), 10)


if __name__ == "__main__":
    unittest.main()
