"""Application-owned three-path MQTT client with scoped physical receipts.

This adapter keeps the bridge's logical publish/subscription callbacks. Only
authenticated route policy may authorize business paths; bootstrap publications
are explicitly classified by the application, never by untrusted packet fields.
"""
from __future__ import annotations

import hashlib
import itertools
import logging
import secrets
import threading
import time
from dataclasses import dataclass, field
from types import SimpleNamespace

import paho.mqtt.client as mqtt

from mqtt_broker_catalog import BROKER_IDS, CATALOG
from mqtt_broker_pool import BrokerPool, Ingress, publish_packet_bytes
from mqtt_multipath_policy import Attempt, MultipathPolicy, Traffic

log = logging.getLogger(__name__)

@dataclass
class PublishInfo:
    mid: int
    rc: int = mqtt.MQTT_ERR_SUCCESS
    _done: threading.Event = field(default_factory=threading.Event)

    def is_published(self):
        return self._done.is_set() and self.rc == mqtt.MQTT_ERR_SUCCESS

    def wait_for_publish(self, timeout=None):
        self._done.wait(timeout)
        if self.rc != mqtt.MQTT_ERR_SUCCESS:
            raise RuntimeError("MQTT publication failed")


@dataclass(frozen=True)
class Publication:
    peer: str
    message_id: str
    content_hash: str
    traffic: Traffic
    receive_topics: frozenset[str]
    bootstrap: bool = False
    preferred_broker: str | None = None
    authorized_paths: tuple[tuple[str, int], ...] | None = None


