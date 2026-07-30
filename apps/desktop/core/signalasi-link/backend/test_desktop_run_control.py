from __future__ import annotations

import threading
import time

import pytest

from agent_task_manager import AgentTaskManager, TERMINAL_STATES
from desktop_run_control import (
    TASK_CONTINUE,
    TASK_PAUSE,
    TASK_TAKEOVER,
    DesktopRunControlCoordinator,
    DesktopRunControlError,
)


def _wait_for(manager: AgentTaskManager, task_id: str, status: str, timeout: float = 2.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        task = manager.get(task_id)
        if task is not None and task.status == status:
            return task
        time.sleep(0.01)
    current = manager.get(task_id)
    raise AssertionError(f"Task did not reach {status}; current={getattr(current, 'status', None)}")


def _manager(tmp_path) -> AgentTaskManager:
    return AgentTaskManager(
        state_path=tmp_path / "tasks.sqlite3",
        heartbeat_interval_seconds=0.01,
        stall_timeout_seconds=30,
    )


def test_pause_discards_late_result_and_continue_reuses_same_task(tmp_path):
    manager = _manager(tmp_path)
    first_release = threading.Event()
    second_release = threading.Event()

    task = manager.create(
        agent_id="codex",
        contact_id="codex",
        source_message_id="desktop:pause-test",
        prompt="Continue this project",
        runner=lambda _task: first_release.wait(1.0) and "stale result",
        on_event=lambda _event: None,
        task_id="pause-test",
        conversation_id="conversation-1",
    )
    _wait_for(manager, task.task_id, "running")

    paused = manager.pause(task.task_id, reason="User is taking control")
    assert paused is not None
    assert paused.status == "paused"
    assert paused.pause_requested is True
    first_release.set()
    time.sleep(0.05)
    assert manager.get(task.task_id).status == "paused"
    assert manager.get(task.task_id).result == ""

    continued = manager.continue_task(
        task.task_id,
        lambda _task: second_release.wait(1.0) and "verified resumed result",
        on_event=lambda _event: None,
        checkpoint={"active_window": {"title": "Editor"}},
    )
    assert continued is not None
    assert continued.task_id == task.task_id
    assert continued.resume_count == 1
    assert continued.execution_generation == 2
    _wait_for(manager, task.task_id, "running")
    second_release.set()
    completed = _wait_for(manager, task.task_id, "completed")
    assert completed.result == "verified resumed result"
    assert completed.execution_checkpoint["active_window"]["title"] == "Editor"


def test_late_paused_worker_cannot_clear_resumed_process_handle(tmp_path):
    class RunningProcess:
        pid = 123

        def poll(self):
            return None

    manager = _manager(tmp_path)
    first_release = threading.Event()
    resumed_started = threading.Event()
    resumed_release = threading.Event()
    resumed_process = RunningProcess()
    task = manager.create(
        agent_id="codex",
        contact_id="codex",
        source_message_id="desktop:process-generation",
        prompt="Resume without losing cancellation control",
        runner=lambda _task: first_release.wait(2.0) and "stale",
        on_event=lambda _event: None,
        task_id="process-generation",
    )
    _wait_for(manager, task.task_id, "running")
    manager.pause(task.task_id)

    def resumed_runner(_task):
        manager.register_process(task.task_id, resumed_process)
        resumed_started.set()
        resumed_release.wait(2.0)
        return "resumed"

    manager.continue_task(
        task.task_id,
        resumed_runner,
        on_event=lambda _event: None,
    )
    assert resumed_started.wait(1.0)
    first_release.set()
    time.sleep(0.05)
    assert manager.get(task.task_id).process is resumed_process
    resumed_release.set()
    assert _wait_for(manager, task.task_id, "completed").result == "resumed"


def test_paused_task_survives_desktop_restart_without_auto_resume(tmp_path):
    manager = _manager(tmp_path)
    release = threading.Event()
    task = manager.create(
        agent_id="hermes",
        contact_id="hermes",
        source_message_id="desktop:restart-pause",
        prompt="Research this topic",
        runner=lambda _task: release.wait(1.0) and "late",
        on_event=lambda _event: None,
        task_id="restart-pause",
    )
    _wait_for(manager, task.task_id, "running")
    manager.pause(task.task_id)
    release.set()

    restored = AgentTaskManager(
        state_path=tmp_path / "tasks.sqlite3",
        heartbeat_interval_seconds=0.01,
        stall_timeout_seconds=30,
    ).get(task.task_id)
    assert restored is not None
    assert restored.status == "paused"
    assert restored.pause_requested is True
    assert restored.recovery_state == "paused"
    assert restored.attempt == 1


def test_takeover_lease_returns_to_paused_and_never_auto_resumes(tmp_path):
    manager = _manager(tmp_path)
    task = manager.create_external(
        agent_id="codex",
        contact_id="codex",
        source_message_id="desktop:takeover",
        prompt="Edit the app",
        on_event=lambda _event: None,
        task_id="takeover-test",
    )
    manager.update(task.task_id, "running")
    manager.pause(task.task_id)
    taken = manager.begin_takeover(
        task.task_id,
        {
            "controller_id": "phone-1",
            "controller_name": "Phone",
            "controller_platform": "android",
            "client_route_id": "route-1",
        },
    )
    assert taken is not None
    assert taken.status == "takeover"
    lease_id = taken.takeover["lease_id"]

    manager._expire_takeover(task.task_id, lease_id)
    expired = manager.get(task.task_id)
    assert expired is not None
    assert expired.status == "paused"
    assert expired.takeover == {}
    assert expired.pause_reason == "Manual takeover lease expired"


def test_phone_cannot_take_over_another_phone_task(tmp_path):
    manager = _manager(tmp_path)
    task = manager.create_external(
        agent_id="codex",
        contact_id="codex",
        source_message_id="phone:message",
        prompt="Private phone task",
        on_event=lambda _event: None,
        task_id="private-task",
        client_route_id="route-owner",
        client_conversation_id="conversation-owner",
        client_turn_id="turn-owner",
    )
    manager.update(task.task_id, "running")
    coordinator = DesktopRunControlCoordinator()
    coordinator.configure(
        task_manager_provider=lambda: manager,
        interrupt_handler=lambda _task: {},
        checkpoint_provider=lambda _task: {"persisted": {}, "grounding": ""},
        runner_factory=lambda _task, _checkpoint: lambda _current: "done",
    )

    with pytest.raises(DesktopRunControlError) as error:
        coordinator.execute(
            TASK_PAUSE,
            {"task_id": task.task_id},
            {
                "controller_id": "phone-2",
                "controller_name": "Other phone",
                "controller_platform": "android",
                "client_route_id": "route-other",
            },
        )
    assert error.value.code == "task_controller_mismatch"
    assert manager.get(task.task_id).status == "running"


def test_coordinator_pause_takeover_continue_lifecycle(tmp_path):
    manager = _manager(tmp_path)
    interrupted: list[str] = []
    published_events: list[dict] = []
    published_results: list[dict] = []
    terminal_event_published = threading.Event()

    def record_event(event: dict) -> None:
        published_events.append(event)
        if event.get("status") in TERMINAL_STATES:
            terminal_event_published.set()

    task = manager.create_external(
        agent_id="codex",
        contact_id="codex",
        source_message_id="desktop:lifecycle",
        prompt="Build and verify",
        on_event=lambda _event: None,
        task_id="lifecycle",
    )
    manager.update(task.task_id, "running")
    coordinator = DesktopRunControlCoordinator()
    coordinator.configure(
        task_manager_provider=lambda: manager,
        interrupt_handler=lambda current: interrupted.append(current.task_id) or {"count": 1},
        checkpoint_provider=lambda _task: {
            "persisted": {"capture_id": "capture-1"},
            "grounding": "Active window: Editor",
        },
        runner_factory=lambda _task, _checkpoint: lambda _current: "continued result",
        event_handler=record_event,
        result_handler=published_results.append,
    )
    controller = {
        "controller_id": "desktop-ui",
        "controller_name": "Desktop user",
        "controller_platform": "desktop",
    }

    paused = coordinator.execute(TASK_PAUSE, {"task_id": task.task_id}, controller)
    assert paused["status"] == "paused"
    assert interrupted == [task.task_id]
    taken = coordinator.execute(
        TASK_TAKEOVER,
        {"task_id": task.task_id, "lease_seconds": 60},
        controller,
    )
    assert taken["status"] == "takeover"
    continued = coordinator.execute(TASK_CONTINUE, {"task_id": task.task_id}, controller)
    assert continued["status"] in {"queued", "running"}
    completed = _wait_for(manager, task.task_id, "completed")
    assert completed.result == "continued result"
    assert completed.execution_checkpoint["capture_id"] == "capture-1"
    assert completed.status in TERMINAL_STATES
    assert terminal_event_published.wait(timeout=1)
    published_statuses = [event["status"] for event in published_events]
    assert "paused" in published_statuses
    assert "takeover" in published_statuses
    assert "completed" in published_statuses
    assert [result["result"] for result in published_results] == ["continued result"]
