from dataclasses import asdict, replace
import json
from pathlib import Path
import tempfile
import threading
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from agent_latency import AgentLatencyTracer, AgentTimingPoint, opaque_id, summarize, record_task
from agent_latency_hooks import execution_event, lifecycle, trace_stage
from agent_latency_store import AgentTimingJournal
from voice_latency import VoiceTraceEvents


class MemorySink:
    def __init__(self):
        self.points = []

    def append(self, point):
        self.points.append(point)

    def snapshot(self):
        return list(self.points)

    def health(self):
        return {"loading": False, "dropped_events": 0, "write_failures": 0}


class AgentLatencyTest(unittest.TestCase):
    def point(self, stage, ms, task="task-1", clock="a" * 32, operation="", outcome=""):
        return AgentTimingPoint(opaque_id(task), clock, stage, ms * 1_000_000,
                                1_000, opaque_id(operation) if operation else "", outcome=outcome)

    def test_exact_nearest_rank_percentiles(self):
        points = []
        for index in range(1, 101):
            points += [self.point("desktop_agent_started", 0, str(index)),
                       self.point("desktop_first_output", index, str(index))]
        metric = summarize(points)["metrics"]["desktop_first_output_ms"]
        self.assertEqual((100, 50.0, 95.0, 99.0), tuple(metric[k] for k in ("count", "p50_ms", "p95_ms", "p99_ms")))

    def test_no_samples_are_null_not_zero(self):
        self.assertIsNone(summarize([])["metrics"]["desktop_queue_ms"]["p95_ms"])

    def test_clock_domains_never_join_even_when_wall_times_match(self):
        result = summarize([self.point("desktop_agent_started", 0),
                            self.point("desktop_first_output", 1, clock="b" * 32)])
        metric = result["metrics"]["desktop_first_output_ms"]
        self.assertEqual((0, 1), (metric["count"], metric["incomplete"]))
        self.assertFalse(result["cross_device_clock_subtraction"])

    def test_tasks_do_not_join(self):
        metric = summarize([self.point("desktop_agent_started", 1, "one"),
                            self.point("desktop_first_output", 9, "two")])["metrics"]["desktop_first_output_ms"]
        self.assertEqual(0, metric["count"])

    def test_concurrent_tool_spans_use_operation_ids(self):
        points = [self.point("desktop_tool_started", 0, operation="a"),
                  self.point("desktop_tool_started", 100, operation="b"),
                  self.point("desktop_tool_completed", 120, operation="b"),
                  self.point("desktop_tool_completed", 300, operation="a")]
        metric = summarize(points)["metrics"]["desktop_tool_ms"]
        self.assertEqual((2, 20, 300), (metric["count"], metric["p50_ms"], metric["p95_ms"]))

    def test_duplicate_and_out_of_order_events_keep_first_valid_result(self):
        start = self.point("desktop_agent_started", 10)
        end = self.point("desktop_first_output", 20)
        metric = summarize([end, start, start, end, self.point("desktop_first_output", 5)])[
            "metrics"]["desktop_first_output_ms"]
        self.assertEqual((1, 10), (metric["count"], metric["p95_ms"]))

    def test_failed_cancelled_and_timeout_are_not_fast_success(self):
        for outcome in ("failed", "cancelled", "timed_out"):
            with self.subTest(outcome=outcome):
                metric = summarize([self.point("desktop_agent_started", 0),
                                    self.point("desktop_task_completed", 1, outcome=outcome)])[
                    "metrics"]["desktop_execution_ms"]
                self.assertEqual((0, 1, None), (metric["count"], metric["unsuccessful"], metric["p95_ms"]))

    def test_wall_clock_adjustments_do_not_change_duration(self):
        points = [self.point("desktop_agent_started", 100),
                  replace(self.point("desktop_first_output", 200), wall_clock_ms=0)]
        self.assertEqual(100, summarize(points)["metrics"]["desktop_first_output_ms"]["p50_ms"])

    def test_privacy_and_once(self):
        sink = MemorySink()
        tracer = AgentLatencyTracer(sink, monotonic_ns=lambda: 1000)
        for _ in range(100):
            tracer.record("secret-task", "desktop_tool_started", operation_id="private-path",
                          provider="a prompt with spaces", once=True)
        self.assertEqual(1, len(sink.points))
        raw = json.dumps(asdict(sink.points[0]))
        for secret in ("secret-task", "private-path", "prompt with spaces"):
            self.assertNotIn(secret, raw)
        self.assertEqual("", sink.points[0].provider)

    def test_supplied_time_preserves_earlier_callback_boundary(self):
        sink = MemorySink()
        AgentLatencyTracer(sink, monotonic_ns=lambda: 999).record("task", "desktop_request_received", at_ns=100)
        self.assertEqual(100, sink.points[0].monotonic_ns)

    def test_corrupt_point_validation(self):
        valid = asdict(self.point("desktop_first_output", 1))
        for key, value in (("clock_id", "phone"), ("trace_id", "prompt"), ("stage", "secret"),
                           ("monotonic_ns", True), ("wall_clock_ms", -1), ("outcome", "unknown")):
            with self.subTest(key=key), self.assertRaises((ValueError, TypeError)):
                AgentTimingPoint.decode({**valid, key: value})

    def test_recording_failure_cannot_fail_task(self):
        with patch("agent_latency.tracer", side_effect=OSError("full")):
            record_task("task", "desktop_agent_started")

    def test_export_uses_one_snapshot_for_counts_and_points(self):
        from agent_latency import export_snapshot
        sink = MemorySink()
        tracer = AgentLatencyTracer(sink)
        tracer.record("t", "desktop_agent_started")
        with patch("agent_latency.tracer", return_value=tracer), patch.object(sink, "snapshot", wraps=sink.snapshot) as snapshot:
            result = export_snapshot()
        self.assertEqual(1, snapshot.call_count)
        self.assertEqual(result["event_count"], len(result["events"]))

    def test_submission_can_return_after_first_output(self):
        result = summarize([
            self.point("desktop_model_submit_started", 1),
            self.point("desktop_first_output", 101),
            self.point("desktop_model_submitted", 201),
        ])
        self.assertEqual(100, result["metrics"]["desktop_model_first_output_ms"]["p95_ms"])
        self.assertEqual(200, result["metrics"]["desktop_model_submit_ms"]["p95_ms"])

    def test_lifecycle_and_tool_mapping_omit_all_content(self):
        task = SimpleNamespace(task_id="t", agent_id="codex", delegate_agent_id="")
        with patch("agent_latency_hooks.record_task") as record:
            lifecycle(task, VoiceTraceEvents.AGENT_COMPLETED, {"task_status": "failed"})
            self.assertEqual("failed", record.call_args.kwargs["outcome"])
            execution_event("t", {"kind": "tool", "event_id": "a", "status": "running", "detail": "secret"})
            self.assertEqual("desktop_tool_started", record.call_args.args[1])
            self.assertNotIn("secret", repr(record.call_args))
            execution_event("t", {"kind": "tool", "event_id": "a", "status": "completed"})
            self.assertEqual("a", record.call_args.kwargs["operation_id"])
            previous = record.call_count
            execution_event("t", {"kind": "reasoning", "status": "completed"})
            self.assertEqual(previous, record.call_count)
            trace_stage("t", "codex_turn_submitted")
            self.assertEqual("desktop_model_submitted", record.call_args.args[1])

    def test_journal_reopens_without_reloading_on_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "timings.jsonl"
            journal = AgentTimingJournal(path)
            journal.append(self.point("desktop_agent_started", 1))
            self.assertTrue(journal.close())
            journal = AgentTimingJournal(path)
            self.assertTrue(journal.close())
            self.assertEqual(1, len(journal.snapshot()))
            with patch.object(Path, "open", side_effect=AssertionError("synchronous I/O")):
                self.assertEqual(1, len(journal.snapshot()))

    def test_journal_recovers_after_corrupt_oversized_and_truncated_lines(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "timings.jsonl"
            good = json.dumps(asdict(self.point("desktop_agent_started", 1)))
            path.write_bytes(b"x" * 100_000 + b"\n\xff\n" + good.encode() + b"\n{truncated")
            journal = AgentTimingJournal(path)
            self.assertTrue(journal.close())
            self.assertEqual(1, len(journal.snapshot()))
            self.assertEqual(3, journal.health()["invalid_events"])

    def test_slow_disk_does_not_block_append_and_queue_is_bounded(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "timings.jsonl"
            entered, release = threading.Event(), threading.Event()
            original = Path.open
            def slow_open(candidate, *args, **kwargs):
                if candidate == path and args and args[0] == "a":
                    entered.set()
                    release.wait(5)
                return original(candidate, *args, **kwargs)
            with patch.object(Path, "open", slow_open):
                journal = AgentTimingJournal(path, queue_limit=4)
                journal.append(self.point("desktop_agent_started", 1))
                self.assertTrue(entered.wait(2))
                started = time.monotonic()
                for i in range(100):
                    journal.append(self.point("desktop_first_output", i, str(i)))
                self.assertLess(time.monotonic() - started, .5)
                self.assertGreaterEqual(journal.health()["dropped_events"], 96)
                self.assertLessEqual(len(journal._pending), 4)
                release.set()
                self.assertTrue(journal.close())

    def test_real_task_manager_emits_boundaries_without_extra_task_mutations(self):
        from agent_task_manager import AgentTaskManager
        with tempfile.TemporaryDirectory() as directory, patch("agent_latency_hooks.record_task") as record:
            manager = AgentTaskManager(state_path=Path(directory) / "tasks.sqlite3")
            task = manager.create_external("codex", "codex", "source", "private prompt",
                                           lambda _: None, task_id="actual-task")
            manager.update(task.task_id, "running")
            manager.record_partial_result(task.task_id, "private output")
            manager.add_event(task.task_id, "tool", "private command", event_id="tool-a", status="running")
            manager.add_event(task.task_id, "tool", "private command", event_id="tool-a", status="completed")
            manager.update(task.task_id, "completed", result="private output")
            stages = {call.args[1] for call in record.call_args_list}
            self.assertTrue({"desktop_task_created", "desktop_agent_started", "desktop_first_output",
                             "desktop_task_completed", "desktop_tool_started", "desktop_tool_completed"} <= stages)
            self.assertNotIn("private", repr(record.call_args_list))
            self.assertEqual("completed", manager.get(task.task_id).status)


if __name__ == "__main__":
    unittest.main()
