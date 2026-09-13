"""Bounded physical races over the existing durable Link outbox.

No worker or durable message queue lives here. The pool owner's maintenance
tick drives delayed copies; only authenticated RX_STORED ends their race.
"""
from __future__ import annotations

from dataclasses import dataclass, field
import secrets
import threading
import time
from typing import Callable

import paho.mqtt.client as mqtt

from mqtt_broker_pool import publish_packet_bytes
from mqtt_broker_catalog import CATALOG
from mqtt_delivery_envelope import Attempt as WireAttempt, Frame, Message
from mqtt_multipath_policy import Attempt, Traffic


@dataclass(frozen=True)
class Delivery:
    peer: str
    message: Message
    receive_topics: frozenset[str]
    encode_attempt: Callable[[Frame], bytes | str]
    authorized: Callable[[str, int], bool]
    size_bound: int


@dataclass
class _Job:
    topic: str
    delivery: Delivery
    info: object
    started: float
    scheduled: list
    attempts: set = field(default_factory=set)
    accepted: bool = False
    publishing: bool = False

    @property
    def key(self):
        return self.delivery.peer, self.delivery.message


@dataclass
class _Sent:
    job: _Job
    frame: Frame
    started: float
    pending: bool = True


class DeliveryDispatch:
    def __init__(self, policy, publish, completed, *, clock=time.monotonic):
        self.policy, self._publish, self._completed, self._clock = policy, publish, completed, clock
        self._jobs, self._sent = {}, {}
        self._lock = threading.RLock()
        self._closed = False

    def submit(self, topic, delivery, info):
        now = self._clock()
        traffic = Traffic(delivery.message.traffic)
        plans = self.policy.plan(delivery.peer, delivery.message.message_id, traffic,
                                 delivery.size_bound, set(delivery.receive_topics), now=now)
        with self._lock:
            key = delivery.peer, delivery.message
            previous = self._jobs.get(key)
            if previous is not None and self._expired(previous, now):
                self._retire(previous)
                previous = self._jobs.get(key)
            if previous is not None:
                return previous.info
            priority = traffic in {Traffic.CONTROL, Traffic.RECEIPT, Traffic.FINAL}
            limit = self.policy.limits
            if self._closed or not plans:
                info.rc = mqtt.MQTT_ERR_NO_CONN
                return info
            if (len(self._jobs) >= limit.max_attempts - (0 if priority else limit.control_reserve)
                    or sum(job.delivery.size_bound for job in self._jobs.values()) + delivery.size_bound
                    > limit.inflight_bytes - (0 if priority else limit.control_reserve * limit.small_packet_bytes)):
                info.rc = mqtt.MQTT_ERR_QUEUE_SIZE
                return info
            job = _Job(topic, delivery, info, now, [(now + plan.delay, plan) for plan in plans])
            self._jobs[key] = job
        try:
            self._pump(job, now)
        except Exception:
            with self._lock:
                if not job.attempts:
                    self._jobs.pop(key, None)
            raise
        with self._lock:
            # Admission requires a physical send, not another unbounded queue.
            if not job.attempts:
                job.scheduled.clear()
                self._jobs.pop(key, None)
                if not info._done.is_set():
                    info.rc = mqtt.MQTT_ERR_QUEUE_SIZE
        return info

    def _finish(self, job, success):
        with self._lock:
            if job.info._done.is_set():
                return
            job.info.rc = mqtt.MQTT_ERR_SUCCESS if success else mqtt.MQTT_ERR_NO_CONN
            job.info._done.set()
        self._completed(job.info, success)

    def _pump(self, job, now):
        with self._lock:
            if self._closed or job.accepted or job.publishing or self._jobs.get(job.key) is not job:
                return
            job.publishing = True
        try:
            while True:
                with self._lock:
                    if self._closed or job.accepted or not job.scheduled or job.scheduled[0][0] > now:
                        break
                    _due, plan = job.scheduled.pop(0)
                delivery, message = job.delivery, job.delivery.message
                # Revalidate expiry, subscriptions, generation AND pair identity
                # at each actual send, not just when the outbox selected a row.
                allowed = self.policy.plan(delivery.peer, message.message_id, Traffic(message.traffic),
                                           delivery.size_bound, set(delivery.receive_topics), now=now)
                if (not any((p.broker_id, p.generation) == (plan.broker_id, plan.generation) for p in allowed)
                        or not delivery.authorized(plan.broker_id, plan.generation)):
                    continue
                frame = Frame(message, WireAttempt(secrets.token_hex(16), plan.broker_id, plan.generation))
                encoded = delivery.encode_attempt(frame)
                encoded = encoded.encode("utf-8") if isinstance(encoded, str) else bytes(encoded)
                size = publish_packet_bytes(job.topic, len(encoded))
                if size > delivery.size_bound:
                    raise ValueError("Delivery exceeds its encoded packet bound")
                with self._lock:
                    if self._closed or job.accepted or self._jobs.get(job.key) is not job:
                        break
                    attempt_id = frame.attempt.attempt_id
                    if not self.policy.reserve(attempt_id, Attempt(delivery.peer, message.message_id,
                            message.content_hash, plan.broker_id, plan.generation, size, Traffic(message.traffic), now)):
                        job.scheduled.insert(0, (now + 0.25, plan))
                        break
                    job.attempts.add(attempt_id)
                    self._sent[attempt_id] = _Sent(job, frame, now)
                try:
                    receipt = self._publish(plan.broker_id, plan.generation, job.topic, encoded, attempt_id=attempt_id)
                except Exception:
                    receipt = None
                if receipt is None:
                    with self._lock:
                        self._sent.pop(attempt_id, None)
                        job.attempts.discard(attempt_id)
                        self.policy.discard_attempt(attempt_id)
                        job.scheduled = [(now, p) for _, p in job.scheduled]
        except Exception:
            with self._lock:
                job.scheduled.clear()
            raise
        finally:
            with self._lock:
                job.publishing = False
                failed = not job.scheduled and not any(
                    sent.pending for key in job.attempts if (sent := self._sent.get(key)))
            if failed and not job.info._done.is_set():
                self._finish(job, False)

    def published(self, receipt):
        with self._lock:
            sent = self._sent.get(receipt.attempt_id)
            if sent is None:
                return False
            attempt = sent.frame.attempt
            if (attempt.broker_id, attempt.generation) != (receipt.physical.broker_id, receipt.physical.generation):
                return True
            if not sent.pending:
                return True
            sent.pending = False
            job = sent.job
            if receipt.broker_acked:
                self.policy.broker_ack(attempt.attempt_id, attempt.broker_id, attempt.generation)
            else:
                self.policy.discard_attempt(attempt.attempt_id)
                self._sent.pop(attempt.attempt_id, None)
                job.attempts.discard(attempt.attempt_id)
                job.scheduled = [(self._clock(), plan) for _, plan in job.scheduled]
            if job.accepted or self._closed:
                self._sent.pop(attempt.attempt_id, None)
                job.attempts.discard(attempt.attempt_id)
                self.policy.discard_attempt(attempt.attempt_id)
                if not job.attempts:
                    self._jobs.pop(job.key, None)
            failed = not job.publishing and not job.scheduled and not any(
                item.pending for key in job.attempts if (item := self._sent.get(key)))
        if receipt.broker_acked:
            self._finish(job, True)
        elif failed:
            self._finish(job, False)
        return True

    def accept_verified_receipt(self, peer, frame, commit):
        """After current-pair AEAD validation, bind to our exact local attempt.

        commit may retire the existing durable outbox row. Its failure must
        leave transport retries live. There is no receipt-of-receipt here.
        """
        with self._lock:
            sent = self._sent.get(frame.attempt.attempt_id)
            if self._closed or not sent or sent.frame != frame or sent.job.delivery.peer != peer or sent.job.accepted:
                return False
            job = sent.job
        commit()
        with self._lock:
            completed = self.policy.accept_verified_receipt(peer, frame.message.message_id,
                frame.message.content_hash, frame.attempt.attempt_id, now=self._clock())
            if not completed:
                return False
            job.accepted = True
            job.scheduled.clear()
            # Sent copies stay accounted until PUBACK/disconnect. Unsent copies
            # are cancelled; a business receipt is not a fake broker receipt.
            for key in completed:
                other = self._sent.get(key)
                if other and not other.pending:
                    self._sent.pop(key, None)
                    other.job.attempts.discard(key)
            return True

    def accept_verified_message(self, peer, message_id, content_hash):
        """Called only after the existing ciphertext-bound outbox ACK passes."""
        with self._lock:
            if self._closed:
                return
            self.policy.accept_verified_message(peer, message_id, content_hash)
            for job in self._jobs.values():
                message = job.delivery.message
                if (job.delivery.peer, message.message_id, message.content_hash) == (peer, message_id, content_hash):
                    job.accepted = True
                    job.scheduled.clear()

    def tick(self):
        now = self._clock()
        with self._lock:
            due = [job for job in self._jobs.values() if self._expired(job, now) or job.accepted
                   or (job.scheduled and job.scheduled[0][0] <= now)]
            urgent = [job for job in due if job.delivery.message.traffic in {"control", "final", "receipt"}]
            ordinary = [job for job in due if job.delivery.message.traffic not in {"control", "final", "receipt"}]
            jobs = urgent[:12] + ordinary[:4]
            jobs += (urgent[12:] + ordinary[4:])[:16 - len(jobs)]
            for job in jobs:
                self._jobs.pop(job.key, None)
                self._jobs[job.key] = job
        for job in jobs:
            with self._lock:
                if self._expired(job, now) or job.accepted:
                    self._retire(job)
                    continue
            self._pump(job, now)

    @staticmethod
    def _expired(job, now):
        return now - job.started >= CATALOG["timing"]["attempt_observation_seconds"]

    def _retire(self, job):
        if job.publishing:
            return
        job.scheduled.clear()
        for key in list(job.attempts):
            sent = self._sent.get(key)
            if sent and not sent.pending:
                self._sent.pop(key, None)
                self.policy.discard_attempt(key)
                job.attempts.discard(key)
        if not job.attempts:
            self._jobs.pop(job.key, None)

    def close(self):
        with self._lock:
            self._closed = True
            jobs = list(self._jobs.values())
            for job in jobs:
                self._retire(job)
        for job in jobs:
            self._finish(job, False)

    def diagnostics(self):
        with self._lock:
            return {"messages": len(self._jobs), "tracked_attempts": len(self._sent),
                    "queued_copies": sum(len(job.scheduled) for job in self._jobs.values()),
                    "buffered_bytes": sum(job.delivery.size_bound for job in self._jobs.values())}
