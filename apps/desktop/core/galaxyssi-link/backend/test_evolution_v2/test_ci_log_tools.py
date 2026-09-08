from __future__ import annotations

import copy
import json
from pathlib import Path
import tempfile
import threading
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch

from evolution_v2.ci_log_tools import CiLogTools, LOG_LIMIT, PAGE
from evolution_v2.local_action_contract import action_schema
from evolution_v2.local_implementation import implement_locally, implementation_observer
from evolution_v2.local_tool_observations import WorkspaceToolError


URL = "https://github.com/owner/project/pull/7"
SHA = "a" * 40


class CiLogToolsTests(unittest.TestCase):
    def setUp(self):
        self.client = Mock()
        self.client.source_root = Path(".")
        self.repair = {"url": URL, "head_sha": SHA, "head_ref": "evolution/test"}
        self.head = {"repository": "owner/project", "head_repository": "owner/project", "head_sha": SHA,
                     "head_ref": "evolution/test", "state": "open", "merged": False}
        self.check = {"kind": "check_run", "id": 11, "outcome": "failed", "name": "repository-check",
                      "conclusion": "failure", "summary": "", "url": "https://github.com/owner/project/actions/runs/20/job/30"}
        self.job = {"id": 30, "run_id": 20, "head_sha": SHA, "status": "completed", "conclusion": "failure",
                    "completed_at": "2026-09-08T00:00:00Z",
                    "check_run_url": "https://api.github.com/repos/owner/project/check-runs/11"}
        self.client.pull_request_head.side_effect = lambda _: copy.deepcopy(self.head)
        self.snapshot = {"head_sha": SHA, "checks": [self.check]}
        self.client.pull_request_ci_snapshot.side_effect = lambda _: copy.deepcopy(self.snapshot)
        self.client._api.side_effect = lambda _: copy.deepcopy(self.job)
        self.client.runner.run_bounded.return_value = (SimpleNamespace(ok=True, stdout="error: missing source\n"), False)
        self.tools = CiLogTools(self.client, self.repair)

    def read(self, **kwargs):
        return self.tools.execute({"operation": "ci_log", "check_id": 11, **kwargs})

    def test_empty_summary_can_be_followed_to_actual_job_error(self):
        checks = self.tools.execute({"operation": "ci_checks"})
        self.assertEqual("", checks["checks"][0]["summary"])
        result = self.read()
        self.assertIn("missing source", result["text"])
        self.assertEqual(SHA, result["head_sha"])
        self.assertTrue(result["untrusted"])
        self.client.runner.run_bounded.assert_called_once_with(
            ("gh", "api", "repos/owner/project/actions/jobs/30/logs"), Path("."),
            maximum_bytes=LOG_LIMIT, timeout_seconds=120)

    def test_failed_checks_only_and_check_list_pagination(self):
        self.snapshot["checks"] = [{**self.check, "id": i} for i in range(1, 23)]
        self.snapshot["checks"].append({**self.check, "id": 99, "outcome": "passed"})
        first = self.tools.execute({"operation": "ci_checks"})
        second = self.tools.execute({"operation": "ci_checks", "offset": first["next_offset"]})
        self.assertEqual(list(range(1, 23)), [row["id"] for row in first["checks"] + second["checks"]])
        self.assertIsNone(second["next_offset"])
        self.client.runner.run_bounded.assert_not_called()

    def test_large_check_summaries_are_explicitly_paged_and_bounded(self):
        self.check.update(summary="x" * 10000, name="n" * 1000)
        row = self.tools.execute({"operation": "ci_checks"})["checks"][0]
        self.assertEqual(500, len(row["summary"]))
        self.assertEqual(200, len(row["name"]))
        self.assertTrue(row["summary_truncated"])

    def test_missing_summary_is_empty_not_invented_evidence(self):
        self.check["summary"] = None
        row = self.tools.execute({"operation": "ci_checks"})["checks"][0]
        self.assertEqual("", row["summary"])
        self.assertFalse(row["summary_truncated"])

    def test_tail_first_and_bidirectional_pages_do_not_repeat_download(self):
        text = "a" * PAGE + "b" * PAGE + "c" * PAGE
        self.client.runner.run_bounded.return_value = (SimpleNamespace(ok=True, stdout=text), False)
        tail = self.read()
        middle = self.read(offset=tail["previous_offset"])
        first = self.read(offset=middle["previous_offset"])
        self.assertEqual(text, first["text"] + middle["text"] + tail["text"])
        self.assertEqual(PAGE, first["next_offset"])
        self.assertEqual(first["log_sha256"], tail["log_sha256"])
        self.client.runner.run_bounded.assert_called_once()

    def test_secret_redaction_precedes_page_splitting(self):
        secret = "ghp_" + "X" * 36
        text = "a" * (PAGE - 10) + "Authorization: Bearer private-token\n" + secret
        self.client.runner.run_bounded.return_value = (SimpleNamespace(ok=True, stdout=text), False)
        pages = self.read(offset=0)["text"] + self.read(offset=PAGE)["text"]
        self.assertNotIn("private-token", pages)
        self.assertNotIn(secret, pages)
        self.assertIn("REDACTED", pages)

    def test_head_change_invalidates_cached_log(self):
        self.read()
        self.head["head_sha"] = "b" * 40
        with self.assertRaisesRegex(WorkspaceToolError, "identity changed"):
            self.read()
        self.assertIsNone(self.tools.cache)

    def test_new_read_only_audit_can_bind_to_already_merged_pr(self):
        self.head.update(state="closed", merged=True, merge_commit_sha="b" * 40)
        self.tools = CiLogTools(self.client, self.repair, read_only_snapshot=self.head)
        self.assertIn("missing source", self.read()["text"])
        self.head["merge_commit_sha"] = "c" * 40
        with self.assertRaises(WorkspaceToolError):
            self.read()

    def test_audit_snapshot_cannot_rebind_the_target_commit(self):
        self.tools = CiLogTools(self.client, self.repair, read_only_snapshot={**self.head, "merge_commit_sha": ""})
        self.head.update(head_sha="b" * 40, merge_commit_sha="")
        with self.assertRaises(WorkspaceToolError):
            self.read()

    def test_identity_changes_before_any_network_download(self):
        for field, value in (("head_ref", "other"), ("repository", "other/project"),
                             ("head_repository", "fork/project"), ("state", "closed"), ("merged", True)):
            with self.subTest(field=field):
                original = self.head[field]
                self.head[field] = value
                with self.assertRaises(WorkspaceToolError):
                    self.read()
                self.head[field] = original
        self.client.runner.run_bounded.assert_not_called()

    def test_head_changed_during_download_does_not_reach_model(self):
        def download(*args, **kwargs):
            self.head["head_sha"] = "b" * 40
            return SimpleNamespace(ok=True, stdout="old private log"), False
        self.client.runner.run_bounded.side_effect = download
        with self.assertRaises(WorkspaceToolError):
            self.read()
        self.assertIsNone(self.tools.cache)

    def test_foreign_snapshot_rejected(self):
        self.snapshot["head_sha"] = "b" * 40
        with self.assertRaises(WorkspaceToolError):
            self.read()
        self.client.runner.run_bounded.assert_not_called()

    def test_job_metadata_is_bound_to_check_commit_and_run(self):
        for field, value in (("id", 99), ("run_id", 99), ("head_sha", "b" * 40),
                             ("status", "in_progress"), ("conclusion", "success"),
                             ("check_run_url", "https://api.github.com/repos/other/project/check-runs/11")):
            with self.subTest(field=field):
                original = self.job[field]
                self.job[field] = value
                with self.assertRaisesRegex(WorkspaceToolError, "metadata"):
                    self.read()
                self.job[field] = original
        self.client.runner.run_bounded.assert_not_called()

    def test_arbitrary_provider_urls_never_execute_or_download(self):
        for url in ("file:///secret", "http://127.0.0.1:8765", "https://evil.test/actions/runs/20/job/30",
                    "https://github.com/other/project/actions/runs/20/job/30",
                    "https://github.com/owner/project/actions/runs/20/job/30?token=x"):
            with self.subTest(url=url):
                self.check["url"] = url
                with self.assertRaises(WorkspaceToolError) as caught:
                    self.read()
                self.assertEqual("ci_log_provider_unavailable", caught.exception.code)
        self.client._api.assert_not_called()
        self.client.runner.run_bounded.assert_not_called()

    def test_unknown_nonfailed_and_commit_status_checks_cannot_fetch_logs(self):
        for change in ({"id": 99}, {"outcome": "passed"}, {"kind": "commit_status"}):
            self.snapshot["checks"] = [{**self.check, **change}]
            with self.subTest(change=change), self.assertRaises(WorkspaceToolError):
                self.read()
        self.client.runner.run_bounded.assert_not_called()

    def test_arguments_rejected_before_network(self):
        for action in ({"operation": "ci_log", "check_id": 11, "url": "https://evil.test"},
                       {"operation": "ci_checks", "offset": -1}, {"operation": "ci_checks", "offset": True},
                       {"operation": "ci_log", "offset": None}):
            with self.subTest(action=action), self.assertRaises(WorkspaceToolError):
                self.tools.execute(action)
        self.client.pull_request_head.assert_not_called()

    def test_invalid_check_ids_never_download(self):
        for value in (True, -1, 0, "11", None):
            with self.subTest(value=value), self.assertRaises(WorkspaceToolError):
                self.tools.execute({"operation": "ci_log", "check_id": value})
        self.client.runner.run_bounded.assert_not_called()

    def test_unavailable_logs_and_transport_errors_are_observations_not_success(self):
        self.client.runner.run_bounded.return_value = (SimpleNamespace(ok=False, stdout="private error"), False)
        with self.assertRaises(WorkspaceToolError) as caught:
            self.read()
        self.assertEqual("ci_log_unavailable", caught.exception.code)
        self.client.runner.run_bounded.side_effect = TimeoutError("private-token")
        with self.assertRaises(WorkspaceToolError) as caught:
            self.read()
        self.assertEqual("ci_observation_unavailable", caught.exception.code)
        self.assertNotIn("private-token", str(caught.exception))

    def test_truncation_is_explicit(self):
        self.client.runner.run_bounded.return_value = (SimpleNamespace(ok=True, stdout="partial"), True)
        result = self.read()
        self.assertTrue(result["truncated"])
        self.assertIsNone(result["next_offset"])

    def test_offsets_outside_snapshot_are_errors(self):
        for action in ({"operation": "ci_checks", "offset": 2}, {"operation": "ci_log", "check_id": 11, "offset": 999}):
            with self.subTest(action=action), self.assertRaises(WorkspaceToolError):
                self.tools.execute(action)

    def test_job_completion_revision_invalidates_log_cache(self):
        self.read()
        self.job["completed_at"] = "2026-09-08T00:01:00Z"
        self.read()
        self.assertEqual(2, self.client.runner.run_bounded.call_count)

    def test_real_loop_observes_logs_without_persisting_content(self):
        actions = iter([{"operation": "ci_checks"}, {"operation": "ci_log", "check_id": 11},
                        {"operation": "finish", "summary": "Missing source; repair requires inspecting the source."}])
        seen, events = [], []
        def infer(messages):
            seen.append(messages)
            return json.dumps(next(actions))
        with tempfile.TemporaryDirectory() as folder, implementation_observer(
                threading.Event(), lambda event, **data: events.append(data)):
            implement_locally("Diagnose failed CI", Path(folder), infer=infer, ci_logs=self.tools)
        observation = json.loads(seen[-1][-1]["content"])["observation"]
        self.assertIn("missing source", observation["result"]["text"])
        self.assertEqual("read_only", observation["effect"])
        self.assertEqual(["ci_checks", "ci_log"], [event["operation"] for event in events])
        self.assertNotIn("missing source", str(events))

    def test_normal_tasks_have_no_ci_capability(self):
        self.assertNotIn("ci_log", json.dumps(action_schema()))
        self.assertIn("ci_log", json.dumps(action_schema(ci_logs=True)))
        actions = iter(['{"operation":"ci_checks"}', '{"operation":"finish","summary":"No attached CI"}'])
        seen = []
        def infer(messages):
            seen.append(messages)
            return next(actions)
        with tempfile.TemporaryDirectory() as folder:
            implement_locally("Inspect", Path(folder), infer=infer)
        self.assertIn("ci_tools_unavailable", seen[-1][-1]["content"])


if __name__ == "__main__":
    unittest.main()
