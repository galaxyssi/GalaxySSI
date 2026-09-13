"""Connector diagnostics must not confuse queue acceptance with phone delivery."""
import unittest
from unittest.mock import patch

import agent_gateway as gateway
import mqtt_bridge as bridge


class ConnectorSelfTestDeliveryTest(unittest.TestCase):
    def setUp(self):
        self.spec = gateway.AgentSpec("codex", "Codex Agent", "local-cli", None, 60)
        specs = patch.object(gateway, "all_agent_specs", return_value={"codex": self.spec})
        specs.start()
        self.addCleanup(specs.stop)
        status = patch.object(gateway, "agent_status", return_value={
            "id": "codex", "name": "Codex Agent", "status": "ready", "detail": "ready"})
        self.status = status.start()
        self.addCleanup(status.stop)

    def run_delivery(self, result):
        with patch.object(bridge, "publish_mobile_test_message", return_value=result):
            return gateway.connector_self_test(include_mobile_delivery=True)

    def test_committed_queue_is_pending_not_delivery_success(self):
        report = self.run_delivery({"ok": True, "queued": True, "delivered": False})
        self.assertEqual(["codex"], report["summary"]["mobile_delivery_queued"])
        self.assertEqual([], report["summary"]["mobile_delivery_ok"])
        self.assertEqual([], report["summary"]["mobile_delivery_failed"])
        item = report["results"][0]
        self.assertIsNone(item["mobile_delivery"]["ok"])
        self.assertTrue(item["mobile_delivery"]["accepted"])
        self.assertEqual("mobile_delivery_queued", item["mobile_delivery"]["code"])
        self.assertEqual("waiting_delivery", item["overall"])

    def test_empty_failed_partial_and_unproven_results_are_not_success(self):
        for result in (None, {}, {"ok": False}, {"ok": True},
                       {"ok": False, "queued": True, "delivery_state": "partially_queued"}):
            with self.subTest(result=result):
                report = self.run_delivery(result)
                self.assertEqual([], report["summary"]["mobile_delivery_ok"])
                self.assertEqual([], report["summary"]["mobile_delivery_queued"])
                self.assertEqual(["codex"], report["summary"]["mobile_delivery_failed"])
                self.assertEqual("delivery_failed", report["results"][0]["overall"])

    def test_exception_is_failure_and_disabled_test_does_not_send(self):
        with patch.object(bridge, "publish_mobile_test_message", side_effect=RuntimeError("storage unavailable")) as send:
            report = gateway.connector_self_test()
            self.assertEqual(["codex"], report["summary"]["mobile_delivery_failed"])
            send.reset_mock()
            skipped = gateway.connector_self_test(include_mobile_delivery=False)
            send.assert_not_called()
            self.assertEqual("skipped", skipped["results"][0]["mobile_delivery"]["status"])
            self.assertEqual([], skipped["summary"]["mobile_delivery_queued"])

    def test_pending_delivery_does_not_hide_setup_or_agent_failures(self):
        with patch.object(bridge, "publish_mobile_test_message", return_value={"ok": True, "queued": True}), \
             patch.object(gateway, "ask_agent_sync", side_effect=RuntimeError("agent offline")):
            failed = gateway.connector_self_test(include_agent_calls=True)
            self.assertEqual("agent_failed", failed["results"][0]["overall"])
            self.status.return_value = {"id": "codex", "status": "unavailable"}
            setup = gateway.connector_self_test()
            self.assertEqual("needs_setup", setup["results"][0]["overall"])


if __name__ == "__main__":
    unittest.main()
