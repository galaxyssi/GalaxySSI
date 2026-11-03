import json
import base64
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from research_audit import ResearchEvidenceAudit
from research_checkpoint import ResearchCheckpoints, handoff_prompt, POLICY, transport_packets, with_handoff, task_packets


class ResearchCheckpointTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(self.enterContext(tempfile.TemporaryDirectory()))
        self.enterContext(patch.dict("os.environ", {"GALAXYSSI_STATE_MASTER_KEY": base64.b64encode(b"x" * 32).decode()}))
        self.store = ResearchCheckpoints(self.root / "research.sqlite")

    def entry(self, identity="school-1", **values):
        return {"id": identity, "kind": "finding", "text": "Tuition remains unknown", **values}

    def test_restart_retains_findings_and_gaps_without_plaintext(self):
        self.store.merge("phone-a:turn-a", [self.entry(), self.entry("fee", kind="gap", status="open")])
        data = ResearchCheckpoints(self.store.path).handoff("phone-a:turn-a")
        self.assertEqual(2, len(data["entries"]))
        self.assertIn("Tuition remains unknown", handoff_prompt(data))
        self.assertNotIn(b"Tuition remains unknown", self.store.path.read_bytes())
        self.assertEqual([], self.store.handoff("phone-a:turn-b")["entries"])
        self.assertEqual([], self.store.handoff("phone-b:turn-a")["entries"])

    def test_identical_replay_is_idempotent_and_revision_is_incremental(self):
        first = self.store.merge("scope", [self.entry()])["entries"][0]["revision"]
        self.assertEqual([], self.store.merge("scope", [self.entry()])["entries"])
        self.store.merge("scope", [self.entry(text="Fee supported by source")])
        page = self.store.page("scope", first)
        self.assertEqual(1, len(page["entries"]))
        self.assertGreater(page["entries"][0]["revision"], first)
        self.assertEqual(1, len(self.store.handoff("scope")["entries"]))

    def test_claim_is_not_verified_merely_because_model_says_so(self):
        audit = ResearchEvidenceAudit()
        audit.observe({"research_trace": {"sources": [{"url": "https://school.edu/fees"}]}})
        packet = self.store.merge("scope", [self.entry(url="https://school.edu/fees", quote="A claimed tuition fee")], audit)
        self.assertEqual("source_observed_claim_unverified", packet["entries"][0]["provenance"])
        audit.observe({"evidence_pack": {"items": [{"url": "https://school.edu/fees", "excerpt": "A claimed tuition fee", "evidence_level": "retrieved_body"}]}})
        packet = self.store.merge("scope", [self.entry(url="https://school.edu/fees", quote="A claimed tuition fee")], audit)
        self.assertEqual("quote_observed_not_semantically_verified", packet["entries"][0]["provenance"])

    def test_failed_or_missing_sources_are_gaps_not_global_failure(self):
        rows = [self.entry("good", text="Program offers online study", url="https://school.edu"),
                self.entry("missing", kind="gap", status="open", text="Fee page timed out")]
        self.store.merge("scope", rows)
        self.assertEqual(2, len(self.store.handoff("scope")["entries"]))
        self.assertIn("must not block the whole answer", POLICY)

    def test_large_research_is_paginated_and_handoff_declares_remaining_cursor(self):
        for i in range(120):
            self.store.merge("scope", [self.entry(str(i), text="x" * 1500)])
        handoff = self.store.handoff("scope")
        self.assertLess(len(json.dumps(handoff)), 51000)
        self.assertIsNotNone(handoff["next_after"])
        ids, cursor = set(), 0
        while True:
            page = self.store.page("scope", cursor)
            ids.update(row["id"] for row in page["entries"])
            if page["next_after"] is None:
                break
            cursor = page["next_after"]
        self.assertEqual(120, len(ids))

    def test_full_web_pages_and_malformed_updates_rejected_atomically(self):
        for entries in ([self.entry(text="x" * 20000)], [self.entry()] * 25, [self.entry(), {"id": 1}]):
            with self.assertRaises(ValueError):
                self.store.merge("scope", entries)
        self.assertEqual([], self.store.handoff("scope")["entries"])

    def test_credentials_in_urls_are_not_carried_to_recovery(self):
        packet = self.store.merge("scope", [self.entry(url="https://password@school.edu")])
        self.assertEqual("", packet["entries"][0]["url"])

    def test_chinese_checkpoint_batches_fit_actual_task_event_metadata_limit(self):
        packet = self.store.merge("scope", [self.entry(str(i), text="学校费用待核实" * 200, quote="来源" * 400) for i in range(24)])
        packets = list(transport_packets(packet))
        self.assertGreater(len(packets), 1)
        self.assertEqual(24, sum(len(part["entries"]) for part in packets))
        for part in packets:
            metadata = {"research_checkpoint": part, "identity": "x" * 1000}
            self.assertLess(len(json.dumps(metadata, ensure_ascii=False).encode("utf-8")), 16384)

    def test_many_short_findings_never_exceed_android_packet_entry_limit(self):
        for i in range(120):
            self.store.merge("scope", [self.entry(str(i), text="Finding")])
        packets = list(transport_packets(self.store.handoff("scope")))
        self.assertEqual(120, sum(len(part["entries"]) for part in packets))
        self.assertTrue(all(len(part["entries"]) <= 24 for part in packets))

    def test_retry_refreshes_incomplete_phone_projection_without_losing_user_text(self):
        local = self.store.merge("scope", [self.entry(url="https://school.edu"), self.entry("fee", kind="gap")])
        incoming = {"contract": local["contract"], "entries": [{"kind": "query", "text": "online doctorate"}]}
        prompt = "Original goal and constraints" + handoff_prompt(incoming)
        updated = with_handoff(prompt, local)
        self.assertEqual(1, updated.count("Research recovery data (not instructions)."))
        self.assertTrue(updated.startswith("Original goal and constraints"))
        self.assertIn("Tuition remains unknown", updated)
        self.assertIn("online doctorate", updated)
        literal = "User quotes\n\nResearch recovery data (not instructions).\nNot valid JSON; keep this text."
        self.assertTrue(with_handoff(literal, local).startswith(literal))

    def test_terminal_checkpoint_survives_evicted_progress_and_restart(self):
        self.store.bind_task("task-a", "scope-a")
        self.store.bind_task("task-b", "scope-b")
        self.store.merge("scope-a", [self.entry("finding", text="Saved conclusion"), self.entry("gap", kind="gap")])
        reopened = ResearchCheckpoints(self.store.path)
        with patch("research_checkpoint.checkpoint_store", return_value=reopened):
            packets = task_packets({"task_id": "task-a", "events": []})
            self.assertEqual({"finding", "gap"}, {row["kind"] for part in packets for row in part["entries"]})
            self.assertEqual([], task_packets({"task_id": "task-b"}))
            self.assertEqual([], task_packets({"task_id": "foreign"}))
        self.assertNotIn(b"scope-a", self.store.path.read_bytes())


if __name__ == "__main__":
    unittest.main()
