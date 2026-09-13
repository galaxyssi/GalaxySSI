"""Authenticated per-pair resume exchange for the application broker pool."""
from __future__ import annotations

from collections import deque
from dataclasses import dataclass, field
import hashlib
import json
import logging
import threading
import time

from link_protocol import seal_wire_packet, valid_link_secret
from mqtt_broker_catalog import CATALOG
from mqtt_multipath_policy import PeerRoute, Traffic
from mqtt_broker_pool import publish_packet_bytes
from mqtt_delivery_dispatch import Delivery
from mqtt_delivery_envelope import (Attempt, Frame, Message, MAX_SAFE_INTEGER, content_hash,
                                    parse_verified_receipt, RECEIPT_TYPE)
from mqtt_pool_client import Publication
from mqtt_route_state import (FINGERPRINT, RESUME_ID, TTL_MS, RouteAdvertisement, ResumeResult, issue_local_resume,
                              forget_route, parse_verified_resume, record_verified_resume)

log = logging.getLogger(__name__)


@dataclass(frozen=True)
class PeerBinding:
    scope: str
    sender: str
    receiver: str
    secret: str
    send_topic: str
    receive_topics: frozenset[str]

    @property
    def identity(self):
        return self.scope, self.sender, self.receiver, self.secret


@dataclass
class _Peer:
    binding: PeerBinding
    local: RouteAdvertisement | None = None
    local_generations: dict = field(default_factory=dict)
    remote_epoch: int = 0
    local_confirmed_epoch: int = 0
    next_send: float = 0.0
    failure_until: float = 0.0
    active: bool = True
    last_response: dict = field(default_factory=dict)
    lock: threading.RLock = field(default_factory=threading.RLock)


