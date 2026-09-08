"""Bounded local execution with round-robin App and conversation admission."""
from __future__ import annotations

from collections import OrderedDict
from concurrent.futures import Future
from dataclasses import dataclass
import threading
import time
from typing import Callable


class AgentQueueFull(RuntimeError):
    pass


@dataclass(frozen=True)
class ExecutionKey:
    app: str
    conversation: str
    turn: str
    task: str
    generation: int


@dataclass
class _Work:
    key: ExecutionKey
    callback: Callable[[], object]
    future: Future


class AgentWorkPool:
    """Queue waiting work, not waiting threads; callbacks never hold the queue lock."""

    def __init__(self, *, max_workers=10, max_pending=10000, idle_seconds=5.0):
        if not 1 <= int(max_workers) <= 128 or not 1 <= int(max_pending) <= 10000:
            raise ValueError("Worker and pending limits are outside supported bounds")
        self.max_workers, self.max_pending = int(max_workers), int(max_pending)
        self.idle_seconds = max(0.01, float(idle_seconds))
        self._condition = threading.Condition()
        self._apps: OrderedDict[str, OrderedDict] = OrderedDict()
        self._pending: dict[ExecutionKey, _Work] = {}
        self._active: dict[ExecutionKey, _Work] = {}
        self._workers: set[threading.Thread] = set()
        self._closed = False
        self._rejected = 0

    def submit(self, key: ExecutionKey, callback: Callable[[], object]) -> Future:
        if not isinstance(key, ExecutionKey) or not all((key.app, key.conversation, key.turn, key.task)):
            raise ValueError("Complete execution identity is required")
        if type(key.generation) is not int or key.generation < 1 or not callable(callback):
            raise ValueError("Valid execution generation and callback are required")
        with self._condition:
            if self._closed:
                raise RuntimeError("Agent work pool is closed")
            existing = self._pending.get(key) or self._active.get(key)
            if existing is not None:
                return existing.future
            if len(self._pending) >= self.max_pending:
                self._rejected += 1
                raise AgentQueueFull("Desktop Agent queue is full; retry after capacity is available")
            work = _Work(key, callback, Future())
            self._apps.setdefault(key.app, OrderedDict()).setdefault(
                key.conversation, OrderedDict(),
            )[key] = work
            self._pending[key] = work
            desired = min(self.max_workers, len(self._active) + len(self._pending))
            while len(self._workers) < desired:
                thread = threading.Thread(target=self._run, daemon=True, name="galaxyssi-agent-worker")
                self._workers.add(thread)
                try:
                    thread.start()
                except Exception:
                    self._workers.remove(thread)
                    self._remove_pending(key)
                    raise
            self._condition.notify_all()
            return work.future

    def _remove_pending(self, key: ExecutionKey) -> _Work | None:
        work = self._pending.pop(key, None)
        if work is None:
            return None
        conversations = self._apps[key.app]
        lane = conversations[key.conversation]
        lane.pop(key)
        if not lane:
            conversations.pop(key.conversation)
        if not conversations:
            self._apps.pop(key.app)
        return work

    def cancel(self, key: ExecutionKey) -> bool:
        with self._condition:
            work = self._remove_pending(key)
            self._condition.notify_all()
        return work.future.cancel() if work is not None else False

    def _next(self) -> _Work:
        app, conversations = self._apps.popitem(last=False)
        conversation, lane = conversations.popitem(last=False)
        key, work = lane.popitem(last=False)
        if lane:
            conversations[conversation] = lane
        if conversations:
            self._apps[app] = conversations
        self._pending.pop(key)
        self._active[key] = work
        return work

    def _run(self):
        current = threading.current_thread()
        while True:
            with self._condition:
                available = self._condition.wait_for(
                    lambda: self._pending or self._closed, timeout=self.idle_seconds,
                )
                if not available or (self._closed and not self._pending):
                    self._workers.discard(current)
                    self._condition.notify_all()
                    return
                work = self._next()
            try:
                if work.future.set_running_or_notify_cancel():
                    try:
                        value = work.callback()
                    except BaseException as error:
                        work.future.set_exception(error)
                    else:
                        work.future.set_result(value)
            finally:
                with self._condition:
                    self._active.pop(work.key, None)
                    self._condition.notify_all()

    def snapshot(self) -> dict:
        with self._condition:
            return {"max_workers": self.max_workers, "max_pending": self.max_pending,
                    "active": len(self._active), "pending": len(self._pending),
                    "workers": len(self._workers), "queued_apps": len(self._apps),
                    "rejected": self._rejected, "closed": self._closed}

    def wait_idle(self, timeout=5.0) -> bool:
        with self._condition:
            return self._condition.wait_for(lambda: not self._pending and not self._active, timeout)

    def close(self, *, wait=True, cancel_pending=False, timeout=5.0) -> bool:
        with self._condition:
            self._closed = True
            cancelled = list(self._pending.values()) if cancel_pending else []
            if cancel_pending:
                self._pending.clear()
                self._apps.clear()
            workers = list(self._workers)
            self._condition.notify_all()
        for work in cancelled:
            work.future.cancel()
        if wait:
            deadline = time.monotonic() + max(0.0, timeout)
            for worker in workers:
                if worker is not threading.current_thread():
                    worker.join(max(0.0, deadline - time.monotonic()))
        with self._condition:
            return not self._workers
