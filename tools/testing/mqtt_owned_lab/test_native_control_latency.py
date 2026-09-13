import unittest
from unittest.mock import AsyncMock, patch

import native_control_latency as control


class ControlEvidenceTests(unittest.TestCase):
    def test_overlap_requires_queued_chunk_not_already_receipted(self):
        probe = {"stages": {"started": 100}}
        chunks = {"pending": {"stages": {"queued": 90}},
                  "later": {"stages": {"queued": 101}},
                  "completed": {"stages": {"queued": 70, "receipt_committed": 99}},
                  "concurrent": {"stages": {"queued": 80, "receipt_committed": 110}},
                  "never_queued": {"stages": {"started": 90}}}
        self.assertEqual(["pending", "concurrent"], control.overlapping_chunks(probe, chunks))

    def test_delivery_ack_is_not_enough_for_cancel_completion(self):
        sample = {"stages": {"started": 1, "queued": 2, "first_publish": 3, "receipt_committed": 4},
                  "packets": {"a": {"accepted": True, "at_ns": 3, "bytes": 50, "broker": "owned"}}}
        with self.assertRaises(KeyError):
            control.control_summary([sample])
        sample["stages"]["cancel_event_received"] = 5
        self.assertEqual(4e-6, control.control_summary([sample])["request_to_cancel_event_ms"]["p95"])


class ControlExitTests(unittest.IsolatedAsyncioTestCase):
    async def test_failed_provisional_gate_has_nonzero_exit(self):
        for passed, expected in ((False, 2), (True, 0)):
            with patch("sys.argv", ["native_control_latency.py", "--endpoint-python", "unused", "--report-dir", "unused"]), \
                    patch.object(control, "OwnedBrokers") as factory, \
                    patch.object(control.asyncio, "to_thread", new_callable=AsyncMock) as run, patch("builtins.print"):
                factory.return_value.__aenter__.return_value = object()
                run.return_value = {"provisional_gate": {"passed": passed}}
                self.assertEqual(expected, await control.main())
                factory.return_value.__aexit__.assert_awaited_once()


if __name__ == "__main__":
    unittest.main()
