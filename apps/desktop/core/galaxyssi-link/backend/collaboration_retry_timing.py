"""Bounded, peer-local retry timing from authenticated exchange completion times."""
from collections import OrderedDict
from dataclasses import dataclass
import math
import threading


@dataclass
class _Estimate:
    mean: float | None
    deviation: float
    delay: float
    observed_at: float


class ResponseRetryTiming:
    def __init__(self, initial=2.0, maximum=8.0, *, capacity=128, ttl=600.0):
        self.initial, self.maximum = initial, maximum
        self.capacity, self.ttl = capacity, ttl
        self._peers = OrderedDict()
        self._lock = threading.Lock()

    def _current(self, peer, now):
        value = self._peers.get(peer)
        if value is not None and not 0 <= now - value.observed_at < self.ttl:
            self._peers.pop(peer, None)
            return None
        return value

    def delay(self, peer, now):
        with self._lock:
            value = self._current(peer, now)
            return value.delay if value is not None else self.initial

    def completed(self, peer, elapsed, now):
        if not math.isfinite(elapsed) or elapsed <= 0:
            return
        with self._lock:
            previous = self._current(peer, now)
            if previous is None or previous.mean is None:
                mean, deviation = elapsed, elapsed / 2
            else:
                deviation = .75 * previous.deviation + .25 * abs(previous.mean - elapsed)
                mean = .875 * previous.mean + .125 * elapsed
            # This includes phone work, local queueing and possible retransmission;
            # it is a conservative completion estimate, not a network RTT sample.
            delay = min(self.maximum, max(self.initial, mean + max(.25, 4 * deviation)))
            self._save(peer, _Estimate(mean, deviation, delay, now))

    def timed_out(self, peer, now):
        with self._lock:
            previous = self._current(peer, now)
            delay = min(self.maximum, 2 * (previous.delay if previous else self.initial))
            self._save(peer, _Estimate(previous.mean if previous else None,
                previous.deviation if previous else 0, delay, now))

    def _save(self, peer, value):
        self._peers.pop(peer, None)
        self._peers[peer] = value
        while len(self._peers) > self.capacity:
            self._peers.popitem(last=False)
