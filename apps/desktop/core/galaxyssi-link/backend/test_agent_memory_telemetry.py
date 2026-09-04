from __future__ import annotations

import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

from agent_memory_telemetry import (
    AgentMemorySample,
    AgentSessionMemorySample,
    AgentMemoryTelemetryRuntime,
    AgentMemoryTelemetryStore,
    DEFAULT_SESSION_MEMORY_TARGET_BYTES,
    ProcessMemoryReading,
    aggregate_memory_samples,
    aggregate_session_memory_samples,
    default_database_path,
    measurement_kind,
    process_memory_reading,
    provider_id_for_task,
)


MIB = 1_048_576


class AgentMemoryTelemetryTest(unittest.TestCase):
    def test_default_store_path_follows_application_state_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.dict(
                "os.environ",
                {"GALAXYSSI_STATE_DIR": directory},
                clear=False,
            ):
                expected = Path(directory) / "agent_memory_telemetry.sqlite3"
                self.assertEqual(expected, default_database_path())
                self.assertEqual(expected, AgentMemoryTelemetryStore().path)

    def test_provider_identity_prefers_explicit_then_delegate(self):
        self.assertEqual(
            "deepseek",
            provider_id_for_task({"provider_id": "model:DeepSeek"}),
        )
        self.assertEqual(
            "codex",
            provider_id_for_task({
                "delegate_agent_id": "codex",
                "agent_id": "auto",
            }),
        )
        self.assertEqual(
            "on-device",
            provider_id_for_task({"agent_id": "galaxyssi-desktop"}),
        )

    def test_aggregation_keeps_current_peak_and_estimation_semantics(self):
        samples = [
            sample("one", 1_000, 300, 120, agent="codex", mode="exclusive_process_tree"),
            sample("two", 2_000, 220, 80, agent="codex", mode="exclusive_process_tree"),
            sample("three", 2_000, 220, 110, agent="hermes", mode="shared_weighted"),
        ]

        snapshot = aggregate_memory_samples(samples)

        self.assertEqual(220 * MIB, snapshot["process_current_bytes"])
        self.assertEqual(300 * MIB, snapshot["process_peak_bytes"])
        codex = next(item for item in snapshot["by_agent"] if item["id"] == "codex")
        hermes = next(item for item in snapshot["by_agent"] if item["id"] == "hermes")
        self.assertEqual(80 * MIB, codex["current_bytes"])
        self.assertEqual(120 * MIB, codex["peak_bytes"])
        self.assertFalse(codex["estimated"])
        self.assertTrue(hermes["estimated"])

    def test_runtime_attributes_child_tree_and_shared_backend_separately(self):
        with tempfile.TemporaryDirectory() as directory:
            store = AgentMemoryTelemetryStore(
                Path(directory) / "memory.sqlite3",
                max_samples=100,
            )
            runtime = AgentMemoryTelemetryRuntime(
                lambda: [
                    {
                        "task_id": "task-codex",
                        "status": "running",
                        "process_id": 22,
                        "delegate_agent_id": "codex",
                        "conversation_id": "session-a",
                    },
                    {
                        "task_id": "task-cloud",
                        "status": "running",
                        "process_id": 0,
                        "delegate_agent_id": "model:deepseek",
                        "conversation_id": "session-b",
                    },
                    {
                        "task_id": "done",
                        "status": "completed",
                        "process_id": 33,
                        "delegate_agent_id": "hermes",
                        "conversation_id": "session-c",
                    },
                ],
                store=store,
                process_sampler=lambda pid: ProcessMemoryReading(
                    300 * MIB,
                    "windows_working_set",
                    pid,
                ),
                process_tree_sampler=lambda pid: ProcessMemoryReading(
                    180 * MIB,
                    "windows_working_set",
                    pid,
                ),
            )

            snapshot = runtime.capture()

            codex = next(item for item in snapshot["by_agent"] if item["id"] == "codex")
            deepseek = next(
                item for item in snapshot["by_provider"]
                if item["id"] == "deepseek"
            )
            self.assertEqual(180 * MIB, codex["current_bytes"])
            self.assertFalse(codex["estimated"])
            self.assertEqual(300 * MIB, deepseek["current_bytes"])
            self.assertTrue(deepseek["estimated"])
            self.assertFalse(any(item["id"] == "hermes" for item in snapshot["by_agent"]))

    def test_historical_agent_is_not_reported_as_current(self):
        snapshot = aggregate_memory_samples([
            sample("agent", 1_000, 200, 100, agent="codex", mode="exclusive_process_tree"),
            sample("process", 2_000, 150, 0),
        ])

        codex = next(item for item in snapshot["by_agent"] if item["id"] == "codex")
        self.assertEqual(0, codex["current_bytes"])
        self.assertEqual(100 * MIB, codex["peak_bytes"])

    def test_terminal_observation_is_sampled_before_idle_window_clears_current(self):
        with tempfile.TemporaryDirectory() as directory:
            runtime = AgentMemoryTelemetryRuntime(
                lambda: [],
                store=AgentMemoryTelemetryStore(
                    Path(directory) / "memory.sqlite3",
                    max_samples=100,
                ),
                process_sampler=lambda pid: ProcessMemoryReading(
                    120 * MIB,
                    "windows_working_set",
                    pid,
                ),
                process_tree_sampler=lambda pid: ProcessMemoryReading(
                    70 * MIB,
                    "windows_working_set",
                    pid,
                ),
            )
            runtime.observe_task({
                "task_id": "fast-task",
                "status": "completed",
                "status_seq": 4,
                "updated_at": 10,
                "process_id": 44,
                "delegate_agent_id": "codex",
                "conversation_id": "fast-session",
            })

            terminal = runtime.capture()
            idle = runtime.capture()

            self.assertEqual(
                70 * MIB,
                next(item for item in terminal["by_agent"] if item["id"] == "codex")[
                    "current_bytes"
                ],
            )
            self.assertEqual(
                0,
                next(item for item in idle["by_agent"] if item["id"] == "codex")[
                    "current_bytes"
                ],
            )

    def test_store_enforces_bounded_history(self):
        with tempfile.TemporaryDirectory() as directory:
            store = AgentMemoryTelemetryStore(
                Path(directory) / "memory.sqlite3",
                max_samples=100,
            )
            now = int(time.time() * 1000)
            store.append_many([
                sample(str(index), now + index, 100, 50, agent="codex")
                for index in range(120)
            ])

            retained = store.recent(limit=200)

            self.assertEqual(100, len(retained))
            self.assertEqual("20", retained[0].sample_id)
            self.assertEqual("119", retained[-1].sample_id)

    def test_process_sampler_reports_platform_specific_resident_metric(self):
        reading = process_memory_reading(__import__("os").getpid())

        self.assertEqual(measurement_kind(), reading.measurement_kind)
        self.assertGreater(reading.resident_bytes, 0)

    def test_session_budget_uses_incremental_process_memory(self):
        snapshot = aggregate_session_memory_samples([
            session_sample("one", 1_000, 100, 109),
            session_sample("two", 2_000, 109, 121),
        ])

        self.assertEqual(12 * MIB, snapshot["latest_incremental_bytes"])
        self.assertEqual(12 * MIB, snapshot["peak_incremental_bytes"])
        self.assertEqual(2, snapshot["sample_count"])
        self.assertEqual(0, snapshot["exceeded_count"])
        self.assertTrue(snapshot["within_budget"])
        self.assertEqual(DEFAULT_SESSION_MEMORY_TARGET_BYTES, snapshot["target_bytes"])

    def test_runtime_persists_new_session_budget_separately_from_agent_processes(self):
        with tempfile.TemporaryDirectory() as directory:
            store = AgentMemoryTelemetryStore(
                Path(directory) / "memory.sqlite3",
                max_samples=100,
            )
            runtime = AgentMemoryTelemetryRuntime(
                lambda: [],
                store=store,
                process_sampler=lambda pid: ProcessMemoryReading(
                    140 * MIB,
                    "windows_working_set",
                    pid,
                ),
            )

            runtime.observe_session_created({
                "sampled_at": int(time.time() * 1000),
                "session_id": "session-new",
                "agent_id": "codex",
                "conversation_id": "conversation-new",
                "before_bytes": 140 * MIB,
                "after_bytes": 151 * MIB,
                "measurement_kind": "windows_working_set",
            })
            snapshot = runtime.snapshot()

            self.assertEqual(11 * MIB, snapshot["session_budget"]["latest_incremental_bytes"])
            self.assertEqual("session-new", snapshot["session_budget"]["latest_session_id"])
            self.assertTrue(snapshot["session_budget"]["within_budget"])
            self.assertEqual(1, len(store.recent_sessions()))


def sample(
    sample_id: str,
    at: int,
    process_mib: int,
    attributed_mib: int,
    *,
    agent: str = "",
    mode: str = "process_total",
) -> AgentMemorySample:
    return AgentMemorySample(
        sample_id=sample_id,
        sampled_at=at,
        process_total_bytes=process_mib * MIB,
        attributed_bytes=attributed_mib * MIB,
        measurement_kind="windows_working_set",
        attribution_mode=mode,
        process_id=1,
        agent_id=agent,
        session_id=f"session-{agent}" if agent else "",
        provider_id=agent,
        task_id=f"task-{agent}" if agent else "",
    )


def session_sample(
    sample_id: str,
    at: int,
    before_mib: int,
    after_mib: int,
) -> AgentSessionMemorySample:
    return AgentSessionMemorySample(
        sample_id=sample_id,
        sampled_at=at,
        session_id=f"session-{sample_id}",
        agent_id="codex",
        conversation_id=f"conversation-{sample_id}",
        before_bytes=before_mib * MIB,
        after_bytes=after_mib * MIB,
        incremental_bytes=max(0, after_mib - before_mib) * MIB,
        measurement_kind="windows_working_set",
    )


if __name__ == "__main__":
    unittest.main()
