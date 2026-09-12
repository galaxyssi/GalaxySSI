"""Bounded latest-state feedback, flushed by the existing pool maintenance tick."""
from dataclasses import dataclass
import threading

from mqtt_broker_catalog import CATALOG


@dataclass
class Pending:
    due: float
    revision: int
    send: object


class ChunkFeedback:
    def __init__(self):
        self.pending = {}
        self.lock = threading.Lock()

    def offer(self, scope, transfer, request, revision, send, now, urgent=False):
        key = scope, transfer, request
        with self.lock:
            previous = self.pending.get(key)
            if previous and revision < previous.revision:
                return None
            if urgent:
                self.pending.pop(key, None)
                return send
            if previous is None and (len(self.pending) >= CATALOG["limits"]["max_chunk_feedback"]
                    or sum(item[0] == scope for item in self.pending) >= CATALOG["limits"]["per_peer_chunk_feedback"]):
                return None
            due = previous.due if previous else now + CATALOG["timing"]["chunk_feedback_window_ms"] / 1000
            self.pending[key] = Pending(due, revision, send)
        return None

    def drain(self, now, limit=16):
        with self.lock:
            keys = [key for key, value in self.pending.items() if value.due <= now][:limit]
            return [self.pending.pop(key).send for key in keys]

    def forget(self, scope):
        with self.lock:
            self.pending = {key: value for key, value in self.pending.items() if key[0] != scope}
