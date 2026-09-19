import copy
import json
import unittest
from unittest.mock import patch

from research_audit import ResearchEvidenceAudit, tool_spec, TOOL
from codex_app_server import CodexAppServer, CodexRun


URL = "https://example.org/paper"
QUOTE = "A Smith works at Institute A."


def observation(body=True):
    return {"research_trace": {"queries": ["Smith publications"], "sources": [{"url": URL}]},
            "evidence_pack": {"items": [{"url": URL, "excerpt": QUOTE, "evidence_level": "retrieved_body" if body else "search_snippet"}]}}


def proposal():
    return {"scope": "Confirmed-so-far inventory", "entities": [{"id": "person", "name": "A Smith", "decision": "include",
            "basis": "positive_match", "reason": "Affiliation matches", "evidence": [{"url": URL, "quote": QUOTE}]}],
            "claims": [{"id": "c1", "statement": "The author works at Institute A", "entity_ids": ["person"],
                        "assessment": "supported", "evidence": [{"url": URL, "quote": QUOTE, "relation": "supports"}]}],
            "coverage": [{"facet": "English records", "status": "searched", "query": "Smith publications", "gap": ""}]}


class ResearchAuditTests(unittest.TestCase):
    def setUp(self):
        self.audit = ResearchEvidenceAudit()
        self.audit.observe(observation())

    def test_quote_match_is_provenance_not_truth(self):
        result = self.audit.submit(proposal())
        ref = result["claims"][0]["evidence"][0]
        self.assertTrue(ref["passage_observed"])
        self.assertEqual(64, len(ref["passage_sha256"]))
        self.assertEqual("not_independently_verified", result["semantic_verification"])
        self.assertEqual("not_established", result["completeness"])

    def test_invented_source_and_quote_remain_unknown(self):
        audit = ResearchEvidenceAudit()
        result = audit.submit(proposal())
        self.assertEqual("pending", result["entities"][0]["decision"])
        self.assertEqual("unknown", result["claims"][0]["assessment"])
        self.assertFalse(result["coverage"][0]["query_observed"])
        self.assertEqual(0, result["observed"]["source_urls"])

    def test_absence_is_not_exclusion(self):
        data = proposal()
        data["entities"][0].update(decision="exclude", basis="insufficient_evidence")
        result = self.audit.submit(data)
        self.assertEqual("pending", result["entities"][0]["decision"])
        self.assertEqual("unknown", result["claims"][0]["assessment"])

    def test_positive_exclusion_still_model_assessed(self):
        data = proposal()
        data["entities"][0].update(decision="exclude", basis="positive_mismatch")
        result = self.audit.submit(data)
        self.assertEqual("exclude", result["entities"][0]["decision"])
        self.assertEqual("model_assessment_not_independent_verification", result["entities"][0]["decision_authority"])

    def test_counterevidence_is_not_dropped(self):
        data = proposal()
        data["claims"][0]["evidence"].append({"url": "https://example.org/conflict", "quote": "Different identity is possible.", "relation": "contradicts"})
        result = self.audit.submit(data)
        self.assertEqual("disputed", result["claims"][0]["assessment"])
        self.assertEqual(2, len(result["claims"][0]["evidence"]))

    def test_duplicates_and_identifier_aliases(self):
        for _ in range(5):
            self.audit.observe(observation())
        self.audit.observe({"research_trace": {"sources": [{"url": "https://doi.org/10.1/ABC"}, {"url": "http://dx.doi.org/10.1/abc"}]}})
        report = self.audit.report()["observed"]
        self.assertEqual(1, report["unique_queries"])
        self.assertEqual(3, report["source_urls"])
        self.assertEqual(2, report["canonical_records"])

    def test_snippet_does_not_inherit_body_receipt(self):
        audit = ResearchEvidenceAudit()
        audit.observe(observation(False))
        another = observation()
        another["evidence_pack"]["items"][0]["excerpt"] = "Unrelated body paragraph."
        audit.observe(another)
        self.assertEqual("search_snippet_or_unavailable", audit.submit(proposal())["claims"][0]["evidence"][0]["evidence_scope"])

    def test_duplicate_ids_invalid_without_replacing_snapshot(self):
        self.audit.submit(proposal())
        data = proposal()
        data["claims"].append(copy.deepcopy(data["claims"][0]))
        self.assertEqual("invalid", self.audit.submit(data)["status"])
        self.assertEqual(1, len(self.audit.report()["claims"]))

    def test_malformed_and_oversized_inputs_fail_closed(self):
        for value in (None, [], {}, {**proposal(), "entities": [{}] * 41}, {**proposal(), "scope": "x" * 160_001}):
            self.assertEqual("invalid", self.audit.submit(value)["status"])
        for field in ("decision", "basis", "evidence"):
            data = proposal()
            data["entities"][0][field] = {"bad": "type"}
            self.assertEqual("invalid", self.audit.submit(data)["status"])

    def test_web_content_cannot_submit_audit(self):
        other = ResearchEvidenceAudit()
        other.observe(self.audit.submit(proposal()))
        self.assertEqual("not_submitted", other.report()["status"])
        self.assertEqual(0, other.report()["observed"]["source_urls"])

    def test_report_is_an_isolated_snapshot(self):
        result = self.audit.submit(proposal())
        result["claims"][0]["assessment"] = "forged"
        self.assertEqual("supported", self.audit.report()["claims"][0]["assessment"])

    def test_schema_and_tool_are_registered(self):
        spec = tool_spec()
        self.assertEqual(TOOL, spec["name"])
        self.assertEqual(80, spec["inputSchema"]["properties"]["claims"]["maxItems"])
        server = CodexAppServer("codex", {}, lambda *_: None)
        self.assertIn(TOOL, [tool["name"] for tool in server._dynamic_tools])

    def test_codex_tool_checkpoint_response_and_task_isolation(self):
        server = CodexAppServer("codex", {}, lambda *_: None)
        run, other = CodexRun(task_id="a"), CodexRun(task_id="b")
        server._runs.update(a=run, b=other)
        run.research_audit.observe(observation())
        with patch.object(server, "_write_server_response") as send, patch.object(server, "_checkpoint_progress") as checkpoint:
            server._execute_dynamic_tool_call("a", {"id": "call"}, {"tool": TOOL, "arguments": proposal()}, {})
            result = send.call_args.args[1]
            self.assertTrue(result["success"])
            self.assertEqual("recorded", json.loads(result["contentItems"][0]["text"])["status"])
            checkpoint.assert_called_once()
        self.assertEqual("not_submitted", other.research_audit.report()["status"])

    def test_closed_task_does_not_mutate_audit(self):
        server = CodexAppServer("codex", {}, lambda *_: None)
        run = CodexRun(task_id="done", finished=True)
        server._runs["done"] = run
        with patch.object(server, "_write_server_response") as send:
            server._execute_dynamic_tool_call("done", {"id": "call"}, {"tool": TOOL, "arguments": proposal()}, {})
        self.assertFalse(send.call_args.args[1]["success"])
        self.assertEqual("not_submitted", run.research_audit.report()["status"])


if __name__ == "__main__":
    unittest.main()
