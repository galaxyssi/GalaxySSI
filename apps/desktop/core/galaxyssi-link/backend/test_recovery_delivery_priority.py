"""Recovery controls must not wait behind a saturated ordinary delivery lane."""

from types import SimpleNamespace
import unittest
from unittest.mock import patch

import mqtt_bridge as bridge


RECOVERY_CONTROLS = (
    "agent_task_recovery_result",
    "agent_task_result_page",
    "agent_task_result_receipt_confirmed",
)


class RecoveryDeliveryPriorityTest(unittest.TestCase):
    def test_recovery_controls_use_the_bounded_dependency_lane(self):
        for kind in RECOVERY_CONTROLS:
            with self.subTest(kind=kind):
                priority = bridge._outbound_delivery_priority({"type": kind})
                self.assertGreaterEqual(priority, bridge.OUTBOUND_TERMINAL_RESERVE_THRESHOLD)
                self.assertLess(priority, bridge.OUTBOUND_PRIORITY_TERMINAL)
        self.assertEqual(bridge.OUTBOUND_PRIORITY_NORMAL,
                         bridge._outbound_delivery_priority({"type": "connector_status"}))

    def test_each_control_can_publish_at_capacity_without_removing_old_messages(self):
        client = {"client_route_id": "fixture-route", "signal_name": "fixture",
                  "link_secret": "A" * 43, "local_identity_fingerprint": "a" * 64,
                  "identity_fingerprint": "b" * 64}
        for kind in RECOVERY_CONTROLS:
            with self.subTest(kind=kind):
                records = [{"client_route_id": "fixture-route", "message_id": f"control-{i}",
                            "wire_payload": "fixture-ciphertext",
                            "priority": bridge._outbound_delivery_priority({"type": kind})}
                           for i in range(3)]
                with (
                    patch.object(bridge, "pending_outbound_acks", {1: ("fixture-route", "old")}),
                    patch.object(bridge, "list_clients", return_value=[client]),
                    patch.object(bridge, "outbound_inflight_count", side_effect=lambda **kwargs:
                        bridge.MAX_DURABLE_OUTBOUND_INFLIGHT_PER_CLIENT if kwargs.get("client_route_id")
                        else bridge.MAX_DURABLE_OUTBOUND_INFLIGHT),
                    patch.object(bridge, "fail_exhausted_outbound", return_value=[]),
                    patch.object(bridge, "pending_outbound", return_value=records),
                    patch.object(bridge, "get_client", return_value=client),
                    patch.object(bridge, "mark_outbound_sending") as mark,
                    patch.object(bridge, "track_outbound_publish") as track,
                    patch.object(bridge, "acknowledge_outbound") as acknowledge,
                    patch.object(bridge, "_publish_mqtt_wire_payload",
                                 return_value=SimpleNamespace(rc=0, mid=2)) as publish,
                ):
                    bridge.flush_outbound_messages(SimpleNamespace(is_connected=lambda: True))
                    mark.assert_called_once_with("fixture-route", "control-0")
                    publish.assert_called_once()
                    track.assert_called_once()
                    acknowledge.assert_not_called()
                    self.assertEqual({1: ("fixture-route", "old")}, bridge.pending_outbound_acks)


if __name__ == "__main__":
    unittest.main()
