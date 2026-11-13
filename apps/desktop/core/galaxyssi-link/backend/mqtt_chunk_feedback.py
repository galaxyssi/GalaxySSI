"""Bounded latest-state feedback, flushed by the existing pool maintenance tick."""
from dataclasses import dataclass
import threading

from mqtt_broker_catalog import CATALOG


@dataclass
class Pending:
    due: float
    expires: float
    revision: int
    send: object
    running: bool = False


class ChunkFeedback:
    def __init__(self):
        self.pending = {}
        self.lock = threading.Lock()

    def _expire(self, now):
        for key in [key for key, item in self.pending.items() if item.expires <= now and not item.running]:
            self.pending.pop(key)

    def offer(self, scope, transfer, request, revision, send, now, urgent=False):
        key = scope, transfer, request
        with self.lock:
            self._expire(now)
            previous = self.pending.get(key)
            if previous and revision < previous.revision:
                return None
            if previous is None and (len(self.pending) >= CATALOG["limits"]["max_chunk_feedback"]
                    or sum(item[0] == scope for item in self.pending) >= CATALOG["limits"]["per_peer_chunk_feedback"]):
                return None
            due = now if urgent else previous.due if previous else now + CATALOG["timing"]["chunk_feedback_window_ms"] / 1000
            item = Pending(due, now + CATALOG["timing"]["receipt_retry_ttl_seconds"], revision, send)
            self.pending[key] = item
            if urgent:
                return self._claim(key, item, now)
        return None

    def _claim(self, key, item, now):
        item.running = True
        item.due = now + CATALOG["timing"]["receipt_retry_ms"] / 1000
        self.pending.pop(key)
        self.pending[key] = item

        def run():
            sent = False
            try:
                with self.lock:
                    current = self.pending.get(key) is item
                if current:
                    sent = bool(item.send())
            finally:
                with self.lock:
                    item.running = False
                    if sent and self.pending.get(key) is item:
                        self.pending.pop(key)
        return run

    def drain(self, now, limit=16):
        with self.lock:
            self._expire(now)
            items = [(key, item) for key, item in self.pending.items() if not item.running and item.due <= now][:limit]
            return [self._claim(key, item, now) for key, item in items]

    def forget(self, scope):
        with self.lock:
            self.pending = {key: value for key, value in self.pending.items() if key[0] != scope}
