"""Bounded wire admission with serial Signal processing and fair route rotation.

Execution-task pooling cannot preserve this boundary: logical task identity is
not known until decryption, and every envelope from a peer must remain ordered.
"""
from collections import OrderedDict, deque
import logging
import threading
import time


log = logging.getLogger(__name__)


class InboundRoutePool:
    def __init__(self, process, *, max_workers=8, max_pending=10000,
                 max_bytes=64 * 1024 * 1024, route_pending=128,
                 route_bytes=8 * 1024 * 1024, idle_seconds=5.0):
        for value, maximum in ((max_workers, 128), (max_pending, 10000),
                               (max_bytes, 1024**3), (route_pending, 10000), (route_bytes, 1024**3)):
            if type(value) is not int or not 1 <= value <= maximum:
                raise ValueError("Invalid inbound pool bound")
        if not callable(process) or not 0 < idle_seconds <= 120 or route_bytes > max_bytes:
            raise ValueError("Invalid inbound processor or route budget")
        self.process = process
        self.max_workers, self.max_pending, self.max_bytes = max_workers, max_pending, max_bytes
        self.route_pending, self.route_bytes, self.idle_seconds = route_pending, route_bytes, idle_seconds
        self._condition = threading.Condition()
        self._routes = {}
        self._ready = OrderedDict()
        self._route_bytes = {}
        self._active = set()
        self._workers = set()
        self._pending = self._retained_bytes = 0
        self._high_pending = self._high_bytes = 0
        self._accepted = self._processed = self._failed = self._cancelled = 0
        self._rejected = {}
        self._closed = False

    def _reject(self, reason):
        self._rejected[reason] = self._rejected.get(reason, 0) + 1
        return reason

    def submit(self, route, item, size):
        """Return an admission code; never wait for a worker or invoke the handler inline."""
        if not isinstance(route, str) or not route or len(route) > 512 or type(size) is not int or size < 1:
            raise ValueError("A bounded route and positive retained wire size are required")
        with self._condition:
            if self._closed:
                return self._reject("closed")
            lane = self._routes.get(route)
            if lane is not None and len(lane) >= self.route_pending:
                return self._reject("route_pending")
            if self._route_bytes.get(route, 0) + size > self.route_bytes:
                return self._reject("route_bytes")
            if self._pending >= self.max_pending:
                return self._reject("global_pending")
            if self._retained_bytes + size > self.max_bytes:
                return self._reject("global_bytes")
            lane = self._routes.setdefault(route, deque())
            lane.append((item, size))
            self._pending += 1
            self._retained_bytes += size
            self._route_bytes[route] = self._route_bytes.get(route, 0) + size
            if route not in self._active:
                self._ready.setdefault(route, None)
            desired = min(self.max_workers, len(self._active) + len(self._ready))
            while len(self._workers) < desired:
                worker = threading.Thread(target=self._run, daemon=True, name="galaxyssi-mqtt-inbound")
                self._workers.add(worker)
                try:
                    worker.start()
                except Exception:
                    self._workers.remove(worker)
                    if not self._workers:
                        lane.pop()
                        self._pending -= 1
                        self._release(route, size)
                        self._ready.pop(route, None)
                        return self._reject("worker_unavailable")
                    break
            self._accepted += 1
            self._high_pending = max(self._high_pending, self._pending)
            self._high_bytes = max(self._high_bytes, self._retained_bytes)
            self._condition.notify_all()
            return "accepted"

    def _release(self, route, size):
        self._retained_bytes -= size
        self._route_bytes[route] -= size
        if not self._routes[route] and route not in self._active:
            self._routes.pop(route)
            self._route_bytes.pop(route)

    def _run(self):
        worker = threading.current_thread()
        while True:
            with self._condition:
                available = self._condition.wait_for(lambda: self._ready or self._closed, self.idle_seconds)
                if not available or (self._closed and not self._ready):
                    self._workers.discard(worker)
                    self._condition.notify_all()
                    return
                route, _ = self._ready.popitem(last=False)
                item, size = self._routes[route].popleft()
                self._pending -= 1
                self._active.add(route)
            failed = False
            try:
                self.process(item)
            except BaseException as error:
                failed = True
                log.error("MQTT inbound handler failed (%s)", type(error).__name__)
            finally:
                # Drop the retained envelope before advertising its budget as free.
                item = None
                with self._condition:
                    self._active.remove(route)
                    self._release(route, size)
                    if self._routes.get(route):
                        self._ready[route] = None
                    self._processed += 1
                    self._failed += int(failed)
                    self._condition.notify_all()

    def snapshot(self):
        with self._condition:
            return {"max_workers": self.max_workers, "max_pending": self.max_pending,
                "max_bytes": self.max_bytes, "route_pending_limit": self.route_pending,
                "route_bytes_limit": self.route_bytes, "workers": len(self._workers),
                "active": len(self._active), "pending": self._pending, "routes": len(self._routes),
                "retained_bytes": self._retained_bytes, "high_pending": self._high_pending,
                "high_bytes": self._high_bytes, "accepted": self._accepted, "processed": self._processed,
                "failed": self._failed, "cancelled": self._cancelled,
                "rejected": dict(self._rejected), "closed": self._closed}

    def wait_idle(self, timeout=5.0):
        with self._condition:
            return self._condition.wait_for(lambda: not self._active and not self._pending, timeout)

    def close(self, *, wait=True, cancel_pending=True, timeout=5.0):
        with self._condition:
            self._closed = True
            if cancel_pending:
                for route in list(self._routes):
                    lane = self._routes[route]
                    while lane:
                        item, size = lane.popleft()
                        item = None
                        self._pending -= 1
                        self._cancelled += 1
                        self._release(route, size)
                self._ready.clear()
            workers = list(self._workers)
            self._condition.notify_all()
        if wait:
            deadline = time.monotonic() + max(0.0, timeout)
            for worker in workers:
                if worker is not threading.current_thread():
                    worker.join(max(0.0, deadline - time.monotonic()))
        with self._condition:
            return not self._workers
