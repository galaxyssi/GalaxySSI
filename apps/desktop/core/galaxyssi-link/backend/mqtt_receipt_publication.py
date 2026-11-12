"""Track broker completion without blocking receipt maintenance or creating a worker."""
from mqtt_broker_catalog import CATALOG


class ReceiptPublication:
    def __init__(self, publish, clock):
        self.publish, self.clock = publish, clock
        self.attempts = []
        self.last_sent = float("-inf")

    def send(self):
        if any(info.is_published() for info in self.attempts):
            return True
        now = self.clock()
        if (any(not info._done.is_set() for info in self.attempts)
                and now - self.last_sent < 2 * CATALOG["timing"]["receipt_retry_ms"] / 1000):
            return False
        info = self.publish(frozenset(info.broker_id for info in self.attempts))
        if info is None or info.rc != 0:
            if all(info._done.is_set() for info in self.attempts):
                self.attempts.clear()
            return False
        self.attempts.append(info)
        self.last_sent = now
        return info.is_published()
