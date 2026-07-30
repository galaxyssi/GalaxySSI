"""Durable pause, manual takeover, and continuation for Desktop Agent runs."""

from __future__ import annotations

import threading
from typing import Callable

from agent_task_manager import AgentTask, AgentTaskManager, EventCallback, agent_task_manager


TASK_PAUSE = "desktop.task_pause"
TASK_TAKEOVER = "desktop.task_takeover"
TASK_CONTINUE = "desktop.task_continue"
TASK_RELEASE = "desktop.task_release"
TASK_CONTROL_TOOLS = (
    TASK_PAUSE,
    TASK_TAKEOVER,
    TASK_CONTINUE,
    TASK_RELEASE,
)

Runner = Callable[[AgentTask], str]
RunnerFactory = Callable[[AgentTask, dict], Runner]
InterruptHandler = Callable[[AgentTask], dict]
CheckpointProvider = Callable[[AgentTask], dict]
TaskManagerProvider = Callable[[], AgentTaskManager]


class DesktopRunControlError(RuntimeError):
    def __init__(self, code: str, message: str, *, retryable: bool = False) -> None:
        super().__init__(message)
        self.code = str(code or "desktop_run_control_failed")
        self.retryable = bool(retryable)


class DesktopRunControlCoordinator:
    def __init__(self) -> None:
        self._lock = threading.RLock()
        self._runner_factory: RunnerFactory | None = None
        self._interrupt_handler: InterruptHandler | None = None
        self._checkpoint_provider: CheckpointProvider | None = None
        self._event_handler: EventCallback | None = None
        self._result_handler: EventCallback | None = None
        self._task_manager_provider: TaskManagerProvider = lambda: agent_task_manager

    def configure(
        self,
        *,
        runner_factory: RunnerFactory,
        interrupt_handler: InterruptHandler,
        checkpoint_provider: CheckpointProvider,
        task_manager_provider: TaskManagerProvider | None = None,
        event_handler: EventCallback | None = None,
        result_handler: EventCallback | None = None,
    ) -> None:
        with self._lock:
            self._runner_factory = runner_factory
            self._interrupt_handler = interrupt_handler
            self._checkpoint_provider = checkpoint_provider
            self._event_handler = event_handler
            self._result_handler = result_handler
            if task_manager_provider is not None:
                self._task_manager_provider = task_manager_provider

    def execute(
        self,
        tool_id: str,
        arguments: dict,
        controller: dict,
    ) -> dict:
        task_id = str(arguments.get("task_id") or "").strip()
        if not task_id:
            raise DesktopRunControlError(
                "task_id_required",
                "Desktop task control requires task_id",
            )
        manager = self._task_manager_provider()
        task = manager.get(task_id)
        if task is None:
            raise DesktopRunControlError("task_not_found", "Desktop task was not found")
        self._authorize_task(task, controller)

        if tool_id == TASK_PAUSE:
            return self._pause(manager, task, controller)
        if tool_id == TASK_TAKEOVER:
            return self._takeover(manager, task, controller, arguments)
        if tool_id == TASK_RELEASE:
            released = manager.release_takeover(
                task.task_id,
                reason="Manual takeover ended by the controller",
                on_event=self._event_handler,
            )
            if released is None or released.status != "paused":
                raise DesktopRunControlError(
                    "task_not_in_takeover",
                    "Only a manually controlled task can end takeover",
                )
            return self._task_result(released, "Manual takeover ended")
        if tool_id == TASK_CONTINUE:
            return self._continue(manager, task)
        raise DesktopRunControlError("invalid_tool", "Desktop run control tool is not supported")

    def _pause(
        self,
        manager: AgentTaskManager,
        task: AgentTask,
        controller: dict,
    ) -> dict:
        if task.status in {"paused", "takeover"}:
            return self._task_result(task, "Task is already paused")
        if self._interrupt_handler is None:
            raise DesktopRunControlError(
                "run_control_unavailable",
                "Desktop run control is not ready",
                retryable=True,
            )
        paused = manager.pause(
            task.task_id,
            reason=(
                f"Paused by "
                f"{str(controller.get('controller_name') or 'user')[:120]}"
            ),
            on_event=self._event_handler,
        )
        if paused is None or paused.status != "paused":
            raise DesktopRunControlError(
                "task_not_pausable",
                "This task cannot be paused in its current state",
            )
        interruption = self._interrupt_handler(paused)
        result = self._task_result(paused, "Task paused")
        result["interruption"] = dict(interruption or {})
        return result

    def _takeover(
        self,
        manager: AgentTaskManager,
        task: AgentTask,
        controller: dict,
        arguments: dict,
    ) -> dict:
        if task.status not in {"paused", "takeover"}:
            self._pause(manager, task, controller)
            task = manager.get(task.task_id) or task
        lease_seconds = max(
            30,
            min(3_600, int(arguments.get("lease_seconds") or 900)),
        )
        taken = manager.begin_takeover(
            task.task_id,
            controller,
            lease_seconds=lease_seconds,
            on_event=self._event_handler,
        )
        if taken is None or taken.status != "takeover":
            raise DesktopRunControlError(
                "task_takeover_unavailable",
                "The task could not enter manual takeover",
            )
        return self._task_result(taken, "Manual takeover started")

    def _continue(
        self,
        manager: AgentTaskManager,
        task: AgentTask,
    ) -> dict:
        if task.status not in {"paused", "takeover"}:
            raise DesktopRunControlError(
                "task_not_resumable",
                "Only a paused task can continue",
            )
        with self._lock:
            runner_factory = self._runner_factory
            checkpoint_provider = self._checkpoint_provider
        if runner_factory is None or checkpoint_provider is None:
            raise DesktopRunControlError(
                "run_control_unavailable",
                "Desktop run continuation is not ready",
                retryable=True,
            )
        checkpoint_bundle = checkpoint_provider(task)
        runner = runner_factory(task, checkpoint_bundle)
        persisted_checkpoint = (
            dict(checkpoint_bundle.get("persisted") or {})
            if isinstance(checkpoint_bundle, dict)
            else {}
        )
        continued = manager.continue_task(
            task.task_id,
            runner,
            on_event=self._event_handler or (lambda _event: None),
            on_result=self._result_handler,
            checkpoint=persisted_checkpoint,
        )
        if continued is None or continued.status not in {"queued", "running"}:
            raise DesktopRunControlError(
                "task_continue_failed",
                "The paused task could not continue",
                retryable=True,
            )
        return self._task_result(continued, "Task continued")

    @staticmethod
    def _authorize_task(task: AgentTask, controller: dict) -> None:
        platform = str(controller.get("controller_platform") or "").strip().lower()
        if platform == "desktop":
            return
        route_id = str(controller.get("client_route_id") or "").strip()
        if not route_id:
            raise DesktopRunControlError(
                "controller_identity_required",
                "A verified controller identity is required",
            )
        if task.client_route_id and task.client_route_id != route_id:
            raise DesktopRunControlError(
                "task_controller_mismatch",
                "This task belongs to another paired client",
            )

    @staticmethod
    def _task_result(task: AgentTask, summary: str) -> dict:
        return {
            "task_id": task.task_id,
            "status": task.status,
            "summary": summary,
            "resume_count": task.resume_count,
            "execution_generation": task.execution_generation,
            "takeover": dict(task.takeover),
        }


_COORDINATOR = DesktopRunControlCoordinator()


def desktop_run_control() -> DesktopRunControlCoordinator:
    return _COORDINATOR
