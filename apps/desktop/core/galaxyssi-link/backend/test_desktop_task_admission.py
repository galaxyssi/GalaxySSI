"""Admission validates selection, without probing unrelated Agent runtimes."""
from __future__ import annotations

import threading
import time
from types import SimpleNamespace

import pytest

import agent_gateway
from agent_task_manager import AgentTaskManager, TERMINAL_STATES
import desktop_mcp
import main


@pytest.fixture(autouse=True)
def forbid_admission_diagnostics(monkeypatch):
    def unexpected_probe(*_args, **_kwargs):
        raise AssertionError("Task admission must not inspect runtime health")
    monkeypatch.setattr(main, "connector_diagnostics", unexpected_probe)
    monkeypatch.setattr(agent_gateway, "agent_status", unexpected_probe)
    monkeypatch.setattr(agent_gateway, "_local_model_available", unexpected_probe)


@pytest.mark.parametrize("agent", ["codex", "hermes", "claude", "gemini", "openclaw", "local-llm"])
def test_explicit_selection_does_not_probe_other_providers(agent):
    assert main._desktop_agent_for("\u4f60\u597d", f" {agent.upper()} ") == agent


@pytest.mark.parametrize("agent", ["", "auto", "desktop", "this-desktop"])
def test_automatic_selection_remains_the_desktop_coordinator(agent):
    assert main._desktop_agent_for("\u5206\u6790\u4e00\u4e0b", agent) == "desktop"


@pytest.mark.parametrize("agent", ["missing-provider", "cloud-model"])
def test_unknown_or_hidden_agent_still_returns_not_found(agent):
    with pytest.raises(main.HTTPException) as failure:
        main._desktop_agent_for("\u4f60\u597d", agent)
    assert failure.value.status_code == 404


def test_newly_configured_and_removed_custom_agents_are_not_cached(monkeypatch):
    configured = []
    monkeypatch.setattr(agent_gateway, "custom_agent_configs", lambda: configured)
    with pytest.raises(main.HTTPException):
        main._desktop_agent_for("\u4f60\u597d", "custom-probe")
    configured.append({"id": "custom-probe", "name": "Test provider", "kind": "custom-cli"})
    assert main._desktop_agent_for("\u4f60\u597d", "custom-probe") == "custom-probe"
    configured.clear()
    with pytest.raises(main.HTTPException):
        main._desktop_agent_for("\u4f60\u597d", "custom-probe")


def test_mcp_selection_only_looks_up_the_requested_connection(monkeypatch):
    looked_up = []
    def lookup(connection_id):
        looked_up.append(connection_id)
        return object() if connection_id == "configured" else None
    monkeypatch.setattr(desktop_mcp, "desktop_mcp_registry", lambda: SimpleNamespace(get=lookup))
    assert main._desktop_agent_for("\u4f60\u597d", "mcp:configured") == "mcp:configured"
    with pytest.raises(main.HTTPException) as failure:
        main._desktop_agent_for("\u4f60\u597d", "mcp:missing")
    assert failure.value.status_code == 404
    assert looked_up == ["configured", "missing"]


def test_execution_failure_is_reported_after_task_is_accepted(tmp_path, monkeypatch):
    manager = AgentTaskManager(state_path=tmp_path / "tasks.sqlite3")
    monkeypatch.setattr(main, "agent_task_manager", manager)
    monkeypatch.setenv("GALAXYSSI_WORKSPACE_ROOT", str(tmp_path / "workspaces"))
    started = threading.Event()
    release = threading.Event()
    terminal_event = threading.Event()
    observed = []
    def on_event(row):
        observed.append(row["status"])
        if row["status"] in TERMINAL_STATES:
            terminal_event.set()
    subscription = manager.subscribe(on_event)
    def failing_provider(agent_id, _prompt, **_kwargs):
        assert agent_id == "codex"
        started.set()
        assert release.wait(5), "Test did not release the controlled provider"
        raise RuntimeError("Provider unavailable during execution")
    monkeypatch.setattr(main, "deliver_agent_sync", failing_provider)
    task_id = None
    try:
        row = main.api_start_desktop_task(
            main.DesktopTaskStartReq(prompt="\u4f60\u597d", agent_id="codex"),
            SimpleNamespace(client=SimpleNamespace(host="127.0.0.1")))
        task_id = row["task_id"]
        assert started.wait(3)
        assert row["status"] not in TERMINAL_STATES
        release.set()
        deadline = time.monotonic() + 3
        while manager.get(task_id).status not in TERMINAL_STATES and time.monotonic() < deadline:
            time.sleep(.01)
        task = manager.get(task_id)
        assert task.status == "failed"
        assert task.error == "Provider unavailable during execution"
        assert terminal_event.wait(3)
        assert "running" in observed
        assert observed[-1] == "failed"
    finally:
        release.set()
        if task_id and manager.get(task_id).status not in TERMINAL_STATES:
            manager.cancel(task_id)
        manager.unsubscribe(subscription)


def test_remote_caller_still_rejected_before_admission():
    with pytest.raises(main.HTTPException) as failure:
        main.api_start_desktop_task(main.DesktopTaskStartReq(prompt="\u4f60\u597d", agent_id="codex"),
                                    SimpleNamespace(client=SimpleNamespace(host="203.0.113.1")))
    assert failure.value.status_code == 403
