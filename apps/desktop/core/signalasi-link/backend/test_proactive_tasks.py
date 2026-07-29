import hashlib
import hmac
import json
import tempfile
import threading
import time
import unittest
from dataclasses import replace
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from proactive_tasks import (
    CronExpression,
    ProactiveAction,
    ProactiveTaskError,
    ProactiveTaskRuntime,
    ProactiveTrigger,
)


class CronExpressionTests(unittest.TestCase):
    def test_next_occurrence_respects_time_zone(self):
        cron = CronExpression.parse("30 9 * * mon-fri")
        zone = ZoneInfo("Asia/Shanghai")
        friday = datetime(2026, 7, 24, 9, 31, tzinfo=zone)

        result = datetime.fromtimestamp(
            cron.next_after(int(friday.timestamp() * 1000), "Asia/Shanghai") / 1000,
            zone,
        )

        self.assertEqual(datetime(2026, 7, 27, 9, 30, tzinfo=zone), result)

    def test_day_and_weekday_use_vixie_or_semantics(self):
        cron = CronExpression.parse("0 12 1 * mon")
        zone = ZoneInfo("UTC")

        monday_not_first = datetime(2026, 7, 6, 12, 0, tzinfo=zone)
        first_not_monday = datetime(2026, 8, 1, 12, 0, tzinfo=zone)

        self.assertTrue(cron.matches(monday_not_first))
        self.assertTrue(cron.matches(first_not_monday))

    def test_steps_lists_and_sunday_alias(self):
        cron = CronExpression.parse("*/15 8,12 * jan,mar 0,7")
        self.assertTrue(cron.matches(datetime(2026, 3, 1, 12, 45, tzinfo=ZoneInfo("UTC"))))
        self.assertFalse(cron.matches(datetime(2026, 3, 2, 12, 45, tzinfo=ZoneInfo("UTC"))))

    def test_invalid_expression_is_rejected(self):
        with self.assertRaises(ProactiveTaskError):
            CronExpression.parse("60 * * * *")


class ProactiveTaskRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.now = [1_800_000_000_000]
        self.calls = []

    def tearDown(self):
        self.temporary.cleanup()

    def runtime(self, dispatcher=None, constraint_probe=None):
        runtime = ProactiveTaskRuntime(
            Path(self.temporary.name),
            dispatcher or self._dispatcher,
            now_millis=lambda: self.now[0],
            poll_seconds=60,
            max_workers=4,
            constraint_probe=constraint_probe,
            constraint_recheck_seconds=1,
        )
        return runtime

    def _dispatcher(self, task, run):
        self.calls.append((task.task_id, run.run_id, run.cause))
        return {"reply": task.action.prompt, "goal_completed": False}

    def create_interval(self, runtime, **policy):
        return runtime.create(
            name="Heartbeat",
            trigger={"kind": "interval", "interval_seconds": 60},
            action={"kind": "agent", "target_id": "codex", "prompt": "Check status"},
            policy={"retry_backoff_seconds": 1, **policy},
            task_id="heartbeat",
        )

    def wait_terminal(self, runtime, run_id, timeout=3):
        deadline = time.time() + timeout
        while time.time() < deadline:
            run = runtime.store.run(run_id)
            if run and run.status in {"completed", "failed", "cancelled", "skipped"}:
                return run
            time.sleep(0.02)
        self.fail(f"Run {run_id} did not complete")

    def wait_status(self, runtime, run_id, status, timeout=3):
        deadline = time.time() + timeout
        while time.time() < deadline:
            run = runtime.store.run(run_id)
            if run and run.status == status:
                return run
            time.sleep(0.02)
        self.fail(f"Run {run_id} did not reach {status}")

    def test_task_round_trips_through_sqlite(self):
        runtime = self.runtime()
        created = self.create_interval(runtime)

        stored = runtime.require_task(created["task_id"])

        self.assertEqual("interval", stored.trigger.kind)
        self.assertEqual("agent", stored.action.kind)
        self.assertEqual(60, stored.trigger.interval_seconds)
        runtime.stop(wait_for_workers=True)

    def test_fire_once_collapses_missed_interval_runs(self):
        runtime = self.runtime()
        created = self.create_interval(runtime, misfire="fire_once")
        task = runtime.require_task(created["task_id"])
        runtime.store.upsert_task(
            replace(task, next_run_at_millis=self.now[0] - 10 * 60_000)
        )

        runs = runtime.tick()
        result = self.wait_terminal(runtime, runs[0].run_id)

        self.assertEqual(1, len(runs))
        self.assertEqual("completed", result.status)
        self.assertGreater(runtime.require_task(task.task_id).next_run_at_millis, self.now[0])
        runtime.stop(wait_for_workers=True)

    def test_catch_up_is_bounded_to_policy_limit(self):
        runtime = self.runtime()
        created = self.create_interval(runtime, misfire="catch_up", catch_up_limit=3)
        task = runtime.require_task(created["task_id"])
        runtime.store.upsert_task(
            replace(task, next_run_at_millis=self.now[0] - 20 * 60_000)
        )

        runs = runtime.tick()
        for run in runs:
            self.wait_terminal(runtime, run.run_id)

        self.assertEqual(3, len(runs))
        runtime.stop(wait_for_workers=True)

    def test_webhook_requires_signature_and_rejects_replay(self):
        runtime = self.runtime()
        created = runtime.create(
            name="Build hook",
            trigger={
                "kind": "webhook",
                "event_filter": {"event.type": "build.completed"},
            },
            action={"kind": "agent", "target_id": "desktop", "prompt": "Review build"},
            task_id="build-hook",
        )
        body = json.dumps({"event": {"type": "build.completed"}}).encode()
        timestamp = str(self.now[0] // 1000)
        nonce = "nonce-123456"
        digest = hashlib.sha256(body).hexdigest()
        signature = hmac.new(
            created["webhook_secret"].encode(),
            f"{timestamp}.{nonce}.{digest}".encode(),
            hashlib.sha256,
        ).hexdigest()

        run = runtime.handle_webhook(
            "build-hook",
            body,
            timestamp=timestamp,
            nonce=nonce,
            signature=f"sha256={signature}",
        )
        result = self.wait_terminal(runtime, run.run_id)

        self.assertEqual("completed", result.status)
        with self.assertRaisesRegex(ProactiveTaskError, "already been used"):
            runtime.handle_webhook(
                "build-hook",
                body,
                timestamp=timestamp,
                nonce=nonce,
                signature=signature,
            )
        runtime.stop(wait_for_workers=True)

    def test_webhook_filter_rejects_unrelated_events(self):
        runtime = self.runtime()
        created = runtime.create(
            name="Release hook",
            trigger={"kind": "webhook", "event_filter": {"event": "release"}},
            action={"kind": "agent", "target_id": "desktop", "prompt": "Review release"},
            task_id="release-hook",
        )
        body = b'{"event":"push"}'
        timestamp = str(self.now[0] // 1000)
        nonce = "nonce-654321"
        digest = hashlib.sha256(body).hexdigest()
        signature = hmac.new(
            created["webhook_secret"].encode(),
            f"{timestamp}.{nonce}.{digest}".encode(),
            hashlib.sha256,
        ).hexdigest()

        with self.assertRaisesRegex(ProactiveTaskError, "does not match"):
            runtime.handle_webhook(
                "release-hook",
                body,
                timestamp=timestamp,
                nonce=nonce,
                signature=signature,
            )
        runtime.stop(wait_for_workers=True)

    def test_retry_records_structured_events(self):
        attempts = []

        def dispatcher(task, run):
            attempts.append(run.attempt)
            if len(attempts) == 1:
                raise ProactiveTaskError("temporary", "Temporary failure", retryable=True)
            return {"reply": "Recovered"}

        runtime = self.runtime(dispatcher)
        created = self.create_interval(runtime, max_attempts=2)
        run = runtime.trigger_now(created["task_id"])
        result = self.wait_terminal(runtime, run.run_id, timeout=4)
        events = runtime.store.events(run.run_id)

        self.assertEqual("completed", result.status)
        self.assertEqual([1, 2], attempts)
        self.assertIn("observe", [event["kind"] for event in events])
        runtime.stop(wait_for_workers=True)

    def test_dispatcher_can_record_durable_phase_progress(self):
        started = threading.Event()
        release = threading.Event()

        def dispatcher(_task, _run):
            started.set()
            release.wait(timeout=2)
            return {"reply": "Done"}

        runtime = self.runtime(dispatcher)
        created = self.create_interval(runtime)
        run = runtime.trigger_now(created["task_id"])
        self.assertTrue(started.wait(timeout=2))

        self.assertTrue(
            runtime.record_progress(
                run.run_id,
                "headless_plan",
                "Coordinator prepared a plan",
                {"phase": "plan"},
            )
        )
        release.set()
        self.wait_terminal(runtime, run.run_id)
        events = runtime.store.events(run.run_id)

        progress = next(
            event for event in events if event["kind"] == "headless_plan"
        )
        self.assertEqual("Coordinator prepared a plan", progress["detail"])
        self.assertEqual("plan", progress["metadata"]["phase"])
        runtime.stop(wait_for_workers=True)

    def test_cancelled_run_cannot_be_overwritten_by_late_agent_result(self):
        started = threading.Event()
        release = threading.Event()

        def dispatcher(_task, _run):
            started.set()
            release.wait(timeout=2)
            return {"reply": "Late result"}

        runtime = self.runtime(dispatcher)
        created = self.create_interval(runtime)
        run = runtime.trigger_now(created["task_id"])
        self.assertTrue(started.wait(timeout=2))

        self.assertTrue(runtime.cancel_run(run.run_id))
        release.set()
        result = self.wait_terminal(runtime, run.run_id)
        time.sleep(0.05)

        self.assertEqual("cancelled", result.status)
        self.assertEqual("cancelled", runtime.store.run(run.run_id).status)
        runtime.stop(wait_for_workers=True)

    def test_cancelled_run_cannot_be_overwritten_by_late_agent_failure(self):
        started = threading.Event()
        release = threading.Event()

        def dispatcher(_task, _run):
            started.set()
            release.wait(timeout=2)
            raise RuntimeError("Late failure")

        runtime = self.runtime(dispatcher)
        created = self.create_interval(runtime)
        run = runtime.trigger_now(created["task_id"])
        self.assertTrue(started.wait(timeout=2))

        self.assertTrue(runtime.cancel_run(run.run_id))
        release.set()
        result = self.wait_terminal(runtime, run.run_id)
        time.sleep(0.05)

        self.assertEqual("cancelled", result.status)
        self.assertEqual("cancelled", runtime.store.run(run.run_id).status)
        runtime.stop(wait_for_workers=True)

    def test_agent_action_requires_a_goal(self):
        with self.assertRaisesRegex(ProactiveTaskError, "require a goal"):
            ProactiveAction.parse(
                {
                    "kind": "agent",
                    "target_id": "codex",
                    "prompt": "",
                }
            )

    def test_constraints_wait_without_consuming_attempt_and_resume(self):
        allowed = [False]
        runtime = self.runtime(
            constraint_probe=lambda _policy: (
                allowed[0],
                "" if allowed[0] else "Waiting for external power",
            )
        )
        created = self.create_interval(runtime, requires_charging=True)
        run = runtime.trigger_now(created["task_id"])
        waiting = self.wait_status(runtime, run.run_id, "waiting")

        self.assertEqual(1, waiting.attempt)
        self.assertEqual([], self.calls)

        allowed[0] = True
        self.now[0] += 1_001
        runtime._resume_waiting_constraints()
        result = self.wait_terminal(runtime, run.run_id)

        self.assertEqual("completed", result.status)
        self.assertEqual(1, result.attempt)
        self.assertEqual(1, len(self.calls))
        runtime.stop(wait_for_workers=True)

    def test_subagent_team_requires_exactly_one_lead(self):
        with self.assertRaisesRegex(ProactiveTaskError, "exactly one lead"):
            ProactiveAction.parse(
                {
                    "kind": "subagent_team",
                    "team": [
                        {"agent_id": "codex", "role": "observer"},
                        {"agent_id": "hermes", "role": "verifier"},
                    ],
                }
            )

    def test_coordinator_specialist_team_requires_unique_bounded_roles(self):
        action = ProactiveAction.parse(
            {
                "kind": "subagent_team",
                "prompt": "Prepare the release",
                "team": [
                    {"agent_id": "codex", "role": "coordinator"},
                    {
                        "agent_id": "claude",
                        "role": "specialist",
                        "instructions": "Review the implementation",
                    },
                    {"agent_id": "hermes", "role": "verifier"},
                ],
            }
        )

        self.assertEqual("coordinator", action.team[0]["role"])
        self.assertEqual("specialist", action.team[1]["role"])
        with self.assertRaisesRegex(ProactiveTaskError, "at least one specialist"):
            ProactiveAction.parse(
                {
                    "kind": "subagent_team",
                    "prompt": "Prepare the release",
                    "team": [
                        {"agent_id": "codex", "role": "coordinator"},
                        {"agent_id": "hermes", "role": "verifier"},
                    ],
                }
            )
        with self.assertRaisesRegex(ProactiveTaskError, "repeats Agent"):
            ProactiveAction.parse(
                {
                    "kind": "subagent_team",
                    "prompt": "Prepare the release",
                    "team": [
                        {"agent_id": "codex", "role": "coordinator"},
                        {"agent_id": "codex", "role": "specialist"},
                    ],
                }
            )

    def test_headless_swarm_validates_workflow_team_scope_and_checks(self):
        action = ProactiveAction.parse(
            {
                "kind": "headless_swarm",
                "target_id": "test_repair",
                "prompt": "Repair the failing tests",
                "arguments": {
                    "repository_root": str(Path("test-repository").resolve()),
                    "scope": ["src"],
                    "checks": [["python", "-m", "unittest"]],
                },
                "team": [
                    {"agent_id": "codex", "role": "coordinator"},
                    {"agent_id": "hermes", "role": "specialist"},
                ],
            }
        )

        self.assertEqual("headless_swarm", action.kind)
        self.assertEqual("test_repair", action.target_id)
        with self.assertRaisesRegex(ProactiveTaskError, "one coordinator"):
            ProactiveAction.parse(
                {
                    "kind": "headless_swarm",
                    "target_id": "pr_review",
                    "prompt": "Review the candidate",
                    "arguments": {
                        "repository_root": str(Path("test-repository").resolve()),
                    },
                    "team": [
                        {"agent_id": "codex", "role": "lead"},
                        {"agent_id": "hermes", "role": "specialist"},
                    ],
                }
            )

    def test_goal_checkpoint_requires_goal_id(self):
        with self.assertRaises(ProactiveTaskError):
            ProactiveTrigger.parse(
                {
                    "kind": "goal_checkpoint",
                    "interval_seconds": 300,
                    "goal_id": "",
                }
            )


if __name__ == "__main__":
    unittest.main()
