"""Bounded receipt publication; durable sender replay owns retry and recovery."""
import json

from mqtt_broker_catalog import CATALOG
from mqtt_inbound_pool import InboundRoutePool


class StoredReceiptPublisher:
    def __init__(self, *, max_pending=None, route_pending=None):
        self.pool = InboundRoutePool(
            self._publish, max_workers=2,
            max_pending=CATALOG["limits"]["max_pending_receipts"] if max_pending is None else max_pending,
            route_pending=CATALOG["limits"]["per_peer_pending_receipts"] if route_pending is None else route_pending,
            max_bytes=8 * 1024 * 1024, route_bytes=512 * 1024,
        )

    def submit(self, bridge, mqttc, paired, receipt, *, duplicate=False):
        route = paired["client_route_id"]
        binding = bridge._receipt_binding_for_client(paired)
        encoded = json.dumps(receipt, ensure_ascii=False, allow_nan=False, separators=(",", ":"))
        key = (receipt["transport_message_id"], receipt["content_hash"], binding)
        # Retain only the receipt, never the inbound ciphertext or application body.
        return self.pool.submit(route, (bridge, mqttc, route, binding, encoded, duplicate),
                                len(encoded.encode("utf-8")) + 512, key=key)

    @staticmethod
    def _publish(item):
        bridge, mqttc, route, binding, encoded, duplicate = item
        receipt = json.loads(encoded)
        key = (route, receipt["transport_message_id"], receipt["content_hash"], binding)
        return bridge.signal_receipt_replay_gate.publish(key, lambda: bridge._publish_phone_payload(
            mqttc, {"_client_route_id": route}, receipt, expected_receipt_binding=binding),
            duplicate=duplicate)

    def snapshot(self):
        return self.pool.snapshot()

    def wait_idle(self, timeout=5.0):
        return self.pool.wait_idle(timeout)

    def close(self, **kwargs):
        return self.pool.close(**kwargs)
