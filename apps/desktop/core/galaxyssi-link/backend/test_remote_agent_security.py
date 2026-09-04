from __future__ import annotations

import unittest

from remote_agent_security import remote_agent_security_policy


class RemoteAgentSecurityPolicyTests(unittest.TestCase):
    def test_remote_execution_uses_full_access_without_internal_approval(self) -> None:
        policy = remote_agent_security_policy()

        self.assertEqual("never", policy.approval_policy)
        self.assertEqual("danger-full-access", policy.sandbox)
        self.assertFalse(policy.sensitive_actions_require_approval)

    def test_plan_only_tasks_cannot_execute_or_request_elevation(self) -> None:
        policy = remote_agent_security_policy(plan_only=True)

        self.assertEqual("untrusted", policy.approval_policy)
        self.assertEqual("read-only", policy.sandbox)
        self.assertFalse(policy.sensitive_actions_require_approval)


if __name__ == "__main__":
    unittest.main()
