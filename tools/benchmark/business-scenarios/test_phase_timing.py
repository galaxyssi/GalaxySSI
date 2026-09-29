import copy
import unittest
from phase_timing import summarize_phases


def sample():
    return {"driver_schema": 4, "elapsed_ms": 100,
            "assessment": {"correct": True, "all_artifacts_verified": True}, "phase_timing": {
        "schema": 1, "clock": "elapsed_realtime", "reply_terminal_ms": 100,
        "assessment_started_ms": 110, "assessment_completed_ms": 200, "assessment_duration_ms": 90,
        "ui_check_ms": 30, "observed_end_to_end_ms": 230, "artifacts_present_ms": 150,
        "artifact_presence_wait_ms": 40, "artifact_audit_ms": 50, "save_verification_ms": 20,
        "artifacts_verified_ms": 200}}


class PhaseTimingTest(unittest.TestCase):
    def test_legacy_is_unmeasured_not_zero_or_inferred(self):
        result = summarize_phases([sample(), {"driver_schema": 3, "elapsed_ms": 500}])
        self.assertEqual(1, result["measured_turns"])
        self.assertEqual(1, result["unmeasured_turns"])
        self.assertEqual(230, result["phases"]["observed_end_to_end_ms"]["p50_ms"])
        self.assertIsNone(result["phases"]["observed_end_to_end_ms"]["p95_ms"])

    def test_failed_or_text_only_has_no_fake_ready_latency(self):
        failed = sample()
        failed["assessment"]["correct"] = False
        failed["phase_timing"].update(artifacts_present_ms=None, artifacts_verified_ms=None)
        text = copy.deepcopy(failed)
        for key in ("artifact_presence_wait_ms", "artifact_audit_ms", "save_verification_ms"):
            text["phase_timing"][key] = None
        result = summarize_phases([failed, text])
        self.assertEqual(0, result["phases"]["artifacts_verified_ms"]["samples"])
        self.assertEqual(1, result["phases"]["artifact_audit_ms"]["samples"])

    def test_bad_chronology_and_non_numeric_values_are_rejected(self):
        for key, value in (("reply_terminal_ms", 101), ("ui_check_ms", -1),
                           ("observed_end_to_end_ms", 199), ("artifact_presence_wait_ms", 400),
                           ("save_verification_ms", 51), ("artifacts_verified_ms", 199),
                           ("assessment_started_ms", True), ("artifact_audit_ms", "50")):
            turn = sample()
            turn["phase_timing"][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                summarize_phases([turn])

    def test_p95_requires_thirty_actual_samples(self):
        self.assertIsNone(summarize_phases([sample()] * 29)["phases"]["observed_end_to_end_ms"]["p95_ms"])
        self.assertEqual(230, summarize_phases([sample()] * 30)["phases"]["observed_end_to_end_ms"]["p95_ms"])

    def test_report_keeps_reply_latency_and_full_workload_denominator(self):
        from artifact_catalog import catalog
        from report import summarize
        plan = catalog()
        turn = sample()
        turn.update(index=0, state="completed")
        turn["assessment"].update(content_verified=False, requires_human_review=True)
        report = {"case_id": "A032", "catalog_sha256": plan["catalog_sha256"], "turns": [turn]}
        result = summarize(plan, [report])
        self.assertEqual(100, result["latency"]["p50_ms"])
        self.assertEqual(230, result["phase_latency"]["phases"]["observed_end_to_end_ms"]["p50_ms"])
        self.assertEqual(0, result["correct_turns"])
        self.assertEqual(100, result["planned_cases"])
        self.assertEqual(1100, result["planned_turns"])
        self.assertEqual(1099, result["unobserved_turns"])
        self.assertEqual("incomplete", result["overall_status"])


if __name__ == "__main__":
    unittest.main()