class PeerRoutes:
    def __init__(self, client, *, on_ready=None, clock=time.monotonic, wall_clock=time.time):
        from mqtt_chunk_feedback import ChunkFeedback
        self._chunk_feedback = ChunkFeedback()
        self.client = client
        self._on_ready = on_ready or (lambda *_: None)
        self._clock, self._wall = clock, wall_clock
        self._peers = {}
        self._outbound = {}
        self._rotation = deque()
        self._urgent = {}
        self._lock = threading.RLock()

    def replace(self, bindings):
        bindings = list(bindings)
        if len(bindings) > CATALOG["limits"]["max_peer_routes"]:
            raise ValueError("Too many authenticated peer routes")
        if len({binding.scope for binding in bindings}) != len(bindings):
            raise ValueError("Duplicate authenticated peer scope")
        if len({binding.send_topic for binding in bindings}) != len(bindings):
            raise ValueError("Ambiguous outgoing mailbox")
        for binding in bindings:
            if (not binding.scope or len(binding.scope) > 512 or not valid_link_secret(binding.secret)
                    or not FINGERPRINT.fullmatch(binding.sender) or not FINGERPRINT.fullmatch(binding.receiver)
                    or binding.sender == binding.receiver or not binding.receive_topics
                    or len(binding.receive_topics) > 16
                    or any(not topic or len(topic) > 512 or any(c in topic for c in ("#", "+", "\0"))
                           for topic in (*binding.receive_topics, binding.send_topic))):
                raise ValueError("Invalid authenticated peer binding")
        with self._lock:
            retained = {}
            outbound = {}
            for binding in bindings:
                previous = self._peers.get(binding.scope)
                if previous and previous.binding.identity != binding.identity:
                    with previous.lock:
                        forget_route(binding.scope)
                        previous.active = False
                        self.client.policy.forget_peer(binding.scope)
                        self._chunk_feedback.forget(binding.scope)
                    previous = None
                if previous is None:
                    previous = _Peer(binding)
                else:
                    with previous.lock:
                        if previous.binding.receive_topics != binding.receive_topics:
                            previous.local = None
                            previous.local_confirmed_epoch = 0
                        previous.binding = binding
                retained[binding.scope] = previous
                outbound[binding.send_topic] = previous
            for scope in set(self._peers) - set(retained):
                with self._peers[scope].lock:
                    forget_route(scope)
                    self._peers[scope].active = False
                    self.client.policy.forget_peer(scope)
                    self._chunk_feedback.forget(scope)
            self._peers, self._outbound = retained, outbound
            existing_order = [scope for scope in self._rotation if scope in retained]
            existing = set(existing_order)
            self._rotation = deque(existing_order + [scope for scope in retained if scope not in existing])
            self._urgent = {scope: True for scope in self._urgent if scope in retained}

    def request(self, scope):
        with self._lock:
            if scope in self._peers and len(self._urgent) < 64:
                self._urgent[scope] = True

    def _local_advertisement(self, peer, now_ms):
        binding = peer.binding
        generations = self.client.ready_path_generations(binding.receive_topics)
        ready = frozenset(generations)
        if not ready:
            return None
        previous = peer.local
        if (previous is None or previous.receive_brokers != ready or peer.local_generations != generations
                or previous.expires_at_ms - now_ms < TTL_MS / 2):
            peer.local = issue_local_resume(binding.scope, sender=binding.sender, receiver=binding.receiver,
                                           receive_brokers=ready, now_ms=now_ms)
            peer.local_confirmed_epoch = 0
            peer.local_generations = generations
        return peer.local

    def maintenance(self, limit=16):
        if not 1 <= limit <= 64:
            raise ValueError("Bounded resume admission required")
        for send in self._chunk_feedback.drain(self._clock(), limit):
            try:
                send()
            except Exception as exc:
                log.warning("Chunk feedback deferred (%s)", type(exc).__name__)
        with self._lock:
            scopes = list(self._urgent)[:limit]
            for scope in scopes:
                self._urgent.pop(scope, None)
            for _ in range(min(limit - len(scopes), len(self._rotation))):
                scope = self._rotation.popleft()
                self._rotation.append(scope)
                if scope not in scopes:
                    scopes.append(scope)
            peers = [self._peers[scope] for scope in scopes if scope in self._peers]
        for peer in peers:
            if not peer.lock.acquire(blocking=False):
                continue
            try:
                now, now_ms = self._clock(), int(self._wall() * 1000)
                if not peer.active or now < peer.failure_until:
                    continue
                previous = peer.local
                advertisement = self._local_advertisement(peer, now_ms)
                if advertisement is None:
                    continue
                changed = advertisement is not previous
                confirmed = peer.local_confirmed_epoch == advertisement.epoch
                if not changed and (confirmed or now < peer.next_send):
                    continue
                payload = advertisement.to_wire()
                binding = peer.binding
                peer.next_send = now + 5.0
                targets = advertisement.receive_brokers
            except Exception as exc:
                log.warning("Peer path resume deferred (%s)", type(exc).__name__)
                peer.failure_until = self._clock() + 5.0
                continue
            finally:
                peer.lock.release()
            # Each endpoint is attempted independently; no wait for all brokers.
            for broker in targets:
                try:
                    self._publish_control(binding, payload, broker)
                except Exception as exc:
                    log.warning("Peer path publication deferred (%s)", type(exc).__name__)

    def _publish_control(self, binding, payload, broker):
        if broker not in self.client.policy.ready_brokers(set(binding.receive_topics)):
            return
        encoded = json.dumps(payload, separators=(",", ":"))
        digest = hashlib.sha256(encoded.encode()).hexdigest()
        descriptor = Publication(binding.scope, digest, digest, Traffic.CONTROL,
                                 binding.receive_topics, bootstrap=True, preferred_broker=broker)
        return self.client.publish(binding.send_topic, seal_wire_packet(encoded, binding.secret),
                                   publication=descriptor)

    def handle_verified(self, scope, payload, *, broker_id, generation, authenticated_identity):
        """Called only inside authenticated AEAD ingress for this configured pair."""
        if not isinstance(payload, dict) or payload.get("type") not in {"link_resume", "link_resume_ack"}:
            return False
        with self._lock:
            peer = self._peers.get(scope)
        if peer is None:
            raise ValueError("Resume does not belong to an authorized pair")
        path = self.client.path_snapshot()["paths"].get(broker_id)
        if not path or not path["connected"] or path["generation"] != generation:
            return True
        notify = False
        request_resume = False
        response = None
        with peer.lock:
            binding = peer.binding
            if not peer.active or binding.identity != authenticated_identity:
                raise ValueError("Resume authentication no longer matches the configured pair")
            if broker_id not in self.client.policy.ready_brokers(set(binding.receive_topics)):
                return True
            now, now_ms = self._clock(), int(self._wall() * 1000)
            raw = payload if payload["type"] == "link_resume" else payload.get("advertisement")
            advertisement = parse_verified_resume(raw, sender=binding.receiver, receiver=binding.sender, now_ms=now_ms)
            if payload["type"] == "link_resume_ack":
                local = peer.local
                epoch = payload.get("acknowledged_route_epoch")
                resume_id, digest = payload.get("acknowledged_resume_id"), payload.get("acknowledged_digest")
                if (type(epoch) is not int or not isinstance(resume_id, str) or not RESUME_ID.fullmatch(resume_id)
                        or not isinstance(digest, str) or not FINGERPRINT.fullmatch(digest)):
                    raise ValueError("Malformed resume acknowledgement")
                # A surviving path can deliver an old ACK after another path
                # rotates the local epoch. Discard it before any route mutation.
                if local is not None and 0 < epoch < local.epoch:
                    return True
                if (local is None or local.expires_at_ms <= now_ms
                        or resume_id != local.resume_id or epoch != local.epoch or digest != local.digest()):
                    raise ValueError("Unsolicited or mismatched resume acknowledgement")
            result = record_verified_resume(scope, advertisement, now_ms=now_ms)
            if result in {ResumeResult.STALE, ResumeResult.CONFLICT}:
                return True
            if advertisement.epoch > peer.remote_epoch:
                remaining = min(CATALOG["timing"]["resume_ttl_seconds"],
                                (advertisement.expires_at_ms - now_ms) / 1000)
                route = PeerRoute(advertisement.epoch, advertisement.receive_brokers,
                                  advertisement.packet_bytes, True, now + remaining)
                if not self.client.policy.accept_verified_resume(scope, route, now=now):
                    return True
                peer.remote_epoch = advertisement.epoch
                if peer.local is None or peer.local_confirmed_epoch != peer.local.epoch:
                    peer.next_send = 0
                    request_resume = True
            if payload["type"] == "link_resume_ack":
                notify = peer.local_confirmed_epoch != peer.local.epoch
                peer.local_confirmed_epoch = peer.local.epoch
            else:
                local = self._local_advertisement(peer, now_ms)
                previous = peer.last_response.get(broker_id)
                response_key = (advertisement.epoch, advertisement.resume_id)
                if local and (not previous or previous[0] != response_key or now - previous[1] >= 1.0):
                    peer.last_response[broker_id] = (response_key, now)
                    response = {"type": "link_resume_ack", "advertisement": local.to_wire(),
                                "acknowledged_resume_id": advertisement.resume_id,
                                "acknowledged_route_epoch": advertisement.epoch,
                                "acknowledged_digest": advertisement.digest()}
        if response:
            self._publish_control(binding, response, broker_id)
        if request_resume:
            self.request(scope)
        if notify:
            self._on_ready(scope)
        return True

    def ready(self, scope):
        with self._lock:
            peer = self._peers.get(scope)
        if not peer:
            return False
        with peer.lock:
            local = peer.local
            if (not peer.active or not local or local.expires_at_ms <= self._wall() * 1000
                    or peer.local_confirmed_epoch != local.epoch):
                return False
            binding = peer.binding
            current = self.client.ready_path_generations(binding.receive_topics)
            if not current or any(peer.local_generations.get(broker) != generation
                                  for broker, generation in current.items()):
                return False
        return bool(self.client.policy.plan(scope, "route-readiness", Traffic.MESSAGE, 1,
                                             set(binding.receive_topics), now=self._clock()))

    def classify(self, topic, encoded):
        with self._lock:
            peer = self._outbound.get(topic)
        if peer is None:
            return None
        if not self.ready(peer.binding.scope):
            self.request(peer.binding.scope)
            return None
        digest = hashlib.sha256(encoded).hexdigest()
        with peer.lock:
            if not peer.active:
                return None
            return Publication(peer.binding.scope, digest, digest, Traffic.MESSAGE, peer.binding.receive_topics,
                               authorized_paths=tuple(peer.local_generations.items()))

    def prepare_delivery(self, topic, wire, message_id, traffic):
        with self._lock:
            peer = self._outbound.get(topic)
        if peer is None or not self.ready(peer.binding.scope):
            if peer:
                self.request(peer.binding.scope)
            return None
        with peer.lock:
            binding = peer.binding
            if not peer.active:
                return None
        immutable = json.loads(json.dumps(wire, ensure_ascii=False))
        message = Message(message_id, content_hash(immutable), binding.sender, binding.receiver, traffic.value)

        def encode(frame):
            return seal_wire_packet(json.dumps(frame.attach(immutable), ensure_ascii=False,
                                               separators=(",", ":")), binding.secret)

        def authorized(broker, generation):
            with peer.lock:
                local = peer.local
                return (peer.active and peer.binding == binding and local is not None
                        and local.expires_at_ms > self._wall() * 1000 and peer.local_confirmed_epoch == local.epoch
                        and peer.local_generations.get(broker) == generation
                        and self.client.ready_path_generations(binding.receive_topics).get(broker) == generation)

        # Bound final AEAD/base64/MQTT bytes with the longest catalog ID and
        # maximum representable generation. Signal encryption is never repeated.
        longest = max(CATALOG["brokers"], key=len)
        preview = encode(Frame(message, Attempt("0" * 32, longest, MAX_SAFE_INTEGER)))
        size = publish_packet_bytes(topic, len(preview.encode("utf-8") if isinstance(preview, str) else preview))
        return Delivery(binding.scope, message, binding.receive_topics, encode, authorized, size)

    def accept_delivery_receipt(self, scope, payload, *, broker_id, generation, authenticated_identity, commit):
        if not isinstance(payload, dict) or payload.get("type") != RECEIPT_TYPE:
            return False, False
        with self._lock:
            peer = self._peers.get(scope)
        if peer is None:
            raise ValueError("Receipt does not belong to an authorized pair")
        with peer.lock:
            binding = peer.binding
            if not peer.active or binding.identity != authenticated_identity:
                raise ValueError("Receipt authentication no longer matches the configured pair")
            if self.client.ready_path_generations(binding.receive_topics).get(broker_id) != generation:
                return True, False
            frame = parse_verified_receipt(payload, original_sender=binding.sender, original_receiver=binding.receiver)
            accepted = self.client.delivery.accept_verified_receipt(scope, frame, lambda: commit(frame))
        return True, accepted

    def publish_stored_receipt(self, scope, frame, message_id, wire_hash, *, authenticated_identity):
        with self._lock:
            peer = self._peers.get(scope)
        if peer is None or not self.ready(scope):
            return None
        with peer.lock:
            binding = peer.binding
            if (not peer.active or binding.identity != authenticated_identity
                    or peer.local is None or peer.local.expires_at_ms <= self._wall() * 1000
                    or peer.local_confirmed_epoch != peer.local.epoch
                    or (frame.message.sender, frame.message.receiver) != (binding.receiver, binding.sender)):
                return None
            receipt = frame.receipt_after_store(stored_message_id=message_id, stored_content_hash=wire_hash)
            encoded = seal_wire_packet(json.dumps(receipt, separators=(",", ":")), binding.secret)
            digest = hashlib.sha256(encoded.encode() if isinstance(encoded, str) else encoded).hexdigest()
            descriptor = Publication(scope, digest, digest, Traffic.RECEIPT, binding.receive_topics,
                                     preferred_broker=frame.attempt.broker_id,
                                     authorized_paths=tuple(peer.local_generations.items()))
        return self.client.publish(binding.send_topic, encoded, publication=descriptor)

    def status(self):
        with self._lock:
            scopes = tuple(self._peers)
        return {"configured": len(scopes), "ready": sum(self.ready(scope) for scope in scopes)}

    def chunk_publication(self, topic, payload, *, authenticated_identity, attempted=frozenset(), on_path=None):
        from mqtt_chunk_receipts import PROBE, Query
        from mqtt_chunk_throughput import ChunkAttempt
        from mqtt_durable_chunks import Chunk
        with self._lock:
            peer = self._outbound.get(topic)
        if peer is None or not self.ready(peer.binding.scope):
            return None
        with peer.lock:
            if not peer.active or peer.binding.identity != authenticated_identity:
                return None
            binding = peer.binding
            observation = None
            if payload.get("type") == PROBE:
                query = Query.parse(payload)
                identity, digest, traffic = query.transfer + ":probe", query.manifest, Traffic.RECEIPT
            else:
                chunk = Chunk.parse(payload)
                identity, digest, traffic = f"{chunk.transfer}:{chunk.index}", chunk.digest, Traffic.CHUNK
                query = Query.from_chunk(payload)
                if query is not None:
                    observation = ChunkAttempt(chunk.transfer, query.request, chunk.index, not attempted)
            return Publication(binding.scope, identity, digest, traffic, binding.receive_topics,
                               authorized_paths=tuple(peer.local_generations.items()),
                               attempted_brokers=attempted, on_path=on_path, chunk=observation)

    def committed_chunk_state(self, scope, payload):
        from mqtt_chunk_receipts import parse_state
        query, _, _, bitmap = parse_state(payload)
        indices = [index for index in range(query.count) if bitmap[index // 8] & (1 << (index % 8))]
        self.client.policy.confirm_chunk_state(scope, query.transfer, query.request, indices, self._clock())

    def chunk_ingress(self, scope, *, broker_id, generation, authenticated_identity):
        with self._lock:
            peer = self._peers.get(scope)
        if peer is None:
            return False
        with peer.lock:
            return (peer.active and peer.binding.identity == authenticated_identity
                    and self.client.ready_path_generations(peer.binding.receive_topics).get(broker_id) == generation)

    def publish_chunk_state(self, scope, payload, *, authenticated_identity, broker_id, urgent=False):
        from mqtt_chunk_receipts import parse_state
        query, _, revision, bitmap = parse_state(payload)
        complete = all(bitmap[index // 8] & (1 << (index % 8)) for index in range(query.count))
        frozen = json.dumps(payload, separators=(",", ":"))
        with self._lock:
            peer = self._peers.get(scope)
        if peer is None:
            return
        with peer.lock:
            if not peer.active or peer.binding.identity != authenticated_identity:
                return
            send = self._chunk_feedback.offer(scope, query.transfer, query.request, revision,
                lambda: self._send_chunk_state(scope, frozen, authenticated_identity, broker_id), self._clock(), urgent or complete)
        if send:
            return send()

    def _send_chunk_state(self, scope, frozen, authenticated_identity, broker_id):
        with self._lock:
            peer = self._peers.get(scope)
        if peer is None or not self.ready(scope):
            return None
        with peer.lock:
            binding = peer.binding
            if not peer.active or binding.identity != authenticated_identity:
                return None
            encoded = seal_wire_packet(frozen, binding.secret)
            digest = hashlib.sha256(encoded.encode()).hexdigest()
            descriptor = Publication(scope, digest, digest, Traffic.RECEIPT, binding.receive_topics,
                                     preferred_broker=broker_id,
                                     authorized_paths=tuple(peer.local_generations.items()))
        return self.client.publish(binding.send_topic, encoded, publication=descriptor)
