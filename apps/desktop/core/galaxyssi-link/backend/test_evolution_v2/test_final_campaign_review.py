"""A narrow model response cannot silently discard negative final-goal evidence."""
import importlib.util
import json
from pathlib import Path
import unittest


PATH = Path(__file__).resolve().parents[6] / "tools/testing/verify_local_campaign_completion.py"
SPEC = importlib.util.spec_from_file_location("verify_local_campaign_completion", PATH)
review = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(review)


class FinalCampaignReviewTests(unittest.TestCase):
    def response(self, verdict="pass"):
        return {"assessments": {"original-goal": {"verdict": verdict, "evidence": "Actual observed requirement evidence"}}}

    def test_schema_requires_original_goal_without_ambiguous_global_findings(self):
        schema = review.final_review_schema()
        self.assertEqual(["assessments"], schema["required"])
        self.assertEqual(["original-goal"], schema["properties"]["assessments"]["required"])
        self.assertFalse(schema["additionalProperties"])

    def test_row_verdict_drives_final_status_without_dropping_failures(self):
        for verdict in ("pass", "fail", "inconclusive"):
            with self.subTest(verdict=verdict):
                result = review.parse_final_review(json.dumps(self.response(verdict)))
                self.assertEqual(verdict, result["verdict"])
                self.assertEqual(verdict != "pass", bool(result["findings"]))

    def test_unexpected_findings_are_rejected_not_silently_removed(self):
        value = self.response()
        value["findings"] = ["Unresolved issue"]
        with self.assertRaises(ValueError):
            review.parse_final_review(json.dumps(value))

    def test_missing_foreign_and_empty_evidence_are_rejected(self):
        for value in ({"assessments": {}}, {"assessments": {"other": {"verdict": "pass", "evidence": "Fact"}}},
                {"assessments": {"original-goal": {"verdict": "pass", "evidence": ""}}}):
            with self.subTest(value=value), self.assertRaises(ValueError):
                review.parse_final_review(json.dumps(value))

    def test_duplicate_verdict_cannot_overwrite_failure_with_pass(self):
        with self.assertRaises(ValueError):
            review.parse_final_review('{"assessments":{"original-goal":{"verdict":"fail","verdict":"pass","evidence":"Fact"}}}')
