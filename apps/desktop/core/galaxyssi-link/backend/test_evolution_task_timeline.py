from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

from evolution_task_timeline import evolution_task_timeline_item
from evolution_v2.audit import AuditLedger
from evolution_v2.legacy import EvolutionAttempt, EvolutionGate, EvolutionTask


class EvolutionTaskTimelineTests(unittest.TestCase):
    def test_candidate_projects_to_completed_desktop_timeline_with_actions(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            audit = AuditLedger(Path(temp_dir) / "audit.jsonl")
            task = EvolutionTask(
                task_id="evolve-timeline",
                problem="Improve the Desktop self-evolution timeline",
                reproduction_steps=[],
                scope=["apps/desktop"],
                acceptance=["Show each action in the main output"],
                risk_level="medium",
                max_attempts=3,
                status="waiting_approval",
                agent_id="auto",
                candidate_commit="a" * 40,
                candidate_branch="feature/evolution-timeline",
                approval_hash="b" * 64,
                attempts=[
                    EvolutionAttempt(
                        number=1,
                        status="passed",
                        branch="feature/evolution-timeline",
                        worktree="redacted",
                        agent_id="codex",
                        changed_files=["apps/desktop/src/renderer/workspace.js"],
                        gates=[
                            EvolutionGate(
                                id="desktop-source-smoke",
                                status="passed",
                                duration_millis=1_250,
                                summary="Desktop source smoke passed.",
                            ),
                        ],
                        agent_summary="Implemented and verified the self-evolution timeline.",
                        started_at_millis=1_100,
                        completed_at_millis=8_000,
                    ),
                ],
                created_at_millis=1_000,
                updated_at_millis=8_000,
            )
            for event, payload in (
                ("start_requested", {}),
                ("worktree_ready", {"attempt": 1}),
                ("agent_started", {"attempt": 1}),
                ("validation_started", {"attempt": 1}),
                ("gate_started", {"attempt": 1, "gate": "desktop-source-smoke"}),
                ("gate_finished", {"attempt": 1, "gate": "desktop-source-smoke"}),
                ("candidate_ready", {"attempt": 1}),
            ):
                audit.append(event, task_id=task.task_id, payload=payload)
            manager = SimpleNamespace(
                audit=audit,
                task_metadata=lambda _task_id: {"origin": "research"},
            )

            item = evolution_task_timeline_item(manager, task)

            self.assertIsNotNone(item)
            self.assertEqual("self_evolution", item["task_kind"])
            self.assertEqual("completed", item["status"])
            self.assertEqual("waiting_approval", item["evolution_status"])
            self.assertEqual("codex", item["delegate_agent_id"])
            self.assertTrue(item["automatic"])
            self.assertEqual("evolution:evolve-timeline", item["conversation_id"])
            self.assertIn("Implemented and verified", item["result"])
            self.assertEqual(6, len(item["events"]))
            self.assertEqual("Candidate ready for review", item["events"][-1]["title"])
            self.assertEqual("passed", item["quality_gates"][0]["status"])
            self.assertEqual(["apps/desktop/src/renderer/workspace.js"], item["changed_files"])

    def test_unstarted_proposal_is_not_added_to_the_main_timeline(self):
        task = EvolutionTask(
            task_id="evolve-proposed",
            problem="A candidate that has not started",
            reproduction_steps=[],
            scope=["apps/desktop"],
            acceptance=["Remain in the evolution management panel"],
            risk_level="low",
            max_attempts=1,
            status="proposed",
        )
        manager = SimpleNamespace(
            audit=SimpleNamespace(list_for_task=lambda *_args, **_kwargs: []),
            task_metadata=lambda _task_id: {"origin": "manual"},
        )

        self.assertIsNone(evolution_task_timeline_item(manager, task))

    def test_live_event_is_visible_before_audit_append_finishes(self):
        task = EvolutionTask(
            task_id="evolve-live",
            problem="Stream the current action immediately",
            reproduction_steps=[],
            scope=["apps/desktop"],
            acceptance=["The live event appears without polling"],
            risk_level="low",
            max_attempts=1,
            status="preparing",
            created_at_millis=1_000,
            updated_at_millis=2_000,
        )
        manager = SimpleNamespace(
            audit=SimpleNamespace(list_for_task=lambda *_args, **_kwargs: []),
            task_metadata=lambda _task_id: {"origin": "manual"},
        )

        item = evolution_task_timeline_item(
            manager,
            task,
            live_event={
                "event": "start_requested",
                "metadata": {},
                "timestamp_millis": 2_000,
            },
        )

        self.assertEqual("running", item["status"])
        self.assertEqual("Self-evolution task started", item["events"][0]["title"])
        self.assertEqual("running", item["events"][0]["status"])


if __name__ == "__main__":
    unittest.main()
