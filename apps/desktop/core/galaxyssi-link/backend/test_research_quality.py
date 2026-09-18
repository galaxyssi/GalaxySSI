import json
import unittest
from pathlib import Path
from unittest.mock import patch

from research_quality import assess_answer, quality_repair_prompt, research_quality_prompt, research_stage, standard
from response_policy import response_policy_prompt, compact_codex_turn_prompt
from response_self_check import evaluate_response, response_repair_prompt
from codex_app_server import CODEX_TASK_POLICY, CodexAppServer, CodexRun


class ResearchQualityTests(unittest.TestCase):
    def test_shared_regression_cases(self):
        cases = json.loads((Path(__file__).with_name("research_contract") / "quality-cases.json").read_text(encoding="utf-8"))
        for case in cases:
            with self.subTest(case=case["id"]):
                report = assess_answer(case["answer"], research_observed=case["research"])
                self.assertEqual(case["risks"], report["risks"])
                self.assertEqual("not_independently_verified", report["semantic_verification"])

    def test_all_desktop_prompt_routes_include_same_standard(self):
        for prompt in (response_policy_prompt("question", "en"), compact_codex_turn_prompt("question", "en"), CODEX_TASK_POLICY):
            self.assertIn(research_quality_prompt(), prompt)
        self.assertIn("not proof", standard()["repair"])

    def test_existing_generic_agent_repair_uses_quality_risks(self):
        result = evaluate_response("What is their relationship?", "No authoritative records exist. [Bio](https://example.org/bio)")
        self.assertFalse(result.accepted)
        self.assertIn("unbounded_absence_of_evidence", result.reasons)
        self.assertIn("not proof", response_repair_prompt("What is their relationship?", "draft", result))

    def test_codex_native_search_without_host_pack_can_be_reviewed(self):
        server = CodexAppServer("codex", {}, lambda *_: None)
        run = CodexRun(task_id="quality-native", research_observed=True,
                       final_text="No authoritative records exist.")
        with patch("codex_app_server.threading.Thread") as thread:
            self.assertTrue(server._apply_web_citation_gate("quality-native", run, {}, "turn-1"))
            self.assertTrue(run.citation_repair_attempted)
            thread.return_value.start.assert_called_once()
            args = thread.call_args.kwargs["args"]
            self.assertIn("unbounded_absence_of_evidence", args[4])
            self.assertNotIn("verified Evidence Pack URLs", args[4])

    def test_codex_quality_repair_is_bounded(self):
        run = CodexRun(task_id="quality-second", research_observed=True, citation_repair_attempted=True,
                       final_text="No authoritative records exist.")
        server = CodexAppServer("codex", {}, lambda *_: None)
        with patch("codex_app_server.threading.Thread") as thread:
            self.assertFalse(server._apply_web_citation_gate(run.task_id, run, {}, "turn-1"))
            thread.assert_not_called()
        self.assertIn("did not establish", run.final_text)
        self.assertEqual("needs_review", run.research_quality["status"])

    def test_quality_does_not_search_or_claim_delivery(self):
        report = assess_answer("Supported [fact](https://example.org/paper)", research_observed=True)
        self.assertEqual("no_structural_risk_detected", report["status"])
        self.assertEqual("not_confirmed", research_stage("synthesis_completed")["delivery"])
        with self.assertRaises(ValueError):
            research_stage("delivered")

    def test_repeated_source_failure_does_not_start_a_second_loop_or_fail_the_task(self):
        server = CodexAppServer("codex", {}, lambda *_: None)
        run = CodexRun(task_id="source-failure")
        with patch("codex_app_server.threading.Thread") as thread:
            for _ in range(10):
                server._record_failed_item(run, {"type": "webSearch", "status": "failed", "query": "primary record"})
            thread.assert_not_called()
        self.assertFalse(run.finished)
        self.assertEqual({}, run.failure_counts)

    def test_quality_review_state_is_isolated_per_task(self):
        server = CodexAppServer("codex", {}, lambda *_: None)
        first = CodexRun(task_id="a", research_observed=True, final_text="No authoritative records exist.")
        second = CodexRun(task_id="b", research_observed=True, final_text="A coauthored [paper](https://example.org/paper).")
        with patch("codex_app_server.threading.Thread"):
            self.assertTrue(server._apply_web_citation_gate("a", first, {}, "turn-a"))
            self.assertFalse(server._apply_web_citation_gate("b", second, {}, "turn-b"))
        self.assertTrue(first.citation_repair_attempted)
        self.assertFalse(second.citation_repair_attempted)
        self.assertEqual([], second.research_quality["risks"])

    def test_native_search_and_final_are_distinct_without_host_search(self):
        events = []
        server = CodexAppServer("codex", {}, lambda task, event: events.append(event))
        run = CodexRun(task_id="native", turn_id="turn", thread_id="thread")
        server._runs["native"] = run
        server._turn_tasks["turn"] = "native"
        server._handle_event({"method": "item/completed", "params": {"turnId": "turn", "item": {
            "id": "search", "type": "webSearch", "query": "primary source"}}})
        self.assertTrue(run.research_observed)
        self.assertFalse(run.finished)
        server._handle_event({"method": "item/completed", "params": {"turnId": "turn", "item": {
            "id": "answer", "type": "agentMessage", "phase": "final_answer",
            "text": "A supported [finding](https://example.org/paper)."}}})
        self.assertFalse(any(event.get("output_delta") for event in events))
        server._handle_event({"method": "turn/completed", "params": {"turnId": "turn", "turn": {"status": "completed"}}})
        self.assertTrue(run.finished)
        final = events[-1]
        self.assertEqual("synthesis_completed", final["research"]["stage"])
        self.assertEqual("not_confirmed", final["research"]["delivery"])


if __name__ == "__main__":
    unittest.main()
