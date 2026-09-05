"""Content-free, per-response search timings, including preparation and cache I/O."""
from __future__ import annotations

import time
from typing import Callable


class SearchResponseTiming:
    def __init__(self, clock: Callable[[], int] = time.perf_counter_ns):
        self.clock = clock
        self.started = self.previous = clock()
        self.phases: dict[str, float] = {}

    def mark(self, name: str) -> None:
        current = self.clock()
        self.phases[name] = round(max(0, current - self.previous) / 1_000_000, 3)
        self.previous = current

    def finish(self, result: dict, *, completed_at_millis: int, source_budget_seconds: float) -> dict:
        self.mark("finalize")
        elapsed = max(0, self.previous - self.started) / 1_000_000
        metadata = result.setdefault("metadata", {})
        metadata["elapsed_millis"] = int(elapsed)
        metadata["response_timing"] = {
            "scope": "search_response", "clock": "perf_counter",
            "elapsed_ms": round(elapsed, 3), "phases_ms": dict(self.phases),
            "source_budget_ms": round(source_budget_seconds * 1_000, 3),
        }
        result["completed_at_millis"] = completed_at_millis
        return result
