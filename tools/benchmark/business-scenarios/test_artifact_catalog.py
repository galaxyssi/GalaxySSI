import unittest
from collections import Counter

from artifact_catalog import catalog
from report import summarize


class ArtifactCatalogTest(unittest.TestCase):
    def test_inventory_covers_one_hundred_deliverables(self):
        plan = catalog()
        self.assertEqual(100, len(plan["cases"]))
        self.assertEqual(100, len({c["name"] for c in plan["cases"]}))
        self.assertEqual(25, len({c["domain"] for c in plan["cases"]}))
        self.assertEqual({"artifact_" + f: 25 for f in ("docx", "xlsx", "pptx", "png")},
                         Counter(c["modality"] for c in plan["cases"]))

    def test_revisions_and_restoration_are_explicit(self):
        for case in catalog()["cases"]:
            turns = case["turns"]
            self.assertEqual(11, len(turns))
            image_edit = case.get("workflow") == "image_edit"
            if not image_edit:
                initial = turns[0]["artifact_expectations"]["expected_amount"]
                self.assertEqual(initial + 56, turns[1]["artifact_expectations"]["expected_amount"])
                self.assertEqual(initial + 156, turns[3]["artifact_expectations"]["expected_amount"])
                self.assertEqual(initial, turns[6]["artifact_expectations"]["expected_amount"])
            for i, turn in enumerate(turns):
                expected = turn["artifact_expectations"]
                self.assertEqual(f"ART-{int(case['id'][1:]):03d}-v{i+1:02d}", expected["name_prefix"])
                self.assertEqual(i >= 9 and not image_edit, "pdf" in expected["extensions"])
                self.assertTrue(expected["requires_human_review"])
                if not expected.get("text_only"):
                    self.assertIn("不能只给本机路径", turn["prompt"])
                    self.assertIn("不要覆盖旧版", turn["prompt"])

    def test_image_edit_oracles_are_not_sent_as_prompts(self):
        images = [c for c in catalog()["cases"] if c.get("workflow") == "image_edit"]
        self.assertEqual(10, len(images))
        for case in images:
            self.assertTrue(case["fixtures"])
            self.assertIn("Synthetic", case["handwriting_scope"])
            self.assertEqual([], case["turns"][7]["artifact_expectations"]["extensions"])
            self.assertTrue(case["turns"][7]["artifact_expectations"]["text_only"])
            for turn in case["turns"]:
                self.assertNotIn("annotation_oracle", turn["prompt"])
                self.assertEqual([5], turn["artifact_expectations"]["annotation_oracle"]["unreadable_rows"])
                if not turn["artifact_expectations"]["text_only"]:
                    self.assertEqual(["png", "jpg", "jpeg"], turn["artifact_expectations"]["image_extensions"])
            self.assertEqual([1], case["turns"][5]["artifact_expectations"]["annotation_oracle"]["visible_corrections"])
            self.assertEqual([1, 3], case["turns"][6]["artifact_expectations"]["annotation_oracle"]["visible_corrections"])

    def test_catalog_hash_is_reproducible(self):
        self.assertEqual(catalog()["catalog_sha256"], catalog()["catalog_sha256"])

    def test_download_success_does_not_claim_content_accuracy(self):
        plan = catalog()
        report = {"case_id": "A001", "catalog_sha256": plan["catalog_sha256"], "turns": [
            {"index": 0, "state": "completed", "elapsed_ms": 1000,
             "assessment": {"correct": True, "content_verified": False, "requires_human_review": True},
             "rendered": True, "timer_stopped": True, "within_latency_target": True}]}
        result = summarize(plan, [report])
        self.assertEqual(0, result["correct_turns"])
        self.assertEqual(1, result["artifact_delivery_checks_passed"])
        self.assertEqual(1, result["artifact_content_unverified"])
        self.assertEqual("incomplete", result["overall_status"])

    def test_late_receipt_does_not_replace_timeout_or_latency(self):
        plan = catalog()
        report = {"case_id": "A003", "catalog_sha256": plan["catalog_sha256"], "turns": [
            {"index": 0, "state": "observation_timeout", "elapsed_ms": 600356,
             "late_receipt": {"correct": True, "visible": True}},
            {"index": 1, "state": "completed", "elapsed_ms": 151263,
             "assessment": {"correct": True, "content_verified": False},
             "driver_schema": 3, "visual_entry_id": "revision-reply", "rendered": True,
             "visual_window_focused": True, "visual_capture_stable": True,
             "timer_observed": True, "timer_stopped": True, "within_latency_target": True}]}
        result = summarize(plan, [report])
        self.assertEqual(2, result["observed_turns"])
        self.assertEqual(1, result["completed_turns"])
        self.assertEqual(0, result["correct_turns"])
        self.assertEqual(1, result["artifact_delivery_checks_passed"])
        self.assertEqual(151263, result["latency"]["p50_ms"])
        self.assertIsNone(result["latency"]["p95_ms"])
        self.assertIn({"case_id": "A003", "turn": 0, "reasons": ["observation_timeout"]}, result["failures"])
        self.assertEqual("incomplete", result["overall_status"])


if __name__ == "__main__":
    unittest.main()
