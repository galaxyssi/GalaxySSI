import copy
from contextlib import closing
import hashlib
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch

from agent_provider_usage import AgentProviderUsage
from agent_task_store import AgentTaskStore
from agent_tool_evidence import canonical, task_identity
from codex_provider_usage import normalize
from codex_trial_capture import FORMAT, capture, export, main, read_tasks
from test_codex_provider_usage import payload


class CodexTrialCaptureTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.path = self.root / "run.db"
        self.store = AgentTaskStore(self.path)
        self.archive = AgentProviderUsage(self.path)
        self.scope = dict(format=FORMAT, trial_id="fixture-trial", client_route_id="phone",
                          conversation_id="conversation", turn_id="turn", contact_id="paired-codex",
                          agent_id="codex", requested_model="gpt-6-astra", requested_reasoning_effort="xhigh",
                          expected_nodes=["author", "review", "deliver"])

    def task(self, node="author", task_id=None, usage=True, **changes):
        value = dict(task_id=task_id or node, client_route_id="phone", client_conversation_id="conversation",
                     client_turn_id="turn", contact_id="paired-codex", source_message_id=task_id or node,
                     agent_id="codex", conversation_id="backend-" + node, status="completed", status_seq=1,
                     execution_generation=1, created_at=100, started_at=110, completed_at=200, updated_at=200,
                     request_snapshot={"version": 1, "options": {"agent_instance_id": node,
                         "agent_invocation": {"model_id": "gpt-6-astra", "reasoning_effort": "xhigh"}}},
                     prompt="PRIVATE-PROMPT", result="PRIVATE-ANSWER", error="PRIVATE-ERROR")
        value.update(changes)
        value["_storage_revision"] = self.store.upsert(value)
        if usage:
            self.observe(value)
        return value

    def observe(self, task, model="gpt-6-astra", effort="xhigh", terminal=True, malformed=False):
        data = payload()
        data["threadId"] = "provider-" + task["task_id"]
        data["turnId"] = "turn-" + str(task["execution_generation"])
        if malformed:
            data["tokenUsage"]["total"]["inputTokens"] = None
        for kind in ["turn_started", "usage_snapshot"] + (["turn_terminal"] if terminal else []):
            self.archive.record(task, normalize(data, model=model, effort=effort, kind=kind, status="completed"))

    def all_tasks(self):
        return [self.task(node) for node in self.scope["expected_nodes"]]

    def codes(self, report):
        return {item["code"] for item in report["issues"]}

    def test_collects_every_node_without_turning_notifications_into_cost_or_requests(self):
        self.all_tasks()
        before = self.path.read_bytes()
        result = capture(self.path, self.scope)
        self.assertEqual(before, self.path.read_bytes())
        self.assertEqual([], result["issues"])
        self.assertEqual(3, len(result["assignments"]))
        self.assertEqual(3, len(result["tasks"]))
        self.assertEqual(9, sum(len(t["usage_journals"][0]["entries"]) for t in result["tasks"]))
        for key in ("request_count", "trial_token_total", "billed_cost", "actual_model", "actual_reasoning_effort"):
            self.assertIsNone(result[key])
        self.assertFalse(result["ready_for_equal_budget_comparison"])
        self.assertFalse(result["provider_history_complete"])
        self.assertNotIn("PRIVATE-", json.dumps(result))
        expected = result.pop("capture_sha256")
        self.assertEqual(expected, hashlib.sha256(canonical(result)).hexdigest())

    def test_foreign_routes_contacts_turns_and_agents_are_not_exported(self):
        self.all_tasks()
        for index, change in enumerate(({"client_route_id": "other"}, {"client_conversation_id": "other"},
                                       {"client_turn_id": "other"}, {"contact_id": "other"}, {"agent_id": "claude"})):
            self.task(task_id=f"foreign-{index}", usage=False, **change)
        result = capture(self.path, self.scope)
        self.assertEqual(3, len(result["tasks"]))
        self.assertNotIn("foreign-", json.dumps(result))

    def test_missing_failed_and_running_nodes_are_not_filtered_out(self):
        self.task(status="failed")
        self.task("review", status="running")
        result = capture(self.path, self.scope)
        self.assertEqual(["failed", "running"], [t["status"] for t in result["tasks"]])
        self.assertEqual("unobserved", result["assignments"][2]["observation"])
        self.assertEqual([], result["assignments"][2]["task_ids"])
        self.assertIn("planned_assignment_unobserved", self.codes(result))
        self.assertIn("task_not_terminal", self.codes(result))

    def test_retries_and_unplanned_members_are_retained_not_best_of(self):
        self.all_tasks()
        self.task("author", task_id="author-retry", retry_of="author", status="failed")
        self.task("unplanned")
        result = capture(self.path, self.scope)
        self.assertEqual(5, len(result["tasks"]))
        self.assertEqual(2, len(result["assignments"][0]["task_ids"]))
        self.assertIn("multiple_tasks_retained_not_best_of", self.codes(result))
        self.assertIn("unexpected_assignment", self.codes(result))

    def test_missing_usage_stays_unknown(self):
        self.task(usage=False)
        result = capture(self.path, self.scope)
        self.assertEqual([], result["tasks"][0]["usage_journals"])
        self.assertEqual(1, result["tasks"][0]["unobserved_generation_count"])
        self.assertIn("unobserved_execution_generations", self.codes(result))
        self.assertIsNone(result["trial_token_total"])

    def test_model_effort_and_provider_schema_drift_are_explicit(self):
        value = self.task(usage=False)
        value["request_snapshot"]["options"]["agent_invocation"] = {"model_id": "other", "reasoning_effort": "medium"}
        self.store.upsert(value)
        self.observe(value, model="other", effort="medium", terminal=False, malformed=True)
        codes = self.codes(capture(self.path, self.scope))
        self.assertTrue({"requested_model_mismatch", "requested_reasoning_effort_mismatch",
                         "provider_requested_controls_mismatch", "provider_usage_schema_issues",
                         "provider_terminal_unobserved"}.issubset(codes))

    def test_every_observed_generation_retained_and_missing_generations_flagged(self):
        value = self.task()
        value["execution_generation"] = 3
        value["_storage_revision"] = self.store.upsert(value)
        self.observe(value)
        result = capture(self.path, self.scope)
        journals = result["tasks"][0]["usage_journals"]
        self.assertEqual([1, 3], [item["execution_generation"] for item in journals])
        self.assertEqual(1, result["tasks"][0]["unobserved_generation_count"])
        self.assertIn("unobserved_execution_generations", self.codes(result))

    def test_sparse_large_generation_is_reported_without_enumerating_missing_history(self):
        self.task(execution_generation=2**40)
        result = capture(self.path, self.scope)
        self.assertEqual(2**40 - 1, result["tasks"][0]["unobserved_generation_count"])
        self.assertEqual(1, len(result["tasks"][0]["usage_journals"]))

    def test_generation_discovery_rejects_mismatched_identity(self):
        value = self.task()
        identity = task_identity(value)
        for fields in ({**identity, "source_message_id": "wrong"}, {**identity, "client_route_id": "wrong"}):
            with self.assertRaises(ValueError):
                self.archive.observed_generations(fields, client_route_id="phone")

    def test_corrupted_generation_receipt_is_not_silently_dropped(self):
        self.task()
        with closing(sqlite3.connect(self.path)) as db:
            db.execute("UPDATE agent_provider_usage SET digest='bad' WHERE sequence=1")
            db.commit()
        with self.assertRaises(ValueError):
            capture(self.path, self.scope)

    def test_task_changes_during_capture_are_reported(self):
        self.all_tasks()
        first = read_tasks(self.path, self.scope)
        second = copy.deepcopy(first)
        second[0]["execution_generation"] = 2
        with patch("codex_trial_capture.read_tasks", side_effect=[first, second]):
            result = capture(self.path, self.scope)
        self.assertIn("task_snapshot_changed_during_capture", self.codes(result))
        self.assertNotEqual(result["task_snapshot_sha256"], result["task_snapshot_after_sha256"])

    def test_new_generation_during_capture_never_produces_negative_missing_count(self):
        value = self.task()
        first = read_tasks(self.path, self.scope)
        value["execution_generation"] = 2
        value["_storage_revision"] = self.store.upsert(value)
        self.observe(value)
        second = read_tasks(self.path, self.scope)
        with patch("codex_trial_capture.read_tasks", side_effect=[first, second]):
            result = capture(self.path, self.scope)
        self.assertEqual(0, result["tasks"][0]["unobserved_generation_count"])
        self.assertEqual(2, len(result["tasks"][0]["usage_journals"]))
        self.assertIn("execution_generation_changed_during_capture", self.codes(result))

    def test_previous_turn_terminal_cannot_hide_a_later_unfinished_provider_turn(self):
        value = self.task()
        data = payload()
        data["threadId"] = "provider-author"
        data["turnId"] = "second-turn"
        self.archive.record(value, normalize(data, model="gpt-6-astra", effort="xhigh", kind="turn_started"))
        result = capture(self.path, self.scope)
        self.assertIn("provider_terminal_unobserved", self.codes(result))
        self.assertIn("usage_snapshot_missing", self.codes(result))
        self.assertEqual(2, len(result["tasks"][0]["usage_journals"][0]["observed_turn_coverage"]))

    def test_malformed_scope_rejected_before_database_open(self):
        for change in ({"expected_nodes": []}, {"expected_nodes": ["a", "a"]}, {"expected_nodes": [None]},
                       {"requested_model": "auto"}, {"requested_reasoning_effort": "auto"},
                       {"client_route_id": ""}, {"agent_id": "claude"}, {"extra": "secret"}):
            with self.subTest(change=change), patch("codex_trial_capture.read_tasks") as reader:
                with self.assertRaises(ValueError):
                    capture(self.path, {**self.scope, **change})
                reader.assert_not_called()

    def test_export_refuses_overwrite_and_git_paths(self):
        self.all_tasks()
        target = self.root / "capture.json"
        report = export(self.path, self.scope, target)
        self.assertEqual(report, json.loads(target.read_text()))
        with self.assertRaises(FileExistsError):
            export(self.path, self.scope, target)
        (self.root / ".git").write_text("gitdir: elsewhere")
        with self.assertRaises(ValueError):
            export(self.path, self.scope, self.root / "other.json")

    def test_cli_preserves_incomplete_capture_and_returns_two(self):
        self.task()
        scope = self.root / "scope.json"
        scope.write_text(json.dumps(self.scope), encoding="utf-8")
        output = self.root / "capture.json"
        self.assertEqual(2, main(["--database", str(self.path), "--scope", str(scope), "--output", str(output)]))
        self.assertTrue(output.is_file())


if __name__ == "__main__":
    unittest.main()
