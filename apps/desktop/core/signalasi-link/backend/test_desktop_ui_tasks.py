from __future__ import annotations

import time
from types import SimpleNamespace

import agent_task_manager as task_module
import main


class LoopbackRequest:
    client = SimpleNamespace(host="127.0.0.1")


def wait_for_terminal(manager, task_id: str, timeout: float = 3.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        task = manager.get(task_id)
        if task and task.status in task_module.TERMINAL_STATES:
            return task
        time.sleep(0.02)
    raise AssertionError("Desktop task did not reach a terminal state")


def test_desktop_task_runs_async_and_reuses_conversation_context(tmp_path, monkeypatch):
    monkeypatch.setattr(task_module, "TASKS_DB_PATH", tmp_path / "tasks.sqlite3")
    manager = task_module.AgentTaskManager()
    monkeypatch.setattr(main, "agent_task_manager", manager)
    monkeypatch.setenv("SIGNALASI_WORKSPACE_ROOT", str(tmp_path / "workspace"))
    monkeypatch.setattr(
        main,
        "connector_diagnostics",
        lambda quick=False: {
            "agents": [
                {"id": "codex", "status": "ready"},
                {"id": "hermes", "status": "needs_setup"},
            ]
        },
    )
    prompts: list[str] = []
    deliveries: list[dict] = []

    def fake_delivery(agent_id, prompt, **kwargs):
        prompts.append(prompt)
        deliveries.append(kwargs)
        return {"reply": f"reply-{len(prompts)}", "agent_id": agent_id}

    monkeypatch.setattr(main, "deliver_agent_sync", fake_delivery)
    source = tmp_path / "brief.txt"
    source.write_text("release brief", encoding="utf-8")

    first = main.api_start_desktop_task(
        main.DesktopTaskStartReq(
            prompt="Inspect the attached release brief",
            conversation_id="conversation-1",
            attachments=[str(source)],
        ),
        LoopbackRequest(),
    )
    first_task = wait_for_terminal(manager, first["task_id"])
    assert first_task.result == "reply-1"
    assert first_task.attachments == ["downloads/input/brief.txt"]
    assert "downloads/input/brief.txt" in prompts[0]
    assert deliveries[0]["execution_prompt"] == "Inspect the attached release brief"
    assert deliveries[0]["execution_policy"]["task_kind"] == "artifact"
    assert deliveries[0]["execution_policy"]["requires_artifact"] is False

    second = main.api_start_desktop_task(
        main.DesktopTaskStartReq(
            prompt="Continue with the release notes",
            conversation_id="conversation-1",
        ),
        LoopbackRequest(),
    )
    second_task = wait_for_terminal(manager, second["task_id"])
    assert second_task.result == "reply-2"
    assert "Inspect the attached release brief" in prompts[1]
    assert "reply-1" in prompts[1]
    assert deliveries[1]["execution_prompt"] == "Continue with the release notes"
    assert deliveries[1]["execution_policy"]["task_kind"] == "chat"

    listed = main.api_list_desktop_tasks(LoopbackRequest(), limit=10)["tasks"]
    assert [item["task_id"] for item in listed[:2]] == [second["task_id"], first["task_id"]]
    assert all(item["source_message_id"].startswith("desktop:") for item in listed)


def test_desktop_auto_uses_super_agent_and_explicit_agents_remain_direct(monkeypatch):
    monkeypatch.setattr(
        main,
        "connector_diagnostics",
        lambda quick=False: {
            "agents": [
                {"id": "codex", "status": "ready"},
                {"id": "hermes", "status": "ready"},
            ]
        },
    )
    assert main._desktop_agent_for("Research today's latest news") == "desktop"
    assert main._desktop_agent_for("Fix the project build") == "desktop"
    assert main._desktop_agent_for("Research today's latest news", "hermes") == "hermes"
    assert main._desktop_agent_for("Fix the project build", "codex") == "codex"


def test_desktop_task_forwards_plan_only_policy_without_requesting_artifacts(
    tmp_path,
    monkeypatch,
):
    monkeypatch.setattr(task_module, "TASKS_DB_PATH", tmp_path / "tasks.sqlite3")
    manager = task_module.AgentTaskManager()
    monkeypatch.setattr(main, "agent_task_manager", manager)
    monkeypatch.setenv("SIGNALASI_WORKSPACE_ROOT", str(tmp_path / "workspace"))
    monkeypatch.setattr(
        main,
        "connector_diagnostics",
        lambda quick=False: {"agents": [{"id": "codex", "status": "ready"}]},
    )
    deliveries: list[dict] = []

    def fake_delivery(agent_id, provider_prompt, **kwargs):
        deliveries.append({
            "agent_id": agent_id,
            "provider_prompt": provider_prompt,
            **kwargs,
        })
        return {"reply": "Plan ready", "agent_id": agent_id}

    monkeypatch.setattr(main, "deliver_agent_sync", fake_delivery)
    started = main.api_start_desktop_task(
        main.DesktopTaskStartReq(
            prompt="Build an Android app and return the APK",
            agent_id="codex",
            execution_mode="plan_only",
            conversation_id="plan-conversation",
        ),
        LoopbackRequest(),
    )
    completed = wait_for_terminal(manager, started["task_id"])

    assert completed.result == "Plan ready"
    assert deliveries[0]["execution_policy"]["execution_mode"] == "plan_only"
    assert deliveries[0]["execution_policy"]["requires_artifact"] is False
    assert "read-only plan" in deliveries[0]["provider_prompt"].lower()


def test_prompt_can_override_desktop_plan_default_with_auto_complete(
    tmp_path,
    monkeypatch,
):
    monkeypatch.setattr(task_module, "TASKS_DB_PATH", tmp_path / "tasks.sqlite3")
    manager = task_module.AgentTaskManager()
    monkeypatch.setattr(main, "agent_task_manager", manager)
    monkeypatch.setenv("SIGNALASI_WORKSPACE_ROOT", str(tmp_path / "workspace"))
    monkeypatch.setattr(
        main,
        "connector_diagnostics",
        lambda quick=False: {"agents": [{"id": "codex", "status": "ready"}]},
    )
    policies: list[dict] = []

    def fake_delivery(_agent_id, _prompt, **kwargs):
        policies.append(kwargs["execution_policy"])
        return {"reply": "Completed"}

    monkeypatch.setattr(main, "deliver_agent_sync", fake_delivery)
    started = main.api_start_desktop_task(
        main.DesktopTaskStartReq(
            prompt="Build the app and execute until complete",
            agent_id="codex",
            execution_mode="plan_only",
        ),
        LoopbackRequest(),
    )
    wait_for_terminal(manager, started["task_id"])

    assert policies[0]["execution_mode"] == "auto_complete"
    assert policies[0]["requires_artifact"] is True


def test_desktop_asks_once_then_uses_the_same_conversation_context(tmp_path, monkeypatch):
    monkeypatch.setattr(task_module, "TASKS_DB_PATH", tmp_path / "tasks.sqlite3")
    manager = task_module.AgentTaskManager()
    monkeypatch.setattr(main, "agent_task_manager", manager)
    monkeypatch.setenv("SIGNALASI_WORKSPACE_ROOT", str(tmp_path / "workspace"))
    monkeypatch.setattr(
        main,
        "connector_diagnostics",
        lambda quick=False: {"agents": [{"id": "codex", "status": "ready"}]},
    )
    deliveries: list[str] = []

    def fake_delivery(_agent_id, prompt, **_kwargs):
        deliveries.append(prompt)
        return {"reply": "continued", "agent_id": "codex"}

    monkeypatch.setattr(main, "deliver_agent_sync", fake_delivery)
    first = main.api_start_desktop_task(
        main.DesktopTaskStartReq(
            prompt="Control my computer",
            agent_id="codex",
            conversation_id="clarification-conversation",
            response_language="en-US",
        ),
        LoopbackRequest(),
    )
    clarified = wait_for_terminal(manager, first["task_id"])

    assert clarified.status == "completed"
    assert clarified.result == "What should I do on the device?"
    assert deliveries == []
    assert clarified.events[-1]["kind"] == "clarification"

    second = main.api_start_desktop_task(
        main.DesktopTaskStartReq(
            prompt="Continue",
            agent_id="codex",
            conversation_id="clarification-conversation",
        ),
        LoopbackRequest(),
    )
    continued = wait_for_terminal(manager, second["task_id"])

    assert continued.result == "continued"
    assert len(deliveries) == 1


def test_failed_attachment_task_retries_in_the_same_conversation(tmp_path, monkeypatch):
    monkeypatch.setattr(task_module, "TASKS_DB_PATH", tmp_path / "tasks.sqlite3")
    manager = task_module.AgentTaskManager()
    monkeypatch.setattr(main, "agent_task_manager", manager)
    monkeypatch.setenv("SIGNALASI_WORKSPACE_ROOT", str(tmp_path / "workspace"))
    monkeypatch.setattr(
        main,
        "connector_diagnostics",
        lambda quick=False: {"agents": [{"id": "codex", "status": "ready"}]},
    )
    prompts: list[str] = []

    def flaky_delivery(_agent_id, prompt, **_kwargs):
        prompts.append(prompt)
        if len(prompts) == 1:
            raise RuntimeError("temporary failure")
        return {"reply": "retry completed"}

    monkeypatch.setattr(main, "deliver_agent_sync", flaky_delivery)
    source = tmp_path / "report.csv"
    source.write_text("name,value\nSignalASI,1\n", encoding="utf-8")

    first = main.api_start_desktop_task(
        main.DesktopTaskStartReq(
            prompt="Summarize the attached report",
            agent_id="codex",
            conversation_id="conversation-retry",
            attachments=[str(source)],
        ),
        LoopbackRequest(),
    )
    failed = wait_for_terminal(manager, first["task_id"])
    assert failed.status == "failed"

    retried = main.api_retry_desktop_task(first["task_id"], LoopbackRequest())
    completed = wait_for_terminal(manager, retried["task_id"])
    assert completed.status == "completed"
    assert completed.result == "retry completed"
    assert completed.conversation_id == "conversation-retry"
    assert completed.retry_of == first["task_id"]
    assert completed.attempt == 2
    assert completed.attachments == ["downloads/input/report.csv"]
    assert prompts[1].count("Current user request:\nSummarize the attached report") == 1
