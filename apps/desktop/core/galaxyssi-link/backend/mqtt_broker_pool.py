"""Independent TLS broker workers with generation-scoped MQTT acknowledgements.

This layer does not decrypt, deduplicate, or claim business delivery. Its consumer
must enqueue ingress into Link's bounded, per-relationship serial processor.
"""
from __future__ import annotations

import itertools
import logging
import random
import secrets
import threading
import time
from dataclasses import dataclass, field
from typing import Callable

import paho.mqtt.client as mqtt

from mqtt_broker_catalog import BROKERS, CATALOG
from mqtt_multipath_policy import PhysicalKey

log = logging.getLogger(__name__)


def publish_packet_bytes(topic: str, payload_bytes: int) -> int:
    remaining = 2 + len(topic.encode("utf-8")) + 2 + payload_bytes
    encoded_length_bytes = 1
    value = remaining
    while value >= 128:
        encoded_length_bytes += 1
        value //= 128
    return 1 + encoded_length_bytes + remaining


@dataclass(frozen=True)
class Ingress:
    broker_id: str
    generation: int
    received_at: float


@dataclass(frozen=True)
class PublishReceipt:
    logical_id: int
    physical: PhysicalKey
    attempt_id: str
    broker_acked: bool


@dataclass
class _Path:
    broker_id: str
    generation: int = 0
    client: object | None = None
    connected: bool = False
    active_topics: set[str] = field(default_factory=set)
    pending_topics: set[str] = field(default_factory=set)
    subscriptions: dict[int, tuple[str, ...]] = field(default_factory=dict)
    subscription_started: dict[int, float] = field(default_factory=dict)
    early_subacks: dict[int, tuple[bool, ...]] = field(default_factory=dict)
    publications: dict[int, tuple[int, str]] = field(default_factory=dict)
    early_pubacks: dict[int, bool] = field(default_factory=dict)
    last_error: str = ""
    failure_notified: bool = False
    subscribing: bool = False
    publishing: bool = False
    lock: threading.RLock = field(default_factory=threading.RLock)


