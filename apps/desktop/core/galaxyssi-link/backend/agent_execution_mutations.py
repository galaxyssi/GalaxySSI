"""Immutable execution binding for asynchronous provider callbacks."""
from dataclasses import dataclass
from typing import Any

from agent_work_pool import ExecutionKey


@dataclass(frozen=True)
class AgentExecutionMutations:
    manager: Any
    key: ExecutionKey

    def _call(self, method, task_id, *args, **kwargs):
        if task_id != self.key.task:
            return None
        return getattr(self.manager, method)(task_id, *args, expected_execution=self.key, **kwargs)

    def update(self, task_id, *args, **kwargs):
        return self._call("update", task_id, *args, **kwargs)

    def add_event(self, task_id, *args, **kwargs):
        return self._call("add_event", task_id, *args, **kwargs)

    def record_partial_result(self, task_id, *args, **kwargs):
        return self._call("record_partial_result", task_id, *args, **kwargs)

    def snapshot(self):
        return self.manager.execution_snapshot(self.key)

    def current(self):
        return self.manager.is_current_execution(self.key)

    def accepts(self, snapshot):
        if not isinstance(snapshot, dict):
            return False
        return (
            snapshot.get("client_route_id") == self.key.app
            and (snapshot.get("client_conversation_id") or snapshot.get("conversation_id")) == self.key.conversation
            and snapshot.get("client_turn_id") == self.key.turn
            and snapshot.get("task_id") == self.key.task
            and snapshot.get("execution_generation") == self.key.generation
            and self.current()
        )
