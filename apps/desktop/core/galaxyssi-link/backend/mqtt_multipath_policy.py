"""Broker-independent scheduling; authentication and durable acceptance stay in Link.

All times are monotonic seconds supplied by the caller. A broker receipt only
releases a physical send slot. Only a verified peer receipt ends a message race.
"""
from __future__ import annotations

import hashlib
import math
import secrets
import threading
from collections import deque
from dataclasses import dataclass, field, replace
from enum import Enum

from mqtt_broker_catalog import BROKER_IDS, CATALOG
from mqtt_chunk_throughput import ChunkThroughput

TRANSPORT_VERSION = CATALOG["transport_version"]


class Traffic(Enum):
    CONTROL = "control"
    MESSAGE = "message"
    FINAL = "final"
    PROGRESS = "progress"
    CHUNK = "chunk"
    RECEIPT = "receipt"


@dataclass(frozen=True)
class Limits:
    packet_bytes: int = CATALOG["limits"]["encoded_packet_bytes"]
    small_packet_bytes: int = CATALOG["limits"]["small_packet_bytes"]
    inflight_packets: int = CATALOG["limits"]["global_inflight_packets"]
    control_reserve: int = CATALOG["limits"]["reserved_control_packets"]
    inflight_bytes: int = CATALOG["limits"]["global_inflight_bytes"]
    peer_inflight_bytes: int = CATALOG["limits"]["per_peer_inflight_bytes"]
    max_peer_routes: int = CATALOG["limits"]["max_peer_routes"]
    max_attempts: int = CATALOG["limits"]["max_tracked_attempts"]
    metric_ttl: float = CATALOG["timing"]["metric_ttl_seconds"]
    route_ttl: float = CATALOG["timing"]["resume_ttl_seconds"]
    hedge_min: float = CATALOG["timing"]["hedge_min_ms"] / 1000
    hedge_max: float = CATALOG["timing"]["hedge_max_ms"] / 1000
    unmeasured_hedge: float = CATALOG["timing"]["unmeasured_hedge_ms"] / 1000
    unmeasured_path_rtt: float = CATALOG["timing"]["unmeasured_path_rtt_ms"] / 1000

    def __post_init__(self):
        if not (0 < self.small_packet_bytes <= self.packet_bytes <= self.inflight_bytes):
            raise ValueError("invalid packet limits")
        if not (0 <= self.control_reserve < self.inflight_packets):
            raise ValueError("invalid control reservation")
        if self.peer_inflight_bytes < self.packet_bytes or self.max_attempts < self.inflight_packets:
            raise ValueError("invalid peer/attempt limits")
        if not (0 < self.hedge_min <= self.unmeasured_hedge <= self.hedge_max):
            raise ValueError("invalid hedge timing")
        if not math.isfinite(self.unmeasured_path_rtt) or self.unmeasured_path_rtt <= 0:
            raise ValueError("invalid unmeasured path RTT")
        if min(self.route_ttl, self.metric_ttl, self.max_peer_routes) <= 0:
            raise ValueError("invalid expiry or route limit")


@dataclass(frozen=True)
class PhysicalKey:
    broker_id: str
    generation: int
    packet_id: int


@dataclass
class Path:
    generation: int = 0
    connected: bool = False
    topics: set[str] = field(default_factory=set)
    packet_bytes: int = 1_048_576


@dataclass(frozen=True)
class PeerRoute:
    epoch: int
    receive_brokers: frozenset[str]
    packet_bytes: int
    chunk_acks: bool
    expires_at: float


@dataclass(frozen=True)
class Dispatch:
    broker_id: str
    generation: int
    delay: float


@dataclass
class Attempt:
    peer: str
    message_id: str
    content_hash: str
    path: str
    generation: int
    wire_bytes: int
    traffic: Traffic
    started_at: float
    broker_acked: bool = False
    slot_held: bool = True
    peer_accepted: bool = False


