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


if __name__ == "__main__":
    unittest.main()
