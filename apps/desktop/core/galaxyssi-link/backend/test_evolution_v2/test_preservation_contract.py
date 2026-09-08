import copy
import json
import unittest
from unittest.mock import Mock

from evolution_v2.candidate_acceptance import CandidateAcceptance, CONTRACT
from evolution_v2.legacy import EvolutionError
from evolution_v2.preservation_contract import compile_preservation, evaluate_preservation, source_input


def evidence(after="Original\nAdded\n", before="Original\n"):
    return {"task_id": "task", "base_commit": "a" * 40, "candidate_commit": "b" * 40,
        "requirements": [{"id": "task", "text": "Append at the end and retain all original text."}],
        "scope": ["docs"], "diff": "private candidate diff",
        "files": {"docs/a.md": {"before": before, "after": after,
            "original_text_present": True, "original_text_is_prefix": True}}}


def compiler(mode="append_only"):
    def infer(messages, **kwargs):
        source = json.loads(messages[-1]["content"])
        requirement = source["requirements"][0]
        return json.dumps({"files": {path: {"preservation": mode,
            "source_requirement_id": requirement["id"], "source_quote": requirement["text"],
            "reason": "Explicit controlled source classification"} for path in source["paths"]}})
    return Mock(side_effect=infer)


def reviewer():
    def infer(messages, **kwargs):
        facts = json.loads(messages[-1]["content"])
        return json.dumps({"verdict": "pass", "findings": [], "assessments": {
            row["id"]: {"verdict": "pass", "evidence": "Controlled passing reviewer"} for row in facts["requirements"]},
            "file_requirements": {path: {"preservation": "none", "reason": "Weaker post-hoc declaration"}
                                  for path in facts["files"]}})
    return Mock(side_effect=infer)


