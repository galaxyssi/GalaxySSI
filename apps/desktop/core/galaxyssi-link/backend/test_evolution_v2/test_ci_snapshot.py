from __future__ import annotations

import copy
import unittest

from evolution_v2.ci_snapshot import CiObservationError, observe, pull_request, target

URL = "https://github.com/galaxyssi/GalaxySSI/pull/42"
SHA = "a" * 40


def raw_pr():
    return {"number": 42, "state": "open", "merged": False,
            "head": {"sha": SHA, "ref": "evolution/test", "repo": {"full_name": "galaxyssi/GalaxySSI"}},
            "base": {"ref": "main", "repo": {"full_name": "galaxyssi/GalaxySSI"}}}


def check(number=1, conclusion="success", status="completed"):
    return {"id": number, "name": "build", "head_sha": SHA, "status": status,
            "conclusion": conclusion, "output": {"summary": "diagnostics"}}


class Client:
    def __init__(self, checks=None, statuses=None):
        self.pr = raw_pr()
        self.after = None
        self.runs = [{"total_count": len(checks or []), "check_runs": checks or []}]
        self.statuses = [statuses or []]
        self.calls = []

    def _api(self, args):
        self.calls.append(args)
        if "check-runs" in args[-1]:
            return copy.deepcopy(self.runs)
        if args[-1].endswith("/statuses?per_page=100"):
            return copy.deepcopy(self.statuses)
        return copy.deepcopy(self.after if self.after and len(self.calls) > 1 else self.pr)


class CiSnapshotTests(unittest.TestCase):
    def test_head_bound_paginated_requests(self):
        client = Client([check()])
        result = observe(client, URL)
        self.assertEqual("passed", result["status"])
        self.assertEqual(SHA, result["head_sha"])
        self.assertEqual(("--paginate", "--slurp"), client.calls[1][:2])
        self.assertIn(f"commits/{SHA}/", client.calls[1][-1])
        self.assertEqual(4, len(client.calls))

    def test_no_checks_is_not_success(self):
        self.assertEqual("pending", observe(Client(), URL)["status"])

    def test_unknown_conclusion_is_not_success(self):
        self.assertEqual("pending", observe(Client([check(conclusion="new-status")]), URL)["status"])

    def test_failure_waits_for_pending_jobs(self):
        result = observe(Client([check(conclusion="failure"), check(2, status="in_progress")]), URL)
        self.assertEqual(("pending", 1, 1), (result["status"], result["failed"], result["pending"]))

    def test_completed_failure_is_repairable(self):
        for conclusion in ("failure", "timed_out", "cancelled", "action_required", "startup_failure", "stale"):
            with self.subTest(conclusion=conclusion):
                self.assertEqual("failed", observe(Client([check(conclusion=conclusion)]), URL)["status"])

    def test_pr_change_during_observation_rejected(self):
        for field, value in (("sha", "b" * 40), ("ref", "another-branch")):
            with self.subTest(field=field):
                client = Client([check()])
                client.after = raw_pr()
                client.after["head"][field] = value
                with self.assertRaises(CiObservationError):
                    observe(client, URL)

    def test_wrong_head_check_rejected(self):
        item = check()
        item["head_sha"] = "b" * 40
        with self.assertRaises(CiObservationError):
            observe(Client([item]), URL)

    def test_partial_or_duplicate_pages_rejected(self):
        for pages in ([], [{"check_runs": []}], [{"total_count": 2, "check_runs": [check()]}],
                      [{"total_count": 2, "check_runs": [check(), check()]}]):
            with self.subTest(pages=pages):
                client = Client()
                client.runs = pages
                with self.assertRaises(CiObservationError):
                    observe(client, URL)

    def test_duplicate_names_in_different_suites_preserved(self):
        result = observe(Client([check(1), check(2, conclusion="failure")]), URL)
        self.assertEqual("failed", result["status"])
        self.assertEqual(2, len(result["checks"]))

    def test_multiple_check_pages(self):
        client = Client()
        client.runs = [{"total_count": 2, "check_runs": [check(1)]}, {"total_count": 2, "check_runs": [check(2)]}]
        self.assertEqual("passed", observe(client, URL)["status"])

    def test_latest_legacy_status_wins(self):
        statuses = [{"context": "legacy", "id": 5, "state": "success"},
                    {"context": "legacy", "id": 4, "state": "failure"}]
        result = observe(Client(statuses=statuses), URL)
        self.assertEqual("passed", result["status"])
        self.assertEqual(1, len(result["checks"]))

    def test_legacy_status_failure_is_preserved(self):
        self.assertEqual("failed", observe(Client([check()], [{"context": "external", "id": 9, "state": "error"}]), URL)["status"])

    def test_closed_pr_does_not_request_checks(self):
        client = Client()
        client.pr.update(state="closed")
        self.assertEqual("closed", observe(client, URL)["status"])
        self.assertEqual(1, len(client.calls))

    def test_merged_pr_still_verifies_exact_head_checks(self):
        for checks, passed in (([check()], True), ([], False), ([check(conclusion="failure")], False)):
            with self.subTest(passed=passed, checks=checks):
                client = Client(checks)
                client.pr.update(state="closed", merged=True, merge_commit_sha="b" * 40)
                result = observe(client, URL)
                self.assertEqual("merged", result["status"])
                self.assertEqual(passed, result["passed"])
                self.assertEqual("b" * 40, result["merge_commit_sha"])
                self.assertEqual(4, len(client.calls))

    def test_merge_without_commit_evidence_is_rejected(self):
        client = Client([check()])
        client.pr.update(state="closed", merged=True)
        with self.assertRaises(CiObservationError):
            observe(client, URL)

    def test_malformed_metadata_rejected(self):
        for mutation in (lambda pr: pr.update(number=43), lambda pr: pr["head"].update(repo=[]),
                         lambda pr: pr["base"].update(ref=None), lambda pr: pr["head"].update(sha="short")):
            client = Client()
            mutation(client.pr)
            with self.assertRaises(CiObservationError):
                pull_request(client, URL)

    def test_unsafe_branch_rejected(self):
        for branch in ("--all", "x\ny", "../main", "x@{1}", "x.lock", "x y", "x//y", "x\\y"):
            with self.subTest(branch=branch):
                client = Client()
                client.pr["head"]["ref"] = branch
                with self.assertRaises(CiObservationError):
                    pull_request(client, URL)

    def test_unrelated_urls_rejected(self):
        for url in ("42", "https://evil.test/x/y/pull/42", URL + "?q=x", "https://github.com/x/y/pull/0"):
            with self.assertRaises(CiObservationError):
                target(url)

    def test_diagnostics_redacted_and_fingerprint_stable(self):
        item = check()
        item["output"]["summary"] = "Authorization: Bearer secret-secret-secret"
        a = observe(Client([item]), URL)
        self.assertNotIn("secret-secret", str(a))
        b = observe(Client([check()]), URL)
        self.assertEqual(a["fingerprint"], b["fingerprint"])

    def test_invalid_check_output_rejected(self):
        item = check()
        item["output"] = ["unexpected"]
        with self.assertRaises(CiObservationError):
            observe(Client([item]), URL)
