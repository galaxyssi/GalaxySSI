from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from evolution_v2.issues import IssueSignalScanner
from evolution_v2.storage import EvolutionV2Store


class IssueTests(unittest.TestCase):
    def test_duplicate_mqtt_signal_is_deduplicated(self):
        with tempfile.TemporaryDirectory() as root:
            store = EvolutionV2Store(Path(root))
            scanner = IssueSignalScanner(store, [])
            text = "duplicate MQTT message replay caused processing stuck"
            first = scanner.ingest_text(text, source="test")
            second = scanner.ingest_text(text, source="test")
            self.assertTrue(first)
            self.assertEqual(first[0].signal_id, second[0].signal_id)
            self.assertEqual(2, second[0].occurrences)
            proposal = scanner.proposal(second[0])
            self.assertTrue(proposal.scope)
            self.assertTrue(proposal.acceptance)


if __name__ == "__main__":
    unittest.main()
