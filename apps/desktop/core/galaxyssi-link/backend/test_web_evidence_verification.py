import json
import unittest

from model_directed_search import _retrieved_document_from_output, render_search_evidence
from web_evidence_pack import (
    build_evidence_pack,
    citation_repair_prompt,
    validate_answer_citations,
    verify_evidence_pack,
)


class WebEvidenceVerificationTest(unittest.TestCase):
    def test_pack_verifies_and_flags_cross_domain_numeric_conflict(self):
        pack = build_evidence_pack(
            query="launch facts",
            status="completed",
            documents=[
                self.document(
                    "https://alpha.example/report",
                    "The launch year is 2026 and tested capacity is 64 GB.",
                    "a" * 64,
                ),
                self.document(
                    "https://beta.example/report",
                    "The launch year is 2026 and tested capacity is 128 GB.",
                    "b" * 64,
                ),
            ],
            results=[],
            receipts=[],
            generated_at_millis=1,
        )

        self.assertEqual("verified", pack["verification"]["status"])
        self.assertEqual("potential_conflict", pack["conflict_review"]["status"])
        self.assertEqual(2, pack["conflict_review"]["independent_retrieved_domain_count"])
        self.assertEqual(1, len(pack["conflict_review"]["potential_conflicts"]))
        self.assertEqual("current_model_required", pack["conflict_review"]["semantic_resolution"])

    def test_citation_validation_rejects_missing_and_foreign_urls(self):
        pack = build_evidence_pack(
            query="fixture",
            status="completed",
            documents=[self.document(
                "https://example.com/report",
                "Verified evidence.",
                "d" * 64,
            )],
            results=[],
            receipts=[],
            generated_at_millis=2,
        )
        encoded = [("web_research", json.dumps({"evidence_pack": pack}))]

        valid = validate_answer_citations(
            "Supported by [the report](https://example.com/report).",
            encoded,
        )
        missing = validate_answer_citations("Unsupported draft.", encoded)
        foreign = validate_answer_citations(
            "See [another page](https://attacker.example/report).",
            encoded,
        )

        self.assertTrue(valid.valid)
        self.assertEqual("missing_citations", missing.status)
        self.assertEqual("foreign_citations", foreign.status)
        self.assertEqual(("https://attacker.example/report",), foreign.invalid_citation_urls)
        self.assertIn("https://example.com/report", citation_repair_prompt(missing, encoded))

    def test_tampered_citation_fails_verification(self):
        pack = build_evidence_pack(
            query="fixture",
            status="completed",
            documents=[self.document(
                "https://example.com/report",
                "Verified evidence.",
                "e" * 64,
            )],
            results=[],
            receipts=[],
            generated_at_millis=3,
        )
        pack["items"][0]["citation_id"] = "0" * 24

        report = verify_evidence_pack(pack)

        self.assertEqual("failed", report["status"])
        self.assertEqual(1, report["invalid_item_count"])

    def test_desktop_page_reader_consumes_unified_pack_after_raw_body_removal(self):
        pack = build_evidence_pack(
            query="fixture",
            status="completed",
            documents=[self.document(
                "https://example.com/report",
                "A retrieved body that remains available through the compact evidence pack.",
                "f" * 64,
            )],
            results=[],
            receipts=[],
            generated_at_millis=4,
        )

        document = _retrieved_document_from_output({
            "documents": [{"url": "https://example.com/report"}],
            "evidence_pack": pack,
        })

        self.assertIsNotNone(document)
        self.assertIn("retrieved body", document["content"])

    def test_model_directed_prompt_uses_pack_ids_and_conflict_contract(self):
        rows = [{
            "url": "https://example.com/report",
            "title": "Report",
            "excerpt": "Search discovery evidence",
            "content_sha256": "1" * 64,
            "engines": ["bing"],
        }]
        prompt = render_search_evidence("fixture", rows)

        self.assertIn("Cite only URLs listed in the Evidence Pack", prompt)
        self.assertIn("https://example.com/report", prompt)
        self.assertRegex(prompt, r"\[[a-f0-9]{24}\]")

    @staticmethod
    def document(url, content, content_hash):
        return {
            "url": url,
            "title": "Evidence",
            "content": content,
            "content_sha256": content_hash,
            "retrieved_at_millis": 1,
            "content_type": "text/html",
        }


if __name__ == "__main__":
    unittest.main()