class PreservationContractTests(unittest.TestCase):
    def test_source_compiler_cannot_see_candidate_or_base_text_or_model_findings(self):
        infer = compiler()
        candidate = evidence(after="PRIVATE AFTER", before="PRIVATE BEFORE")
        candidate["review"] = "PRIVATE REVIEW"
        contract = compile_preservation(candidate, infer)
        payload = infer.call_args.args[0][1]["content"]
        self.assertEqual(source_input(candidate), json.loads(payload))
        for forbidden in ("PRIVATE", "private candidate diff", "candidate_commit", "base_commit"):
            self.assertNotIn(forbidden, payload)
        self.assertEqual("append_only", contract["files"]["docs/a.md"]["preservation"])

    def test_preservation_matrix_uses_actual_text_not_supplied_boolean_claims(self):
        cases = [
            ("append_only", "Original\n", "Original\nAdded\n", True),
            ("append_only", "Original\n", "Added\nOriginal\n", False),
            ("append_only", "Original\n", "Original changed\n", False),
            ("append_only", "Original\n", None, False),
            ("append_only", "Original\n", "Original\n", True),
            ("verbatim", "Original\n", "Added\nOriginal\n", True),
            ("verbatim", "One\nTwo\n", "Two\nOne\n", False),
            ("verbatim", "Original\n", "Changed\n", False),
            ("verbatim", "Original\n", None, False),
            ("none", "Original\n", "Changed\n", True),
            ("none", "Original\n", None, True),
            ("append_only", "", "Added\n", True),
            ("append_only", "", None, False),
            ("verbatim", None, "New file\n", True),
            ("append_only", None, "New file\n", True),
            ("append_only", None, None, False),
        ]
        for mode, before, after, expected in cases:
            with self.subTest(mode=mode, before=before, after=after):
                data = evidence(after, before)
                contract = compile_preservation(data, compiler(mode))
                self.assertEqual(expected, evaluate_preservation(contract, data["files"])[0]["passed"])

    def test_prepend_negative_cannot_be_overruled_by_a_passing_reviewer(self):
        semantic = reviewer()
        result = CandidateAcceptance(semantic, preservation_infer=compiler()).verify(evidence("Added\nOriginal\n"))
        self.assertEqual("fail", result["verdict"])
        self.assertIn("append_only", result["findings"][0])
        semantic.assert_not_called()

    def test_legitimate_append_and_rewrite_can_pass(self):
        for mode, after in (("append_only", "Original\nAdded\n"), ("none", "Rewritten\n")):
            with self.subTest(mode=mode):
                data = evidence(after)
                if mode == "none":
                    data["requirements"][0]["text"] = "Rewrite the document."
                result = CandidateAcceptance(reviewer(), preservation_infer=compiler(mode)).verify(data)
                self.assertEqual("pass", result["verdict"])
                self.assertEqual(mode, result["preservation_contract"]["files"]["docs/a.md"]["preservation"])

    def test_restart_and_forced_review_reuse_source_contract_not_old_verdict(self):
        infer, semantic = compiler(), reviewer()
        first = CandidateAcceptance(semantic, preservation_infer=infer).verify(evidence())
        restarted = CandidateAcceptance(reviewer(), preservation_infer=Mock(side_effect=AssertionError("Do not reclassify")))
        restored = json.loads(json.dumps(first))
        self.assertEqual(first, restarted.verify(evidence(), restored))
        self.assertEqual("pass", restarted.verify(evidence(), restored, force_review=True)["verdict"])
        self.assertEqual(1, restarted.infer.call_count)
        changed = evidence("Added\nOriginal\n")
        changed["candidate_commit"] = "c" * 40
        self.assertEqual("fail", restarted.verify(changed, restored)["verdict"])
        self.assertEqual(1, restarted.infer.call_count)

    def test_contract_checkpoint_survives_semantic_transport_failure(self):
        checkpoints = []
        verifier = CandidateAcceptance(Mock(side_effect=TimeoutError("offline")), preservation_infer=compiler())
        with self.assertRaises(EvolutionError):
            verifier.verify(evidence(), checkpoint=checkpoints.append)
        self.assertEqual(1, len(checkpoints))
        proof = json.loads(json.dumps(checkpoints[0]))
        self.assertEqual("inconclusive", proof["verdict"])
        resumed = CandidateAcceptance(reviewer(), preservation_infer=Mock(side_effect=AssertionError("No reclassification")))
        self.assertEqual("pass", resumed.verify(evidence(), proof)["verdict"])

    def test_stale_contracts_recompile_when_source_path_scope_or_version_changes(self):
        infer = compiler()
        first = compile_preservation(evidence(), infer)
        for field, replacement in (("requirements", [{"id": "task", "text": "Rewrite this file"}]),
                                   ("scope", ["docs/a.md"]), ("files", {"other.md": evidence()["files"]["docs/a.md"]})):
            with self.subTest(field=field):
                data = {**evidence(), field: replacement}
                fresh = compile_preservation(data, infer, first)
                self.assertNotEqual(first["source_hash"], fresh["source_hash"])
        compile_preservation(evidence(), infer, {**first, "version": 0})
        self.assertEqual(5, infer.call_count)

    def test_inconclusive_missing_fabricated_and_partial_classification_never_pass(self):
        semantic = reviewer()
        with self.assertRaises(EvolutionError):
            CandidateAcceptance(semantic, preservation_infer=compiler("inconclusive")).verify(evidence())
        semantic.assert_not_called()
        good = json.loads(compiler().side_effect([{"content": json.dumps(source_input(evidence()))}]))
        mutations = [{"files": {}}, {"files": []}, {"files": {"alien.md": good["files"]["docs/a.md"]}}]
        for field, value in (("source_quote", "invented"), ("source_requirement_id", "missing"),
                             ("reason", ""), ("preservation", "unknown")):
            bad = copy.deepcopy(good)
            bad["files"]["docs/a.md"][field] = value
            mutations.append(bad)
        for bad in mutations:
            with self.subTest(bad=bad), self.assertRaises(EvolutionError):
                compile_preservation(evidence(), Mock(return_value=json.dumps(bad)))

    def test_multi_file_move_does_not_satisfy_original_path_preservation(self):
        data = evidence(None)
        data["files"]["docs/moved.md"] = {"before": None, "after": "Original\n"}
        result = CandidateAcceptance(reviewer(), preservation_infer=compiler("verbatim")).verify(data)
        self.assertEqual("fail", result["verdict"])
        self.assertEqual([False, True], [row["passed"] for row in result["preservation_checks"]])

    def test_old_acceptance_contract_cannot_skip_source_classification(self):
        first = CandidateAcceptance(reviewer(), preservation_infer=compiler()).verify(evidence())
        first["contract"] = "galaxyssi.candidate-acceptance.v5"
        del first["preservation_contract"]
        semantic, infer = reviewer(), compiler()
        result = CandidateAcceptance(semantic, preservation_infer=infer).verify(evidence(), first)
        self.assertEqual(CONTRACT, result["contract"])
        self.assertEqual(1, infer.call_count)
        self.assertEqual(1, semantic.call_count)
