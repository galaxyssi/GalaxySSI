"""Deterministic in-process broker bus; it never connects to public services."""
from types import SimpleNamespace
import time

from mqtt_broker_catalog import BROKER_IDS
from mqtt_broker_pool import Ingress, PublishReceipt
from mqtt_multipath_policy import PhysicalKey


class ManualPool:
    def __init__(self, *, on_state, on_subscribed, on_packet, on_publish):
        self.state, self.subscribed, self.packet, self.receipt = on_state, on_subscribed, on_packet, on_publish
        self.paths = {b: {"connected": False, "generation": 0, "topics": set()} for b in BROKER_IDS}
        self.desired, self.sent, self.pending = {}, [], {}
        self.counter = 0
        self.auto_ack = True
        self.auto_suback = True
        self.start_count = 0

    def start(self):
        self.start_count += 1

    def connect(self, broker, generation=1):
        self.paths[broker].update(connected=True, generation=generation, topics=set())
        self.state(Ingress(broker, generation, time.monotonic()), "connected", "")
        if self.auto_suback:
            self.confirm(broker, self.desired)

    def confirm(self, broker, topics):
        path = self.paths[broker]
        path["topics"].update(topics)
        self.subscribed(Ingress(broker, path["generation"], time.monotonic()), frozenset(topics), True)

    def lose(self, broker):
        path = self.paths[broker]
        path["connected"] = False
        path["topics"].clear()
        for logical, (attempt, physical) in list(self.pending.items()):
            if physical.broker_id == broker and physical.generation == path["generation"]:
                self.ack(logical, False)
        self.state(Ingress(broker, path["generation"], time.monotonic()), "disconnected", "test_failure")

    def subscribe(self, topics):
        self.desired.update(topics)
        for broker, path in self.paths.items():
            if path["connected"] and self.auto_suback:
                self.confirm(broker, topics)

    def unsubscribe(self, topics):
        for topic in topics:
            self.desired.pop(topic, None)
        for path in self.paths.values():
            path["topics"].difference_update(topics)

    def refresh_subscriptions(self):
        self.subscribe(self.desired)

    def publish(self, broker, generation, topic, payload, *, attempt_id):
        path = self.paths[broker]
        if not path["connected"] or path["generation"] != generation:
            return None
        self.counter += 1
        logical = self.counter
        # Equal native MIDs on different paths must remain independent.
        physical = PhysicalKey(broker, generation, 1)
        self.pending[logical] = (attempt_id, physical)
        self.sent.append((broker, generation, topic, payload, logical))
        if self.auto_ack:
            self.ack(logical)
        return logical

    def ack(self, logical, accepted=True):
        attempt, physical = self.pending.pop(logical)
        self.receipt(PublishReceipt(logical, physical, attempt, accepted))

    def snapshot(self):
        return {"selection": "automatic", "paths": {
            broker: {"generation": p["generation"], "connected": p["connected"],
                     "active_subscriptions": len(p["topics"]), "last_error": ""}
            for broker, p in self.paths.items()}}

    def close(self, timeout=4):
        for broker in self.paths:
            self.lose(broker)
        return True

    def wait_closed(self, timeout=None):
        return True
