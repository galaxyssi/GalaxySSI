from __future__ import annotations

import copy
import json
import unittest
from unittest.mock import Mock, patch

from evolution_v2.candidate_acceptance import CandidateAcceptance
from evolution_v2.goal_text_contract import compile_contract, contract_input, evaluate_contract, ground_contract, headings, validate_contract
from evolution_v2.legacy import EvolutionError
from evolution_v2.local_planning import LocalPlannerUnavailable


class GoalTextContractTests(unittest.TestCase):
    def evidence(self, content="Original\n"):
        return {"base_commit": "a" * 40, "candidate_commit": "b" * 40,
                "requirements": [{"id": "task", "text": "Improve the guide"},
                                 {"id": "parent-intent", "text": "Append a Recovery checklist section. Remove obsolete notice."}],
                "scope": ["docs/guide.md"], "diff": "candidate-secret",
                "files": {"docs/guide.md": {"before": "Original\n", "after": content,
                          "original_text_present": True, "original_text_is_prefix": True}}}

    def check(self, **changes):
        return {"kind": "markdown_heading", "path": "docs/guide.md", "text": "Recovery checklist",
                "source_quote": "Append a Recovery checklist section.", "case_sensitive": False, **changes}

    def compiler(self, **changes):
        check = self.check()
        del check["source_quote"]
        check.update(changes)
        return Mock(return_value=json.dumps({"checks": [check]}))

    def review(self):
        return Mock(return_value=json.dumps({"verdict": "pass", "findings": [], "assessments": {
            key: {"verdict": "pass", "evidence": "Controlled proof"} for key in ["task", "parent-intent"]},
            "file_requirements": {"docs/guide.md": {"preservation": "append_only", "reason": "Append requested"}}}))

    def test_compiler_has_original_goal_and_scope_but_not_candidate_content(self):
        infer = self.compiler()
        compile_contract(self.evidence("private-candidate-text"), infer)
        messages = infer.call_args.args[0]
        source = json.loads(messages[1]["content"])
        self.assertEqual({"original_goal", "child_task", "scope", "paths"}, set(source))
        self.assertNotIn("private-candidate-text", json.dumps(messages))
        self.assertNotIn("candidate-secret", json.dumps(messages))
        self.assertEqual(["docs/guide.md"], source["paths"])
        self.assertIn("markdown_heading", infer.call_args.kwargs["response_schema"]["properties"]["checks"]["items"]["properties"]["kind"]["enum"])

    def test_fabricated_quotes_literals_paths_and_modes_are_rejected(self):
        for change in [{"source_quote": "Invented requirement"}, {"text": "Invented title"},
                       {"path": "../other.md"}, {"kind": "shell"}, {"case_sensitive": "false"},
                       {"text": " "}, {"source_quote": ""}, {"command": "echo pass"}]:
            with self.subTest(change=change), self.assertRaises(EvolutionError) as caught:
                compile_contract(self.evidence(), self.compiler(**change))
            self.assertEqual("acceptance_review_unavailable", caught.exception.code)

    def test_duplicate_checks_and_extra_root_fields_are_rejected(self):
        source = contract_input(self.evidence())
        for value in [{"checks": [self.check(), self.check()]}, {"checks": [], "pass": True}, {"checks": None}]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                validate_contract(value, source)

    def test_casefolded_literal_remains_grounded(self):
        check = self.check(text="RECOVERY CHECKLIST")
        self.assertEqual([check], validate_contract({"checks": [check]}, contract_input(self.evidence())))

    def test_invalid_literal_receives_actionable_correction_without_candidate_text(self):
        bad = self.compiler(text="Invented title").return_value
        good = self.compiler().return_value
        infer = Mock(side_effect=[bad, good])
        contract = compile_contract(self.evidence("private-candidate"), infer)
        self.assertEqual("Recovery checklist", contract["checks"][0]["text"])
        self.assertEqual(2, infer.call_count)
        messages = infer.call_args.args[0]
        self.assertIn("text must occur literally", json.loads(messages[-1]["content"])["validation_error"])
        self.assertNotIn("private-candidate", json.dumps(messages))

    def test_host_attaches_actual_source_without_requiring_model_to_copy_prose(self):
        evidence = self.evidence()
        goal = "\u8bf7\u8ffd\u52a0 Recovery checklist \u5c0f\u8282\uff0c\u4fdd\u7559\u539f\u6587\u3002"
        evidence["requirements"][1]["text"] = goal
        contract = compile_contract(evidence, self.compiler())
        self.assertEqual(goal, contract["checks"][0]["source_quote"])
        self.assertNotIn("source_quote", self.compiler().return_value)

    def test_literal_regex_metacharacters_are_not_executed_as_patterns(self):
        source = contract_input(self.evidence())
        source["original_goal"] = "Name the section a+b[1]."
        check = {"kind": "markdown_heading", "path": "docs/guide.md", "text": "a+b[1]", "case_sensitive": True}
        self.assertEqual("a+b[1]", ground_contract({"checks": [check]}, source)[0]["text"])
        check["text"] = "a.*"
        with self.assertRaises(ValueError):
            ground_contract({"checks": [check]}, source)

    def test_repeated_invalid_contract_is_bounded_and_unavailable_transport_is_not_retried(self):
        infer = Mock(return_value="not json")
        with self.assertRaises(EvolutionError):
            compile_contract(self.evidence(), infer)
        self.assertEqual(2, infer.call_count)
        infer = Mock(side_effect=ConnectionError("offline"))
        with self.assertRaises(EvolutionError):
            compile_contract(self.evidence(), infer)
        self.assertEqual(1, infer.call_count)

    def mixed_compiler(self):
        checks = json.loads(self.compiler().return_value)["checks"]
        checks.append({**checks[0], "kind": "contains", "text": "Invented semantic output"})
        return Mock(return_value=json.dumps({"checks": checks}))

    def test_known_host_failure_is_actionable_even_when_another_check_is_invalid(self):
        reviewer = self.review()
        result = CandidateAcceptance(reviewer, self.mixed_compiler()).verify(self.evidence())
        self.assertEqual("fail", result["verdict"])
        self.assertIn("markdown_heading", result["findings"][0])
        self.assertTrue(result["goal_contract"]["issues"])
        self.assertFalse(result["goal_checks"][0]["passed"])
        reviewer.assert_not_called()

    def test_partial_contract_cannot_pass_or_reuse_as_complete_compilation(self):
        infer, reviewer = self.mixed_compiler(), self.review()
        evidence = self.evidence("Original\n## Recovery checklist\n")
        contract = compile_contract(evidence, infer)
        self.assertTrue(contract["issues"])
        compile_contract(evidence, infer, contract)
        self.assertEqual(4, infer.call_count)
        with self.assertRaises(EvolutionError) as caught:
            CandidateAcceptance(reviewer, infer).verify(evidence)
        self.assertIn("checks remain incomplete", str(caught.exception))
        reviewer.assert_not_called()

    def test_candidate_change_reuses_compilation_but_checks_new_content(self):
        infer = self.compiler()
        first = compile_contract(self.evidence(), infer)
        changed = self.evidence("Original\n## Recovery checklist\n")
        second = compile_contract(changed, infer, first)
        self.assertEqual(1, infer.call_count)
        self.assertFalse(evaluate_contract(first, self.evidence()["files"])[0]["passed"])
        self.assertTrue(evaluate_contract(second, changed["files"])[0]["passed"])

    def test_goal_child_scope_and_paths_changes_invalidate_cache(self):
        infer = self.compiler()
        old = compile_contract(self.evidence(), infer)
        variants = []
        goal = self.evidence()
        goal["requirements"][1]["text"] += " Preserve the introduction."
        variants.append(goal)
        child = self.evidence()
        child["requirements"][0]["text"] = "A different child"
        variants.append(child)
        scope = self.evidence()
        scope["scope"] = ["docs"]
        variants.append(scope)
        paths = self.evidence()
        paths["files"]["docs/extra.md"] = {"after": "Other"}
        variants.append(paths)
        for changed in variants:
            self.assertNotEqual(old["source_hash"], compile_contract(changed, infer, old)["source_hash"])
        self.assertEqual(5, infer.call_count)

    def test_invalid_cached_contract_is_recompiled(self):
        infer = self.compiler()
        old = compile_contract(self.evidence(), infer)
        bad = copy.deepcopy(old)
        bad["checks"][0]["source_quote"] = "Invented"
        self.assertEqual(old, compile_contract(self.evidence(), infer, bad))
        self.assertEqual(2, infer.call_count)

    def test_manual_task_does_not_invent_a_parent_or_inference(self):
        evidence = self.evidence()
        evidence["requirements"] = evidence["requirements"][:1]
        infer = Mock(side_effect=AssertionError("Unexpected model call"))
        self.assertIsNone(compile_contract(evidence, infer))
        infer.assert_not_called()

    def test_top_level_commonmark_headings(self):
        for content in ["## Recovery checklist\n", "Recovery checklist\n----\n",
                        "## **Recovery** `checklist` ##\r\n", "# [Recovery checklist](https://example.org)\n"]:
            with self.subTest(content=content):
                self.assertIn("Recovery checklist", headings(content))

    def test_mentions_fences_quotes_lists_and_comments_are_not_top_level_sections(self):
        for content in ["Recovery checklist is mentioned.\n", "```md\n## Recovery checklist\n```\n",
                        "> ## Recovery checklist\n", "- ## Recovery checklist\n",
                        "<!--\n## Recovery checklist\n-->\n", "    ## Recovery checklist\n"]:
            with self.subTest(content=content):
                self.assertNotIn("Recovery checklist", headings(content))

    def test_contains_absent_heading_and_case_modes(self):
        files = self.evidence("## recovery checklist\nObsolete notice\n")["files"]
        cases = [(self.check(), True), (self.check(case_sensitive=True), False),
                 (self.check(kind="contains"), True),
                 (self.check(kind="absent", text="obsolete notice"), False),
                 (self.check(kind="absent", text="missing"), True)]
        for check, expected in cases:
            with self.subTest(check=check):
                self.assertEqual(expected, evaluate_contract({"checks": [check]}, files)[0]["passed"])

    def test_host_failure_blocks_semantic_reviewer_and_explains_parent_requirement(self):
        reviewer = Mock(side_effect=AssertionError("Must not overrule host failure"))
        proof = CandidateAcceptance(reviewer, self.compiler()).verify(self.evidence())
        self.assertEqual("fail", proof["verdict"])
        self.assertIn("Recovery checklist", proof["findings"][0])
        self.assertEqual("parent-intent", proof["assessments"][1]["id"])
        self.assertEqual("fail", proof["assessments"][1]["verdict"])
        reviewer.assert_not_called()

    def test_passed_literals_still_require_semantic_review(self):
        reviewer = self.review()
        verifier = CandidateAcceptance(reviewer, self.compiler())
        evidence = self.evidence("Original\n## Recovery checklist\n")
        proof = verifier.verify(evidence)
        self.assertEqual("pass", proof["verdict"])
        self.assertTrue(json.loads(reviewer.call_args.args[0][1]["content"])["host_goal_checks"][0]["passed"])
        self.assertEqual(proof, verifier.verify(evidence, proof))
        self.assertEqual(1, reviewer.call_count)
        changed = self.evidence("Original\nNo heading\n")
        self.assertEqual("fail", verifier.verify(changed, proof)["verdict"])
        self.assertEqual(1, reviewer.call_count)

    def test_model_and_parser_unavailability_never_pass_or_fallback(self):
        reviewer = self.review()
        for failure in [TimeoutError("private endpoint"), ConnectionError("offline")]:
            with self.subTest(failure=failure), self.assertRaises(EvolutionError):
                CandidateAcceptance(reviewer, Mock(side_effect=failure)).verify(self.evidence())
        with patch("evolution_v2.candidate_acceptance.evaluate_contract", side_effect=ImportError("missing parser")):
            with self.assertRaises(EvolutionError) as caught:
                CandidateAcceptance(reviewer, self.compiler()).verify(self.evidence())
            self.assertEqual("acceptance_review_unavailable", caught.exception.code)
        reviewer.assert_not_called()

    def test_local_response_limit_reason_reaches_the_acceptance_observation(self):
        infer = Mock(side_effect=LocalPlannerUnavailable("Local planner response reached its context or output limit"))
        with self.assertRaisesRegex(EvolutionError, "context or output limit") as caught:
            compile_contract(self.evidence(), infer)
        self.assertEqual("acceptance_review_unavailable", caught.exception.code)
        self.assertEqual(1, infer.call_count)


if __name__ == "__main__":
    unittest.main()
