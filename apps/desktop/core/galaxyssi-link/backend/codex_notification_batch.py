"""Drain adjacent text deltas without delaying RPC replies or lifecycle events."""
from __future__ import annotations

from dataclasses import dataclass
import queue


@dataclass(frozen=True)
class NotificationBatch:
    message: dict
    entries: int


class CodexNotificationBatcher:
    """Single-consumer adapter; only already queued, identical-scope deltas merge."""

    def __init__(self, events: queue.Queue, max_delta_characters: int = 64_000):
        if max_delta_characters <= 0:
            raise ValueError("max_delta_characters must be positive")
        self.events = events
        self.max_delta_characters = max_delta_characters
        self._pending: dict | None = None

    def get(self, timeout: float = 0.1) -> NotificationBatch:
        if self._pending is None:
            first = self.events.get(timeout=timeout)
        else:
            first, self._pending = self._pending, None
        signature = self._signature(first)
        if signature is None:
            return NotificationBatch(first, 1)
        chunks = [first["params"]["delta"]]
        size = len(chunks[0])
        while size < self.max_delta_characters:
            try:
                following = self.events.get_nowait()
            except queue.Empty:
                break
            if self._signature(following) != signature:
                self._pending = following
                break
            delta = following["params"]["delta"]
            if size + len(delta) > self.max_delta_characters:
                self._pending = following
                break
            chunks.append(delta)
            size += len(delta)
        if len(chunks) == 1:
            return NotificationBatch(first, 1)
        merged = {**first, "params": {**first["params"], "delta": "".join(chunks)}}
        return NotificationBatch(merged, len(chunks))

    def task_done(self, batch: NotificationBatch) -> None:
        for _ in range(batch.entries):
            self.events.task_done()

    @staticmethod
    def _signature(message: dict) -> tuple[dict, dict] | None:
        if "id" in message or message.get("method") != "item/agentMessage/delta":
            return None
        params = message.get("params")
        if not isinstance(params, dict) or not isinstance(params.get("delta"), str):
            return None
        # All identity and extension fields must agree; lifecycle/tool events are barriers.
        if not all(isinstance(params.get(key), str) and params[key] for key in ("threadId", "turnId", "itemId")):
            return None
        return ({key: value for key, value in message.items() if key != "params"},
                {key: value for key, value in params.items() if key != "delta"})
