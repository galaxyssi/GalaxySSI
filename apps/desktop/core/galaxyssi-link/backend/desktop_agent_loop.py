"""Bounded state and failure policy for the GalaxySSI Desktop Agent loop."""
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Mapping


class AgentLoopPhase(str, Enum):
    PLAN = "plan"
    CONTEXT = "context"
    ACT = "act"
    OBSERVE = "observe"
    REPLAN = "replan"
    VERIFY = "verify"
    FINALIZE = "finalize"
    LEARN = "learn"


class AgentLoopFailureKind(str, Enum):
    TRANSIENT = "transient"
    TOOL_UNAVAILABLE = "tool_unavailable"
    PERMISSION_REQUIRED = "permission_required"
    INPUT_REQUIRED = "input_required"
    TIMEOUT = "timeout"
    VERIFICATION_FAILED = "verification_failed"
    AGENT_UNAVAILABLE = "agent_unavailable"
    CANCELLED = "cancelled"
    PERMANENT = "permanent"


@dataclass(frozen=True)
class AgentLoopBudget:
    max_iterations: int = 8
    max_tool_attempts: int = 2
    max_delegate_attempts: int = 3
    max_observations: int = 16

    def __post_init__(self) -> None:
        if self.max_iterations < 1:
            raise ValueError("Agent loop requires at least one iteration")
        if self.max_tool_attempts < 1 or self.max_delegate_attempts < 1:
            raise ValueError("Agent loop attempt budgets must be positive")
        if self.max_observations < 1:
            raise ValueError("Agent loop observation budget must be positive")


@dataclass(frozen=True)
class AgentLoopObservation:
    actor_id: str
    action_id: str
    status: str
    message: str = ""
    output: Mapping[str, Any] = field(default_factory=dict)
    error: Mapping[str, Any] = field(default_factory=dict)
    verification: Mapping[str, Any] = field(default_factory=dict)
    failure_kind: AgentLoopFailureKind | None = None
    retryable: bool = False

    @property
    def verified(self) -> bool:
        if self.status != "succeeded":
            return False
        status = str(self.verification.get("status") or "").strip().lower()
        return status in {"passed", "verified", "succeeded"}

    def evidence(self) -> dict[str, Any]:
        return {
            "actor_id": self.actor_id,
            "action_id": self.action_id,
            "status": self.status,
            "message": self.message,
            "output": dict(self.output),
            "error": dict(self.error),
            "verification": dict(self.verification),
            "failure_kind": self.failure_kind.value if self.failure_kind else "",
            "retryable": self.retryable,
        }


@dataclass
class AgentLoopTrace:
    budget: AgentLoopBudget
    iteration: int = 0
    observations: list[AgentLoopObservation] = field(default_factory=list)

    def next_iteration(self) -> int:
        if self.iteration >= self.budget.max_iterations:
            raise RuntimeError("Agent loop iteration budget exhausted")
        self.iteration += 1
        return self.iteration

    def record(self, observation: AgentLoopObservation) -> None:
        self.observations.append(observation)
        del self.observations[:-self.budget.max_observations]


def classify_failure(
    *,
    code: str = "",
    message: str = "",
    retryable: bool = False,
    verification_failed: bool = False,
) -> AgentLoopFailureKind:
    if verification_failed:
        return AgentLoopFailureKind.VERIFICATION_FAILED
    normalized = f"{code} {message}".strip().lower()
    if "cancel" in normalized or "interrupt" in normalized:
        return AgentLoopFailureKind.CANCELLED
    if "permission" in normalized or "approval" in normalized or "consent" in normalized:
        return AgentLoopFailureKind.PERMISSION_REQUIRED
    if "missing" in normalized and any(term in normalized for term in ("input", "argument", "parameter")):
        return AgentLoopFailureKind.INPUT_REQUIRED
    if "timeout" in normalized or "timed out" in normalized or "deadline" in normalized:
        return AgentLoopFailureKind.TIMEOUT
    if any(term in normalized for term in ("unavailable", "not installed", "not found", "unknown agent")):
        return AgentLoopFailureKind.TOOL_UNAVAILABLE
    if retryable or any(term in normalized for term in ("busy", "temporar", "network", "connection", "http 5")):
        return AgentLoopFailureKind.TRANSIENT
    return AgentLoopFailureKind.PERMANENT