class MultipathPolicy:
    def __init__(self, limits: Limits | None = None, *, tie_seed: bytes | None = None):
        self.limits = limits or Limits()
        self.paths = {key: Path(packet_bytes=self.limits.packet_bytes) for key in BROKER_IDS}
        self._routes: dict[str, PeerRoute] = {}
        self._attempts: dict[str, Attempt] = {}
        self._rtt: dict[tuple[str, str], deque[tuple[float, float]]] = {}
        self._lock = threading.RLock()
        self._tie_seed = tie_seed if tie_seed is not None else secrets.token_bytes(16)
        self._network = ""
        self.chunks = ChunkThroughput()

    def set_network(self, network: str) -> None:
        with self._lock:
            if network != self._network:
                self._network = network
                self._rtt.clear()
                self.chunks.reset()

    def connected(self, broker: str, generation: int, *, packet_bytes: int | None = None) -> bool:
        packet_limit = self.limits.packet_bytes if packet_bytes is None else packet_bytes
        if packet_limit <= 0:
            raise ValueError("invalid path packet limit")
        with self._lock:
            path = self.paths[broker]
            if generation <= path.generation:
                return False
            self._release_path(broker, path.generation)
            path.generation = generation
            path.connected = True
            path.topics.clear()
            path.packet_bytes = min(packet_limit, self.limits.packet_bytes)
            return True

    def disconnected(self, broker: str, generation: int) -> bool:
        with self._lock:
            path = self.paths[broker]
            if generation != path.generation:
                return False
            path.connected = False
            path.topics.clear()
            self._release_path(broker, generation)
            return True

    def _release_path(self, broker: str, generation: int) -> None:
        for key, attempt in list(self._attempts.items()):
            if attempt.path == broker and attempt.generation == generation:
                attempt.slot_held = False
                if attempt.peer_accepted:
                    del self._attempts[key]

    def subscribed(self, broker: str, generation: int, topics: set[str]) -> bool:
        with self._lock:
            path = self.paths[broker]
            if not path.connected or path.generation != generation:
                return False
            path.topics.update(topics)
            return True

    def unsubscribe(self, topics: set[str]) -> None:
        with self._lock:
            for path in self.paths.values():
                path.topics.difference_update(topics)

    def accept_verified_resume(self, peer: str, route: PeerRoute, *, now: float) -> bool:
        """Call only AFTER Link authenticates the sender and commits its route epoch.

        An identical replay cannot extend expiry. Epoch watermarks must also be
        enforced in the durable Link store across process restarts.
        """
        if (not peer or not 0 < route.epoch <= 9_007_199_254_740_991
                or not route.receive_brokers <= BROKER_IDS
                or not 0 < route.packet_bytes <= self.limits.packet_bytes
                or not math.isfinite(route.expires_at)
                or not now < route.expires_at <= now + self.limits.route_ttl):
            return False
        with self._lock:
            previous = self._routes.get(peer)
            if previous is not None and route.epoch <= previous.epoch:
                return route == previous
            if previous is None and len(self._routes) >= self.limits.max_peer_routes:
                return False
            self._routes[peer] = route
            return True

    def forget_peer(self, peer: str) -> None:
        with self._lock:
            self.chunks.forget(peer)
            self._routes.pop(peer, None)
            self._rtt = {key: values for key, values in self._rtt.items() if key[0] != peer}
            for key in [key for key, value in self._attempts.items() if value.peer == peer]:
                del self._attempts[key]

    def ready_brokers(self, receive_topics: set[str]) -> frozenset[str]:
        with self._lock:
            return frozenset(key for key, value in self.paths.items()
                             if value.connected and receive_topics and receive_topics <= value.topics)

    def _samples(self, peer: str, broker: str, now: float) -> list[float]:
        samples = self._rtt.get((peer, broker))
        if samples is None:
            return []
        while samples and now - samples[0][0] > self.limits.metric_ttl:
            samples.popleft()
        return [value for _, value in samples]

    def _rank(self, peer: str, broker: str, message_id: str, now: float, traffic=None, wire_bytes=0) -> tuple[float, bytes]:
        samples = self._samples(peer, broker, now)
        latency = sum(samples) / len(samples) if samples else self.limits.unmeasured_path_rtt
        load = sum(value.wire_bytes for value in self._attempts.values()
                   if value.path == broker and value.slot_held)
        score = latency * (1 + load / self.limits.peer_inflight_bytes)
        if traffic == Traffic.CHUNK:
            score = latency + (wire_bytes + max(load, self.chunks.pending_bytes(broker))) / self.chunks.rate(peer, broker)
        # An unpredictable per-process tie-break avoids a permanently preferred provider.
        tie = hashlib.sha256(self._tie_seed + f"{peer}\0{message_id}\0{broker}".encode()).digest()
        return score, tie

    def plan(self, peer: str, message_id: str, traffic: Traffic, wire_bytes: int,
             receive_topics: set[str], *, now: float, ingress: str | None = None,
             attempted: frozenset[str] = frozenset()) -> tuple[Dispatch, ...]:
        if not message_id or wire_bytes <= 0 or wire_bytes > self.limits.packet_bytes:
            return ()
        with self._lock:
            self.chunks.expire(now)
            route = self._routes.get(peer)
            if route is None or route.expires_at <= now or wire_bytes > route.packet_bytes:
                return ()
            if traffic == Traffic.CHUNK and not route.chunk_acks:
                return ()
            common = self.ready_brokers(receive_topics) & route.receive_brokers
            candidates = [key for key in common if wire_bytes <= self.paths[key].packet_bytes]
            unused = [key for key in candidates if key not in attempted]
            if unused:
                candidates = unused
            candidates.sort(key=lambda key: self._rank(peer, key, message_id, now, traffic, wire_bytes))
            if not candidates:
                return ()
            if traffic == Traffic.RECEIPT and ingress in candidates:
                candidates.remove(ingress)
                candidates.insert(0, ingress)
            small = wire_bytes <= self.limits.small_packet_bytes
            if traffic == Traffic.CONTROL and small:
                return tuple(Dispatch(key, self.paths[key].generation, 0.0) for key in candidates)
            first = candidates[0]
            result = [Dispatch(first, self.paths[first].generation, 0.0)]
            if (small and traffic in {Traffic.MESSAGE, Traffic.FINAL} and len(candidates) > 1):
                samples = self._samples(peer, first, now)
                if len(samples) < CATALOG["timing"]["hedge_min_samples"]:
                    # Shared receiver/storage latency is observable before any
                    # individual path has a full window of verified receipts.
                    samples = [sample for broker in candidates for sample in self._samples(peer, broker, now)]
                samples = sorted(samples)
                delay = (samples[math.ceil(len(samples) * 0.9) - 1] * 1.5
                         if len(samples) >= CATALOG["timing"]["hedge_min_samples"] else self.limits.unmeasured_hedge)
                delay = max(self.limits.hedge_min, min(delay, self.limits.hedge_max))
                result.extend(Dispatch(key, self.paths[key].generation, delay * index)
                              for index, key in enumerate(candidates[1:], 1))
            return tuple(result)

    def reserve(self, attempt_id: str, attempt: Attempt) -> bool:
        """Reserve before publish; congestion never grows the Paho queues unboundedly."""
        if (not attempt_id or not attempt.peer or not attempt.message_id
                or len(attempt.content_hash) != 64
                or any(char not in "0123456789abcdef" for char in attempt.content_hash)
                or not 0 < attempt.wire_bytes <= self.limits.packet_bytes):
            return False
        with self._lock:
            path = self.paths.get(attempt.path)
            priority = attempt.traffic in {Traffic.CONTROL, Traffic.RECEIPT, Traffic.FINAL}
            tracking_limit = self.limits.max_attempts - (0 if priority else self.limits.control_reserve)
            if (path is None or not path.connected or path.generation != attempt.generation
                    or attempt.wire_bytes > path.packet_bytes
                    or attempt_id in self._attempts or len(self._attempts) >= tracking_limit):
                return False
            matching = [value for value in self._attempts.values()
                        if value.peer == attempt.peer and value.message_id == attempt.message_id]
            if any(value.content_hash != attempt.content_hash for value in matching):
                return False
            active = [value for value in self._attempts.values() if value.slot_held]
            packet_limit = self.limits.inflight_packets - (0 if priority else self.limits.control_reserve)
            byte_reserve = self.limits.control_reserve * self.limits.small_packet_bytes
            byte_limit = self.limits.inflight_bytes - (0 if priority else byte_reserve)
            peer_byte_limit = self.limits.peer_inflight_bytes - (0 if priority else byte_reserve)
            if (len(active) >= packet_limit
                    or sum(value.wire_bytes for value in active) + attempt.wire_bytes > byte_limit
                    or sum(value.wire_bytes for value in active if value.peer == attempt.peer)
                    + attempt.wire_bytes > peer_byte_limit):
                return False
            self._attempts[attempt_id] = replace(attempt, broker_acked=False, slot_held=True, peer_accepted=False)
            return True

    def broker_ack(self, attempt_id: str, broker: str, generation: int) -> bool:
        with self._lock:
            attempt = self._attempts.get(attempt_id)
            if attempt is None or (attempt.path, attempt.generation) != (broker, generation):
                return False
            attempt.broker_acked = True
            attempt.slot_held = False
            if attempt.peer_accepted:
                del self._attempts[attempt_id]
            return True

    def accept_verified_receipt(self, peer: str, message_id: str, content_hash: str,
                                accepted_attempt_id: str, *, now: float) -> tuple[str, ...]:
        """The durable RX_STORED/CHUNK_STORED handler owns authentication and storage checks."""
        with self._lock:
            accepted = self._attempts.get(accepted_attempt_id)
            if (accepted is None or accepted.peer_accepted or (accepted.peer, accepted.message_id, accepted.content_hash)
                    != (peer, message_id, content_hash)):
                return ()
            elapsed = now - accepted.started_at
            if math.isfinite(elapsed) and elapsed >= 0:
                self._rtt.setdefault((peer, accepted.path), deque(maxlen=32)).append((now, elapsed))
            completed = tuple(key for key, value in self._attempts.items()
                              if (value.peer, value.message_id, value.content_hash)
                              == (peer, message_id, content_hash))
            for key in completed:
                self._attempts[key].peer_accepted = True
                if not self._attempts[key].slot_held:
                    del self._attempts[key]
            return completed

    def accept_verified_message(self, peer: str, message_id: str, content_hash: str) -> tuple[str, ...]:
        """An authenticated stored-message ACK has no attributable path RTT."""
        with self._lock:
            completed = tuple(key for key, value in self._attempts.items()
                              if (value.peer, value.message_id, value.content_hash) == (peer, message_id, content_hash))
            for key in completed:
                self._attempts[key].peer_accepted = True
                if not self._attempts[key].slot_held:
                    del self._attempts[key]
            return completed

    def discard_attempt(self, attempt_id: str) -> None:
        with self._lock:
            self._attempts.pop(attempt_id, None)

    def track_chunk(self, peer, chunk, broker, generation, size, now):
        with self._lock:
            if peer in self._routes and self.paths[broker].generation == generation:
                self.chunks.track(peer, chunk, broker, generation, size, now)

    def discard_chunk(self, peer, chunk):
        with self._lock:
            self.chunks.discard(peer, chunk)

    def confirm_chunk_state(self, peer, transfer, request, indices, now):
        """Called only after the solicited, pair-authenticated bitmap commit succeeded."""
        with self._lock:
            generations = {key: value.generation for key, value in self.paths.items() if value.connected}
            self.chunks.confirmed(peer, transfer, request, indices, generations, now)

    def pending(self, peer: str, message_id: str) -> bool:
        with self._lock:
            return any(value.peer == peer and value.message_id == message_id and not value.peer_accepted
                       for value in self._attempts.values())

    def expire_attempts(self, before: float) -> tuple[str, ...]:
        """Retire transport observations only; the durable business outbox still owns retries."""
        with self._lock:
            expired = tuple(key for key, value in self._attempts.items() if value.started_at < before)
            for key in expired:
                del self._attempts[key]
            return expired

    def diagnostics(self) -> dict:
        with self._lock:
            return {
                "selection": "automatic",
                "paths": {key: {"connected": path.connected, "generation": path.generation,
                                 "subscription_count": len(path.topics)} for key, path in self.paths.items()},
                "inflight_packets": sum(value.slot_held for value in self._attempts.values()),
                "inflight_bytes": sum(value.wire_bytes for value in self._attempts.values() if value.slot_held),
                "pending_attempts": len(self._attempts),
            }
