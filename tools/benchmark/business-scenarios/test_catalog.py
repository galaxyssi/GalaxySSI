import copy
import unittest
from catalog import catalog
from report import summarize


class CatalogTest(unittest.TestCase):
    def test_full_inventory_and_modalities(self):
        plan = catalog()
        self.assertEqual(100, len(plan["cases"]))
        self.assertEqual(100, len({c["id"] for c in plan["cases"]}))
        self.assertEqual(100, len({c["name"] for c in plan["cases"]}))
        self.assertEqual(1100, sum(len(c["turns"]) for c in plan["cases"]))
        self.assertEqual(5, len({c["modality"] for c in plan["cases"]}))
        self.assertEqual(plan["catalog_sha256"], catalog()["catalog_sha256"])
        self.assertEqual(100, len({c["turns"][2]["prompt"] for c in plan["cases"]}))
        self.assertTrue(all(c["turns"][2]["kind"] == "business_decision" for c in plan["cases"]))

    def test_business_rules_use_real_domain_operations(self):
        cases = catalog()["cases"]
        self.assertEqual(39, cases[0]["turns"][2]["expected"]["补货量"])
        self.assertEqual(67.5, cases[1]["turns"][2]["expected"]["应付"])
        warehouse = cases[7]
        source = warehouse["turns"][0]["expected"]
        self.assertEqual(source["乙"] - source["甲"], warehouse["turns"][2]["expected"]["剩余容量"])
        education = cases[58]
        original = education["turns"][0]["expected"]["合计"]
        self.assertEqual(5 * ((original + 2) // 3), education["turns"][2]["expected"]["五天"])

    def test_corrections_and_rollback_do_not_reuse_forecast(self):
        for case in catalog()["cases"]:
            turns = case["turns"]
            original = turns[0]["expected"]
            self.assertEqual(original["合计"], original["甲"] + original["乙"] + original["丙"])
            revised = turns[3]["expected"]["修订合计"]
            self.assertEqual(revised * 2, turns[4]["expected"]["预测合计"])
            self.assertEqual(revised, turns[8]["expected"]["当前合计"])
            self.assertEqual(revised, turns[10]["expected"]["当前合计"])
            self.assertEqual(original["合计"], turns[10]["expected"]["原始合计"])
            self.assertEqual(list(range(11)), [t["index"] for t in turns])

    def test_no_reports_is_not_success(self):
        result = summarize(catalog(), [])
        self.assertEqual("incomplete", result["overall_status"])
        self.assertEqual(1100, result["unobserved_turns"])
        self.assertEqual(0, result["correct_turns"])

    def test_partial_reports_keep_full_denominator(self):
        plan = catalog()
        sample = {"case_id": "B001", "catalog_sha256": plan["catalog_sha256"],
                  "turns": [{"index": 0, "state": "completed", "elapsed_ms": 1000,
                             "assessment": {"correct": True, "requires_human_review": True},
                             "rendered": True, "timer_stopped": True, "within_latency_target": True}]}
        result = summarize(plan, [sample])
        self.assertEqual(1, result["correct_turns"])
        self.assertEqual(1099, result["unobserved_turns"])
        self.assertIsNone(result["latency"]["p95_ms"])
        self.assertEqual(1, result["human_review_pending"])
        self.assertEqual(1, result["capture_stability_unobserved"])
        self.assertEqual(0, result["stable_capture_turns"])
        bad = copy.deepcopy(sample)
        bad["catalog_sha256"] = "different"
        with self.assertRaises(ValueError):
            summarize(plan, [bad])
        with self.assertRaises(ValueError):
            summarize(plan, [sample, sample])
        repeated = copy.deepcopy(sample)
        repeated["turns"].append(copy.deepcopy(repeated["turns"][0]))
        with self.assertRaises(ValueError):
            summarize(plan, [repeated])

    def test_transient_capture_is_not_stable_visual_evidence(self):
        plan = catalog()
        turn = {"index": 0, "state": "completed", "elapsed_ms": 1000,
                "assessment": {"correct": True}, "rendered": True,
                "timer_stopped": True, "within_latency_target": True, "visual_capture_stable": False}
        sample = {"case_id": "B001", "catalog_sha256": plan["catalog_sha256"], "turns": [turn]}
        result = summarize(plan, [sample])
        self.assertEqual(0, result["stable_capture_turns"])
        self.assertIn("visual_capture_unstable", result["failures"][0]["reasons"])
        turn["visual_capture_stable"] = True
        self.assertEqual(1, summarize(plan, [sample])["stable_capture_turns"])

    def test_only_current_row_captures_prove_reply_and_timer_visibility(self):
        plan = catalog()
        turn = {"index": 0, "state": "completed", "elapsed_ms": 1000,
                "assessment": {"correct": True}, "rendered": True, "timer_stopped": True,
                "within_latency_target": True, "visual_capture_stable": True, "visual_window_focused": True}
        sample = {"case_id": "B001", "catalog_sha256": plan["catalog_sha256"], "turns": [turn]}
        old = summarize(plan, [sample])
        self.assertEqual(0, old["rendered_turns"])
        self.assertEqual(0, old["timer_stopped_turns"])
        self.assertEqual(1, old["legacy_visual_evidence_unverified"])
        turn.update(driver_schema=3, visual_entry_id="actual-final-row", timer_observed=True)
        current = summarize(plan, [sample])
        self.assertEqual(1, current["rendered_turns"])
        self.assertEqual(1, current["timer_stopped_turns"])
        turn["visual_entry_id"] = ""
        turn["timer_observed"] = False
        self.assertEqual(0, summarize(plan, [sample])["rendered_turns"])
        self.assertEqual(0, summarize(plan, [sample])["timer_stopped_turns"])


if __name__ == "__main__":
    unittest.main()
