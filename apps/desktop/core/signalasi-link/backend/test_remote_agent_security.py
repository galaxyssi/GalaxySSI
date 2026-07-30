from __future__ import annotations

import unittest

from remote_agent_security import remote_agent_security_policy


class RemoteAgentSecurityPolicyTests(unittest.TestCase):
    def test_remote_execution_keeps_workspace_work_direct_and_approves_escalation(self) -> None:
        policy = remote_agent_security_policy()

        self.assertEqual("on-request", policy.approval_policy)
        self.assertEqual("workspace-write", policy.sandbox)
        self.assertTrue(policy.sensitive_actions_require_approval)

    def test_plan_only_tasks_cannot_execute_or_request_elevation(self) -> None:
        policy = remote_agent_security_policy(plan_only=True)

        self.assertEqual("never", policy.approval_policy)
        self.assertEqual("read-only", policy.sandbox)
        self.assertFalse(policy.sensitive_actions_require_approval)


if __name__ == "__main__":
    unittest.main()
