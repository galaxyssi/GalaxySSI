"""Coalesce burst duplicates without replacing the durable Signal receipt."""
from collections import OrderedDict
import threading
import time


class ReceiptReplayGate:
    def __init__(self, *, clock=time.monotonic, interval=2.0, capacity=2048):
        if interval <= 0 or capacity < 1:
            raise ValueError("Receipt replay bounds must be positive")
        self.clock, self.interval, self.capacity = clock, interval, capacity
        self._sent = OrderedDict()
        self._lock = threading.Lock()

    def publish(self, key, send, *, duplicate=False):
        now = self.clock()
        with self._lock:
            while self._sent and next(iter(self._sent.values())) <= now:
                self._sent.popitem(last=False)
            if duplicate and self._sent.get(key, 0) > now:
                return True
        # Only successful local publication can suppress a burst duplicate.
        # A broker/network loss still causes the sender's durable replay later.
        if not send():
            return False
        with self._lock:
            self._sent.pop(key, None)
            self._sent[key] = self.clock() + self.interval
            while len(self._sent) > self.capacity:
                self._sent.popitem(last=False)
        return True
