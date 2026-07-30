import json
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from agent_performance_lab import build_agent_performance_report


NOW = datetime(2026, 7, 30, 4, 0, tzinfo=timezone.utc)


class AgentPerformanceLabTest(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.log_path = Path(self.temporary_directory.name) / "agent-execution.jsonl"
        self.agents = [
            {"id": "codex", "name": "Codex Agent", "status": "ready", "runtime_status": "idle"},
            {"id": "claude", "name": "Claude Code", "status": "ready", "runtime_status": "idle"},
            {"id": "hermes", "name": "Hermes Agent", "status": "needs_setup"},
            {"id": "openclaw", "name": "OpenClaw", "status": "ready", "runtime_status": "busy", "active_tasks": 1},
        ]

    def tearDown(self):
        self.temporary_directory.cleanup()

    def write_entries(self, *entries, backup=False):
        target = self.log_path.with_suffix(".jsonl.1") if backup else self.log_path
        target.write_text(
            "".join(json.dumps(entry) + "\n" for entry in entries),
            encoding="utf-8",
        )

    def entry(self, agent_id, *, age_hours, duration_ms, ok=True, error=""):
        return {
            "ts": (NOW - timedelta(hours=age_hours)).isoformat(),
            "contact_id": agent_id,
            "duration_ms": duration_ms,
            "ok": ok,
            "error": error,
        }

    def test_window_filters_samples_and_ranks_reliability_before_speed(self):
        self.write_entries(
            self.entry("codex", age_hours=2, duration_ms=900, ok=True),
            self.entry("codex", age_hours=1, duration_ms=100, ok=False, error="failed"),
            self.entry("claude", age_hours=3, duration_ms=1500, ok=True),
            self.entry("claude", age_hours=2, duration_ms=1700, ok=True),
            self.entry("openclaw", age_hours=72, duration_ms=400, ok=True),
        )

        report = build_agent_performance_report(
            window="24h",
            agents=self.agents,
            execution_log_path=self.log_path,
            now=NOW,
        )

        rows = {row["agent_id"]: row for row in report["agents"]}
        self.assertEqual(2, rows["codex"]["attempts"])
        self.assertEqual(0.5, rows["codex"]["success_rate"])
        self.assertEqual(2, rows["claude"]["attempts"])
        self.assertEqual(1.0, rows["claude"]["success_rate"])
        self.assertEqual(1, rows["claude"]["rank"])
        self.assertEqual(2, rows["codex"]["rank"])
        self.assertEqual(0, rows["openclaw"]["attempts"])
        self.assertEqual("no_data", rows["openclaw"]["measurement_state"])
        self.assertEqual("claude", report["summary"]["recommended_agent_id"])

    def test_unavailable_and_no_data_are_not_presented_as_measurements(self):
        report = build_agent_performance_report(
            window="7d",
            agents=self.agents,
            execution_log_path=self.log_path,
            now=NOW,
        )

        rows = {row["agent_id"]: row for row in report["agents"]}
        self.assertEqual("unavailable", rows["hermes"]["measurement_state"])
        self.assertEqual("no_data", rows["codex"]["measurement_state"])
        self.assertIsNone(rows["codex"]["success_rate"])
        self.assertIsNone(report["summary"]["recommended_agent_id"])

    def test_all_window_reads_rotated_log_and_skips_invalid_records(self):
        self.write_entries(
            self.entry("openclaw", age_hours=1000, duration_ms=450, ok=True),
            backup=True,
        )
        self.log_path.write_text(
            "{broken json\n"
            + json.dumps(self.entry("openclaw", age_hours=1, duration_ms=550, ok=True))
            + "\n",
            encoding="utf-8",
        )

        report = build_agent_performance_report(
            window="all",
            agents=self.agents,
            execution_log_path=self.log_path,
            now=NOW,
        )

        row = next(item for item in report["agents"] if item["agent_id"] == "openclaw")
        self.assertEqual(2, row["attempts"])
        self.assertEqual(500.0, row["average_latency_ms"])
        self.assertEqual(1, report["evidence"]["invalid_entries"])
        self.assertFalse(report["evidence"]["contains_prompt_or_reply_content"])

    def test_failed_attempts_do_not_make_latency_look_faster(self):
        self.write_entries(
            self.entry("codex", age_hours=2, duration_ms=20, ok=False, error="startup failed"),
            self.entry("codex", age_hours=1, duration_ms=2000, ok=True),
        )

        report = build_agent_performance_report(
            window="7d",
            agents=self.agents,
            execution_log_path=self.log_path,
            now=NOW,
        )

        row = next(item for item in report["agents"] if item["agent_id"] == "codex")
        self.assertEqual(1, row["successful_latency_observations"])
        self.assertEqual(2000.0, row["p50_latency_ms"])

    def test_invalid_window_is_rejected(self):
        with self.assertRaises(ValueError):
            build_agent_performance_report(
                window="year",
                agents=self.agents,
                execution_log_path=self.log_path,
                now=NOW,
            )


if __name__ == "__main__":
    unittest.main()
