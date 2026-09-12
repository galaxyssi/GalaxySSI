"""Bound best-effort progress by authenticated phone receipts, not broker PUBACKs."""

import threading
import time


class TaskProgressWindow:
    def __init__(self, limit=2, ttl=30.0, max_routes=4096, clock=time.monotonic):
        self.limit, self.ttl, self.max_routes, self.clock = limit, ttl, max_routes, clock
        self._routes = {}
        self._lock = threading.Lock()

    def reserve(self, route, message):
        if not route or not message:
            return False
        with self._lock:
            now = self.clock()
            if route not in self._routes and len(self._routes) >= self.max_routes:
                self._routes = {key: pending for key, pending in self._routes.items()
                                if any(deadline > now for deadline in pending.values())}
                if len(self._routes) >= self.max_routes:
                    return False
            pending = {key: deadline for key, deadline in self._routes.get(route, {}).items() if deadline > now}
            self._routes[route] = pending
            if len(pending) >= self.limit:
                return False
            pending[message] = now + self.ttl
            return True

    def release(self, route, message):
        with self._lock:
            pending = self._routes.get(route)
            if pending is None or message not in pending:
                return False
            del pending[message]
            if not pending:
                del self._routes[route]
            return True
