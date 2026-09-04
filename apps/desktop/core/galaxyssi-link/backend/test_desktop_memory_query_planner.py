from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from desktop_memory import DesktopMemoryStore
from desktop_memory_query_planner import plan_memory_query


class DesktopMemoryQueryPlannerTest(unittest.TestCase):
    def test_combines_history_device_and_relationship_intent(self):
        plan = plan_memory_query(
            "What model did the phone previously support, and what does it support now?"
        )

        self.assertIn("historical_decision", plan.types)
        self.assertIn("device_capability", plan.types)
        self.assertIn("relationship", plan.types)
        self.assertEqual(plan.temporal_scope, "current_and_history")
        self.assertEqual(plan.namespaces, ("device",))
        self.assertIn("supports", plan.preferred_relations)
        self.assertEqual(plan.graph_hops, 3)

    def test_runtime_does_not_trigger_run_tool_intent(self):
        plan = plan_memory_query("What is the phone runtime status?")

        self.assertIn("device_capability", plan.types)
        self.assertNotIn("tool_evidence", plan.types)

    def test_current_query_excludes_superseded_project_state(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db")
            old = store.remember(
                "Project release status is blocked",
                kind="project_state",
                namespace="project:galaxyssi",
                key="release-status",
            )
            current = store.remember(
                "Project release status is ready",
                kind="project_state",
                namespace="project:galaxyssi",
                key="release-status",
            )

            rows = store.search("What is the current project release status?")

            self.assertEqual([row["id"] for row in rows], [current["id"]])
            self.assertNotIn(old["id"], [row["id"] for row in rows])

    def test_historical_query_returns_superseded_state_only(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db")
            old = store.remember(
                "Project release status is blocked",
                kind="project_state",
                namespace="project:galaxyssi",
                key="release-status",
            )
            store.remember(
                "Project release status is ready",
                kind="project_state",
                namespace="project:galaxyssi",
                key="release-status",
            )

            rows = store.search("What was the previous project release status?")

            self.assertEqual([row["id"] for row in rows], [old["id"]])

    def test_comparison_query_returns_current_and_historical_state(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db")
            old = store.remember(
                "Project release status is blocked",
                kind="project_state",
                namespace="project:galaxyssi",
                key="release-status",
            )
            current = store.remember(
                "Project release status is ready",
                kind="project_state",
                namespace="project:galaxyssi",
                key="release-status",
            )

            rows = store.search("Compare the previous and current project release status")

            self.assertEqual({row["id"] for row in rows}, {old["id"], current["id"]})

    def test_preference_query_does_not_mix_project_state(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db")
            user = store.remember(
                "My default response style preference is concise",
                kind="preference",
                namespace="user",
                key="response-style",
            )
            project = store.remember(
                "The project default response style is detailed",
                kind="project_state",
                namespace="project:docs",
                key="response-style",
            )

            rows = store.search("What is my default response style preference?")

            self.assertEqual([row["id"] for row in rows], [user["id"]])
            self.assertNotIn(project["id"], [row["id"] for row in rows])

    def test_device_query_uses_device_namespace_without_explicit_filter(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db")
            device = store.remember(
                "Phone battery status is 80 percent",
                kind="device_state",
                namespace="device:phone",
                key="battery-status",
            )
            project = store.remember(
                "Battery status feature is under development",
                kind="project_state",
                namespace="project:battery-app",
                key="battery-status",
            )

            rows = store.search("What is the phone battery status?")

            self.assertEqual([row["id"] for row in rows], [device["id"]])
            self.assertNotIn(project["id"], [row["id"] for row in rows])

    def test_graph_query_uses_planned_hops_and_relation_priority(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db")
            store.remember(
                "GalaxySSI phone contains Snapdragon chip",
                kind="device_state",
                namespace="device:phone",
                key="phone-chip",
            )
            store.remember(
                "Snapdragon chip supports Gemma model",
                kind="device_state",
                namespace="device:phone",
                key="chip-model",
            )

            plan = plan_memory_query("What model does the phone support?")
            graph = store.search_graph(
                "What model does the phone support?",
                query_plan=plan,
            )

            self.assertEqual(plan.graph_hops, 3)
            self.assertIn("supports", plan.preferred_relations)
            self.assertTrue(any(node["label"] == "Gemma model" for node in graph["nodes"]))

    def test_historical_graph_query_excludes_current_relation(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db")
            store.remember(
                "Gateway status is online",
                kind="project_state",
                namespace="project:gateway",
                key="gateway-status",
            )
            store.remember(
                "Gateway status is offline",
                kind="project_state",
                namespace="project:gateway",
                key="gateway-status",
            )

            graph = store.search_graph("What was the previous project gateway status?")

            self.assertTrue(graph["relations"])
            self.assertTrue(all(
                relation["temporal_state"] == "deprecated"
                for relation in graph["relations"]
            ))
            self.assertTrue(any(node["label"] == "online" for node in graph["nodes"]))

    def test_context_identifies_query_plan_without_exposing_unrelated_history(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db")
            old = store.remember(
                "Project build status is failing",
                kind="project_state",
                namespace="project:galaxyssi",
                key="build-status",
            )
            current = store.remember(
                "Project build status is passing",
                kind="project_state",
                namespace="project:galaxyssi",
                key="build-status",
            )

            context = store.compile_context("What is the current project build status?")

            self.assertIn("types=project_state", context)
            self.assertIn(current["content"], context)
            self.assertNotIn(old["content"], context)

    def test_general_query_keeps_cross_namespace_retrieval_open(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db")
            memory = store.remember(
                "Orion is the release codename",
                kind="fact",
                namespace="project:galaxyssi",
                key="release-codename",
            )

            plan = plan_memory_query("Tell me about Orion")
            rows = store.search("Tell me about Orion")

            self.assertEqual(plan.types, ("general",))
            self.assertEqual([row["id"] for row in rows], [memory["id"]])


if __name__ == "__main__":
    unittest.main()
