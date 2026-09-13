"""Bounded local receipt retries; durable sender replay remains the recovery owner."""
from dataclasses import dataclass
import threading

from mqtt_broker_catalog import CATALOG


@dataclass
class Pending:
    due: float
    expires: float
    send: object
    running: bool = False


class ReceiptRetry:
    def __init__(self):
        self.pending = {}
        self.lock = threading.Lock()

    def _expire(self, now):
        for key in [key for key, value in self.pending.items() if value.expires <= now and not value.running]:
            self.pending.pop(key)

    def offer(self, scope, message_id, attempt_id, send, now):
        key = scope, message_id, attempt_id
        with self.lock:
            self._expire(now)
            if key in self.pending:
                return
            if (len(self.pending) >= CATALOG["limits"]["max_pending_receipts"]
                    or sum(item[0] == scope for item in self.pending) >= CATALOG["limits"]["per_peer_pending_receipts"]):
                return
            item = Pending(now, now + CATALOG["timing"]["receipt_retry_ttl_seconds"], send)
            self.pending[key] = item
        self._run(key, item, now)

    def _run(self, key, item, now):
        with self.lock:
            if self.pending.get(key) is not item or item.running or item.due > now or item.expires <= now:
                return
            item.running = True
            item.due = now + CATALOG["timing"]["receipt_retry_ms"] / 1000
            self.pending.pop(key)
            self.pending[key] = item
        sent = False
        try:
            sent = bool(item.send())
        finally:
            with self.lock:
                item.running = False
                if sent and self.pending.get(key) is item:
                    self.pending.pop(key)

    def drain(self, now, limit=16):
        with self.lock:
            self._expire(now)
            items = [(key, item) for key, item in self.pending.items() if not item.running and item.due <= now][:limit]
        return [lambda key=key, item=item: self._run(key, item, now) for key, item in items]

    def forget(self, scope):
        with self.lock:
            self.pending = {key: item for key, item in self.pending.items() if key[0] != scope}
