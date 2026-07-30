"""Security policy for Agent work started by a paired remote client."""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class RemoteAgentSecurityPolicy:
    approval_policy: str
    sandbox: str
    sensitive_actions_require_approval: bool


def remote_agent_security_policy(*, plan_only: bool = False) -> RemoteAgentSecurityPolicy:
    """Keep ordinary workspace work direct and require approval for escalation."""
    if plan_only:
        return RemoteAgentSecurityPolicy(
            approval_policy="never",
            sandbox="read-only",
            sensitive_actions_require_approval=False,
        )
    return RemoteAgentSecurityPolicy(
        approval_policy="on-request",
        sandbox="workspace-write",
        sensitive_actions_require_approval=True,
    )
