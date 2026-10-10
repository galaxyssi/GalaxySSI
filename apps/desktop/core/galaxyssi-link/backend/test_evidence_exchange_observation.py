import hashlib
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

import codex_tool_evidence_bridge as bridge


class EvidenceExchangeObservationTest(unittest.TestCase):
    def test_logs_only_correlated_stage_and_timing(self):
        request = {"request_id": "private-rpc", "content": "private-evidence"}
        with patch.object(bridge.log, "info") as log, patch.object(bridge.time, "monotonic", return_value=2):
            bridge.observe(request, "lookup_ready", 1)
        args = log.call_args.args
        self.assertEqual(hashlib.sha256(b"private-rpc").hexdigest()[:16], args[1])
        self.assertEqual(("lookup_ready", 1000, None), args[2:5])
        self.assertNotIn("private-", str(args))

    def test_query_stays_successful_when_logging_fails(self):
        result = {"status": "ready", "content": "private-evidence"}
        store = SimpleNamespace(query=Mock(return_value=result))
        with patch.object(bridge.log, "info", side_effect=OSError("private-path")):
            self.assertIs(result, bridge.query(SimpleNamespace(tool_evidence=store),
                                               {"request_id": "request"}, client_route_id="private-route"))
        store.query.assert_called_once()

    def test_publication_is_exactly_once_and_keeps_result(self):
        for result in (True, False):
            publish = Mock(return_value=result)
            with patch.object(bridge.log, "info") as log:
                self.assertIs(result, bridge.publish_response({"request_id": "request"}, publish))
            publish.assert_called_once_with()
            self.assertEqual(["publish_started", "publish_finished"], [c.args[2] for c in log.call_args_list])
            self.assertIs(result, log.call_args.args[4])

    def test_observation_failure_does_not_repeat_or_drop_publish(self):
        publish = Mock(return_value=True)
        with patch.object(bridge.log, "info", side_effect=OSError("private-path")):
            self.assertTrue(bridge.publish_response({"request_id": "request"}, publish))
        publish.assert_called_once_with()
        publish = Mock(side_effect=RuntimeError("publication failed"))
        with self.assertRaises(RuntimeError):
            bridge.publish_response({"request_id": "request"}, publish)
        publish.assert_called_once_with()

    def test_malformed_tokens_and_stages_do_not_log_content(self):
        with patch.object(bridge.log, "info") as log:
            for value in (None, [], {}, {"request_id": []}, {"request_id": ""}, {"request_id": "x" * 129}):
                bridge.observe(value, "lookup_ready", 0)
            bridge.observe({"request_id": "request"}, "private-content", 0)
        log.assert_not_called()
