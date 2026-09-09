import tempfile
import unittest
from contextlib import ExitStack
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import link_delivery as store
import mqtt_bridge as bridge
from tests.test_mqtt_durable_delivery import DurableMqttClient, paired_client


class ArtifactOutboundLaneTest(unittest.TestCase):
    def test_current_images_pass_old_backlog_with_global_and_route_bounds(self):
        with tempfile.TemporaryDirectory() as directory, ExitStack() as stack:
            stack.enter_context(patch.object(store, "DB_PATH", Path(directory) / "delivery.db"))
            stack.enter_context(patch.object(store.time, "time", return_value=100.0))
            clients = [paired_client("app-a"), paired_client("app-b")]
            stack.enter_context(patch.object(bridge, "list_clients", return_value=clients))
            stack.enter_context(patch.object(bridge, "get_client", side_effect=lambda route: next(p for p in clients if p["client_route_id"] == route)))
            stack.enter_context(patch.object(bridge, "pending_outbound_acks", {}))
            stack.enter_context(patch.object(bridge, "track_outbound_publish"))
            publish = stack.enter_context(patch.object(bridge, "_publish_mqtt_wire_payload", return_value=SimpleNamespace(rc=0, mid=1)))
            for peer in clients:
                route = peer["client_route_id"]
                for index in range(100):
                    message = f"old-{index}"
                    store.queue_outbound(route, message, "topic", "old-wire")
                    if index < 2:
                        store.mark_outbound_sending(route, message)
                for index in range(3):
                    store.queue_outbound(route, f"image-{index}", "topic", "image-wire", priority=bridge.OUTBOUND_PRIORITY_ARTIFACT)
            self.assertEqual(4, store.outbound_inflight_count())
            first = bridge.flush_outbound_messages(DurableMqttClient())
            self.assertEqual({("app-a", "image-0"), ("app-b", "image-0")}, set(first))
            self.assertEqual(2, publish.call_count)
            self.assertEqual(6, store.outbound_inflight_count())
            self.assertEqual({}, bridge.flush_outbound_messages(DurableMqttClient()))
            self.assertTrue(store.acknowledge_outbound("app-a", "image-0"))
            self.assertEqual({("app-a", "image-1")}, set(bridge.flush_outbound_messages(DurableMqttClient())))
            self.assertEqual(2, store.outbound_inflight_count(priority=bridge.OUTBOUND_PRIORITY_ARTIFACT))
            self.assertEqual("queued", store.outbound_status("app-a", "old-99"))

    def test_broker_owned_retry_keeps_artifact_slot_after_application_timeout(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(store, "DB_PATH", Path(directory) / "delivery.db"), patch.object(store.time, "time", return_value=100.0):
            store.queue_outbound("app-a", "image", "topic", "wire", priority=bridge.OUTBOUND_PRIORITY_ARTIFACT)
            store.mark_outbound_sending("app-a", "image")
            self.assertEqual(0, store.outbound_inflight_count(now=200, priority=bridge.OUTBOUND_PRIORITY_ARTIFACT))
            self.assertEqual(1, store.outbound_inflight_count(now=200, priority=bridge.OUTBOUND_PRIORITY_ARTIFACT,
                active_messages={("app-a", "image")}))
            self.assertEqual(0, store.outbound_inflight_count(now=200, client_route_id="app-b",
                priority=bridge.OUTBOUND_PRIORITY_ARTIFACT, active_messages={("app-a", "image")}))

    def test_artifact_lane_does_not_promote_unrelated_messages(self):
        self.assertEqual(bridge.OUTBOUND_PRIORITY_ARTIFACT, bridge._outbound_delivery_priority({"type": "artifact_chunk"}))
        self.assertEqual(bridge.OUTBOUND_PRIORITY_DEPENDENCY, bridge._outbound_delivery_priority({"type": "artifact_redelivery_result"}))
        self.assertEqual(bridge.OUTBOUND_PRIORITY_NORMAL, bridge._outbound_delivery_priority({"type": "other"}))
