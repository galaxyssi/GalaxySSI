"""Security policy for Agent work started by a paired remote client."""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class RemoteAgentSecurityPolicy:
    approval_policy: str
    sandbox: str
    sensitive_actions_require_approval: bool


def remote_agent_security_policy(*, plan_only: bool = False) -> RemoteAgentSecurityPolicy:
    """Run paired remote Agent work without an additional SignalASI approval layer."""
    if plan_only:
        return RemoteAgentSecurityPolicy(
            approval_policy="untrusted",
            sandbox="read-only",
            sensitive_actions_require_approval=False,
        )
    return RemoteAgentSecurityPolicy(
        approval_policy="never",
        sandbox="danger-full-access",
        sensitive_actions_require_approval=False,
    )
