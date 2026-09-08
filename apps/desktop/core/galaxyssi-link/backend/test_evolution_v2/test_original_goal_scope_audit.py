import json
import unittest
from unittest.mock import Mock

from agent_task_dag import TaskDagError
from evolution_v2.original_goal_scope_audit import audit_scopes, validate_audit


class OriginalGoalScopeAuditTests(unittest.TestCase):
    def setUp(self):
        self.requirements = {"a": "Keep existing file contents.", "b": "Title or body says Recovery."}
        self.catalog = {key: {"value": "Private contents", "description": key} for key in ("paths", "before", "after", "title", "body")}
        self.scopes = {"a": {"field_ids": ["paths"]}, "b": {"field_ids": ["title", "body"]}}
        self.result = {"clauses": {
            "a": {"sufficient": False, "missing_field_ids": ["before", "after"], "evidence": "Paths do not show preservation"},
            "b": {"sufficient": True, "missing_field_ids": [], "evidence": "Both OR fields are available; not both predicates must hold"}}}

    def test_missing_fields_and_joint_alternatives_are_retained_without_a_verdict(self):
        result = validate_audit(json.dumps(self.result), self.requirements, self.scopes, self.catalog)
        self.assertEqual(["before", "after"], result["a"]["missing_field_ids"])
        self.assertTrue(result["b"]["sufficient"])
        self.assertNotIn("verdict", result["b"])

    def test_audit_is_value_blind_and_ignores_selector_explanations(self):
        infer = Mock(return_value=json.dumps(self.result))
        self.scopes["a"]["reason"] = "Untrusted selector says pass"
        observations = []
        audit_scopes("Original goal", self.requirements, self.scopes, self.catalog, infer, observations.append)
        sent = json.dumps(infer.call_args.args[0])
        self.assertNotIn("Private contents", sent)
        self.assertNotIn("Untrusted selector", sent)
        self.assertEqual([json.dumps(self.result)], observations)

    def test_audit_requires_exact_clause_coverage(self):
        del self.result["clauses"]["a"]
        with self.assertRaises(TaskDagError):
            validate_audit(json.dumps(self.result), self.requirements, self.scopes, self.catalog)

    def test_foreign_duplicate_selected_or_nontext_missing_fields_are_rejected(self):
        for fields in (["foreign"], ["before", "before"], ["paths"], [False]):
            with self.subTest(fields=fields), self.assertRaises(TaskDagError):
                self.result["clauses"]["a"]["missing_field_ids"] = fields
                validate_audit(json.dumps(self.result), self.requirements, self.scopes, self.catalog)

    def test_cannot_claim_sufficiency_with_missing_or_empty_selected_fields(self):
        self.result["clauses"]["a"]["sufficient"] = True
        with self.assertRaises(TaskDagError):
            validate_audit(json.dumps(self.result), self.requirements, self.scopes, self.catalog)
        self.result["clauses"]["a"]["missing_field_ids"] = []
        self.scopes["a"]["field_ids"] = []
        with self.assertRaises(TaskDagError):
            validate_audit(json.dumps(self.result), self.requirements, self.scopes, self.catalog)

    def test_missing_evidence_outside_directory_remains_insufficient(self):
        self.result["clauses"]["a"]["missing_field_ids"] = []
        self.result["clauses"]["a"]["evidence"] = "No execution receipt is available in the directory"
        self.assertFalse(validate_audit(json.dumps(self.result), self.requirements, self.scopes, self.catalog)["a"]["sufficient"])

    def test_malformed_raw_audit_is_observed_before_rejection(self):
        observations = []
        with self.assertRaises(TaskDagError):
            audit_scopes("Goal", self.requirements, self.scopes, self.catalog,
                         Mock(return_value='{"clauses":{}}'), observations.append)
        self.assertEqual(['{"clauses":{}}'], observations)

    def test_oversized_audit_is_not_truncated_or_sent(self):
        infer = Mock()
        with self.assertRaises(TaskDagError):
            audit_scopes("x" * 131073, self.requirements, self.scopes, self.catalog, infer, Mock())
        infer.assert_not_called()
