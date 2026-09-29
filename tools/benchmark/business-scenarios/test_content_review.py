import copy
import unittest

from artifact_catalog import catalog
from content_review import source_digest
from report import summarize


class ContentReviewTest(unittest.TestCase):
    def setUp(self):
        self.plan = catalog()
        files = [{"evidence_file": f"artifact-{i}.png", "sha256": str(i + 1) * 64,
                  **{k: True for k in ("received", "container_valid", "version_name_matches",
                     "save_api_pass", "download_hash_matches")}} for i in range(2)]
        self.turn = {"index": 0, "state": "completed", "turn_id": "turn", "task_id": "task",
                     "reply": "Synthetic output", "elapsed_ms": 1200,
                     "driver_schema": 4, "visual_entry_id": "entry", "rendered": True,
                     "visual_window_focused": True, "visual_capture_stable": True,
                     "timer_observed": True, "timer_stopped": True, "within_latency_target": True,
                     "assessment": {"correct": True, "content_verified": False,
                       "requires_human_review": True, "all_artifacts_present": True,
                       "all_artifacts_verified": True, "artifacts": files}}
        self.report = {"case_id": "A001", "catalog_sha256": self.plan["catalog_sha256"],
                       "device": "SM-T575", "window_key": "test-run", "conversation": "conversation",
                       "turns": [self.turn]}

    def review(self, verdict="pass"):
        return {"schema": 1, "case_id": "A001", "turn_index": 0,
                "source_sha256": source_digest(self.report, self.turn), "verdict": verdict,
                "reviewer": "fixture reviewer", "notes": "Synthetic test, not actual semantic evidence.",
                "checked_artifacts": [{k: item[k] for k in ("evidence_file", "sha256")}
                    for item in self.turn["assessment"]["artifacts"]]}

    def test_explicit_review_changes_summary_without_mutating_source(self):
        original = copy.deepcopy(self.report)
        result = summarize(self.plan, [self.report], [self.review()])
        self.assertEqual(1, result["correct_turns"])
        self.assertEqual(1, result["artifact_content_review_passed"])
        self.assertEqual(0, result["artifact_content_unverified"])
        self.assertEqual(100, result["planned_cases"])
        self.assertEqual(1100, result["planned_turns"])
        self.assertEqual("incomplete", result["overall_status"])
        self.assertEqual(original, self.report)

    def test_known_failure_is_not_merely_unverified_or_overridden_by_old_flag(self):
        self.turn["assessment"]["content_verified"] = True
        review = self.review("fail")
        review["checked_artifacts"] = review["checked_artifacts"][:1]
        result = summarize(self.plan, [self.report], [review])
        self.assertEqual(0, result["correct_turns"])
        self.assertEqual(1, result["artifact_delivery_checks_passed"])
        self.assertEqual(1, result["artifact_content_review_failed"])
        self.assertIn("artifact_content_review_failed", result["failures"][0]["reasons"])

    def test_review_cannot_clear_delivery_or_latency_failure(self):
        self.turn["assessment"]["all_artifacts_present"] = False
        self.turn["within_latency_target"] = False
        result = summarize(self.plan, [self.report], [self.review()])
        self.assertEqual(0, result["correct_turns"])
        self.assertIn("artifact_delivery_incomplete_or_unverified", result["failures"][0]["reasons"])
        self.assertIn("latency_target", result["failures"][0]["reasons"])

    def test_any_changed_turn_or_run_evidence_invalidates_review(self):
        for owner, key, value in ((self.turn, "reply", "changed"), (self.turn, "task_id", "other"),
                                  (self.turn, "elapsed_ms", 1), (self.report, "device", "other"),
                                  (self.report, "window_key", "other"), (self.report, "conversation", "other")):
            review = self.review()
            before = owner[key]
            owner[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                summarize(self.plan, [self.report], [review])
            owner[key] = before

    def test_appending_new_turn_does_not_invalidate_previous_review(self):
        review = self.review()
        later = copy.deepcopy(self.turn)
        later.update(index=1, turn_id="later-turn", task_id="later-task")
        self.report["turns"].append(later)
        result = summarize(self.plan, [self.report], [review])
        self.assertEqual(2, result["completed_turns"])
        self.assertEqual(1, result["artifact_content_review_passed"])
        self.assertEqual(1, result["artifact_content_unverified"])
        self.assertEqual(1100, result["planned_turns"])

    def test_partial_duplicate_unknown_and_wrong_hash_coverage_are_rejected(self):
        for coverage in ([], self.review()["checked_artifacts"][:1],
                         [self.review()["checked_artifacts"][0]] * 2,
                         [{"evidence_file": "unknown", "sha256": "1" * 64}],
                         [{"evidence_file": "artifact-0.png", "sha256": "9" * 64}]):
            review = self.review()
            review["checked_artifacts"] = coverage
            with self.subTest(coverage=coverage), self.assertRaises(ValueError):
                summarize(self.plan, [self.report], [review])

    def test_duplicate_unobserved_and_timeout_reviews_are_rejected(self):
        review = self.review()
        with self.assertRaises(ValueError):
            summarize(self.plan, [self.report], [review, review])
        review["turn_index"] = 1
        with self.assertRaises(ValueError):
            summarize(self.plan, [self.report], [review])
        self.turn["state"] = "observation_timeout"
        with self.assertRaises(ValueError):
            summarize(self.plan, [self.report], [self.review()])

    def test_absent_reviews_preserve_old_behavior_and_invalid_roots_fail(self):
        self.assertEqual(0, summarize(self.plan, [self.report])["correct_turns"])
        for reviews in ({}, "", {"verdict": "pass"}):
            with self.subTest(reviews=reviews), self.assertRaises(ValueError):
                summarize(self.plan, [self.report], reviews)

    def test_unattributed_or_malformed_reviews_are_rejected(self):
        for field, value in (("reviewer", ""), ("notes", " "), ("verdict", "maybe"),
                             ("schema", True), ("turn_index", False), ("checked_artifacts", "all")):
            review = self.review()
            review[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                summarize(self.plan, [self.report], [review])

    def test_missing_identity_and_artifact_hash_cannot_be_approved(self):
        self.report["conversation"] = ""
        with self.assertRaises(ValueError):
            summarize(self.plan, [self.report], [self.review()])
        self.report["conversation"] = "conversation"
        self.turn["assessment"]["artifacts"][0]["sha256"] = ""
        with self.assertRaises(ValueError):
            summarize(self.plan, [self.report], [self.review()])

    def test_text_only_artifact_turn_uses_reply_binding_not_fake_files(self):
        self.report["case_id"] = "A044"
        self.turn["index"] = 7
        self.turn["assessment"].update(artifacts=[], unexpected_file_count=0)
        review = self.review()
        review.update(case_id="A044", turn_index=7)
        self.assertEqual(1, summarize(self.plan, [self.report], [review])["correct_turns"])
        self.turn["reply"] = "changed"
        with self.assertRaises(ValueError):
            summarize(self.plan, [self.report], [review])
