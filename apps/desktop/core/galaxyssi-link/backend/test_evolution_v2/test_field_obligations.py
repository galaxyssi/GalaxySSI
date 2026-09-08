"""Compound requirements cannot borrow evidence from a neighboring field."""
from copy import deepcopy
import json
import unittest
from unittest.mock import Mock

from agent_task_dag import TaskDagError
from evolution_v2.evidence_scope import publication_fields
from evolution_v2.field_obligations import compile_obligations, parse_obligations, source_tokens, validate_obligations
from evolution_v2.scoped_verification import ScopedEvidenceError, verify_scoped


class FieldObligationTests(unittest.TestCase):
    def setUp(self):
        self.requirement = "The title is English and the commit describes the change."
        self.catalog = publication_fields({"done": {"title": "Add recovery", "commit_message": "Prepare task-42"}})
        self.title = "/publications/done/title"
        self.commit = "/publications/done/commit_message"
        self.guard = {"source_quote": "the commit describes the change", "field_ids": [self.commit]}
        self.guards = {"guards": [self.guard]}
        self.admission = {"valid": True, "evidence": "The commit clause is independently necessary"}
        self.scopes = {"scopes": {"criterion": {"field_ids": list(self.catalog), "reason": "Both fields are required"}}}

    def infer(self, *values):
        return Mock(side_effect=[json.dumps(self.compiled(value["guards"]) if set(value) == {"guards"} else value)
                                 for value in values])

    def compiled(self, guards):
        rows = {}
        for key in self.catalog:
            guard = next((guard for guard in guards if key in guard["field_ids"]), None)
            if guard:
                tokens = source_tokens(self.requirement)
                position = self.requirement.index(guard["source_quote"])
                start = next(index for index, token in enumerate(tokens) if token.start() == position)
                end = next(index + 1 for index, token in enumerate(tokens)
                           if token.end() == position + len(guard["source_quote"]))
                rows[key] = {"classification": "necessary", "start": start, "end": end,
                             "field_ids": guard["field_ids"], "reason": "Unconditional source clause"}
            else:
                rows[key] = {"classification": "joint_only", "start": None, "end": None,
                             "field_ids": [], "reason": "Requires joint assessment"}
        return {"assessments": rows}

    def result(self, verdict, fields=None):
        fields = fields or {self.commit: "Prepare task-42"}
        return {"verdict": verdict, "evidence": "Observed field content", "quotes": [
            {"field_id": key, "quote": value} for key, value in fields.items()]}

    def test_guards_and_necessity_review_never_see_candidate_values(self):
        infer = self.infer(self.guards, self.admission)
        proof = compile_obligations(self.requirement, self.catalog, infer, lambda: None)
        self.assertEqual(self.guards["guards"], proof["guards"])
        for call in infer.call_args_list:
            self.assertNotIn("Prepare task-42", str(call.args))
            self.assertNotIn("Add recovery", str(call.args))
            self.assertIn(self.requirement, str(call.args))

    def test_independent_review_does_not_receive_compiler_explanations(self):
        value = self.compiled([self.guard])
        for row in value["assessments"].values():
            row["reason"] = "PRIVATE-COMPILER-REASON"
        infer = self.infer(value, self.admission)
        compile_obligations(self.requirement, self.catalog, infer, lambda: None)
        self.assertNotIn("PRIVATE-COMPILER-REASON", str(infer.call_args.args))
        self.assertIn("CONDITION IS FALSE", str(infer.call_args.args))
        self.assertNotIn("source_tokens", str(infer.call_args.args))
        self.assertEqual(["evidence", "valid"], infer.call_args.kwargs["response_schema"]["required"])

    def test_all_guards_are_observed_even_after_an_earlier_failure(self):
        guards = {"guards": [{"source_quote": "The title is English", "field_ids": [self.title]}, self.guard]}
        infer = self.infer(self.scopes, guards, self.admission,
                           self.result("fail", {self.title: "Add recovery"}), self.result("fail"))
        with self.assertRaises(ScopedEvidenceError) as raised:
            verify_scoped({"criterion": self.requirement}, self.catalog, infer)
        reviews = raised.exception.proof["compound"]["criterion"]["reviews"]
        self.assertEqual(2, len(reviews))
        self.assertEqual([self.commit], reviews[-1]["guard"]["field_ids"])
        self.assertEqual(5, infer.call_count)

    def test_invalid_source_quotes_and_field_subsets_are_rejected(self):
        for guard in ({**self.guard, "source_quote": "Translated invented requirement"},
                      {**self.guard, "source_quote": self.requirement},
                      {**self.guard, "source_quote": ""},
                      {**self.guard, "field_ids": []},
                      {**self.guard, "field_ids": ["missing"]},
                      {**self.guard, "field_ids": list(self.catalog)},
                      {**self.guard, "field_ids": [self.commit, self.commit]}):
            with self.subTest(guard=guard), self.assertRaises(TaskDagError):
                validate_obligations({"guards": [guard]}, self.requirement, self.catalog)

    def test_duplicate_and_unknown_obligation_fields_are_rejected(self):
        for value in ({"guards": [self.guard, self.guard]}, {"guards": [{**self.guard, "verdict": "pass"}]},
                      {"guards": "not an array"}, {"guards": [], "complete": True}):
            with self.subTest(value=value), self.assertRaises(TaskDagError):
                validate_obligations(value, self.requirement, self.catalog)

    def test_necessity_rejection_does_not_add_an_extra_requirement(self):
        rejection = {"valid": False, "evidence": "The clause is an OR alternative"}
        infer = self.infer(self.guards, rejection, self.guards, rejection)
        with self.assertRaisesRegex(TaskDagError, "preserve the original requirement"):
            compile_obligations(self.requirement, self.catalog, infer, lambda: None)

    def test_invalid_necessity_result_cannot_admit_guards(self):
        for response in ({"valid": "true", "evidence": "Claim"}, {"valid": True, "evidence": ""},
                         {"valid": True, "evidence": "Claim", "override": True}):
            with self.subTest(response=response), self.assertRaises(TaskDagError):
                compile_obligations(self.requirement, self.catalog, self.infer(self.guards, response), lambda: None)

    def test_failed_guard_stops_joint_review_and_excludes_neighbor_values(self):
        infer = self.infer(self.scopes, self.guards, self.admission, self.result("fail"))
        with self.assertRaises(ScopedEvidenceError) as raised:
            verify_scoped({"criterion": self.requirement}, self.catalog, infer)
        self.assertEqual("fail", raised.exception.proof["checks"]["criterion"]["verdict"])
        self.assertEqual(4, infer.call_count)
        self.assertNotIn("Add recovery", str(infer.call_args.args))
        self.assertNotIn(self.title, str(infer.call_args.args))

    def test_passing_guards_do_not_replace_the_complete_joint_review(self):
        infer = self.infer(self.scopes, self.guards, self.admission, self.result("pass"), self.result("fail"))
        with self.assertRaises(ScopedEvidenceError) as raised:
            verify_scoped({"criterion": self.requirement}, self.catalog, infer)
        self.assertEqual(5, infer.call_count)
        self.assertIn(self.requirement, str(infer.call_args.args))
        self.assertEqual("fail", raised.exception.proof["checks"]["criterion"]["verdict"])

    def test_or_and_relational_requirements_can_use_joint_review_without_guards(self):
        result = self.result("pass", {self.title: "Add recovery", self.commit: "Prepare task-42"})
        infer = self.infer(self.scopes, {"guards": []}, self.admission, result)
        proof = verify_scoped({"criterion": "The title or commit mentions recovery."}, self.catalog, infer)
        self.assertEqual("pass", proof["checks"]["criterion"]["verdict"])
        self.assertEqual(4, infer.call_count)

    def test_partial_guard_progress_is_persisted_as_inconclusive_not_pass(self):
        result = self.result("pass", {self.title: "Add recovery", self.commit: "Prepare task-42"})
        infer = self.infer(self.scopes, self.guards, self.admission, self.result("pass"), result)
        snapshots = []
        verify_scoped({"criterion": self.requirement}, self.catalog, infer,
                      checkpoint=lambda proof: snapshots.append(deepcopy(proof)))
        self.assertEqual("inconclusive", snapshots[0]["checks"]["criterion"]["verdict"])
        self.assertEqual("pass", snapshots[-1]["checks"]["criterion"]["verdict"])

    def test_disabling_after_compilation_stops_necessity_review(self):
        active = Mock(side_effect=[None, TaskDagError("Disabled")])
        infer = self.infer(self.guards)
        with self.assertRaisesRegex(TaskDagError, "Disabled"):
            compile_obligations(self.requirement, self.catalog, infer, active)
        self.assertEqual(1, infer.call_count)

    def test_compilation_cannot_omit_a_selected_field(self):
        value = self.compiled([self.guard])
        value["assessments"].pop(self.title)
        with self.assertRaisesRegex(TaskDagError, "every selected field"):
            parse_obligations(value, self.requirement, self.catalog)

    def test_nonmandatory_classification_cannot_smuggle_a_guard(self):
        value = self.compiled([self.guard])
        value["assessments"][self.commit]["classification"] = "alternative_or_conditional"
        with self.assertRaisesRegex(TaskDagError, "Non-mandatory"):
            parse_obligations(value, self.requirement, self.catalog)

    def test_empty_guard_set_still_requires_independent_classification_review(self):
        rejection = {"valid": False, "evidence": "A necessary field was skipped"}
        infer = self.infer({"guards": []}, rejection, {"guards": []}, rejection)
        with self.assertRaisesRegex(TaskDagError, "necessary field was skipped"):
            compile_obligations(self.requirement, self.catalog, infer, lambda: None)
        self.assertEqual(4, infer.call_count)

    def test_rejected_compilation_is_observed_and_independently_rechecked(self):
        rejection = {"valid": False, "evidence": "CORRECTION-OBSERVATION"}
        infer = self.infer(self.guards, rejection, self.guards, self.admission)
        proof = compile_obligations(self.requirement, self.catalog, infer, lambda: None)
        self.assertIn("CORRECTION-OBSERVATION", str(infer.call_args_list[2].args))
        self.assertNotIn("CORRECTION-OBSERVATION", str(infer.call_args_list[3].args))
        self.assertNotIn("Prepare task-42", str(infer.call_args_list))
        self.assertEqual(rejection, proof["rejected_compilations"][0]["necessity_review"])
        self.assertEqual(self.admission, proof["necessity_review"])

    def test_disabled_review_cannot_start_correction(self):
        active = Mock(side_effect=[None, None, TaskDagError("Disabled before correction")])
        infer = self.infer(self.guards, {"valid": False, "evidence": "Invalid clause"})
        with self.assertRaisesRegex(TaskDagError, "Disabled before correction"):
            compile_obligations(self.requirement, self.catalog, infer, active)
        self.assertEqual(2, infer.call_count)

    def test_failed_correction_preserves_both_reviews_without_accepting(self):
        rejection = {"valid": False, "evidence": "Still invalid"}
        infer = self.infer(self.scopes, self.guards, rejection, self.guards, rejection)
        with self.assertRaises(ScopedEvidenceError) as raised:
            verify_scoped({"criterion": self.requirement}, self.catalog, infer)
        proof = raised.exception.proof
        self.assertEqual("inconclusive", proof["checks"]["criterion"]["verdict"])
        self.assertEqual(rejection, proof["compound"]["criterion"]["necessity_review"])
        self.assertEqual(rejection, proof["compound"]["criterion"]["rejected_compilations"][0]["necessity_review"])
        self.assertEqual(5, infer.call_count)

    def test_host_extracts_the_source_instead_of_accepting_model_paraphrases(self):
        rows, guards = parse_obligations(self.compiled([self.guard]), self.requirement, self.catalog)
        self.assertEqual(self.guard["source_quote"], guards[0]["source_quote"])
        self.assertEqual(self.guard["source_quote"], rows[self.commit]["source_quote"])

    def test_shared_subject_clause_can_bind_multiple_fields_without_duplication(self):
        self.requirement = "The title and body are English and the commit describes the change."
        self.catalog = publication_fields({"done": {"title": "Add recovery", "body": "Recovery details",
                                                   "commit_message": "Prepare task-42"}})
        shared = {"source_quote": "The title and body are English",
                  "field_ids": [self.title, "/publications/done/body"]}
        _, guards = parse_obligations(self.compiled([shared, self.guard]), self.requirement, self.catalog)
        self.assertEqual([shared, self.guard], guards)

    def test_invalid_token_ranges_are_rejected(self):
        for start, end in ((-1, 1), (1, 1), (2, 1), (False, 1), (0, 1000), (None, 1)):
            value = self.compiled([self.guard])
            value["assessments"][self.commit].update(start=start, end=end)
            with self.subTest(start=start, end=end), self.assertRaises(TaskDagError):
                parse_obligations(value, self.requirement, self.catalog)

    def test_source_indexing_preserves_unicode_punctuation_and_original_whitespace(self):
        text = "\u4e2d\u6587\uff0c a  +\tb"
        tokens = source_tokens(text)
        self.assertEqual(["\u4e2d", "\u6587", "\uff0c", "a", "+", "b"], [token.group() for token in tokens])
        self.assertEqual("a  +\tb", text[tokens[3].start():tokens[5].end()])
