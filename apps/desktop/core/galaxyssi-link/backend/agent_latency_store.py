"""Bounded, best-effort diagnostic journal; no task work waits for disk I/O."""

from collections import deque
from dataclasses import asdict
import json
from pathlib import Path
import threading

from agent_latency import AgentTimingPoint, TRACE_LIMIT


class AgentTimingJournal:
    def __init__(self, path: Path, *, queue_limit=1024, byte_limit=2 * 1024 * 1024):
        self.path = path
        self.previous = path.with_suffix(".previous.jsonl")
        self.queue_limit = max(1, queue_limit)
        self.byte_limit = byte_limit
        self._points = deque(maxlen=TRACE_LIMIT)
        self._pending = deque()
        self._condition = threading.Condition()
        self._closed = False
        self._loading = True
        self._dropped = 0
        self._failures = 0
        self._invalid = 0
        self._worker = threading.Thread(target=self._run, name="agent-latency-writer", daemon=True)
        self._worker.start()

    def append(self, point):
        with self._condition:
            if self._closed:
                return
            self._points.append(point)
            if len(self._pending) == self.queue_limit:
                self._pending.popleft()
                self._dropped += 1
            self._pending.append(point)
            self._condition.notify()

    def snapshot(self):
        with self._condition:
            return list(self._points)

    def health(self):
        with self._condition:
            return {"loading": self._loading, "dropped_events": self._dropped,
                    "write_failures": self._failures, "invalid_events": self._invalid,
                    "event_limit": TRACE_LIMIT, "retention": "bounded_recent_events"}

    def close(self, timeout=5):
        with self._condition:
            self._closed = True
            self._condition.notify_all()
        self._worker.join(timeout)
        return not self._worker.is_alive()

    def _run(self):
        loaded = deque(maxlen=TRACE_LIMIT)
        try:
            for source in (self.previous, self.path):
                if source.is_file():
                    with source.open("rb") as stream:
                        # A corrupt diagnostic file must not allocate an unbounded line.
                        while line := stream.readline(2049):
                            try:
                                if len(line) > 2048 or not line.endswith(b"\n"):
                                    while line and not line.endswith(b"\n"):
                                        line = stream.readline(2049)
                                    raise ValueError("Oversized or incomplete timing record")
                                loaded.append(AgentTimingPoint.decode(json.loads(line)))
                            except (TypeError, ValueError, AttributeError):
                                self._invalid += 1
                                continue
        except OSError:
            with self._condition:
                self._failures += 1
        with self._condition:
            loaded.extend(self._points)
            self._points = loaded
            self._loading = False
        while True:
            with self._condition:
                self._condition.wait_for(lambda: self._pending or self._closed)
                if not self._pending and self._closed:
                    return
                batch = [self._pending.popleft() for _ in range(min(64, len(self._pending)))]
            try:
                self.path.parent.mkdir(parents=True, exist_ok=True)
                if self.path.exists() and self.path.stat().st_size >= self.byte_limit:
                    self.previous.unlink(missing_ok=True)
                    self.path.replace(self.previous)
                with self.path.open("a", encoding="utf-8") as stream:
                    for point in batch:
                        stream.write(json.dumps(asdict(point), separators=(",", ":")) + "\n")
            except OSError:
                with self._condition:
                    self._failures += 1
