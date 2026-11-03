"""Bounded, hash-only receipts for inputs already submitted to a phone planner thread."""

from collections import OrderedDict
import hashlib
from pathlib import Path
import time
import threading


class PlannerContinuations:
    def __init__(self, clock=time.monotonic, capacity=128, ttl=600):
        self.clock, self.capacity, self.ttl = clock, capacity, ttl
        self.records = OrderedDict()
        self.lock = threading.RLock()
        self.epoch = 0

    @staticmethod
    def fingerprints(prompt, images):
        chunks = [hashlib.sha256(prompt[i:i + 256].encode()).digest() for i in range(0, len(prompt), 256)]
        pictures = {}
        for path in images:
            digest = hashlib.sha256()
            with Path(path).open("rb") as source:
                for chunk in iter(lambda: source.read(1024 * 1024), b""):
                    digest.update(chunk)
            pictures[path] = digest.digest()
        return chunks, pictures

    def prepare(self, thread, prompt, images):
        # Disk I/O must never hold the App Server state or receipt lock.
        chunks, pictures = self.fingerprints(prompt, images)
        with self.lock:
            return self._prepare(thread, prompt, images, chunks, pictures)

    def _prepare(self, thread, prompt, images, chunks, pictures):
        now = self.clock()
        for key, value in list(self.records.items()):
            if now - value[0] >= self.ttl:
                del self.records[key]
        prior = self.records.get(thread)
        if prior is None:
            return prompt, images, (chunks, set(pictures.values()), self.epoch)
        common = 0
        for old, new in zip(prior[1], chunks):
            if old != new:
                break
            common += 256
        boundary = prompt.rfind("\n", 0, min(common, len(prompt)))
        current = prompt
        if boundary >= 2048:
            current = (
                "Continue the same phone goal. Retain the unchanged instructions already supplied in this thread. "
                "The current state/evidence below supersedes previous transient observations; do not repeat completed work.\n"
                + prompt[boundary + 1:]
            )
        remaining = [path for path in images if pictures[path] not in prior[2]]
        # Forgotten hashes only cause a full resend, never missing input.
        known = prior[2] | set(pictures.values())
        if len(known) > 128:
            known = set(pictures.values())
        return current, remaining, (chunks, known, self.epoch)

    def commit(self, thread, receipt):
        with self.lock:
            if receipt[2] != self.epoch:
                return
            self.records[thread] = (self.clock(), receipt[0], receipt[1])
            self.records.move_to_end(thread)
            while len(self.records) > self.capacity:
                self.records.popitem(last=False)

    def forget(self, thread):
        with self.lock:
            self.epoch += 1
            self.records.pop(thread, None)
