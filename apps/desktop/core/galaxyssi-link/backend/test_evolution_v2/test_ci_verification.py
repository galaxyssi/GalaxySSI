from __future__ import annotations

import copy
import unittest

from evolution_v2.ci_verification import fingerprint, verification_issue
from test_evolution_v2.test_ci_snapshot import Client, SHA, URL, check, commit_snapshot, observe


class CiVerificationTests(unittest.TestCase):
    def test_recompute_not_a_cached_verification_boolean(self):
        snapshot = commit_snapshot()
        snapshot["verification_passed"] = False
        self.assertEqual("", verification_issue(snapshot))
        snapshot = commit_snapshot(conclusion="skipped")
        snapshot["verification_passed"] = True
        self.assertTrue(verification_issue(snapshot))

    def test_missing_malformed_and_partial_evidence_is_not_verification(self):
        original = commit_snapshot()
        for patch in ({"checks": []}, {"checks": None}, {"checks": [{}]},
                      {"checks": [None]}, {"head_sha": "short"}, {"repository": "other"},
                      {"passed": 1}, {"failed": False}, {"pending": -1}, {"pending": 1},
                      {"fingerprint": "green"}, {"status": "pending"}):
            with self.subTest(patch=patch):
                self.assertTrue(verification_issue({**original, **patch}))
        self.assertTrue(verification_issue(None))
        self.assertTrue(verification_issue({"passed": True}))

    def test_check_identity_status_and_commit_are_all_required(self):
        original = commit_snapshot()
        for patch in ({"id": True}, {"id": 0}, {"kind": "unknown"}, {"name": " "},
                      {"head_sha": "b" * 40}, {"status": "in_progress"}, {"status": None},
                      {"outcome": "pending"}, {"conclusion": "neutral"}, {"conclusion": "skipped"}):
            with self.subTest(patch=patch):
                snapshot = copy.deepcopy(original)
                snapshot["checks"][0].update(patch)
                snapshot["fingerprint"] = fingerprint(SHA, snapshot["checks"])
                self.assertTrue(verification_issue(snapshot))

    def test_commit_and_repository_cannot_be_rebound(self):
        snapshot = commit_snapshot()
        self.assertEqual("", verification_issue(snapshot, repository="galaxyssi/GalaxySSI", sha=SHA))
        self.assertTrue(verification_issue(snapshot, repository="another/repo", sha=SHA))
        self.assertTrue(verification_issue(snapshot, sha="b" * 40))

    def test_tampered_content_requires_new_observation_fingerprint(self):
        snapshot = commit_snapshot()
        snapshot["checks"][0]["id"] += 1
        self.assertIn("fingerprint", verification_issue(snapshot))

    def test_duplicate_identity_or_legacy_context_is_not_complete_evidence(self):
        for duplicate_context in (False, True):
            client = Client(statuses=[{"context": "external", "id": 7, "state": "success"}])
            snapshot = observe(client, URL)
            extra = copy.deepcopy(snapshot["checks"][0])
            if duplicate_context:
                extra["id"] += 1
            snapshot["checks"].append(extra)
            snapshot["fingerprint"] = fingerprint(SHA, snapshot["checks"])
            self.assertIn("duplicated", verification_issue(snapshot))

    def test_same_names_in_distinct_check_runs_are_not_deduplicated(self):
        snapshot = observe(Client([check(1), check(2)]), URL)
        self.assertEqual("", verification_issue(snapshot))
        self.assertEqual(2, len(snapshot["checks"]))

    def test_row_order_and_diagnostic_text_do_not_change_verification(self):
        snapshot = observe(Client([check(1), check(2)]), URL)
        snapshot["checks"].reverse()
        snapshot["checks"][0]["summary"] = "updated diagnostic only"
        self.assertEqual("", verification_issue(snapshot))
