import hashlib
import unittest
from unittest.mock import patch

from collaboration_receive_observation import observe, RESPONSE_TYPES, STAGES


class CollaborationReceiveObservationTest(unittest.TestCase):
    def test_exact_monotonic_phases_and_private_content_free_token(self):
        timings = [("desktop_request_received", 10_000_000), ("desktop_handler_started", 90_000_000),
                   ("desktop_decrypt_started", 120_000_000), ("desktop_signal_decrypt_finished", 145_000_000)]
        for kind in RESPONSE_TYPES:
            for stage in STAGES:
                with patch("collaboration_receive_observation.log.info") as log:
                    observe({"type": kind, "request_id": "private-request", "result": "private-content",
                             "task_id": "private-task", "client_route_id": "private-route"},
                            timings, stage, 200_000_000)
                    self.assertEqual((hashlib.sha256(b"private-request").hexdigest()[:16], stage, 80.0, 25.0, 110.0),
                                     log.call_args.args[1:])
                    self.assertNotIn("private-", str(log.call_args))

    def test_recovered_or_incomplete_timing_is_unknown_not_zero(self):
        with patch("collaboration_receive_observation.log.info") as log:
            observe({"type": "collaboration_recall_result", "request_id": "request"}, [], "stored", 100)
            self.assertEqual((-1, -1, -1), log.call_args.args[-3:])
            observe({"type": "collaboration_recall_result", "request_id": "request"},
                    [("desktop_handler_started", 200)], "stored", 100)
            self.assertEqual(-1, log.call_args.args[-1])

    def test_other_message_types_and_invalid_request_ids_are_not_traced(self):
        with patch("collaboration_receive_observation.log.info") as log:
            for payload in (None, [], {"type": []}, {"type": {}}):
                observe(payload, [], "stored", 0)
            observe({"type": "peer_message", "request_id": "request"}, [], "stored", 0)
            for request_id in (None, [], "", "x" * 129):
                observe({"type": "collaboration_recall_result", "request_id": request_id}, [], "stored", 0)
            log.assert_not_called()

    def test_diagnostics_error_cannot_change_dispatch(self):
        with patch("collaboration_receive_observation.log.info", side_effect=OSError("private-path")):
            self.assertIsNone(observe({"type": "collaboration_recall_result", "request_id": "request"}, [], "stored", 0))


if __name__ == "__main__":
    unittest.main()
