"""Bounded context-compaction phase, independent of ordinary output silence."""
from dataclasses import dataclass, field

COMPACTION_TIMEOUT_SECONDS = 300.0


@dataclass
class CompactionPhase:
    item_id: str = ""
    started: float | None = None
    last_probe: float = 0
    closed: set[str] = field(default_factory=set)

    def observe(self, method, params, now):
        item = params.get("item") or {}
        identity = str(item.get("id") or "context-compaction")
        if method == "item/started" and item.get("type") == "contextCompaction":
            if self.started is None and identity not in self.closed:
                self.item_id, self.started, self.last_probe = identity, now, now
        elif method == "thread/compacted":
            self.closed.add(identity)
            if self.item_id:
                self.closed.add(self.item_id)
            self.started = None
        elif method == "item/completed" and item.get("type") == "contextCompaction":
            self.closed.add(identity)
            if identity == self.item_id:
                self.started = None

    def expired(self, now, budget):
        return self.started is not None and now - self.started >= budget

    def probe_due(self, now):
        return self.started is not None and now - self.last_probe >= 30
