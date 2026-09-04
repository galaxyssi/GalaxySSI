from __future__ import annotations

import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from desktop_memory import DesktopMemoryStore
from desktop_skills import DesktopSkillRegistry


class DesktopMemoryTest(unittest.TestCase):
    def test_retrieves_cross_conversation_memory_and_supersedes_state(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db", now=lambda: 100.0)
            first = store.remember(
                "GalaxySSI response style is concise",
                kind="decision",
                key="project:response-style",
                conversation_id="old-conversation",
            )
            second = store.remember(
                "GalaxySSI response style is concise and action oriented",
                kind="decision",
                key="project:response-style",
                conversation_id="new-conversation",
            )

            previous = store.get(first["id"])
            self.assertEqual(previous["status"], "superseded")
            self.assertEqual(previous["superseded_by_id"], second["id"])
            self.assertEqual(second["supersedes_id"], first["id"])
            matches = store.search("What is the GalaxySSI response style?")
            self.assertEqual(matches[0]["id"], second["id"])

    def test_supersession_chain_preserves_every_version_and_its_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            clock = iter((100.0, 101.0, 102.0, 103.0))
            store = DesktopMemoryStore(Path(directory) / "memory.db", now=lambda: next(clock))
            first = store.remember(
                "The runtime is preparing",
                kind="device_state",
                key="device:runtime-state",
                evidence=[{"source": "event-a"}],
            )
            second = store.remember(
                "The runtime is installing",
                kind="device_state",
                key="device:runtime-state",
                evidence=[{"source": "event-b"}],
            )
            third = store.remember(
                "The runtime is ready",
                kind="device_state",
                key="device:runtime-state",
                evidence=[{"source": "event-c"}],
            )

            chain = store.supersession_chain(second["id"])

            self.assertTrue(chain["complete"])
            self.assertEqual(
                [first["id"], second["id"], third["id"]],
                [memory["id"] for memory in chain["memories"]],
            )
            self.assertEqual(
                ["event-a", "event-b", "event-c"],
                [memory["evidence"][0]["source"] for memory in chain["memories"]],
            )
            self.assertEqual(chain["evidence_count"], 3)
            self.assertEqual(store.get(first["id"])["superseded_by_id"], second["id"])
            self.assertEqual(store.get(second["id"])["supersedes_id"], first["id"])
            self.assertEqual(store.get(second["id"])["superseded_by_id"], third["id"])
            self.assertEqual(store.get(third["id"])["supersedes_id"], second["id"])
            snapshot = store.evolution_snapshot()
            self.assertEqual(snapshot["summary"]["supersession_edges"], 2)
            self.assertEqual(snapshot["supersession"]["broken_edge_count"], 0)

    def test_evolution_ignores_secrets_and_records_reusable_task_episode(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db")

            self.assertIsNone(store.remember("api_key=secret-value", kind="fact"))
            learned = store.evolve(
                "Build the desktop release checklist and remember that verification is required",
                "Created and verified the release checklist with four checks.",
                conversation_id="conversation-1",
                task_id="task-1",
            )

            self.assertGreaterEqual(len(learned), 1)
            self.assertGreaterEqual(store.stats()["active"], 1)
            self.assertIn("verification", store.compile_context("desktop release verification"))

    def test_evolution_keeps_explicit_chinese_memory_but_skips_volatile_status(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db")

            explicit = store.evolve(
                "\u8bf7\u8bb0\u4f4f\uff1a\u9ed8\u8ba4\u4f7f\u7528\u7b80\u4f53\u4e2d\u6587",
                "\u5df2\u8bb0\u4f4f\uff0c\u540e\u7eed\u9ed8\u8ba4\u4f7f\u7528\u7b80\u4f53\u4e2d\u6587\u56de\u590d\u3002",
                task_id="task-explicit",
            )
            volatile = store.evolve(
                "Show current computer status and memory usage",
                "Windows 11 with 20 GB memory currently available.",
                task_id="task-volatile",
            )

            self.assertEqual(explicit[0]["kind"], "preference")
            self.assertEqual(explicit[0]["status"], "pending_review")
            self.assertEqual(store.stats()["active"], 0)
            approved = store.approve_candidate(explicit[0]["id"])
            self.assertEqual(approved["status"], "approved")
            self.assertIn("\u7b80\u4f53\u4e2d\u6587", store.compile_context("\u9ed8\u8ba4\u8bed\u8a00"))
            self.assertEqual(volatile, [])

    def test_low_risk_fact_auto_merges_with_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db", now=lambda: 200.0)
            candidate = store.propose(
                "GalaxySSI project build is passing",
                kind="project_state",
                key="project:galaxyssi:build",
                conversation_id="conversation-1",
                task_id="task-1",
            )

            self.assertEqual(candidate["status"], "auto_merged")
            self.assertEqual(candidate["evolution_action"], "create")
            self.assertEqual(candidate["namespace"], "project")
            self.assertTrue(candidate["resulting_memory_id"])
            memory = store.get(candidate["resulting_memory_id"])
            self.assertEqual(memory["temporal_state"], "current")
            self.assertEqual(memory["evidence"][0]["task_id"], "task-1")

    def test_auto_merge_rolls_back_queue_and_memory_when_promotion_fails(self):
        class FailingPromotionStore(DesktopMemoryStore):
            def _before_candidate_promotion(self, _connection, _candidate_id):
                raise RuntimeError("simulated promotion failure")

        with tempfile.TemporaryDirectory() as directory:
            store = FailingPromotionStore(Path(directory) / "memory.db", now=lambda: 225.0)

            with self.assertRaisesRegex(RuntimeError, "simulated promotion failure"):
                store.propose(
                    "GalaxySSI release verification is passing",
                    kind="project_state",
                    key="project:release-verification",
                )

            snapshot = store.stats()
            self.assertEqual(snapshot["total"], 0)
            self.assertEqual(sum(snapshot["candidate_counts"].values()), 0)

    def test_pending_candidate_is_excluded_from_context_until_atomic_approval(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db", now=lambda: 230.0)
            candidate = store.propose(
                "Prefer compact release status summaries",
                kind="preference",
                key="user:release-status-style",
            )

            self.assertEqual(candidate["status"], "pending_review")
            self.assertNotIn(
                "compact release status",
                store.compile_context("release status summary").casefold(),
            )
            approved = store.approve_candidate(candidate["id"])
            self.assertEqual(approved["status"], "approved")
            self.assertIn(
                "compact release status",
                store.compile_context("release status summary").casefold(),
            )

    def test_matching_evidence_is_reported_as_strengthening_current_memory(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db", now=lambda: 250.0)
            current = store.remember(
                "GalaxySSI desktop memory is encrypted",
                kind="project_state",
                key="project:desktop-memory-security",
                evidence=[{"source": "architecture"}],
            )
            candidate = store.propose(
                "GalaxySSI desktop memory is encrypted",
                kind="project_state",
                key="project:desktop-memory-security",
                evidence=[{"source": "runtime-check"}],
            )

            self.assertEqual(candidate["status"], "auto_merged")
            self.assertEqual(candidate["evolution_action"], "strengthen")
            self.assertEqual(candidate["target_memory_ids"], [current["id"]])
            strengthened = store.get(candidate["resulting_memory_id"])
            self.assertEqual(len(strengthened["evidence"]), 2)

    def test_identity_and_security_candidates_wait_for_review(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db")
            identity = store.propose(
                "The user display name is Ada",
                kind="identity",
                key="user:display-name",
            )
            security = store.propose(
                "Require confirmation before sending external messages",
                kind="security",
                key="security:external-message-confirmation",
            )

            self.assertEqual(identity["status"], "pending_review")
            self.assertEqual(security["status"], "pending_review")
            self.assertEqual(store.stats()["pending"], 2)
            self.assertEqual(store.stats()["active"], 0)

    def test_sensitive_conversation_does_not_leak_into_episode_memory(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db")
            learned = store.evolve(
                "My name is Ada and this should be used in future conversations",
                "Understood. I will use Ada as your display name in future conversations.",
                conversation_id="conversation-identity",
                task_id="task-identity",
            )

            self.assertEqual(len(learned), 1)
            self.assertEqual(learned[0]["kind"], "identity")
            self.assertEqual(learned[0]["status"], "pending_review")
            self.assertEqual(store.stats()["active"], 0)

    def test_private_candidate_is_redacted_and_never_persisted(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db")
            blocked = store.propose(
                "Do not save this password=top-secret-value",
                kind="security",
            )

            self.assertEqual(blocked["status"], "private_blocked")
            self.assertEqual(blocked["content"], "")
            self.assertFalse(blocked["persisted"])
            self.assertEqual(store.list_candidates(), [])
            self.assertEqual(store.stats()["total"], 0)
            learned = store.evolve(
                "Remember that api_key=top-secret-value",
                "I will keep this credential available for future tasks.",
                task_id="task-secret",
            )
            self.assertEqual(learned[0]["status"], "private_blocked")
            self.assertEqual(learned[0]["content"], "")
            self.assertEqual(store.stats()["total"], 0)

    def test_conflict_waits_for_review_then_preserves_superseded_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            clock = iter((300.0, 301.0, 302.0, 303.0, 304.0, 305.0, 306.0))
            store = DesktopMemoryStore(Path(directory) / "memory.db", now=lambda: next(clock))
            previous = store.remember(
                "The device runtime is stable",
                kind="device_state",
                key="device:runtime-state",
                evidence=[{"source": "health-check-1"}],
            )
            candidate = store.propose(
                "The device runtime is blocked",
                kind="device_state",
                key="device:runtime-state",
                evidence=[{"source": "health-check-2"}],
            )

            self.assertEqual(candidate["status"], "conflicted")
            self.assertEqual(candidate["evolution_action"], "review_conflict")
            self.assertEqual(candidate["target_memory_ids"], [previous["id"]])
            self.assertEqual(store.get(previous["id"])["status"], "active")
            approved = store.approve_candidate(candidate["id"])
            self.assertEqual(approved["status"], "approved")
            old = store.get(previous["id"])
            current = store.get(approved["resulting_memory_id"])
            self.assertEqual(old["status"], "superseded")
            self.assertEqual(old["temporal_state"], "deprecated")
            self.assertEqual(old["superseded_by_id"], current["id"])
            self.assertEqual(current["supersedes_id"], old["id"])
            self.assertEqual(old["evidence"][0]["source"], "health-check-1")
            self.assertEqual(current["evidence"][0]["source"], "health-check-2")

    def test_explicit_replacement_auto_supersedes_old_state(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db")
            previous = store.remember(
                "GalaxySSI settings is Control Center",
                kind="project_state",
                key="project:settings-name",
            )
            replacement = store.propose(
                "GalaxySSI settings is now Agent Center",
                kind="project_state",
                key="project:settings-name",
            )

            self.assertEqual(replacement["status"], "auto_merged")
            self.assertEqual(replacement["evolution_action"], "supersede")
            self.assertEqual(replacement["target_memory_ids"], [previous["id"]])
            self.assertEqual(store.get(previous["id"])["status"], "superseded")
            self.assertEqual(store.list(status="history")[0]["id"], previous["id"])

    def test_evolution_snapshot_exposes_state_evidence_conflicts_and_health(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db", now=lambda: 500.0)
            current = store.remember(
                "GalaxySSI memory evolution UI is enabled",
                kind="project_state",
                key="project:memory-evolution-ui",
                evidence=[{"source": "verified-test"}],
            )
            planned = store.remember(
                "Plan the next memory audit",
                kind="goal",
                key="project:next-memory-audit",
            )
            historical = store.remember(
                "The first memory audit completed last week",
                kind="project_state",
                key="project:first-memory-audit",
                temporal_state="historical",
            )
            deprecated = store.remember(
                "The retired memory dashboard used a legacy layout",
                kind="project_state",
                key="project:legacy-memory-dashboard",
                temporal_state="deprecated",
            )
            pending = store.propose(
                "My legal name is Memory Test User",
                kind="identity",
                key="user:legal-name",
            )
            conflict = store.propose(
                "GalaxySSI memory evolution UI lacks access",
                kind="project_state",
                key="project:memory-evolution-ui",
                evidence=[{"source": "conflicting-observation"}],
            )

            snapshot = store.evolution_snapshot()

            self.assertEqual(snapshot["contract_version"], 1)
            self.assertEqual(snapshot["summary"]["current"], 1)
            self.assertEqual(snapshot["summary"]["planned"], 1)
            self.assertEqual(snapshot["summary"]["historical"], 1)
            self.assertEqual(snapshot["summary"]["deprecated"], 1)
            self.assertEqual(snapshot["summary"]["pending_review"], 1)
            self.assertEqual(snapshot["summary"]["conflicted"], 1)
            self.assertEqual(snapshot["summary"]["evidence"], 1)
            self.assertEqual(snapshot["health"]["status"], "attention")
            self.assertEqual(snapshot["conflicts"][0]["id"], conflict["id"])
            self.assertEqual(snapshot["conflicts"][0]["current_memories"][0]["id"], current["id"])
            self.assertEqual(snapshot["conflicts"][0]["evolution_action"], "review_conflict")
            self.assertTrue(any(
                item["id"] == planned["id"]
                for item in store.list(status="active")
            ))
            active_by_id = {
                item["id"]: item["temporal_state"]
                for item in store.list(status="active")
            }
            self.assertEqual(active_by_id[historical["id"]], "historical")
            self.assertEqual(active_by_id[deprecated["id"]], "deprecated")
            self.assertEqual(pending["status"], "pending_review")
            self.assertNotIn(pending["id"], active_by_id)

    def test_namespaces_isolate_identical_keys(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db")
            user = store.remember(
                "Use a concise response style",
                kind="fact",
                key="response-style",
                namespace="user",
            )
            project = store.remember(
                "Use a detailed release report",
                kind="fact",
                key="response-style",
                namespace="project",
            )

            self.assertEqual(store.get(user["id"])["status"], "active")
            self.assertEqual(store.get(project["id"])["status"], "active")
            self.assertEqual(store.stats()["active"], 2)

    def test_scoped_projects_and_devices_never_supersede_each_other(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db")
            alpha = store.remember(
                "Release status is ready",
                kind="project_state",
                key="release-status",
                namespace="project:alpha",
            )
            beta = store.remember(
                "Release status is blocked",
                kind="project_state",
                key="release-status",
                namespace="project:beta",
            )
            phone = store.remember(
                "Release status is unavailable on the phone",
                kind="device_state",
                key="release-status",
                namespace="device:phone",
            )
            alpha_update = store.remember(
                "Release status is published",
                kind="project_state",
                key="release-status",
                namespace="project:alpha",
            )

            self.assertEqual(store.get(alpha["id"])["status"], "superseded")
            self.assertEqual(store.get(alpha["id"])["superseded_by_id"], alpha_update["id"])
            self.assertEqual(store.get(beta["id"])["status"], "active")
            self.assertEqual(store.get(phone["id"])["status"], "active")
            self.assertEqual(store.supersession_chain(alpha_update["id"])["complete"], True)

    def test_namespace_filtered_retrieval_and_counts_use_typed_boundaries(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db")
            store.remember(
                "Battery status is 80 percent",
                kind="device_state",
                key="battery-status",
                namespace="device:phone",
            )
            store.remember(
                "Battery status dashboard is blocked",
                kind="project_state",
                key="battery-status",
                namespace="project:battery-app",
            )

            device_rows = store.search("battery status", namespaces={"device"})
            project_rows = store.search("battery status", namespaces={"project:battery-app"})
            context = store.compile_context("battery status", namespaces={"device"})
            snapshot = store.evolution_snapshot()

            self.assertEqual([item["namespace"] for item in device_rows], ["device:phone"])
            self.assertEqual([item["namespace"] for item in project_rows], ["project:battery-app"])
            self.assertIn("[device:phone/device_state]", context)
            self.assertEqual(snapshot["namespace_counts"]["device"], 1)
            self.assertEqual(snapshot["namespace_counts"]["project"], 1)

    def test_graph_memory_builds_user_device_model_feature_project_and_setting_nodes(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db")
            statements = (
                ("User prefers concise responses", "preference", "user", "user-style"),
                ("GalaxySSI phone uses Qwen model", "device_state", "device:phone", "phone-model"),
                ("GalaxySSI supports OCR feature", "fact", "project:galaxyssi", "ocr-support"),
                ("Project Atlas contains Memory feature", "project_state", "project:atlas", "atlas-memory"),
                ("Settings page renamed to Control Center", "decision", "project:galaxyssi", "settings-name"),
            )
            pending = None
            for content, kind, namespace, key in statements:
                candidate = store.propose(
                    content,
                    kind=kind,
                    namespace=namespace,
                    key=key,
                )
                if candidate["status"] == "pending_review":
                    pending = candidate
            self.assertIsNotNone(pending)
            self.assertEqual(store.graph_snapshot()["node_kinds"]["user"], 0)
            store.approve_candidate(pending["id"])

            graph = store.graph_snapshot()

            for kind in ("user", "device", "model", "feature", "project", "setting"):
                self.assertGreater(graph["node_kinds"][kind], 0, kind)
            for relation in ("prefers", "uses", "supports", "has_component", "named_as"):
                self.assertGreater(graph["relation_kinds"][relation], 0, relation)
            self.assertEqual(graph["node_count"], store.stats()["graph"]["node_count"])

    def test_graph_memory_follows_multi_hop_capability_relationships(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db")
            store.remember(
                "User owns GalaxySSI phone",
                namespace="user",
                key="user-phone",
            )
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

            graph = store.search_graph(
                "What model does the GalaxySSI phone support?",
                namespaces={"device"},
                hops=3,
            )
            context = store.compile_context(
                "What model does the GalaxySSI phone support?",
                namespaces={"device"},
            )

            self.assertTrue(any(node["label"] == "Gemma model" for node in graph["nodes"]))
            self.assertTrue(any(edge["kind"] == "supports" for edge in graph["relations"]))
            self.assertIn("Relationship graph (untrusted evidence):", context)
            self.assertIn("Gemma model", context)

    def test_graph_memory_keeps_chinese_device_scope_and_component_relation(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db")
            store.remember(
                "\u624b\u673a\u5305\u542b\u76f8\u673a\u529f\u80fd",
                kind="device_state",
                namespace="device:\u624b\u673a",
                key="phone-camera",
            )

            graph = store.search_graph(
                "\u624b\u673a\u76f8\u673a",
                namespaces={"device:\u624b\u673a"},
            )

            self.assertTrue(any(node["namespace"] == "device:\u624b\u673a" for node in graph["nodes"]))
            self.assertTrue(any(edge["kind"] == "has_component" for edge in graph["relations"]))

    def test_graph_memory_deprecates_replaced_state_but_preserves_history(self):
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

            current = store.search_graph("Gateway offline", namespaces={"project:gateway"})
            historical = store.search_graph(
                "Gateway online",
                namespaces={"project:gateway"},
                include_historical=True,
            )

            self.assertTrue(any(node["label"] == "offline" for node in current["nodes"]))
            self.assertFalse(any(
                edge["kind"] == "has_state"
                and edge["temporal_state"] == "current"
                and any(
                    node["id"] == edge["to_node_id"] and node["label"] == "online"
                    for node in current["nodes"]
                )
                for edge in current["relations"]
            ))
            self.assertTrue(any(
                edge["kind"] == "has_state" and edge["temporal_state"] == "deprecated"
                for edge in historical["relations"]
            ))

    def test_graph_memory_retracts_deleted_evidence_and_clear_removes_graph(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db")
            memory = store.remember(
                "GalaxySSI supports Browser automation",
                namespace="project:galaxyssi",
                key="browser-support",
            )
            self.assertGreater(store.graph_snapshot()["relation_count"], 0)

            self.assertTrue(store.forget(memory["id"]))
            self.assertEqual(store.graph_snapshot()["relation_count"], 0)
            self.assertGreater(store.graph_snapshot()["historical_relation_count"], 0)

            store.clear()
            self.assertEqual(store.graph_snapshot()["node_count"], 0)
            self.assertEqual(store.graph_snapshot()["historical_node_count"], 0)

    def test_rejected_candidate_remains_auditable_after_reload(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "memory.db"
            store = DesktopMemoryStore(path)
            candidate = store.propose(
                "Prefer compact task summaries",
                kind="preference",
                key="user:summary-style",
            )
            rejected = store.reject_candidate(candidate["id"])

            self.assertEqual(rejected["status"], "rejected")
            reloaded = DesktopMemoryStore(path)
            self.assertEqual(
                reloaded.list_candidates(statuses=("rejected",))[0]["review_note"],
                "user_rejected",
            )

    def test_concurrent_proposals_collapse_to_one_pending_candidate(self):
        with tempfile.TemporaryDirectory() as directory:
            store = DesktopMemoryStore(Path(directory) / "memory.db")
            with ThreadPoolExecutor(max_workers=8) as executor:
                candidates = list(executor.map(
                    lambda _index: store.propose(
                        "Prefer concise release summaries",
                        kind="preference",
                        key="user:release-summary-style",
                    ),
                    range(24),
                ))

            self.assertEqual(len({candidate["id"] for candidate in candidates}), 1)
            self.assertEqual(len(store.list_candidates()), 1)


class DesktopSkillRegistryTest(unittest.TestCase):
    def test_builtin_skills_match_without_polluting_main_prompt(self):
        with tempfile.TemporaryDirectory() as directory:
            registry = DesktopSkillRegistry(Path(directory) / "skills.json")

            compiled, matched = registry.compile("Fix the Python project build and run tests")

            self.assertEqual(matched[0].id, "galaxyssi.code-work")
            self.assertIn("run proportionate verification", compiled)

    def test_custom_skill_persists_and_can_be_disabled(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "skills.json"
            registry = DesktopSkillRegistry(path)
            registry.upsert({
                "id": "team.release-review",
                "name": "Release review",
                "description": "Review a release candidate",
                "triggers": ["release candidate"],
                "instructions": "Check versioning, artifacts, and release notes.",
            })

            reloaded = DesktopSkillRegistry(path)
            self.assertEqual(reloaded.match("Review this release candidate")[0].id, "team.release-review")
            reloaded.set_enabled("team.release-review", False)
            self.assertFalse(any(item.id == "team.release-review" for item in reloaded.match("release candidate")))


if __name__ == "__main__":
    unittest.main()
