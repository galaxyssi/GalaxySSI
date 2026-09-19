"""Bounded negative cache for authenticated, repeatedly invalid Signal ciphertext.

Not an inbox: deferred packets are never acknowledged as delivered. Entries
expire so a repaired or advanced Signal session can try the ciphertext again.
"""
from collections import OrderedDict
import threading
import time


class DecryptBackoff:
    def __init__(self, *, capacity=1024, clock=time.monotonic):
        if not 1 <= capacity <= 10000:
            raise ValueError("Invalid decrypt backoff capacity")
        self.capacity = capacity
        self.clock = clock
        self._lock = threading.Lock()
        self._entries = OrderedDict()
        self._failures = self._deferred = 0
        self._last_reason = ""

    def defer(self, key):
        with self._lock:
            entry = self._entries.get(key)
            if entry is not None and self.clock() < entry[1]:
                self._deferred += 1
                return True
            return False

    def failed(self, key, error):
        code = getattr(error, "diagnostic_code", "")
        if code not in {"InvalidMessageException", "DuplicateMessageException", "NoSessionException"}:
            return
        with self._lock:
            previous = self._entries.pop(key, None)
            now = self.clock()
            attempts = min(previous[0] + 1, 5) if previous and now - previous[1] < 300 else 1
            self._entries[key] = (attempts, now + min(2 ** attempts, 30))
            while len(self._entries) > self.capacity:
                self._entries.popitem(last=False)
            self._failures += 1
            self._last_reason = code + ":" + getattr(error, "diagnostic_reason", "unspecified")

    def succeeded(self, key):
        with self._lock:
            self._entries.pop(key, None)

    def snapshot(self):
        with self._lock:
            return {"tracked": len(self._entries), "failures": self._failures,
                    "deferred": self._deferred, "last_reason": self._last_reason}
