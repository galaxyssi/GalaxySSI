from __future__ import annotations

import json
import tempfile
import threading
import unittest
from pathlib import Path

from agent_task_manager import AgentTaskManager
from voice_latency import (
    InMemoryVoiceTraceEventSink,
    VoiceLatencyTracer,
    VoiceTraceEvents,
)


class MutableClock:
    def __init__(self) -> None:
        self.monotonic_ns = 1_000_000_000
        self.wall_clock_ms = 20_000

    def monotonic(self) -> int:
        return self.monotonic_ns

    def wall_clock(self) -> int:
        return self.wall_clock_ms


class VoiceLatencyTracerTest(unittest.TestCase):
    def _tracer(self, clock: MutableClock | None = None) -> tuple[VoiceLatencyTracer, InMemoryVoiceTraceEventSink]:
        source = clock or MutableClock()
        sink = InMemoryVoiceTraceEventSink()
        tracer = VoiceLatencyTracer(
            monotonic_ns=source.monotonic,
            wall_clock_ms=source.wall_clock,
            sink=sink,
        )
        return tracer, sink

    def test_elapsed_time_uses_monotonic_clock_when_wall_clock_moves_backwards(self) -> None:
        clock = MutableClock()
        tracer, _ = self._tracer(clock)
        trace_id = "trace-monotonic"
        tracer.record(trace_id, VoiceTraceEvents.AGENT_QUEUE_ENTERED)
        clock.monotonic_ns += 875_000_000
        clock.wall_clock_ms -= 120_000
        tracer.record(trace_id, VoiceTraceEvents.AGENT_RUN_STARTED)

        self.assertEqual(875, tracer.elapsed_ms(
            trace_id,
            VoiceTraceEvents.AGENT_QUEUE_ENTERED,
            VoiceTraceEvents.AGENT_RUN_STARTED,
        ))
        self.assertEqual(875, tracer.diagnostic_summary()["metrics"]["agent_queue_ms"]["p95_ms"])

    def test_sensitive_fields_and_values_are_removed(self) -> None:
        tracer, _ = self._tracer()
        event = tracer.record(
            "trace-private",
            VoiceTraceEvents.AGENT_COMPLETED,
            {
                "prompt": "delete everything",
                "transcript": "private words",
                "file_path": r"C:\Users\agent\secret.txt",
                "api_key": "secret-token",
                "transport": "https://private.example/path",
                "agent_provider": "codex",
                "task_status": "completed",
                "success": True,
            },
        )

        self.assertIsNotNone(event)
        assert event is not None
        self.assertEqual("codex", event.attributes["agent_provider"])
        self.assertEqual("completed", event.attributes["task_status"])
        self.assertEqual("true", event.attributes["success"])
        self.assertNotIn("prompt", event.attributes)
        self.assertNotIn("transcript", event.attributes)
        self.assertNotIn("file_path", event.attributes)
        self.assertNotIn("api_key", event.attributes)
        self.assertNotIn("transport", event.attributes)
        self.assertNotIn("private words", repr(event))
        self.assertNotIn("secret.txt", repr(event))

    def test_disabled_flag_and_once_deduplication(self) -> None:
        disabled_sink = InMemoryVoiceTraceEventSink()
        disabled = VoiceLatencyTracer(enabled=lambda: False, sink=disabled_sink)
        self.assertIsNone(disabled.record("trace-off", VoiceTraceEvents.AGENT_RUN_STARTED))
        self.assertEqual([], disabled_sink.snapshot())

        tracer, sink = self._tracer()
        tracer.record("trace-once", VoiceTraceEvents.AGENT_FIRST_PROGRESS, once=True)
        tracer.record("trace-once", VoiceTraceEvents.AGENT_FIRST_PROGRESS, once=True)
        self.assertEqual(1, len(sink.snapshot()))

    def test_export_is_explicitly_content_free(self) -> None:
        tracer, _ = self._tracer()
        tracer.record(
            "trace-export",
            VoiceTraceEvents.AGENT_COMPLETED,
            {"agent_provider": "hermes", "success": True},
        )
        with tempfile.TemporaryDirectory() as temporary:
            destination = tracer.export_content_free_diagnostics(Path(temporary) / "voice.json")
            payload = json.loads(destination.read_text(encoding="utf-8"))

        self.assertFalse(payload["content_included"])
        self.assertEqual("galaxyssi.voice-latency/1.0", payload["schema"])
        self.assertNotIn("prompt", json.dumps(payload))


class AgentTaskVoiceLatencyIntegrationTest(unittest.TestCase):
    def test_local_task_records_queue_start_and_completion(self) -> None:
        tracer, sink = VoiceLatencyTracerTest()._tracer()
        completed = threading.Event()
        with tempfile.TemporaryDirectory() as temporary:
            manager = AgentTaskManager(
                state_path=Path(temporary) / "tasks.sqlite3",
                latency_tracer=tracer,
            )

            def capture(snapshot: dict) -> None:
                if snapshot.get("status") == "completed":
                    completed.set()

            manager.create(
                agent_id="codex",
                contact_id="codex",
                source_message_id="message-1",
                prompt="content is intentionally excluded from telemetry",
                runner=lambda _task: "done",
                on_event=capture,
                trace_id="trace-local-task",
            )
            self.assertTrue(completed.wait(3.0))

        names = [event.event for event in sink.snapshot()]
        self.assertEqual([
            VoiceTraceEvents.AGENT_QUEUE_ENTERED,
            VoiceTraceEvents.AGENT_RUN_STARTED,
            VoiceTraceEvents.AGENT_COMPLETED,
        ], names)
        self.assertNotIn("intentionally", repr(sink.snapshot()))

    def test_external_task_records_real_progress_and_first_output_once(self) -> None:
        tracer, sink = VoiceLatencyTracerTest()._tracer()
        with tempfile.TemporaryDirectory() as temporary:
            manager = AgentTaskManager(
                state_path=Path(temporary) / "tasks.sqlite3",
                latency_tracer=tracer,
            )
            task = manager.create_external(
                agent_id="claude-code",
                contact_id="claude-code",
                source_message_id="message-2",
                prompt="private task body",
                on_event=lambda _snapshot: None,
                trace_id="trace-external-task",
            )
            manager.update(task.task_id, "running")
            manager.add_event(task.task_id, "tool", "Visible tool progress")
            manager.append_trace(
                task.task_id,
                "agent_first_output",
                "private output detail",
                once=True,
                meaningful_progress=True,
            )
            manager.append_trace(
                task.task_id,
                "agent_first_output",
                "duplicate private output",
                once=True,
                meaningful_progress=True,
            )
            manager.update(task.task_id, "completed", result="private result")

        names = [event.event for event in sink.snapshot()]
        self.assertEqual(1, names.count(VoiceTraceEvents.AGENT_QUEUE_ENTERED))
        self.assertEqual(1, names.count(VoiceTraceEvents.AGENT_RUN_STARTED))
        self.assertEqual(1, names.count(VoiceTraceEvents.AGENT_FIRST_PROGRESS))
        self.assertEqual(1, names.count(VoiceTraceEvents.AGENT_FIRST_PARTIAL_RESULT))
        self.assertEqual(1, names.count(VoiceTraceEvents.AGENT_COMPLETED))
        self.assertNotIn("private", repr(sink.snapshot()))


if __name__ == "__main__":
    unittest.main()

