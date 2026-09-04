"""Structured recovery choices for failed GalaxySSI Agent tasks."""
from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Any, Iterable, Mapping

from desktop_agent_loop import AgentLoopFailureKind, classify_failure


class AgentFailureRecoveryAction(str, Enum):
    RETRY = "retry"
    SWITCH_AGENT = "switch_agent"
    DEGRADE = "degrade"
    DIAGNOSTICS = "diagnostics"


@dataclass(frozen=True)
class AgentFailureRecoveryChoice:
    action: AgentFailureRecoveryAction
    label: str
    description: str
    enabled: bool = True
    recommended: bool = False
    reason: str = ""
    candidate_agent_ids: tuple[str, ...] = ()

    def public(self) -> dict[str, Any]:
        return {
            "action": self.action.value,
            "label": self.label,
            "description": self.description,
            "enabled": self.enabled,
            "recommended": self.recommended,
            "reason": self.reason,
            "candidate_agent_ids": list(self.candidate_agent_ids),
        }


FAILURE_STATUSES = {"failed", "timed_out", "cancelled", "not_found"}


def failure_kind_for_task(task: Mapping[str, Any]) -> AgentLoopFailureKind:
    status = str(task.get("status") or "").strip().lower()
    error = str(task.get("error") or "").strip()
    if status == "cancelled":
        return AgentLoopFailureKind.CANCELLED
    if status == "timed_out":
        return AgentLoopFailureKind.TIMEOUT
    return classify_failure(
        code=str(task.get("error_code") or ""),
        message=error,
        retryable=bool(task.get("retryable")),
        verification_failed="verif" in error.lower(),
    )


def recovery_choices(
    task: Mapping[str, Any],
    available_agents: Iterable[Mapping[str, Any]] | None = None,
) -> list[dict[str, Any]]:
    status = str(task.get("status") or "").strip().lower()
    if status not in FAILURE_STATUSES:
        return []

    current_agent = str(
        task.get("delegate_agent_id")
        or task.get("agent_id")
        or ""
    ).strip().lower()
    candidates = _candidate_agent_ids(available_agents, current_agent)
    discovery_pending = available_agents is None
    switch_enabled = discovery_pending or bool(candidates)
    kind = failure_kind_for_task(task)
    execution_mode = str(
        (task.get("execution_policy") or {}).get("execution_mode")
        if isinstance(task.get("execution_policy"), Mapping)
        else ""
    ).strip().lower()

    recommendation = _recommended_action(
        kind,
        switch_enabled=switch_enabled,
        can_degrade=execution_mode != "plan_only",
    )
    choices = (
        AgentFailureRecoveryChoice(
            AgentFailureRecoveryAction.RETRY,
            "Retry",
            "Repeat the task from its latest safe checkpoint.",
            enabled=status != "not_found",
            recommended=recommendation == AgentFailureRecoveryAction.RETRY,
            reason="" if status != "not_found" else "The original task is no longer available.",
        ),
        AgentFailureRecoveryChoice(
            AgentFailureRecoveryAction.SWITCH_AGENT,
            "Use another Agent",
            "Continue the same goal with another available Agent.",
            enabled=switch_enabled,
            recommended=recommendation == AgentFailureRecoveryAction.SWITCH_AGENT,
            reason="" if switch_enabled else "No alternative Agent is currently available.",
            candidate_agent_ids=candidates,
        ),
        AgentFailureRecoveryChoice(
            AgentFailureRecoveryAction.DEGRADE,
            "Safe fallback",
            "Return a read-only plan without performing side effects.",
            enabled=execution_mode != "plan_only" and status != "not_found",
            recommended=recommendation == AgentFailureRecoveryAction.DEGRADE,
            reason=(
                "The task is already using plan-only execution."
                if execution_mode == "plan_only"
                else ""
            ),
        ),
        AgentFailureRecoveryChoice(
            AgentFailureRecoveryAction.DIAGNOSTICS,
            "Diagnostics only",
            "Explain the failure and the next useful action without retrying.",
            recommended=recommendation == AgentFailureRecoveryAction.DIAGNOSTICS,
        ),
    )
    return [choice.public() for choice in choices]


def failure_diagnostic(
    task: Mapping[str, Any],
    available_agents: Iterable[Mapping[str, Any]] | None = None,
) -> dict[str, Any]:
    agents = tuple(available_agents or ())
    current_agent = str(
        task.get("delegate_agent_id")
        or task.get("agent_id")
        or ""
    ).strip()
    current_status = next(
        (
            str(agent.get("status") or "unknown")
            for agent in agents
            if str(agent.get("id") or "").strip().lower() == current_agent.lower()
        ),
        "unknown",
    )
    choices = recovery_choices(task, agents)
    recommended = next(
        (
            str(choice.get("action") or "")
            for choice in choices
            if choice.get("enabled") and choice.get("recommended")
        ),
        AgentFailureRecoveryAction.DIAGNOSTICS.value,
    )
    return {
        "task_id": str(task.get("task_id") or ""),
        "status": str(task.get("status") or ""),
        "failure_kind": failure_kind_for_task(task).value,
        "error": str(task.get("error") or "").strip()[:1_000],
        "agent_id": current_agent,
        "agent_status": current_status,
        "recommended_action": recommended,
        "retryable": any(
            choice.get("action") == AgentFailureRecoveryAction.RETRY.value
            and choice.get("enabled")
            for choice in choices
        ),
        "available_agent_ids": [
            str(agent.get("id") or "")
            for agent in agents
            if str(agent.get("status") or "").strip().lower()
            in {"ready", "available", "busy", "degraded"}
        ],
        "identity": {
            "client_route_id": str(task.get("client_route_id") or ""),
            "conversation_id": str(
                task.get("client_conversation_id")
                or task.get("conversation_id")
                or ""
            ),
            "task_id": str(task.get("task_id") or ""),
            "turn_id": str(task.get("client_turn_id") or task.get("turn_id") or ""),
        },
    }


def _candidate_agent_ids(
    available_agents: Iterable[Mapping[str, Any]] | None,
    current_agent: str,
) -> tuple[str, ...]:
    if available_agents is None:
        return ()
    candidates: list[str] = []
    for agent in available_agents:
        agent_id = str(agent.get("id") or "").strip().lower()
        status = str(agent.get("status") or "").strip().lower()
        if (
            not agent_id
            or agent_id == current_agent
            or agent_id in {"auto", "desktop", "this-desktop"}
            or status not in {"ready", "available", "busy", "degraded"}
        ):
            continue
        candidates.append(agent_id)
    return tuple(dict.fromkeys(candidates))


def _recommended_action(
    kind: AgentLoopFailureKind,
    *,
    switch_enabled: bool,
    can_degrade: bool,
) -> AgentFailureRecoveryAction:
    if kind in {AgentLoopFailureKind.TRANSIENT, AgentLoopFailureKind.TIMEOUT}:
        return AgentFailureRecoveryAction.RETRY
    if kind in {
        AgentLoopFailureKind.AGENT_UNAVAILABLE,
        AgentLoopFailureKind.TOOL_UNAVAILABLE,
    } and switch_enabled:
        return AgentFailureRecoveryAction.SWITCH_AGENT
    if kind in {
        AgentLoopFailureKind.PERMISSION_REQUIRED,
        AgentLoopFailureKind.VERIFICATION_FAILED,
    } and can_degrade:
        return AgentFailureRecoveryAction.DEGRADE
    return AgentFailureRecoveryAction.DIAGNOSTICS
