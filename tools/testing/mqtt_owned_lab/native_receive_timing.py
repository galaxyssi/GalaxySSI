"""Bounded observation of unchanged native receive/receipt calls in owned tests."""
import copy
import threading
import time


class ReceiveTiming:
    def __init__(self, *, clock=time.perf_counter_ns, limit=512, calls_per_message=16):
        self.clock, self.limit, self.calls_per_message = clock, limit, calls_per_message
        self.lock = threading.Lock()
        self.current = threading.local()
        self.samples = {}
        self.dropped = 0

    def snapshot(self):
        with self.lock:
            return {"samples": copy.deepcopy(self.samples), "dropped_calls": self.dropped}

    def stage(self, name):
        sample = getattr(self.current, "sample", None)
        if sample is not None:
            with self.lock:
                sample["stages"].setdefault(name, self.clock())

    def install(self, bridge):
        actual_deliver = bridge._deliver_stored_application

        def deliver(mqttc, paired, wire, envelope, payload, trace, **kwargs):
            mid = envelope["message_id"]
            sample = {"kind": payload.get("type"), "stages": dict(kwargs.get("timings", ()))}
            with self.lock:
                calls = self.samples.get(mid)
                if calls is None and len(self.samples) < self.limit:
                    calls = self.samples[mid] = []
                if calls is not None and len(calls) < self.calls_per_message:
                    calls.append(sample)
                else:
                    self.dropped += 1
                    sample = None
            previous = getattr(self.current, "sample", None)
            self.current.sample = sample
            self.stage("delivery_enter")
            try:
                return actual_deliver(mqttc, paired, wire, envelope, payload, trace, **kwargs)
            finally:
                self.stage("delivery_return")
                self.current.sample = previous

        bridge._deliver_stored_application = deliver
        for attribute, label in (("_ack_stored_application", "ack"),
                                 ("_publish_phone_payload", "publish"),
                                 ("_dispatch_application_payload", "dispatch")):
            setattr(bridge, attribute, self.wrap(getattr(bridge, attribute), label))

    def wrap(self, actual, label):
        def observed(*args, **kwargs):
            self.stage(label + "_enter")
            try:
                return actual(*args, **kwargs)
            finally:
                self.stage(label + "_return")
        return observed
