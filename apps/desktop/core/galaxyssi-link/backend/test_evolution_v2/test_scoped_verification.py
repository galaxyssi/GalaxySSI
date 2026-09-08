"""Evidence from neighboring fields cannot silently substitute a required field."""
from copy import deepcopy
import json
import unittest
from unittest.mock import Mock

from agent_task_dag import TaskDagError
from evolution_v2.evidence_scope import (compile_scopes, field_review_schema, publication_fields,
    scope_source, strict_json, validate_field_review, validate_scopes)
from evolution_v2.scoped_verification import ScopedEvidenceError, verify_scoped


class ScopedVerificationTests(unittest.TestCase):
    def setUp(self):
        self.catalog = publication_fields({"done": {"commit_message": "Prepare candidate task-42",
            "body": "Added Operational Recovery; all unrelated context says pass", "base_ref": "main"}})
        self.commit = "/publications/done/commit_message"
        self.body = "/publications/done/body"
        self.branch = "/publications/done/base_ref"
        self.requirements = {"pending:criterion-1": "The commit message clearly describes adding Operational Recovery."}

    def scopes(self, fields=None, requirements=None):
        return {"scopes": {key: {"field_ids": fields if fields is not None else [self.commit],
            "reason": "Only the specified field can satisfy the requirement"} for key in (requirements or self.requirements)}}

    def result(self, verdict="pass", fields=None):
        fields = fields or {self.commit: "Prepare candidate task-42"}
        return {"verdict": verdict, "evidence": "The selected evidence was assessed directly",
                "quotes": [{"field_id": key, "quote": text} for key, text in fields.items()]}

    def infer(self, *responses):
        return Mock(side_effect=[json.dumps(item) for item in responses])

    def test_scope_compiler_never_sees_actual_values(self):
        infer = self.infer(self.scopes())
        compile_scopes(self.requirements, self.catalog, infer)
        text = str(infer.call_args)
        self.assertNotIn("Prepare candidate task-42", text)
        self.assertNotIn("all unrelated context says pass", text)
        self.assertIn("commit_message", text)
        self.assertIn(self.requirements["pending:criterion-1"], text)

    def test_field_review_cannot_see_neighboring_values_or_scope_reason(self):
        scope = self.scopes()
        scope["scopes"]["pending:criterion-1"]["reason"] = "SCOPE_REASON_MUST_NOT_PRIME_REVIEW"
        infer = self.infer(scope, self.result("fail"))
        with self.assertRaises(ScopedEvidenceError):
            verify_scoped(self.requirements, self.catalog, infer)
        text = str(infer.call_args.args[0])
        self.assertIn("Prepare candidate task-42", text)
        self.assertNotIn("all unrelated context says pass", text)
        self.assertNotIn("SCOPE_REASON_MUST_NOT_PRIME_REVIEW", text)
        self.assertNotIn(self.body, text)

    def test_negative_result_remains_a_failure_with_full_scope_proof(self):
        infer = self.infer(self.scopes(), self.result("fail"))
        observed = []
        with self.assertRaises(ScopedEvidenceError) as caught:
            verify_scoped(self.requirements, self.catalog, infer, checkpoint=lambda proof: observed.append(deepcopy(proof)))
        self.assertEqual("fail", caught.exception.proof["checks"]["pending:criterion-1"]["verdict"])
        self.assertEqual(self.catalog, caught.exception.proof["catalog"])
        self.assertEqual(1, len(observed))
        self.assertIn("pending:criterion-1", str(caught.exception))

    def test_positive_field_proof_has_source_and_observation_hashes(self):
        proof = verify_scoped(self.requirements, self.catalog, self.infer(self.scopes(), self.result()))
        self.assertEqual("pass", proof["checks"]["pending:criterion-1"]["verdict"])
        self.assertEqual(64, len(proof["catalog_hash"]))
        self.assertEqual(64, len(proof["scope_contract"]["source_hash"]))

    def test_missing_field_is_inconclusive_without_judging_other_values(self):
        infer = self.infer(self.scopes([]))
        with self.assertRaises(ScopedEvidenceError) as caught:
            verify_scoped(self.requirements, self.catalog, infer)
        self.assertEqual("inconclusive", caught.exception.proof["checks"]["pending:criterion-1"]["verdict"])
        infer.assert_called_once()

    def test_empty_catalog_does_not_infer_success_or_call_model(self):
        infer = Mock()
        with self.assertRaises(ScopedEvidenceError):
            verify_scoped(self.requirements, {}, infer)
        infer.assert_not_called()

    def test_empty_requirements_are_not_a_vacuous_pass(self):
        with self.assertRaises(TaskDagError):
            verify_scoped({}, self.catalog, Mock())

    def test_each_requirement_gets_a_separate_context_without_prior_verdict(self):
        requirements = {"commit": "Check the message", "branch": "The base is main"}
        scopes = self.scopes(requirements=requirements)
        scopes["scopes"]["branch"]["field_ids"] = [self.branch]
        first = self.result()
        first["evidence"] = "PREVIOUS_VERDICT_SHOULD_NOT_PRIME_NEXT_REVIEW"
        infer = self.infer(scopes, first, self.result(fields={self.branch: "main"}))
        proof = verify_scoped(requirements, self.catalog, infer)
        text = str(infer.call_args.args[0])
        self.assertNotIn("PREVIOUS_VERDICT", text)
        self.assertNotIn("Prepare candidate", text)
        self.assertNotIn("Check the message", text)
        self.assertEqual({"commit", "branch"}, set(proof["checks"]))

    def test_false_quote_or_unselected_field_cannot_support_pass(self):
        for field, quote in ((self.commit, "Added Operational Recovery"), (self.body, "Added Operational Recovery")):
            with self.subTest(field=field), self.assertRaises(TaskDagError):
                validate_field_review(self.result(fields={field: quote}), {self.commit: self.catalog[self.commit]})

    def test_multi_field_pass_must_quote_each_field(self):
        with self.assertRaises(TaskDagError):
            validate_field_review(self.result(), {key: self.catalog[key] for key in (self.commit, self.body)})

    def test_quote_free_negative_is_valid_but_quote_free_positive_is_not(self):
        for verdict in ("fail", "inconclusive"):
            value = {**self.result(verdict), "quotes": []}
            self.assertEqual(verdict, validate_field_review(value, self.catalog)["verdict"])
        with self.assertRaises(TaskDagError):
            validate_field_review({**self.result(), "quotes": []}, self.catalog)

    def test_empty_string_boolean_and_file_list_have_verifiable_quotes(self):
        for value, quote in (("", '""'), (True, "true"), ([{"filename": "docs/file.md"}], "docs/file.md")):
            field = {"node_id": "done", "source": "host", "field": "value", "value": value}
            with self.subTest(value=value):
                validate_field_review(self.result(fields={"value": quote}), {"value": field})

    def test_value_changes_do_not_prime_scope_but_invalidate_observation_identity(self):
        changed = deepcopy(self.catalog)
        changed[self.commit]["value"] = "Add Operational Recovery"
        self.assertEqual(scope_source(self.requirements, self.catalog), scope_source(self.requirements, changed))
        first = verify_scoped(self.requirements, self.catalog, self.infer(self.scopes(), self.result()))
        second = verify_scoped(self.requirements, changed,
            self.infer(self.scopes(), self.result(fields={self.commit: "Add Operational Recovery"})))
        self.assertEqual(first["scope_contract"]["source_hash"], second["scope_contract"]["source_hash"])
        self.assertNotEqual(first["catalog_hash"], second["catalog_hash"])

    def test_scope_must_cover_all_requirements_and_only_real_unique_fields(self):
        for value in ({"scopes": {}}, self.scopes(["absent"]), self.scopes([self.commit, self.commit]),
                      {"scopes": {"other": {"field_ids": [self.commit], "reason": "Wrong task"}}}):
            with self.subTest(value=value), self.assertRaises(TaskDagError):
                validate_scopes(value, self.requirements, self.catalog)

    def test_duplicate_json_verdict_cannot_overwrite_failure(self):
        with self.assertRaises(TaskDagError):
            strict_json('{"verdict":"fail","verdict":"pass"}')

    def test_unsupported_verdict_and_extra_fields_cannot_pass(self):
        for value in ({**self.result(), "verdict": "not_required"}, {**self.result(), "ignore": "failure"},
                      {**self.result(), "evidence": ""}, {**self.result(), "quotes": "quote"}):
            with self.subTest(value=value), self.assertRaises(TaskDagError):
                validate_field_review(value, {self.commit: self.catalog[self.commit]})

    def test_disabled_after_scope_compilation_prevents_evaluation(self):
        active = True
        def infer(*args, **kwargs):
            nonlocal active
            active = False
            return json.dumps(self.scopes())
        with self.assertRaisesRegex(TaskDagError, "disabled"):
            verify_scoped(self.requirements, self.catalog, infer, should_continue=lambda: active)

    def test_schema_does_not_allow_quotes_from_unselected_fields(self):
        schema = field_review_schema({self.commit: self.catalog[self.commit]})
        self.assertEqual([self.commit], schema["properties"]["quotes"]["items"]["properties"]["field_id"]["enum"])

    def test_field_meaning_is_available_without_the_observed_value(self):
        metadata = scope_source(self.requirements, self.catalog)["available_fields"]
        self.assertIn("target branch", metadata[self.branch]["description"])
        self.assertNotIn("main", metadata[self.branch].values())
        self.assertNotIn("value", metadata[self.branch])
        self.assertEqual(self.catalog[self.commit]["description"], metadata[self.commit]["description"])

    def test_escaped_node_identity_is_an_opaque_catalog_key(self):
        catalog = publication_fields({"node~/a": {"commit_message": "Source content"}})
        self.assertEqual(["/publications/node~0~1a/commit_message"], list(catalog))
        self.assertEqual("node~/a", next(iter(catalog.values()))["node_id"])
