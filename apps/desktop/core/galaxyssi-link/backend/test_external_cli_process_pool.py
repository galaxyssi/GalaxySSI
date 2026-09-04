import os
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

from external_cli_process_pool import (
    CLI_PROTOCOL,
    ExternalCliPoolTimeout,
    ExternalCliProcessExited,
    ExternalCliProcessPool,
    PersistentCliRequest,
)


class ExternalCliProcessPoolTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.script = self.root / "persistent_agent.py"
        self.startup_log = self.root / "starts.log"
        self.script.write_text(
            "import json, os, sys, time\n"
            "log = os.environ.get('STARTUP_LOG', '')\n"
            "if log:\n"
            "    with open(log, 'a', encoding='utf-8') as handle:\n"
            "        handle.write(str(os.getpid()) + '\\n')\n"
            "for line in sys.stdin:\n"
            "    try:\n"
            "        request = json.loads(line)\n"
            "    except Exception:\n"
            "        continue\n"
            "    request_id = str(request.get('id') or '')\n"
            "    method = str(request.get('method') or '')\n"
            "    if method == 'agent/shutdown':\n"
            "        print(json.dumps({'id': request_id, 'result': {'stopped': True}}), flush=True)\n"
            "        break\n"
            "    params = request.get('params') or {}\n"
            "    prompt = str(params.get('prompt') or '')\n"
            "    if prompt.startswith('sleep:'):\n"
            "        time.sleep(float(prompt.split(':', 1)[1]))\n"
            "    if prompt == 'crash':\n"
            "        os._exit(7)\n"
            "    if prompt == 'stream':\n"
            "        print(json.dumps({\n"
            "            'protocol': 'galaxyssi.agent-cli/1.0',\n"
            "            'method': 'agent/output_delta',\n"
            "            'params': {\n"
            "                'task_id': str(params.get('task_id') or ''),\n"
            "                'sequence': 1,\n"
            "                'text': 'visible partial',\n"
            "                'user_visible': True,\n"
            "            },\n"
            "        }), flush=True)\n"
            "    print(json.dumps({\n"
            "        'protocol': 'galaxyssi.agent-cli/1.0',\n"
            "        'id': request_id,\n"
            "        'result': {\n"
            "            'reply': f'{os.getpid()}:{prompt}',\n"
            "            'capabilities': params.get('client_capabilities', []),\n"
            "        },\n"
            "    }), flush=True)\n",
            encoding="utf-8",
        )
        self.pools: list[ExternalCliProcessPool] = []

    def tearDown(self):
        for pool in self.pools:
            pool.shutdown()
        self.temporary.cleanup()

    def pool(self, **kwargs) -> ExternalCliProcessPool:
        pool = ExternalCliProcessPool(start_janitor=False, **kwargs)
        self.pools.append(pool)
        return pool

    def command(self) -> list[str]:
        return [sys.executable, str(self.script)]

    def env(self) -> dict[str, str]:
        return {**os.environ, "STARTUP_LOG": str(self.startup_log)}

    @staticmethod
    def request(
        prompt: str,
        task_id: str,
        *,
        timeout_seconds: float = 2,
        priority: str = "foreground",
    ) -> PersistentCliRequest:
        return PersistentCliRequest(
            agent_id="custom-agent",
            prompt=prompt,
            task_id=task_id,
            conversation_id="conversation-1",
            working_directory="C:/workspace",
            timeout_seconds=timeout_seconds,
            priority=priority,
        )

    def execute(
        self,
        pool: ExternalCliProcessPool,
        prompt: str,
        task_id: str,
        *,
        timeout_seconds: float = 2,
        process_limit: int | None = None,
        priority: str = "foreground",
    ):
        return pool.execute(
            self.request(
                prompt,
                task_id,
                timeout_seconds=timeout_seconds,
                priority=priority,
            ),
            command=self.command(),
            env=self.env(),
            cwd=self.root,
            process_limit=process_limit,
        )

    def test_process_is_reused_across_requests(self):
        pool = self.pool()

        first = self.execute(pool, "one", "task-1")
        second = self.execute(pool, "two", "task-2")

        self.assertEqual(first.pid, second.pid)
        self.assertFalse(first.reused)
        self.assertTrue(second.reused)
        self.assertEqual(2, second.request_count)
        self.assertEqual(1, len(self.startup_log.read_text(encoding="utf-8").splitlines()))
        self.assertEqual(1, pool.health()["metrics"]["warm_reuses"])

    def test_user_visible_notification_and_capabilities_are_negotiated(self):
        pool = self.pool()
        events = []
        request = PersistentCliRequest(
            agent_id="custom-agent",
            prompt="stream",
            task_id="task-stream",
            conversation_id="conversation-1",
            working_directory="C:/workspace",
            timeout_seconds=2,
            on_event=events.append,
        )

        result = pool.execute(
            request,
            command=self.command(),
            env=self.env(),
            cwd=self.root,
        )

        self.assertEqual(1, len(events))
        self.assertEqual("agent/output_delta", events[0]["method"])
        self.assertEqual("visible partial", events[0]["text"])
        self.assertIn("user_visible_output_delta_v1", result.capabilities)

    def test_prewarmed_process_serves_first_request_without_restart(self):
        pool = self.pool()

        warmed = pool.prewarm(
            "custom-agent",
            command=self.command(),
            env=self.env(),
            cwd=self.root,
        )
        result = self.execute(pool, "hello", "task-1")

        self.assertEqual(1, warmed)
        self.assertTrue(result.reused)
        self.assertEqual(1, pool.health()["process_count"])

    def test_parallel_requests_use_bounded_workers(self):
        pool = self.pool(max_processes=2, max_processes_per_agent=2)
        results = []

        threads = [
            threading.Thread(
                target=lambda index=index: results.append(
                    self.execute(pool, "sleep:0.2", f"task-{index}")
                )
            )
            for index in range(2)
        ]
        for thread in threads:
            thread.start()
        deadline = time.time() + 2
        while time.time() < deadline and pool.health()["busy_count"] < 2:
            time.sleep(0.01)
        self.assertEqual(2, pool.health()["busy_count"])
        for thread in threads:
            thread.join(timeout=3)

        self.assertEqual(2, len(results))
        self.assertEqual(2, len({result.pid for result in results}))
        self.assertEqual(2, pool.health()["process_count"])

    def test_agent_process_limit_serializes_parallel_requests(self):
        pool = self.pool(max_processes=4, max_processes_per_agent=4)
        results = []

        threads = [
            threading.Thread(
                target=lambda index=index: results.append(
                    self.execute(
                        pool,
                        "sleep:0.15",
                        f"task-{index}",
                        process_limit=1,
                    )
                )
            )
            for index in range(2)
        ]
        for thread in threads:
            thread.start()
        deadline = time.time() + 2
        while time.time() < deadline and pool.health()["busy_count"] < 1:
            time.sleep(0.01)
        self.assertEqual(1, pool.health()["busy_count"])
        self.assertEqual(1, pool.health()["process_count"])
        for thread in threads:
            thread.join(timeout=3)

        self.assertEqual(2, len(results))
        self.assertEqual(1, len({result.pid for result in results}))
        self.assertEqual(1, pool.health()["process_count"])

    def test_foreground_request_bursts_past_busy_background_process(self):
        pool = self.pool(max_processes=1, max_processes_per_agent=1)
        background_result = []
        foreground_result = []
        background = threading.Thread(
            target=lambda: background_result.append(
                self.execute(
                    pool,
                    "sleep:0.4",
                    "background-task",
                    process_limit=1,
                    priority="background",
                )
            )
        )
        background.start()
        deadline = time.time() + 2
        while time.time() < deadline and pool.health()["busy_count"] < 1:
            time.sleep(0.01)
        self.assertEqual(1, pool.health()["busy_count"])

        foreground = threading.Thread(
            target=lambda: foreground_result.append(
                self.execute(
                    pool,
                    "foreground",
                    "foreground-task",
                    process_limit=1,
                    priority="foreground",
                )
            )
        )
        foreground.start()
        foreground.join(timeout=0.25)

        self.assertFalse(foreground.is_alive())
        self.assertEqual(1, len(foreground_result))
        self.assertTrue(background.is_alive())
        self.assertEqual(1, pool.health()["metrics"]["foreground_bursts"])

        background.join(timeout=2)
        self.assertEqual(1, len(background_result))

    def test_process_rotates_after_request_budget(self):
        pool = self.pool(max_requests_per_process=1)

        first = self.execute(pool, "one", "task-1")
        second = self.execute(pool, "two", "task-2")

        self.assertNotEqual(first.pid, second.pid)
        self.assertEqual(2, pool.health()["metrics"]["process_starts"])

    def test_idle_process_is_released_after_delay(self):
        clock = [100.0]
        pool = self.pool(idle_timeout_seconds=5, now=lambda: clock[0])
        self.execute(pool, "one", "task-1")
        clock[0] += 6

        released = pool.reap_idle()

        self.assertEqual(1, released)
        self.assertEqual(0, pool.health()["process_count"])

    def test_keep_alive_target_survives_idle_timeout(self):
        clock = [100.0]
        pool = self.pool(idle_timeout_seconds=5, now=lambda: clock[0])
        pool.prewarm(
            "custom-agent",
            command=self.command(),
            env=self.env(),
            cwd=self.root,
        )
        first_pid = pool.health()["workers"][0]["pid"]
        clock[0] += 60

        maintained = pool.maintain()

        self.assertEqual(0, maintained["released"])
        self.assertEqual(0, maintained["started"])
        self.assertEqual(first_pid, pool.health()["workers"][0]["pid"])
        self.assertEqual(1, pool.health()["warm_targets"][0]["ready_count"])

    def test_keep_alive_target_restarts_a_crashed_process(self):
        pool = self.pool()
        pool.prewarm(
            "custom-agent",
            command=self.command(),
            env=self.env(),
            cwd=self.root,
        )
        first_worker = next(iter(pool._workers.values()))
        first_pid = first_worker.pid
        first_worker.process.kill()
        first_worker.process.wait(timeout=2)

        maintained = pool.maintain()
        health = pool.health()

        self.assertEqual(1, maintained["released"])
        self.assertEqual(1, maintained["started"])
        self.assertNotEqual(first_pid, health["workers"][0]["pid"])
        self.assertEqual(1, health["metrics"]["prewarm_starts"])
        self.assertEqual(1, health["metrics"]["keepalive_restarts"])

    def test_optional_prewarm_without_keep_alive_is_released(self):
        clock = [100.0]
        pool = self.pool(idle_timeout_seconds=5, now=lambda: clock[0])
        pool.prewarm(
            "custom-agent",
            command=self.command(),
            env=self.env(),
            cwd=self.root,
            keep_alive=False,
        )
        clock[0] += 6

        maintained = pool.maintain()

        self.assertEqual(1, maintained["released"])
        self.assertEqual(0, maintained["started"])
        self.assertEqual([], pool.health()["warm_targets"])

    def test_timeout_kills_only_the_affected_worker(self):
        pool = self.pool()

        with self.assertRaises(ExternalCliPoolTimeout):
            self.execute(
                pool,
                "sleep:2",
                "task-timeout",
                timeout_seconds=0.1,
            )

        self.assertEqual(0, pool.health()["process_count"])
        self.assertEqual(1, pool.health()["metrics"]["failures"])

    def test_cancel_kills_active_worker(self):
        pool = self.pool()
        failures = []

        thread = threading.Thread(
            target=lambda: self._capture_failure(
                failures,
                lambda: self.execute(pool, "sleep:5", "task-cancel", timeout_seconds=10),
            )
        )
        thread.start()
        deadline = time.time() + 2
        while time.time() < deadline and pool.health()["busy_count"] < 1:
            time.sleep(0.01)

        self.assertTrue(pool.cancel("task-cancel"))
        thread.join(timeout=3)

        self.assertTrue(failures)
        self.assertEqual(0, pool.health()["process_count"])
        self.assertEqual(1, pool.health()["metrics"]["cancellations"])

    def test_worker_reservation_is_immediately_cancellable(self):
        pool = self.pool()
        failures = []
        acquired = threading.Event()
        release_execute = threading.Event()
        original_acquire = pool._acquire

        def paused_acquire(*args, **kwargs):
            result = original_acquire(*args, **kwargs)
            acquired.set()
            release_execute.wait(timeout=2)
            return result

        pool._acquire = paused_acquire
        thread = threading.Thread(
            target=lambda: self._capture_failure(
                failures,
                lambda: self.execute(pool, "sleep:5", "task-reserved", timeout_seconds=10),
            )
        )
        thread.start()
        self.assertTrue(acquired.wait(timeout=2))

        try:
            self.assertEqual(1, pool.health()["busy_count"])
            self.assertTrue(pool.cancel("task-reserved"))
        finally:
            release_execute.set()
            thread.join(timeout=3)

        self.assertTrue(failures)
        self.assertFalse(thread.is_alive())
        self.assertEqual(0, pool.health()["process_count"])

    def test_crash_after_send_is_not_automatically_retried(self):
        pool = self.pool()

        with self.assertRaises(ExternalCliProcessExited) as raised:
            self.execute(pool, "crash", "task-crash")

        self.assertTrue(raised.exception.request_sent)
        self.assertEqual(1, len(self.startup_log.read_text(encoding="utf-8").splitlines()))
        self.assertEqual(0, pool.health()["process_count"])

    def test_health_does_not_expose_command_or_environment(self):
        pool = self.pool()
        self.execute(pool, "hello", "task-1")

        serialized = str(pool.health())

        self.assertIn(CLI_PROTOCOL, serialized)
        self.assertNotIn(str(self.script), serialized)
        self.assertNotIn("STARTUP_LOG", serialized)

    @staticmethod
    def _capture_failure(target: list[Exception], callback) -> None:
        try:
            callback()
        except Exception as exc:
            target.append(exc)


if __name__ == "__main__":
    unittest.main()
