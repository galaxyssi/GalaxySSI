from copy import deepcopy
import json
import unittest
from unittest.mock import Mock

from agent_task_dag import TaskDagError
from evolution_v2.original_goal_evidence import original_goal_catalog
from evolution_v2.original_goal_requirements import compile_requirements, validate_requirements
from evolution_v2.original_goal_review import review_original_goal


class OriginalGoalReviewTests(unittest.TestCase):
    def setUp(self):
        self.evidence = {"graph": {"objective": "Keep the file. Publish an English title."},
            "publications": {"n": {"title": "Recovery", "body": "Claim: everything passed."}},
            "candidates": {"n": {"files": {"x.md": {"before": "Original", "after": "Original\nNew"}},
                "requirements": ["Untrusted generated requirement"], "parent_context": {"claim": "Done"},
                "current_literal_checks": [{"passed": True}], "previous_acceptance_is_not_final_goal_acceptance": True}},
            "current_integrations": {"n": {"passed": True, "reason": "Not source evidence"}}}
        self.file = "/candidates/n/files/x.md/after"
        self.title = "/publications/n/title"
        self.plan = {"parts": [{"source_quote": "Keep the file. ", "field_ids": [self.file]},
                               {"source_quote": "Publish an English title.", "field_ids": [self.title]}]}
        self.responses = self.compilation() + [self.answer(self.file, "Original"), self.answer(self.title, "Recovery")]
        self.infer = Mock(side_effect=self.responses)

    def compilation(self):
        return [json.dumps({"clauses": [part["source_quote"] for part in self.plan["parts"]]}),
            json.dumps({"scopes": {"part-" + str(index + 1): {"field_ids": part["field_ids"], "reason": "Direct evidence"}
                for index, part in enumerate(self.plan["parts"])}}),
            json.dumps({"clauses": {"part-" + str(index + 1): {"sufficient": bool(part["field_ids"]),
                "missing_field_ids": [], "evidence": "Evidence sufficiency assessed"}
                for index, part in enumerate(self.plan["parts"])}})]

    @staticmethod
    def answer(field, quote, verdict="pass"):
        return json.dumps({"verdict": verdict, "evidence": "Direct observed contents", "quotes": [{"field_id": field, "quote": quote}]})

    def review(self, **kwargs):
        return review_original_goal(self.evidence, self.infer, reviewer_id="model-1", **kwargs)

    def test_catalog_does_not_admit_generated_requirements_or_previous_passes(self):
        catalog = original_goal_catalog(self.evidence)
        text = json.dumps(catalog)
        self.assertNotIn("Untrusted generated requirement", text)
        self.assertNotIn("Not source evidence", text)
        self.assertNotIn("parent_context", text)
        self.assertIn("Claim: everything passed.", text)
        self.assertIn("claims in it are not independent proof", text)

    def test_compiler_is_candidate_blind_and_reviews_are_field_isolated(self):
        result = self.review()
        self.assertEqual("pass", result["verdict"])
        calls = self.infer.call_args_list
        compilation = calls[0].args[0][1]["content"]
        self.assertNotIn("Original\\nNew", compilation)
        self.assertNotIn("Claim: everything passed", compilation)
        self.assertNotIn("available_fields", compilation)
        self.assertNotIn(self.file, compilation)
        audit_input = calls[2].args[0][1]["content"]
        self.assertNotIn("Claim: everything passed", audit_input)
        self.assertNotIn("Original\\nNew", audit_input)
        first = json.loads(calls[3].args[0][1]["content"])
        self.assertEqual([self.file], list(first["fields"]))
        self.assertNotIn("Recovery", json.dumps(first))
        self.assertEqual("Keep the file. ", first["required_source_clause"])
        second = json.loads(calls[4].args[0][1]["content"])
        self.assertEqual([self.title], list(second["fields"]))
        self.assertNotIn("Original", json.dumps(second))

    def test_source_cannot_be_dropped_translated_reordered_or_repeated(self):
        catalog = original_goal_catalog(self.evidence)
        malformed = [self.plan["parts"][:1], list(reversed(self.plan["parts"])),
            self.plan["parts"] + self.plan["parts"], [{"source_quote": "Different goal", "field_ids": []}]]
        for parts in malformed:
            with self.subTest(parts=parts), self.assertRaises(TaskDagError):
                validate_requirements({"parts": parts}, self.evidence["graph"]["objective"], catalog)

    def test_no_transformation_of_chinese_punctuation_or_whitespace(self):
        goal = "\u4fdd\u7559\u539f\u6587\u3002\n\u53d1\u5e03 PR\u3002"
        parts = {"parts": [{"source_quote": "\u4fdd\u7559\u539f\u6587\u3002\n", "field_ids": []},
                           {"source_quote": "\u53d1\u5e03 PR\u3002", "field_ids": []}]}
        self.assertEqual(parts["parts"], validate_requirements(parts, goal, {}))
        parts["parts"][0]["source_quote"] = parts["parts"][0]["source_quote"].strip()
        with self.assertRaises(TaskDagError):
            validate_requirements(parts, goal, {})

    def test_foreign_duplicate_and_nontext_evidence_ids_are_rejected(self):
        for ids in (["foreign"], [self.file, self.file], [False]):
            plan = deepcopy(self.plan)
            plan["parts"][0]["field_ids"] = ids
            with self.subTest(ids=ids), self.assertRaises(TaskDagError):
                validate_requirements(plan, self.evidence["graph"]["objective"], original_goal_catalog(self.evidence))

    def test_late_pass_cannot_overwrite_an_earlier_failure(self):
        self.infer.side_effect = self.compilation() + [self.answer(self.file, "Original", "fail"), self.responses[4]]
        result = self.review()
        self.assertEqual("fail", result["verdict"])
        self.assertEqual(5, self.infer.call_count)
        self.assertEqual("pass", result["checks"]["part-2"]["result"]["verdict"])

    def test_missing_evidence_is_inconclusive_without_a_model_call(self):
        self.plan["parts"][1]["field_ids"] = []
        self.infer.side_effect = self.compilation() + [self.responses[3]]
        result = self.review()
        self.assertEqual("inconclusive", result["verdict"])
        self.assertEqual(4, self.infer.call_count)

    def test_invalid_quotes_are_archived_and_do_not_skip_remaining_requirements(self):
        self.infer.side_effect = self.compilation() + [self.answer(self.file, "Invented source"), self.responses[4]]
        events = []
        result = self.review(checkpoint=events.append)
        self.assertEqual("inconclusive", result["verdict"])
        self.assertEqual(5, self.infer.call_count)
        self.assertIn("Invented source", result["checks"]["part-1"]["response"])
        self.assertTrue(any(event.get("checks", {}).get("part-1", {}).get("status") == "observed" for event in events))

    def test_unchanged_proof_resumes_without_inference_and_rechecks_raw_quotes(self):
        previous = self.review()
        self.infer = Mock(side_effect=AssertionError("No repeated inference"))
        self.assertEqual("pass", self.review(previous=previous)["verdict"])
        previous["checks"]["part-2"]["response"] = self.answer(self.title, "Not present")
        self.assertEqual("inconclusive", self.review(previous=previous)["verdict"])

    def test_changed_field_rechecks_only_its_affected_source_clause(self):
        previous = self.review()
        self.evidence["publications"]["n"]["title"] = "\u6062\u590d"
        self.infer = Mock(return_value=self.answer(self.title, "\u6062\u590d", "fail"))
        self.assertEqual("fail", self.review(previous=previous)["verdict"])
        self.infer.assert_called_once()

    def test_changed_goal_or_reviewer_cannot_reuse_the_old_compilation(self):
        previous = self.review()
        for mode in ("goal", "reviewer"):
            with self.subTest(mode=mode):
                candidate = deepcopy(previous)
                if mode == "goal":
                    candidate["requirements"]["source_hash"] = "stale"
                else:
                    candidate["reviewer_id"] = "another-model"
                self.infer = Mock(side_effect=self.responses)
                self.assertEqual("pass", self.review(previous=candidate)["verdict"])
                self.assertGreaterEqual(self.infer.call_count, 1)

    def test_compilation_response_is_retained_before_coverage_validation(self):
        self.infer = Mock(return_value='{"parts":[]}')
        events = []
        with self.assertRaises(TaskDagError):
            self.review(checkpoint=events.append)
        self.assertEqual('{"parts":[]}', events[0]["requirements"]["partition_response"])

    def test_stop_prevents_next_inference_and_no_final_verdict_is_emitted(self):
        events = []
        active = iter([True, True, True, True, True, False])
        with self.assertRaises(TaskDagError):
            self.review(checkpoint=events.append, should_continue=lambda: next(active))
        self.assertEqual(4, self.infer.call_count)
        self.assertNotIn("verdict", events[-1])

    def test_stop_between_partition_and_scope_prevents_scope_inference(self):
        active = iter([True, True, False])
        events = []
        with self.assertRaises(TaskDagError):
            self.review(checkpoint=events.append, should_continue=lambda: next(active))
        self.infer.assert_called_once()
        self.assertIn("partition_response", events[-1]["requirements"])
        self.assertNotIn("scope_response", events[-1]["requirements"])

    def test_corrupt_cached_compilation_cannot_become_a_pass(self):
        previous = self.review()
        previous["requirements"]["response"] = '{"parts":[]}'
        with self.assertRaises(TaskDagError):
            self.review(previous=previous)

    def test_rejected_compilation_is_not_reused_forever(self):
        self.infer = Mock(return_value='{"parts":[]}')
        events = []
        with self.assertRaises(TaskDagError):
            self.review(checkpoint=events.append)
        self.infer = Mock(side_effect=self.responses)
        self.assertEqual("pass", self.review(previous=events[-1])["verdict"])
        self.assertEqual(5, self.infer.call_count)

    def test_insufficient_scope_blocks_acceptance_and_next_run_reselects_without_repartitioning(self):
        compilation = self.compilation()
        audit = json.loads(compilation[2])
        audit["clauses"]["part-1"] = {"sufficient": False, "missing_field_ids": [], "evidence": "Need an execution receipt"}
        self.infer = Mock(side_effect=compilation[:2] + [json.dumps(audit), self.responses[4]])
        previous = self.review()
        self.assertEqual("inconclusive", previous["verdict"])
        self.assertEqual("awaiting_evidence", previous["checks"]["part-1"]["status"])
        self.assertEqual(4, self.infer.call_count)
        self.infer = Mock(side_effect=compilation[1:] + [self.responses[3]])
        repaired = self.review(previous=previous)
        self.assertEqual("pass", repaired["verdict"])
        self.assertEqual(3, self.infer.call_count)
        replanning = json.loads(self.infer.call_args_list[0].args[0][1]["content"])
        self.assertIn("previous_insufficient_selection", replanning)
        self.assertEqual(self.evidence["graph"]["objective"], replanning["original_goal"])
        self.assertEqual(previous["requirements"]["partition_response"], repaired["requirements"]["partition_response"])

    def test_corrupt_cached_audit_cannot_grant_acceptance(self):
        previous = self.review()
        previous["requirements"]["audit_response"] = '{"clauses":{}}'
        with self.assertRaises(TaskDagError):
            self.review(previous=previous)

    def test_valid_but_tampered_cached_scope_cannot_reassign_original_requirements(self):
        previous = self.review()
        scopes = json.loads(previous["requirements"]["scope_response"])
        scopes["scopes"]["part-2"]["field_ids"] = [self.file]
        previous["requirements"]["scope_response"] = json.dumps(scopes)
        with self.assertRaises(TaskDagError):
            self.review(previous=previous)

    def test_scope_failure_preserves_partition_and_raw_scope_response(self):
        self.infer = Mock(side_effect=[self.responses[0], '{"scopes":{}}'])
        events = []
        with self.assertRaises(TaskDagError):
            self.review(checkpoint=events.append)
        self.assertEqual(self.responses[0], events[-1]["requirements"]["partition_response"])
        self.assertEqual('{"scopes":{}}', events[-1]["requirements"]["scope_response"])

    def test_no_evidence_catalog_still_preserves_every_source_clause(self):
        self.evidence = {"graph": self.evidence["graph"], "candidates": {}, "publications": {}, "current_integrations": {}}
        self.infer = Mock(return_value=self.responses[0])
        proof = self.review()
        self.assertEqual("inconclusive", proof["verdict"])
        self.assertEqual(2, len(proof["checks"]))
        self.infer.assert_called_once()
        self.infer = Mock(side_effect=AssertionError("No repeated inference"))
        self.assertEqual("inconclusive", self.review(previous=proof)["verdict"])

    def test_pointer_keys_escape_slashes_and_tildes_without_aliases(self):
        self.evidence["candidates"]["n"]["files"] = {"a/b~c": {"before": None, "after": "New"}}
        catalog = original_goal_catalog(self.evidence)
        self.assertIn("/candidates/n/files/a~1b~0c/after", catalog)

    def test_conditional_or_clause_can_remain_one_joint_source_requirement(self):
        goal = "Title contains Recovery or body contains Recovery."
        plan = {"parts": [{"source_quote": goal, "field_ids": [self.title, "/publications/n/body"]}]}
        self.assertEqual(plan["parts"], validate_requirements(plan, goal, original_goal_catalog(self.evidence)))
