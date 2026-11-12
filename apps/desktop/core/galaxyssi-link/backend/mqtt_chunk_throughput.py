"""Bounded, process-local delivery observations; never a retry or message ledger."""
from dataclasses import dataclass
import math

from mqtt_broker_catalog import CATALOG


@dataclass(frozen=True)
class ChunkAttempt:
    transfer: str
    request: str
    index: int
    sample_eligible: bool


@dataclass
class Flight:
    broker: str
    generation: int
    size: int
    started: float
    eligible: bool


class ChunkThroughput:
    """Caller serializes access under the policy lock. Time is monotonic seconds."""
    def __init__(self):
        self.flights = {}
        self.rates = {}
        self.windows = {}

    def expire(self, now):
        horizon = CATALOG["timing"]["attempt_observation_seconds"]
        expired = {(key[0], value.broker) for key, value in self.flights.items() if now - value.started > horizon}
        for key in expired:
            self.windows[key] = now, max(131072, self.windows.get(key, (now, 262144))[1] // 2)
        self.flights = {key: value for key, value in self.flights.items() if 0 <= now - value.started <= horizon}
        ttl = CATALOG["timing"]["metric_ttl_seconds"]
        self.rates = {key: value for key, value in self.rates.items() if 0 <= now - value[0] <= ttl}
        self.windows = {key: value for key, value in self.windows.items() if 0 <= now - value[0] <= ttl}

    def track(self, peer, chunk, broker, generation, size, now):
        self.expire(now)
        # A new retry round supersedes observations, not durable bytes or bits.
        self.flights = {key: value for key, value in self.flights.items()
                        if key[:2] != (peer, chunk.transfer) or key[2] == chunk.request}
        key = peer, chunk.transfer, chunk.request, chunk.index
        previous = self.flights.get(key)
        if previous is not None:
            previous.eligible = False  # More than one possible receiving attempt.
        elif len(self.flights) < CATALOG["limits"]["max_tracked_attempts"]:
            self.flights[key] = Flight(broker, generation, size, now, chunk.sample_eligible)

    def discard(self, peer, chunk):
        self.flights.pop((peer, chunk.transfer, chunk.request, chunk.index), None)

    def confirmed(self, peer, transfer, request, indices, generations, now):
        self.expire(now)
        groups = {}
        for index in indices:
            flight = self.flights.pop((peer, transfer, request, index), None)
            if flight and flight.eligible and generations.get(flight.broker) == flight.generation:
                groups.setdefault(flight.broker, []).append(flight)
        for broker, flights in groups.items():
            elapsed = now - min(value.started for value in flights)
            if not math.isfinite(elapsed) or elapsed <= 0:
                continue
            sample = sum(value.size for value in flights) / max(0.020, elapsed)
            old = self.rates.get((peer, broker))
            smoothed = sample if old is None else old[1] * 0.75 + sample * 0.25
            self.rates[peer, broker] = now, smoothed, min(32, (old[2] if old else 0) + 1)
            self.windows[peer, broker] = now, min(524288,
                self.windows.get((peer, broker), (now, 262144))[1] + sum(value.size for value in flights))

    def pending_bytes(self, broker):
        return sum(value.size for value in self.flights.values() if value.broker == broker)

    def can_send(self, peer, broker, size):
        pending = self.pending_bytes(broker)
        window = self.windows.get((peer, broker), (0, 262144))[1]
        return pending == 0 or pending + size <= window

    def rate(self, peer, broker):
        value = self.rates.get((peer, broker))
        if value and value[2] >= CATALOG["timing"]["chunk_throughput_min_samples"]:
            return value[1]
        return CATALOG["limits"]["unmeasured_chunk_bytes_per_second"]

    def forget(self, peer):
        self.flights = {key: value for key, value in self.flights.items() if key[0] != peer}
        self.rates = {key: value for key, value in self.rates.items() if key[0] != peer}
        self.windows = {key: value for key, value in self.windows.items() if key[0] != peer}

    def reset(self):
        self.flights.clear()
        self.rates.clear()
        self.windows.clear()
