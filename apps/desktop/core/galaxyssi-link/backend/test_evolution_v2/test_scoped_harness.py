"""A correct top-level verdict for the wrong reason is not a passing regression."""
import importlib.util
from pathlib import Path
import unittest


PATH = Path(__file__).resolve().parents[6] / "tools/testing/verify_local_evidence_scopes.py"
SPEC = importlib.util.spec_from_file_location("verify_local_evidence_scopes", PATH)
harness = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(harness)


class ScopedHarnessTests(unittest.TestCase):
    def fixture(self, failed_field="commit_message"):
        catalog = {field: {"field": field} for field in ("title", "body", "commit_message")}
        row = {"name": "compound-publication", "expected": "fail", "expected_fields": list(catalog),
               "proof": {"scope_contract": {"scopes": {"criterion-1": {"field_ids": list(catalog)}}},
                         "checks": {"criterion-1": {"verdict": "fail"}},
                         "compound": {"criterion-1": {"reviews": [{
                             "guard": {"field_ids": [failed_field]}, "result": {"verdict": "fail"}}]}}}}
        return row, catalog

    def test_wrong_field_failure_does_not_count_as_counterexample_success(self):
        row, catalog = self.fixture("title")
        self.assertFalse(harness.score_case(row, catalog)["passed"])

    def test_expected_field_failure_is_required(self):
        row, catalog = self.fixture()
        self.assertTrue(harness.score_case(row, catalog)["passed"])

    def test_expected_failure_cannot_hide_an_additional_false_rejection(self):
        row, catalog = self.fixture()
        row["proof"]["compound"]["criterion-1"]["reviews"].append({
            "guard": {"field_ids": ["title"]}, "result": {"verdict": "fail"}})
        self.assertFalse(harness.score_case(row, catalog)["passed"])
        self.assertTrue(row["failure_binding_verified"])
        self.assertEqual(1, len(row["unexpected_guard_failures"]))

    def test_invalid_response_is_not_semantic_rejection(self):
        row, catalog = self.fixture()
        row["error"] = "Scoped evidence review is invalid for criterion-1: false quote"
        self.assertFalse(harness.score_case(row, catalog)["passed"])

    def test_an_or_positive_control_cannot_pass_with_a_fail_verdict(self):
        row, catalog = self.fixture()
        row.update(name="alternative-destination", expected="pass")
        self.assertFalse(harness.score_case(row, catalog)["passed"])
