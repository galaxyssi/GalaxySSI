import copy
import json
from pathlib import Path
import tempfile
import unittest

from agent_task_recovery_query import IDENTITY_FIELDS
from codex_provider_usage import normalize
from codex_trial_capture import capture
from codex_trial_usage_audit import audit, digest, export, main, read_capture
import test_codex_trial_capture as fixtures


def rehash(value):
    for task in value["tasks"]:
        for journal in task["usage_journals"]:
            for entry in journal["entries"]:
                content = {key: entry[key] for key in ("contract", *IDENTITY_FIELDS, "execution_generation", "observation")}
                entry["event_id"] = digest(content)
            journal["entries_sha256"] = digest(journal["entries"])
    value["scope_sha256"] = digest(value["scope"])
    value["capture_sha256"] = digest({key: field for key, field in value.items() if key != "capture_sha256"})
    return value


def usages(value):
    return [entry for task in value["tasks"] for journal in task["usage_journals"]
            for entry in journal["entries"] if entry["observation"]["kind"] == "usage_snapshot"]


class CodexTrialUsageAuditTest(unittest.TestCase):
    def make_capture(self, trial_id="trial", people=("analyst", "reviewer", "analyst")):
        fixture = fixtures.CodexTrialCaptureTest()
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        fixture.scope["trial_id"] = trial_id
        running = {}
        for index, (node, person) in enumerate(zip(fixture.scope["expected_nodes"], people)):
            task = fixture.task(node, usage=False, created_at=100 + index * 100,
                                started_at=110 + index * 100, completed_at=120 + index * 100)
            count = running.get(person, 0) + 1
            running[person] = count
            counts = dict(inputTokens=100 * count, cachedInputTokens=20 * count,
                          cacheWriteInputTokens=0, outputTokens=10 * count,
                          reasoningOutputTokens=3 * count, totalTokens=110 * count)
            last = {key: number // count for key, number in counts.items()}
            payload = dict(threadId=trial_id + "-" + person, turnId=node,
                           tokenUsage=dict(total=counts, last=last, modelContextWindow=400000))
            for kind in ("turn_started", "usage_snapshot", "turn_terminal"):
                fixture.archive.record(task, normalize(payload, model="gpt-6-astra", effort="xhigh",
                                                      kind=kind, status="completed"))
        result = capture(fixture.path, fixture.scope)
        for index, task in enumerate(result["tasks"]):
            for entry in task["usage_journals"][0]["entries"]:
                entry["recorded_at_ms"] = 1000 + index * 100 + entry["sequence"]
        return rehash(result)

    def report(self, value):
        return audit([rehash(value)])["trials"][0]

    def test_counts_one_endpoint_per_thread_and_keeps_parent_subsets_separate(self):
        original = self.make_capture()
        unchanged = copy.deepcopy(original)
        result = audit([original])
        row = result["trials"][0]
        self.assertEqual([], row["issues"])
        self.assertEqual(2, len(row["threads"]))
        self.assertEqual(dict(input_tokens=300, cached_input_tokens=60, cache_write_input_tokens=0,
                              output_tokens=30, reasoning_output_tokens=9, total_tokens=330,
                              uncached_input_tokens=240), row["observed_thread_cumulative_endpoint_sum"])
        for field in ("trial_token_total", "provider_request_count", "billed_cost"):
            self.assertIsNone(row[field])
        self.assertFalse(row["ready_for_equal_budget_comparison"])
        self.assertFalse(result["provider_history_complete"])
        self.assertEqual(original, unchanged)
        self.assertEqual(result["audit_sha256"], digest({k: v for k, v in result.items() if k != "audit_sha256"}))

    def test_single_person_three_tasks_is_not_sum_of_three_cumulative_snapshots(self):
        result = self.report(self.make_capture(people=("one", "one", "one")))
        self.assertEqual(330, result["observed_thread_cumulative_endpoint_sum"]["total_tokens"])
        self.assertEqual(1, len(result["threads"]))
        self.assertEqual(3, result["threads"][0]["observed_turn_count"])
        self.assertEqual(3, result["threads"][0]["observed_usage_snapshot_count"])

    def test_two_arm_context_reuse_is_flagged_not_summed_twice(self):
        first, second = self.make_capture("a"), self.make_capture("b")
        for task in second["tasks"]:
            for entry in task["usage_journals"][0]["entries"]:
                entry["observation"]["provider_thread_id"] = entry["observation"]["provider_thread_id"].replace("b-", "a-")
        result = audit([first, rehash(second)])
        for trial in result["trials"]:
            self.assertIn("cross_trial_thread_reuse", trial["issues"])
            self.assertEqual(2, len(trial["cross_trial_shared_threads"]))
            self.assertIsNone(trial["observed_thread_cumulative_endpoint_sum"])

    def test_same_capture_or_duplicate_trial_cannot_be_counted_twice(self):
        value = self.make_capture()
        for duplicate in (value, self.make_capture()):
            with self.assertRaises(ValueError):
                audit([value, duplicate])

    def test_late_old_snapshot_regression_is_not_hidden_by_taking_maximum(self):
        value = self.make_capture(people=("one", "one", "one"))
        rows = usages(value)
        rows[-1]["observation"]["total"] = dict(rows[0]["observation"]["total"])
        result = self.report(value)
        self.assertIn("cumulative_counter_regressed", result["threads"][0]["issues"])
        self.assertIsNone(result["observed_thread_cumulative_endpoint_sum"])

    def test_cached_counter_regression_also_invalidates_endpoint(self):
        value = self.make_capture(people=("one", "one", "one"))
        usages(value)[-1]["observation"]["total"]["cached_input_tokens"] = 0
        usages(value)[-1]["observation"]["last"]["cached_input_tokens"] = 0
        self.assertIn("cumulative_counter_regressed", self.report(value)["threads"][0]["issues"])

    def test_missing_optional_cache_write_remains_unknown(self):
        value = self.make_capture()
        for row in usages(value):
            for kind in ("total", "last"):
                row["observation"][kind]["cache_write_input_tokens"] = None
        result = self.report(value)
        self.assertEqual([], result["issues"])
        self.assertIsNone(result["observed_thread_cumulative_endpoint_sum"]["cache_write_input_tokens"])
        self.assertEqual(330, result["observed_thread_cumulative_endpoint_sum"]["total_tokens"])

    def test_invalid_required_counter_never_becomes_zero(self):
        for invalid in (None, True, -1, "100", 1.5, 2**54):
            with self.subTest(invalid=invalid):
                value = self.make_capture()
                usages(value)[0]["observation"]["total"]["input_tokens"] = invalid
                result = self.report(value)
                self.assertIn("thread_usage_issues", result["issues"])
                self.assertIsNone(result["observed_thread_cumulative_endpoint_sum"])

    def test_inconsistent_totals_parent_subsets_and_unknown_scopes_are_not_accepted(self):
        for field, number in (("total_tokens", 999), ("cached_input_tokens", 999), ("reasoning_output_tokens", 999)):
            value = self.make_capture()
            usages(value)[0]["observation"]["total"][field] = number
            self.assertIn("total_inconsistent_counter", self.report(value)["threads"][0]["issues"])
        value = self.make_capture()
        usages(value)[0]["observation"]["total_scope"] = "task_total"
        self.assertIn("unknown_counter_scope", self.report(value)["threads"][0]["issues"])

    def test_last_counter_errors_block_endpoint_but_last_is_never_summed(self):
        value = self.make_capture()
        usages(value)[0]["observation"]["last"]["total_tokens"] = 111
        self.assertIn("last_inconsistent_counter", self.report(value)["threads"][0]["issues"])

    def test_last_usage_cannot_exceed_cumulative_parent(self):
        value = self.make_capture()
        last = usages(value)[0]["observation"]["last"]
        last["input_tokens"], last["total_tokens"] = 200, 210
        self.assertIn("last_exceeds_cumulative_counter", self.report(value)["threads"][0]["issues"])

    def test_preexisting_history_is_not_assumed_to_be_a_zero_baseline(self):
        value = self.make_capture()
        for entry in usages(value):
            total = entry["observation"]["total"]
            total["input_tokens"] += 1000
            total["total_tokens"] += 1000
        result = self.report(value)
        self.assertEqual(2330, result["observed_thread_cumulative_endpoint_sum"]["total_tokens"])
        self.assertIsNone(result["trial_token_total"])
        self.assertTrue(all(not thread["pre_trial_baseline_observed"] and
                            thread["trial_attributable_tokens"] is None for thread in result["threads"]))

    def test_repeated_equal_endpoint_does_not_add_a_second_request(self):
        value = self.make_capture(people=("one", "one", "one"))
        rows = usages(value)
        rows[2]["observation"]["total"] = dict(rows[1]["observation"]["total"])
        result = self.report(value)
        self.assertEqual(220, result["observed_thread_cumulative_endpoint_sum"]["total_tokens"])
        self.assertIsNone(result["provider_request_count"])

    def test_equal_millisecond_cross_execution_order_is_ambiguous(self):
        value = self.make_capture(people=("one", "one", "one"))
        rows = usages(value)
        rows[1]["recorded_at_ms"] = rows[0]["recorded_at_ms"]
        self.assertIn("ambiguous_cross_execution_snapshot_order", self.report(value)["threads"][0]["issues"])

    def test_failed_and_retried_tasks_are_retained(self):
        value = self.make_capture()
        value["tasks"][0]["status"] = "failed"
        value["tasks"][2]["retry_of"] = value["tasks"][0]["task_id"]
        value["tasks"][0]["usage_journals"][0]["entries"][-1]["observation"]["provider_status"] = "failed"
        result = self.report(value)
        self.assertEqual(3, result["observed_task_count"])
        self.assertEqual(330, result["observed_thread_cumulative_endpoint_sum"]["total_tokens"])

    def test_incomplete_capture_preserved_with_no_computable_sum(self):
        value = self.make_capture()
        value["issues"] = [{"code": "planned_assignment_unobserved"}]
        result = self.report(value)
        self.assertIn("capture_has_issues", result["issues"])
        self.assertEqual(2, len(result["threads"]))
        self.assertIsNone(result["observed_thread_cumulative_endpoint_sum"])

    def test_missing_journals_are_unknown_even_without_capture_issue(self):
        value = self.make_capture()
        value["tasks"][0]["usage_journals"] = []
        value["tasks"][0]["unobserved_generation_count"] = 1
        self.assertIn("task_usage_coverage_incomplete", self.report(value)["issues"])

    def test_missing_planned_task_is_detected_even_when_capture_issues_are_empty(self):
        value = self.make_capture()
        value["tasks"] = value["tasks"][:-1]
        value["assignments"][-1].update(task_ids=[], observation="unobserved")
        result = self.report(value)
        self.assertIn("planned_assignment_unobserved", result["issues"])
        self.assertIsNone(result["observed_thread_cumulative_endpoint_sum"])

    def test_running_task_blocks_summary_even_when_provider_turn_ended(self):
        value = self.make_capture()
        value["tasks"][0]["status"] = "running"
        self.assertIn("task_not_terminal", self.report(value)["issues"])

    def test_assignment_and_task_control_tampering_do_not_pass(self):
        value = self.make_capture()
        value["assignments"][0]["task_ids"] = ["other-task"]
        with self.assertRaises(ValueError):
            self.report(value)
        value = self.make_capture()
        value["tasks"][0]["requested_reasoning_effort"] = "low"
        self.assertIn("task_requested_controls_mismatch", self.report(value)["issues"])

    def test_missing_terminal_or_usage_is_an_explicit_issue(self):
        for missing in ("turn_started", "usage_snapshot", "turn_terminal"):
            value = self.make_capture()
            journal = value["tasks"][0]["usage_journals"][0]
            journal["entries"] = [e for e in journal["entries"] if e["observation"]["kind"] != missing]
            for i, entry in enumerate(journal["entries"], 1):
                entry["sequence"] = i
            journal["observed_through_sequence"] = len(journal["entries"])
            self.assertIn("incomplete_turn_observations", self.report(value)["threads"][0]["issues"])

    def test_turn_owned_by_two_tasks_is_rejected_for_aggregation(self):
        value = self.make_capture(people=("one", "one", "one"))
        for entry in value["tasks"][2]["usage_journals"][0]["entries"]:
            entry["observation"]["provider_turn_id"] = "author"
        self.assertIn("provider_turn_has_multiple_owners", self.report(value)["threads"][0]["issues"])

    def test_requested_model_drift_blocks_aggregation(self):
        value = self.make_capture()
        usages(value)[0]["observation"]["requested_model"] = "different-model"
        self.assertIn("requested_controls_mismatch", self.report(value)["threads"][0]["issues"])

    def test_capture_journal_event_and_sequence_tampering_are_rejected(self):
        original = self.make_capture()
        with self.assertRaises(ValueError):
            audit([{**original, "ended_at_ms": 1}])
        for mutation in (lambda j: j.update(entries_sha256="bad"),
                         lambda j: j["entries"][0].update(event_id="bad"),
                         lambda j: j["entries"][0].update(sequence=2),
                         lambda j: j["entries"][0].update(task_id="other")):
            value = copy.deepcopy(original)
            mutation(value["tasks"][0]["usage_journals"][0])
            value["capture_sha256"] = digest({k: v for k, v in value.items() if k != "capture_sha256"})
            with self.assertRaises(ValueError):
                audit([value])

    def test_no_content_or_private_task_results_are_exported(self):
        result = audit([self.make_capture()])
        encoded = json.dumps(result)
        self.assertNotIn("PRIVATE-", encoded)
        self.assertNotIn('"observation"', encoded)
        self.assertNotIn('"prompt"', encoded)

    def test_read_rejects_duplicate_json_fields_and_nonfinite_numbers(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "bad.json"
            for text in ('{"a": 1, "a": 2}', '{"a": NaN}', '{"a": Infinity}'):
                path.write_text(text)
                with self.assertRaises(ValueError):
                    read_capture(path)

    def test_export_is_exclusive_and_outside_git(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source, output = root / "capture.json", root / "audit.json"
            source.write_text(json.dumps(self.make_capture()), encoding="utf-8")
            self.assertEqual(0, main(["--capture", str(source), "--output", str(output)]))
            self.assertTrue(output.is_file())
            with self.assertRaises(FileExistsError):
                export([source], output)
            (root / ".git").write_text("gitdir: somewhere")
            with self.assertRaises(ValueError):
                export([source], root / "second.json")

    def test_cli_preserves_incomplete_report_and_returns_two(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            value = self.make_capture()
            value["issues"] = [{"code": "missing"}]
            source, output = root / "capture.json", root / "audit.json"
            source.write_text(json.dumps(rehash(value)), encoding="utf-8")
            self.assertEqual(2, main(["--capture", str(source), "--output", str(output)]))
            self.assertIsNone(read_capture(output)["trials"][0]["observed_thread_cumulative_endpoint_sum"])


if __name__ == "__main__":
    unittest.main()
