from __future__ import annotations

import base64
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from secure_state import clear_cached_keys
from tool_permission_policy import (
    ALLOW_ALWAYS,
    ALLOW_ONCE,
    ALLOW_SESSION,
    DENY_ALWAYS,
    ToolPermissionPolicy,
)


class ToolPermissionPolicyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "tool-permissions.json"
        key = base64.urlsafe_b64encode(b"p" * 32).decode("ascii")
        self.environment = patch.dict(
            os.environ,
            {"GALAXYSSI_STATE_MASTER_KEY": key},
        )
        self.environment.start()
        self.addCleanup(self.environment.stop)
        clear_cached_keys()
        self.addCleanup(clear_cached_keys)
        self.values = {
            "client_route_id": "phone-route-1",
            "contact_id": "codex",
            "conversation_id": "conversation-1",
            "action_hash": "a" * 64,
        }

    def policy(self) -> ToolPermissionPolicy:
        return ToolPermissionPolicy(self.path, clock=lambda: 1_000.0)

    def test_allow_once_is_audited_by_caller_but_not_reused(self) -> None:
        policy = self.policy()
        decision = policy.record(choice=ALLOW_ONCE, **self.values)

        self.assertTrue(decision.approved)
        self.assertIsNone(policy.resolve(**self.values))
        self.assertNotIn(self.values["action_hash"], self.path.read_text("ascii"))

    def test_session_permission_is_bound_to_one_conversation(self) -> None:
        self.policy().record(choice=ALLOW_SESSION, **self.values)
        restored = self.policy()

        self.assertEqual(ALLOW_SESSION, restored.resolve(**self.values).choice)
        self.assertIsNone(
            restored.resolve(**dict(self.values, conversation_id="conversation-2"))
        )

    def test_permanent_permission_survives_conversation_change(self) -> None:
        self.policy().record(choice=ALLOW_ALWAYS, **self.values)

        decision = self.policy().resolve(
            **dict(self.values, conversation_id="conversation-2")
        )

        self.assertEqual(ALLOW_ALWAYS, decision.choice)
        self.assertTrue(decision.approved)

    def test_permanent_denial_replaces_allow_and_stays_encrypted(self) -> None:
        policy = self.policy()
        policy.record(choice=ALLOW_ALWAYS, **self.values)
        policy.record(choice=DENY_ALWAYS, **self.values)

        decision = self.policy().resolve(**self.values)
        raw = self.path.read_text("ascii")

        self.assertEqual(DENY_ALWAYS, decision.choice)
        self.assertFalse(decision.approved)
        self.assertNotIn(self.values["client_route_id"], raw)
        self.assertNotIn(self.values["action_hash"], raw)

    def test_invalid_action_hash_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            self.policy().record(
                choice=ALLOW_ALWAYS,
                **dict(self.values, action_hash="changed"),
            )


if __name__ == "__main__":
    unittest.main()