class MqttPoolClient:
    def __init__(self, *, classify_publication, on_paths_changed=None, pool_factory=BrokerPool):
        self.on_connect = self.on_disconnect = self.on_subscribe = self.on_publish = self.on_message = None
        self._classify = classify_publication
        self._on_paths_changed = on_paths_changed or (lambda *_: None)
        self.policy = MultipathPolicy()
        self._pool = pool_factory(on_state=self._state, on_subscribed=self._subscribed,
                                  on_packet=self._packet, on_publish=self._published)
        self._lock = threading.RLock()
        self._sequence = itertools.count(1)
        self._paths = {broker: {"generation": 0, "connected": False, "topics": set()} for broker in BROKER_IDS}
        self._desired = {}
        self._pending_subscriptions = {}
        self._publications = {}
        self._closed = threading.Event()
        self._started = False
        self._connected = False
        self._seed = secrets.token_bytes(16)
        self.on_tick = None
        self._last_tick_error = float("-inf")

    @staticmethod
    def _call(callback, *args):
        if callback is not None:
            callback(*args)

    def start(self):
        with self._lock:
            if self._closed.is_set():
                raise RuntimeError("MQTT pool client is closed")
            if self._started:
                return
            self._started = True
        self._pool.start()

    def loop_forever(self, retry_first_connection=False):
        del retry_first_connection
        self.start()
        try:
            while not self._closed.wait(0.25):
                self._pool.refresh_subscriptions()
                self._tick()
        finally:
            self.disconnect()
            # Retain the owning bridge worker while DNS/TLS unwinds, so its
            # supervisor cannot overlap a new pool with these workers.
            self.wait_closed()

    def _tick(self):
        try:
            self._call(self.on_tick)
        except Exception as exc:
            now = time.monotonic()
            if now - self._last_tick_error >= 30:
                self._last_tick_error = now
                log.warning("MQTT maintenance deferred (%s)", type(exc).__name__)

    def is_connected(self):
        with self._lock:
            return self._connected and not self._closed.is_set()

    def active_topics(self):
        with self._lock:
            return set().union(*(path["topics"] for path in self._paths.values() if path["connected"])) & set(self._desired)

    def path_snapshot(self):
        return self._pool.snapshot()

    def ready_path_generations(self, topics):
        required = set(topics)
        with self._lock:
            return {broker: path["generation"] for broker, path in self._paths.items()
                    if path["connected"] and required <= path["topics"] and not self._closed.is_set()}

    def _state(self, ingress: Ingress, state, error):
        if self._closed.is_set() and state != "disconnected":
            return
        with self._lock:
            path = self._paths[ingress.broker_id]
            if ingress.generation < path["generation"]:
                return
            if state == "connected":
                if (ingress.generation == path["generation"]
                        or not self.policy.connected(ingress.broker_id, ingress.generation)):
                    return
                path.update(generation=ingress.generation, connected=True, topics=set())
            elif state == "disconnected":
                self.policy.disconnected(ingress.broker_id, path["generation"])
                path.update(generation=ingress.generation, connected=False, topics=set())
            was_connected = self._connected
            self._connected = any(item["connected"] for item in self._paths.values())
            connected = self._connected
        # Only aggregate zero-to-one/one-to-zero transitions enter the old
        # bridge lifecycle. A single failed path never resets shared inbox/run state.
        if connected and not was_connected:
            self._call(self.on_connect, self, None, {"session_present": False}, 0, None)
        elif was_connected and not connected:
            self._call(self.on_disconnect, self, None, {}, 128, None)
        self._on_paths_changed(self, ingress, state, error)

    def subscribe(self, request, qos=1):
        topics = dict(request) if not isinstance(request, str) else {request: qos}
        if any(not topic or any(char in topic for char in ("#", "+", "\0"))
               or len(topic) > 512 or level not in (0, 1) for topic, level in topics.items()):
            raise ValueError("Only exact bounded subscription topics are allowed")
        with self._lock:
            if self._closed.is_set():
                return mqtt.MQTT_ERR_NO_CONN, 0
            if len(self._pending_subscriptions) >= 1024 or len(set(self._desired) | set(topics)) > 65536:
                return mqtt.MQTT_ERR_QUEUE_SIZE, 0
            for pending_mid, pending in self._pending_subscriptions.items():
                if pending == tuple(topics):
                    return mqtt.MQTT_ERR_SUCCESS, pending_mid
            mid = next(self._sequence)
            self._desired.update(topics)
            self._pending_subscriptions[mid] = tuple(topics)
        try:
            self._pool.subscribe(topics)
        except Exception:
            with self._lock:
                self._pending_subscriptions.pop(mid, None)
            raise
        self._complete_subscriptions()
        return mqtt.MQTT_ERR_SUCCESS, mid

    def _subscribed(self, ingress, topics, complete):
        del complete
        self.policy.subscribed(ingress.broker_id, ingress.generation, set(topics))
        with self._lock:
            path = self._paths[ingress.broker_id]
            if not path["connected"] or path["generation"] != ingress.generation:
                return
            path["topics"].update(set(topics) & set(self._desired))
        self._complete_subscriptions()
        self._on_paths_changed(self, ingress, "subscribed", "")

    def _complete_subscriptions(self):
        active = self.active_topics()
        with self._lock:
            completed = [(mid, topics) for mid, topics in self._pending_subscriptions.items()
                         if set(topics) <= active]
            for mid, _ in completed:
                self._pending_subscriptions.pop(mid, None)
        for mid, topics in completed:
            self._call(self.on_subscribe, self, None, mid, [1] * len(topics), None)

    def unsubscribe(self, topics):
        topics = {topics} if isinstance(topics, str) else set(topics)
        with self._lock:
            for topic in topics:
                self._desired.pop(topic, None)
            for path in self._paths.values():
                path["topics"].difference_update(topics)
            for mid, pending in list(self._pending_subscriptions.items()):
                if set(pending) & topics:
                    self._pending_subscriptions.pop(mid, None)
            mid = next(self._sequence)
        self.policy.unsubscribe(topics)
        self._pool.unsubscribe(topics)
        return mqtt.MQTT_ERR_SUCCESS, mid

    def _packet(self, ingress, topic, payload):
        self._call(self.on_message, self, None, SimpleNamespace(
            topic=topic, payload=payload, broker_id=ingress.broker_id,
            broker_generation=ingress.generation, received_at_ns=time.perf_counter_ns(),
            received_at_ms=int(time.time() * 1000)))

    def publish(self, topic, payload, qos=1, retain=False, *, publication=None):
        if retain or qos != 1:
            raise ValueError("Link requires QoS 1 and retain=false")
        encoded = payload.encode("utf-8") if isinstance(payload, str) else bytes(payload)
        size = publish_packet_bytes(topic, len(encoded))
        with self._lock:
            info = PublishInfo(next(self._sequence))
        publication = publication or self._classify(topic, encoded)
        if publication is None or size > CATALOG["limits"]["encoded_packet_bytes"]:
            info.rc = mqtt.MQTT_ERR_NO_CONN
            return info
        now = time.monotonic()
        if publication.bootstrap:
            candidates = list(self.policy.ready_brokers(set(publication.receive_topics)))
            candidates.sort(key=lambda broker: (
                broker != publication.preferred_broker,
                hashlib.sha256(self._seed + encoded[:128] + broker.encode()).digest()))
            # Bootstrap path validation is outside the business route policy.
            with self._lock:
                plans = [(broker, self._paths[broker]["generation"]) for broker in candidates]
        else:
            plans = [(item.broker_id, item.generation) for item in self.policy.plan(
                publication.peer, publication.message_id, publication.traffic, size,
                set(publication.receive_topics), now=now, ingress=publication.preferred_broker)
                if item.delay == 0]
            if publication.authorized_paths is not None:
                plans = [item for item in plans if item in publication.authorized_paths]
        # This token represents one physical packet. Full durable message hedges
        # and chunk scheduling must be integrated above this adapter.
        for broker, generation in plans:
            attempt_id = secrets.token_hex(16)
            attempt = Attempt(publication.peer, publication.message_id, publication.content_hash,
                              broker, generation, size, publication.traffic, now)
            if not self.policy.reserve(attempt_id, attempt):
                continue
            with self._lock:
                self._publications[attempt_id] = (info, publication, broker, generation)
            receipt = self._pool.publish(broker, generation, topic, encoded, attempt_id=attempt_id)
            if receipt is not None:
                return info
            with self._lock:
                self._publications.pop(attempt_id, None)
            self.policy.discard_attempt(attempt_id)
        info.rc = mqtt.MQTT_ERR_NO_CONN if not plans else mqtt.MQTT_ERR_QUEUE_SIZE
        return info

    def _published(self, receipt):
        with self._lock:
            item = self._publications.get(receipt.attempt_id)
            if item is None or item[2:] != (receipt.physical.broker_id, receipt.physical.generation):
                return
            self._publications.pop(receipt.attempt_id, None)
        info, _publication, broker, generation = item
        if receipt.broker_acked:
            self.policy.broker_ack(receipt.attempt_id, broker, generation)
        info.rc = mqtt.MQTT_ERR_SUCCESS if receipt.broker_acked else mqtt.MQTT_ERR_NO_CONN
        # Business receipt tracking is owned by the durable message dispatcher,
        # not by this Paho compatibility token.
        self.policy.discard_attempt(receipt.attempt_id)
        info._done.set()
        self._call(self.on_publish, self, None, info.mid, 0 if receipt.broker_acked else 128, None)

    def repair_subscriptions(self):
        self._pool.refresh_subscriptions()

    def disconnect(self):
        self._closed.set()
        return self._pool.close()

    def wait_closed(self, timeout=None):
        return self._pool.wait_closed(timeout)
