from __future__ import annotations

from agent_failure_recovery import (
    AgentFailureRecoveryAction,
    failure_diagnostic,
    recovery_choices,
)


def failed_task(**overrides):
    task = {
        "task_id": "task-1",
        "status": "failed",
        "agent_id": "codex",
        "delegate_agent_id": "codex",
        "error": "Agent is unavailable",
        "execution_policy": {"execution_mode": "auto_complete"},
        "client_route_id": "client-1",
        "client_conversation_id": "conversation-1",
        "client_turn_id": "turn-1",
    }
    task.update(overrides)
    return task


def test_agent_unavailable_recommends_an_alternative_agent():
    choices = recovery_choices(
        failed_task(),
        [
            {"id": "codex", "status": "unavailable"},
            {"id": "hermes", "status": "ready"},
            {"id": "claude", "status": "needs_setup"},
        ],
    )

    switch = next(
        choice
        for choice in choices
        if choice["action"] == AgentFailureRecoveryAction.SWITCH_AGENT.value
    )
    assert switch["enabled"] is True
    assert switch["recommended"] is True
    assert switch["candidate_agent_ids"] == ["hermes"]


def test_timeout_recommends_retry_and_plan_only_disables_degrade():
    choices = recovery_choices(
        failed_task(
            status="timed_out",
            error="Execution timed out",
            execution_policy={"execution_mode": "plan_only"},
        ),
        [],
    )

    retry = next(choice for choice in choices if choice["action"] == "retry")
    degrade = next(choice for choice in choices if choice["action"] == "degrade")
    assert retry["recommended"] is True
    assert degrade["enabled"] is False


def test_completed_tasks_do_not_offer_recovery():
    assert recovery_choices(failed_task(status="completed"), []) == []


def test_diagnostic_exposes_bounded_failure_and_strict_identity():
    diagnostic = failure_diagnostic(
        failed_task(error="network failed " * 200),
        [{"id": "codex", "status": "degraded"}, {"id": "hermes", "status": "ready"}],
    )

    assert diagnostic["failure_kind"] == "transient"
    assert len(diagnostic["error"]) <= 1_000
    assert diagnostic["identity"] == {
        "client_route_id": "client-1",
        "conversation_id": "conversation-1",
        "task_id": "task-1",
        "turn_id": "turn-1",
    }
    assert diagnostic["available_agent_ids"] == ["codex", "hermes"]
