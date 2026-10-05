import copy
import json
from pathlib import Path
import queue
import tempfile
import unittest
from unittest.mock import Mock

import thread_usage as usage
import test_codex_trial_usage_audit as capture_fixtures


THREAD = "12345678-abcd-4000-8000-1234567890ab"
OTHER = "12345678-abcd-4000-8000-1234567890ac"


def response(key=THREAD):
    return {"summary": {"lifetimeTokens": 999999999, "private": "PRIVATE-ACCOUNT"},
            "dailyUsageBuckets": [{"startDate": "PRIVATE-DATE", "tokens": 123}],
            "threadUsage": {"threadId": key, "estimatedUsageCreditsMicros": 500,
                            "estimatedUsageUsdMicros": 120,
                            "groups": [{"model": "fixture-model", "reasoningEffort": "high", "speed": "standard",
                                        "inputTokens": 100, "cachedInputTokens": 20, "netNewInputTokens": 50,
                                        "outputTokens": 10, "totalTokens": 110, "estimatedUsageCreditsMicros": 500}]}}


class NormalizeTest(unittest.TestCase):
    def test_normalization_does_not_export_account_data_or_double_count_cache(self):
        result = usage.normalize(response(), THREAD)
        self.assertEqual("available", result["status"])
        self.assertEqual(110, result["estimated_thread_tokens"]["total_tokens"])
        self.assertEqual(20, result["estimated_thread_tokens"]["cached_input_tokens"])
        self.assertEqual(50, result["estimated_thread_tokens"]["net_new_input_tokens"])
        self.assertIsNone(result["billed_cost"])
        self.assertIsNone(result["provider_request_count"])
        self.assertFalse(result["actual_served_model_attested"])
        self.assertNotIn("PRIVATE", json.dumps(result))
        self.assertNotIn("999999999", json.dumps(result))

    def test_missing_thread_is_not_account_fallback(self):
        for value in ({"summary": {"lifetimeTokens": 1000}}, {"threadUsage": None}):
            result = usage.normalize(value, THREAD)
            self.assertEqual("unavailable", result["status"])
            self.assertIsNone(result["estimated_thread_tokens"])

    def test_wrong_thread_fails_closed(self):
        result = usage.normalize(response(OTHER), THREAD)
        self.assertEqual(["thread_usage_identity_mismatch"], result["issues"])
        self.assertEqual([], result["groups"])

    def test_bad_thread_target_is_rejected(self):
        for key in (None, "", "thread", THREAD.upper(), "../private", True):
            with self.subTest(key=key), self.assertRaises(ValueError):
                usage.normalize(response(), key)

    def test_optional_counters_remain_unknown_not_zero(self):
        value = response()
        group = value["threadUsage"]["groups"][0]
        for field in usage.COUNTERS:
            group.pop(field)
        value["threadUsage"].pop("estimatedUsageUsdMicros")
        result = usage.normalize(value, THREAD)
        self.assertEqual("available", result["status"])
        self.assertTrue(all(number is None for number in result["estimated_thread_tokens"].values()))
        self.assertIsNone(result["estimated_usage_usd_micros"])

    def test_invalid_numbers_are_not_coerced(self):
        for number in (True, -1, "100", 1.5, 2**54):
            value = response()
            value["threadUsage"]["groups"][0]["inputTokens"] = number
            result = usage.normalize(value, THREAD)
            self.assertEqual("invalid", result["status"])
            self.assertIsNone(result["estimated_thread_tokens"])

    def test_invalid_totals_parent_subset_or_credit_sum_block_aggregation(self):
        for field, value in (("totalTokens", 1), ("cachedInputTokens", 101), ("estimatedUsageCreditsMicros", 999)):
            payload = response()
            payload["threadUsage"]["groups"][0][field] = value
            self.assertEqual("invalid", usage.normalize(payload, THREAD)["status"])

    def test_required_credits_and_malformed_groups_are_not_zero(self):
        for groups in (None, "raw-private", [], [None]):
            payload = response()
            payload["threadUsage"]["groups"] = groups
            result = usage.normalize(payload, THREAD)
            self.assertEqual("invalid", result["status"])
            self.assertIsNone(result["estimated_thread_tokens"])
        payload = response()
        payload["threadUsage"].pop("estimatedUsageCreditsMicros")
        self.assertEqual("invalid", usage.normalize(payload, THREAD)["status"])

    def test_duplicate_groups_are_ambiguous_not_summed(self):
        payload = response()
        payload["threadUsage"]["groups"] *= 2
        payload["threadUsage"]["estimatedUsageCreditsMicros"] *= 2
        result = usage.normalize(payload, THREAD)
        self.assertIn("duplicate_or_ambiguous_usage_group", result["issues"])
        self.assertIsNone(result["estimated_thread_tokens"])

    def test_distinct_model_groups_summed_once(self):
        payload = response()
        group = copy.deepcopy(payload["threadUsage"]["groups"][0])
        group["model"] = "fixture-other-model"
        payload["threadUsage"]["groups"].append(group)
        payload["threadUsage"]["estimatedUsageCreditsMicros"] *= 2
        result = usage.normalize(payload, THREAD)
        self.assertEqual(220, result["estimated_thread_tokens"]["total_tokens"])
        self.assertFalse(result["actual_served_model_attested"])

    def test_overflow_is_not_exported(self):
        payload = response()
        group = payload["threadUsage"]["groups"][0]
        group.update(inputTokens=usage.MAX_COUNTER, outputTokens=0, totalTokens=usage.MAX_COUNTER)
        second = {**group, "model": "other"}
        payload["threadUsage"]["groups"].append(second)
        payload["threadUsage"]["estimatedUsageCreditsMicros"] = 1000
        result = usage.normalize(payload, THREAD)
        self.assertIn("token_sum_out_of_range", result["issues"])

    def test_reconciliation_never_claims_complete_trial(self):
        value = usage.normalize(response(), THREAD)
        rows = [{"observed_cumulative_endpoint": {"input_tokens": 100, "cached_input_tokens": 20,
                                                  "output_tokens": 10, "total_tokens": 110}}]
        self.assertEqual("observed_counters_match", usage.reconcile(value, rows)["status"])
        rows[0]["observed_cumulative_endpoint"]["input_tokens"] = 99
        self.assertEqual("observed_counters_differ", usage.reconcile(value, rows)["status"])
        self.assertEqual("shared_thread_not_attributable", usage.reconcile(value, rows * 2)["status"])
        rows[0]["observed_cumulative_endpoint"] = None
        self.assertEqual("unavailable_or_incomplete", usage.reconcile(value, rows)["status"])


