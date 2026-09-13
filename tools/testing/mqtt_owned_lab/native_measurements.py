"""Bounded, test-only monotonic measurements at real native delivery boundaries."""
import copy
import math
import threading
import time


class Measurements:
    def __init__(self, *, clock=time.perf_counter_ns, limit=512):
        self.clock, self.limit = clock, limit
        self.started = clock()
        self.ready = None
        self.samples = {}
        self.lock = threading.Lock()

    def first_ready(self):
        with self.lock:
            if self.ready is None:
                self.ready = self.clock()

    def begin(self, message_id):
        with self.lock:
            if message_id in self.samples or len(self.samples) >= self.limit:
                raise ValueError("Measurement ID reused or bounded sample capacity exceeded")
            self.samples[message_id] = {"stages": {"started": self.clock()}, "packets": {}}

    def stage(self, message_id, name):
        with self.lock:
            sample = self.samples.get(message_id)
            if sample is not None:
                sample["stages"].setdefault(name, self.clock())

    def physical_start(self, message_id, attempt_id, broker, size):
        with self.lock:
            sample = self.samples.get(message_id)
            if sample is not None:
                if len(sample["packets"]) >= 128 or attempt_id in sample["packets"]:
                    raise ValueError("Physical measurement bound exceeded or attempt ID reused")
                now = self.clock()
                sample["packets"][attempt_id] = {"broker": broker, "bytes": size, "at_ns": now,
                                                  "accepted": None}

    def physical_end(self, message_id, attempt_id, accepted):
        with self.lock:
            sample = self.samples.get(message_id)
            if sample is not None and attempt_id in sample["packets"]:
                packet = sample["packets"][attempt_id]
                packet["accepted"] = bool(accepted)
                if accepted:
                    sample["stages"]["first_publish"] = min(packet["at_ns"],
                        sample["stages"].get("first_publish", packet["at_ns"]))

    def snapshot(self, message_id=None):
        with self.lock:
            if message_id is not None:
                return copy.deepcopy(self.samples.get(message_id))
            return {"startup_to_authenticated_ready_ms": None if self.ready is None else
                    (self.ready - self.started) / 1_000_000, "samples": copy.deepcopy(self.samples)}


def summarize(samples):
    """Nearest-rank percentiles; callers retain failed/censored sample details."""
    if not samples:
        raise ValueError("Cannot summarize an empty sample set")
    metrics = {"request_to_rx_stored_ms": [], "queued_to_rx_stored_ms": [],
               "first_publish_to_rx_stored_ms": [], "request_to_queued_ms": []}
    byte_count, redundant, packets = 0, 0, 0
    paths = {}
    for sample in samples:
        stages = sample["stages"]
        for required in ("started", "queued", "first_publish", "receipt_committed"):
            if required not in stages:
                raise ValueError("Incomplete delivery sample")
        for name, start, end in (
            ("request_to_rx_stored_ms", "started", "receipt_committed"),
            ("queued_to_rx_stored_ms", "queued", "receipt_committed"),
            ("first_publish_to_rx_stored_ms", "first_publish", "receipt_committed"),
            ("request_to_queued_ms", "started", "queued"),
        ):
            elapsed = (stages[end] - stages[start]) / 1_000_000
            if elapsed < 0 or not math.isfinite(elapsed):
                raise ValueError("Invalid monotonic stage order")
            metrics[name].append(elapsed)
        attempts = list(sample["packets"].values())
        if any(item["accepted"] is None for item in attempts):
            raise ValueError("Physical publish still in progress")
        accepted = sorted((item for item in attempts if item["accepted"]), key=lambda item: item["at_ns"])
        if not accepted:
            raise ValueError("No actual physical submission")
        sizes = [item["bytes"] for item in accepted]
        byte_count += sum(sizes)
        redundant += sum(sizes[1:])
        packets += len(sizes)
        for item in accepted:
            paths[item["broker"]] = paths.get(item["broker"], 0) + 1
    result = {"samples": len(samples), "submitted_mqtt_bytes": byte_count,
              "redundant_submitted_mqtt_bytes": redundant, "submitted_packets": packets,
              "submitted_packets_by_path": paths, "percentile_method": "nearest_rank"}
    for name, values in metrics.items():
        ordered = sorted(values)
        result[name] = {"p50": ordered[math.ceil(len(ordered) * .5) - 1],
                        "p95": ordered[math.ceil(len(ordered) * .95) - 1], "max": ordered[-1]}
    return result
