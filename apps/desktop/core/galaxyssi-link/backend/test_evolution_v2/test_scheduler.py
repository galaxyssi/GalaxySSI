from __future__ import annotations

import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from evolution_v2.models import EvolutionProposal
from evolution_v2.scheduler import EvolutionScheduler, _normalized_config


class FakeAudit:
    def __init__(self) -> None:
        self.events: list[tuple[str, dict]] = []

    def append(self, event: str, **values) -> None:
        self.events.append((event, values))


class FakeStore:
    def __init__(self, root: Path) -> None:
        self.paths = {"scheduler": root / "state" / "scheduler"}
        self.proposals: list[EvolutionProposal] = []

    def list_proposals(self, _limit: int):
        return list(self.proposals)

    def save_proposal(self, proposal: EvolutionProposal) -> None:
        if proposal not in self.proposals:
            self.proposals.append(proposal)


class FakeRadar:
    def __init__(self) -> None:
        self.calls = 0

    def run(self, **_values):
        self.calls += 1
        return SimpleNamespace(run_id="radar-run", items=[])

    def proposals(self, _run):
        return []


class FakeIssueScanner:
    def __init__(self) -> None:
        self.calls = 0

    def scan(self):
        self.calls += 1
        return []


class FakeManager:
    def __init__(self, root: Path) -> None:
        self.source_root = root
        self.v2_store = FakeStore(root)
        self.audit = FakeAudit()
        self.radar = FakeRadar()
        self.issue_scanner = FakeIssueScanner()
        self.tasks: dict[str, SimpleNamespace] = {}
        self.published: list[str] = []

    def create_from_proposal(self, proposal, **values):
        task_id = f"task-{len(self.tasks) + 1}"
        task = SimpleNamespace(
            task_id=task_id,
            status="running" if values.get("start") else "pending",
            approval_hash="",
            pull_request_url="",
        )
        proposal.task_id = task_id
        proposal.status = "materialized"
        self.v2_store.save_proposal(proposal)
        self.tasks[task_id] = task
        return task

    def require(self, task_id: str):
        return self.tasks[task_id]

    def publish(self, task_id: str, _approval_hash: str, **_values):
        task = self.require(task_id)
        task.status = "published"
        task.pull_request_url = f"https://github.com/galaxyssi/GalaxySSI/pull/{len(self.published) + 1}"
        self.published.append(task_id)
        return task


class EvolutionSchedulerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.config_path = self.root / "evolution-scheduler.json"

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def scheduler(self, config: dict | None = None) -> EvolutionScheduler:
        self.config_path.write_text(
            json.dumps(config or {"enabled": False}),
            encoding="utf-8",
        )
        return EvolutionScheduler(
            FakeManager(self.root),
            config_path=self.config_path,
        )

    def test_config_is_bounded_and_invalid_mode_falls_back_to_serial(self) -> None:
        normalized = _normalized_config({
            "evolutions_per_day": 1_000,
            "execution_mode": "shell",
            "max_parallel_evolutions": 50,
        })

        self.assertEqual(96, normalized["evolutions_per_day"])
        self.assertEqual("serial", normalized["execution_mode"])
        self.assertEqual(4, normalized["max_parallel_evolutions"])
        self.assertFalse(normalized["auto_merge"])

    def test_scheduler_is_disabled_until_the_user_enables_it(self) -> None:
        self.config_path.write_text("{}", encoding="utf-8")
        scheduler = EvolutionScheduler(
            FakeManager(self.root),
            config_path=self.config_path,
        )

        scheduler.start()

        self.assertFalse(scheduler.status()["config"]["enabled"])
        self.assertFalse(scheduler.status()["running"])
        self.assertIsNone(scheduler._thread)

    def test_disabled_scheduler_does_not_start_a_background_thread(self) -> None:
        scheduler = self.scheduler({"enabled": False})

        scheduler.start()

        self.assertIsNone(scheduler._thread)
        self.assertFalse(scheduler.status()["running"])

    def test_user_config_is_persisted_without_internal_policy_fields(self) -> None:
        scheduler = self.scheduler()

        with (
            patch.object(scheduler, "start") as start,
            patch.object(scheduler, "wake") as wake,
        ):
            status = scheduler.update_config({
                "enabled": True,
                "evolutions_per_day": 24,
                "execution_mode": "parallel",
                "max_parallel_evolutions": 3,
                "auto_merge": True,
                "auto_publish": False,
            })

        persisted = json.loads(scheduler.settings_path.read_text(encoding="utf-8"))
        self.assertEqual(24, persisted["evolutions_per_day"])
        self.assertEqual("parallel", persisted["execution_mode"])
        self.assertEqual(3, persisted["max_parallel_evolutions"])
        self.assertNotIn("auto_merge", persisted)
        self.assertNotIn("auto_publish", persisted)
        self.assertFalse(status["config"]["auto_merge"])
        self.assertTrue(status["config"]["auto_publish"])
        start.assert_called_once()
        wake.assert_called_once()

    def test_serial_waits_and_parallel_respects_the_configured_capacity(self) -> None:
        scheduler = self.scheduler({
            "enabled": True,
            "execution_mode": "serial",
            "max_parallel_evolutions": 3,
        })
        state = {"active_evolutions": [{"task_id": "one"}]}

        self.assertEqual(0, scheduler._available_capacity(state))

        scheduler.config["execution_mode"] = "parallel"
        self.assertEqual(2, scheduler._available_capacity(state))
        state["active_evolutions"].extend([
            {"task_id": "two"},
            {"task_id": "three"},
        ])
        self.assertEqual(0, scheduler._available_capacity(state))

    def test_frequency_maps_to_an_even_daily_interval(self) -> None:
        scheduler = self.scheduler({
            "enabled": True,
            "evolutions_per_day": 24,
        })

        self.assertEqual(60 * 60 * 1_000, scheduler._evolution_interval_millis())

    def test_due_run_starts_a_proposal_and_publishes_only_after_validation(self) -> None:
        scheduler = self.scheduler({"enabled": True})
        proposal = EvolutionProposal(
            proposal_id="proposal-one",
            title="Improve scheduler",
            problem="Improve the persistent evolution scheduler.",
            scope=["apps/desktop"],
            acceptance=["The scheduler remains bounded."],
        )
        scheduler.manager.v2_store.proposals.append(proposal)

        started = scheduler.run_due(evolution_only=True)

        self.assertEqual("started", started["evolution"]["status"])
        self.assertEqual(0, scheduler.manager.radar.calls)
        self.assertEqual(0, scheduler.manager.issue_scanner.calls)
        task = scheduler.manager.require(started["evolution"]["task_id"])
        self.assertEqual([], scheduler.manager.published)

        task.status = "waiting_approval"
        task.approval_hash = "verified-candidate"
        reconciled = scheduler.run_due()

        self.assertEqual([task.task_id], scheduler.manager.published)
        self.assertEqual(task.pull_request_url, reconciled["published"][0]["pull_request_url"])
        self.assertEqual("published", scheduler.status()["state"]["history"][0]["status"])

    def test_serial_run_is_deferred_while_the_previous_task_is_active(self) -> None:
        scheduler = self.scheduler({
            "enabled": True,
            "execution_mode": "serial",
        })
        task = SimpleNamespace(
            task_id="task-active",
            status="running",
            approval_hash="",
            pull_request_url="",
        )
        scheduler.manager.tasks[task.task_id] = task
        scheduler._save_state({
            "active_evolutions": [{
                "task_id": task.task_id,
                "status": "running",
            }],
        })

        result = scheduler.run_due(force=True)

        self.assertEqual("deferred", result["evolution"]["status"])
        self.assertTrue(scheduler.status()["computed"]["pending"])


if __name__ == "__main__":
    unittest.main()