class BrokerPool:
    def __init__(self, *, on_state: Callable, on_subscribed: Callable,
                 on_packet: Callable, on_publish: Callable, client_factory=None):
        self._on_state = on_state
        self._on_subscribed = on_subscribed
        self._on_packet = on_packet
        self._on_publish = on_publish
        self._factory = client_factory or self._new_client
        self._paths = {key: _Path(key) for key in BROKERS}
        self._desired: dict[str, int] = {}
        self._stop = threading.Event()
        self._lock = threading.RLock()
        self._workers: list[threading.Thread] = []
        self._sequence = itertools.count(1)
        self._started = False
        self._closed = False

    @staticmethod
    def _new_client(broker: str, generation: int):
        client = mqtt.Client(callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
                             client_id=secrets.token_urlsafe(16), clean_session=True,
                             reconnect_on_failure=False, protocol=mqtt.MQTTv311)
        client.tls_set()
        client.tls_insecure_set(False)
        client.connect_timeout = 10.0
        client.max_inflight_messages_set(CATALOG["limits"]["global_inflight_packets"])
        client.max_queued_messages_set(CATALOG["limits"]["global_inflight_packets"])
        return client

    def _emit(self, callback: Callable, *args) -> None:
        try:
            callback(*args)
        except Exception as error:
            log.error("Multipath callback failed kind=%s error=%s", callback.__name__, type(error).__name__)

    def start(self) -> None:
        with self._lock:
            if self._closed:
                raise RuntimeError("broker pool is closed")
            if self._started:
                return
            self._started = True
            # Endpoint enumeration is not a connection or scheduling priority.
            paths = list(self._paths.values())
            random.shuffle(paths)
            self._workers = [threading.Thread(target=self._run, args=(path,), daemon=True,
                                               name=f"galaxyssi-mqtt-{path.broker_id}") for path in paths]
            for worker in self._workers:
                worker.start()

    def _current(self, path: _Path, client, generation: int) -> bool:
        return not self._stop.is_set() and path.client is client and path.generation == generation

    def _run(self, path: _Path) -> None:
        failures = 0
        while not self._stop.is_set():
            with path.lock:
                path.generation += 1
                generation = path.generation
                path.last_error = ""
                path.failure_notified = False
            client = None
            connected_at = 0.0
            try:
                client = self._factory(path.broker_id, generation)
                with path.lock:
                    path.client = client
                self._bind(path, client, generation)
                if self._stop.is_set():
                    break
                endpoint = BROKERS[path.broker_id]
                self._emit(self._on_state, Ingress(path.broker_id, generation, time.monotonic()), "connecting", "")
                client.connect(endpoint["host"], endpoint["tls_port"],
                               keepalive=CATALOG["timing"]["keepalive_seconds"])
                connected_at = time.monotonic()
                if not self._stop.is_set():
                    client.loop_forever(retry_first_connection=False)
            except Exception as error:
                with path.lock:
                    if not path.last_error.startswith("connack_"):
                        path.last_error = type(error).__name__
            finally:
                self._lost(path, client, generation, path.last_error or "connection_closed")
                if client is not None:
                    try:
                        client.disconnect()
                    except Exception:
                        pass
                with path.lock:
                    if path.client is client:
                        path.client = None
            if connected_at and time.monotonic() - connected_at > 60:
                failures = 0
            ceiling = min(30.0, 2.0 ** min(failures, 5))
            failures += 1
            self._stop.wait(random.uniform(ceiling / 2, ceiling))

    def _bind(self, path: _Path, client, generation: int) -> None:
        def connected(_client, _userdata, _flags, reason_code, _properties=None):
            if self._reason(reason_code) != 0:
                self._lost(path, client, generation, f"connack_{self._reason(reason_code)}")
                return
            with path.lock:
                if not self._current(path, client, generation):
                    return
                path.connected = True
                path.last_error = ""
                path.failure_notified = False
            self._emit(self._on_state, Ingress(path.broker_id, generation, time.monotonic()), "connected", "")
            self._subscribe_path(path)

        def disconnected(_client, _userdata, _flags, reason_code, _properties=None):
            self._lost(path, client, generation, f"disconnect_{self._reason(reason_code)}")

        def subscribed(_client, _userdata, mid, codes, _properties=None):
            accepted = tuple(self._reason(code) < 128 for code in codes)
            with path.lock:
                if not self._current(path, client, generation):
                    return
                topics = path.subscriptions.pop(int(mid), None)
                path.subscription_started.pop(int(mid), None)
                if topics is None:
                    if path.subscribing and len(path.early_subacks) < 128:
                        path.early_subacks[int(mid)] = accepted
                    return
            self._apply_suback(path, client, generation, topics, accepted)

        def published(_client, _userdata, mid, reason_code=None, _properties=None):
            accepted = self._reason(reason_code) < 128
            with path.lock:
                if not self._current(path, client, generation):
                    return
                pending = path.publications.pop(int(mid), None)
                if pending is None:
                    if path.publishing and len(path.early_pubacks) < 128:
                        path.early_pubacks[int(mid)] = accepted
                    return
            self._emit(self._on_publish, PublishReceipt(pending[0], PhysicalKey(path.broker_id, generation, int(mid)),
                                                       pending[1], accepted))

        def received(_client, _userdata, message):
            payload = bytes(message.payload)
            with path.lock:
                if (not self._current(path, client, generation) or not path.connected
                        or message.topic not in path.active_topics):
                    return
            if not payload or publish_packet_bytes(message.topic, len(payload)) > CATALOG["limits"]["encoded_packet_bytes"]:
                return
            self._emit(self._on_packet, Ingress(path.broker_id, generation, time.monotonic()), message.topic, payload)

        client.on_connect = connected
        client.on_disconnect = disconnected
        client.on_subscribe = subscribed
        client.on_publish = published
        client.on_message = received

    @staticmethod
    def _reason(code) -> int:
        try:
            return int(getattr(code, "value", code) or 0)
        except (TypeError, ValueError):
            return 128

    def _lost(self, path: _Path, client, generation: int, reason: str) -> None:
        with path.lock:
            if path.client is not client or path.generation != generation:
                return
            was_connected = path.connected
            path.connected = False
            if not path.last_error.startswith("connack_") or reason.startswith("connack_"):
                path.last_error = reason
            notify = not path.failure_notified
            path.failure_notified = True
            path.active_topics.clear()
            path.pending_topics.clear()
            path.subscriptions.clear()
            path.subscription_started.clear()
            path.early_subacks.clear()
            path.early_pubacks.clear()
            pending = list(path.publications.items())
            path.publications.clear()
        for mid, (logical_id, attempt_id) in pending:
            self._emit(self._on_publish, PublishReceipt(logical_id, PhysicalKey(path.broker_id, generation, mid),
                                                       attempt_id, False))
        if was_connected or notify:
            self._emit(self._on_state, Ingress(path.broker_id, generation, time.monotonic()), "disconnected", reason)

    def subscribe(self, topics: dict[str, int]) -> None:
        if any(not topic or len(topic) > 512 or any(char in topic for char in ("#", "+", "\0"))
               or qos not in (0, 1) for topic, qos in topics.items()):
            raise ValueError("exact bounded MQTT topics and QoS 0/1 are required")
        with self._lock:
            if len(set(self._desired) | set(topics)) > 65_536:
                raise ValueError("subscription limit exceeded")
            self._desired.update(topics)
        self.refresh_subscriptions()

    def refresh_subscriptions(self) -> None:
        for path in self._paths.values():
            self._subscribe_path(path)

    def _subscribe_path(self, path: _Path) -> None:
        with self._lock:
            desired = dict(self._desired)
        with path.lock:
            if not path.connected or self._stop.is_set():
                return
            expired = [mid for mid, started in path.subscription_started.items()
                       if time.monotonic() - started > 10.0]
            for mid in expired:
                path.pending_topics.difference_update(path.subscriptions.pop(mid, ()))
                path.subscription_started.pop(mid, None)
            missing = sorted(set(desired) - path.active_topics - path.pending_topics)
            client, generation = path.client, path.generation
        for offset in range(0, len(missing), 128):
            topics = tuple(missing[offset:offset + 128])
            early = None
            with path.lock:
                if not self._current(path, client, generation) or not path.connected:
                    return
                topics = tuple(topic for topic in topics if topic not in path.pending_topics)
                if not topics:
                    continue
                path.pending_topics.update(topics)
                path.subscribing = True
                try:
                    rc, mid = client.subscribe([(topic, desired[topic]) for topic in topics])
                    if rc != mqtt.MQTT_ERR_SUCCESS:
                        path.pending_topics.difference_update(topics)
                        return
                    path.subscriptions[int(mid)] = topics
                    path.subscription_started[int(mid)] = time.monotonic()
                    early = path.early_subacks.pop(int(mid), None)
                    if early is not None:
                        path.subscriptions.pop(int(mid), None)
                        path.subscription_started.pop(int(mid), None)
                except Exception:
                    path.pending_topics.difference_update(topics)
                    return
                finally:
                    path.subscribing = False
            if early is not None:
                self._apply_suback(path, client, generation, topics, early)

    def _apply_suback(self, path, client, generation, topics, accepted) -> None:
        with self._lock:
            desired = set(self._desired)
        with path.lock:
            if not self._current(path, client, generation) or not path.connected:
                return
            path.pending_topics.difference_update(topics)
            active = {topic for index, topic in enumerate(topics)
                      if index < len(accepted) and accepted[index] and topic in desired}
            path.active_topics.update(active)
        self._emit(self._on_subscribed, Ingress(path.broker_id, generation, time.monotonic()),
                   frozenset(active), len(active) == len(topics))

    def unsubscribe(self, topics: set[str]) -> None:
        with self._lock:
            for topic in topics:
                self._desired.pop(topic, None)
        for path in self._paths.values():
            with path.lock:
                path.active_topics.difference_update(topics)
                path.pending_topics.difference_update(topics)
                if path.connected:
                    try:
                        path.client.unsubscribe(sorted(topics))
                    except Exception:
                        pass

    def publish(self, broker: str, generation: int, topic: str, payload: bytes, *, attempt_id: str) -> int | None:
        if (not attempt_id or not topic or any(char in topic for char in ("#", "+", "\0"))
                or len(topic.encode("utf-8")) > 65535 or not payload
                or publish_packet_bytes(topic, len(payload)) > CATALOG["limits"]["encoded_packet_bytes"]):
            return None
        path = self._paths[broker]
        early = None
        with self._lock:
            logical_id = next(self._sequence)
        with path.lock:
            client = path.client
            if (not self._current(path, client, generation) or not path.connected
                    or len(path.publications) >= CATALOG["limits"]["global_inflight_packets"]):
                return None
            path.publishing = True
            try:
                info = client.publish(topic, payload, qos=1, retain=False)
                if info.rc != mqtt.MQTT_ERR_SUCCESS:
                    return None
                path.publications[int(info.mid)] = (logical_id, attempt_id)
                early = path.early_pubacks.pop(int(info.mid), None)
                if early is not None:
                    path.publications.pop(int(info.mid), None)
            except Exception:
                return None
            finally:
                path.publishing = False
        if early is not None:
            self._emit(self._on_publish, PublishReceipt(logical_id, PhysicalKey(broker, generation, int(info.mid)),
                                                       attempt_id, early))
        return logical_id

    def snapshot(self) -> dict:
        result = {}
        for broker, path in self._paths.items():
            with path.lock:
                result[broker] = {"generation": path.generation, "connected": path.connected,
                                  "active_subscriptions": len(path.active_topics),
                                  "pending_subscriptions": len(path.pending_topics),
                                  "pending_publishes": len(path.publications), "last_error": path.last_error}
        return {"selection": "automatic", "paths": result}

    def close(self, timeout: float = 4.0) -> None:
        self._stop.set()
        with self._lock:
            self._closed = True
        for path in self._paths.values():
            with path.lock:
                client, generation = path.client, path.generation
            self._lost(path, client, generation, "closed")
            if client is not None:
                try:
                    client.disconnect()
                except Exception:
                    pass
        deadline = time.monotonic() + timeout
        for worker in self._workers:
            if worker is not threading.current_thread():
                worker.join(max(0.0, deadline - time.monotonic()))