class ClientTest(unittest.TestCase):
    def client(self):
        client = object.__new__(usage.Client)
        client.responses = queue.Queue()
        client.next_id = 0
        client._write = Mock()
        return client

    def test_only_exact_thread_usage_and_initialize_allowed(self):
        client = self.client()
        for method, params in (("turn/start", {}), ("command/exec", {}), ("thread/read", {}), ("thread/resume", {}),
                               ("account/usage/read", {}), ("account/usage/read", None),
                               ("account/usage/read", {"threadId": None}), ("account/usage/read", {"threadId": ""}),
                               ("account/usage/read", {"threadId": THREAD, "extra": True})):
            with self.subTest(method=method, params=params), self.assertRaises(ValueError):
                client.request(method, params)
        client._write.assert_not_called()

    def test_wrong_request_id_ignored_and_matching_thread_requested(self):
        client = self.client()
        client.responses.put({"id": True, "result": "not-an-integer-id"})
        client.responses.put({"id": 5, "result": "old"})
        client.responses.put({"id": 1, "result": response()})
        self.assertEqual(response(), client.request("account/usage/read", {"threadId": THREAD}))
        self.assertEqual({"threadId": THREAD}, client._write.call_args.args[0]["params"])

    def test_unexpected_server_request_never_approved(self):
        client = self.client()
        client.responses.put({"id": 7, "method": "item/tool/requestApproval"})
        with self.assertRaises(RuntimeError):
            client.request("account/usage/read", {"threadId": THREAD})
        self.assertEqual(1, client._write.call_count)

    def test_timeout_and_rpc_error_are_redacted(self):
        client = self.client()
        with self.assertRaises(TimeoutError):
            client.request("account/usage/read", {"threadId": THREAD}, timeout=.001)
        client.responses.put({"id": 2, "error": {"code": -32601, "message": "PRIVATE-ERROR"}})
        with self.assertRaises(usage.RpcError) as raised:
            client.request("account/usage/read", {"threadId": THREAD})
        self.assertNotIn("PRIVATE", str(raised.exception))
        self.assertEqual(-32601, raised.exception.code)


class RunTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.executable = self.root / "codex-fixture"
        self.executable.write_bytes(b"never-execute")
        self.fixture = capture_fixtures.CodexTrialUsageAuditTest()
        self.addCleanup(self.fixture.doCleanups)
        value = self.fixture.make_capture(people=("one", "one", "one"))
        for task in value["tasks"]:
            for journal in task["usage_journals"]:
                for entry in journal["entries"]:
                    entry["observation"]["provider_thread_id"] = THREAD
        self.capture = self.root / "capture.json"
        self.capture.write_text(json.dumps(capture_fixtures.rehash(value)), encoding="utf-8")
        self.client = Mock()
        self.client.request.return_value = response()
        self.factory = Mock(return_value=self.client)

    def run_probe(self):
        return usage.run(self.executable, [self.capture], self.root / "output", client_factory=self.factory)

    def test_only_validated_unique_threads_read_and_private_report_written(self):
        report = self.run_probe()
        self.assertEqual("observed", report["status"])
        self.client.request.assert_called_once_with("account/usage/read", {"threadId": THREAD})
        self.client.close.assert_called_once()
        self.assertTrue(report["cleanup_completed"])
        self.assertEqual(0, report["model_calls"])
        self.assertFalse(report["ready_for_equal_budget_comparison"])
        self.assertIsNone(report["trial_token_total"])
        self.assertEqual(report["report_sha256"], usage.digest({k: v for k, v in report.items() if k != "report_sha256"}))
        text = (self.root / "output/report.json").read_text()
        self.assertNotIn("PRIVATE", text)
        self.assertNotIn("999999999", text)
        with self.assertRaises(FileExistsError):
            self.run_probe()
        self.assertEqual(1, self.factory.call_count)

    def test_query_error_preserves_record_and_closes(self):
        self.client.request.side_effect = usage.RpcError({"code": -1, "message": "PRIVATE-ERROR"})
        report = self.run_probe()
        self.assertEqual("incomplete", report["status"])
        self.assertEqual("query_failed", report["requests"][0]["status"])
        self.assertNotIn("PRIVATE", json.dumps(report))
        self.client.close.assert_called_once()

    def test_missing_thread_estimate_is_preserved_without_retries(self):
        self.client.request.return_value = {"summary": {"lifetimeTokens": 12345}, "threadUsage": None}
        report = self.run_probe()
        self.assertEqual("incomplete", report["status"])
        self.assertEqual("unavailable", report["requests"][0]["observation"]["status"])
        self.assertEqual(1, self.client.request.call_count)
        self.assertNotIn('"lifetimeTokens"', json.dumps(report))
        self.assertIsNone(report["requests"][0]["observation"]["estimated_thread_tokens"])

    def test_one_thread_error_does_not_discard_other_observation(self):
        value = json.loads(self.capture.read_text())
        for journal in value["tasks"][-1]["usage_journals"]:
            for entry in journal["entries"]:
                entry["observation"]["provider_thread_id"] = OTHER
        self.capture.write_text(json.dumps(capture_fixtures.rehash(value)))
        self.client.request.side_effect = [TimeoutError("PRIVATE"), response(OTHER)]
        report = self.run_probe()
        self.assertEqual(2, len(report["requests"]))
        self.assertEqual("query_failed", report["requests"][0]["status"])
        self.assertEqual("available", report["requests"][1]["observation"]["status"])
        self.assertEqual("incomplete", report["status"])

    def test_shared_trial_thread_is_queried_once_without_attribution(self):
        second = self.fixture.make_capture(trial_id="other", people=("one", "one", "one"))
        for task in second["tasks"]:
            for journal in task["usage_journals"]:
                for entry in journal["entries"]:
                    entry["observation"]["provider_thread_id"] = THREAD
        path = self.root / "capture-other.json"
        path.write_text(json.dumps(capture_fixtures.rehash(second)))
        report = usage.run(self.executable, [self.capture, path], self.root / "output", client_factory=self.factory)
        self.client.request.assert_called_once()
        self.assertEqual("shared_thread_not_attributable", report["requests"][0]["reconciliation"]["status"])
        self.assertTrue(all("cross_trial_thread_reuse" in row["issues"] for row in report["source_trial_issues"]))

    def test_source_capture_issues_remain_visible(self):
        value = json.loads(self.capture.read_text())
        value["issues"] = [{"code": "planned_assignment_unobserved"}]
        self.capture.write_text(json.dumps(capture_fixtures.rehash(value)))
        report = self.run_probe()
        self.assertIn("capture_has_issues", report["source_trial_issues"][0]["issues"])
        self.assertFalse(report["ready_for_equal_budget_comparison"])

    def test_initialization_and_cleanup_failures_are_reported(self):
        self.client.initialize.side_effect = RuntimeError("PRIVATE")
        self.client.close.side_effect = OSError("PRIVATE")
        report = self.run_probe()
        self.assertEqual("failed", report["status"])
        self.assertFalse(report["cleanup_completed"])
        self.assertNotIn("PRIVATE", json.dumps(report))
        self.client.request.assert_not_called()

    def test_tampered_capture_fails_before_starting_anything(self):
        value = json.loads(self.capture.read_text())
        value["capture_sha256"] = "bad"
        self.capture.write_text(json.dumps(value))
        with self.assertRaises(ValueError):
            self.run_probe()
        self.factory.assert_not_called()
        self.assertFalse((self.root / "output").exists())

    def test_output_inside_git_rejected_before_process_start(self):
        (self.root / ".git").write_text("gitdir: elsewhere")
        with self.assertRaises(ValueError):
            self.run_probe()
        self.factory.assert_not_called()


if __name__ == "__main__":
    unittest.main()
